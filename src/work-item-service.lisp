(in-package #:sbcl-agent)

(defun work-item-associated-execution-summaries (session work-item)
  (let ((environment (session-bound-environment session)))
    (when environment
      (mapcar #'kernel-execution-summary
              (kernel-find-executions-by-target :work-item-id
                                                (work-item-id work-item)
                                                environment)))))

(defun enrich-work-item-summary-with-executions (session summary)
  (let* ((work-item-id (getf summary :id))
         (work-item (and work-item-id
                         (find-work-item session work-item-id)))
         (handles (and work-item
                       (work-item-associated-execution-summaries session work-item))))
    (append summary
            (list :primary-execution-handle (first handles)
                  :execution-handles (or handles '())
                  :execution-surface (compact-execution-surface-summary
                                      (primary-execution-surface-summary session handles))))))

(defun enriched-work-item-service-detail (session work-item)
  (let ((detail (work-item-detail work-item))
        (record (work-item-workflow-record session work-item)))
    (append detail
            (when record
              (list :workflow-record (workflow-record-summary record)))
            (let ((handles (or (work-item-associated-execution-summaries session work-item)
                               '())))
              (list :primary-execution-handle (first handles)
                    :execution-handles handles
                    :execution-surface (compact-execution-surface-summary
                                        (primary-execution-surface-summary session handles)))))))

(defun query-work-item-list-service (session)
  (make-service-query-response :work-item
                               :list
                               (mapcar (lambda (summary)
                                         (enrich-work-item-summary-with-executions session summary))
                                       (list-work-item-summaries session))
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :work-item-list-v1
                                                                :session session)))

(defun query-work-item-detail-service (session work-item-id)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (make-service-query-response :work-item
                                 :detail
                                 (enriched-work-item-service-detail session work-item)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :work-item-detail-v1
                                                                  :session session
                                                                  :work-item-id work-item-id))))

(defun query-work-item-plan-service (session work-item-id)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (make-service-query-response
     :work-item
     :plan
     (let ((handles (or (work-item-associated-execution-summaries session work-item)
                        '())))
       (list :id (work-item-id work-item)
             :status (work-item-status work-item)
             :goal (work-item-goal work-item)
             :long-horizon-plan (work-item-long-horizon-plan work-item)
             :plan-health (work-item-plan-health work-item)
             :plan-steering (work-item-plan-steering work-item)
             :operator-steering-history (work-item-operator-steering-history work-item)
             :next-action (work-item-next-action work-item)
             :resume-payload (work-item-resume-payload work-item)
             :pending-validations (work-item-pending-validations work-item)
             :primary-execution-handle (first handles)
             :execution-handles handles
             :execution-surface (compact-execution-surface-summary
                                 (primary-execution-surface-summary session handles))))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :work-item-plan-v1
                                      :session session
                                      :work-item-id work-item-id))))
