(in-package #:sbcl-agent)

(defun query-incident-list-service (session &key thread-id turn-id)
  (make-service-query-response :incident
                               :list
                               (list-incident-summaries session :thread-id thread-id :turn-id turn-id)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :incident-list-v1
                                                                :session session
                                                                :thread-id thread-id
                                                                :turn-id turn-id)))

(defun query-incident-detail-service (session incident-id)
  (let ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown incident ~A" incident-id))
    (make-service-query-response :incident
                                 :detail
                                 (incident-detail session incident)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :incident-detail-v1
                                                                  :session session
                                                                  :incident-id incident-id))))
