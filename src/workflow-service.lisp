(in-package #:sbcl-agent)

(defun query-workflow-record-list-service (session)
  (make-service-query-response :workflow
                               :list-records
                               (list-workflow-record-summaries session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :workflow-record-list-v1
                                                                :session session)))

(defun query-workflow-record-detail-service (session workflow-record-id)
  (let ((record (find-workflow-record session workflow-record-id)))
    (unless record
      (error "Unknown workflow record ~A" workflow-record-id))
    (make-service-query-response :workflow
                                 :record-detail
                                 (workflow-record-detail record)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :workflow-record-detail-v1
                                                                  :session session
                                                                  :workflow-record-id workflow-record-id))))
