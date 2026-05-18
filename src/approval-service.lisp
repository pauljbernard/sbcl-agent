(in-package #:sbcl-agent)

(defun make-governance-control-actor-address (session)
  (make-standard-actor-address :governance
                               :scope (agent-session-id session)))

(defun actorize-approval-command-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (listp data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun make-governance-control-request (session action capability
                                        &key payload metadata work-item-id)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :governance
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :governance-control-v1)
                     (when work-item-id
                       (list :work-item-id work-item-id))
                     metadata)))

(defun call-with-governance-actor (session request thunk capability action
                                   &key work-item-id workflow-record-id policy-id)
  (let ((actor-address (make-governance-control-actor-address session)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-approval-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :governance
               :policy-id policy-id
               :target :governance
               :operation action
               :request-id (desktop-task-request-id request)
               :work-item-id work-item-id
               :workflow-record-id workflow-record-id))))

(defun perform-approve-policy-service (session policy)
  (let* ((awaiting-records (desktop-task-records-awaiting-policy session policy))
         (approved (approve-policy session policy)))
    (dolist (record awaiting-records)
      (mark-desktop-task-record-approved session record))
  (kernelize-service-command-response
   (make-service-command-response :approval
                                  :approve-policy
                                  (list :approved approved
                                        :approved-policies (session-approved-policies session)
                                        :capability-grants (session-capability-grants-summary session)
                                        :desktop-task-records
                                        (mapcar #'desktop-task-record-summary awaiting-records))
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :approval-command-v1
                                                                   :session session
                                                                   :policy-id policy))
   :session session
   :intention (format nil "Grant authority for policy ~A." policy)
   :capability :authority/grant
   :authority :operator)))

(defun command-approve-policy-service (session policy)
  (call-with-governance-actor
   session
   (make-governance-control-request session
                                    :approve-policy
                                    :authority/grant
                                    :payload (list :policy policy)
                                    :metadata (list :policy-id policy))
   (lambda ()
     (perform-approve-policy-service session policy))
   :authority/grant
   :approve-policy
   :policy-id policy))

(defun perform-request-work-item-approval-service (session work-item-id policy &key reason)
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

(defun command-request-work-item-approval-service (session work-item-id policy &key reason)
  (let* ((work-item (or (find-work-item session work-item-id)
                        (error "Unknown work-item ~A" work-item-id)))
         (workflow-record-id (work-item-workflow-record-ref work-item)))
    (call-with-governance-actor
     session
     (make-governance-control-request session
                                      :request-work-item-approval
                                      :workflow/request-approval
                                      :payload (list :work-item-id work-item-id
                                                     :policy policy
                                                     :reason reason)
                                      :metadata (append (list :policy-id policy)
                                                        (when reason
                                                          (list :reason reason)))
                                      :work-item-id work-item-id)
     (lambda ()
       (perform-request-work-item-approval-service session
                                                   work-item-id
                                                   policy
                                                   :reason reason))
     :workflow/request-approval
     :request-work-item-approval
     :work-item-id work-item-id
     :workflow-record-id workflow-record-id
     :policy-id policy)))
