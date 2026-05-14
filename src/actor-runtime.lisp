(in-package #:sbcl-agent)

(defstruct actor-pool-worker-state
  id
  thread
  running-p
  busy-p
  phase
  leased-actor-id
  current-job-id
  completed-job-id
  last-error
  session-id)

(defstruct actor-execution-job
  id
  actor-id
  max-concurrency
  thunk
  lock
  waitqueue
  done-p
  result
  error)

(defstruct actor-runtime-state
  workers
  pool-size
  running-p
  queue
  lock
  waitqueue
  active-actors
  submitted-job-count
  completed-job-count
  failed-job-count)

(defparameter *default-actor-thread-pool-size* 4)

(defun make-actor-pool-worker-id ()
  (format nil "actor-worker-~D-~D" (get-universal-time) (random 1000000)))

(defun make-actor-execution-job-id ()
  (format nil "actor-job-~D-~D" (get-universal-time) (random 1000000)))

(defun make-actor-runtime-state-instance (&key (pool-size *default-actor-thread-pool-size*))
  (make-actor-runtime-state
   :workers '()
   :pool-size pool-size
   :running-p nil
   :queue '()
   :lock (sb-thread:make-mutex :name "sbcl-agent-actor-thread-pool")
   :waitqueue (sb-thread:make-waitqueue)
   :active-actors (make-hash-table :test #'equal)
   :submitted-job-count 0
   :completed-job-count 0
   :failed-job-count 0))

(defun actor-runtime-state-summary (session)
  (let* ((runtime (agent-session-actor-runtime-state session))
         (workers (and runtime (actor-runtime-state-workers runtime)))
         (busy-workers (count-if #'actor-pool-worker-state-busy-p workers))
         (idle-workers (max 0 (- (length workers) busy-workers)))
         (queue-depth (and runtime (length (actor-runtime-state-queue runtime)))))
    (list :running-p (and runtime (actor-runtime-state-running-p runtime))
          :pool-size (or (and runtime (actor-runtime-state-pool-size runtime)) 0)
          :worker-count (length (or workers '()))
          :busy-worker-count busy-workers
          :idle-worker-count idle-workers
          :queue-depth (or queue-depth 0)
          :active-actor-count (if runtime
                                  (hash-table-count (actor-runtime-state-active-actors runtime))
                                  0)
          :submitted-job-count (or (and runtime (actor-runtime-state-submitted-job-count runtime)) 0)
          :completed-job-count (or (and runtime (actor-runtime-state-completed-job-count runtime)) 0)
          :failed-job-count (or (and runtime (actor-runtime-state-failed-job-count runtime)) 0)
          :workers (mapcar (lambda (worker)
                             (list :id (actor-pool-worker-state-id worker)
                                   :running-p (actor-pool-worker-state-running-p worker)
                                   :busy-p (actor-pool-worker-state-busy-p worker)
                                   :phase (actor-pool-worker-state-phase worker)
                                   :leased-actor-id (actor-pool-worker-state-leased-actor-id worker)
                                   :current-job-id (actor-pool-worker-state-current-job-id worker)
                                   :completed-job-id (actor-pool-worker-state-completed-job-id worker)
                                   :last-error (actor-pool-worker-state-last-error worker)
                                   :session-id (actor-pool-worker-state-session-id worker)))
                           (or workers '())))))

(defun actor-runtime-pop-runnable-job (runtime worker)
  (let ((queue (actor-runtime-state-queue runtime))
        (active-actors (actor-runtime-state-active-actors runtime))
        (previous nil)
        (cursor nil))
    (setf cursor queue)
    (loop while cursor
          for job = (car cursor)
          for actor-id = (actor-execution-job-actor-id job)
          for max-concurrency = (max 1 (actor-execution-job-max-concurrency job))
          for active-count = (gethash actor-id active-actors 0)
          do (if (< active-count max-concurrency)
                 (progn
                   (if previous
                       (setf (cdr previous) (cdr cursor))
                       (setf (actor-runtime-state-queue runtime) (cdr cursor)))
                   (setf (gethash actor-id active-actors) (1+ active-count)
                         (actor-pool-worker-state-busy-p worker) t
                         (actor-pool-worker-state-phase worker) :leased
                         (actor-pool-worker-state-leased-actor-id worker) actor-id
                         (actor-pool-worker-state-current-job-id worker) (actor-execution-job-id job))
                   (return-from actor-runtime-pop-runnable-job job))
                 (progn
                   (setf previous cursor
                         cursor (cdr cursor)))))
    nil))

(defun actor-runtime-lease-next-job (runtime worker)
  (sb-thread:with-mutex ((actor-runtime-state-lock runtime))
    (loop
      for job = (actor-runtime-pop-runnable-job runtime worker)
      do (cond
           (job
            (return-from actor-runtime-lease-next-job job))
           ((not (actor-runtime-state-running-p runtime))
            (return-from actor-runtime-lease-next-job nil))
           (t
            (setf (actor-pool-worker-state-phase worker) :waiting)
            (sb-thread:condition-wait (actor-runtime-state-waitqueue runtime)
                                      (actor-runtime-state-lock runtime)))))))

(defun signal-actor-execution-job-complete (job result error)
  (sb-thread:with-mutex ((actor-execution-job-lock job))
    (setf (actor-execution-job-result job) result
          (actor-execution-job-error job) error
          (actor-execution-job-done-p job) t)
    (sb-thread:condition-broadcast (actor-execution-job-waitqueue job))))

(defun actor-runtime-release-job (runtime worker job &key result error)
  (sb-thread:with-mutex ((actor-runtime-state-lock runtime))
    (let* ((actor-id (actor-execution-job-actor-id job))
           (active-actors (actor-runtime-state-active-actors runtime))
           (active-count (max 0 (1- (gethash actor-id active-actors 1)))))
      (if (> active-count 0)
          (setf (gethash actor-id active-actors) active-count)
          (remhash actor-id active-actors)))
    (setf (actor-pool-worker-state-busy-p worker) nil
          (actor-pool-worker-state-phase worker) (if error :failed :idle)
          (actor-pool-worker-state-leased-actor-id worker) nil
          (actor-pool-worker-state-completed-job-id worker) (actor-execution-job-id job)
          (actor-pool-worker-state-current-job-id worker) nil
          (actor-pool-worker-state-last-error worker) error)
    (if error
        (incf (actor-runtime-state-failed-job-count runtime))
        (incf (actor-runtime-state-completed-job-count runtime)))
    (sb-thread:condition-broadcast (actor-runtime-state-waitqueue runtime)))
  (signal-actor-execution-job-complete job result error))

(defun actor-thread-pool-worker-loop (runtime worker)
  (handler-case
      (loop
        for job = (actor-runtime-lease-next-job runtime worker)
        while job
        do (handler-case
               (progn
                 (setf (actor-pool-worker-state-phase worker) :executing)
                 (let ((result (funcall (actor-execution-job-thunk job))))
                   (actor-runtime-release-job runtime worker job :result result)))
             (error (condition)
               (actor-runtime-release-job runtime worker job
                                          :error (princ-to-string condition)))))
    (error (condition)
      (setf (actor-pool-worker-state-phase worker) :crashed
            (actor-pool-worker-state-last-error worker) (princ-to-string condition))))
  (setf (actor-pool-worker-state-running-p worker) nil
         (actor-pool-worker-state-busy-p worker) nil
        (actor-pool-worker-state-phase worker) :stopped
        (actor-pool-worker-state-leased-actor-id worker) nil
        (actor-pool-worker-state-current-job-id worker) nil))

(defun start-actor-thread-pool (session &key (pool-size *default-actor-thread-pool-size*))
  (let ((runtime (or (agent-session-actor-runtime-state session)
                     (setf (agent-session-actor-runtime-state session)
                           (make-actor-runtime-state-instance :pool-size pool-size)))))
    (unless (actor-runtime-state-running-p runtime)
      (setf (actor-runtime-state-pool-size runtime) pool-size
            (actor-runtime-state-running-p runtime) t)
      (setf (actor-runtime-state-workers runtime)
            (loop repeat pool-size
                  collect (let ((worker (make-actor-pool-worker-state
                                         :id (make-actor-pool-worker-id)
                                         :thread nil
                                         :running-p t
                                         :busy-p nil
                                         :phase :starting
                                         :leased-actor-id nil
                                         :current-job-id nil
                                         :completed-job-id nil
                                         :last-error nil
                                         :session-id (agent-session-id session))))
                            (setf (actor-pool-worker-state-thread worker)
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (actor-thread-pool-worker-loop runtime worker))
                                   :name (actor-pool-worker-state-id worker)))
                            worker))))
    runtime))

(defun ensure-actor-thread-pool (session &key (pool-size *default-actor-thread-pool-size*))
  (let ((runtime (agent-session-actor-runtime-state session)))
    (if (and runtime (actor-runtime-state-running-p runtime))
        runtime
        (start-actor-thread-pool session :pool-size pool-size))))

(defun stop-actor-thread-pool (session)
  (let ((runtime (agent-session-actor-runtime-state session)))
    (when runtime
      (sb-thread:with-mutex ((actor-runtime-state-lock runtime))
        (setf (actor-runtime-state-running-p runtime) nil)
        (sb-thread:condition-broadcast (actor-runtime-state-waitqueue runtime)))
      (dolist (worker (actor-runtime-state-workers runtime))
        (let ((thread (actor-pool-worker-state-thread worker)))
          (when thread
            (sb-thread:join-thread thread)
            (setf (actor-pool-worker-state-thread worker) nil
                  (actor-pool-worker-state-running-p worker) nil
                  (actor-pool-worker-state-busy-p worker) nil
                  (actor-pool-worker-state-leased-actor-id worker) nil
                  (actor-pool-worker-state-current-job-id worker) nil))))
      runtime)))

(defun await-actor-execution-job (job)
  (sb-thread:with-mutex ((actor-execution-job-lock job))
    (loop until (actor-execution-job-done-p job)
          do (sb-thread:condition-wait (actor-execution-job-waitqueue job)
                                       (actor-execution-job-lock job))))
  (if (actor-execution-job-error job)
      (error "~A" (actor-execution-job-error job))
      (actor-execution-job-result job)))

(defun submit-actor-execution-job (session actor-id thunk &key (max-concurrency 1))
  (let* ((runtime (ensure-actor-thread-pool session))
         (job (make-actor-execution-job
               :id (make-actor-execution-job-id)
               :actor-id actor-id
               :max-concurrency (max 1 max-concurrency)
               :thunk thunk
               :lock (sb-thread:make-mutex :name "sbcl-agent-actor-job")
               :waitqueue (sb-thread:make-waitqueue)
               :done-p nil
               :result nil
               :error nil)))
    (sb-thread:with-mutex ((actor-runtime-state-lock runtime))
      (setf (actor-runtime-state-queue runtime)
            (append (actor-runtime-state-queue runtime) (list job)))
      (incf (actor-runtime-state-submitted-job-count runtime))
      (sb-thread:condition-broadcast (actor-runtime-state-waitqueue runtime)))
    (await-actor-execution-job job)))

(defun actor-address-for-request-execution (session request)
  (or (and (desktop-task-request-actor-message request)
           (actor-message-receiver (desktop-task-request-actor-message request)))
      (make-standard-actor-address (desktop-task-request-target request)
                                   :scope (agent-session-id session))))

(defun call-with-actor-worker-for-request (session request thunk)
  (let* ((actor-address (actor-address-for-request-execution session request))
         (definition (and (fboundp 'find-actor-definition-for-address)
                          (find-actor-definition-for-address session actor-address)))
         (execution-policy (and definition
                                (actor-definition-execution-policy definition)))
         (execution-model (and execution-policy
                               (actor-execution-policy-model execution-policy)))
         (max-concurrency (or (and execution-policy
                                   (actor-execution-policy-max-concurrency execution-policy))
                              1)))
    (if (eq execution-model :thread-pool-worker)
        (submit-actor-execution-job session
                                    (actor-address-id actor-address)
                                    thunk
                                    :max-concurrency max-concurrency)
        (funcall thunk))))
