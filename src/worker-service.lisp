(in-package #:sbcl-agent)

(defun query-worker-list-service (session)
  (make-service-query-response :worker
                               :list
                               (list-worker-summaries session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :worker-list-v1
                                                                :session session)))

(defun query-worker-detail-service (session worker-id)
  (let ((worker (find-worker session worker-id)))
    (unless worker
      (error "Unknown worker ~A" worker-id))
    (make-service-query-response :worker
                                 :detail
                                 (worker-summary worker)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :worker-detail-v1
                                                                  :session session))))

(defun command-worker-start-service (session provider)
  (make-service-command-response :worker
                                 :start
                                 (worker-summary (start-worker session provider))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :worker-command-v1
                                                                  :session session)))

(defun command-worker-stop-service (session worker-id)
  (make-service-command-response :worker
                                 :stop
                                 (worker-summary (stop-worker session worker-id))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :worker-command-v1
                                                                  :session session)))
