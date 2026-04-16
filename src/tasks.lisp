(in-package #:tutor-codex)

(defstruct task
  id
  kind
  command
  payload
  status
  priority
  created-at
  started-at
  completed-at
  result
  error
  session-id
  worker-id
  progress-events)

(defstruct worker-state
  id
  thread
  running-p
  session-id)

(defparameter *worker-sleep-seconds* 0.1)
(defparameter *task-progress-callback* nil)

(defun make-task-id ()
  (format nil "task-~D-~D" (get-universal-time) (random 1000000)))

(defun make-worker-id ()
  (format nil "worker-~D-~D" (get-universal-time) (random 1000000)))

(defun session-tasks (session)
  (agent-session-tasks session))

(defun session-workers (session)
  (agent-session-workers session))

(defun active-worker-count (session)
  (count-if #'worker-state-running-p (agent-session-workers session)))

(defun worker-summary (worker)
  (list :id (worker-state-id worker)
        :running-p (worker-state-running-p worker)
        :session-id (worker-state-session-id worker)))

(defun list-worker-summaries (session)
  (mapcar #'worker-summary (agent-session-workers session)))

(defun find-worker (session worker-id)
  (find worker-id (agent-session-workers session)
        :key #'worker-state-id :test #'string=))

(defun make-queued-task (session command &key (priority 0) payload)
  (make-task :id (make-task-id)
             :kind (command-kind command)
             :command command
             :payload payload
             :status :queued
             :priority priority
             :created-at (get-universal-time)
             :started-at nil
             :completed-at nil
             :result nil
             :error nil
             :session-id (agent-session-id session)
             :worker-id nil
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
  (setf (agent-session-tasks session) tasks)
  tasks)

(defun enqueue-task (session command &key (priority 0) payload)
  (let* ((task (make-queued-task session command :priority priority :payload payload))
         (tasks (append (agent-session-tasks session) (list task))))
    (update-session-task-list session (sort-tasks tasks))
    (append-session-event session :task-enqueued (task-summary task))
    task))

(defun find-task (session task-id)
  (find task-id (agent-session-tasks session) :key #'task-id :test #'string=))

(defun list-task-summaries (session)
  (mapcar #'task-summary (agent-session-tasks session)))

(defun cancel-task (session task-id)
  (let ((task (find-task session task-id)))
    (unless task
      (error "Unknown task ~A" task-id))
    (when (member (task-status task) '(:completed :failed :cancelled))
      (error "Task ~A is already finalized" task-id))
    (setf (task-status task) :cancelled
          (task-completed-at task) (get-universal-time))
    (append-task-progress-event session task :task-cancelled (task-summary task))
    (append-session-event session :task-cancelled (task-summary task))
    task))

(defun next-queued-task (session)
  (find :queued (agent-session-tasks session) :key #'task-status))

(defun execute-task (session provider task &optional worker-id)
  (setf (task-status task) :running
        (task-started-at task) (get-universal-time)
        (task-worker-id task) worker-id)
  (append-task-progress-event session task :task-started (task-summary task))
  (append-session-event session :task-started (task-summary task))
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
          task)
      (error (condition)
        (setf (task-status task) :failed
              (task-completed-at task) (get-universal-time)
              (task-error task) (princ-to-string condition))
        (append-task-progress-event session task :task-failed (task-summary task))
        (append-session-event session :task-failed (task-summary task))
        task))))

(defun run-next-task (session provider &optional worker-id)
  (let ((task (next-queued-task session)))
    (unless task
      (error "No queued tasks are available in the current session"))
    (execute-task session provider task worker-id)))

(defun worker-loop (session provider worker-state)
  (loop while (worker-state-running-p worker-state)
        do (let ((task (next-queued-task session)))
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
    (setf (agent-session-workers session)
          (append (agent-session-workers session) (list worker)))
    (append-session-event session :worker-started (worker-summary worker))
    worker))

(defun stop-worker (session worker-id)
  (let ((worker (find-worker session worker-id)))
    (unless worker
      (error "Unknown worker ~A" worker-id))
    (setf (worker-state-running-p worker) nil)
    worker))

(defun stop-all-workers (session)
  (mapcar (lambda (worker)
            (setf (worker-state-running-p worker) nil)
            (worker-summary worker))
          (agent-session-workers session)))

(defun serializable-worker-state (worker)
  (make-worker-state :id (worker-state-id worker)
                     :thread nil
                     :running-p nil
                     :session-id (worker-state-session-id worker)))

(defun serializable-worker-states (session)
  (mapcar #'serializable-worker-state (agent-session-workers session)))
