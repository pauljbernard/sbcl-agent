(in-package #:sbcl-agent)

(defun worker-execution-surface-summary (worker)
  (compact-execution-surface-summary
   (list :surface-id (format nil "surface-worker-~A" (worker-state-id worker))
         :surface-kind "worker"
         :attention-rank (if (worker-state-running-p worker) 1 2)
         :execution-id nil
         :title (format nil "Worker ~A" (worker-state-id worker))
         :status (if (worker-state-running-p worker) :running :stopped)
         :object-kind "worker"
         :worker-id (worker-state-id worker)
         :primary-execution-handle nil)))

(defun enrich-worker-summary-with-surface (summary)
  (let ((worker-id (getf summary :id))
        (running-p (getf summary :running-p)))
    (append summary
            (list :primary-execution-handle nil
                  :execution-handles '()
                  :execution-surface (worker-execution-surface-summary
                                      (make-worker-state :id worker-id
                                                         :running-p running-p
                                                         :session-id (getf summary :session-id)))))))

(defun query-worker-list-service (session)
  (make-service-query-response :worker
                               :list
                               (mapcar #'enrich-worker-summary-with-surface
                                       (list-worker-summaries session))
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :worker-list-v1
                                                                :session session)))

(defun query-worker-detail-service (session worker-id)
  (let ((worker (find-worker session worker-id)))
    (unless worker
      (error "Unknown worker ~A" worker-id))
    (make-service-query-response :worker
                                 :detail
                                 (enrich-worker-summary-with-surface
                                  (worker-summary worker))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :worker-detail-v1
                                                                  :session session))))

(defun command-worker-start-service (session provider)
  (make-service-command-response :worker
                                 :start
                                 (enrich-worker-summary-with-surface
                                  (worker-summary (start-worker session provider)))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :worker-command-v1
                                                                  :session session)))

(defun command-worker-stop-service (session worker-id)
  (make-service-command-response :worker
                                 :stop
                                 (enrich-worker-summary-with-surface
                                  (worker-summary (stop-worker session worker-id)))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :worker-command-v1
                                                                  :session session)))
