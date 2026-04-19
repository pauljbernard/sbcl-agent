(in-package #:sbcl-agent)

(defun query-task-list-service (session)
  (make-service-query-response :task
                               :list
                               (list-task-summaries session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :task-list-v1
                                                                :session session)))

(defun query-task-detail-service (session task-id)
  (let ((task (find-task session task-id)))
    (unless task
      (error "Unknown task ~A" task-id))
    (make-service-query-response :task
                                 :detail
                                 (task-summary task)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :task-detail-v1
                                                                  :session session))))

(defun query-task-monitor-service (session task-id)
  (let ((task (find-task session task-id)))
    (unless task
      (error "Unknown task ~A" task-id))
    (make-service-query-response :task
                                 :monitor
                                 (task-monitor-view task)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :task-monitor-v1
                                                                  :session session))))

(defun command-task-enqueue-service (session form command priority)
  (let ((task (enqueue-task session command :priority priority :payload form)))
    (make-service-command-response :task
                                   :enqueue
                                   (task-summary task)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :task-command-v1
                                                                    :session session))))

(defun command-task-cancel-service (session task-id)
  (make-service-command-response :task
                                 :cancel
                                 (task-summary (cancel-task session task-id))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :task-command-v1
                                                                  :session session)))

(defun command-task-run-next-service (session provider)
  (make-service-command-response :task
                                 :run-next
                                 (task-summary (run-next-task session provider))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :task-command-v1
                                                                  :session session)))
