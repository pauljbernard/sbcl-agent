(in-package #:sbcl-agent)

(defun actorize-rgp-query-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (keyword-plist-p data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun actorize-rgp-command-response (response
                                      &key actor-execution-job-id
                                        governance-authority
                                        policy-id
                                        approval-required-p
                                        approval-granted-p)
  (if (listp response)
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (when actor-execution-job-id
          (setf (getf metadata :actor-execution-job-id) actor-execution-job-id))
        (when governance-authority
          (setf (getf metadata :governance-authority) governance-authority))
        (when policy-id
          (setf (getf metadata :policy-id) policy-id))
        (setf (getf metadata :approval-required-p) (and approval-required-p t)
              (getf metadata :approval-granted-p) (and approval-granted-p t)
              (getf response :metadata) metadata)
        (when (keyword-plist-p data)
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

(defun command-rgp-workspace-query-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request active-environment
                                       :rgp-workspace-query
                                       :rgp/workspace
                                       :payload '()
                                       :metadata (list :rgp-query-kind :workspace))
     (lambda ()
       (actorize-rgp-query-response
        (query-rgp-workspace-service session active-environment)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :rgp/workspace
     :rgp-workspace-query)))

(defun query-rgp-artifact-detail-service (session artifact-id &optional environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (record (environment-find-artifact-record active-environment artifact-id)))
    (unless record
      (error "Unknown artifact ~A" artifact-id))
    (make-service-query-response
     :artifact
     :detail
     (append record
             (list :lineage (list :source-ref (getf record :source-ref)
                                  :image-ref (getf record :image-ref)
                                  :work-item-id (getf record :work-item-id))
                   :governance-scope (if (getf record :thread-id)
                                         :thread
                                         :environment)))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :artifact-detail-v1
                                      :session session
                                      :environment active-environment))))

(defun command-rgp-artifacts-query-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request active-environment
                                       :rgp-artifacts-query
                                       :rgp/artifacts
                                       :payload '()
                                       :metadata (list :rgp-query-kind :artifacts))
     (lambda ()
       (actorize-rgp-query-response
        (query-rgp-artifacts-service session active-environment)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :rgp/artifacts
     :rgp-artifacts-query)))

(defun command-rgp-artifact-detail-query-service (session artifact-id &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request active-environment
                                       :rgp-artifact-detail-query
                                       :rgp/artifact-detail
                                       :payload (list :artifact-id artifact-id)
                                       :metadata (list :artifact-id artifact-id
                                                       :rgp-query-kind :artifact-detail))
     (lambda ()
       (actorize-rgp-query-response
        (query-rgp-artifact-detail-service session artifact-id active-environment)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :rgp/artifact-detail
     :rgp-artifact-detail-query)))

(defun command-rgp-approvals-query-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request active-environment
                                       :rgp-approvals-query
                                       :rgp/approvals
                                       :payload '()
                                       :metadata (list :rgp-query-kind :approvals))
     (lambda ()
       (actorize-rgp-query-response
        (query-rgp-approvals-service session active-environment)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :rgp/approvals
     :rgp-approvals-query)))

(defun command-rgp-bind-service (session &key tenant-id
                                      request-id
                                      agent-session-id
                                      integration-id
                                      projection-id
                                      rgp-agent-id
                                      operator-id
                                      employment-model
                                      trust-profile
                                      visibility-profile
                                      billing-profile
                                      accepted-policy-profiles
                                      environment)
  (let* ((binding (bind-environment-to-rgp session
                                           :tenant-id tenant-id
                                           :request-id request-id
                                           :agent-session-id agent-session-id
                                           :integration-id integration-id
                                           :projection-id projection-id
                                           :rgp-agent-id rgp-agent-id
                                           :operator-id operator-id
                                           :employment-model employment-model
                                           :trust-profile trust-profile
                                           :visibility-profile visibility-profile
                                           :billing-profile billing-profile
                                           :accepted-policy-profiles accepted-policy-profiles
                                           :environment environment))
         (active-environment (ensure-environment environment)))
    (make-service-command-response :rgp
                                   :bind
                                   (list :binding (rgp-binding-summary active-environment)
                                         :node-profile (environment-rgp-node-profile active-environment)
                                         :governed-runtime (environment-rgp-runtime-summary active-environment)
                                         :environment-id (environment-id active-environment)
                                         :session-id (agent-session-id session)
                                         :updated-binding binding)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-command-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun query-rgp-show-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :show
                                 (environment-rgp-snapshot active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-snapshot-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-rgp-node-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :node
                                 (list :node-profile (environment-rgp-node-profile active-environment)
                                       :governed-runtime (environment-rgp-runtime-summary
                                                          active-environment)
                                       :local-assignments (environment-rgp-enriched-assignment-summaries
                                                           session
                                                           active-environment)
                                       :workspace-summary (environment-rgp-workspace-summary
                                                           session
                                                           active-environment)
                                       :business-posture (environment-rgp-business-posture
                                                          active-environment)
                                       :publication-posture (environment-rgp-publication-posture
                                                             active-environment))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-node-profile-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-rgp-workspace-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :workspace-summary
                                 (environment-rgp-workspace-summary
                                  session
                                  active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-workspace-summary-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-rgp-configure-node-service (session &key rgp-agent-id
                                                operator-id
                                                employment-model
                                                trust-profile
                                                visibility-profile
                                                billing-profile
                                                accepted-policy-profiles
                                                environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (profile (configure-environment-rgp-node-profile
                   session
                   :rgp-agent-id rgp-agent-id
                   :operator-id operator-id
                   :employment-model employment-model
                   :trust-profile trust-profile
                   :visibility-profile visibility-profile
                   :billing-profile billing-profile
                   :accepted-policy-profiles accepted-policy-profiles
                   :environment active-environment)))
    (make-service-command-response :rgp
                                   :configure-node
                                   (list :node-profile profile
                                         :environment-id (environment-id active-environment))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-node-command-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun command-rgp-export-service (session path &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-command-response :rgp
                                   :export
                                   (export-environment-rgp-snapshot path active-environment)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-command-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-rgp-assignments-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :assignments
                                 (environment-rgp-enriched-assignment-summaries
                                  session
                                  active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-local-assignments-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-rgp-evidence-service (session &optional assignment-id environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (evidence (environment-rgp-assignment-evidence-summaries active-environment)))
    (make-service-query-response :rgp
                                 :evidence
                                 (if assignment-id
                                     (find assignment-id evidence
                                           :key (lambda (entry) (getf entry :assignment-id))
                                           :test #'string=)
                                     evidence)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-assignment-evidence-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-rgp-receive-assignment-service (session &key assignment-id
                                                    goal
                                                    rgp-work-id
                                                    operator-model
                                                    compensation-profile
                                                    evidence-profile
                                                    visibility-profile
                                                    billing-state
                                                    acceptance-state
                                                    thread-id
                                                    environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (result (receive-environment-rgp-assignment
                  session
                  :assignment-id assignment-id
                  :goal goal
                  :rgp-work-id rgp-work-id
                  :operator-model operator-model
                  :compensation-profile compensation-profile
                  :evidence-profile evidence-profile
                  :visibility-profile visibility-profile
                  :billing-state billing-state
                  :acceptance-state acceptance-state
                  :thread-id thread-id
                  :environment active-environment)))
    (make-service-command-response :rgp
                                   :receive-assignment
                                   result
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-assignment-inbound-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun command-rgp-accept-assignment-service (session assignment-id &key note environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment)))
    (multiple-value-bind (assignment publication lifecycle)
        (transition-environment-rgp-local-assignment session assignment-id :accepted
                                                     :note note
                                                     :environment active-environment)
      (make-service-command-response :rgp
                                     :accept-assignment
                                     (list :assignment assignment
                                           :publication publication
                                           :decision-terms
                                           (rgp-assignment-decision-terms
                                            assignment
                                            (rgp-assignment-acceptance-posture
                                             assignment
                                             active-environment))
                                           :lifecycle lifecycle)
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :rgp-assignment-decision-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun command-rgp-reject-assignment-service (session assignment-id &key note environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment)))
    (multiple-value-bind (assignment publication lifecycle)
        (transition-environment-rgp-local-assignment session assignment-id :rejected
                                                     :note note
                                                     :environment active-environment)
      (make-service-command-response :rgp
                                     :reject-assignment
                                     (list :assignment assignment
                                           :publication publication
                                           :decision-terms
                                           (rgp-assignment-decision-terms
                                            assignment
                                            (rgp-assignment-acceptance-posture
                                             assignment
                                             active-environment))
                                           :lifecycle lifecycle)
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :rgp-assignment-decision-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun command-rgp-request-assignment-clarification-service (session assignment-id
                                                                  &key note environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment)))
    (multiple-value-bind (assignment publication lifecycle)
        (transition-environment-rgp-local-assignment session assignment-id :clarification-requested
                                                     :note note
                                                     :environment active-environment)
      (make-service-command-response :rgp
                                     :request-assignment-clarification
                                     (list :assignment assignment
                                           :publication publication
                                           :decision-terms
                                           (rgp-assignment-decision-terms
                                            assignment
                                            (rgp-assignment-acceptance-posture
                                             assignment
                                             active-environment))
                                           :lifecycle lifecycle)
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :rgp-assignment-decision-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun command-rgp-record-assignment-service (session &key assignment-id
                                                   rgp-work-id
                                                   operator-model
                                                   compensation-profile
                                                   evidence-profile
                                                   acceptance-state
                                                   billing-state
                                                   visibility-profile
                                                   linked-local-work-item-ids
                                                   linked-thread-id
                                                   linked-incident-ids
                                                   published-at
                                                   environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (record (upsert-environment-rgp-local-assignment
                  session
                  :assignment-id assignment-id
                  :rgp-work-id rgp-work-id
                  :operator-model operator-model
                  :compensation-profile compensation-profile
                  :evidence-profile evidence-profile
                  :acceptance-state acceptance-state
                  :billing-state billing-state
                  :visibility-profile visibility-profile
                  :linked-local-work-item-ids linked-local-work-item-ids
                  :linked-thread-id linked-thread-id
                  :linked-incident-ids linked-incident-ids
                  :published-at published-at
                  :environment active-environment)))
    (make-service-command-response :rgp
                                   :record-assignment
                                   (list :assignment record
                                         :assignment-count (length (environment-rgp-local-assignments
                                                                    active-environment)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-assignment-command-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun query-rgp-publications-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :publications
                                 (list :entries (environment-rgp-publication-backlog active-environment)
                                       :posture (environment-rgp-publication-posture active-environment))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-publication-backlog-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-rgp-mark-publication-service (session publication-id &key state
                                                  failure-reason
                                                  next-attempt-at
                                                  environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (publication (update-environment-rgp-publication-entry
                       session
                       publication-id
                       :state state
                       :published-at (when (eql state :published) (get-universal-time))
                       :next-attempt-at next-attempt-at
                       :failure-reason failure-reason
                       :environment active-environment)))
    (make-service-command-response :rgp
                                   :mark-publication
                                   publication
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-publication-command-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun command-rgp-retry-publication-service (session publication-id
                                                   &key next-attempt-at environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (publication (update-environment-rgp-publication-entry
                       session
                       publication-id
                       :state :retrying
                       :next-attempt-at next-attempt-at
                       :failure-reason nil
                       :environment active-environment)))
    (make-service-command-response :rgp
                                   :retry-publication
                                   publication
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-publication-command-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun query-rgp-artifacts-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :artifacts
                                 (environment-rgp-artifact-summaries active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-artifacts-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-rgp-approvals-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :approvals
                                 (mapcar (lambda (approval)
                                           (let ((approval-plist
                                                   (if (and (listp approval)
                                                            (= (length approval) 1)
                                                            (listp (first approval))
                                                            (keywordp (first (first approval))))
                                                       (first approval)
                                                       approval)))
                                             (append approval-plist
                                                   (list :execution-surface
                                                         (compact-execution-surface-summary
                                                          (primary-execution-surface-summary
                                                           session
                                                           (getf approval-plist :execution-handles)
                                                           :environment active-environment))))))
                                         (environment-rgp-approval-summaries active-environment
                                                                            session))
                                 :metadata (make-service-metadata :authority :environment
                                                                 :read-model :rgp-approvals-v1
                                                                 :session session
                                                                 :environment active-environment))))

(defun query-rgp-usage-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :usage
                                 (environment-rgp-usage-telemetry active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-usage-telemetry-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-rgp-facts-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :facts
                                 (environment-rgp-execution-facts active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-execution-facts-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-rgp-billing-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :billing
                                 (environment-rgp-billing-milestones active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-billing-milestones-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-rgp-record-usage-service (session &key provider
                                              model
                                              input-tokens
                                              output-tokens
                                              cached-tokens
                                              execution-seconds
                                              blocked-seconds
                                              tool-invocations
                                              artifact-count
                                              validation-effort
                                              environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (usage (record-environment-rgp-usage-telemetry
                 session
                 :provider provider
                 :model model
                 :input-tokens input-tokens
                 :output-tokens output-tokens
                 :cached-tokens cached-tokens
                 :execution-seconds execution-seconds
                 :blocked-seconds blocked-seconds
                 :tool-invocations tool-invocations
                 :artifact-count artifact-count
                 :validation-effort validation-effort
                 :environment active-environment)))
    (make-service-command-response :rgp
                                   :record-usage
                                   usage
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-usage-command-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun command-rgp-record-execution-fact-service (session &key assignment-id
                                                       fact-kind
                                                       status
                                                       note
                                                       artifact-count
                                                       checkpoint-count
                                                       validation-count
                                                       environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment)))
    (multiple-value-bind (fact publications)
        (record-environment-rgp-execution-fact
         session
         :assignment-id assignment-id
         :fact-kind fact-kind
         :status status
         :note note
         :artifact-count artifact-count
         :checkpoint-count checkpoint-count
         :validation-count validation-count
         :environment active-environment)
      (make-service-command-response :rgp
                                     :record-execution-fact
                                     (list :fact fact
                                           :publications publications)
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :rgp-execution-fact-command-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun command-rgp-record-billing-milestone-service (session &key assignment-id
                                                          milestone-kind
                                                          status
                                                          note
                                                          environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment)))
    (multiple-value-bind (milestone publications)
        (record-environment-rgp-billing-milestone
         session
         :assignment-id assignment-id
         :milestone-kind milestone-kind
         :status status
         :note note
         :environment active-environment)
      (make-service-command-response :rgp
                                     :record-billing-milestone
                                     (list :milestone milestone
                                           :publications publications)
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :rgp-billing-milestone-command-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun command-rgp-approve-service (session work-item-id policy &key reason environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (approval-response (command-request-work-item-approval-service session
                                                                        work-item-id
                                                                        policy
                                                                        :reason reason))
         (approval-metadata (service-response-metadata approval-response)))
    (actorize-rgp-command-response
     (make-service-command-response :rgp
                                    :approve
                                    (list :binding (rgp-binding-summary active-environment)
                                          :approval (getf (service-response-data approval-response) :wait)
                                          :work-item (getf (service-response-data approval-response) :work-item)
                                          :workflow-record (getf (service-response-data approval-response) :workflow-record))
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :rgp-command-v2
                                                                     :session session
                                                                     :environment active-environment
                                                                     :work-item-id work-item-id
                                                                     :policy-id policy))
     :actor-execution-job-id (getf approval-metadata :actor-execution-job-id)
     :governance-authority (or (getf approval-metadata :governance-authority) :actor-runtime)
     :policy-id (or (getf approval-metadata :policy-id) policy)
     :approval-required-p (getf approval-metadata :approval-required-p)
     :approval-granted-p (getf approval-metadata :approval-granted-p))))

(defun command-rgp-resume-service (session work-item-id &key note environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (resume-response (command-work-item-resume-service session
                                                            work-item-id
                                                            :note note))
         (resume-metadata (service-response-metadata resume-response)))
    (actorize-rgp-command-response
     (make-service-command-response :rgp
                                    :resume
                                    (list :binding (rgp-binding-summary active-environment)
                                          :approval (getf (service-response-data resume-response) :wait)
                                          :work-item (getf (service-response-data resume-response) :work-item)
                                          :actor-execution-job-id
                                          (or (getf (service-response-data resume-response) :actor-execution-job-id)
                                              (getf resume-metadata :actor-execution-job-id)))
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :rgp-command-v2
                                                                     :session session
                                                                     :environment active-environment
                                                                     :work-item-id work-item-id))
     :actor-execution-job-id (getf resume-metadata :actor-execution-job-id)
     :governance-authority (or (getf resume-metadata :governance-authority) :actor-runtime)
     :policy-id (getf resume-metadata :policy-id)
     :approval-required-p (getf resume-metadata :approval-required-p)
     :approval-granted-p (getf resume-metadata :approval-granted-p))))
