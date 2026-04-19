(in-package #:sbcl-agent)

(defun query-environment-summary-service (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (make-service-query-response :environment
                                 :summary
                                 (environment-summary active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-summary-v1
                                                                  :environment active-environment))))

(defun query-environment-status-service (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (make-service-query-response :environment
                                 :status
                                 (environment-status active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-status-v1
                                                                  :environment active-environment))))

(defun query-environment-events-service (&key tail environment)
  (let* ((active-environment (ensure-environment environment))
         (events (environment-event-log active-environment))
         (tail-count (normalize-tail-count tail))
         (start (max 0 (- (length events) tail-count))))
    (make-service-query-response :environment
                                 :events
                                 (list :environment-id (environment-id active-environment)
                                       :event-count (length events)
                                       :events (subseq events start))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-events-v1
                                                                  :environment active-environment))))
