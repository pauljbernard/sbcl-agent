(in-package #:sbcl-agent)

(defun command-approve-policy-service (session policy)
  (kernelize-service-command-response
   (make-service-command-response :approval
                                  :approve-policy
                                  (list :approved (approve-policy session policy)
                                        :approved-policies (session-approved-policies session)
                                        :capability-grants (session-capability-grants-summary session))
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :approval-command-v1
                                                                   :session session
                                                                   :policy-id policy))
   :session session
   :intention (format nil "Grant authority for policy ~A." policy)
   :capability :authority/grant
   :authority :operator))

(defun command-request-work-item-approval-service (session work-item-id policy &key reason)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (request-work-item-approval session work-item policy :reason reason)
    (let ((response
            (kernelize-service-command-response
             (make-service-command-response :approval
                                            :request-work-item-approval
                                            (list :work-item (work-item-detail work-item)
                                                  :wait (work-item-wait-report session work-item)
                                                  :workflow-record (let ((record (work-item-workflow-record session work-item)))
                                                                     (and record
                                                                          (workflow-record-summary record))))
                                            :metadata (make-service-metadata :authority :environment
                                                                             :command-model :approval-command-v1
                                                                             :session session
                                                                             :work-item-id work-item-id
                                                                             :policy-id policy))
             :session session
             :intention (format nil "Request approval for governed work item ~A." work-item-id)
             :capability :workflow/request-approval
             :authority :governance
             :constraints (list :policy policy :reason reason))))
      (setf (getf response :data)
            (list :work-item (enriched-work-item-service-detail session work-item)
                  :wait (work-item-wait-report session work-item)
                  :workflow-record (let ((record (work-item-workflow-record session work-item)))
                                     (and record
                                          (enrich-workflow-record-summary-with-executions
                                           session
                                           (workflow-record-summary record))))))
      response)))
