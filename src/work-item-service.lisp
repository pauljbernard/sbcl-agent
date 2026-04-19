(in-package #:sbcl-agent)

(defun enriched-work-item-service-detail (session work-item)
  (let ((detail (work-item-detail work-item))
        (record (work-item-workflow-record session work-item)))
    (if record
        (append detail (list :workflow-record (workflow-record-summary record)))
        detail)))

(defun query-work-item-list-service (session)
  (make-service-query-response :work-item
                               :list
                               (list-work-item-summaries session)
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
     (list :id (work-item-id work-item)
           :status (work-item-status work-item)
           :goal (work-item-goal work-item)
           :long-horizon-plan (work-item-long-horizon-plan work-item)
           :plan-health (work-item-plan-health work-item)
           :plan-steering (work-item-plan-steering work-item)
           :operator-steering-history (work-item-operator-steering-history work-item)
           :next-action (work-item-next-action work-item)
           :resume-payload (work-item-resume-payload work-item)
           :pending-validations (work-item-pending-validations work-item))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :work-item-plan-v1
                                      :session session
                                      :work-item-id work-item-id))))
