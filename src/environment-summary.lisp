(in-package #:sbcl-agent)

(defun environment-summary-count (primary fallback)
  (if (and (integerp primary) (not (minusp primary)))
      primary
      fallback))

(defun event-summary-kind-counts (events)
  (let ((counts '()))
    (dolist (event events)
      (let* ((kind (event-kind event))
             (existing (find kind counts
                             :key (lambda (entry) (getf entry :kind))
                             :test #'eq)))
        (if existing
            (incf (getf existing :count))
            (setf counts (append counts (list (list :kind kind :count 1)))))))
    counts))

(defun event-summary-family-counts (events)
  (let ((counts '()))
    (dolist (event events)
      (let* ((family (event-family event))
             (existing (find family counts
                             :key (lambda (entry) (getf entry :family))
                             :test #'eq)))
        (if existing
            (incf (getf existing :count))
            (setf counts (append counts (list (list :family family :count 1)))))))
    counts))

(defun recent-event-kinds (events &key (limit 8))
  (mapcar #'event-kind
          (let ((count (length events)))
            (if (> count limit)
                (subseq events (- count limit))
                events))))

(defun environment-event-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (events (or (environment-event-log active-environment) '()))
         (kind-counts (event-summary-kind-counts events))
         (family-counts (event-summary-family-counts events)))
    (list :event-count (length events)
          :kind-counts kind-counts
          :family-counts family-counts
          :recent-kinds (recent-event-kinds events)
          :provider-stream-count (or (getf (find :provider-stream kind-counts
                                                :key (lambda (entry) (getf entry :kind))
                                                :test #'eq)
                                           :count)
                                     0)
          :validation-count (or (getf (find :validation-completed kind-counts
                                            :key (lambda (entry) (getf entry :kind))
                                            :test #'eq)
                                       :count)
                                 0)
          :reconciliation-count (or (getf (find :reconciliation-created kind-counts
                                                :key (lambda (entry) (getf entry :kind))
                                                :test #'eq)
                                           :count)
                                     0)
          :incident-count (or (getf (find :incident-created kind-counts
                                          :key (lambda (entry) (getf entry :kind))
                                          :test #'eq)
                                     :count)
                              0)
          :workflow-transition-count (loop for entry in kind-counts
                                           when (member (getf entry :kind)
                                                        '(:workflow-record-created
                                                          :workflow-record-quarantined
                                                          :workflow-record-resumed
                                                          :workflow-record-closed
                                                          :work-item-created)
                                                        :test #'eq)
                                           sum (getf entry :count)))))

(defun limited-environment-summary-list (entries &key (limit 6))
  (subseq (or entries '()) 0 (min limit (length (or entries '())))))

(defun provider-profile-ready-p (profile)
  (or (getf profile :api-key-present-p)
      (eq (getf profile :locality) :local)
      (member (getf profile :provider)
              '("lm-studio" "ollama" "local")
              :test #'string-equal)))

(defun testing-harness-ready-p (entry)
  (let ((entrypoint (getf entry :entrypoint)))
    (and (stringp entrypoint)
         (> (length entrypoint) 0))))

(defun compatibility-app-ready-p (entry)
  (and (or (null (getf entry :enabled-p))
           (getf entry :enabled-p))
       (or (null (getf entry :health-status))
           (member (getf entry :health-status)
                   '(:healthy :ready :connected)
                   :test #'eq))))

(defun provider-route-viable-p (provider-profile)
  (and provider-profile
       (provider-profile-ready-p provider-profile)
       (or (eq (getf provider-profile :locality) :local)
           (getf provider-profile :api-base)
           (getf provider-profile :api-key-present-p))))

(defun capability-executable-readiness-summary (testing-harnesses compatibility-apps)
  (let* ((ready-harnesses (count-if #'testing-harness-ready-p testing-harnesses))
         (ready-apps (count-if #'compatibility-app-ready-p compatibility-apps)))
    (list :testing-harness-ready-count ready-harnesses
          :testing-harness-total-count (length testing-harnesses)
          :compatibility-app-ready-count ready-apps
          :compatibility-app-total-count (length compatibility-apps)
          :status (cond
                    ((and (= ready-harnesses (length testing-harnesses))
                          (= ready-apps (length compatibility-apps)))
                     :ready)
                    ((or (plusp ready-harnesses)
                         (plusp ready-apps))
                     :partial)
                    (t
                     :degraded)))))

(defun capability-provider-route-summary (provider-profile provider-profile-summary)
  (list :routing-mode (getf provider-profile-summary :routing-mode)
        :active-profile-name (getf provider-profile-summary :active-profile-name)
        :active-provider (and provider-profile
                              (getf provider-profile :provider))
        :locality (and provider-profile
                       (getf provider-profile :locality))
        :api-base-present-p (not (null (and provider-profile
                                            (getf provider-profile :api-base))))
        :api-key-present-p (not (null (and provider-profile
                                           (getf provider-profile :api-key-present-p))))
        :viable-p (provider-route-viable-p provider-profile)))

(defun environment-package-management-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (sessionish (environment-compatibility-session active-environment))
         (working-directory (and (compatibility-session-materialized-p sessionish)
                                 (agent-session-cwd sessionish))))
    (when (and working-directory
               (fboundp 'sbcl-agent.bootstrap:package-management-summary))
      (handler-case
          (sb-ext:with-timeout 1
            (sbcl-agent.bootstrap:package-management-summary
             :project-dir working-directory
             :working-directory working-directory))
        (sb-ext:timeout ()
          (list :status :timeout
                :qlot-available-p nil
                :managed-source-registry-entry-count 0))
        (error ()
          (list :status :unavailable
                :qlot-available-p nil
                :managed-source-registry-entry-count 0))))))

(defun capability-inventory-anomalies (runtime-summary active-profile
                                        testing-harnesses mcp-server-configs
                                        compatibility-apps package-management-summary)
  (let ((anomalies '()))
    (unless (getf runtime-summary :active-runtime-id)
      (push (list :kind :no-active-runtime
                  :severity :high
                  :statement "No active runtime is currently bound.") anomalies))
    (when (zerop (or (getf runtime-summary :loaded-system-count) 0))
      (push (list :kind :no-loaded-systems
                  :severity :medium
                  :statement "No loaded systems are currently visible in the runtime.") anomalies))
    (unless (provider-profile-ready-p active-profile)
      (push (list :kind :provider-not-ready
                  :severity :high
                  :statement "The active provider profile is missing readiness evidence, typically an API key or local runtime indicator.") anomalies))
    (when (null testing-harnesses)
      (push (list :kind :no-testing-harnesses
                  :severity :medium
                  :statement "No testing harness inventory is currently available.") anomalies))
    (dolist (entry testing-harnesses)
      (unless (testing-harness-ready-p entry)
        (push (list :kind :testing-harness-not-ready
                    :severity :medium
                    :harness-id (getf entry :id)
                    :statement "A testing harness is missing an executable entrypoint.") anomalies)))
    (dolist (entry mcp-server-configs)
      (unless (member (getf entry :health-status)
                      '(:healthy :ready :connected nil)
                      :test #'eq)
        (push (list :kind :mcp-server-degraded
                    :severity :medium
                    :server-id (getf entry :server-id)
                    :statement "An MCP server reports degraded or unknown health.") anomalies)))
    (dolist (entry compatibility-apps)
      (unless (compatibility-app-ready-p entry)
        (push (list :kind :compatibility-app-degraded
                    :severity :medium
                    :app-id (or (getf entry :app-id)
                                (getf entry :id))
                    :statement "A compatibility app is disabled or reports degraded health.") anomalies)))
    (when (and package-management-summary
               (null (getf package-management-summary :qlot-available-p)))
      (push (list :kind :missing-qlot
                  :severity :medium
                  :statement "Qlot is not currently available for managed Common Lisp dependency workflows.") anomalies))
    (when (and package-management-summary
               (zerop (or (getf package-management-summary :managed-source-registry-entry-count) 0)))
      (push (list :kind :empty-managed-source-registry
                  :severity :medium
                  :statement "The managed source registry currently has no configured entries.") anomalies))
    (nreverse anomalies)))

(defun capability-inventory-readiness-summary (runtime-summary active-profile
                                                testing-harnesses mcp-server-configs
                                                anomalies
                                                compatibility-apps)
  (let ((degraded-mcp-count (count-if (lambda (entry)
                                        (not (member (getf entry :health-status)
                                                     '(:healthy :ready :connected nil)
                                                     :test #'eq)))
                                      mcp-server-configs)))
    (list :runtime-ready-p (not (null (getf runtime-summary :active-runtime-id)))
          :provider-ready-p (provider-profile-ready-p active-profile)
          :testing-ready-p (not (null testing-harnesses))
          :mcp-ready-p (zerop degraded-mcp-count)
          :compatibility-app-ready-p (every #'compatibility-app-ready-p compatibility-apps)
          :anomaly-count (length anomalies)
          :status (cond
                    ((null anomalies) :ready)
                    ((some (lambda (entry)
                             (eq (getf entry :severity) :high))
                           anomalies)
                     :constrained)
                    (t
                     :degraded)))))

(defun environment-capability-inventory-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (runtime-summary (environment-runtime-domain-summary active-environment))
         (policy-state (or (environment-policy-state-snapshot active-environment) '()))
         (provider-profile (environment-provider-profile-summary active-environment))
         (active-provider-profile (or (getf provider-profile :active-profile)
                                      (find (getf provider-profile :active-profile-name)
                                            (or (getf provider-profile :profiles) '())
                                            :key (lambda (entry) (getf entry :name))
                                            :test #'equal)))
         (testing-harnesses (if (fboundp 'testing-harness-inventory)
                                (testing-harness-inventory)
                                '()))
         (mcp-server-configs (if (fboundp 'list-desktop-task-mcp-server-configs)
                                 (list-desktop-task-mcp-server-configs active-environment)
                                 '()))
         (compatibility-apps (or (environment-metadata-value active-environment :compatibility-apps)
                                 '()))
         (package-management-summary (environment-package-management-summary active-environment))
         (anomalies (capability-inventory-anomalies runtime-summary
                                                    active-provider-profile
                                                    testing-harnesses
                                                    mcp-server-configs
                                                    compatibility-apps
                                                    package-management-summary))
         (readiness-summary (capability-inventory-readiness-summary runtime-summary
                                                                    active-provider-profile
                                                                    testing-harnesses
                                                                    mcp-server-configs
                                                                    anomalies
                                                                    compatibility-apps))
         (provider-route-summary (capability-provider-route-summary active-provider-profile
                                                                    provider-profile))
         (executable-readiness (capability-executable-readiness-summary testing-harnesses
                                                                        compatibility-apps)))
    (list :active-runtime-id (environment-active-runtime-id active-environment)
          :runtime-count (length (environment-runtime-set active-environment))
          :loaded-system-count (or (getf runtime-summary :loaded-system-count) 0)
          :loaded-systems (limited-environment-summary-list
                           (or (getf runtime-summary :loaded-systems) '())
                           :limit 8)
          :approved-policy-count (length (or (getf policy-state :approved-policies) '()))
          :approved-policies (limited-environment-summary-list
                              (or (getf policy-state :approved-policies) '())
                              :limit 12)
          :capability-grant-count (length (or (getf policy-state :capability-grants) '()))
          :capability-grants (limited-environment-summary-list
                              (or (getf policy-state :capability-grants) '())
                              :limit 8)
         :provider-profile-count (or (getf provider-profile :profile-count) 0)
         :active-provider-profile (getf provider-profile :active-profile-name)
         :provider-route-summary provider-route-summary
         :package-management-summary
         (and package-management-summary
              (list :qlot-available-p (getf package-management-summary :qlot-available-p)
                    :managed-source-registry-entry-count
                    (or (getf package-management-summary :managed-source-registry-entry-count) 0)
                    :local-project-count
                    (or (getf package-management-summary :local-project-count) 0)))
         :provider-profiles (limited-environment-summary-list
                              (or (getf provider-profile :profiles) '())
                              :limit 4)
          :testing-harness-count (length testing-harnesses)
          :testing-harnesses (mapcar (lambda (entry)
                                       (list :id (getf entry :id)
                                             :label (getf entry :label)
                                             :kind (getf entry :kind)))
                                     (limited-environment-summary-list testing-harnesses :limit 6))
          :mcp-server-count (length mcp-server-configs)
          :mcp-servers (mapcar (lambda (entry)
                                 (list :server-id (getf entry :server-id)
                                       :transport (getf entry :transport)
                                       :capabilities (limited-environment-summary-list
                                                      (or (getf entry :capabilities) '())
                                                      :limit 6)
                                       :health-status (getf entry :health-status)))
                               (limited-environment-summary-list mcp-server-configs :limit 4))
          :compatibility-app-count (length compatibility-apps)
          :compatibility-apps (limited-environment-summary-list compatibility-apps :limit 6)
          :executable-readiness executable-readiness
          :missing-prerequisites
          (remove-if-not (lambda (entry)
                           (member (getf entry :kind)
                                   '(:provider-not-ready
                                     :no-active-runtime
                                     :missing-qlot
                                     :testing-harness-not-ready)
                                   :test #'eq))
                         anomalies)
          :dependency-anomalies
          (remove-if-not (lambda (entry)
                           (member (getf entry :kind)
                                   '(:missing-qlot
                                     :empty-managed-source-registry
                                     :no-loaded-systems)
                                   :test #'eq))
                         anomalies)
          :readiness-summary readiness-summary
          :anomalies anomalies)))

(defun environment-summary (&optional environment &rest options)
  (let ((include-alignment-state-p
          (if (member :include-alignment-state-p options :test #'eq)
              (getf options :include-alignment-state-p)
              t))
        (include-reconciliation-decision-p
          (if (member :include-reconciliation-decision-p options :test #'eq)
              (getf options :include-reconciliation-decision-p)
              t)))
  (let* ((active-environment (ensure-environment environment))
         (sessionish (environment-compatibility-session active-environment))
         (session (and (compatibility-session-materialized-p sessionish)
                       sessionish))
         (alignment-state (and include-alignment-state-p
                               session
                               (compute-alignment-state session)))
         (reconciliation-decision (and include-reconciliation-decision-p
                                       session
                                       (compute-reconciliation-decision session))))
    (let* ((runtime-state (environment-runtime-state active-environment))
           (agent-state (environment-agent-state-snapshot active-environment))
           (root-summary (environment-summaries active-environment))
           (conversation-summary (environment-conversation-domain-summary active-environment))
           (workflow-summary (environment-workflow-domain-summary active-environment))
           (agent-summary (and agent-state
                               (environment-agent-state-summaries agent-state)))
           (runtime-summary (environment-runtime-domain-summary active-environment)))
      (list :id (environment-id active-environment)
            :schema-version (environment-schema-version active-environment)
            :storage-root (environment-storage-root active-environment)
            :active-runtime-id (environment-active-runtime-id active-environment)
            :runtime-count (length (environment-runtime-set active-environment))
            :active-thread-id (environment-summary-active-thread-id active-environment)
            :thread-count (environment-summary-count
                           (getf conversation-summary :thread-count)
                           (length (environment-thread-set active-environment)))
            :artifact-count (environment-summary-count
                             (getf conversation-summary :artifact-count)
                             (environment-artifact-count active-environment))
            :work-item-count (environment-summary-count
                              (getf workflow-summary :work-item-count)
                              (length (environment-work-item-graph active-environment)))
            :agent-count (environment-summary-count
                          (getf agent-summary :agent-count)
                          (length (environment-agent-registry active-environment)))
            :event-count (length (environment-event-log active-environment))
            :runtime-state runtime-summary
            :runtime-history-count (length (if runtime-state
                                               (environment-runtime-history-snapshot active-environment)
                                               '()))
            :conversation-state conversation-summary
            :workflow-state workflow-summary
            :agent-state agent-summary
            :session-id (compatibility-session-id sessionish)
            :plan (or (and agent-state
                           (plan-display-value
                            (environment-agent-state-plan agent-state)))
                      (getf root-summary :plan))
            :active-plan-id (or (and agent-summary
                                     (getf agent-summary :active-plan-id))
                                (and agent-state
                                     (environment-agent-state-active-plan-id agent-state)))
            :plan-count (or (and agent-summary
                                 (getf agent-summary :plan-count))
                            (and agent-state
                                 (length (or (environment-agent-state-plans agent-state) '())))
                            0)
            :plan-summaries (or (and agent-summary
                                     (getf agent-summary :plan-summaries))
                                (and agent-state
                                     (environment-agent-state-plan-summaries agent-state))
                                '())
            :event-summary (environment-event-summary active-environment)
            :artifact-summary (or (environment-artifact-summary active-environment)
                                  (getf root-summary :artifact-summary))
            :agent-constitution (environment-agent-constitution active-environment)
            :capability-inventory (environment-capability-inventory-summary active-environment)
            :context-chat-project-selection (and session
                                                (context-chat-project-selection-summary session))
            :alignment-state alignment-state
            :reconciliation-decision reconciliation-decision
            :incident-count (or (getf agent-summary :incident-count)
                                (getf root-summary :incident-count))
            :incident-summary (or (getf agent-summary :incident-summary)
                                  (getf root-summary :incident-summary))
            :operator-status (getf root-summary :operator-status)
            :recovery-summary (environment-recovery-report active-environment)
            :provider-profile (environment-provider-profile-summary active-environment)
            :has-session-p (not (null (compatibility-session-id sessionish))))))))

(defun summarize-operator-blockers (operator-status)
  (let* ((blocked (append (or (getf operator-status :blocked-work-items) '())
                          (or (getf operator-status :quarantined-work-items) '()))))
    (list :count (length blocked)
          :approval-count (count :approval-required blocked :key (lambda (entry) (getf entry :why)) :test #'eq)
          :cold-validation-count (count :cold-validation-required blocked :key (lambda (entry) (getf entry :why)) :test #'eq)
          :pending-validation-count (count :pending-validation blocked :key (lambda (entry) (getf entry :why)) :test #'eq)
          :operator-review-count (count :operator-review-required blocked :key (lambda (entry) (getf entry :why)) :test #'eq)
          :items blocked)))

(defun environment-operator-evidence (summary)
  (let* ((operator-status (or (getf summary :operator-status) '()))
         (incident-summary (or (getf summary :incident-summary)
                               (list :count 0 :open-count 0 :recent '())))
         (event-summary (or (getf summary :event-summary)
                            (list :event-count 0 :recent-kinds '())))
         (alignment-state (or (getf summary :alignment-state) '()))
         (reconciliation-decision (or (getf summary :reconciliation-decision) '()))
         (blocked-summary (summarize-operator-blockers operator-status)))
    (list :posture (list :ready-count (getf operator-status :ready-count)
                         :blocked-count (getf operator-status :blocked-count)
                         :quarantined-count (getf operator-status :quarantined-count)
                         :image-only-count (getf operator-status :image-only-count)
                         :durable-count (getf operator-status :durable-count)
                         :incident-count (getf operator-status :incident-count)
                         :open-incident-count (getf operator-status :open-incident-count))
          :alignment alignment-state
          :reconciliation reconciliation-decision
          :blocked-work blocked-summary
          :incidents incident-summary
          :events event-summary)))

(defun environment-status (&optional environment &rest options)
  (let ((include-alignment-state-p
          (if (member :include-alignment-state-p options :test #'eq)
              (getf options :include-alignment-state-p)
              t))
        (include-reconciliation-decision-p
          (if (member :include-reconciliation-decision-p options :test #'eq)
              (getf options :include-reconciliation-decision-p)
              t)))
  (let* ((active-environment (ensure-environment environment))
         (summary (environment-summary active-environment
                                       :include-alignment-state-p include-alignment-state-p
                                       :include-reconciliation-decision-p include-reconciliation-decision-p))
         (operator-evidence (environment-operator-evidence summary))
         (operator-status (getf operator-evidence :posture))
         (active-thread (environment-active-thread-summary active-environment))
         (active-turn (environment-active-turn-summary active-environment))
         (blocked-summary (getf operator-evidence :blocked-work))
         (incident-summary (getf operator-evidence :incidents))
         (runtime-state (getf summary :runtime-state)))
    (list :environment (list :id (getf summary :id)
                             :schema-version (getf summary :schema-version)
                             :storage-root (getf summary :storage-root)
                             :has-session-p (getf summary :has-session-p))
          :active-thread active-thread
          :active-turn active-turn
          :active-runtime (list :runtime-id (getf summary :active-runtime-id)
                                :runtime-count (getf summary :runtime-count)
                                :package (getf runtime-state :package)
                                :loaded-system-count (or (getf runtime-state :loaded-system-count) 0)
                                :summary runtime-state)
          :blocked-work blocked-summary
          :incidents incident-summary
          :recovery (getf summary :recovery-summary)
          :provider-profile (getf summary :provider-profile)
          :alignment-state (getf summary :alignment-state)
          :reconciliation-decision (getf summary :reconciliation-decision)
          :operator-posture (append operator-status
                                    (list :outstanding-approval-count (getf blocked-summary :approval-count)
                                          :outstanding-cold-validation-count (getf blocked-summary :cold-validation-count)
                                          :outstanding-pending-validation-count (getf blocked-summary :pending-validation-count)
                                          :outstanding-operator-review-count (getf blocked-summary :operator-review-count)))
          :operator-evidence operator-evidence
          :summary summary))))
