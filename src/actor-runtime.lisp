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
  session
  context
  thunk
  lock
  waitqueue
  done-p
  result
  error)

(defstruct actor-execution-context
  actor-id
  capability
  authority
  policy-id
  target
  operation
  request-id
  thread-id
  turn-id
  work-item-id
  workflow-record-id
  plan-id
  approval-required-p
  metadata)

(defstruct actor-runtime-state
  workers
  pool-size
  running-p
  queue
  lock
  waitqueue
  active-actors
  active-jobs
  execution-history
  submitted-job-count
  completed-job-count
  failed-job-count)

(defparameter *default-actor-thread-pool-size* 4)
(defparameter *actor-runtime-history-limit* 24)
(defparameter *current-actor-execution-job* nil)

(defun make-actor-pool-worker-id ()
  (format nil "actor-worker-~D-~D" (get-universal-time) (random 1000000)))

(defun make-actor-execution-job-id ()
  (format nil "actor-job-~D-~D" (get-universal-time) (random 1000000)))

(defun current-actor-execution-job ()
  *current-actor-execution-job*)

(defun current-actor-execution-job-id ()
  (let ((job (current-actor-execution-job)))
    (and job (actor-execution-job-id job))))

(defun actor-execution-context-summary (context)
  (when context
    (list :actor-id (actor-execution-context-actor-id context)
          :capability (actor-execution-context-capability context)
          :authority (actor-execution-context-authority context)
          :policy-id (actor-execution-context-policy-id context)
          :target (actor-execution-context-target context)
          :operation (actor-execution-context-operation context)
          :request-id (actor-execution-context-request-id context)
          :thread-id (actor-execution-context-thread-id context)
          :turn-id (actor-execution-context-turn-id context)
          :work-item-id (actor-execution-context-work-item-id context)
          :workflow-record-id (actor-execution-context-workflow-record-id context)
          :plan-id (actor-execution-context-plan-id context)
          :approval-required-p (actor-execution-context-approval-required-p context)
          :metadata (copy-tree (or (actor-execution-context-metadata context) '())))))

(defun merge-actor-execution-contexts (baseline override)
  (cond
    ((null baseline) override)
    ((null override) baseline)
    (t
     (make-actor-execution-context
      :actor-id (or (actor-execution-context-actor-id override)
                    (actor-execution-context-actor-id baseline))
      :capability (or (actor-execution-context-capability override)
                      (actor-execution-context-capability baseline))
      :authority (or (actor-execution-context-authority override)
                     (actor-execution-context-authority baseline))
      :policy-id (or (actor-execution-context-policy-id override)
                     (actor-execution-context-policy-id baseline))
      :target (or (actor-execution-context-target override)
                  (actor-execution-context-target baseline))
      :operation (or (actor-execution-context-operation override)
                     (actor-execution-context-operation baseline))
      :request-id (or (actor-execution-context-request-id override)
                      (actor-execution-context-request-id baseline))
      :thread-id (or (actor-execution-context-thread-id override)
                     (actor-execution-context-thread-id baseline))
      :turn-id (or (actor-execution-context-turn-id override)
                   (actor-execution-context-turn-id baseline))
      :work-item-id (or (actor-execution-context-work-item-id override)
                        (actor-execution-context-work-item-id baseline))
      :workflow-record-id (or (actor-execution-context-workflow-record-id override)
                              (actor-execution-context-workflow-record-id baseline))
      :plan-id (or (actor-execution-context-plan-id override)
                   (actor-execution-context-plan-id baseline))
      :approval-required-p (or (actor-execution-context-approval-required-p override)
                               (actor-execution-context-approval-required-p baseline))
      :metadata (append (copy-tree (or (actor-execution-context-metadata override) '()))
                        (copy-tree (or (actor-execution-context-metadata baseline) '())))))))

(defun update-current-actor-execution-context (context &key replace-p)
  (let ((job *current-actor-execution-job*))
    (when job
      (setf (actor-execution-job-context job)
            (if replace-p
                context
                (merge-actor-execution-contexts (actor-execution-job-context job)
                                                context)))
      (actor-execution-job-context job))))

(defun append-actor-execution-lifecycle-event (session event-kind job &key worker status error)
  (let* ((context-summary (actor-execution-context-summary
                           (actor-execution-job-context job)))
         (worker-id (and worker (actor-pool-worker-state-id worker))))
    (append-session-event
     session
     event-kind
     (append (list :job-id (actor-execution-job-id job)
                   :actor-id (actor-execution-job-actor-id job)
                   :worker-id worker-id
                   :status status
                   :error error
                   :context context-summary)
             (when context-summary
               (list :capability (getf context-summary :capability)
                     :authority (getf context-summary :authority)
                     :policy-id (getf context-summary :policy-id)
                     :target (getf context-summary :target)
                     :operation (getf context-summary :operation)
                     :request-id (getf context-summary :request-id)
                     :plan-id (getf context-summary :plan-id)
                     :workflow-record-id (getf context-summary :workflow-record-id)
                     :approval-required-p (getf context-summary :approval-required-p))))
     :family :assistant
     :entity-id (or (and context-summary (getf context-summary :request-id))
                    (actor-execution-job-id job))
     :thread-id (and context-summary (getf context-summary :thread-id))
     :turn-id (and context-summary (getf context-summary :turn-id))
     :work-item-id (and context-summary (getf context-summary :work-item-id))
     :agent-id (actor-execution-job-actor-id job)
     :metadata (append (when worker-id
                         (list :worker-id worker-id))
                       (when context-summary
                         (list :plan-id (getf context-summary :plan-id)
                               :workflow-record-id
                               (getf context-summary :workflow-record-id)))))))

(defun actor-execution-job-summary (job &key status worker-id error)
  (let ((context-summary (actor-execution-context-summary
                          (actor-execution-job-context job))))
    (append (list :job-id (actor-execution-job-id job)
                  :actor-id (actor-execution-job-actor-id job)
                  :status status
                  :worker-id worker-id
                  :error error)
            (when context-summary
              (list :context context-summary
                    :capability (getf context-summary :capability)
                    :authority (getf context-summary :authority)
                    :policy-id (getf context-summary :policy-id)
                    :target (getf context-summary :target)
                    :operation (getf context-summary :operation)
                    :request-id (getf context-summary :request-id)
                    :thread-id (getf context-summary :thread-id)
                    :turn-id (getf context-summary :turn-id)
                    :work-item-id (getf context-summary :work-item-id)
                    :workflow-record-id (getf context-summary :workflow-record-id)
                    :plan-id (getf context-summary :plan-id)
                    :approval-required-p
                    (getf context-summary :approval-required-p))))))

(defun actor-runtime-worker-summary (worker)
  (list :id (actor-pool-worker-state-id worker)
        :running-p (actor-pool-worker-state-running-p worker)
        :busy-p (actor-pool-worker-state-busy-p worker)
        :phase (actor-pool-worker-state-phase worker)
        :leased-actor-id (actor-pool-worker-state-leased-actor-id worker)
        :current-job-id (actor-pool-worker-state-current-job-id worker)
        :completed-job-id (actor-pool-worker-state-completed-job-id worker)
        :last-error (actor-pool-worker-state-last-error worker)
        :session-id (actor-pool-worker-state-session-id worker)))

(defun actor-runtime-state-summary-from-runtime (runtime)
  (let* ((workers (and runtime (actor-runtime-state-workers runtime)))
         (busy-workers (count-if #'actor-pool-worker-state-busy-p workers))
         (idle-workers (max 0 (- (length workers) busy-workers)))
         (queue-depth (and runtime (length (actor-runtime-state-queue runtime))))
         (queued-jobs
           (and runtime
                (mapcar (lambda (job)
                          (actor-execution-job-summary job :status :queued))
                        (actor-runtime-state-queue runtime))))
         (active-jobs
           (and runtime
                (loop for job being the hash-values of (actor-runtime-state-active-jobs runtime)
                      collect (actor-execution-job-summary job :status :executing))))
         (recent-executions
           (and runtime
                (copy-tree (or (actor-runtime-state-execution-history runtime) '())))))
    (list :running-p (and runtime (actor-runtime-state-running-p runtime))
          :pool-size (or (and runtime (actor-runtime-state-pool-size runtime)) 0)
          :worker-count (length (or workers '()))
          :busy-worker-count busy-workers
          :idle-worker-count idle-workers
          :queue-depth (or queue-depth 0)
          :queued-jobs queued-jobs
          :active-jobs active-jobs
          :recent-executions recent-executions
          :active-actor-count (if runtime
                                  (hash-table-count (actor-runtime-state-active-actors runtime))
                                  0)
          :submitted-job-count (or (and runtime (actor-runtime-state-submitted-job-count runtime)) 0)
          :completed-job-count (or (and runtime (actor-runtime-state-completed-job-count runtime)) 0)
          :failed-job-count (or (and runtime (actor-runtime-state-failed-job-count runtime)) 0)
          :workers (mapcar #'actor-runtime-worker-summary
                           (or workers '())))))

(defun serializable-actor-runtime-state (session-or-runtime)
  (let* ((runtime (typecase session-or-runtime
                    (agent-session
                     (agent-session-actor-runtime-state session-or-runtime))
                    (actor-runtime-state session-or-runtime)
                    (t nil)))
         (summary (and runtime
                       (actor-runtime-state-summary-from-runtime runtime))))
    (when summary
      (list :pool-size (or (getf summary :pool-size) 0)
            :submitted-job-count (or (getf summary :submitted-job-count) 0)
            :completed-job-count (or (getf summary :completed-job-count) 0)
            :failed-job-count (or (getf summary :failed-job-count) 0)
            :recent-executions (copy-tree (or (getf summary :recent-executions) '()))
            :saved-running-p (and (getf summary :running-p) t)))))

(defun rehydrate-actor-runtime-state (snapshot)
  (when snapshot
    (let ((runtime (make-actor-runtime-state-instance
                    :pool-size (or (getf snapshot :pool-size)
                                   *default-actor-thread-pool-size*))))
      (setf (actor-runtime-state-running-p runtime) nil
            (actor-runtime-state-execution-history runtime)
            (copy-tree (or (getf snapshot :recent-executions) '()))
            (actor-runtime-state-submitted-job-count runtime)
            (or (getf snapshot :submitted-job-count) 0)
            (actor-runtime-state-completed-job-count runtime)
            (or (getf snapshot :completed-job-count) 0)
            (actor-runtime-state-failed-job-count runtime)
            (or (getf snapshot :failed-job-count) 0))
      runtime)))

(defun record-actor-runtime-history (runtime job &key status worker-id error)
  (let ((entry (actor-execution-job-summary job
                                            :status status
                                            :worker-id worker-id
                                            :error error)))
    (sb-thread:with-mutex ((actor-runtime-state-lock runtime))
      (setf (actor-runtime-state-execution-history runtime)
            (subseq (cons entry (or (actor-runtime-state-execution-history runtime) '()))
                    0
                    (min *actor-runtime-history-limit*
                         (1+ (length (or (actor-runtime-state-execution-history runtime)
                                         '())))))))))

(defun make-actor-runtime-state-instance (&key (pool-size *default-actor-thread-pool-size*))
  (make-actor-runtime-state
   :workers '()
   :pool-size pool-size
   :running-p nil
   :queue '()
   :lock (sb-thread:make-mutex :name "sbcl-agent-actor-thread-pool")
   :waitqueue (sb-thread:make-waitqueue)
   :active-actors (make-hash-table :test #'equal)
   :active-jobs (make-hash-table :test #'equal)
   :execution-history '()
   :submitted-job-count 0
   :completed-job-count 0
   :failed-job-count 0))

(defun actor-runtime-state-summary (session)
  (actor-runtime-state-summary-from-runtime
   (agent-session-actor-runtime-state session)))

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
                         (gethash (actor-execution-job-id job)
                                  (actor-runtime-state-active-jobs runtime)) job
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
          (remhash actor-id active-actors))
      (remhash (actor-execution-job-id job)
               (actor-runtime-state-active-jobs runtime)))
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
  (append-actor-execution-lifecycle-event
   (actor-execution-job-session job)
   (if error :actor-execution-failed :actor-execution-completed)
   job
   :worker worker
   :status (if error :failed :completed)
   :error error)
  (record-actor-runtime-history runtime
                                job
                                :status (if error :failed :completed)
                                :worker-id (actor-pool-worker-state-id worker)
                                :error error)
  (signal-actor-execution-job-complete job result error))

(defun actor-thread-pool-worker-loop (runtime worker)
  (handler-case
      (loop
        for job = (actor-runtime-lease-next-job runtime worker)
        while job
        do (handler-case
               (progn
                 (setf (actor-pool-worker-state-phase worker) :executing)
                 (append-actor-execution-lifecycle-event
                  (actor-execution-job-session job)
                  :actor-execution-started
                  job
                  :worker worker
                  :status :executing)
                 (record-actor-runtime-history runtime
                                               job
                                               :status :executing
                                               :worker-id (actor-pool-worker-state-id worker))
                 (let ((*current-actor-execution-job* job))
                   (let ((result (funcall (actor-execution-job-thunk job))))
                     (actor-runtime-release-job runtime worker job :result result))))
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

(defun submit-actor-execution-job (session actor-id thunk &key (max-concurrency 1) context)
  (let* ((runtime (ensure-actor-thread-pool session))
         (job (make-actor-execution-job
               :id (make-actor-execution-job-id)
               :actor-id actor-id
               :max-concurrency (max 1 max-concurrency)
               :session session
               :context context
               :thunk thunk
               :lock (sb-thread:make-mutex :name "sbcl-agent-actor-job")
               :waitqueue (sb-thread:make-waitqueue)
               :done-p nil
               :result nil
               :error nil)))
    (append-actor-execution-lifecycle-event session
                                            :actor-execution-submitted
                                            job
                                            :status :queued)
    (record-actor-runtime-history runtime job :status :queued)
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

(defun call-with-actor-worker-for-request (session request thunk &key context)
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
                                    :max-concurrency max-concurrency
                                    :context (or context
                                                 (make-actor-execution-context
                                                  :actor-id (actor-address-id actor-address)
                                                  :capability (desktop-task-request-capability request)
                                                  :target (desktop-task-request-target request)
                                                  :operation (desktop-task-request-operation request)
                                                  :request-id (desktop-task-request-id request))))
        (funcall thunk))))
