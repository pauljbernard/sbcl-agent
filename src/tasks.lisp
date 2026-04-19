(in-package #:sbcl-agent)

(defstruct task
  id
  kind
  command
  payload
  orchestration-group-id
  ownership-scope
  merge-policy
  shared-context
  status
  priority
  created-at
  started-at
  completed-at
  result
  error
  session-id
  worker-id
  work-item-id
  progress-events)

(defstruct worker-state
  id
  thread
  running-p
  session-id)

(defparameter *worker-sleep-seconds* 0.1)
(defparameter *task-progress-callback* nil)
(defparameter *task-scheduler-lock* (sb-thread:make-mutex :name "sbcl-agent-task-scheduler"))

(defun make-task-id ()
  (format nil "task-~D-~D" (get-universal-time) (random 1000000)))

(defun make-worker-id ()
  (format nil "worker-~D-~D" (get-universal-time) (random 1000000)))

(defun make-orchestration-group-id ()
  (format nil "group-~D-~D" (get-universal-time) (random 1000000)))

(defun session-tasks (session)
  (agent-session-tasks session))

(defun session-workers (session)
  (agent-session-workers session))

(defun environment-task-records (environment &optional session)
  (let* ((agent-state (and environment
                           (environment-agent-state environment)))
         (existing (and agent-state
                        (environment-agent-state-tasks agent-state))))
    (or existing
        (and environment
             session
             (agent-session-tasks session)
             (refresh-environment-agent-domain environment session)
             (let ((refreshed-state (environment-agent-state environment)))
               (and refreshed-state
                    (environment-agent-state-tasks refreshed-state)))))))

(defun environment-worker-records (environment &optional session)
  (let* ((agent-state (and environment
                           (environment-agent-state environment)))
         (existing (and agent-state
                        (environment-agent-state-workers agent-state))))
    (or existing
        (and environment
             session
             (agent-session-workers session)
             (refresh-environment-agent-domain environment session)
             (let ((refreshed-state (environment-agent-state environment)))
               (and refreshed-state
                    (environment-agent-state-workers refreshed-state)))))))

(defun active-worker-count (session)
  (count-if #'worker-state-running-p (agent-session-workers session)))

(defun worker-summary (worker)
  (list :id (worker-state-id worker)
        :running-p (worker-state-running-p worker)
        :session-id (worker-state-session-id worker)))

(defun list-worker-summaries (session)
  (let ((environment (session-bound-environment session)))
    (mapcar #'worker-summary
            (or (and environment
                     (environment-worker-records environment session))
                (agent-session-workers session)))))

(defun find-worker (session worker-id)
  (let ((environment (session-bound-environment session)))
    (find worker-id
          (or (and environment
                   (environment-worker-records environment session))
              (agent-session-workers session))
          :key #'worker-state-id :test #'string=)))

(defun session-owned-worker (session worker-id)
  (find worker-id
        (agent-session-workers session)
        :key #'worker-state-id :test #'string=))

(defun task-orchestration-summary (task)
  (list :group-id (task-orchestration-group-id task)
        :ownership-scope (task-ownership-scope task)
        :merge-policy (task-merge-policy task)
        :shared-context (task-shared-context task)))

(defun orchestration-group-tasks (session group-id)
  (remove-if-not (lambda (task)
                   (and (task-orchestration-group-id task)
                        (string= group-id (task-orchestration-group-id task))))
                 (agent-session-tasks session)))

(defun finalized-task-status-p (status)
  (member status '(:completed :failed :cancelled) :test #'eq))

(defun orchestration-group-finalized-p (session group-id)
  (every (lambda (task)
           (finalized-task-status-p (task-status task)))
         (orchestration-group-tasks session group-id)))

(defun orchestration-group-summary (session group-id)
  (let* ((tasks (orchestration-group-tasks session group-id))
         (worker-ids (remove-duplicates (remove nil (mapcar #'task-worker-id tasks)) :test #'string=))
         (ownership-scopes (remove nil (mapcar #'task-ownership-scope tasks)))
         (merge-policy (and tasks (task-merge-policy (first tasks))))
         (shared-context (and tasks (task-shared-context (first tasks)))))
    (list :group-id group-id
          :task-count (length tasks)
          :completed-task-count (count :completed tasks :key #'task-status :test #'eq)
          :distinct-worker-count (length worker-ids)
          :worker-ids worker-ids
          :merge-policy merge-policy
          :shared-context shared-context
          :ownership-explicit-p (every #'identity ownership-scopes)
          :ownership-scopes (copy-tree ownership-scopes)
          :review-required-p (eq merge-policy :serial-review)
          :finalized-p (every (lambda (task)
                                (finalized-task-status-p (task-status task)))
                              tasks))))

(defun apply-task-orchestration-review-posture (session task)
  (let ((group-id (task-orchestration-group-id task)))
    (when (and group-id
               (eq (task-merge-policy task) :serial-review)
               (orchestration-group-finalized-p session group-id))
      (let* ((group-summary (orchestration-group-summary session group-id))
             (task-summaries (mapcar #'task-summary (orchestration-group-tasks session group-id))))
        (dolist (group-task (orchestration-group-tasks session group-id))
          (let ((work-item (and (task-work-item-id group-task)
                                (find-work-item session (task-work-item-id group-task)))))
            (when work-item
              (set-work-item-next-action
               session
               work-item
               (list :type :serial-review-merge
                     :suggested-step :review-orchestration-group
                     :orchestration-group group-summary))
              (set-work-item-resume-payload
               session
               work-item
               (list :resume-command :review-orchestration-group
                     :group-id group-id
                     :merge-policy (task-merge-policy group-task)
                     :task-summaries task-summaries
                     :orchestration-group group-summary)))))
        (remember-orchestration-outcome-memory
         session
         group-summary
         :prompt (or (getf (getf group-summary :shared-context) :goal)
                     (format nil "Parallel orchestration group ~A" group-id)))))))

(defun make-queued-task (session command &key (priority 0) payload orchestration-group-id ownership-scope merge-policy shared-context)
  (make-task :id (make-task-id)
             :kind (command-kind command)
             :command command
             :payload payload
             :orchestration-group-id orchestration-group-id
             :ownership-scope ownership-scope
             :merge-policy merge-policy
             :shared-context shared-context
             :status :queued
             :priority priority
             :created-at (get-universal-time)
             :started-at nil
             :completed-at nil
             :result nil
             :error nil
             :session-id (agent-session-id session)
             :worker-id nil
             :work-item-id nil
             :progress-events '()))

(defun task-summary (task)
  (list :id (task-id task)
        :kind (task-kind task)
        :status (task-status task)
        :priority (task-priority task)
        :created-at (task-created-at task)
        :started-at (task-started-at task)
        :completed-at (task-completed-at task)
        :session-id (task-session-id task)
        :worker-id (task-worker-id task)
        :work-item-id (task-work-item-id task)
        :orchestration (task-orchestration-summary task)
        :merge-review-required-p (eq (task-merge-policy task) :serial-review)
        :progress-event-count (length (task-progress-events task))
        :latest-progress-event (car (last (task-progress-events task)))
        :result (task-result task)
        :error (task-error task)))

(defun append-task-progress-event (session task kind payload)
  (declare (ignore session))
  (let ((event (make-event-now kind payload)))
    (setf (task-progress-events task)
          (append (task-progress-events task) (list event)))
    event))

(defun task-progress-callback (session task)
  (lambda (kind payload)
    (append-task-progress-event session task kind payload)))

(defun progress-event-summary (event)
  (list :timestamp (event-timestamp event)
        :kind (event-kind event)
        :payload (event-payload event)))

(defun task-monitor-view (task &key (tail 5))
  (let* ((events (task-progress-events task))
         (count (length events))
         (recent (if (> count tail)
                     (subseq events (- count tail))
                     events)))
    (list :id (task-id task)
          :status (task-status task)
          :worker-id (task-worker-id task)
          :work-item-id (task-work-item-id task)
          :progress-event-count count
          :recent-progress-events (mapcar #'progress-event-summary recent)
          :latest-progress-event (and events (progress-event-summary (car (last events)))))))

(defun sort-tasks (tasks)
  (sort tasks
        (lambda (left right)
          (or (> (task-priority left) (task-priority right))
              (and (= (task-priority left) (task-priority right))
                   (< (task-created-at left) (task-created-at right)))))))

(defun update-session-task-list (session tasks)
  (setf (agent-session-tasks session) tasks
        (agent-session-tasks-tail session) (last tasks))
  tasks)

(defun enqueue-task (session command &key (priority 0) payload orchestration-group-id ownership-scope merge-policy shared-context)
  (let* ((task (make-queued-task session
                                 command
                                 :priority priority
                                 :payload payload
                                 :orchestration-group-id orchestration-group-id
                                 :ownership-scope ownership-scope
                                 :merge-policy merge-policy
                                 :shared-context shared-context))
         (work-item (create-work-item-for-task session task)))
    (setf (task-work-item-id task) (work-item-id work-item))
    (append-work-item-checkpoint session work-item)
    (update-work-item-status-from-task session task :planned)
    (multiple-value-bind (tasks tail)
        (append-linked-item (agent-session-tasks session)
                            (agent-session-tasks-tail session)
                            task)
      (setf (agent-session-tasks session) tasks
            (agent-session-tasks-tail session) tail))
    (update-session-task-list session (sort-tasks (agent-session-tasks session)))
    (append-session-event session :task-enqueued (task-summary task))
    (refresh-bound-environment-agent-state session)
    task))

(defun enqueue-parallel-task-group (session task-specs &key shared-context (merge-policy :serial-review) group-id)
  (let ((resolved-group-id (or group-id (make-orchestration-group-id))))
    (mapcar (lambda (spec)
              (enqueue-task session
                            (getf spec :command)
                            :priority (or (getf spec :priority) 0)
                            :payload (getf spec :payload)
                            :orchestration-group-id resolved-group-id
                            :ownership-scope (getf spec :ownership-scope)
                            :merge-policy merge-policy
                            :shared-context shared-context))
            task-specs)))

(defun find-task (session task-id)
  (let ((environment (session-bound-environment session)))
    (find task-id
          (or (and environment
                   (environment-task-records environment session))
              (agent-session-tasks session))
          :key #'task-id :test #'string=)))

(defun session-owned-task (session task-id)
  (find task-id
        (agent-session-tasks session)
        :key #'task-id :test #'string=))

(defun list-task-summaries (session)
  (let ((environment (session-bound-environment session)))
    (mapcar #'task-summary
            (or (and environment
                     (environment-task-records environment session))
                (agent-session-tasks session)))))

(defun cancel-task (session task-id)
  (let ((task (session-owned-task session task-id)))
    (unless task
      (error "Unknown task ~A" task-id))
    (when (member (task-status task) '(:completed :failed :cancelled))
      (error "Task ~A is already finalized" task-id))
    (setf (task-status task) :cancelled
          (task-completed-at task) (get-universal-time))
    (append-task-progress-event session task :task-cancelled (task-summary task))
    (append-session-event session :task-cancelled (task-summary task))
    (update-work-item-status-from-task session task :rolled-back
                                       :closure-decision :cancelled)
    (refresh-bound-environment-agent-state session)
    task))

(defun next-queued-task (session)
  (find :queued (agent-session-tasks session) :key #'task-status))

(defun claim-next-queued-task (session &optional worker-id)
  (sb-thread:with-mutex (*task-scheduler-lock*)
    (let ((task (next-queued-task session)))
      (when task
        (setf (task-status task) :claimed
              (task-worker-id task) worker-id
              (task-started-at task) (get-universal-time))
        task))))

(defun execute-task (session provider task &optional worker-id)
  (setf (task-status task) :running
        (task-started-at task) (or (task-started-at task) (get-universal-time))
        (task-worker-id task) (or worker-id (task-worker-id task)))
  (append-task-progress-event session task :task-started (task-summary task))
  (append-session-event session :task-started (task-summary task))
  (append-work-item-image-mutation (find-work-item session (task-work-item-id task))
                                   (list :kind :task-execution
                                         :task-id (task-id task)
                                         :command-kind (task-kind task))
                                   session)
  (update-work-item-status-from-task session task :mutating)
  (let ((*task-progress-callback* (task-progress-callback session task)))
    (handler-case
        (multiple-value-bind (result kind updated-session)
            (execute-command (task-command task) provider session)
          (declare (ignore kind updated-session))
          (setf (task-status task) :completed
                (task-completed-at task) (get-universal-time)
                (task-result task) result)
          (append-task-progress-event session task :task-completed (task-summary task))
          (append-session-event session :task-completed (task-summary task))
          (let ((work-item (find-work-item session (task-work-item-id task))))
            (when work-item
              (append-work-item-source-mutation work-item
                                                (list :kind :result
                                                      :task-id (task-id task)
                                                      :result-kind (task-kind task))
                                                session)
              (append-work-item-resource-effect work-item
                                                (list :kind :completion
                                                      :task-id (task-id task)
                                                      :worker-id worker-id)
                                                session)))
          (update-work-item-status-from-task session task :committed
                                             :closure-decision :committed-to-source-and-image)
          (apply-task-orchestration-review-posture session task)
          (refresh-bound-environment-agent-state session)
          task)
      (error (condition)
        (setf (task-status task) :failed
              (task-completed-at task) (get-universal-time)
              (task-error task) (princ-to-string condition))
        (append-task-progress-event session task :task-failed (task-summary task))
        (append-session-event session :task-failed (task-summary task))
        (let ((work-item (find-work-item session (task-work-item-id task))))
          (when work-item
            (append-work-item-resource-effect work-item
                                              (list :kind :failure
                                                    :task-id (task-id task)
                                                    :error (princ-to-string condition))
                                              session)))
        (update-work-item-status-from-task session task :failed
                                           :closure-decision :rejected-and-rolled-back
                                           :error (princ-to-string condition))
        (refresh-bound-environment-agent-state session)
        task))))

(defun run-next-task
 (session provider &optional worker-id)
  (let ((task (claim-next-queued-task session worker-id)))
    (unless task
      (error "No queued tasks are available in the current session"))
    (execute-task session provider task worker-id)))

(defun worker-loop (session provider worker-state)
  (loop while (worker-state-running-p worker-state)
        do (let ((task (claim-next-queued-task session (worker-state-id worker-state))))
             (if task
                 (execute-task session provider task (worker-state-id worker-state))
                 (sleep *worker-sleep-seconds*))))
  (setf (worker-state-running-p worker-state) nil)
  (append-session-event session :worker-stopped
                        (worker-summary worker-state)))

(defun start-worker (session provider)
  (let* ((worker-id (make-worker-id))
         (worker (make-worker-state :id worker-id
                                    :thread nil
                                    :running-p t
                                    :session-id (agent-session-id session))))
    (setf (worker-state-thread worker)
          (sb-thread:make-thread
           (lambda ()
             (worker-loop session provider worker))
           :name worker-id))
    (multiple-value-bind (workers tail)
        (append-linked-item (agent-session-workers session)
                            (agent-session-workers-tail session)
                            worker)
      (setf (agent-session-workers session) workers
            (agent-session-workers-tail session) tail))
    (append-session-event session :worker-started (worker-summary worker))
    (refresh-bound-environment-agent-state session)
    worker))

(defun stop-worker (session worker-id)
  (let ((worker (session-owned-worker session worker-id)))
    (unless worker
      (error "Unknown worker ~A" worker-id))
    (setf (worker-state-running-p worker) nil)
    (refresh-bound-environment-agent-state session)
    worker))

(defun stop-all-workers (session)
  (prog1
      (mapcar (lambda (worker)
                (setf (worker-state-running-p worker) nil)
                (worker-summary worker))
              (agent-session-workers session))
    (refresh-bound-environment-agent-state session)))

(defun serializable-worker-state (worker)
  (make-worker-state :id (worker-state-id worker)
                     :thread nil
                     :running-p nil
                     :session-id (worker-state-session-id worker)))

(defun serializable-worker-states (session)
  (mapcar #'serializable-worker-state (agent-session-workers session)))
