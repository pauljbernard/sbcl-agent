(in-package #:sbcl-agent)

(defun workflow-record-associated-execution-summaries (session record)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let* ((direct (find-execution-handles-by-target :workflow-record-id
                                                       (workflow-record-id record)
                                                       environment))
             (via-work-item (find-execution-handles-by-target :work-item-id
                                                              (workflow-record-work-item-id record)
                                                              environment))
             (combined (append direct via-work-item)))
        (mapcar #'execution-handle-summary
                (remove-duplicates combined
                                   :key #'execution-handle-execution-id
                                   :test #'string=))))))

(defun enrich-workflow-record-summary-with-executions (session summary)
  (let* ((record-id (getf summary :id))
         (record (and record-id
                      (find-workflow-record session record-id)))
         (handles (and record
                       (workflow-record-associated-execution-summaries session record))))
    (append summary
            (list :primary-execution-handle (first handles)
                  :execution-handles (or handles '())
                  :execution-surface (compact-execution-surface-summary
                                      (primary-execution-surface-summary session handles))))))

(defun query-workflow-record-list-service (session)
  (make-service-query-response :workflow
                               :list-records
                               (mapcar (lambda (summary)
                                         (enrich-workflow-record-summary-with-executions session summary))
                                       (list-workflow-record-summaries session))
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :workflow-record-list-v1
                                                                :session session)))

(defun query-workflow-record-detail-service (session workflow-record-id)
  (let ((record (find-workflow-record session workflow-record-id)))
    (unless record
      (error "Unknown workflow record ~A" workflow-record-id))
    (make-service-query-response :workflow
                                 :record-detail
                                 (let ((handles (or (workflow-record-associated-execution-summaries session record)
                                                    '())))
                                   (append (workflow-record-detail record)
                                           (list :primary-execution-handle (first handles)
                                                 :execution-handles handles
                                                 :execution-surface (compact-execution-surface-summary
                                                                     (primary-execution-surface-summary session handles)))))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :workflow-record-detail-v1
                                                                  :session session
                                                                  :workflow-record-id workflow-record-id))))

(defun command-workflow-record-detail-query-service (session workflow-record-id)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :workflow-record-detail-query
                                :workflow/record-detail
                                :payload (list :workflow-record-id workflow-record-id)
                                :workflow-record-id workflow-record-id
                                :metadata (list :workflow-record-id workflow-record-id))
   (lambda ()
     (query-workflow-record-detail-service session workflow-record-id))
   :workflow/record-detail
   :workflow-record-detail-query
   :workflow-record-id workflow-record-id
   :metadata (list :workflow-record-id workflow-record-id)))
