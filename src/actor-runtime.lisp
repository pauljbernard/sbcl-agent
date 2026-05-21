(in-package #:sbcl-agent)

(declaim (special *current-session* *current-environment*))

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
  (future (make-concurrency-core-future-instance)))

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
  gate
  active-actors
  active-jobs
  execution-history
  submitted-job-count
  completed-job-count
  failed-job-count)

(defparameter *default-actor-thread-pool-size* 4)
(defparameter *actor-runtime-history-limit* 24)
(defparameter *current-actor-execution-job* nil)

(defun actor-runtime-lifecycle-lock-key (session)
  (list :actor-runtime-lifecycle (agent-session-id session)))

(defmacro with-actor-runtime-lifecycle-lock ((session) &body body)
  `(sb-thread:with-mutex ((ensure-concurrency-core-lock
                           (actor-runtime-lifecycle-lock-key ,session)))
     ,@body))

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
         (queue-items (and runtime
                           (concurrency-core-queue-items
                            (actor-runtime-state-queue runtime))))
         (queue-depth (length (or queue-items '())))
         (queued-jobs
           (and runtime
                (mapcar (lambda (job)
                          (actor-execution-job-summary job :status :queued))
                        queue-items)))
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
    (record-actor-runtime-history-entry runtime entry)))

(defun record-actor-runtime-history-entry (runtime entry)
  (when runtime
    (with-concurrency-core-gate ((actor-runtime-state-gate runtime))
      (setf (actor-runtime-state-execution-history runtime)
            (subseq (cons (copy-tree entry)
                          (or (actor-runtime-state-execution-history runtime) '()))
                    0
                    (min *actor-runtime-history-limit*
                         (1+ (length (or (actor-runtime-state-execution-history runtime)
                                         '())))))))))

(defun ensure-session-actor-runtime-state (session)
  (or (agent-session-actor-runtime-state session)
      (setf (agent-session-actor-runtime-state session)
            (make-actor-runtime-state-instance))))

(defun record-actor-supervision-runtime-history (session entry action
                                                 &key incident recovery-summary automatic-p)
  (let ((runtime (ensure-session-actor-runtime-state session)))
    (record-actor-runtime-history-entry
     runtime
     (list :entry-kind :supervision
           :status :supervision-applied
           :recorded-at (get-universal-time)
           :automatic-supervision-p (and automatic-p t)
           :action action
           :incident-id (and incident (incident-id incident))
           :incident-status (and incident (incident-status incident))
           :escalation-target (and incident
                                   (getf (incident-metadata incident) :escalation-target))
           :actor-id (and entry
                          (actor-address-id (actor-mailbox-entry-owner entry)))
           :actor-role (and entry
                            (actor-address-role (actor-mailbox-entry-owner entry)))
           :mailbox (and entry (actor-mailbox-entry-mailbox entry))
           :mailbox-entry-id (and entry (actor-mailbox-entry-id entry))
           :request-id (and entry (actor-mailbox-entry-request-id entry))
           :actor-message-id (and entry (actor-mailbox-entry-actor-message-id entry))
           :pending-action-id (and entry (actor-mailbox-entry-pending-action-id entry))
           :delivery-status (and entry (actor-mailbox-entry-delivery-status entry))
           :metadata (copy-tree (or (and entry (actor-mailbox-entry-metadata entry)) '()))
           :recovery (copy-tree recovery-summary)))))

(defun make-actor-runtime-state-instance (&key (pool-size *default-actor-thread-pool-size*))
  (make-actor-runtime-state
   :workers '()
   :pool-size pool-size
   :running-p nil
   :queue (make-concurrency-core-queue-instance)
   :gate (make-concurrency-core-gate-instance
          :name "sbcl-agent-actor-runtime-gate")
   :active-actors (make-hash-table :test #'equal)
   :active-jobs (make-hash-table :test #'equal)
   :execution-history '()
   :submitted-job-count 0
   :completed-job-count 0
   :failed-job-count 0))

(defun actor-runtime-state-summary (session)
  (actor-runtime-state-summary-from-runtime
   (agent-session-actor-runtime-state session)))

(defun actor-runtime-job-runnable-p (runtime candidate)
  (let* ((actor-id (actor-execution-job-actor-id candidate))
         (max-concurrency (max 1 (actor-execution-job-max-concurrency candidate)))
         (active-count (gethash actor-id (actor-runtime-state-active-actors runtime) 0)))
    (< active-count max-concurrency)))

(defun lease-actor-runtime-job (runtime worker job)
  (let* ((actor-id (actor-execution-job-actor-id job))
         (active-actors (actor-runtime-state-active-actors runtime)))
    (setf (gethash actor-id active-actors) (1+ (gethash actor-id active-actors 0))
          (gethash (actor-execution-job-id job)
                   (actor-runtime-state-active-jobs runtime)) job
          (actor-pool-worker-state-busy-p worker) t
          (actor-pool-worker-state-phase worker) :leased
          (actor-pool-worker-state-leased-actor-id worker) actor-id
          (actor-pool-worker-state-current-job-id worker) (actor-execution-job-id job)))
  job)

(defun enqueue-actor-runtime-job (runtime job)
  (enqueue-concurrency-core-queue (actor-runtime-state-queue runtime) job))

(defun actor-runtime-lease-next-job (runtime worker)
  (lease-concurrency-core-queue-item
   (actor-runtime-state-gate runtime)
   (actor-runtime-state-queue runtime)
   (lambda (candidate)
     (actor-runtime-job-runnable-p runtime candidate))
   :on-match (lambda (job)
               (lease-actor-runtime-job runtime worker job))
   :stop-p (lambda ()
             (not (actor-runtime-state-running-p runtime)))
   :on-wait (lambda ()
              (setf (actor-pool-worker-state-phase worker) :waiting))))

(defun signal-actor-execution-job-complete (job result error)
  (if error
      (reject-concurrency-core-future (actor-execution-job-future job) error)
      (resolve-concurrency-core-future (actor-execution-job-future job) result)))

(defun actor-runtime-release-job (runtime worker job &key result error)
  (with-concurrency-core-gate ((actor-runtime-state-gate runtime))
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
    (concurrency-core-gate-broadcast (actor-runtime-state-gate runtime)))
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
  (when (and error
             (fboundp 'maybe-record-runtime-actor-job-supervision-failure))
    (ignore-errors
      (maybe-record-runtime-actor-job-supervision-failure
       (actor-execution-job-session job)
       job
       error)))
  (signal-actor-execution-job-complete job result error))

(defun call-with-actor-execution-bindings (job thunk)
  (let* ((session (actor-execution-job-session job))
         (environment (and session
                           (session-bound-environment session))))
    (let ((*current-actor-execution-job* job)
          (*current-session* session)
          (*current-environment* environment))
      (funcall thunk))))

(defun actor-thread-pool-worker-loop (runtime worker)
  (run-concurrency-core-managed-thread
   (lambda ()
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
                (let ((result (call-with-actor-execution-bindings
                               job
                               (actor-execution-job-thunk job))))
                  (actor-runtime-release-job runtime worker job :result result)))
            (error (condition)
              (actor-runtime-release-job runtime worker job
                                         :error (princ-to-string condition))))))
   :on-error (lambda (condition)
               (setf (actor-pool-worker-state-phase worker) :crashed
                     (actor-pool-worker-state-last-error worker)
                     (princ-to-string condition)))
   :on-finally (lambda ()
                 (setf (actor-pool-worker-state-running-p worker) nil
                       (actor-pool-worker-state-busy-p worker) nil
                       (actor-pool-worker-state-phase worker) :stopped
                       (actor-pool-worker-state-leased-actor-id worker) nil
                       (actor-pool-worker-state-current-job-id worker) nil))))

(defun start-actor-thread-pool (session &key (pool-size *default-actor-thread-pool-size*))
  (with-actor-runtime-lifecycle-lock (session)
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
                                    (spawn-concurrency-core-thread
                                     (actor-pool-worker-state-id worker)
                                     (lambda ()
                                       (actor-thread-pool-worker-loop runtime worker))))
                              worker))))
      runtime)))

(defun ensure-actor-thread-pool (session &key (pool-size *default-actor-thread-pool-size*))
  (let ((runtime (agent-session-actor-runtime-state session)))
    (if (and runtime (actor-runtime-state-running-p runtime))
        runtime
        (start-actor-thread-pool session :pool-size pool-size))))

(defun stop-actor-thread-pool (session)
  (with-actor-runtime-lifecycle-lock (session)
    (let ((runtime (agent-session-actor-runtime-state session)))
      (when runtime
        (with-concurrency-core-gate ((actor-runtime-state-gate runtime))
          (setf (actor-runtime-state-running-p runtime) nil)
          (concurrency-core-gate-broadcast (actor-runtime-state-gate runtime)))
        (dolist (worker (actor-runtime-state-workers runtime))
          (let ((thread (actor-pool-worker-state-thread worker)))
            (when thread
              (join-concurrency-core-thread thread)
              (setf (actor-pool-worker-state-thread worker) nil
                    (actor-pool-worker-state-running-p worker) nil
                    (actor-pool-worker-state-busy-p worker) nil
                    (actor-pool-worker-state-leased-actor-id worker) nil
                    (actor-pool-worker-state-current-job-id worker) nil))))
        runtime))))

(defun await-actor-execution-job (job)
  (await-concurrency-core-future (actor-execution-job-future job)))

(defun enqueue-actor-execution-job (session actor-id thunk &key (max-concurrency 1) context)
  (let* ((runtime (ensure-actor-thread-pool session))
         (job (make-actor-execution-job
               :id (make-actor-execution-job-id)
               :actor-id actor-id
               :max-concurrency (max 1 max-concurrency)
               :session session
               :context context
               :thunk thunk
               :future (make-concurrency-core-future-instance))))
    (append-actor-execution-lifecycle-event session
                                            :actor-execution-submitted
                                            job
                                            :status :queued)
    (record-actor-runtime-history runtime job :status :queued)
    (with-concurrency-core-gate ((actor-runtime-state-gate runtime))
      (enqueue-actor-runtime-job runtime job)
      (incf (actor-runtime-state-submitted-job-count runtime))
      (concurrency-core-gate-broadcast (actor-runtime-state-gate runtime)))
    job))

(defun submit-actor-execution-job (session actor-id thunk &key (max-concurrency 1) context)
  (await-actor-execution-job
   (enqueue-actor-execution-job session
                                actor-id
                                thunk
                                :max-concurrency max-concurrency
                                :context context)))

(defun actor-address-for-request-execution (session request)
  (or (and (desktop-task-request-actor-message request)
           (actor-message-receiver (desktop-task-request-actor-message request)))
      (make-standard-actor-address (desktop-task-request-target request)
                                   :scope (agent-session-id session))))

(defun current-actor-execution-reentrant-p (session actor-id)
  (let ((job *current-actor-execution-job*))
    (and job
         (eq (actor-execution-job-session job) session)
         (equal (actor-execution-job-actor-id job) actor-id))))

(defun actor-request-execution-dispatch (session request thunk &key context)
  (let* ((actor-address (actor-address-for-request-execution session request))
         (definition (and (fboundp 'find-actor-definition-for-address)
                          (find-actor-definition-for-address session actor-address)))
         (execution-policy (and definition
                                (actor-definition-execution-policy definition)))
         (execution-model (and execution-policy
                               (actor-execution-policy-model execution-policy)))
         (max-concurrency (or (and execution-policy
                                   (actor-execution-policy-max-concurrency execution-policy))
                              1))
         (effective-context (or context
                                (make-actor-execution-context
                                 :actor-id (actor-address-id actor-address)
                                 :capability (desktop-task-request-capability request)
                                 :target (desktop-task-request-target request)
                                 :operation (desktop-task-request-operation request)
                                 :request-id (desktop-task-request-id request)))))
    (if (eq execution-model :thread-pool-worker)
        (if (current-actor-execution-reentrant-p session (actor-address-id actor-address))
            (list :mode :inline
                  :thunk thunk
                  :actor-address actor-address
                  :context effective-context)
            (list :mode :queued
                  :job (enqueue-actor-execution-job session
                                                    (actor-address-id actor-address)
                                                    thunk
                                                    :max-concurrency max-concurrency
                                                    :context effective-context)
                  :actor-address actor-address
                  :context effective-context))
        (list :mode :inline
              :thunk thunk
              :actor-address actor-address
              :context effective-context))))

(defun call-with-actor-worker-for-request-async (session request thunk &key context)
  (actor-request-execution-dispatch session request thunk :context context))

(defun call-with-actor-worker-for-request (session request thunk &key context)
  (let* ((dispatch (actor-request-execution-dispatch session request thunk :context context))
         (mode (getf dispatch :mode)))
    (case mode
      (:queued
       (await-actor-execution-job (getf dispatch :job)))
      (:inline
       (let ((*current-session* session)
             (*current-environment* (session-bound-environment session)))
         (funcall (getf dispatch :thunk))))
      (otherwise
       (error "Unknown actor request execution mode ~S." mode)))))
