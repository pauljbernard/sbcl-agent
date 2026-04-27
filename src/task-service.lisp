(in-package #:sbcl-agent)

(defun task-associated-execution-summaries (session task)
  (let ((work-item-id (task-work-item-id task)))
    (when work-item-id
      (let ((work-item (find-work-item session work-item-id)))
        (and work-item
             (work-item-associated-execution-summaries session work-item))))))

(defun task-execution-surface-summary (session task)
  (let* ((handles (or (task-associated-execution-summaries session task) '()))
         (primary-handle (first handles))
         (command (task-command task))
         (title (format nil "Task ~A" (or (and command (command-kind command))
                                          (task-kind task)
                                          :unknown))))
    (compact-execution-surface-summary
     (list :surface-id (format nil "surface-task-~A" (task-id task))
           :surface-kind "task"
           :attention-rank (if (member (task-status task) '(:queued :running) :test #'eq) 1 2)
           :execution-id (getf primary-handle :execution-id)
           :title title
           :status (task-status task)
           :object-kind "task"
           :task-id (task-id task)
           :work-item-id (task-work-item-id task)
           :primary-execution-handle primary-handle))))

(defun enrich-task-summary-with-surface (session summary)
  (let ((task (find-task session (getf summary :id))))
    (append summary
            (when task
              (let ((handles (or (task-associated-execution-summaries session task) '())))
                (list :primary-execution-handle (first handles)
                      :execution-handles handles
                      :execution-surface (task-execution-surface-summary session task)))))))

(defun query-task-list-service (session)
  (make-service-query-response :task
                               :list
                               (mapcar (lambda (summary)
                                         (enrich-task-summary-with-surface session summary))
                                       (list-task-summaries session))
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :task-list-v1
                                                                :session session)))

(defun query-task-detail-service (session task-id)
  (let ((task (find-task session task-id)))
    (unless task
      (error "Unknown task ~A" task-id))
    (make-service-query-response :task
                                 :detail
                                 (enrich-task-summary-with-surface session
                                                                   (task-summary task))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :task-detail-v1
                                                                  :session session))))

(defun query-task-monitor-service (session task-id)
  (let ((task (find-task session task-id)))
    (unless task
      (error "Unknown task ~A" task-id))
    (make-service-query-response :task
                                 :monitor
                                 (append (task-monitor-view task)
                                         (let ((handles (or (task-associated-execution-summaries session task)
                                                            '())))
                                           (list :primary-execution-handle (first handles)
                                                 :execution-handles handles
                                                 :execution-surface (task-execution-surface-summary session task))))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :task-monitor-v1
                                                                  :session session))))

(defun command-task-enqueue-service (session form command priority)
  (let ((task (enqueue-task session command :priority priority :payload form)))
    (make-service-command-response :task
                                   :enqueue
                                   (enrich-task-summary-with-surface session
                                                                     (task-summary task))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :task-command-v1
                                                                    :session session))))

(defun command-task-cancel-service (session task-id)
  (make-service-command-response :task
                                 :cancel
                                 (enrich-task-summary-with-surface session
                                                                   (task-summary
                                                                    (cancel-task session task-id)))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :task-command-v1
                                                                  :session session)))

(defun command-task-run-next-service (session provider)
  (make-service-command-response :task
                                 :run-next
                                 (let ((task (run-next-task session provider)))
                                   (enrich-task-summary-with-surface session
                                                                     (task-summary task)))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :task-command-v1
                                                                  :session session)))
