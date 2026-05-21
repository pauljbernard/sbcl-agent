(in-package #:sbcl-agent.system.policy)

(defun make-governance-control-actor-address (session)
  (sbcl-agent::make-standard-actor-address :governance
                                           :scope (sbcl-agent::agent-session-id session)))

(defun actorize-approval-command-response (response
                                           &key actor-execution-job-id
                                             governance-authority
                                             policy-id
                                             approval-required-p
                                             approval-granted-p)
  (if (listp response)
      (let* ((metadata (copy-list (or (sbcl-agent::service-response-metadata response) '())))
             (data (sbcl-agent::service-response-data response)))
        (when actor-execution-job-id
          (setf (getf metadata :actor-execution-job-id) actor-execution-job-id))
        (when governance-authority
          (setf (getf metadata :governance-authority) governance-authority))
        (when policy-id
          (setf (getf metadata :policy-id) policy-id))
        (setf (getf metadata :approval-required-p) (and approval-required-p t)
              (getf metadata :approval-granted-p) (and approval-granted-p t)
              (getf response :metadata) metadata)
        (when (sbcl-agent::keyword-plist-p data)
          (let ((updated-data (copy-list data)))
            (when actor-execution-job-id
              (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id))
            (when governance-authority
              (setf (getf updated-data :governance-authority) governance-authority))
            (when policy-id
              (setf (getf updated-data :policy-id) policy-id))
            (setf (getf updated-data :approval-required-p) (and approval-required-p t)
                  (getf updated-data :approval-granted-p) (and approval-granted-p t)
                  (getf response :data) updated-data)))
        response)
      response))

(defun make-governance-control-request (session action capability
                                        &key payload metadata work-item-id)
  (sbcl-agent::make-governed-desktop-task-request
   :requester :context-chat
   :target :governance
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (sbcl-agent::agent-session-id session)
                           :actor-slice :governance-control-v1)
                     (when work-item-id
                       (list :work-item-id work-item-id))
                     metadata)))

(defun call-with-governance-actor (session request thunk capability action
                                   &key work-item-id workflow-record-id policy-id)
  (let* ((actor-address (make-governance-control-actor-address session))
         (actor-context (sbcl-agent::make-actor-execution-context
                         :actor-id (sbcl-agent::actor-address-id actor-address)
                         :capability capability
                         :authority :governed-runtime
                         :policy-id policy-id
                         :target :governance
                         :operation action
                         :request-id (sbcl-agent::desktop-task-request-id request)
                         :work-item-id work-item-id
                         :workflow-record-id workflow-record-id)))
    (sbcl-agent::call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (when (fboundp 'sbcl-agent::update-current-actor-execution-context)
         (sbcl-agent::update-current-actor-execution-context actor-context :replace-p t))
       (actorize-approval-command-response
        (funcall thunk)
        :actor-execution-job-id (sbcl-agent::current-actor-execution-job-id)
        :governance-authority :actor-runtime
        :policy-id policy-id))
     :context actor-context)))

(defun perform-approve-policy-service (session policy)
  (let* ((awaiting-records (sbcl-agent::desktop-task-records-awaiting-policy session policy))
         (approved (sbcl-agent::approve-policy session policy)))
    (dolist (record awaiting-records)
      (sbcl-agent::mark-desktop-task-record-approved session record))
    (sbcl-agent::register-service-command-response
     (sbcl-agent::make-service-command-response :approval
                                                :approve-policy
                                                (list :approved approved
                                                      :approved-policies (sbcl-agent::session-approved-policies session)
                                                      :capability-grants (sbcl-agent::session-capability-grants-summary session)
                                                      :desktop-task-records
                                                      (mapcar #'sbcl-agent::desktop-task-record-summary awaiting-records))
                                                :metadata (sbcl-agent::make-service-metadata :authority :environment
                                                                                             :command-model :approval-command-v2
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
  (let ((work-item (sbcl-agent::find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (sbcl-agent::request-work-item-approval session work-item policy :reason reason)
    (let ((response
            (sbcl-agent::register-service-command-response
             (sbcl-agent::make-service-command-response :approval
                                                        :request-work-item-approval
                                                        (list :work-item (sbcl-agent::work-item-detail work-item)
                                                              :wait (sbcl-agent::work-item-wait-report session work-item)
                                                              :workflow-record (let ((record (sbcl-agent::work-item-workflow-record session work-item)))
                                                                     (and record
                                                                          (sbcl-agent::workflow-record-summary record))))
                                                        :metadata (sbcl-agent::make-service-metadata :authority :environment
                                                                                                     :command-model :approval-command-v2
                                                                                                     :session session
                                                                                                     :work-item-id work-item-id
                                                                                                     :policy-id policy))
             :session session
             :intention (format nil "Request approval for governed work item ~A." work-item-id)
             :capability :workflow/request-approval
             :authority :governance
             :constraints (list :policy policy :reason reason))))
      (setf (getf response :data)
            (list :work-item (sbcl-agent::enriched-work-item-service-detail session work-item)
                  :wait (sbcl-agent::work-item-wait-report session work-item)
                  :workflow-record (let ((record (sbcl-agent::work-item-workflow-record session work-item)))
                                     (and record
                                          (sbcl-agent::enrich-workflow-record-summary-with-executions
                                           session
                                           (sbcl-agent::workflow-record-summary record))))))
      response)))

(defun command-request-work-item-approval-service (session work-item-id policy &key reason)
  (let* ((work-item (or (sbcl-agent::find-work-item session work-item-id)
                        (error "Unknown work-item ~A" work-item-id)))
         (workflow-record-id (sbcl-agent::work-item-workflow-record-ref work-item)))
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
