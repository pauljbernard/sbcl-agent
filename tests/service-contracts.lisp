(in-package #:sbcl-agent/tests)

(defun service-envelope-helper-test ()
  (let ((response (sbcl-agent::make-service-query-response :environment
                                                           :status
                                                           '(:ok t)
                                                           :metadata '(:read-model :demo))))
    (assert-equal 1
                  (getf response :contract-version)
                  "service responses should carry a contract version")
    (assert-equal :environment
                  (getf response :domain)
                  "service responses should identify the domain")
    (assert-equal :query
                  (getf response :kind)
                  "query helpers should tag query responses")
    (assert-equal '(:ok t)
                  (sbcl-agent::service-response-data response)
                  "service-response-data should unwrap the data payload")
    (assert-equal '(:read-model :demo)
                  (sbcl-agent::service-response-metadata response)
                  "service-response-metadata should unwrap the metadata payload")))

(defun assert-service-metadata-shape (response message)
  (let* ((metadata (sbcl-agent::service-response-metadata response))
         (binding (getf metadata :binding)))
    (assert-equal :environment
                  (getf metadata :authority)
                  (format nil "~A should declare environment authority" message))
    (assert-true (listp binding)
                 (format nil "~A should include a binding object" message))
    (assert-true (member :session-id binding)
                 (format nil "~A should include binding session-id" message))
    (assert-true (member :environment-id binding)
                 (format nil "~A should include binding environment-id" message))))

(defun environment-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/environment-service-contract/"))
         (environment (sbcl-agent::ensure-environment)))
    (declare (ignore environment))
    (sbcl-agent::approve-policy session :runtime-package-switch)
    (sbcl-agent::command-runtime-set-package-service session "CL-USER")
    (let ((response (sbcl-agent::query-environment-status-service)))
      (assert-service-metadata-shape response "environment status service")
      (assert-equal :environment
                    (getf response :domain)
                    "environment status service should report the environment domain")
      (assert-equal :status
                    (getf response :operation)
                    "environment status service should identify the status operation")
      (assert-true (listp (sbcl-agent::service-response-data response))
                   "environment status service should return a plist payload")
      (assert-true (> (getf (getf (sbcl-agent::service-response-data response) :execution-surfaces)
                            :count)
                      0)
                   "environment status service should expose execution-backed surfaces")
      (assert-true (integerp (getf (getf (sbcl-agent::service-response-data response) :blocked-work-surfaces)
                                   :count))
                   "environment status service should expose compact blocked-work surface counts")
      (assert-true (integerp (getf (getf (sbcl-agent::service-response-data response) :approval-surfaces)
                                   :count))
                   "environment status service should expose compact approval surface counts")
      (assert-equal (sbcl-agent::environment-id sbcl-agent::*current-environment*)
                    (getf (getf response :metadata) :environment-id)
                    "environment status metadata should include the environment id"))))

(defun environment-desktop-preferences-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/environment-desktop-preferences-service-contract/"))
         (environment (sbcl-agent::ensure-environment))
         (preferences '(:theme-preference "dark"
                        :desktop-surface-view
                        (:conversation-text-scale-percent 145)
                        :conversation-draft "service contract draft")))
    (declare (ignore session))
    (let ((command-response
            (sbcl-agent::command-environment-set-desktop-preferences-service preferences environment)))
      (assert-service-metadata-shape command-response "environment desktop preferences command service")
      (assert-equal :environment
                    (getf command-response :domain)
                    "environment desktop preferences command service should report the environment domain")
      (assert-equal :set-desktop-preferences
                    (getf command-response :operation)
                    "environment desktop preferences command service should identify the set-desktop-preferences operation")
      (assert-equal :environment-desktop-preferences-v1
                    (getf (sbcl-agent::service-response-metadata command-response) :command-model)
                    "environment desktop preferences command service should declare the desktop preferences command model")
      (assert-equal "dark"
                    (getf (sbcl-agent::service-response-data command-response) :theme-preference)
                    "environment desktop preferences command service should echo the canonical theme preference"))
    (let ((query-response (sbcl-agent::query-environment-desktop-preferences-service environment)))
      (assert-service-metadata-shape query-response "environment desktop preferences query service")
      (assert-equal :desktop-preferences
                    (getf query-response :operation)
                    "environment desktop preferences query service should identify the desktop-preferences operation")
      (assert-equal :environment-desktop-preferences-v1
                    (getf (sbcl-agent::service-response-metadata query-response) :read-model)
                    "environment desktop preferences query service should declare the desktop preferences read model")
      (assert-equal 145
                    (getf (getf (sbcl-agent::service-response-data query-response) :desktop-surface-view)
                          :conversation-text-scale-percent)
                    "environment desktop preferences query service should preserve nested desktop surface values")
      (assert-equal "service contract draft"
                    (getf (sbcl-agent::service-response-data query-response) :conversation-draft)
                    "environment desktop preferences query service should preserve the conversation draft"))))

(defun environment-image-service-contract-test ()
  (let* ((root (make-temporary-directory "/tmp/environment-image-service-contract-XXXXXX"))
         (root-path (namestring root))
         (session (make-test-session :cwd root-path))
         (environment (sbcl-agent::ensure-environment)))
    (declare (ignore session))
    (let ((save-response
            (sbcl-agent::command-environment-save-image-service
             "contract-image"
             :environment environment)))
      (assert-service-metadata-shape save-response "environment image save command service")
      (assert-equal :save-image
                    (getf save-response :operation)
                    "environment image save command service should identify the save-image operation")
      (assert-equal :environment-image-command-v1
                    (getf (sbcl-agent::service-response-metadata save-response) :command-model)
                    "environment image save command service should declare the image command model")
      (assert-equal "contract-image"
                    (getf (getf (sbcl-agent::service-response-data save-response) :image) :name)
                    "environment image save command service should return the saved image name"))
    (let ((query-response (sbcl-agent::query-environment-image-registry-service environment)))
      (assert-service-metadata-shape query-response "environment image registry query service")
      (assert-equal :image-registry
                    (getf query-response :operation)
                    "environment image registry query service should identify the image-registry operation")
      (assert-equal :environment-image-registry-v1
                    (getf (sbcl-agent::service-response-metadata query-response) :read-model)
                    "environment image registry query service should declare the image registry read model")
      (assert-equal 1
                    (length (getf (sbcl-agent::service-response-data query-response) :images))
                    "environment image registry query service should surface the saved image list")))
  (let* ((root (make-temporary-directory "/tmp/environment-image-load-service-contract-XXXXXX"))
         (root-path (namestring root))
         (session (make-test-session :cwd root-path))
         (environment (sbcl-agent::ensure-environment)))
    (declare (ignore session))
    (sbcl-agent::command-environment-save-image-service "loadable-image" :environment environment)
    (let ((load-response
            (sbcl-agent::command-environment-load-image-service
             "loadable-image"
             environment)))
      (assert-service-metadata-shape load-response "environment image load command service")
      (assert-equal :load-image
                    (getf load-response :operation)
                    "environment image load command service should identify the load-image operation")
      (assert-equal "loadable-image"
                    (getf (sbcl-agent::service-response-data load-response) :image-name)
                    "environment image load command service should return the loaded image name")
      (assert-true (member (getf (getf (sbcl-agent::service-response-data load-response) :recovery-summary)
                                 :status)
                           '(:steady :recovering :degraded))
                   "environment image load command service should return an explicit recovery summary")
      (assert-true (listp (getf (getf (sbcl-agent::service-response-data load-response) :recovery-summary)
                                :runtime-replay))
                   "environment image load command service should surface runtime replay evidence"))))

(defun environment-provider-service-contract-test ()
  (let ((sbcl-agent::*current-environment* nil)
        (sbcl-agent::*current-session* nil))
    (let* ((root (make-temporary-directory "/tmp/environment-provider-service-contract-XXXXXX"))
           (root-path (namestring root))
           (session (make-test-session :cwd root-path))
           (environment (sbcl-agent::ensure-environment)))
      (sbcl-agent::bind-session-to-environment session environment)
      (sbcl-agent::ensure-environment-provider-profile
       :environment environment
       :config (sbcl-agent::make-config :provider "openai-compatible"
                                        :model "gpt-5"
                                        :working-directory root-path)
       :profile-name "default")
      (sbcl-agent::command-environment-provider-configure-service
       "local-fast"
       '(:provider "lm-studio"
         :model "qwen-coder"
         :fast-model "qwen-coder-mini"
         :api-base "http://localhost:1234/v1"
         :api-key "local-secret"
         :intents (:quick-turn :local-development :code-execution)
         :latency-tier :fast
         :execution-bias :high
         :locality :local)
       environment)
      (let ((provider-response (sbcl-agent::query-environment-provider-service environment)))
        (assert-service-metadata-shape provider-response "environment provider service")
        (assert-equal :environment
                      (getf provider-response :domain)
                      "environment provider service should report environment domain")
        (assert-equal :provider
                      (getf provider-response :operation)
                      "environment provider service should identify provider operation")
        (assert-equal :environment-provider-v1
                      (getf (sbcl-agent::service-response-metadata provider-response) :read-model)
                      "environment provider service should declare the provider read model")
        (assert-equal :auto
                      (getf (getf (sbcl-agent::service-response-data provider-response) :routing-policy) :mode)
                      "environment provider service should expose routing policy mode")
        (assert-equal '(:auto :manual)
                      (getf (getf (sbcl-agent::service-response-data provider-response) :routing-policy) :available-modes)
                      "environment provider service should expose supported routing modes")
        (let* ((profiles (getf (sbcl-agent::service-response-data provider-response) :profiles))
               (local-fast (find "local-fast"
                                 profiles
                                 :key (lambda (profile) (getf profile :name))
                                 :test #'string=))
               (raw-local-fast (sbcl-agent::environment-find-provider-profile environment "local-fast")))
          (assert-true (getf local-fast :api-key-present-p)
                       "environment provider service should expose token presence without exposing the raw secret")
          (assert-equal nil
                        (getf local-fast :api-key)
                        "environment provider service should redact raw provider tokens from public responses")
          (assert-equal nil
                        (getf raw-local-fast :api-key)
                        "environment provider profiles should no longer persist raw provider tokens in metadata")
          (assert-true (probe-file
                        (merge-pathnames #P"lm-studio-api-key.key"
                                         (uiop:ensure-directory-pathname root-path)))
                       "environment provider configuration should persist LM Studio tokens to the vendor key file")
          (assert-equal "local-secret"
                        (sbcl-agent::config-api-key
                         (sbcl-agent::provider-profile->config
                          raw-local-fast
                          (sbcl-agent::make-config :provider "lm-studio"
                                                   :model "qwen-coder"
                                                   :working-directory root-path)))
                        "provider profile config reconstruction should still preserve the stored token for runtime use")))
      (let ((routing-command (sbcl-agent::command-environment-provider-routing-service :manual environment)))
        (assert-service-metadata-shape routing-command "environment provider routing command service")
        (assert-equal :provider-routing
                      (getf routing-command :operation)
                      "environment provider routing command should identify provider-routing operation")
        (assert-equal :environment-provider-routing-command-v1
                      (getf (sbcl-agent::service-response-metadata routing-command) :command-model)
                      "environment provider routing command should declare the routing command model")
        (assert-equal :manual
                      (getf (getf (sbcl-agent::service-response-data routing-command) :routing-policy) :mode)
                      "environment provider routing command should update routing policy mode"))
      (sbcl-agent::command-environment-provider-routing-service :auto environment)
      (let* ((route (sbcl-agent::select-environment-provider-profile
                     "Use the local model and implement the fix"
                     :environment environment
                     :session session))
             (summary (sbcl-agent::record-environment-provider-route route environment)))
        (declare (ignore summary)))
      (let ((route-response (sbcl-agent::query-environment-provider-route-service environment)))
        (assert-service-metadata-shape route-response "environment provider route service")
        (assert-equal :provider-route
                      (getf route-response :operation)
                      "environment provider route service should identify provider-route operation")
        (assert-equal :environment-provider-route-v1
                      (getf (sbcl-agent::service-response-metadata route-response) :read-model)
                      "environment provider route service should declare the provider-route read model")
        (assert-equal :auto
                      (getf (getf (sbcl-agent::service-response-data route-response) :routing-policy) :mode)
                      "environment provider route service should project routing policy mode")
        (assert-equal "local-fast"
                      (getf (getf (sbcl-agent::service-response-data route-response) :last-route) :selected-profile-name)
                      "environment provider route service should expose the selected provider profile")
        (assert-true (consp (getf (getf (sbcl-agent::service-response-data route-response) :last-route)
                                  :candidate-rankings))
                     "environment provider route service should expose candidate rankings")
        (let ((last-route (getf (sbcl-agent::service-response-data route-response) :last-route)))
      (let ((preview-response (sbcl-agent::query-environment-provider-preview-service
                               "Use the local model and implement the fix"
                               :environment environment
                               :session session)))
        (assert-service-metadata-shape preview-response "environment provider preview service")
        (assert-equal :provider-preview
                      (getf preview-response :operation)
                      "environment provider preview service should identify provider-preview operation")
        (assert-equal :environment-provider-preview-v1
                      (getf (sbcl-agent::service-response-metadata preview-response) :read-model)
                      "environment provider preview service should declare the provider-preview read model")
        (assert-equal "local-fast"
                      (getf (sbcl-agent::service-response-data preview-response) :selected-profile-name)
                      "environment provider preview service should project the previewed selected profile")
        (assert-true (consp (getf (sbcl-agent::service-response-data preview-response) :candidate-rankings))
                     "environment provider preview service should expose candidate rankings")
        (assert-equal "local-fast"
                      (getf last-route :selected-profile-name)
                      "environment provider preview service should not mutate the last recorded route")))))))

(defun intent-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/intent-service-contract/"))
         (create-response
           (sbcl-agent::command-intent-create-service
            session
            :description "Keep runtime and intent continuously aligned"
            :scope '(:symbols ("SBCL-AGENT::RUN-CONVERSATION-TURN")
                     :systems ("sbcl-agent")
                     :workflows ("alignment-loop"))
            :constraints '((:invariant "runtime-is-authoritative")
                           (:policy "governed-mutation"))
            :expected-behaviors '("Observe runtime changes"
                                  "Recompute alignment continuously")
            :non-goals '("Treat code as the only source of truth")
            :priority :critical
            :version 1
            :status :active
            :linked-runtime-objects '("SBCL-AGENT::RUN-CONVERSATION-TURN")
            :linked-source-artifacts '("/Volumes/data/development/sbcl-agent/src/execution-service.lisp")
            :linked-event-ids '("event-1")
            :linked-mutation-ids '("mutation-1")
            :metadata '(:owner "cas"))))
    (assert-service-metadata-shape create-response "intent create service")
    (assert-equal :intent
                  (getf create-response :domain)
                  "intent create service should report the intent domain")
    (assert-equal :create
                  (getf create-response :operation)
                  "intent create service should identify the create operation")
    (assert-equal :intent-command-v1
                  (getf (sbcl-agent::service-response-metadata create-response) :command-model)
                  "intent create service should declare the intent command model")
    (let* ((created (sbcl-agent::service-response-data create-response))
           (intent-id (getf created :id))
           (list-response (sbcl-agent::query-intent-list-service session))
           (detail-response (sbcl-agent::query-intent-detail-service session intent-id))
           (update-response
             (sbcl-agent::command-intent-update-service
              session
              intent-id
              :description "Keep runtime, intent, and reconciliation continuously aligned"
              :status :evolving
              :version 2))
           (select-response (sbcl-agent::command-intent-select-service session intent-id)))
      (assert-true (stringp intent-id)
                   "intent create service should allocate a durable id")
      (assert-true (getf created :current-p)
                   "intent create service should select the created intent")
      (assert-equal :critical
                    (getf created :priority)
                    "intent create service should preserve priority")
      (assert-equal 1
                    (getf created :version)
                    "intent create service should preserve version")
      (assert-service-metadata-shape list-response "intent list service")
      (assert-equal :list
                    (getf list-response :operation)
                    "intent list service should identify the list operation")
      (assert-equal :intent-list-v1
                    (getf (sbcl-agent::service-response-metadata list-response) :read-model)
                    "intent list service should declare the intent list read model")
      (assert-equal intent-id
                    (getf (sbcl-agent::service-response-data list-response) :current-intent-id)
                    "intent list service should expose the selected current intent id")
      (assert-equal 1
                    (length (getf (sbcl-agent::service-response-data list-response) :intents))
                    "intent list service should return the created intent")
      (let ((trace-links (sbcl-agent::entity-trace-links session :intent intent-id)))
        (assert-true (>= (length trace-links) 4)
                     "intent creation should sync linked runtime, source, event, and mutation references into trace links"))
      (assert-service-metadata-shape detail-response "intent detail service")
      (assert-equal :detail
                    (getf detail-response :operation)
                    "intent detail service should identify the detail operation")
      (assert-equal :intent-detail-v1
                    (getf (sbcl-agent::service-response-metadata detail-response) :read-model)
                    "intent detail service should declare the intent detail read model")
      (assert-equal "Keep runtime and intent continuously aligned"
                    (getf (sbcl-agent::service-response-data detail-response) :description)
                    "intent detail service should preserve description")
      (assert-equal 1
                    (length (getf (getf (sbcl-agent::service-response-data detail-response) :scope)
                                  :systems))
                    "intent detail service should preserve scoped systems")
      (assert-service-metadata-shape update-response "intent update service")
      (assert-equal :update
                    (getf update-response :operation)
                    "intent update service should identify the update operation")
      (assert-equal :intent-command-v1
                    (getf (sbcl-agent::service-response-metadata update-response) :command-model)
                    "intent update service should declare the intent command model")
      (assert-equal :evolving
                    (getf (sbcl-agent::service-response-data update-response) :status)
                    "intent update service should persist updated status")
      (assert-equal 2
                    (getf (sbcl-agent::service-response-data update-response) :version)
                    "intent update service should persist updated version")
      (assert-true (find :description (getf (sbcl-agent::service-response-data update-response) :diff)
                         :key (lambda (entry) (getf entry :field)))
                   "intent update service should report description changes in the diff")
      (assert-true (find :status (getf (sbcl-agent::service-response-data update-response) :diff)
                         :key (lambda (entry) (getf entry :field)))
                   "intent update service should report status changes in the diff")
      (assert-service-metadata-shape select-response "intent select service")
      (assert-equal :select
                    (getf select-response :operation)
                    "intent select service should identify the select operation")
      (assert-true (getf (sbcl-agent::service-response-data select-response) :current-p)
                   "intent select service should mark the selected intent as current"))))

(defun reconciliation-correction-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/reconciliation-correction-service-contract/"))
         (thread (sbcl-agent::create-thread session :title "CAS correction"))
         (user-message (sbcl-agent::create-message session thread :user "reconcile the drift"))
         (turn (sbcl-agent::start-turn session thread user-message))
         (linked-event (sbcl-agent::append-session-event
                        session
                        :runtime-drift-detected
                        '(:status :observed)
                        :family :runtime
                        :entity-id "runtime-drift-1"
                        :thread-id (sbcl-agent::thread-id thread)
                        :turn-id (sbcl-agent::turn-id turn)))
         (_intent
           (sbcl-agent::create-intent-record
            session
            :description "Keep runtime behavior aligned with the approved contract."
            :scope '(:symbols ("SBCL-AGENT::RUN-CONVERSATION-TURN"))
            :constraints '((:policy "governance-required"))
            :expected-behaviors nil
            :status :deprecated
            :linked-event-ids (list (sbcl-agent::event-id linked-event))
            :linked-mutation-ids '("mutation-missing")))
         (response
           (sbcl-agent::command-materialize-reconciliation-correction-service
            session
            "Explain the alignment divergence and materialize the governed correction."
            :operator-mode :conversation))
         (payload (sbcl-agent::service-response-data response))
         (decision (getf payload :reconciliation-decision))
         (work-item (getf payload :work-item))
         (workflow-record (getf payload :workflow-record))
         (work-item-id (getf work-item :id))
         (_environment (sbcl-agent::bind-session-to-environment session))
         (session-summary (sbcl-agent::service-response-data
                           (sbcl-agent::query-session-summary-service session)))
         (approval-surface (getf (getf (getf session-summary :approval-surfaces) :top-surface)
                                 :corrective-context))
         (governance-queue (sbcl-agent::service-response-data
                            (sbcl-agent::query-shell-governance-queue-service session)))
         (queue-item (find work-item-id
                           (or (getf governance-queue :items) '())
                           :key #'(lambda (entry) (getf entry :work-item-id))
                           :test #'string=))
         (work-item-trace-links (getf (sbcl-agent::service-response-data
                                       (sbcl-agent::query-trace-link-list-service session
                                                                                  :entity-kind :work-item
                                                                                  :entity-id work-item-id))
                                      :trace-links))
         (intent-trace-links (getf (sbcl-agent::service-response-data
                                    (sbcl-agent::query-trace-link-list-service session
                                                                               :entity-kind :intent
                                                                               :entity-id (getf decision :intent-id)))
                                   :trace-links)))
    (declare (ignore _intent _environment))
    (assert-equal :alignment
                  (getf response :domain)
                  "reconciliation correction service should report the alignment domain")
    (assert-service-metadata-shape response "reconciliation correction service")
    (assert-equal :materialize-reconciliation-correction
                  (getf response :operation)
                  "reconciliation correction service should identify the materialization operation")
    (assert-equal :awaiting-approval
                  (getf response :status)
                  "governed corrective materialization should wait on approval when required")
    (assert-equal :awaiting-approval
                  (getf payload :outcome)
                  "governed corrective materialization should report awaiting approval outcome")
    (assert-equal :alignment-reconciliation-execute
                  (getf (sbcl-agent::service-response-metadata response) :policy-id)
                  "reconciliation correction service should expose the corrective execution policy")
    (assert-equal :awaiting-approval
                  (getf work-item :status)
                  "corrective work item should enter awaiting approval")
    (assert-equal :awaiting-approval
                  (getf workflow-record :status)
                  "corrective workflow record should enter awaiting approval")
    (assert-equal :governed-review
                  (getf decision :approval-posture)
                  "materialized corrective execution should preserve governed review posture")
    (assert-equal :alignment-reconciliation
                  (getf (getf work-item :corrective-context) :kind)
                  "corrective work item detail should expose alignment reconciliation context")
    (assert-equal :alignment-reconciliation
                  (getf approval-surface :kind)
                  "session approval surfaces should preserve corrective work context")
    (assert-equal :alignment-reconciliation
                  (getf (getf queue-item :corrective-context) :kind)
                  "shell governance queue should preserve corrective work context")
    (assert-true (find :triggered-corrective-work
                       work-item-trace-links
                       :key (lambda (entry) (getf entry :relation)))
                 "corrective work item should be trace-linked back to the triggering event")
    (assert-true (find :reconciled-by-work-item
                       intent-trace-links
                       :key (lambda (entry) (getf entry :relation)))
                 "intent should be trace-linked to the corrective work item")))

(defun continuous-alignment-event-loop-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/continuous-alignment-event-loop-service-contract/"))
         (_intent
           (sbcl-agent::create-intent-record
            session
            :description "Keep runtime behavior aligned with the approved contract."
            :scope '(:symbols ("SBCL-AGENT::RUN-CONVERSATION-TURN"))
            :constraints '((:policy "governance-required"))
            :expected-behaviors nil
            :status :deprecated
            :linked-event-ids '("event-missing")
            :linked-mutation-ids '("mutation-missing"))))
    (declare (ignore _intent))
    (sbcl-agent::append-session-event
     session
     :incident-created
     '(:kind :runtime-drift :summary "Observed drift requires governed reconciliation.")
     :family :incident
     :entity-id "incident-loop-1")
    (let* ((corrective-items
             (remove-if-not #'sbcl-agent::work-item-corrective-context
                            (sbcl-agent::agent-session-work-items session)))
           (first-corrective (first corrective-items)))
      (assert-equal 1
                    (length corrective-items)
                    "incident trigger should auto-materialize exactly one governed corrective work item")
      (assert-true first-corrective
                   "continuous alignment loop should materialize a corrective work item")
      (assert-equal :alignment-reconciliation
                    (getf (sbcl-agent::work-item-corrective-context first-corrective) :kind)
                    "auto-materialized work should preserve corrective context")
      (assert-equal :awaiting-approval
                    (sbcl-agent::work-item-status first-corrective)
                    "auto-materialized corrective work should enter governed approval")
      (assert-equal 1
                    (count :reconciliation-correction-created
                           (sbcl-agent::agent-session-events session)
                           :key #'sbcl-agent::event-kind)
                    "continuous alignment loop should emit a single corrective creation event"))
    (sbcl-agent::append-session-event
     session
     :validation-completed
     '(:work-item-id "validation-loop-1" :live (:status :failed) :cold (:status :failed))
     :family :workflow
     :entity-id "validation-loop-1"
     :work-item-id "validation-loop-1")
    (let ((corrective-items-after
            (remove-if-not #'sbcl-agent::work-item-corrective-context
                           (sbcl-agent::agent-session-work-items session))))
      (assert-equal 1
                    (length corrective-items-after)
                    "a second trigger should reuse actionable corrective work instead of duplicating it")
      (assert-equal 1
                    (count :reconciliation-correction-created
                           (sbcl-agent::agent-session-events session)
                           :key #'sbcl-agent::event-kind)
                    "deduped alignment loop should not emit an extra corrective creation event"))))

(defun continuous-alignment-event-loop-reopens-after-resolution-test ()
  (let* ((session (make-test-session :cwd "/tmp/continuous-alignment-event-loop-reopen/"))
         (_intent
           (sbcl-agent::create-intent-record
            session
            :description "Keep runtime behavior aligned with the approved contract."
            :scope '(:symbols ("SBCL-AGENT::RUN-CONVERSATION-TURN"))
            :constraints '((:policy "governance-required"))
            :expected-behaviors nil
            :status :deprecated
            :linked-event-ids '("event-missing")
            :linked-mutation-ids '("mutation-missing"))))
    (declare (ignore _intent))
    (sbcl-agent::append-session-event
     session
     :incident-created
     '(:kind :runtime-drift :summary "Observed drift requires governed reconciliation.")
     :family :incident
     :entity-id "incident-loop-reopen-1")
    (let* ((first-corrective
             (first (remove-if-not #'sbcl-agent::work-item-corrective-context
                                   (sbcl-agent::agent-session-work-items session)))))
      (assert-true first-corrective
                   "first trigger should materialize a corrective work item")
      (setf (sbcl-agent::work-item-status first-corrective) :committed
            (sbcl-agent::work-item-next-action first-corrective) nil
            (sbcl-agent::work-item-resume-payload first-corrective) nil
            (sbcl-agent::work-item-pending-validations first-corrective) nil))
    (sbcl-agent::append-session-event
     session
     :runtime-reloaded-file
     '(:path "/tmp/reloaded.lisp" :policy-id :runtime-reload)
     :family :runtime
     :entity-id "/tmp/reloaded.lisp")
    (let ((corrective-items
            (remove-if-not #'sbcl-agent::work-item-corrective-context
                           (sbcl-agent::agent-session-work-items session))))
      (assert-equal 2
                    (length corrective-items)
                    "a fresh trigger after resolution should materialize a new corrective work item")
      (assert-equal 2
                    (count :reconciliation-correction-created
                           (sbcl-agent::agent-session-events session)
                           :key #'sbcl-agent::event-kind)
                    "reopened alignment loop should emit a new corrective creation event after resolution"))))

(defun continuous-alignment-event-loop-requires-active-intent-test ()
  (let ((session (make-test-session :cwd "/tmp/continuous-alignment-event-loop-requires-intent/")))
    (sbcl-agent::append-session-event
     session
     :incident-created
     '(:kind :runtime-drift :summary "Observed drift without an active governed intent.")
     :family :incident
     :entity-id "incident-loop-no-intent-1")
    (assert-equal 0
                  (length (remove-if-not #'sbcl-agent::work-item-corrective-context
                                         (sbcl-agent::agent-session-work-items session)))
                  "continuous alignment loop should not auto-materialize corrective work without an active intent")
    (assert-equal 0
                  (count :reconciliation-correction-created
                         (sbcl-agent::agent-session-events session)
                         :key #'sbcl-agent::event-kind)
                  "continuous alignment loop should not emit corrective creation events without an active intent")))

(defun continuous-alignment-event-loop-approval-resume-lifecycle-test ()
  (let* ((session (make-test-session :cwd "/tmp/continuous-alignment-event-loop-approval-resume/"))
         (_intent
           (sbcl-agent::create-intent-record
            session
            :description "Keep runtime behavior aligned with the approved contract."
            :scope '(:symbols ("SBCL-AGENT::RUN-CONVERSATION-TURN"))
            :constraints '((:policy "governance-required"))
            :expected-behaviors nil
            :status :deprecated
            :linked-event-ids '("event-missing")
            :linked-mutation-ids '("mutation-missing"))))
    (sbcl-agent::append-session-event
     session
     :incident-created
     '(:kind :runtime-drift :summary "Observed drift requires governed reconciliation.")
     :family :incident
     :entity-id "incident-loop-approval-1")
    (let ((first-corrective
            (first (remove-if-not #'sbcl-agent::work-item-corrective-context
                                  (sbcl-agent::agent-session-work-items session)))))
      (assert-true first-corrective
                   "first trigger should materialize corrective work before approval")
      (assert-equal :awaiting-approval
                    (sbcl-agent::work-item-status first-corrective)
                    "first corrective item should await approval initially")
      (sbcl-agent::command-approve-policy-service
       session
       :alignment-reconciliation-execute)
      (sbcl-agent::resume-work-item session first-corrective :note "approved corrective execution")
      (assert-equal :resumed
                    (sbcl-agent::work-item-status first-corrective)
                    "approved corrective work should become resumed after resume")
      (sbcl-agent::append-session-event
       session
       :validation-completed
       '(:work-item-id "validation-loop-approval-1" :live (:status :failed) :cold (:status :failed))
       :family :workflow
       :entity-id "validation-loop-approval-1"
       :work-item-id "validation-loop-approval-1")
      (assert-equal 1
                    (length (remove-if-not #'sbcl-agent::work-item-corrective-context
                                           (sbcl-agent::agent-session-work-items session)))
                    "additional triggers should not duplicate an already resumed actionable corrective work item")
      (assert-equal 1
                    (count :reconciliation-correction-created
                           (sbcl-agent::agent-session-events session)
                           :key #'sbcl-agent::event-kind)
                    "resumed corrective work should suppress duplicate corrective creation events")
      (setf (sbcl-agent::work-item-status first-corrective) :committed
            (sbcl-agent::work-item-next-action first-corrective) nil
            (sbcl-agent::work-item-resume-payload first-corrective) nil
            (sbcl-agent::work-item-pending-validations first-corrective) nil)
      (sbcl-agent::append-session-event
       session
       :runtime-package-switched
       '(:package "SBCL-AGENT")
       :family :runtime
       :entity-id "package-switch-loop-approval-1")
      (assert-equal 2
                    (length (remove-if-not #'sbcl-agent::work-item-corrective-context
                                           (sbcl-agent::agent-session-work-items session)))
                    "a fresh trigger after approval and resolution should materialize a new corrective work item")
      (assert-equal 2
                    (count :reconciliation-correction-created
                           (sbcl-agent::agent-session-events session)
                           :key #'sbcl-agent::event-kind)
                    "a new trigger after approval and resolution should emit a second corrective creation event"))))

(defun continuous-alignment-event-loop-multi-reopen-lifecycle-test ()
  (let* ((session (make-test-session :cwd "/tmp/continuous-alignment-event-loop-multi-reopen/"))
         (_intent
           (sbcl-agent::create-intent-record
            session
            :description "Keep runtime behavior aligned with the approved contract."
            :scope '(:symbols ("SBCL-AGENT::RUN-CONVERSATION-TURN"))
            :constraints '((:policy "governance-required"))
            :expected-behaviors nil
            :status :deprecated
            :linked-event-ids '("event-missing")
            :linked-mutation-ids '("mutation-missing"))))
    (labels ((corrective-items ()
               (remove-if-not #'sbcl-agent::work-item-corrective-context
                              (sbcl-agent::agent-session-work-items session)))
             (latest-corrective-item ()
               (first (last (corrective-items))))
             (terminalize-corrective-item (work-item)
               (setf (sbcl-agent::work-item-status work-item) :committed
                     (sbcl-agent::work-item-next-action work-item) nil
                     (sbcl-agent::work-item-resume-payload work-item) nil
                     (sbcl-agent::work-item-pending-validations work-item) nil)))
      (sbcl-agent::append-session-event
       session
       :incident-created
       '(:kind :runtime-drift :summary "Observed drift requires governed reconciliation.")
       :family :incident
       :entity-id "incident-loop-multi-1")
      (let ((first-corrective (latest-corrective-item)))
        (assert-true first-corrective
                     "first trigger should materialize the first corrective work item")
        (sbcl-agent::command-approve-policy-service session :alignment-reconciliation-execute)
        (sbcl-agent::resume-work-item session first-corrective :note "approved first corrective execution")
        (sbcl-agent::append-session-event
         session
         :validation-completed
         '(:work-item-id "validation-loop-multi-1" :live (:status :failed) :cold (:status :failed))
         :family :workflow
         :entity-id "validation-loop-multi-1"
         :work-item-id "validation-loop-multi-1")
        (assert-equal 1
                      (length (corrective-items))
                      "while the first corrective item remains actionable, later events should not duplicate it")
        (terminalize-corrective-item first-corrective))
      (sbcl-agent::append-session-event
       session
       :runtime-package-switched
       '(:package "SBCL-AGENT")
       :family :runtime
       :entity-id "package-switch-loop-multi-1")
      (let* ((items-after-second-trigger (corrective-items))
             (second-corrective (latest-corrective-item)))
        (assert-equal 2
                      (length items-after-second-trigger)
                      "a later trigger after the first corrective item is resolved should materialize a second corrective item")
        (assert-true second-corrective
                     "second trigger should materialize a second corrective item")
        (assert-true (not (string= (sbcl-agent::work-item-id second-corrective)
                                   (sbcl-agent::work-item-id (first items-after-second-trigger))))
                     "the second corrective item should be distinct from the first")
        (sbcl-agent::command-approve-policy-service session :alignment-reconciliation-execute)
        (sbcl-agent::resume-work-item session second-corrective :note "approved second corrective execution")
        (sbcl-agent::append-session-event
         session
         :runtime-evaluated
         '(:form "(+ 21 21)" :package "CL-USER")
         :family :runtime
         :entity-id "runtime-eval-loop-multi-1")
        (assert-equal 2
                      (length (corrective-items))
                      "while the second corrective item remains actionable, another runtime event should still suppress duplication")
        (terminalize-corrective-item second-corrective))
      (sbcl-agent::append-session-event
       session
       :runtime-reloaded-file
       '(:path "/tmp/reloaded-multi.lisp" :policy-id :runtime-reload)
       :family :runtime
       :entity-id "/tmp/reloaded-multi.lisp")
      (assert-equal 3
                    (length (corrective-items))
                    "a third trigger after the second corrective item is resolved should materialize a third corrective item")
      (assert-equal 3
                    (count :reconciliation-correction-created
                           (sbcl-agent::agent-session-events session)
                           :key #'sbcl-agent::event-kind)
                    "each fresh reopen cycle should emit exactly one new corrective creation event"))))

(defun project-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/project-service-contract/"))
         (work-item (sbcl-agent::create-work-item session "Traceable testing surface" :transaction-scope :test))
         (incident (sbcl-agent::create-incident session
                                                :runtime-eval-failure
                                                "Project-linked incident"
                                                "Project detail should surface linked incident summaries."
                                                :work-item work-item))
         (project (sbcl-agent::create-project-record
                   session
                   :title "Project Atlas"
                   :summary "Unified SDLC program record."
                   :constitution '(:mission "Keep product intent, architecture, and execution aligned.")
                   :requirements
                   (list (sbcl-agent::make-project-requirement
                          :id "req-1"
                          :title "Traceable requirements"
                          :summary "Requirements must remain linked to work and tests."
                          :scope :project
                          :kind :functional
                          :priority :high
                          :status :accepted
                          :verification-kind :test-suite))
                   :feature-specifications
                   (list (sbcl-agent::make-project-feature-spec
                          :id "spec-1"
                          :title "Testing Surface"
                          :summary "Expose suites, runs, failures, coverage, and performance."
                          :status :planned
                          :acceptance-criteria '("surface suite inventory" "surface failures")
                          :linked-requirement-ids '("req-1")
                          :linked-journey-ids '("journey-1")))
                   :user-journeys
                   (list (sbcl-agent::make-project-user-journey
                          :id "journey-1"
                          :title "Close the loop"
                          :summary "Operator or agent moves from spec to runtime evidence."
                          :actors '("operator" "agent")
                          :entrypoints '("project" "testing")
                          :steps '("choose feature" "run tests" "inspect failures")
                          :outcomes '("feedback captured")
                          :edge-cases '("flaky suite")))
                   :architecture-decisions
                   (list (sbcl-agent::make-project-architecture-decision
                          :id "adr-1"
                          :title "Unified project record"
                          :status :accepted
                          :summary "Project intent must be stored alongside runtime evidence."
                          :drivers '("traceability")
                          :consequences '("stronger session model")
                          :stack-choices '("lisp-native project objects")
                          :linked-requirement-ids '("req-1")))
                   :linked-work-item-ids (list (sbcl-agent::work-item-id work-item))
                   :linked-incident-ids (list (sbcl-agent::incident-id incident))
                   :linked-testing-harness-ids '(:full-suite)
                   :metadata (list :testing-strategy
                                   '(:required-evidence ("coverage" "performance")
                                     :suite-expectations
                                     ((:harness-id :full-suite
                                       :purpose "governed regression"
                                       :evidence-kinds ("coverage" "performance"))))
                                   :release-readiness
                                   '(:stage "candidate"
                                     :signoff-status "pending"
                                     :required-approvers ("platform" "ops"))
                                   :readiness-obligations
                                   '((:id "obl-service-contract"
                                      :title "Record closure evidence"
                                      :summary "Service contract project should expose readiness obligations."
                                      :status :ready
                                      :blocking-p t
                                      :evidence-kinds ("coverage"))))
                   :source-roots '("/Volumes/data/development/sbcl-agent/")))
         (list-response (sbcl-agent::query-project-list-service session))
         (detail-response (sbcl-agent::query-project-detail-service
                           session
                           (sbcl-agent::project-record-id project))))
    (assert-service-metadata-shape list-response "project list service")
    (assert-equal :project
                  (getf list-response :domain)
                  "project list service should report the project domain")
    (assert-equal :list
                  (getf list-response :operation)
                  "project list service should identify the list operation")
    (assert-equal :project-list-v1
                  (getf (sbcl-agent::service-response-metadata list-response) :read-model)
                  "project list service should declare the project list read model")
    (assert-equal (sbcl-agent::project-record-id project)
                  (getf (sbcl-agent::service-response-data list-response) :current-project-id)
                  "project list service should expose the current selected project")
    (assert-equal 1
                  (length (getf (sbcl-agent::service-response-data list-response) :projects))
                  "project list service should expose project summaries")
    (assert-service-metadata-shape detail-response "project detail service")
    (assert-equal :detail
                  (getf detail-response :operation)
                  "project detail service should identify the detail operation")
    (assert-equal :project-detail-v1
                  (getf (sbcl-agent::service-response-metadata detail-response) :read-model)
                  "project detail service should declare the project detail read model")
    (assert-equal "Project Atlas"
                  (getf (sbcl-agent::service-response-data detail-response) :title)
                  "project detail service should expose the project title")
    (assert-equal 1
                  (length (getf (sbcl-agent::service-response-data detail-response) :requirements))
                  "project detail service should expose requirements")
    (assert-equal 1
                  (length (getf (sbcl-agent::service-response-data detail-response) :user-journeys))
                  "project detail service should expose journeys")
    (assert-equal 1
                  (length (getf (sbcl-agent::service-response-data detail-response) :architecture-decisions))
                  "project detail service should expose architecture decisions")
    (assert-equal (list (sbcl-agent::work-item-id work-item))
                  (getf (sbcl-agent::service-response-data detail-response) :linked-work-item-ids)
                  "project detail service should expose linked work-item ids")
    (assert-equal (list (sbcl-agent::incident-id incident))
                  (getf (sbcl-agent::service-response-data detail-response) :linked-incident-ids)
                  "project detail service should expose linked incident ids")
    (assert-equal '(:full-suite)
                  (getf (sbcl-agent::service-response-data detail-response) :linked-testing-harness-ids)
                  "project detail service should expose linked testing harness ids")
    (assert-equal 1
                  (length (getf (sbcl-agent::service-response-data detail-response) :linked-work-items))
                  "project detail service should expose linked work-item summaries")
    (assert-equal "Traceable testing surface"
                  (getf (first (getf (sbcl-agent::service-response-data detail-response) :linked-work-items)) :title)
                  "project detail service should summarize linked work-item titles")
    (assert-equal 1
                  (length (getf (sbcl-agent::service-response-data detail-response) :linked-incidents))
                  "project detail service should expose linked incident summaries")
    (assert-equal "Project-linked incident"
                  (getf (first (getf (sbcl-agent::service-response-data detail-response) :linked-incidents)) :title)
                  "project detail service should summarize linked incidents")
    (assert-equal 1
                  (length (getf (sbcl-agent::service-response-data detail-response) :linked-testing-harnesses))
                  "project detail service should expose linked testing harness summaries")
    (assert-equal :full-suite
                  (getf (first (getf (sbcl-agent::service-response-data detail-response) :linked-testing-harnesses)) :id)
                  "project detail service should summarize linked testing harness ids")
    (assert-true (listp (getf (getf (sbcl-agent::service-response-data detail-response) :testing-evidence)
                              :suite-statuses))
                 "project detail service should expose testing suite status summaries")
    (assert-equal :blocked
                  (getf (getf (getf (sbcl-agent::service-response-data detail-response) :testing-evidence)
                              :evidence-status)
                        :status)
                  "project detail service should summarize required testing evidence readiness")
    (assert-equal :blocked
                  (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary) :status)
                  "project detail service should expose project readiness summary status")
    (assert-equal :blocked
                  (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary)
                        :release-readiness-status)
                  "project detail service should surface blocked release readiness when signoff is pending")
    (assert-equal :blocked
                  (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary)
                        :release-review-state)
                  "project detail service should expose blocked release review state when closure blockers remain")
    (assert-equal :approved
                  (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary)
                        :release-target-phase)
                  "project detail service should expose the next release transition target")
    (assert-equal '("platform" "ops")
                  (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary)
                        :release-pending-approvers)
                  "project detail service should expose pending release approvers when signoff is incomplete")
    (assert-equal :ownership-pending
                  (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary)
                        :release-signoff-state)
                  "project detail service should expose ownership-pending signoff state when required approvers are not yet assigned")
    (assert-true (null (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary)
                             :release-signoff-ownership-ready-p))
                 "project detail service should mark signoff ownership incomplete when required approvers are not mapped to obligations")
    (assert-true (stringp (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary)
                                :release-signoff-summary))
                 "project detail service should expose signoff progression summary text")
    (assert-true (stringp (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary)
                                :release-transition-summary))
                 "project detail service should expose a release transition summary")
    (assert-equal "candidate"
                  (getf (getf (sbcl-agent::service-response-data detail-response) :release-readiness) :stage)
                  "project detail service should expose persisted release readiness records")
    (assert-true (listp (getf (sbcl-agent::service-response-data detail-response) :readiness-obligations))
                 "project detail service should expose persisted readiness obligations")
    (assert-true (listp (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary)
                              :release-next-actions))
                 "project detail service should expose derived release workflow next actions")
    (assert-true (listp (getf (getf (sbcl-agent::service-response-data detail-response) :readiness-summary)
                              :unmet-obligations))
                 "project detail service should expose project readiness obligations")
	    (assert-true (listp (getf (sbcl-agent::service-response-data detail-response) :alignment-state))
	                 "project detail service should expose project-scoped alignment state")
	    (assert-true (numberp (getf (getf (sbcl-agent::service-response-data detail-response) :alignment-state)
	                                :score))
	                 "project detail service should expose an alignment score")
	    (assert-true (listp (getf (sbcl-agent::service-response-data detail-response) :reconciliation-decision))
	                 "project detail service should expose a project-scoped reconciliation decision")
	    (assert-true (member (getf (getf (sbcl-agent::service-response-data detail-response) :reconciliation-decision)
	                               :decision)
	                         '(:maintain :runtime :intent :co-evolve))
	                 "project detail service should expose a valid reconciliation direction")
	    (assert-true (listp (getf (sbcl-agent::service-response-data detail-response) :trace-neighborhood))
	                 "project detail service should expose trace neighborhood data")))

(defun trace-link-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/trace-link-service-contract/"))
         (project (sbcl-agent::create-project-record session
                                                     :title "Trace Service Contract"
                                                     :summary "Trace contract regression."))
         (work-item (sbcl-agent::create-work-item session "Trace service work item")))
    (let ((command-response
            (sbcl-agent::command-trace-link-create-service
             session
             :relation :tracked-by-work-item
             :source-kind :project
             :source-id (sbcl-agent::project-record-id project)
             :target-kind :work-item
             :target-id (sbcl-agent::work-item-id work-item)
             :metadata '(:source :service-contract))))
      (assert-service-metadata-shape command-response "trace link command service")
      (assert-equal :trace
                    (getf command-response :domain)
                    "trace link command service should report the trace domain")
      (assert-equal :create-link
                    (getf command-response :operation)
                    "trace link command service should identify the create-link operation")
      (assert-equal :trace-link-command-v1
                    (getf (sbcl-agent::service-response-metadata command-response) :command-model)
                    "trace link command service should declare the trace command model")
      (assert-equal :tracked-by-work-item
                    (getf (sbcl-agent::service-response-data command-response) :relation)
                    "trace link command service should echo the created relation"))
    (let ((query-response
            (sbcl-agent::query-trace-neighborhood-service
             session
             :project
             (sbcl-agent::project-record-id project))))
      (assert-service-metadata-shape query-response "trace neighborhood query service")
      (assert-equal :neighborhood
                    (getf query-response :operation)
                    "trace neighborhood query service should identify the neighborhood operation")
      (assert-equal :trace-neighborhood-v1
                    (getf (sbcl-agent::service-response-metadata query-response) :read-model)
                    "trace neighborhood query service should declare the trace neighborhood read model")
      (assert-true (> (getf (sbcl-agent::service-response-data query-response) :count) 0)
                   "trace neighborhood query service should return linked evidence"))))

(defun project-command-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/project-command-service-contract/"))
         (work-item (sbcl-agent::create-work-item session "Bind project evidence" :transaction-scope :test))
         (create-response (sbcl-agent::command-project-create-service
                           session
                           :title "Project Atlas"
                           :summary "Project command service contract."
                           :source-roots '("/Volumes/data/development/sbcl-agent/")))
         (project-id (getf (sbcl-agent::service-response-data create-response) :id))
         (incident (sbcl-agent::create-incident session
                                                :runtime-eval-failure
                                                "Bound incident"
                                                "Bind this incident to the project."
                                                :work-item work-item)))
    (let* ((report-root (merge-pathnames #P"tmp/test-results/"
                                         (uiop:ensure-directory-pathname
                                          (uiop:getcwd))))
           (coverage-root (merge-pathnames #P"tmp/coverage/"
                                           (uiop:ensure-directory-pathname
                                            (uiop:getcwd))))
           (performance-root (merge-pathnames #P"tmp/performance/"
                                              (uiop:ensure-directory-pathname
                                               (uiop:getcwd))))
           (report-path (merge-pathnames #P"latest-report.json" report-root))
           (coverage-path (merge-pathnames #P"cover-index.html" coverage-root))
           (performance-path (merge-pathnames #P"latest.sexp" performance-root)))
      (ensure-directories-exist report-path)
      (ensure-directories-exist coverage-path)
      (ensure-directories-exist performance-path)
      (with-open-file (stream report-path
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write-string
         (sbcl-agent::emit-json
          (sbcl-agent::platform-json-safe-value
           '(:generatedAt 123456
             :suiteId "sbcl-agent"
             :summary (:total 3 :passed 3 :failed 0 :durationSeconds 1.5)
             :results ((:name "project-governance-smoke"
                        :category :service-contracts
                        :status :passed
                        :durationSeconds 0.5)
                       (:name "trace-link-smoke"
                        :category :service-contracts
                        :status :passed
                        :durationSeconds 0.5)
                       (:name "persistence-smoke"
                        :category :environment-and-persistence
                        :status :passed
                        :durationSeconds 0.5)))))
         stream))
      (with-open-file (stream coverage-path
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write-string "<html><body>coverage</body></html>" stream))
      (with-open-file (stream performance-path
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (let ((*print-circle* t)
              (*print-pretty* t))
          (write '(:generated-at 123456
                   :say-turn-latency (:avg-seconds 0.02 :min-seconds 0.01 :max-seconds 0.03 :count 3)
                   :environment-save-load (:save-seconds 0.03 :load-seconds 0.04 :total-seconds 0.07))
                 :stream stream))))
    (assert-service-metadata-shape create-response "project create service")
    (assert-equal :project
                  (getf create-response :domain)
                  "project create service should report the project domain")
    (assert-equal :create
                  (getf create-response :operation)
                  "project create service should identify the create operation")
    (assert-equal :project-command-v1
                  (getf (sbcl-agent::service-response-metadata create-response) :command-model)
                  "project create service should declare the project command model")
    (let ((constitution-response
            (sbcl-agent::command-project-constitution-service
             session
             '(:mission "Keep product and execution aligned."
               :principles ("governance-first" "traceability"))
             :project-id project-id)))
      (assert-equal :set-constitution
                    (getf constitution-response :operation)
                    "project constitution service should identify the constitution operation")
      (assert-equal "Keep product and execution aligned."
                    (getf (getf (sbcl-agent::service-response-data constitution-response) :constitution) :mission)
                    "project constitution service should update the project constitution"))
    (let ((design-system-response
            (sbcl-agent::command-project-design-system-service
             session
             '(:tokens ("surface-accent")
               :components ("metric-tile"))
             :project-id project-id)))
      (assert-equal :set-design-system
                    (getf design-system-response :operation)
                    "project design-system service should identify the design-system operation")
      (assert-equal '("surface-accent")
                    (getf (getf (sbcl-agent::service-response-data design-system-response) :design-system) :tokens)
                    "project design-system service should update design-system content"))
    (let ((style-guide-response
            (sbcl-agent::command-project-style-guide-service
             session
             '(:voice "direct"
               :rules ("no marketing copy"))
             :project-id project-id)))
      (assert-equal :set-style-guide
                    (getf style-guide-response :operation)
                    "project style-guide service should identify the style-guide operation")
      (assert-equal "direct"
                    (getf (getf (sbcl-agent::service-response-data style-guide-response) :style-guide) :voice)
                    "project style-guide service should update style-guide content"))
    (let ((testing-strategy-response
            (sbcl-agent::command-project-testing-strategy-service
             session
             '(:required-evidence ("coverage" "performance")
               :suite-expectations ((:harness-id :full-suite :purpose "core regression")))
             :project-id project-id)))
      (assert-equal :set-testing-strategy
                    (getf testing-strategy-response :operation)
                    "project testing-strategy service should identify the testing-strategy operation")
      (assert-equal '("coverage" "performance")
                    (getf (getf (sbcl-agent::service-response-data testing-strategy-response) :testing-strategy)
                          :required-evidence)
                    "project testing-strategy service should update testing-strategy content"))
    (let ((release-readiness-response
            (sbcl-agent::command-project-release-readiness-service
             session
             '(:stage "candidate"
               :signoff-status "pending"
               :target-window "2026-05-15"
               :required-approvers ("platform" "ops"))
             :project-id project-id)))
      (assert-equal :set-release-readiness
                    (getf release-readiness-response :operation)
                    "project release-readiness service should identify the release-readiness operation")
      (assert-equal "candidate"
                    (getf (getf (sbcl-agent::service-response-data release-readiness-response) :release-readiness)
                          :stage)
                    "project release-readiness service should update release-readiness content")
      (assert-equal :blocked
                    (getf (getf (sbcl-agent::service-response-data release-readiness-response) :readiness-summary)
                          :release-readiness-status)
                    "project release-readiness service should block closure when signoff is still pending")
      (assert-equal :blocked
                    (getf (getf (sbcl-agent::service-response-data release-readiness-response) :readiness-summary)
                          :release-review-state)
                    "project release-readiness service should surface blocked release review state when testing posture is still incomplete")
      (assert-equal :approved
                    (getf (getf (sbcl-agent::service-response-data release-readiness-response) :readiness-summary)
                          :release-target-phase)
                    "project release-readiness service should surface approved as the next target phase from a candidate release")
      (assert-equal '("platform" "ops")
                    (getf (getf (sbcl-agent::service-response-data release-readiness-response) :readiness-summary)
                          :release-pending-approvers)
                    "project release-readiness service should expose pending approvers when signoff remains incomplete")
      (assert-equal :ownership-pending
                    (getf (getf (sbcl-agent::service-response-data release-readiness-response) :readiness-summary)
                          :release-signoff-state)
                    "project release-readiness service should expose ownership-pending signoff state before approver obligations are assigned"))
    (let ((readiness-obligations-response
            (sbcl-agent::command-project-readiness-obligations-service
             session
             '((:id "obl-signoff"
                :title "Complete signoff"
                :summary "Approvers must complete signoff."
                :status "blocked"
                :blocking-p t
                :owner "ops"
                :evidence-kinds ("governed-approval")))
             :project-id project-id)))
      (assert-equal :set-readiness-obligations
                    (getf readiness-obligations-response :operation)
                    "project readiness-obligations service should identify the readiness-obligations operation")
      (assert-equal "Complete signoff"
                    (getf (first (getf (sbcl-agent::service-response-data readiness-obligations-response)
                                       :readiness-obligations))
                          :title)
                    "project readiness-obligations service should update readiness obligations"))
    (let ((requirement-response
            (sbcl-agent::command-project-requirement-service
             session
             :project-id project-id
             :title "Traceable Requirements"
             :summary "Requirements must remain linked to work and tests."
             :scope :project
             :priority :high
             :verification-kind :test-suite)))
      (assert-equal :append-requirement
                    (getf requirement-response :operation)
                    "project requirement service should identify the requirement operation")
      (assert-equal 1
                    (length (getf (sbcl-agent::service-response-data requirement-response) :requirements))
                    "project requirement service should append a requirement"))
    (let ((feature-response
            (sbcl-agent::command-project-feature-spec-service
             session
             :project-id project-id
             :title "Testing Surface"
             :summary "Expose test suites and failures."
             :acceptance-criteria '("show suites" "show failures"))))
      (assert-equal :append-feature-specification
                    (getf feature-response :operation)
                    "project feature-spec service should identify the feature-spec operation")
      (assert-equal 1
                    (length (getf (sbcl-agent::service-response-data feature-response) :feature-specifications))
                    "project feature-spec service should append a feature specification"))
    (let ((journey-response
            (sbcl-agent::command-project-user-journey-service
             session
             :project-id project-id
             :title "Close the loop"
             :summary "Move from spec to evidence."
             :actors '("operator" "agent")
             :steps '("review requirements" "run tests" "inspect failures"))))
      (assert-equal :append-user-journey
                    (getf journey-response :operation)
                    "project user-journey service should identify the journey operation")
      (assert-equal 1
                    (length (getf (sbcl-agent::service-response-data journey-response) :user-journeys))
                    "project user-journey service should append a user journey"))
    (let ((adr-response
            (sbcl-agent::command-project-architecture-decision-service
             session
             :project-id project-id
             :title "Environment-first model"
             :summary "The environment stays authoritative."
             :drivers '("traceability")
             :consequences '("strong environment model")
             :stack-choices '("sbcl" "electron"))))
      (assert-equal :append-architecture-decision
                    (getf adr-response :operation)
                    "project architecture-decision service should identify the ADR operation")
      (assert-equal 1
                    (length (getf (sbcl-agent::service-response-data adr-response) :architecture-decisions))
                    "project architecture-decision service should append an architecture decision"))
    (let ((work-item-response
            (sbcl-agent::command-project-bind-work-item-service
             session
             (sbcl-agent::work-item-id work-item)
             :project-id project-id)))
      (assert-equal :bind-work-item
                    (getf work-item-response :operation)
                    "project work-item binding service should identify the binding operation")
      (assert-equal 1
                    (length (getf (sbcl-agent::service-response-data work-item-response) :linked-work-item-ids))
                    "project work-item binding service should append a linked work item")
      (assert-equal "Bind project evidence"
                    (getf (first (getf (sbcl-agent::service-response-data work-item-response) :linked-work-items)) :title)
                    "project work-item binding service should surface linked work-item summaries"))
    (let ((incident-response
            (sbcl-agent::command-project-bind-incident-service
             session
             (sbcl-agent::incident-id incident)
             :project-id project-id)))
      (assert-equal :bind-incident
                    (getf incident-response :operation)
                    "project incident binding service should identify the binding operation")
      (assert-equal 1
                    (length (getf (sbcl-agent::service-response-data incident-response) :linked-incident-ids))
                    "project incident binding service should append a linked incident")
      (assert-equal "Bound incident"
                    (getf (first (getf (sbcl-agent::service-response-data incident-response) :linked-incidents)) :title)
                    "project incident binding service should surface linked incident summaries"))
    (let ((testing-response
            (sbcl-agent::command-project-bind-testing-harness-service
             session
             :full-suite
             :project-id project-id)))
      (assert-equal :bind-testing-harness
                    (getf testing-response :operation)
                    "project testing binding service should identify the binding operation")
      (assert-equal '(:full-suite)
                    (getf (sbcl-agent::service-response-data testing-response) :linked-testing-harness-ids)
                    "project testing binding service should append a linked harness")
      (assert-equal :full-suite
                    (getf (first (getf (sbcl-agent::service-response-data testing-response) :linked-testing-harnesses)) :id)
                    "project testing binding service should surface linked harness summaries"))
    (let ((source-root-response
            (sbcl-agent::command-project-source-root-service
             session
             "/Volumes/data/development/sbcl-agent-ux/"
             :project-id project-id)))
      (assert-equal :append-source-root
                    (getf source-root-response :operation)
                    "project source-root service should identify the source-root operation")
      (assert-equal 2
                    (length (getf (sbcl-agent::service-response-data source-root-response) :source-roots))
                    "project source-root service should append a managed source root"))
    (let ((quality-gate-response
            (sbcl-agent::command-project-quality-gate-service
             session
             :project-id project-id
             :title "Spec To Evidence"
             :summary "Requirements, work, incidents, testing, and source roots must all be attached."
             :required-harness-ids '(:full-suite)
             :minimum-linked-work-items 1
             :minimum-linked-incidents 1
             :require-source-roots-p t
             :required-trace-target-kinds '(:requirement :work-item :incident :testing-harness)
             :maximum-failed-tests 0
             :require-coverage-p t
             :maximum-say-turn-latency-seconds 0.05
             :maximum-environment-save-load-seconds 0.10
             :require-recovery-ready-p t)))
      (assert-equal :append-quality-gate
                    (getf quality-gate-response :operation)
                    "project quality-gate service should identify the quality-gate operation")
      (assert-equal 1
                    (length (getf (sbcl-agent::service-response-data quality-gate-response) :quality-gates))
                    "project quality-gate service should append a quality gate")
      (assert-equal :ready
                    (getf (getf (sbcl-agent::service-response-data quality-gate-response) :quality-gate-summary) :readiness)
                    "project quality-gate service should evaluate ready when all required evidence is present")
      (assert-equal t
                    (getf (first (getf (getf (sbcl-agent::service-response-data quality-gate-response) :quality-gate-summary) :gates))
                          :coverage-present-p)
                    "project quality-gate service should evaluate coverage evidence")
      (assert-equal t
                    (getf (first (getf (getf (sbcl-agent::service-response-data quality-gate-response) :quality-gate-summary) :gates))
                          :recovery-ready-p)
                    "project quality-gate service should evaluate recovery posture"))
    (let* ((report-root (merge-pathnames #P"tmp/test-results/"
                                         (uiop:ensure-directory-pathname
                                          (uiop:getcwd))))
           (coverage-root (merge-pathnames #P"tmp/coverage/"
                                           (uiop:ensure-directory-pathname
                                            (uiop:getcwd))))
           (performance-root (merge-pathnames #P"tmp/performance/"
                                              (uiop:ensure-directory-pathname
                                               (uiop:getcwd))))
           (report-path (merge-pathnames #P"latest-report.json" report-root))
           (coverage-path (merge-pathnames #P"cover-index.html" coverage-root))
           (performance-path (merge-pathnames #P"latest.sexp" performance-root)))
      (when (probe-file coverage-path)
        (delete-file coverage-path))
      (with-open-file (stream report-path
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write-string
         (sbcl-agent::emit-json
          (sbcl-agent::platform-json-safe-value
           '(:generatedAt 123457
             :suiteId "sbcl-agent"
             :summary (:total 2 :passed 1 :failed 1 :durationSeconds 1.0)
             :results ((:name "project-governance-smoke"
                        :category :service-contracts
                        :status :failed
                        :durationSeconds 0.5
                        :error "quality gate regression")
                       (:name "trace-link-smoke"
                        :category :service-contracts
                        :status :passed
                        :durationSeconds 0.5)))))
         stream))
      (with-open-file (stream performance-path
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (let ((*print-circle* t)
              (*print-pretty* t))
          (write '(:generated-at 123457
                   :say-turn-latency (:avg-seconds 0.08 :min-seconds 0.07 :max-seconds 0.09 :count 3)
                   :environment-save-load (:save-seconds 0.07 :load-seconds 0.08 :total-seconds 0.15))
                 :stream stream)))
      (let* ((blocked-response
               (sbcl-agent::command-project-quality-gate-service
                session
                :project-id project-id
                :title "Operational Readiness"
                :summary "Tests, coverage, performance, and recovery posture must all remain green."
                :maximum-failed-tests 0
                :require-coverage-p t
                :maximum-say-turn-latency-seconds 0.05
                :maximum-environment-save-load-seconds 0.10
                :require-recovery-ready-p t))
             (blocked-summary (getf (sbcl-agent::service-response-data blocked-response) :quality-gate-summary))
             (blocked-gate (second (getf blocked-summary :gates))))
        (assert-equal :blocked
                      (getf blocked-summary :readiness)
                      "project quality-gate service should block when testing and performance posture regresses")
        (assert-true (> (length (or (getf blocked-gate :unmet-conditions) '())) 0)
                     "project quality-gate service should report unmet conditions for blocked gates")))
    (let* ((second-project (sbcl-agent::create-project-record session :title "Secondary Project"))
           (select-response (sbcl-agent::command-project-select-service
                             session
                             (sbcl-agent::project-record-id second-project))))
      (assert-equal :select
                    (getf select-response :operation)
                    "project select service should identify the select operation")
      (assert-equal (sbcl-agent::project-record-id second-project)
                    (getf (sbcl-agent::service-response-data select-response) :id)
                    "project select service should switch the selected project"))))

(defun conversation-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/conversation-service-contract/")))
    (let ((create-response (sbcl-agent::command-conversation-create-thread-service session
                                                                                   :title "Service Thread")))
      (assert-service-metadata-shape create-response "conversation create-thread service")
      (assert-equal :conversation
                    (getf create-response :domain)
                    "conversation command should report the conversation domain")
      (assert-equal :command
                    (getf create-response :kind)
                    "create-thread should be modeled as a command")
      (assert-equal "Service Thread"
                    (getf (sbcl-agent::service-response-data create-response) :title)
                    "create-thread should return the created thread summary"))
    (let ((list-response (sbcl-agent::query-conversation-thread-list-service session)))
      (assert-service-metadata-shape list-response "conversation thread-list service")
      (assert-equal :thread-list
                    (getf list-response :operation)
                    "thread list should identify its query operation")
      (assert-true (>= (length (sbcl-agent::service-response-data list-response)) 1)
                   "thread list service should return at least one thread"))
    (let* ((provider (make-test-provider))
           (execution-response
             (sbcl-agent::command-conversation-execution-service
              session
              provider
              "Summarize the current conversation posture."
              '()
              :source :say
              :operator-mode :conversation))
           (turn-id (getf (getf (sbcl-agent::service-response-data execution-response) :turn) :id))
           (turn-response (sbcl-agent::query-conversation-turn-detail-service session turn-id))
           (turn-detail (sbcl-agent::service-response-data turn-response)))
      (assert-service-metadata-shape turn-response "conversation turn-detail service")
      (assert-true (member :primary-execution-handle turn-detail)
                   "turn detail should advertise the primary execution-handle field")
      (assert-true (consp (getf turn-detail :execution-handles))
                   "turn detail should advertise execution handles when a turn execution exists")
      (assert-equal "conversation"
                    (getf (getf turn-detail :execution-surface) :surface-kind)
                    "turn detail should expose the primary execution surface for the turn")
      (assert-equal (getf (sbcl-agent::service-response-metadata execution-response) :execution-id)
                    (getf (getf turn-detail :primary-execution-handle) :execution-id)
                    "turn detail should point back to the governing execution handle"))
    (let* ((input-attachments (list (list :attachment-id "upload-1"
                                          :name "notes.txt"
                                          :media-type "text/plain"
                                          :kind :text
                                          :source :input
                                          :summary "Operator notes"
                                          :text-content "hello from the operator")))
           (assistant-attachments (list (list :attachment-id "result-1"
                                              :name "diagram.png"
                                              :media-type "image/png"
                                              :kind :image
                                              :source :output
                                              :summary "Generated diagram"
                                              :data-url "data:image/png;base64,AA==")))
           (provider (make-instance 'attachment-echo-provider
                                    :response-attachments assistant-attachments))
           (execution-response
             (sbcl-agent::command-conversation-execution-service
              session
              provider
              "Review the uploaded notes and return a diagram."
              (list :attachments input-attachments)
              :source :say
              :operator-mode :conversation))
           (thread-id (getf (getf (sbcl-agent::service-response-data execution-response) :thread) :id))
           (thread-response (sbcl-agent::query-conversation-thread-detail-service session thread-id))
           (thread-detail (sbcl-agent::service-response-data thread-response))
           (messages (getf thread-detail :messages))
           (user-message (find :user messages :from-end t :key (lambda (message) (getf message :role))))
           (assistant-message (find :assistant messages :from-end t :key (lambda (message) (getf message :role))))
           (provider-request (attachment-echo-provider-last-request provider))
           (provider-request-attachments (sbcl-agent::provider-request-attachments provider-request)))
      (assert-equal 1
                    (length provider-request-attachments)
                    "conversation execution should forward uploaded attachments into the provider request")
      (assert-equal "notes.txt"
                    (getf (first provider-request-attachments) :name)
                    "provider requests should preserve uploaded attachment names")
      (assert-equal "notes.txt"
                    (getf (first (getf user-message :attachments)) :name)
                    "thread history should retain uploaded user attachments")
      (assert-equal "diagram.png"
                    (getf (first (getf assistant-message :attachments)) :name)
                    "thread history should retain assistant-returned attachments"))))

(defun runtime-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/runtime-service-contract/")))
    (sbcl-agent::ensure-environment)
    (let ((summary-response (sbcl-agent::query-runtime-summary-service session)))
      (assert-service-metadata-shape summary-response "runtime summary service")
      (assert-equal :runtime
                    (getf summary-response :domain)
                    "runtime summary service should report the runtime domain")
      (assert-equal :summary
                    (getf summary-response :operation)
                    "runtime summary service should identify the summary operation")
      (assert-true (stringp (getf (sbcl-agent::service-response-data summary-response) :package))
                   "runtime summary service should expose the active package"))
    (let ((history-response (sbcl-agent::query-runtime-history-service session :tail 1)))
      (assert-service-metadata-shape history-response "runtime history service")
      (assert-equal :history
                    (getf history-response :operation)
                    "runtime history service should identify the history operation")
      (assert-equal :runtime/history
                    (getf (sbcl-agent::service-response-data history-response) :tool)
                    "runtime history service should reuse the runtime history read model"))))

(defun calculator-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/calculator-service-contract/")))
    (sbcl-agent::ensure-environment)
    (let ((summary-response (sbcl-agent::query-calculator-summary-service session)))
      (assert-service-metadata-shape summary-response "calculator summary service")
      (assert-equal :calculator
                    (getf summary-response :domain)
                    "calculator summary service should report the calculator domain")
      (assert-equal :summary
                    (getf summary-response :operation)
                    "calculator summary service should identify the summary operation")
      (assert-true (member :scientific
                           (getf (sbcl-agent::service-response-data summary-response) :available-modes))
                   "calculator summary service should advertise scientific mode"))
    (let* ((basic-response (sbcl-agent::command-calculator-evaluate-service session "2 + 2"))
           (basic-data (sbcl-agent::service-response-data basic-response))
           (scientific-response
             (sbcl-agent::command-calculator-evaluate-service session
                                                              "sin(90)"
                                                              :mode :scientific
                                                              :angle-unit :degrees))
           (scientific-data (sbcl-agent::service-response-data scientific-response))
           (programmer-response
             (sbcl-agent::command-calculator-evaluate-service session
                                                              "0xF & 0x3"
                                                              :mode :programmer
                                                              :base 16
                                                              :word-size 16))
           (programmer-data (sbcl-agent::service-response-data programmer-response)))
      (assert-service-metadata-shape basic-response "calculator evaluate service")
      (assert-equal :evaluate
                    (getf basic-response :operation)
                    "calculator evaluate service should identify the evaluate operation")
      (assert-true (search "4" (getf basic-data :display-value))
                   "basic calculator evaluation should add decimal values")
      (assert-true (search "1" (getf scientific-data :display-value))
                   "scientific calculator evaluation should support degree-based trigonometry")
      (assert-equal "0x3"
                    (string-downcase (getf programmer-data :hexadecimal-value))
                    "programmer calculator evaluation should expose hexadecimal output"))))

(defun kernel-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/kernel-service-contract/")))
    (ensure-directories-exist "/tmp/kernel-service-contract/")
    (sbcl-agent::ensure-environment)
    (assert-signals-error
     (lambda ()
       (sbcl-agent::command-kernel-invoke-service session
                                                  "Mutate the runtime without approval."
                                                  :runtime/eval
                                                  :payload (list :form "(progn (defparameter sbcl-agent-user::*kernel-approval-probe* nil) (setf sbcl-agent-user::*kernel-approval-probe* :blocked))"
                                                                 :package "SBCL-AGENT-USER"
                                                                 :mutating t)))
     "Approval required for :RUNTIME-EVAL-MUTATE"
     "kernel invoke should enforce approval-required runtime mutation policy before dispatch")
    (sbcl-agent::approve-policy session :runtime-package-switch)
    (sbcl-agent::approve-policy session :runtime-eval-mutate)

    (let* ((runtime-command (sbcl-agent::command-runtime-set-package-service session "CL-USER"))
           (runtime-execution-id (getf (sbcl-agent::service-response-metadata runtime-command) :execution-id))
           (runtime-inspect (sbcl-agent::query-kernel-inspect-service session runtime-execution-id)))
      (assert-service-metadata-shape runtime-inspect "kernel inspect service")
      (assert-equal :kernel
                    (getf runtime-inspect :domain)
                    "kernel inspect service should report the kernel domain")
      (assert-equal :inspect
                    (getf runtime-inspect :operation)
                    "kernel inspect service should identify the inspect operation")
      (assert-equal :runtime
                    (getf (sbcl-agent::service-response-data runtime-inspect) :object-kind)
                    "kernel inspect should classify runtime executions explicitly")
      (assert-true (stringp (getf (getf (sbcl-agent::service-response-data runtime-inspect) :inspection) :package))
                   "kernel inspect should expose runtime summary data for runtime executions")
      (assert-equal :invoke
                    (getf (first (getf (getf (sbcl-agent::service-response-data runtime-inspect) :forensics)
                                       :lifecycle-history))
                          :event-kind)
                    "kernel inspect should expose generic lifecycle history for runtime executions")
      (assert-equal :execution-handle
                    (getf (sbcl-agent::service-response-data runtime-inspect) :resolved-via)
                    "kernel inspect should identify the execution-handle read path"))

    (let* ((provider-configure-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Configure a local provider profile."
                                                        "environment/provider-configure"
                                                        :payload (list :profile-name "kernel-local"
                                                                       :options '(:provider "lm-studio"
                                                                                  :model "qwen-coder"
                                                                                  :fast-model "qwen-mini"
                                                                                  :api-base "http://localhost:1234/v1"))))
           (provider-execution-id (getf (sbcl-agent::service-response-metadata provider-configure-response)
                                        :execution-id))
           (profiles (getf (sbcl-agent::service-response-data provider-configure-response) :profiles))
           (configured-profile (find "kernel-local"
                                     profiles
                                     :key (lambda (profile) (getf profile :name))
                                     :test #'string=)))
      (assert-true (stringp provider-execution-id)
                   "kernel invoke should assign an execution handle to provider configuration commands")
      (assert-equal "kernel-local"
                    (getf configured-profile :name)
                    "kernel invoke should dispatch environment/provider-configure through the environment provider service"))

    (let* ((rgp-bind-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Bind the governed runtime to RGP."
                                                        "rgp/bind"
                                                        :payload (list :request-id "kernel-rgp-req"
                                                                       :agent-session-id "kernel-rgp-session")))
           (rgp-bind-execution-id (getf (sbcl-agent::service-response-metadata rgp-bind-response)
                                        :execution-id)))
      (assert-true (stringp rgp-bind-execution-id)
                   "kernel invoke should assign an execution handle to rgp bind commands")
      (assert-equal "kernel-rgp-req"
                    (getf (getf (sbcl-agent::service-response-data rgp-bind-response) :binding) :request-id)
                    "kernel invoke should dispatch rgp/bind through the rgp bind service"))

    (let* ((task-enqueue-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Enqueue a filesystem read task."
                                                        "task/enqueue"
                                                        :payload (list :form '(tool :fs/read :path "src/main.lisp")
                                                                       :priority 2)))
           (task-execution-id (getf (sbcl-agent::service-response-metadata task-enqueue-response)
                                    :execution-id))
           (task-inspect (sbcl-agent::service-response-data
                          (sbcl-agent::query-kernel-inspect-service session task-execution-id))))
      (assert-true (stringp task-execution-id)
                   "kernel invoke should assign an execution handle to task enqueue commands")
      (assert-equal :task
                    (getf task-inspect :object-kind)
                    "kernel inspect should classify task enqueue executions as task objects"))

    (let* ((worker-start-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Start a worker."
                                                        "worker/start"
                                                        :provider (make-test-provider)))
           (worker-execution-id (getf (sbcl-agent::service-response-metadata worker-start-response)
                                      :execution-id))
           (worker-inspect (sbcl-agent::service-response-data
                            (sbcl-agent::query-kernel-inspect-service session worker-execution-id))))
      (assert-true (stringp worker-execution-id)
                   "kernel invoke should assign an execution handle to worker start commands")
      (assert-equal :worker
                    (getf worker-inspect :object-kind)
                    "kernel inspect should classify worker start executions as worker objects"))

    (let* ((authority-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Grant process-run authority."
                                                        "authority/grant"
                                                        :payload (list :policy :process-run)))
           (authority-execution-id (getf (sbcl-agent::service-response-metadata authority-response)
                                         :execution-id))
           (authority-inspect (sbcl-agent::service-response-data
                               (sbcl-agent::query-kernel-inspect-service session authority-execution-id))))
      (assert-true (stringp authority-execution-id)
                   "kernel invoke should assign an execution handle to authority grant commands")
      (assert-equal :execution
                    (getf authority-inspect :object-kind)
                    "kernel inspect should classify authority grants as generic execution objects when no more specific target exists"))

    (let* ((thread-create-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Create a kernel thread."
                                                        "conversation/create-thread"
                                                        :payload (list :title "Kernel Thread")))
           (thread-execution-id (getf (sbcl-agent::service-response-metadata thread-create-response)
                                      :execution-id))
           (thread-inspect (sbcl-agent::service-response-data
                            (sbcl-agent::query-kernel-inspect-service session thread-execution-id))))
      (assert-true (stringp thread-execution-id)
                   "kernel invoke should assign an execution handle to thread creation commands")
      (assert-equal :thread
                    (getf thread-inspect :object-kind)
                    "kernel inspect should resolve thread execution handles through the conversation target model"))

    (let* ((desktop-task-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Invoke a governed runtime desktop task through the kernel ingress."
                                                        "desktop-task/invoke"
                                                        :payload (list :requester :context-chat
                                                                       :target :runtime
                                                                       :operation :evaluate-form
                                                                       :payload '(:form "(+ 11 12)"
                                                                                  :package-name "SBCL-AGENT-USER"))))
           (desktop-task-data (sbcl-agent::service-response-data desktop-task-response))
           (desktop-task-record (getf desktop-task-data :task-record))
           (desktop-task-result (getf desktop-task-data :result))
           (desktop-task-execution-id
             (getf (sbcl-agent::service-response-metadata desktop-task-response)
                   :execution-id)))
      (assert-true (stringp desktop-task-execution-id)
                   "kernel invoke should assign an execution handle to desktop-task invoke commands")
      (assert-equal :invoke
                    (getf desktop-task-response :operation)
                    "desktop-task invoke should identify the invoke operation")
      (assert-equal :desktop-task
                    (getf desktop-task-response :domain)
                    "desktop-task invoke should report the desktop-task domain")
      (assert-equal :runtime-eval-safe
                    (getf (getf desktop-task-data :manifest) :capability)
                    "desktop-task invoke should resolve the governed manifest through the authoritative ingress")
      (assert-equal :evaluate-form
                    (getf (getf desktop-task-data :resolution) :operation)
                    "desktop-task invoke should surface the resolved desktop-task operation")
      (assert-equal 23
                    (or (getf desktop-task-result :result)
                        (first (or (getf desktop-task-result :values) '())))
                    "desktop-task invoke should execute the governed runtime task successfully")
      (assert-equal :completed
                    (getf desktop-task-record :status)
                    "desktop-task invoke should persist a completed governed desktop-task record")
      (assert-true (stringp (getf desktop-task-data :actor-execution-job-id))
                   "desktop-task invoke should surface the native actor execution handle directly")
      (assert-equal (getf desktop-task-data :actor-execution-job-id)
                    (getf desktop-task-record :actor-execution-job-id)
                    "desktop-task invoke should keep the record and response aligned on actor execution identity"))

    (let* ((session-save-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Save the session."
                                                        "session/save"
                                                        :payload (list :path "/tmp/kernel-session-save.sexp")))
           (session-save-execution-id (getf (sbcl-agent::service-response-metadata session-save-response)
                                            :execution-id)))
      (assert-true (stringp session-save-execution-id)
                   "kernel invoke should assign an execution handle to session save commands"))

    (let* ((session-load-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Load the session."
                                                        "session/load"
                                                        :payload (list :path "/tmp/kernel-session-save.sexp")))
           (session-load-payload (sbcl-agent::service-response-data session-load-response))
           (loaded-session (getf session-load-payload :session))
           (session-load-execution-id (getf (sbcl-agent::service-response-metadata session-load-response)
                                            :execution-id))
           (session-load-inspect (and loaded-session
                                      (sbcl-agent::service-response-data
                                       (sbcl-agent::query-kernel-inspect-service loaded-session
                                                                                 session-load-execution-id)))))
      (assert-true (stringp session-load-execution-id)
                   "kernel invoke should assign an execution handle to session load commands")
      (assert-equal "/tmp/kernel-session-save.sexp"
                    (getf session-load-payload :loaded)
                    "kernel invoke should preserve the loaded session path in the kernelized response")
      (assert-equal :execution
                    (getf session-load-inspect :object-kind)
                    "kernel inspect should expose session/load as a generic execution object"))

    (let* ((environment-save-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Save the environment."
                                                        "environment/save"
                                                        :payload (list :path "/tmp/kernel-environment-save.sexp")))
           (environment-save-execution-id (getf (sbcl-agent::service-response-metadata environment-save-response)
                                                :execution-id)))
      (assert-true (stringp environment-save-execution-id)
                   "kernel invoke should assign an execution handle to environment save commands"))

    (let* ((environment-load-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Load the environment."
                                                        "environment/load"
                                                        :payload (list :path "/tmp/kernel-environment-save.sexp")))
           (environment-load-payload (sbcl-agent::service-response-data environment-load-response))
           (loaded-session (getf environment-load-payload :session))
           (environment-load-execution-id (getf (sbcl-agent::service-response-metadata environment-load-response)
                                                :execution-id))
           (environment-load-inspect (and loaded-session
                                          (sbcl-agent::service-response-data
                                           (sbcl-agent::query-kernel-inspect-service loaded-session
                                                                                     environment-load-execution-id)))))
      (assert-true (stringp environment-load-execution-id)
                   "kernel invoke should assign an execution handle to environment load commands")
      (assert-equal "/tmp/kernel-environment-save.sexp"
                    (getf environment-load-payload :loaded)
                    "kernel invoke should preserve the loaded environment path in the kernelized response")
      (assert-equal :execution
                    (getf environment-load-inspect :object-kind)
                    "kernel inspect should expose environment/load as a generic execution object"))

    (sbcl-agent::approve-policy session :process-run)
    (let* ((proc-command (sbcl-agent::command-invoke-tool-service session :proc/run '(:argv ("/bin/echo" "compatibility"))))
           (proc-execution-id (getf (sbcl-agent::service-response-metadata proc-command) :execution-id))
           (proc-inspect (sbcl-agent::service-response-data
                          (sbcl-agent::query-kernel-inspect-service session proc-execution-id)))
           (compatibility-response (sbcl-agent::query-compatibility-executions-service session
                                                                                      :kind :host-process))
           (compatibility-list (sbcl-agent::service-response-data compatibility-response))
           (matching-entry (find proc-execution-id
                                 (getf compatibility-list :entries)
                                 :key (lambda (entry) (getf entry :execution-id))
                                 :test #'string=))
           (compatibility-target (getf (getf proc-inspect :target) :compatibility-execution)))
      (assert-equal :compatibility-execution
                    (getf proc-inspect :object-kind)
                    "kernel inspect should classify proc/run as a compatibility execution")
      (assert-equal :host-process
                    (getf (getf proc-inspect :inspection) :kind)
                    "kernel inspect should surface the compatibility execution kind")
      (assert-equal :completed
                    (getf (getf proc-inspect :inspection) :status)
                    "kernel inspect should classify synchronous proc/run compatibility execution as completed")
      (assert-equal :proc/run
                    (getf (getf proc-inspect :inspection) :tool-id)
                    "kernel inspect should preserve the compatibility tool identity")
      (assert-equal '("/bin/echo" "compatibility")
                    (getf (getf proc-inspect :inspection) :argv)
                    "kernel inspect should preserve compatibility execution argv")
      (assert-equal :host-process
                    (getf compatibility-target :kind)
                    "kernel execution target should persist compatibility metadata")
      (assert-equal :process-run
                    (getf compatibility-target :sandbox-profile)
                    "kernel execution target should persist compatibility sandbox posture")
      (assert-equal :host-process-sync
                    (getf compatibility-target :backend-adapter-id)
                    "kernel execution target should persist the backend adapter id for attached compatibility tools")
      (assert-equal :attached-host-process
                    (getf (getf compatibility-target :backend-profile) :runtime-class)
                    "kernel execution target should expose attached host-process runtime posture for proc/run")
      (assert-service-metadata-shape compatibility-response "compatibility executions service")
      (assert-equal :compatibility
                    (getf compatibility-response :domain)
                    "compatibility query should report the compatibility domain")
      (assert-equal :executions
                    (getf compatibility-response :operation)
                    "compatibility query should identify the executions operation")
      (assert-true (> (getf compatibility-list :count) 0)
                   "compatibility query should list hosted compatibility executions")
      (assert-true matching-entry
                   "compatibility query should include the created proc/run execution")
      (assert-equal :host-process
                    (getf matching-entry :kind)
                    "compatibility query should preserve execution kind for the matching execution")
      (assert-equal :completed
                    (getf matching-entry :status)
                    "compatibility query should expose completed lifecycle state for synchronous proc/run execution")
      (assert-equal nil
                    (getf (getf matching-entry :control-posture) :controllable-p)
                    "compatibility query should expose non-controllable posture for synchronous host-process execution")
      (assert-equal '()
                    (getf (getf matching-entry :control-posture) :supported-actions)
                    "compatibility query should expose an empty supported action list for synchronous host-process execution")
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-control-service session proc-execution-id :stop))
       "Compatibility execution is already terminal."
       "kernel control should explain why stop is unavailable for completed compatibility execution")
      (let* ((surface-response (sbcl-agent::query-execution-surfaces-service session))
             (surface-data (sbcl-agent::service-response-data surface-response))
             (matching-surface (find proc-execution-id
                                     (getf surface-data :items)
                                     :key (lambda (surface) (getf surface :execution-id))
                                     :test #'string=)))
        (assert-equal :surfaces
                      (getf surface-response :operation)
                      "kernel execution surfaces query should identify the surfaces operation")
        (assert-service-metadata-shape surface-response "kernel execution surfaces service")
        (assert-true (> (getf surface-data :count) 0)
                     "kernel execution surfaces query should return execution-backed surfaces")
        (assert-true matching-surface
                     "kernel execution surfaces query should include the compatibility execution surface")
        (assert-equal "compatibility"
                      (getf matching-surface :surface-kind)
                      "kernel execution surfaces query should classify compatibility surfaces explicitly")))

    (let* ((spawn-command (sbcl-agent::command-invoke-tool-service session :proc/spawn '(:argv ("/bin/sleep" "5"))))
           (spawn-execution-id (getf (sbcl-agent::service-response-metadata spawn-command) :execution-id))
           (spawn-inspect (sbcl-agent::service-response-data
                           (sbcl-agent::query-kernel-inspect-service session spawn-execution-id)))
           (spawn-detail (sbcl-agent::service-response-data
                          (sbcl-agent::query-compatibility-execution-detail-service session spawn-execution-id)))
           (spawn-stop (sbcl-agent::command-kernel-control-service session spawn-execution-id :stop))
           (spawn-stop-data (sbcl-agent::service-response-data spawn-stop)))
      (assert-equal :compatibility-execution
                    (getf spawn-inspect :object-kind)
                    "kernel inspect should classify proc/spawn as a compatibility execution")
      (assert-equal :running
                    (getf (getf spawn-inspect :inspection) :status)
                    "kernel inspect should expose running lifecycle state for spawned compatibility execution")
      (assert-equal :host-process-detached
                    (getf (getf spawn-inspect :inspection) :backend-adapter-id)
                    "kernel inspect should preserve the detached compatibility backend adapter id")
      (assert-equal :detached-host-process
                    (getf (getf (getf spawn-inspect :inspection) :backend-profile) :runtime-class)
                    "kernel inspect should expose detached host-process runtime posture for proc/spawn")
      (assert-true (member :stop
                           (getf (getf (getf spawn-inspect :inspection) :control-posture) :supported-actions))
                   "kernel inspect should expose stop support for spawned compatibility execution")
      (assert-equal :running
                    (getf (getf spawn-detail :lifecycle) :status)
                    "compatibility detail should expose running lifecycle state for spawned execution")
      (assert-equal t
                    (getf (getf spawn-detail :lifecycle) :control-token-live-p)
                    "compatibility detail should expose a live control token for spawned execution")
      (assert-true (integerp (getf (getf spawn-detail :lifecycle) :registered-at))
                   "compatibility detail should expose registration time for spawned execution")
      (assert-equal :accepted
                    (getf (getf spawn-stop-data :result) :status)
                    "kernel control should accept stop for spawned compatibility execution")
      (assert-equal :stopped
                    (getf (getf (getf spawn-stop-data :post-state) :inspection) :status)
                    "kernel control should project stopped post-state for spawned compatibility execution")
      (assert-equal :stop
                    (getf (getf (getf spawn-stop-data :post-state) :inspection) :last-control-action)
                    "kernel control should preserve the last compatibility control action in post-state")
      (assert-equal :stopped
                    (getf (getf (getf spawn-stop-data :post-state) :inspection) :last-observed-status)
                    "kernel control should preserve the last observed compatibility status in post-state")
      (assert-equal :stop
                    (getf (car (last (getf (getf spawn-stop-data :execution) :control-history)))
                          :action)
                    "kernel control should record generic control history for compatibility executions"))

    (sbcl-agent::approve-policy session :linux-app-launch)

    (let* ((linux-echo-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Launch a Linux echo app."
                                                        "linux.echo"
                                                        :payload (list :arguments '("linux-app"))))
           (linux-echo-execution-id (getf (sbcl-agent::service-response-metadata linux-echo-response)
                                          :execution-id))
           (linux-echo-inspect (sbcl-agent::service-response-data
                                (sbcl-agent::query-kernel-inspect-service session linux-echo-execution-id))))
      (assert-true (stringp linux-echo-execution-id)
                   "kernel invoke should assign an execution handle to linux app invocations")
      (assert-equal :compatibility-execution
                    (getf linux-echo-inspect :object-kind)
                    "kernel inspect should classify linux app invocations as compatibility executions")
      (assert-equal :linux-app
                    (getf (getf linux-echo-inspect :inspection) :kind)
                    "kernel inspect should classify linux.echo as a linux-app compatibility execution")
      (assert-equal "linux.echo"
                    (getf (getf linux-echo-inspect :inspection) :app-id)
                    "kernel inspect should preserve the linux app manifest id")
      (assert-equal :linux-app-launch
                    (getf (getf linux-echo-inspect :inspection) :policy-id)
                    "kernel inspect should preserve the linux app manifest policy id")
      (assert-equal :headless
                    (getf (getf linux-echo-inspect :inspection) :display-surface-kind)
                    "kernel inspect should preserve the linux app display surface contract")
      (assert-equal :none
                    (getf (getf linux-echo-inspect :inspection) :filesystem-scope-kind)
                    "kernel inspect should preserve the linux app filesystem scope contract")
      (assert-equal :host-process-sync
                    (getf (getf linux-echo-inspect :inspection) :backend-profile-id)
                    "kernel inspect should expose the declared runtime backend profile for attached linux apps")
      (assert-equal :sandbox-worker-process
                    (getf (getf (getf linux-echo-inspect :inspection) :backend-profile) :substrate-kind)
                    "kernel inspect should expose the backend substrate contract for attached linux apps")
      (assert-equal :sandbox-proc-runner
                    (getf (getf linux-echo-inspect :inspection) :backend-implementation)
                    "kernel inspect should expose the actual backend implementation used for attached linux apps")
      (assert-equal :completed
                    (getf (getf linux-echo-inspect :inspection) :status)
                    "kernel inspect should report attached linux app executions as completed when the backend exits cleanly")
      (assert-true (member :relaunch
                           (getf (getf (getf linux-echo-inspect :inspection) :control-posture)
                                 :supported-actions))
                   "kernel inspect should advertise relaunch for terminal linux app executions")
      (let* ((linux-echo-relaunch
               (sbcl-agent::command-kernel-control-service session
                                                          linux-echo-execution-id
                                                          :relaunch))
             (linux-echo-relaunch-data (sbcl-agent::service-response-data linux-echo-relaunch)))
        (assert-equal :accepted
                      (getf (getf linux-echo-relaunch-data :result) :status)
                      "kernel control should accept relaunch for terminal linux app executions")
        (assert-equal :linux-app
                      (getf (getf (getf linux-echo-relaunch-data :post-state) :inspection) :kind)
                      "kernel control relaunch should project the relaunched linux app execution")
        (assert-true (string/= linux-echo-execution-id
                               (getf (getf linux-echo-relaunch-data :execution) :execution-id))
                     "kernel control relaunch should return a new execution handle")))

    (let* ((linux-sleep-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Launch a Linux sleep app."
                                                        "linux.sleep"
                                                        :payload (list :arguments '("5"))))
           (linux-sleep-execution-id (getf (sbcl-agent::service-response-metadata linux-sleep-response)
                                           :execution-id))
           (linux-sleep-inspect (sbcl-agent::service-response-data
                                 (sbcl-agent::query-kernel-inspect-service session linux-sleep-execution-id)))
           (linux-sleep-stop (sbcl-agent::command-kernel-control-service session
                                                                         linux-sleep-execution-id
                                                                         :stop))
           (linux-sleep-stop-data (sbcl-agent::service-response-data linux-sleep-stop)))
      (assert-true (stringp linux-sleep-execution-id)
                   "kernel invoke should assign an execution handle to detached linux app invocations")
      (assert-equal :linux-app
                    (getf (getf linux-sleep-inspect :inspection) :kind)
                    "kernel inspect should classify linux.sleep as a linux-app compatibility execution")
      (assert-equal :running
                    (getf (getf linux-sleep-inspect :inspection) :status)
                    "kernel inspect should surface running lifecycle state for detached linux app executions")
      (assert-equal :host-process-detached
                    (getf (getf linux-sleep-inspect :inspection) :backend-profile-id)
                    "kernel inspect should expose the declared runtime backend profile for detached linux apps")
      (assert-equal :process-token
                    (getf (getf (getf linux-sleep-inspect :inspection) :backend-profile) :control-plane-kind)
                    "kernel inspect should expose runtime control-plane posture for detached linux apps")
      (assert-equal :sandbox-detached-process
                    (getf (getf linux-sleep-inspect :inspection) :backend-implementation)
                    "kernel inspect should expose the actual backend implementation used for detached linux apps")
      (assert-true (member :stop
                           (getf (getf (getf linux-sleep-inspect :inspection) :control-posture) :supported-actions))
                   "kernel inspect should advertise governed stop control for detached linux app executions")
      (assert-equal :accepted
                    (getf (getf linux-sleep-stop-data :result) :status)
                    "kernel control should accept stop for detached linux app executions")
      (assert-true (member :relaunch
                           (getf (getf (getf (getf linux-sleep-stop-data :post-state) :inspection)
                                       :control-posture)
                                 :supported-actions))
                   "kernel control post-state should advertise relaunch for terminal linux app executions")
      (let* ((linux-sleep-relaunch
               (sbcl-agent::command-kernel-control-service session
                                                          linux-sleep-execution-id
                                                          :relaunch))
             (linux-sleep-relaunch-data (sbcl-agent::service-response-data linux-sleep-relaunch)))
        (assert-equal :accepted
                      (getf (getf linux-sleep-relaunch-data :result) :status)
                      "kernel control should accept relaunch for terminal linux app executions")
        (assert-equal :linux-app
                      (getf (getf (getf linux-sleep-relaunch-data :post-state) :inspection) :kind)
                      "kernel control relaunch should project the relaunched linux app execution")))

    (let* ((apps-response (sbcl-agent::query-compatibility-apps-service))
           (apps-data (sbcl-agent::service-response-data apps-response))
           (vscode-response (sbcl-agent::query-compatibility-apps-service :app-id "linux.vscode"))
           (vscode-data (sbcl-agent::service-response-data vscode-response))
           (vscode-entry (first (getf vscode-data :entries)))
           (managed-response (sbcl-agent::query-compatibility-apps-service :app-id "linux.intent-demo"))
           (managed-entry (first (getf (sbcl-agent::service-response-data managed-response) :entries))))
      (assert-equal :compatibility
                    (getf apps-response :domain)
                    "compatibility apps query should report the compatibility domain")
      (assert-equal :apps
                    (getf apps-response :operation)
                    "compatibility apps query should identify the apps operation")
      (assert-true (> (getf apps-data :count) 0)
                   "compatibility apps query should expose registered linux app manifests")
      (assert-equal "linux.vscode"
                    (getf vscode-entry :id)
                    "compatibility apps query should expose specific manifest selection")
      (assert-equal :linux-ide-launch
                    (getf vscode-entry :policy-id)
                    "compatibility apps query should expose the manifest policy contract")
      (assert-equal :proc/spawn
                    (getf vscode-entry :launch-tool-id)
                    "compatibility apps query should preserve launch backend identity")
      (assert-equal :desktop-app-bridge
                    (getf vscode-entry :backend-profile-id)
                    "compatibility apps query should expose the manifest runtime backend profile")
      (assert-equal :desktop-window
                    (getf (getf vscode-entry :backend-profile) :display-bridge-kind)
                    "compatibility apps query should expose the manifest display bridge contract")
      (assert-equal :desktop-session
                    (getf (getf vscode-entry :backend-profile) :control-plane-kind)
                    "compatibility apps query should expose a distinct desktop-session control plane for bridged apps")
      (assert-equal :desktop-bridge
                    (getf (getf vscode-entry :backend-profile) :runtime-class)
                    "compatibility apps query should expose desktop-bridge runtime posture for display-bearing Linux apps")
      (assert-equal :session-workspace
                    (getf vscode-entry :filesystem-scope-kind)
                    "compatibility apps query should expose per-manifest filesystem scope")
      (assert-equal :client
                    (getf vscode-entry :network-policy)
                    "compatibility apps query should expose per-manifest network policy")
      (assert-equal :desktop-window
                    (getf vscode-entry :display-surface-kind)
                    "compatibility apps query should expose per-manifest display surface contract")
      (assert-equal t
                    (getf vscode-entry :workspace-write-p)
                    "compatibility apps query should expose per-manifest workspace write posture")
      (assert-equal "linux.intent-demo"
                    (getf managed-entry :id)
                    "compatibility apps query should expose managed desktop surface manifests")
      (assert-equal :managed-desktop-surface
                    (getf managed-entry :backend-profile-id)
                    "compatibility apps query should expose a non-host-process backend profile")
      (assert-equal :managed-desktop-surface
                    (getf (getf managed-entry :backend-profile) :runtime-class)
                    "compatibility apps query should expose managed runtime posture for non-host-process display apps")
      (assert-equal :governed-desktop-surface
                    (getf (getf managed-entry :backend-profile) :substrate-kind)
                    "compatibility apps query should expose a governed desktop substrate for non-host-process display apps")
      (assert-equal nil
                    (getf (getf managed-entry :backend-profile) :host-process-p)
                    "compatibility apps query should distinguish managed desktop surfaces from host-process backends"))

    (let* ((managed-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Launch a managed Linux app surface."
                                                        "linux.intent-demo"))
           (managed-execution-id (getf (sbcl-agent::service-response-metadata managed-response)
                                       :execution-id))
           (managed-inspect (sbcl-agent::service-response-data
                             (sbcl-agent::query-kernel-inspect-service session managed-execution-id)))
           (managed-stop (sbcl-agent::command-kernel-control-service session
                                                                    managed-execution-id
                                                                    :stop))
           (managed-stop-data (sbcl-agent::service-response-data managed-stop)))
      (assert-true (stringp managed-execution-id)
                   "kernel invoke should assign an execution handle to managed desktop surface app launches")
      (assert-equal :linux-app
                    (getf (getf managed-inspect :inspection) :kind)
                    "kernel inspect should classify managed desktop surface launches as linux-app compatibility executions")
      (assert-equal :managed-desktop-surface
                    (getf (getf managed-inspect :inspection) :backend-profile-id)
                    "kernel inspect should expose the managed desktop surface backend profile")
      (assert-equal :managed-desktop-surface
                    (getf (getf (getf managed-inspect :inspection) :backend-profile) :runtime-class)
                    "kernel inspect should expose managed runtime posture for non-host-process display apps")
      (assert-equal :managed-desktop-surface
                    (getf (getf managed-inspect :inspection) :backend-implementation)
                    "kernel inspect should expose the managed desktop surface implementation")
      (assert-equal :running
                    (getf (getf managed-inspect :inspection) :status)
                    "kernel inspect should surface managed desktop surfaces as running governed executions")
      (assert-equal :desktop-window
                    (getf (getf managed-inspect :inspection) :display-surface-kind)
                    "kernel inspect should preserve the managed desktop surface display contract")
      (assert-equal :accepted
                    (getf (getf managed-stop-data :result) :status)
                    "kernel control should accept stop for managed desktop surface executions")
      (assert-equal :stopped
                    (getf (getf (getf managed-stop-data :post-state) :inspection) :status)
                    "kernel control post-state should preserve the stopped managed desktop surface status")
      (assert-true (member :relaunch
                           (getf (getf (getf (getf managed-stop-data :post-state) :inspection)
                                       :control-posture)
                                 :supported-actions))
                   "kernel control post-state should advertise relaunch for terminal managed desktop surface executions"))

    (let* ((linux-echo-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Launch another Linux echo app."
                                                        "linux.echo"
                                                        :payload (list :arguments '("counted"))))
           (linux-echo-execution-id (getf (sbcl-agent::service-response-metadata linux-echo-response)
                                          :execution-id))
           (apps-response (sbcl-agent::query-compatibility-apps-service :app-id "linux.echo"
                                                                        :session session))
           (apps-entry (first (getf (sbcl-agent::service-response-data apps-response) :entries))))
      (assert-true (stringp linux-echo-execution-id)
                   "kernel invoke should still assign an execution handle to repeated linux app launches")
      (assert-true (> (getf apps-entry :execution-count) 0)
                   "compatibility apps query should expose execution counts for launched apps")
      (assert-true (find linux-echo-execution-id
                         (getf apps-entry :recent-executions)
                         :key (lambda (entry) (getf entry :execution-id))
                         :test #'string=)
                   "compatibility apps query should expose recent executions for launched apps"))

    (let* ((display-package-path "/tmp/linux-app-display-bridge.aop"))
      (sbcl-agent::command-platform-package-service display-package-path
                                                   :package-id "display-kit"
                                                   :package-version "1.0.0"
                                                   :title "Display Kit"
                                                   :capability-ids '(:proc/run)
                                                   :session session)
      (rewrite-platform-package-app-display-surface-kind display-package-path
                                                         "linux.echo"
                                                         :desktop-window
                                                         :backend-profile-id :desktop-app-bridge)
      (sbcl-agent::command-platform-import-package-service display-package-path
                                                           :session session)
      (sbcl-agent::command-platform-activate-package-service "display-kit"
                                                             :session session)
      (let* ((display-launch-response
               (sbcl-agent::command-kernel-invoke-service session
                                                          "Launch a display-bearing linux echo app."
                                                          "linux.echo"
                                                          :payload (list :arguments '("display-bridge"))))
             (display-execution-id (getf (sbcl-agent::service-response-metadata display-launch-response)
                                         :execution-id))
             (display-surfaces-response
               (sbcl-agent::query-compatibility-display-surfaces-service session
                                                                         :app-id "linux.echo"))
             (display-surfaces-data (sbcl-agent::service-response-data display-surfaces-response))
             (display-entry (find display-execution-id
                                  (getf display-surfaces-data :entries)
                                  :key (lambda (entry) (getf entry :execution-id))
                                  :test #'string=)))
        (assert-equal :display-surfaces
                      (getf display-surfaces-response :operation)
                      "compatibility display surface query should identify the display-surfaces operation")
        (assert-true display-entry
                     "compatibility display surface query should include launched display-bearing linux apps")
        (assert-equal :desktop-window
                      (getf display-entry :display-surface-kind)
                      "compatibility display surface query should preserve the app display contract")
        (assert-equal "display-kit"
                      (getf display-entry :source-package-id)
                      "compatibility display surface query should preserve package-provided manifest provenance")))

    (let* ((persist-session (make-test-session :cwd "/tmp/kernel-compatibility-detached/"))
           (path "/tmp/kernel-compatibility-detached.sexp"))
      (ensure-directories-exist "/tmp/kernel-compatibility-detached/")
      (sbcl-agent::approve-policy persist-session :process-run)
      (let* ((spawn-command (sbcl-agent::command-invoke-tool-service persist-session :proc/spawn '(:argv ("/bin/sleep" "5"))))
             (spawn-execution-id (getf (sbcl-agent::service-response-metadata spawn-command) :execution-id))
             (environment (sbcl-agent::ensure-environment)))
        (sbcl-agent::save-environment environment path)
        (let* ((loaded-environment (sbcl-agent::load-environment path))
               (loaded-session (sbcl-agent::environment-session loaded-environment))
               (detached-detail (sbcl-agent::service-response-data
                                 (sbcl-agent::query-compatibility-execution-detail-service loaded-session
                                                                                           spawn-execution-id
                                                                                           :environment loaded-environment))))
          (assert-equal :detached
                        (getf (getf detached-detail :lifecycle) :status)
                        "compatibility detail should expose detached lifecycle state after reload without live process registry")
          (assert-equal nil
                        (getf (getf detached-detail :lifecycle) :control-token-live-p)
                        "compatibility detail should report the missing live control token after reload")
          (assert-equal t
                        (getf (getf detached-detail :lifecycle) :detached-runtime-loss-p)
                        "compatibility detail should expose detached runtime-loss posture after reload")
          (assert-true (member :acknowledge-loss
                               (getf (getf (getf detached-detail :lifecycle) :control-posture)
                                     :supported-actions))
                       "compatibility detail should expose acknowledge-loss for detached runtime-loss posture")
          (assert-equal "Compatibility execution is no longer attached to an active runtime control token."
                        (getf (getf (getf detached-detail :lifecycle) :control-posture) :blocked-reason)
                        "compatibility detail should expose detached runtime-loss posture after reload")
          (let* ((acknowledge-response
                   (sbcl-agent::command-kernel-control-service loaded-session
                                                              spawn-execution-id
                                                              :acknowledge-loss
                                                              :note "loss reviewed"
                                                              :environment loaded-environment))
                 (acknowledge-data (sbcl-agent::service-response-data acknowledge-response))
                 (acknowledge-lifecycle
                   (getf (getf acknowledge-data :post-state) :inspection)))
            (assert-equal :acknowledge-loss
                          (getf acknowledge-lifecycle :last-control-action)
                          "kernel control should persist acknowledge-loss as the last control action")
            (assert-equal t
                          (getf acknowledge-lifecycle :loss-acknowledged-p)
                          "kernel control should persist acknowledged compatibility runtime loss")
          (assert-equal "loss reviewed"
                          (getf acknowledge-lifecycle :recovery-note)
                          "kernel control should persist the compatibility recovery note"))
          (sbcl-agent::command-kernel-control-service persist-session
                                                     spawn-execution-id
                                                     :revoke
                                                     :environment environment))))

    (let* ((natural-session (make-test-session :cwd "/tmp/kernel-natural-lifecycle/")))
      (ensure-directories-exist "/tmp/kernel-natural-lifecycle/")
      (sbcl-agent::approve-policy natural-session :process-run)
      (let* ((spawn-command (sbcl-agent::command-invoke-tool-service natural-session
                                                                     :proc/spawn
                                                                     '(:argv ("/bin/sleep" "1"))))
             (spawn-execution-id (getf (sbcl-agent::service-response-metadata spawn-command) :execution-id))
             (initial-inspect (sbcl-agent::service-response-data
                               (sbcl-agent::query-kernel-inspect-service natural-session
                                                                         spawn-execution-id))))
        (assert-equal :running
                      (getf (getf initial-inspect :inspection) :status)
                      "kernel inspect should initially observe a short-lived spawned compatibility execution as running")
        (sleep 1.2)
        (let* ((completed-inspect (sbcl-agent::service-response-data
                                   (sbcl-agent::query-kernel-inspect-service natural-session
                                                                             spawn-execution-id)))
               (forensics (getf completed-inspect :forensics))
               (lifecycle-history (getf forensics :lifecycle-history))
               (last-lifecycle (car (last lifecycle-history))))
          (assert-equal :completed
                        (getf (getf completed-inspect :inspection) :status)
                        "kernel inspect should observe natural completion for a spawned compatibility execution")
          (assert-true (>= (length lifecycle-history) 2)
                       "kernel inspect should record an additional lifecycle event when observed status changes after invoke")
          (assert-equal :lifecycle
                        (getf last-lifecycle :event-kind)
                        "kernel inspect should record observed status changes as lifecycle events")
          (assert-equal :completed
                        (getf last-lifecycle :status)
                        "kernel inspect should record the observed terminal status in lifecycle history")
          (assert-equal :observation
                        (getf last-lifecycle :result)
                        "kernel inspect should mark observed status changes distinctly from invoke/control history"))))

    (let* ((invoke-response (sbcl-agent::command-kernel-invoke-service session
                                                                       "Mutate the runtime for governance preflight."
                                                                       :runtime/eval
                                                                       :payload (list :form "(progn (defparameter sbcl-agent::*kernel-governance-preflight-probe* nil) (setf sbcl-agent::*kernel-governance-preflight-probe* :ok))"
                                                                                      :mutating t)))
           (preflight (getf (sbcl-agent::service-response-metadata invoke-response)
                            :governance-preflight)))
      (assert-equal :runtime-mutation
                    (getf preflight :mutation-class)
                    "kernel invoke should classify mutating runtime eval through shared governance preflight")
      (assert-equal :runtime-eval-mutate
                    (getf preflight :policy-id)
                    "kernel invoke should expose the governing policy in shared preflight")
      (assert-equal t
                    (getf preflight :approval-required-p)
                    "kernel invoke should expose approval posture in shared preflight")
      (assert-equal t
                    (getf preflight :approval-granted-p)
                    "kernel invoke should expose granted approval posture in shared preflight")
      (assert-equal t
                    (getf preflight :checkpoint-required-p)
                    "kernel invoke should mark mutating runtime eval as checkpoint-requiring"))

    (let* ((work-item (sbcl-agent::create-work-item session "Kernel preflight checkpoint work"))
           (invoke-response (sbcl-agent::command-kernel-invoke-service session
                                                                       "Mutate the runtime with a bound governed work-item."
                                                                       :runtime/eval
                                                                       :payload (list :form "(setf sbcl-agent::*kernel-governance-preflight-probe* :bound)"
                                                                                      :mutating t)
                                                                       :context (list :work-item-id (sbcl-agent::work-item-id work-item))))
           (preflight (getf (sbcl-agent::service-response-metadata invoke-response)
                            :governance-preflight)))
      (assert-true (stringp (getf preflight :checkpoint-id))
                   "kernel invoke should create a checkpoint for bound governed work before mutation dispatch")
      (assert-equal t
                    (getf preflight :checkpoint-present-p)
                    "kernel invoke should report the created checkpoint in shared governance preflight")
      (assert-equal (getf preflight :checkpoint-id)
                    (sbcl-agent::latest-work-item-checkpoint-id work-item)
                    "kernel invoke should attach the created checkpoint to the bound work-item"))

    (let* ((work-item (sbcl-agent::create-work-item session "Kernel inspection governed work"))
           (approval-command (sbcl-agent::command-request-work-item-approval-service session
                                                                                     (sbcl-agent::work-item-id work-item)
                                                                                     :workspace-write
                                                                                     :reason "Kernel inspect coverage"))
           (approval-execution-id (getf (sbcl-agent::service-response-metadata approval-command) :execution-id))
           (approval-inspect (sbcl-agent::query-kernel-inspect-service session approval-execution-id))
           (related (getf (sbcl-agent::service-response-data approval-inspect) :related)))
      (assert-equal :work-item
                    (getf (sbcl-agent::service-response-data approval-inspect) :object-kind)
                    "kernel inspect should classify approval-backed governed work as work-item executions")
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (getf (getf (sbcl-agent::service-response-data approval-inspect) :inspection) :id)
                    "kernel inspect should expose the governed work-item detail payload")
      (assert-true (listp (getf related :workflow-record))
                   "kernel inspect should attach related workflow summaries when they can be derived from the execution target")
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (getf (getf related :work-item) :id)
                    "kernel inspect related objects should include the bound work-item summary"))

    (let* ((work-item (sbcl-agent::create-work-item session "Kernel control governed work"))
           (approval-command (sbcl-agent::command-request-work-item-approval-service session
                                                                                     (sbcl-agent::work-item-id work-item)
                                                                                     :workspace-write
                                                                                     :reason "Kernel control coverage"))
           (approval-execution-id (getf (sbcl-agent::service-response-metadata approval-command) :execution-id))
           (approve-response (sbcl-agent::command-kernel-control-service session
                                                                         approval-execution-id
                                                                         :approve))
           (quarantine-response (sbcl-agent::command-kernel-control-service session
                                                                            approval-execution-id
                                                                            :quarantine
                                                                            :reason "Operator review"))
           (resume-response (sbcl-agent::command-kernel-control-service session
                                                                        approval-execution-id
                                                                        :resume
                                                                        :note "Continue execution"))
           (approve-data (sbcl-agent::service-response-data approve-response))
           (quarantine-data (sbcl-agent::service-response-data quarantine-response))
           (resume-data (sbcl-agent::service-response-data resume-response)))
      (assert-equal :control
                    (getf approve-response :operation)
                    "kernel control should identify the control operation")
      (assert-equal :execution-handle
                    (getf approve-data :resolved-via)
                    "kernel control should identify execution-handle control semantics")
      (assert-true (member :workspace-write
                           (getf (getf approve-data :result) :approved-policies))
                   "kernel control approve should grant the policy bound to the execution handle")
      (assert-equal :quarantined
                    (getf (getf (getf quarantine-data :post-state) :inspection) :status)
                    "kernel control quarantine should project the quarantined post-state through the execution handle")
      (assert-equal :quarantined
                    (getf (getf (getf quarantine-data :post-state) :recovery) :work-item-status)
                    "kernel control post-state should expose quarantined recovery posture")
      (assert-equal :resumed
                    (getf (getf (getf resume-data :post-state) :inspection) :status)
                    "kernel control resume should project the resumed post-state through the execution handle")
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (getf (getf (getf (getf resume-data :post-state) :related) :work-item) :id)
                    "kernel control post-state should retain the related work-item summary"))

    (let* ((work-item (sbcl-agent::create-work-item session "Kernel recovery-governed work"))
           (approval-command (sbcl-agent::command-request-work-item-approval-service session
                                                                                     (sbcl-agent::work-item-id work-item)
                                                                                     :workspace-write
                                                                                     :reason "Kernel recovery coverage"))
           (approval-execution-id (getf (sbcl-agent::service-response-metadata approval-command) :execution-id)))
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-control-service session approval-execution-id :quarantine))
       "requires :reason"
       "kernel control quarantine should require an explicit operator reason")
      (sbcl-agent::command-kernel-control-service session
                                                  approval-execution-id
                                                  :quarantine
                                                  :reason "Recovery hold")
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-control-service session approval-execution-id :resume))
       "requires :note"
       "kernel control resume should require an explicit operator note for quarantined recovery posture"))

    (let* ((work-item (sbcl-agent::create-work-item session "Kernel rollback-governed work"))
           (approval-command (sbcl-agent::command-request-work-item-approval-service session
                                                                                     (sbcl-agent::work-item-id work-item)
                                                                                     :workspace-write
                                                                                     :reason "Kernel rollback coverage"))
           (approval-execution-id (getf (sbcl-agent::service-response-metadata approval-command) :execution-id)))
      (sbcl-agent::command-kernel-control-service session
                                                  approval-execution-id
                                                  :quarantine
                                                  :reason "Rollback review hold")
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-control-service session approval-execution-id :rollback))
       "requires :reason"
       "kernel control rollback should require an explicit operator reason")
      (let* ((rollback-response (sbcl-agent::command-kernel-control-service session
                                                                            approval-execution-id
                                                                            :rollback
                                                                            :reason "Operator requested rollback"
                                                                            :note "Revert governed transaction"))
             (rollback-data (sbcl-agent::service-response-data rollback-response)))
        (assert-equal :rolled-back
                      (getf (getf (getf rollback-data :post-state) :inspection) :status)
                      "kernel control rollback should project the rolled-back post-state through the execution handle")
        (assert-equal :rolled-back
                      (getf (getf (getf rollback-data :post-state) :recovery) :work-item-status)
                      "kernel control rollback should expose rolled-back recovery posture")
        (assert-equal :rolled-back
                      (getf (getf (getf rollback-data :post-state) :recovery) :rollback-status)
                      "kernel control rollback should mark the transaction rollback state as rolled-back")))

    (let* ((work-item (sbcl-agent::create-work-item session "Kernel mutation gating work"))
           (approval-command (sbcl-agent::command-request-work-item-approval-service session
                                                                                     (sbcl-agent::work-item-id work-item)
                                                                                     :runtime-package-switch
                                                                                     :reason "Kernel mutation gating coverage"))
           (approval-execution-id (getf (sbcl-agent::service-response-metadata approval-command) :execution-id)))
      (sbcl-agent::approve-policy session :runtime-package-switch)
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-invoke-service session
                                                    "Blocked runtime package switch"
                                                    :runtime/set-package
                                                    :context (list :work-item-id (sbcl-agent::work-item-id work-item))
                                                    :payload (list :package "SBCL-AGENT-USER")))
       "Kernel invoke blocked for governed mutation"
       "kernel invoke should block governed mutation when the bound work-item is awaiting approval")
      (sbcl-agent::command-kernel-control-service session
                                                  approval-execution-id
                                                  :quarantine
                                                  :reason "Operator hold")
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-invoke-service session
                                                    "Blocked runtime package switch"
                                                    :runtime/set-package
                                                    :context (list :work-item-id (sbcl-agent::work-item-id work-item))
                                                    :payload (list :package "SBCL-AGENT-USER")))
       "Kernel invoke blocked for governed mutation"
       "kernel invoke should block governed mutation when the bound work-item is quarantined"))

    (let* ((work-item (sbcl-agent::create-work-item session "Kernel workflow mutation gating work"))
           (work-item-id (sbcl-agent::work-item-id work-item))
           (approval-command (sbcl-agent::command-request-work-item-approval-service session
                                                                                     work-item-id
                                                                                     :workspace-write
                                                                                     :reason "Kernel workflow mutation gating coverage"))
           (approval-execution-id (getf (sbcl-agent::service-response-metadata approval-command) :execution-id)))
      (sbcl-agent::command-kernel-control-service session
                                                  approval-execution-id
                                                  :quarantine
                                                  :reason "Operator hold")
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-invoke-service session
                                                    "Blocked workflow steering for quarantined work."
                                                    "workflow/steer-plan"
                                                    :context (list :work-item-id work-item-id)
                                                    :payload (list :work-item-id work-item-id
                                                                   :phase :validate
                                                                   :next-step :run-cold-validation
                                                                   :note "Should not pass")))
       "Kernel invoke blocked for governed mutation"
       "kernel invoke should block workflow steering mutation when the bound work-item is quarantined"))

    (let* ((validation-session (make-test-session :cwd "/tmp/kernel-validation-control/"))
           (invoke-response
             (progn
               (sbcl-agent::approve-policy validation-session :runtime-eval-mutate)
               (sbcl-agent::command-kernel-invoke-service
                validation-session
                "Create governed runtime mutation for validation control."
                :runtime/eval
                :payload (list :form "(progn (defparameter sbcl-agent-user::*kernel-cold-validation-probe* nil) (setf sbcl-agent-user::*kernel-cold-validation-probe* :ok) sbcl-agent-user::*kernel-cold-validation-probe*)"
                               :package "SBCL-AGENT-USER"
                               :mutating t))))
           (result (sbcl-agent::service-response-data invoke-response))
           (work-item (sbcl-agent::find-work-item validation-session (getf result :work-item-id)))
           (execution-id
             (or (getf (sbcl-agent::service-response-metadata invoke-response) :execution-id)
                 (getf (sbcl-agent::kernel-find-execution-by-target :work-item-id
                                                                   (sbcl-agent::work-item-id work-item)
                                                                   (sbcl-agent::ensure-environment))
                       :execution-id)))
           (complete-response (sbcl-agent::command-kernel-control-service validation-session
                                                                          execution-id
                                                                          :complete-validations
                                                                          :status :passed))
           (complete-data (sbcl-agent::service-response-data complete-response)))
      (assert-equal :committed
                    (getf (getf (getf complete-data :post-state) :inspection) :status)
                    "kernel control complete-validations should project the committed post-state through the execution handle")
      (assert-equal :committed
                    (sbcl-agent::work-item-status work-item)
                    "kernel control complete-validations should finalize the governed work-item")
      (assert-equal :committed
                    (sbcl-agent::workflow-record-status
                     (sbcl-agent::work-item-workflow-record validation-session work-item))
                    "kernel control complete-validations should close the workflow record"))

    (let ((self-mod-session (make-test-session :cwd (current-workspace-root))))
      (sbcl-agent::approve-policy self-mod-session :workspace-write)
      (sbcl-agent::approve-policy self-mod-session :runtime-reload)
      (sbcl-agent::approve-policy self-mod-session :runtime-eval-mutate)
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-invoke-service self-mod-session
                                                    "Blocked self-modifying patch"
                                                    :workspace/patch
                                                    :payload '((:write "src/kernel-self-mod-test.lisp" "blocked"))))
       "Kernel invoke blocked for self-modifying mutation"
       "kernel invoke should block self-modifying patch mutations without governed work-item binding")
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-invoke-service self-mod-session
                                                    "Blocked self-modifying reload"
                                                    :runtime/reload-file
                                                    :payload (list :path "src/main.lisp")))
       "Kernel invoke blocked for self-modifying mutation"
       "kernel invoke should block self-modifying runtime reload without governed work-item binding")
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-invoke-service self-mod-session
                                                    "Blocked self-modifying runtime eval"
                                                    :runtime/eval
                                                    :payload (list :form "(setf *package* *package*)"
                                                                   :package "SBCL-AGENT"
                                                                   :mutating t)))
       "Kernel invoke blocked for self-modifying mutation"
       "kernel invoke should block self-modifying runtime eval without governed work-item binding"))

    (let* ((authority-command (sbcl-agent::command-approve-policy-service session :process-run))
           (authority-execution-id (getf (sbcl-agent::service-response-metadata authority-command) :execution-id)))
      (assert-signals-error
       (lambda ()
         (sbcl-agent::command-kernel-control-service session authority-execution-id :approve))
       "Authority cannot be self-granted"
       "kernel control should reject approving authority-grant executions through their own execution handles"))

    (let* ((work-item (sbcl-agent::create-work-item session "Kernel execution association work"))
           (approval-command (sbcl-agent::command-request-work-item-approval-service session
                                                                                     (sbcl-agent::work-item-id work-item)
                                                                                     :workspace-write
                                                                                     :reason "Kernel association coverage"))
           (work-item-detail (sbcl-agent::service-response-data
                              (sbcl-agent::query-work-item-detail-service session
                                                                          (sbcl-agent::work-item-id work-item))))
           (workflow-record (sbcl-agent::work-item-workflow-record session work-item))
           (workflow-record-detail (sbcl-agent::service-response-data
                                    (sbcl-agent::query-workflow-record-detail-service session
                                                                                      (sbcl-agent::workflow-record-id workflow-record))))
           (approval-execution-id (getf (sbcl-agent::service-response-metadata approval-command) :execution-id)))
      (assert-true (consp (getf work-item-detail :execution-handles))
                   "work-item detail should expose associated execution handles")
      (assert-true (consp (getf workflow-record-detail :execution-handles))
                   "workflow-record detail should expose associated execution handles")
      (assert-equal "governed-work"
                    (getf (getf work-item-detail :execution-surface) :surface-kind)
                    "work-item detail should expose the governing execution surface")
      (assert-equal "governed-work"
                    (getf (getf workflow-record-detail :execution-surface) :surface-kind)
                    "workflow-record detail should expose the governing execution surface")
      (assert-equal approval-execution-id
                    (getf (first (getf work-item-detail :execution-handles)) :execution-id)
                    "work-item detail should include the approval execution handle")
      (assert-equal approval-execution-id
                    (getf (first (getf workflow-record-detail :execution-handles)) :execution-id)
                    "workflow-record detail should include the approval execution handle"))))

(defun workflow-and-approval-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/workflow-approval-service-contract/")))
    (sbcl-agent::ensure-environment)
    (let* ((work-item (sbcl-agent::create-work-item session "Service approval goal"))
           (approval-response (sbcl-agent::command-request-work-item-approval-service session
                                                                                      (sbcl-agent::work-item-id work-item)
                                                                                      :workspace-write
                                                                                      :reason "Need operator confirmation")))
      (assert-equal :approval
                    (getf approval-response :domain)
                    "approval service should report the approval domain")
      (assert-service-metadata-shape approval-response "approval request service")
      (assert-equal :workspace-write
                    (getf (sbcl-agent::service-response-metadata approval-response) :policy-id)
                    "approval request service should expose the governing policy id")
      (assert-equal :request-work-item-approval
                    (getf approval-response :operation)
                    "approval service should identify the approval request operation")
      (assert-equal :approval-required
                    (getf (getf (sbcl-agent::service-response-data approval-response) :wait) :why)
                    "approval request should project an approval-required wait state")
      (assert-equal :awaiting-approval
                    (getf (getf (sbcl-agent::service-response-data approval-response) :workflow-record) :status)
                    "approval request should move the workflow record into awaiting-approval")
      (assert-equal "governed-work"
                    (getf (getf (getf (sbcl-agent::service-response-data approval-response) :work-item)
                                :execution-surface)
                          :surface-kind)
                    "approval request should expose a governed execution surface for the work-item")
      (assert-equal "governed-work"
                    (getf (getf (getf (sbcl-agent::service-response-data approval-response) :workflow-record)
                                :execution-surface)
                          :surface-kind)
                    "approval request should expose a governed execution surface for the workflow record")
      (assert-true (stringp (sbcl-agent::latest-work-item-checkpoint-id work-item))
                   "approval request should anchor governed work to a checkpoint before waiting on approval"))
    (let* ((record (sbcl-agent::create-workflow-record session "Workflow service goal"))
           (detail-response (sbcl-agent::query-workflow-record-detail-service session
                                                                              (sbcl-agent::workflow-record-id record))))
      (assert-equal :workflow
                    (getf detail-response :domain)
                    "workflow service should report the workflow domain")
      (assert-service-metadata-shape detail-response "workflow detail service")
      (assert-equal :record-detail
                    (getf detail-response :operation)
                    "workflow detail service should identify the detail operation")
      (assert-equal (sbcl-agent::workflow-record-id record)
                    (getf (sbcl-agent::service-response-data detail-response) :id)
                    "workflow detail service should return the requested workflow record"))))

(defun event-stream-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/event-stream-service-contract/")))
    (let ((environment (sbcl-agent::ensure-environment)))
      (sbcl-agent::append-session-event session
                                        :thread-created
                                        '(:id "thread-1")
                                        :family :conversation
                                        :visibility :operator)
      (sbcl-agent::sync-environment-from-session environment session)
      (let* ((response (sbcl-agent::query-service-event-stream :environment environment
                                                               :limit 10
                                                               :family :conversation))
             (payload (sbcl-agent::service-response-data response))
             (events (getf payload :events)))
        (assert-equal :events
                      (getf response :domain)
                      "event stream service should report the events domain")
        (assert-service-metadata-shape response "event stream service")
        (assert-equal :stream
                      (getf response :operation)
                      "event stream service should identify the stream operation")
        (assert-equal 1
                      (length events)
                      "event stream service should filter by event family")
        (assert-equal 0
                      (getf (first events) :cursor)
                      "event stream entries should include a stable cursor")
        (assert-equal :thread-created
                      (getf (first events) :kind)
                      "event stream entries should expose canonical event kinds")))))

(defun incident-and-work-item-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/incident-work-item-service-contract/")))
    (sbcl-agent::ensure-environment)
    (let* ((work-item (sbcl-agent::create-work-item session "Service work item"))
           (work-list-response (sbcl-agent::query-work-item-list-service session))
           (work-detail-response (sbcl-agent::query-work-item-detail-service session
                                                                             (sbcl-agent::work-item-id work-item)))
           (work-plan-response (sbcl-agent::query-work-item-plan-service session
                                                                         (sbcl-agent::work-item-id work-item))))
      (assert-equal :work-item
                    (getf work-list-response :domain)
                    "work-item list service should report the work-item domain")
      (assert-service-metadata-shape work-list-response "work-item list service")
      (assert-equal :list
                    (getf work-list-response :operation)
                    "work-item list service should identify the list operation")
      (assert-true (= 1 (length (sbcl-agent::service-response-data work-list-response)))
                   "work-item list service should return created work-items")
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (getf (sbcl-agent::service-response-data work-detail-response) :id)
                    "work-item detail service should return the requested work-item")
      (assert-service-metadata-shape work-plan-response "work-item plan service")
      (assert-equal :plan
                    (getf work-plan-response :operation)
                    "work-item plan service should identify the plan operation")
      (assert-equal :work-item-plan-v1
                    (getf (sbcl-agent::service-response-metadata work-plan-response) :read-model)
                    "work-item plan service should declare the plan read model")
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (getf (sbcl-agent::service-response-data work-plan-response) :id)
                    "work-item plan service should preserve the work-item identity")
      (assert-true (listp (getf (sbcl-agent::service-response-data work-plan-response) :plan-steering))
                   "work-item plan service should expose the long-horizon steering snapshot"))
    (let* ((incident (sbcl-agent::create-incident session
                                                  :runtime-eval-failure
                                                  "Incident title"
                                                  "Incident summary"))
           (incident-list-response (sbcl-agent::query-incident-list-service session))
           (incident-detail-response (sbcl-agent::query-incident-detail-service session
                                                                                 (sbcl-agent::incident-id incident))))
      (assert-equal :incident
                    (getf incident-list-response :domain)
                    "incident list service should report the incident domain")
      (assert-service-metadata-shape incident-list-response "incident list service")
      (assert-equal :list
                    (getf incident-list-response :operation)
                    "incident list service should identify the list operation")
      (assert-true (= 1 (length (sbcl-agent::service-response-data incident-list-response)))
                   "incident list service should return created incidents")
      (assert-service-metadata-shape incident-detail-response "incident detail service")
      (assert-equal (sbcl-agent::incident-id incident)
                    (getf (sbcl-agent::service-response-data incident-detail-response) :id)
                    "incident detail service should return the requested incident"))))

(defun runtime-read-and-environment-command-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/runtime-read-service-contract/")))
    (sbcl-agent::ensure-environment)
    (let ((describe-response (sbcl-agent::query-runtime-describe-symbol-service session "CAR")))
      (assert-service-metadata-shape describe-response "runtime describe-symbol service")
      (assert-equal :runtime
                    (getf describe-response :domain)
                    "runtime describe-symbol service should report runtime domain")
      (assert-equal :runtime/describe-symbol
                    (getf (sbcl-agent::service-response-data describe-response) :tool)
                    "runtime describe-symbol service should preserve tool payload shape"))
    (let* ((path "/tmp/service-environment-save.sexp")
           (save-response (sbcl-agent::command-environment-save-service path)))
      (assert-equal :environment
                    (getf save-response :domain)
                    "environment save service should report environment domain")
      (assert-equal :save
                    (getf save-response :operation)
                    "environment save service should identify save operation")
      (assert-service-metadata-shape save-response "environment save service")
      (assert-equal path
                    (getf (sbcl-agent::service-response-data save-response) :saved)
                    "environment save service should report saved path"))))

(defun session-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/session-service-contract/")))
    (sbcl-agent::update-session-plan session "Service-backed session")
    (sbcl-agent::approve-policy session :runtime-package-switch)
    (sbcl-agent::command-runtime-set-package-service session "CL-USER")
    (let ((summary-response (sbcl-agent::query-session-summary-service session)))
      (assert-equal :session
                    (getf summary-response :domain)
                    "session summary service should report session domain")
      (assert-equal :summary
                    (getf summary-response :operation)
                    "session summary service should identify summary operation")
      (assert-service-metadata-shape summary-response "session summary service")
      (assert-equal "Service-backed session"
                    (getf (sbcl-agent::service-response-data summary-response) :plan)
                    "session summary service should expose the current plan")
      (assert-true (> (getf (getf (sbcl-agent::service-response-data summary-response)
                                  :execution-surfaces)
                            :count)
                      0)
                   "session summary service should expose execution-backed surfaces")
      (assert-true (integerp (getf (getf (sbcl-agent::service-response-data summary-response)
                                         :blocked-work-surfaces)
                                   :count))
                   "session summary service should expose compact blocked-work surface counts")
      (assert-true (integerp (getf (getf (sbcl-agent::service-response-data summary-response)
                                         :approval-surfaces)
                                   :count))
                   "session summary service should expose compact approval surface counts"))
    (let* ((path "/tmp/service-session-save.sexp")
           (save-response (sbcl-agent::command-session-save-service session path))
           (load-response (sbcl-agent::command-session-load-service path))
           (loaded-session (getf (sbcl-agent::service-response-data load-response) :session)))
      (assert-equal :save
                    (getf save-response :operation)
                    "session save service should identify save operation")
      (assert-service-metadata-shape save-response "session save service")
      (assert-equal path
                    (getf (sbcl-agent::service-response-data save-response) :saved)
                    "session save service should report the saved path")
      (assert-equal :load
                    (getf load-response :operation)
                    "session load service should identify load operation")
      (assert-service-metadata-shape load-response "session load service")
      (assert-equal "Service-backed session"
                    (sbcl-agent::agent-session-plan loaded-session)
                    "session load service should restore the saved session plan"))))

(defun shell-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/shell-service-contract/"))
         (provider (make-test-provider))
         (work-item (sbcl-agent::create-work-item session "Shell workspace contract work")))
    (ensure-directories-exist "/tmp/shell-service-contract/")
    (sbcl-agent::approve-policy session :process-run)
    (sbcl-agent::command-request-work-item-approval-service session
                                                            (sbcl-agent::work-item-id work-item)
                                                            :process-run
                                                            :reason "Need shell governance review")
    (sbcl-agent::command-task-enqueue-service
     session
     '(tool :fs/list :path ".")
     (sbcl-agent::normalize-form-command '(tool :fs/list :path "."))
     0)
    (sbcl-agent::command-worker-start-service session provider)
    (let* ((workspace-response (sbcl-agent::query-shell-workspace-service session))
           (workspace (sbcl-agent::service-response-data workspace-response))
           (focus-object-id (getf workspace :inspector-focus-object-id)))
      (assert-equal :shell
                    (getf workspace-response :domain)
                    "shell workspace service should report shell domain")
      (assert-equal :workspace
                    (getf workspace-response :operation)
                    "shell workspace service should identify workspace operation")
      (assert-service-metadata-shape workspace-response "shell workspace service")
      (assert-true (> (getf (getf workspace :execution-surfaces) :count) 0)
                   "shell workspace service should expose execution surfaces")
      (assert-true (> (getf (getf workspace :governance-queue) :count) 0)
                   "shell workspace service should expose governance queue items")
      (assert-true (> (getf (getf workspace :object-browser) :group-count) 0)
                   "shell workspace service should expose object browser groups")
      (assert-true (stringp focus-object-id)
                   "shell workspace service should expose an inspector focus object id")
      (assert-true (listp (getf workspace :current-focus))
                   "shell workspace service should expose a compact current focus summary")
      (assert-true (listp (getf workspace :recommended-action))
                   "shell workspace service should expose a recommended next action")
      (let* ((desktop-response (sbcl-agent::query-shell-desktop-model-service session))
             (desktop (sbcl-agent::service-response-data desktop-response)))
        (assert-equal :desktop-model
                      (getf desktop-response :operation)
                      "shell desktop model service should identify desktop-model operation")
        (assert-service-metadata-shape desktop-response "shell desktop model service")
        (assert-true (> (getf desktop :surface-count) 0)
                     "shell desktop model service should expose surface count")
        (assert-true (> (getf desktop :governance-count) 0)
                     "shell desktop model service should expose governance count")
        (assert-true (> (length (getf desktop :entry-points)) 0)
                     "shell desktop model service should expose desktop entry points")
        (assert-equal :inspector
                      (getf desktop :active-panel)
                      "shell desktop model service should expose an active panel")
        (assert-true (listp (getf desktop :active-panel-summary))
                     "shell desktop model service should expose a compact active panel summary")
        (assert-equal :inspector
                      (getf (getf desktop :active-panel-summary) :panel-id)
                      "shell desktop model service should align the active panel summary with the active panel")
        (assert-true (listp (getf desktop :recommended-action))
                     "shell desktop model service should expose a recommended next desktop action")
        (assert-equal :open-panel
                      (getf (getf desktop :recommended-action) :action-kind)
                      "shell desktop model service should recommend opening the focused execution when the inspector is active")
        (assert-true (listp (getf desktop :panels))
                     "shell desktop model service should expose panel state")
        (assert-equal (getf (getf (getf desktop :panels) :workspace) :selected-index)
                      (getf (getf desktop :surface-list) :focus-index)
                      "shell desktop model service should align workspace panel selection with surface focus")
        (assert-true (stringp (getf (getf (getf (getf desktop :panels) :workspace) :actions)
                                          :open-command))
                     "shell desktop model service should expose workspace panel open commands")
        (assert-true (stringp (getf (getf (getf (getf desktop :panels) :governance) :actions)
                                          :select-command))
                     "shell desktop model service should expose governance panel select commands")
        (assert-true (stringp (getf (getf (getf (getf desktop :panels) :object-browser) :actions)
                                          :open-command))
                     "shell desktop model service should expose object-browser panel open commands")
        (assert-equal :activate-panel
                      (getf (getf (getf (getf (getf desktop :panels) :workspace) :actions)
                                  :activate)
                            :action-kind)
                      "shell desktop model service should expose structured desktop actions")
        (assert-true (stringp (getf (getf (getf (getf (getf desktop :panels) :workspace) :actions)
                                                :activate)
                                      :action-id))
                     "shell desktop model service should expose stable desktop action ids")
        (assert-true (stringp (getf (getf (getf (getf (getf desktop :panels) :workspace) :actions)
                                                :restore)
                                      :action-id))
                     "shell desktop model service should expose stable desktop restore action ids")
        (assert-equal (getf workspace :inspector-focus-object-id)
                      (getf desktop :focus-object-id)
                      "shell desktop model service should align focus with workspace posture"))
      (let ((display-package-path "/tmp/shell-service-display-kit.aop"))
        (sbcl-agent::command-platform-package-service display-package-path
                                                     :package-id "shell-display-kit"
                                                     :package-version "1.0.0"
                                                     :title "Shell Display Kit"
                                                     :capability-ids '(:proc/run)
                                                     :session session)
        (rewrite-platform-package-app-display-surface-kind display-package-path
                                                           "linux.echo"
                                                           :desktop-window)
        (sbcl-agent::command-platform-import-package-service display-package-path
                                                             :session session)
        (sbcl-agent::command-platform-activate-package-service "shell-display-kit"
                                                               :session session)
        (sbcl-agent::approve-policy session :linux-app-launch)
        (let* ((display-echo-response
                 (sbcl-agent::command-kernel-invoke-service session
                                                            "Launch a shell display bridge app."
                                                            "linux.echo"
                                                            :payload (list :arguments '("display-shell-service"))))
               (display-echo-execution-id
                 (getf (sbcl-agent::service-response-metadata display-echo-response) :execution-id)))
        (let* ((display-workspace (sbcl-agent::service-response-data
                                   (sbcl-agent::query-shell-workspace-service session)))
               (display-desktop (sbcl-agent::service-response-data
                                 (sbcl-agent::query-shell-desktop-model-service session)))
               (display-list-response
                 (sbcl-agent::query-shell-display-list-service session))
               (display-list
                 (sbcl-agent::service-response-data display-list-response))
               (display-show-response
                 (sbcl-agent::query-shell-display-detail-service session
                                                                 nil
                                                                 :app-id "linux.echo"))
               (display-show
                 (sbcl-agent::service-response-data display-show-response))
               (display-select-response
                 (sbcl-agent::command-shell-display-select-service session :app-id "linux.echo"))
               (display-select
                 (sbcl-agent::service-response-data display-select-response))
               (display-step-response
                 (sbcl-agent::command-shell-display-step-service session :next))
               (display-step
                 (sbcl-agent::service-response-data display-step-response))
               (display-open-response
                 (sbcl-agent::command-shell-open-service session :display-index 0))
               (display-open
                 (sbcl-agent::service-response-data display-open-response))
               (display-app-open-response
                 (sbcl-agent::command-shell-open-service session :display-app-id "linux.echo"))
               (display-app-open
                 (sbcl-agent::service-response-data display-app-open-response))
               (display-relaunch-response
                 (sbcl-agent::command-shell-display-control-service session
                                                                    :relaunch
                                                                    :app-id "linux.echo"))
               (display-relaunch
                 (sbcl-agent::service-response-data display-relaunch-response))
               (display-app-select-response
                 (sbcl-agent::command-shell-desktop-select-service session :display :app-id "linux.echo"))
               (display-app-select
                 (sbcl-agent::service-response-data display-app-select-response))
               (display-app-restore-response
                 (sbcl-agent::command-shell-desktop-restore-service session
                                                                    :panel-state '(:panel-id :display
                                                                                   :selected-app-id "linux.echo")))
               (display-app-restore
                 (sbcl-agent::service-response-data display-app-restore-response)))
          (assert-true (listp (getf display-workspace :current-display-surface))
                       "shell workspace service should expose current display posture when Linux app windows exist")
          (assert-equal :desktop-window
                        (getf (getf display-workspace :current-display-posture) :display-surface-kind)
                        "shell workspace service should expose current display surface kind in workspace posture")
          (assert-true (getf (getf display-workspace :current-display-posture) :relaunch-ready-p)
                       "shell workspace service should expose relaunch readiness in workspace posture")
          (assert-true (stringp (getf (getf display-workspace :display-actions) :show-command))
                       "shell workspace service should expose display show commands in the workspace model")
          (assert-true (stringp (getf (getf (getf display-workspace :display-actions) :show) :action-id))
                       "shell workspace service should expose stable action ids for current display actions")
          (assert-true (stringp (getf (getf display-workspace :display-action-ids) :show))
                       "shell workspace service should expose compact current display action id maps")
          (assert-equal :step-panel
                        (getf (getf (getf display-workspace :display-actions) :next) :action-kind)
                        "shell workspace service should expose structured display next actions in the workspace model")
          (assert-equal :show-panel
                        (getf (getf (getf display-workspace :display-entry-actions) :show) :action-kind)
                        "shell workspace service should expose structured display entry show actions in the workspace model")
          (assert-true (stringp (getf (getf (getf display-workspace :display-entry-actions) :show) :action-id))
                       "shell workspace service should expose stable action ids for display entry actions")
          (assert-true (stringp (getf (getf display-workspace :display-entry-action-ids) :show))
                       "shell workspace service should expose compact display entry action id maps")
          (assert-equal :step-panel
                        (getf (getf (getf display-workspace :display-entry-actions) :next) :action-kind)
                        "shell workspace service should expose structured display entry next actions in the workspace model")
          (assert-equal :display
                        (getf (getf display-workspace :current-focus) :focus-kind)
                        "shell workspace service should summarize display focus when a display surface is active")
          (assert-equal "linux.echo"
                        (getf (getf display-workspace :current-focus) :app-id)
                        "shell workspace service should preserve app identity in the compact focus summary")
          (assert-equal :show-panel
                        (getf (getf display-workspace :recommended-action) :action-kind)
                        "shell workspace service should recommend the display show action for active display focus")
          (assert-true (stringp (getf (getf display-workspace :recommended-action) :action-id))
                       "shell workspace service should expose a stable action id for the recommended action")
          (assert-true (> (getf (getf display-workspace :display-surfaces) :count) 0)
                       "shell workspace service should project display-bearing Linux apps into display surfaces")
          (assert-true (> (getf display-desktop :display-count) 0)
                       "shell desktop model service should project Linux app display count")
          (assert-equal :display
                        (getf display-desktop :active-panel)
                        "shell desktop model service should prefer the display panel when display-bearing Linux apps exist")
          (assert-equal :display
                        (getf (getf display-desktop :active-panel-summary) :panel-id)
                        "shell desktop model service should expose a display-focused active panel summary when Linux app windows exist")
          (assert-equal "linux.echo"
                        (getf (getf display-desktop :active-panel-summary) :app-id)
                        "shell desktop model service should preserve app identity in the active panel summary")
          (assert-equal :show-panel
                        (getf (getf display-desktop :recommended-action) :action-kind)
                        "shell desktop model service should recommend a compact next desktop action for the active display panel")
          (assert-equal :display-list
                        (getf display-list-response :operation)
                        "shell display list service should identify display-list operation")
          (assert-service-metadata-shape display-list-response "shell display list service")
          (assert-true (> (getf display-list :count) 0)
                       "shell display list service should expose display-bearing Linux app surfaces")
          (assert-equal :display-show
                        (getf display-show-response :operation)
                        "shell display detail service should identify display-show operation")
          (assert-service-metadata-shape display-show-response "shell display detail service")
          (assert-equal :display
                        (getf display-show :panel-id)
                        "shell display detail service should report display panel posture")
          (assert-equal display-echo-execution-id
                        (getf (getf display-show :display-surface) :execution-id)
                        "shell display detail service should expose the requested display-bearing Linux app")
          (assert-true (listp (getf display-show :inspection))
                       "shell display detail service should include display inspection data")
          (assert-true (listp (getf display-show :lifecycle))
                       "shell display detail service should include compatibility lifecycle data")
          (assert-equal :display-select
                        (getf display-select-response :operation)
                        "shell display select service should identify display-select operation")
          (assert-service-metadata-shape display-select-response "shell display select service")
          (assert-equal :display
                        (getf display-select :panel-id)
                        "shell display select service should move the shell into the display panel")
          (assert-equal "linux.echo"
                        (getf (getf display-select :display-surface) :app-id)
                        "shell display select service should support display selection by app id")
          (assert-equal :display-step
                        (getf display-step-response :operation)
                        "shell display step service should identify display-step operation")
          (assert-service-metadata-shape display-step-response "shell display step service")
          (assert-equal :display
                        (getf display-step :panel-id)
                        "shell display step service should keep the shell in the display panel")
          (assert-equal :open
                        (getf display-open-response :operation)
                        "shell open service should still identify open operation for display entry")
          (assert-service-metadata-shape display-open-response "shell display open service")
          (assert-equal :display
                        (getf display-open :open-via)
                        "shell open service should support display-index entry through the display lane")
          (assert-equal :open
                        (getf display-app-open-response :operation)
                        "shell open service should still identify open operation for display app entry")
          (assert-service-metadata-shape display-app-open-response "shell display app open service")
          (assert-equal :display
                        (getf display-app-open :open-via)
                        "shell open service should support display-app-id entry through the display lane")
          (assert-equal :display-control
                        (getf display-relaunch-response :operation)
                        "shell display control service should identify display-control operation")
          (assert-service-metadata-shape display-relaunch-response "shell display control service")
          (assert-equal :display
                        (getf display-relaunch :panel-id)
                        "shell display control service should keep the shell in the display panel")
          (assert-equal :relaunch
                        (getf (getf display-relaunch :result) :action)
                        "shell display control service should preserve the requested relaunch action")
          (assert-true (string/= display-echo-execution-id
                                 (getf display-relaunch :focus-object-id))
                       "shell display control relaunch should focus the newly launched execution")
          (assert-equal :display
                        (getf display-app-select :panel-id)
                        "shell desktop select service should support display selection by app id")
          (assert-equal "linux.echo"
                        (getf (getf (getf (getf display-app-select :desktop-model) :panels) :display) :selected-app-id)
                        "shell desktop select service should preserve selected display app id in the desktop model")
          (assert-equal :display
                        (getf (getf display-app-restore :desktop-model) :active-panel)
                        "shell desktop restore service should support display restore by app id")
          (assert-equal "linux.echo"
                        (getf (getf (getf (getf display-app-restore :desktop-model) :panels) :display) :selected-app-id)
                        "shell desktop restore service should preserve selected display app id in the desktop model")
          (assert-true (find :display
                             (getf display-desktop :entry-points)
                             :key (lambda (entry) (getf entry :entry-kind))
                             :test #'eq)
                       "shell desktop model service should expose display entry points when Linux app windows exist")
          (let ((display-entry (find :display
                                     (getf display-desktop :entry-points)
                                     :key (lambda (entry) (getf entry :entry-kind))
                                     :test #'eq)))
            (assert-true (listp (getf display-entry :actions))
                         "shell desktop model service should expose structured actions on the top display entry point")
            (assert-equal :show-panel
                          (getf (getf (getf display-entry :actions) :show) :action-kind)
                          "shell desktop model service should expose a structured show action on the top display entry point")
            (assert-equal :step-panel
                          (getf (getf (getf display-entry :actions) :next) :action-kind)
                          "shell desktop model service should expose a structured next action on the top display entry point")
            (assert-equal :control-panel
                          (getf (getf (getf display-entry :actions) :relaunch) :action-kind)
                          "shell desktop model service should expose a structured relaunch action on the top display entry point")
            (assert-equal "linux.echo"
                          (getf (getf (getf (getf display-entry :actions) :show) :params) :app-id)
                          "shell desktop model service should preserve app-id in the top display entry show action")
            (assert-equal "linux.echo"
                          (getf (getf (getf (getf display-entry :actions) :open) :params) :app-id)
                          "shell desktop model service should preserve app-id in the top display entry open action")
            (assert-equal :previous
                          (getf (getf (getf (getf display-entry :actions) :previous) :params) :direction)
                          "shell desktop model service should preserve previous direction on the top display entry")
            (assert-equal "linux.echo"
                          (getf (getf (getf (getf display-entry :actions) :relaunch) :params) :app-id)
                          "shell desktop model service should preserve app-id in the top display entry relaunch action"))
          (assert-true (> (getf (getf (getf display-desktop :panels) :display) :count) 0)
                       "shell desktop model service should expose a first-class display panel when Linux app windows exist")
          (assert-equal :desktop-window
                        (getf (getf (getf display-desktop :panels) :display) :selected-display-surface-kind)
                        "shell desktop model service should preserve the selected display surface kind in panel state")
          (assert-true (getf (getf (getf display-desktop :panels) :display) :selected-relaunch-ready-p)
                       "shell desktop model service should preserve relaunch readiness in display panel state")
          (assert-true (member :relaunch
                               (getf (getf (getf display-desktop :panels) :display) :selected-supported-actions))
                       "shell desktop model service should preserve supported actions in display panel state")
          (assert-true (stringp (getf (getf (getf (getf display-desktop :panels) :display) :actions)
                                          :next-command))
                       "shell desktop model service should expose a display next command when Linux app windows exist")
          (assert-true (stringp (getf (getf (getf (getf display-desktop :panels) :display) :actions)
                                          :show-command))
                       "shell desktop model service should expose a display show command when Linux app windows exist")
          (assert-true (stringp (getf (getf (getf (getf display-desktop :panels) :display) :actions)
                                          :relaunch-command))
                       "shell desktop model service should expose a display relaunch command when the selected Linux app can relaunch")
          (assert-equal :show-panel
                        (getf (getf (getf (getf (getf display-desktop :panels) :display) :actions)
                                    :show)
                              :action-kind)
                        "shell desktop model service should expose a structured display show action")
          (assert-equal :control-panel
                        (getf (getf (getf (getf (getf display-desktop :panels) :display) :actions)
                                    :relaunch)
                              :action-kind)
                        "shell desktop model service should expose a structured display control action")
          (assert-equal :step-panel
                        (getf (getf (getf (getf (getf display-desktop :panels) :display) :actions)
                                    :next)
                              :action-kind)
                        "shell desktop model service should expose a structured display next action")
          (assert-equal :previous
                        (getf (getf (getf (getf (getf (getf display-desktop :panels) :display) :actions)
                                          :previous)
                                    :params)
                              :direction)
                        "shell desktop model service should preserve previous step direction on the display panel")
          (assert-equal :display
                        (getf (sbcl-agent::service-response-data
                               (sbcl-agent::command-shell-desktop-select-service session :display :index 0))
                              :panel-id)
                        "shell desktop select service should support display panel selection"))
        )
        (sbcl-agent::command-platform-deactivate-package-service "shell-display-kit"
                                                                 :session session))
      (let* ((desktop-panel-response
               (sbcl-agent::command-shell-desktop-panel-service session :governance))
             (desktop-panel (sbcl-agent::service-response-data desktop-panel-response)))
        (assert-equal :desktop-panel
                      (getf desktop-panel-response :operation)
                      "shell desktop panel service should identify desktop-panel operation")
        (assert-service-metadata-shape desktop-panel-response "shell desktop panel service")
        (assert-equal :governance
                      (getf desktop-panel :active-panel)
                      "shell desktop panel service should persist the requested active panel")
        (assert-equal :governance
                      (getf (getf desktop-panel :desktop-model) :active-panel)
                      "shell desktop panel service should return the selected active panel"))
      (let* ((desktop-select-response
               (sbcl-agent::command-shell-desktop-select-service session :workspace :index 0))
             (desktop-select (sbcl-agent::service-response-data desktop-select-response)))
        (assert-equal :desktop-select
                      (getf desktop-select-response :operation)
                      "shell desktop select service should identify desktop-select operation")
        (assert-service-metadata-shape desktop-select-response "shell desktop select service")
        (assert-equal :workspace
                      (getf desktop-select :panel-id)
                      "shell desktop select service should report the selected panel")
        (assert-equal :workspace
                      (getf (getf desktop-select :desktop-model) :active-panel)
                      "shell desktop select service should make workspace the active panel")
        (assert-equal (getf (getf desktop-select :selection) :selected-index)
                      (getf (getf (getf (getf desktop-select :desktop-model) :panels) :workspace)
                            :selected-index)
                      "shell desktop select service should restore workspace selected index in the desktop model")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf (getf desktop-select :desktop-model) :focus-object-id)
                      "shell desktop select service should preserve the selected focus object"))
      (let* ((desktop-select-governance-response
               (sbcl-agent::command-shell-desktop-select-service session :governance :index 0))
             (desktop-select-governance (sbcl-agent::service-response-data desktop-select-governance-response)))
        (assert-equal :governance
                      (getf desktop-select-governance :panel-id)
                      "shell desktop select service should support governance selection")
        (assert-equal :governance
                      (getf (getf desktop-select-governance :desktop-model) :active-panel)
                      "shell desktop select service should return governance as the active panel")
        (assert-true (stringp (getf (getf (getf (getf desktop-select-governance :desktop-model) :panels)
                                                :governance)
                                      :selected-title))
                     "shell desktop select service should expose governance selected title in the desktop model"))
      (let* ((desktop-model (sbcl-agent::service-response-data
                             (sbcl-agent::query-shell-desktop-model-service session)))
             (desktop-governance-action (getf (getf (getf (getf desktop-model :panels)
                                                          :governance)
                                                    :actions)
                                              :activate))
             (desktop-action-response
               (sbcl-agent::command-shell-desktop-action-service session desktop-governance-action))
             (desktop-action (sbcl-agent::service-response-data desktop-action-response)))
        (assert-equal :desktop-action
                      (getf desktop-action-response :operation)
                      "shell desktop action service should identify desktop-action operation")
        (assert-service-metadata-shape desktop-action-response "shell desktop action service")
        (assert-equal :governance
                      (getf (getf desktop-action :desktop-model) :active-panel)
                      "shell desktop action service should activate the selected panel"))
      (let* ((display-desktop-model (sbcl-agent::service-response-data
                                     (sbcl-agent::query-shell-desktop-model-service session)))
             (display-next-action (getf (getf (getf (getf display-desktop-model :panels)
                                                    :display)
                                              :actions)
                                        :next))
             (display-step-action-response
               (sbcl-agent::command-shell-desktop-action-service session display-next-action))
             (display-step-action (sbcl-agent::service-response-data display-step-action-response)))
        (assert-equal :desktop-action
                      (getf display-step-action-response :operation)
                      "shell desktop action service should identify display step actions")
        (assert-equal :step-panel
                      (getf (getf display-step-action :action) :action-kind)
                      "shell desktop action service should preserve display step action kind")
        (assert-equal :display
                      (getf (getf display-step-action :result) :panel-id)
                      "shell desktop action service should keep display step actions in the display panel")
        (assert-equal :next
                      (getf (getf display-step-action :result) :direction)
                      "shell desktop action service should preserve display step direction"))
      (let* ((desktop-model (sbcl-agent::service-response-data
                             (sbcl-agent::query-shell-desktop-model-service session)))
             (desktop-governance-action-id
               (getf (getf (getf (getf (getf desktop-model :panels)
                                       :governance)
                                 :actions)
                           :activate)
                     :action-id))
             (desktop-action-response
               (sbcl-agent::command-shell-desktop-action-service session
                                                                 (list :action-id desktop-governance-action-id)))
             (desktop-action (sbcl-agent::service-response-data desktop-action-response)))
        (assert-equal desktop-governance-action-id
                      (getf (getf desktop-action :action) :action-id)
                      "shell desktop action service should resolve desktop actions by action id")
        (assert-equal :governance
                      (getf (getf desktop-action :desktop-model) :active-panel)
                      "shell desktop action service should preserve the activated panel when resolved by id"))
      (let* ((desktop-select-object-response
               (sbcl-agent::command-shell-desktop-select-service session :object-browser :index 0 :object-kind :work-item))
             (desktop-select-object (sbcl-agent::service-response-data desktop-select-object-response)))
        (assert-equal :object-browser
                      (getf desktop-select-object :panel-id)
                      "shell desktop select service should support object-browser selection")
        (assert-equal :object-browser
                      (getf (getf desktop-select-object :desktop-model) :active-panel)
                      "shell desktop select service should return object-browser as the active panel")
        (assert-equal :work-item
                      (getf (getf (getf (getf desktop-select-object :desktop-model) :panels)
                                  :object-browser)
                            :selected-kind)
                      "shell desktop select service should preserve selected object-browser kind in the desktop model"))
      (let* ((desktop-model (sbcl-agent::service-response-data
                             (sbcl-agent::query-shell-desktop-model-service session)))
             (workspace-panel-state (getf (getf desktop-model :panels) :workspace))
             (desktop-restore-response
               (sbcl-agent::command-shell-desktop-restore-service session
                                                                  :panel-state workspace-panel-state))
             (desktop-restore (sbcl-agent::service-response-data desktop-restore-response)))
        (assert-equal :desktop-restore
                      (getf desktop-restore-response :operation)
                      "shell desktop restore service should identify desktop-restore operation")
        (assert-service-metadata-shape desktop-restore-response "shell desktop restore service")
        (assert-equal :workspace
                      (getf (getf desktop-restore :desktop-model) :active-panel)
                      "shell desktop restore service should restore the requested panel")
        (assert-equal (getf workspace-panel-state :selected-index)
                      (getf (getf (getf (getf desktop-restore :desktop-model) :panels) :workspace)
                            :selected-index)
                      "shell desktop restore service should restore workspace selection posture"))
      (let* ((desktop-model (sbcl-agent::service-response-data
                             (sbcl-agent::query-shell-desktop-model-service session)))
             (workspace-restore-action
               (getf (getf (getf (getf desktop-model :panels)
                                 :workspace)
                           :actions)
                     :restore))
             (desktop-action-response
               (sbcl-agent::command-shell-desktop-action-service session workspace-restore-action))
             (desktop-action (sbcl-agent::service-response-data desktop-action-response)))
        (assert-equal :workspace
                      (getf (getf desktop-action :desktop-model) :active-panel)
                      "shell desktop action service should support restore actions")
        (assert-equal :workspace
                      (getf (getf desktop-action :result) :panel-id)
                      "shell desktop action service should preserve restore panel identity"))
      (let* ((desktop-model (sbcl-agent::service-response-data
                             (sbcl-agent::query-shell-desktop-model-service session)))
             (desktop-governance-open-action (getf (getf (getf (getf desktop-model :panels)
                                                               :governance)
                                                         :actions)
                                                   :open))
             (desktop-action-response
               (sbcl-agent::command-shell-desktop-action-service session desktop-governance-open-action))
             (desktop-action (sbcl-agent::service-response-data desktop-action-response)))
        (assert-equal :governance
                      (getf (getf desktop-action :result) :open-via)
                      "shell desktop action service should preserve governance open routing"))
      (let* ((desktop-select-inspector-response
               (sbcl-agent::command-shell-desktop-select-service session :inspector))
             (desktop-select-inspector (sbcl-agent::service-response-data desktop-select-inspector-response)))
        (assert-equal :inspector
                      (getf desktop-select-inspector :panel-id)
                      "shell desktop select service should support inspector selection")
        (assert-equal :inspector
                      (getf (getf desktop-select-inspector :desktop-model) :active-panel)
                      "shell desktop select service should return inspector as the active panel"))
      (let* ((surface-list-response (sbcl-agent::query-shell-surface-list-service session))
             (surface-list (sbcl-agent::service-response-data surface-list-response)))
        (assert-equal :surface-list
                      (getf surface-list-response :operation)
                      "shell surface list service should identify surface-list operation")
        (assert-service-metadata-shape surface-list-response "shell surface list service")
        (assert-true (> (getf surface-list :count) 0)
                     "shell surface list service should expose execution surfaces")
        (assert-true (integerp (getf surface-list :focus-index))
                     "shell surface list service should expose a focus index"))
      (let* ((surface-select-response
               (sbcl-agent::command-shell-surface-select-service session :index 0 :source :test))
             (surface-select (sbcl-agent::service-response-data surface-select-response)))
        (assert-equal :surface-select
                      (getf surface-select-response :operation)
                      "shell surface select service should identify surface-select operation")
        (assert-service-metadata-shape surface-select-response "shell surface select service")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf surface-select :focus-object-id)
                      "shell surface select service should persist shell focus"))
      (let* ((surface-step-response
               (sbcl-agent::command-shell-surface-step-service session :next))
             (surface-step (sbcl-agent::service-response-data surface-step-response)))
        (assert-equal :surface-step
                      (getf surface-step-response :operation)
                      "shell surface step service should identify surface-step operation")
        (assert-service-metadata-shape surface-step-response "shell surface step service")
        (assert-equal :next
                      (getf surface-step :direction)
                      "shell surface step service should preserve direction")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf surface-step :focus-object-id)
                      "shell surface step service should persist shell focus"))
      (let* ((open-response
               (sbcl-agent::command-shell-open-service session :surface-index 0 :source :test))
             (open (sbcl-agent::service-response-data open-response)))
        (assert-equal :open
                      (getf open-response :operation)
                      "shell open service should identify open operation")
        (assert-service-metadata-shape open-response "shell open service")
        (assert-equal :surface
                      (getf open :open-via)
                      "shell open service should record the surface entry path")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf open :focus-object-id)
                      "shell open service should persist shell focus")
        (assert-true (member (getf (getf open :inspection) :object-kind)
                             '(:workflow-record :work-item :incident :turn :runtime :execution :compatibility-execution))
                     "shell open service should return inspected kernel object data"))
      (let* ((governance-response (sbcl-agent::query-shell-governance-queue-service session))
             (governance (sbcl-agent::service-response-data governance-response)))
        (assert-equal :governance-queue
                      (getf governance-response :operation)
                      "shell governance queue service should identify governance-queue operation")
        (assert-service-metadata-shape governance-response "shell governance queue service")
        (assert-true (> (getf governance :count) 0)
                     "shell governance queue service should surface blocked operator work")
        (assert-true (member (getf (getf governance :top-item) :queue-kind)
                             '(:approval :blocked-work :incident))
                     "shell governance queue service should classify top queue items"))
      (let* ((browser-response (sbcl-agent::query-shell-object-browser-service session))
             (browser (sbcl-agent::service-response-data browser-response)))
        (assert-equal :object-browser
                      (getf browser-response :operation)
                      "shell object browser service should identify object-browser operation")
        (assert-service-metadata-shape browser-response "shell object browser service")
        (assert-true (> (getf browser :group-count) 0)
                     "shell object browser service should expose grouped objects")
        (assert-true (stringp (getf browser :focus-object-id))
                     "shell object browser service should expose a focus execution id")
        (let* ((object-select-response
                 (sbcl-agent::command-shell-object-select-service session :work-item :index 0))
               (object-select (sbcl-agent::service-response-data object-select-response)))
          (assert-equal :object-select
                        (getf object-select-response :operation)
                        "shell object select service should identify object-select operation")
          (assert-service-metadata-shape object-select-response "shell object select service")
          (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                        (getf object-select :focus-object-id)
                        "shell object select service should persist shell focus")
          (assert-true (stringp (getf object-select :selected-title))
                       "shell object select service should expose the selected title")))
      (let* ((governance-select-response
               (sbcl-agent::command-shell-governance-select-service session :index 0))
             (governance-select (sbcl-agent::service-response-data governance-select-response))
             (selected-focus-id (getf governance-select :focus-object-id)))
        (assert-equal :governance-select
                      (getf governance-select-response :operation)
                      "shell governance select service should identify governance-select operation")
        (assert-service-metadata-shape governance-select-response "shell governance select service")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      selected-focus-id
                      "shell governance select service should persist shell focus")
        (assert-true (stringp (getf (getf governance-select :selected-item) :title))
                     "shell governance select service should expose the selected title")
        (let* ((focus-set-response
                 (sbcl-agent::command-shell-focus-set-service session selected-focus-id))
               (focus-set (sbcl-agent::service-response-data focus-set-response)))
          (assert-equal :focus-set
                        (getf focus-set-response :operation)
                        "shell focus set service should identify focus-set operation")
          (assert-service-metadata-shape focus-set-response "shell focus set service")
          (assert-equal selected-focus-id
                        (getf focus-set :focus-object-id)
                        "shell focus set service should preserve the selected focus object"))
        (let* ((open-governance-response
                 (sbcl-agent::command-shell-open-service session :governance-index 0 :source :test))
               (open-governance (sbcl-agent::service-response-data open-governance-response)))
          (assert-equal :governance
                        (getf open-governance :open-via)
                        "shell open service should support governance queue entry")
          (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                        (getf open-governance :focus-object-id)
                        "shell open governance should persist shell focus")))
      (let* ((open-object-response
               (sbcl-agent::command-shell-open-service session
                                                       :object-kind :work-item
                                                       :object-index 0
                                                       :source :test))
             (open-object (sbcl-agent::service-response-data open-object-response)))
        (assert-equal :object-browser
                      (getf open-object :open-via)
                      "shell open service should support object-browser entry")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf open-object :focus-object-id)
                      "shell open object-browser should persist shell focus"))
      (let* ((inspector-response (sbcl-agent::query-shell-inspector-service session focus-object-id))
             (inspector (sbcl-agent::service-response-data inspector-response)))
        (assert-equal :inspector
                      (getf inspector-response :operation)
                      "shell inspector service should identify inspector operation")
        (assert-service-metadata-shape inspector-response "shell inspector service")
        (assert-equal focus-object-id
                      (getf inspector :focus-object-id)
                      "shell inspector service should preserve the focused execution id")
        (assert-true (member (getf inspector :object-kind)
                             '(:workflow-record :work-item :incident :turn :runtime :execution :compatibility-execution))
                     "shell inspector service should resolve focused kernel objects")
        (assert-true (listp (getf inspector :summary))
                     "shell inspector service should expose a compact inspector summary")
        (assert-true (integerp (getf (getf inspector :summary) :history-count))
                     "shell inspector service should expose forensic history counts in its compact summary")
        (assert-true (listp (getf inspector :recommended-action))
                     "shell inspector service should expose a recommended next action"))
      (let* ((focused-inspector-response (sbcl-agent::query-shell-inspector-service session))
             (focused-inspector (sbcl-agent::service-response-data focused-inspector-response)))
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf focused-inspector :focus-object-id)
                      "shell inspector service without an explicit object should follow persisted shell focus")))))

(defun platform-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/platform-service-contract/"))
         (output-path "/tmp/platform-service-contract.aop")
         (manifest-response (sbcl-agent::query-platform-manifest-service
                             :capability-ids '(:proc/run :git/status)
                             :session session))
         (manifest (sbcl-agent::service-response-data manifest-response)))
    (ensure-directories-exist "/tmp/platform-service-contract/")
    (when (probe-file output-path)
      (delete-file output-path))
    (assert-equal :platform
                  (getf manifest-response :domain)
                  "platform manifest service should report platform domain")
    (assert-equal :manifest
                  (getf manifest-response :operation)
                  "platform manifest service should identify manifest operation")
    (assert-service-metadata-shape manifest-response "platform manifest service")
    (assert-equal 2 (getf manifest :capability-count)
                  "platform manifest service should filter capabilities")
    (assert-equal "intentos.aop.v1"
                  (getf manifest :package-format)
                  "platform manifest service should expose the package format")
    (assert-equal '(:invoke :inspect :control)
                  (getf manifest :kernel-api)
                  "platform manifest service should expose the execution-kernel api")
    (assert-true (> (getf manifest :workflow-count) 0)
                 "platform manifest service should expose governed workflow inventory")
    (assert-true (> (getf manifest :sdk-command-count) 0)
                 "platform manifest service should expose sdk entrypoint inventory")
    (assert-true (> (getf manifest :compatibility-app-count) 0)
                 "platform manifest service should expose compatibility app inventory")
    (assert-true (> (getf manifest :compatibility-kind-count) 0)
                 "platform manifest service should expose compatibility inventory")
    (assert-true (find :compatibility-host-process
                       (getf manifest :workflows)
                       :key (lambda (entry) (getf entry :workflow-id))
                       :test #'eq)
                 "platform manifest service should expose the compatibility host-process workflow when compatible capabilities are selected")
    (assert-true (find :desktop/show
                       (getf manifest :sdk-commands)
                       :key (lambda (entry) (getf entry :command-id))
                       :test #'eq)
                 "platform manifest service should expose desktop host sdk entrypoints")
      (let* ((package-response
             (sbcl-agent::command-platform-package-service output-path
                                                          :package-id "demo-kit"
                                                          :package-version "1.2.0"
                                                          :title "Demo Kit"
                                                          :capability-ids '(:proc/run)
                                                          :session session))
           (package-result (sbcl-agent::service-response-data package-response)))
      (assert-equal :package
                    (getf package-response :operation)
                    "platform package service should identify package operation")
      (assert-service-metadata-shape package-response "platform package service")
      (assert-equal "demo-kit"
                    (getf package-result :package-id)
                    "platform package service should preserve the package id")
      (assert-equal "1.2.0"
                    (getf package-result :package-version)
                    "platform package service should preserve the package version")
      (assert-equal t
                    (getf package-result :contract-compatible-p)
                    "platform package service should export a contract-compatible package descriptor")
      (assert-equal t
                    (getf package-result :support-valid-p)
                    "platform package service should export a support-valid package descriptor")
      (assert-equal t
                    (getf package-result :lifecycle-valid-p)
                    "platform package service should export a lifecycle-valid package descriptor")
      (assert-equal nil
                    (getf package-result :lifecycle-override-required-p)
                    "platform package service should export active packages without lifecycle override posture")
      (assert-equal t
                    (getf package-result :recovery-valid-p)
                    "platform package service should export a recovery-valid package descriptor")
      (assert-equal nil
                    (getf package-result :recovery-override-required-p)
                    "platform package service should export default recovery posture without explicit override")
      (assert-equal t
                    (getf package-result :provenance-valid-p)
                    "platform package service should export a provenance-valid package descriptor")
      (assert-equal t
                    (getf package-result :provenance-trusted-p)
                    "platform package service should export a provenance-trusted package descriptor")
      (assert-equal t
                    (getf package-result :integrity-valid-p)
                    "platform package service should export an integrity-valid package descriptor")
      (assert-true (> (getf package-result :workflow-count) 0)
                   "platform package service should return workflow inventory counts")
      (assert-true (probe-file output-path)
                   "platform package service should write the requested descriptor")
      (let ((contents (uiop:read-file-string output-path)))
        (assert-true (search "\"package_id\":\"demo-kit\"" contents)
                     "platform package service should persist the package id")
        (assert-true (search "\"package_version\":\"1.2.0\"" contents)
                     "platform package service should persist the package version")
        (assert-true (search "\"requires\"" contents)
                     "platform package service should persist runtime compatibility requirements")
        (assert-true (search "\"support\"" contents)
                     "platform package service should persist support metadata")
        (assert-true (search "\"release_channel\":\"stable\"" contents)
                     "platform package service should persist support posture")
        (assert-true (search "\"lifecycle\"" contents)
                     "platform package service should persist lifecycle metadata")
        (assert-true (search "\"release_status\":\"active\"" contents)
                     "platform package service should persist active lifecycle posture")
        (assert-true (search "\"recovery\"" contents)
                     "platform package service should persist recovery metadata")
        (assert-true (search "\"rollback_strategy\":\"reinstall-prior\"" contents)
                     "platform package service should persist default recovery posture")
        (assert-true (search "\"provenance\"" contents)
                     "platform package service should persist provenance metadata")
        (assert-true (search "\"publisher\":\"local-developer\"" contents)
                     "platform package service should persist publisher provenance")
        (assert-true (search "\"attested_p\":true" contents)
                     "platform package service should persist attestation posture")
        (assert-true (search "\"integrity\"" contents)
                     "platform package service should persist integrity metadata")
        (assert-true (search "\"algorithm\":\"fnv1a-64\"" contents)
                     "platform package service should persist the package integrity algorithm")
        (assert-true (search "\"required_desktop_contract\":\"desktop-shell-v1\"" contents)
                     "platform package service should persist the desktop host contract requirement")
        (assert-true (search "\"capability_count\":1" contents)
                     "platform package service should persist the selected capability filter")
        (assert-true (search "\"compatibility_app_ids\"" contents)
                     "platform package service should persist a top-level compatibility app contents index")
        (assert-true (search "\"workflow_ids\"" contents)
                     "platform package service should persist a top-level workflow contents index")
        (assert-true (search "\"sdk_command_ids\"" contents)
                     "platform package service should persist a top-level sdk command contents index")
        (assert-true (search "\"desktop-host-shell\"" contents)
                     "platform package service should persist desktop host workflow metadata")))
      (let* ((kernel-output-path "/tmp/platform-service-contract-kernel.aop")
             (kernel-package-data
               (sbcl-agent::execute-platform-package-command
                (list :output-path kernel-output-path
                      :package-id "demo-kit-kernel"
                      :package-version "1.2.1"
                      :title "Demo Kit Kernel"
                      :capabilities '(:proc/run))
                session))
             (kernel-package-handle
               (sbcl-agent::kernel-find-execution-by-target :platform-package-id
                                                            "demo-kit-kernel"
                                                            (sbcl-agent::session-bound-environment session))))
        (assert-equal "demo-kit-kernel"
                      (getf kernel-package-data :package-id)
                      "shell platform package execution should preserve package data")
        (assert-true (listp kernel-package-handle)
                     "shell platform package execution should record a kernel execution handle")
        (assert-equal "platform/package"
                      (getf kernel-package-handle :capability)
                      "shell platform package execution should record the kernel capability")
        (assert-equal "demo-kit-kernel"
                      (getf (getf kernel-package-handle :target) :platform-package-id)
                      "shell platform package execution should capture the platform package target"))
      (let* ((show-response (sbcl-agent::query-platform-package-service output-path
                                                                        :session session))
             (show-result (sbcl-agent::service-response-data show-response)))
        (assert-equal :package
                      (getf show-response :operation)
                      "platform package query service should identify package operation")
        (assert-service-metadata-shape show-response "platform package query service")
        (assert-equal "1.2.0"
                      (getf show-result :package-version)
                      "platform package query service should preserve the package version")
        (assert-equal t
                      (getf show-result :contract-compatible-p)
                      "platform package query service should mark exported descriptors contract-compatible")
        (assert-equal t
                      (getf show-result :support-valid-p)
                      "platform package query service should mark exported descriptors support-valid")
        (assert-equal t
                      (getf show-result :lifecycle-valid-p)
                      "platform package query service should mark exported descriptors lifecycle-valid")
        (assert-equal t
                      (getf show-result :recovery-valid-p)
                      "platform package query service should mark exported descriptors recovery-valid")
        (assert-equal t
                      (getf show-result :provenance-valid-p)
                      "platform package query service should mark exported descriptors provenance-valid")
        (assert-equal t
                      (getf show-result :provenance-trusted-p)
                      "platform package query service should mark exported descriptors provenance-trusted")
        (assert-equal t
                      (getf show-result :integrity-valid-p)
                      "platform package query service should mark exported descriptors integrity-valid")
        (assert-equal t
                      (getf show-result :valid-p)
                      "platform package query service should report valid descriptors")
        (assert-equal :new
                      (getf show-result :update-posture)
                      "platform package query service should mark brand-new descriptors as new"))
      (let* ((validate-response
               (sbcl-agent::command-platform-validate-package-service output-path
                                                                      :session session))
             (validate-result (sbcl-agent::service-response-data validate-response)))
        (assert-equal :validate-package
                      (getf validate-response :operation)
                      "platform package validate service should identify validation operation")
        (assert-service-metadata-shape validate-response "platform package validate service")
        (assert-equal "1.2.0"
                      (getf validate-result :package-version)
                      "platform package validate service should preserve the package version")
        (assert-equal t
                      (getf validate-result :contract-compatible-p)
                      "platform package validate service should preserve contract-compatibility state")
        (assert-equal t
                      (getf validate-result :support-valid-p)
                      "platform package validate service should preserve support-valid state")
        (assert-equal t
                      (getf validate-result :lifecycle-valid-p)
                      "platform package validate service should preserve lifecycle-valid state")
        (assert-equal t
                      (getf validate-result :recovery-valid-p)
                      "platform package validate service should preserve recovery-valid state")
        (assert-equal t
                      (getf validate-result :provenance-valid-p)
                      "platform package validate service should preserve provenance-valid state")
        (assert-equal t
                      (getf validate-result :provenance-trusted-p)
                      "platform package validate service should preserve provenance-trusted state")
        (assert-equal t
                      (getf validate-result :integrity-valid-p)
                      "platform package validate service should preserve integrity-valid state")
        (assert-equal t
                      (getf validate-result :valid-p)
                      "platform package validate service should report valid descriptors")
        (assert-equal :new
                      (getf validate-result :update-posture)
                      "platform package validate service should mark brand-new descriptors as new"))
      (let* ((import-response
               (sbcl-agent::command-platform-import-package-service output-path
                                                                   :session session))
             (import-result (sbcl-agent::service-response-data import-response)))
        (assert-equal :import-package
                      (getf import-response :operation)
                      "platform package import service should identify import operation")
        (assert-service-metadata-shape import-response "platform package import service")
        (assert-equal 1
                      (getf import-result :registry-count)
                      "platform package import service should register the imported package")
        (assert-equal "demo-kit"
                      (getf (getf import-result :package) :package-id)
                      "platform package import service should return the imported package summary")
        (assert-equal "1.2.0"
                      (getf (getf import-result :package) :package-version)
                      "platform package import service should preserve the imported package version")
        (assert-equal :new
                      (getf (getf import-result :package) :update-posture)
                      "platform package import service should mark the first import as new"))
      (let* ((history-response
               (sbcl-agent::query-platform-package-history-service :session session))
             (history-result (sbcl-agent::service-response-data history-response)))
        (assert-equal :package-history
                      (getf history-response :operation)
                      "platform package history service should identify the history operation")
        (assert-service-metadata-shape history-response "platform package history service")
        (assert-equal 1
                      (getf history-result :count)
                      "platform package history service should record the initial import event")
        (assert-equal :import
                      (getf (first (getf history-result :entries)) :action)
                      "platform package history service should record import actions"))
      (let* ((audit-response
               (sbcl-agent::query-platform-audit-service :session session))
             (audit-result (sbcl-agent::service-response-data audit-response)))
        (assert-equal :audit
                      (getf audit-response :operation)
                      "platform audit service should identify the audit operation")
        (assert-service-metadata-shape audit-response "platform audit service")
        (assert-equal 1
                      (getf audit-result :count)
                      "platform audit service should report imported package count")
        (assert-equal 0
                      (getf audit-result :override-count)
                      "platform audit service should not report override usage before any override-granted import")
        (assert-equal 1
                      (getf audit-result :manual-update-count)
                      "platform audit service should report manual update posture from imported package support metadata"))
      (let* ((simulate-same-response
               (sbcl-agent::query-platform-simulate-package-service output-path
                                                                   :session session))
             (simulate-same-result (sbcl-agent::service-response-data simulate-same-response)))
        (assert-equal :same-version
                      (getf simulate-same-result :update-posture)
                      "platform package simulation service should recognize same-version replacement posture immediately after import"))
      (let* ((registry-response
               (sbcl-agent::query-platform-package-registry-service :session session))
             (registry-result (sbcl-agent::service-response-data registry-response)))
        (assert-equal :package-registry
                      (getf registry-response :operation)
                      "platform package registry service should identify the registry operation")
        (assert-service-metadata-shape registry-response "platform package registry service")
        (assert-equal 1
                      (getf registry-result :count)
                      "platform package registry service should expose imported package count")
        (assert-equal 0
                      (getf registry-result :active-count)
                      "platform package registry service should report no active packages before activation"))
      (let* ((imported-response
               (sbcl-agent::query-platform-imported-package-service "demo-kit" :session session))
             (imported-result (sbcl-agent::service-response-data imported-response)))
        (assert-equal :imported-package
                      (getf imported-response :operation)
                      "platform imported package service should identify the imported package operation")
        (assert-service-metadata-shape imported-response "platform imported package service")
        (assert-equal "demo-kit"
                      (getf imported-result :package-id)
                      "platform imported package service should return the imported package by id")
        (assert-equal "1.2.0"
                      (getf imported-result :package-version)
                      "platform imported package service should preserve imported package version"))
      (let* ((activate-response
               (sbcl-agent::command-platform-activate-package-service "demo-kit"
                                                                     :session session))
             (activate-result (sbcl-agent::service-response-data activate-response)))
        (assert-equal :activate-package
                      (getf activate-response :operation)
                      "platform package activation service should identify the activation operation")
        (assert-service-metadata-shape activate-response "platform package activation service")
        (assert-equal t
                      (getf (getf activate-result :package) :active-p)
                      "platform package activation service should mark the package active"))
      (let* ((app-response
               (sbcl-agent::query-compatibility-apps-service :app-id "linux.echo"
                                                             :session session))
             (app-entry (first (getf (sbcl-agent::service-response-data app-response) :entries))))
        (assert-equal "demo-kit"
                      (getf app-entry :source-package-id)
                      "active platform packages should project compatibility apps back into the effective registry")
        (assert-equal :linux-app-launch
                      (getf app-entry :policy-id)
                      "active platform package compatibility apps should preserve their launch policy"))
      (sbcl-agent::approve-policy session :process-run)
      (sbcl-agent::approve-policy session :linux-app-launch)
      (let* ((app-launch-response
               (sbcl-agent::command-kernel-invoke-service session
                                                          "Launch platform-provided linux echo app."
                                                          "linux.echo"
                                                          :payload (list :arguments '("from-package"))))
             (app-inspection
               (sbcl-agent::service-response-data
                (sbcl-agent::query-kernel-inspect-service session
                                                          (getf (sbcl-agent::service-response-metadata app-launch-response)
                                                                :execution-id)))))
        (assert-equal "demo-kit"
                      (getf (getf app-inspection :inspection) :source-package-id)
                      "kernel inspect should preserve platform-provided compatibility app provenance on execution handles"))
      (let* ((active-response
               (sbcl-agent::query-platform-active-packages-service :session session))
             (active-result (sbcl-agent::service-response-data active-response)))
        (assert-equal :active-packages
                      (getf active-response :operation)
                      "platform active-packages service should identify the active package operation")
        (assert-service-metadata-shape active-response "platform active-packages service")
        (assert-equal 1
                      (getf active-result :count)
                      "platform active-packages service should report the active imported package")
        (assert-equal "demo-kit"
                      (getf (first (getf active-result :packages)) :package-id)
                      "platform active-packages service should return the activated package by id"))
      (let* ((profile-response
               (sbcl-agent::query-platform-profile-service :session session))
             (profile-result (sbcl-agent::service-response-data profile-response)))
        (assert-equal :profile
                      (getf profile-response :operation)
                      "platform profile service should identify the applied profile operation")
        (assert-service-metadata-shape profile-response "platform profile service")
        (assert-equal 1
                      (getf profile-result :count)
                      "platform profile service should report the active imported package count")
        (assert-equal 1
                      (getf profile-result :capability-count)
                      "platform profile service should expose the applied active-package capability set"))
      (let* ((registry-response
               (sbcl-agent::query-platform-package-registry-service :session session))
             (registry-result (sbcl-agent::service-response-data registry-response)))
        (assert-equal 1
                      (getf registry-result :active-count)
                      "platform package registry service should report one active package after activation"))
      (let* ((deactivate-response
               (sbcl-agent::command-platform-deactivate-package-service "demo-kit"
                                                                       :session session))
             (deactivate-result (sbcl-agent::service-response-data deactivate-response)))
        (assert-equal :deactivate-package
                      (getf deactivate-response :operation)
                      "platform package deactivation service should identify the deactivation operation")
        (assert-service-metadata-shape deactivate-response "platform package deactivation service")
        (assert-equal nil
                      (getf (getf deactivate-result :package) :active-p)
                      "platform package deactivation service should clear the active package flag"))
      (let* ((history-response
               (sbcl-agent::query-platform-package-history-service :session session
                                                                  :package-id "demo-kit"))
             (history-result (sbcl-agent::service-response-data history-response))
             (actions (mapcar (lambda (entry) (getf entry :action))
                              (getf history-result :entries))))
        (assert-equal 3
                      (getf history-result :count)
                      "platform package history service should record import, activate, and deactivate lifecycle events for one package")
        (assert-true (equal '(:import :activate :deactivate) actions)
                     "platform package history service should preserve action order for package lifecycle events"))
      (let* ((install-path "/tmp/platform-install-service-contract.aop"))
        (uiop:copy-file output-path install-path)
        (let* ((install-session (make-test-session :cwd "/tmp/platform-install-service-contract/"))
               (install-response
                 (sbcl-agent::command-platform-install-package-service install-path
                                                                      :session install-session))
               (install-result (sbcl-agent::service-response-data install-response)))
          (assert-equal :install-package
                        (getf install-response :operation)
                        "platform package install service should identify the install operation")
          (assert-service-metadata-shape install-response "platform package install service")
          (assert-equal t
                        (getf (getf install-result :package) :active-p)
                        "platform package install service should activate the imported package")
          (assert-equal 1
                        (getf (getf install-result :profile) :count)
                        "platform package install service should return the applied active-package profile")
          (let* ((install-history-response
                   (sbcl-agent::query-platform-package-history-service :session install-session
                                                                      :package-id "demo-kit"))
                 (install-history-result (sbcl-agent::service-response-data install-history-response))
                 (install-actions (mapcar (lambda (entry) (getf entry :action))
                                          (getf install-history-result :entries))))
            (assert-true (equal '(:import :activate :install) install-actions)
                         "platform package history service should record install lifecycle actions in order"))))
      (let* ((simulate-response
               (sbcl-agent::query-platform-simulate-package-service output-path
                                                                   :session session))
             (simulate-result (sbcl-agent::service-response-data simulate-response)))
        (assert-equal :simulate-package
                      (getf simulate-response :operation)
                      "platform package simulation service should identify the simulate operation")
        (assert-service-metadata-shape simulate-response "platform package simulation service")
        (assert-equal t
                      (getf simulate-result :valid-p)
                      "platform package simulation service should accept a valid descriptor")
        (assert-equal 1
                      (getf (getf simulate-result :simulated-profile) :count)
                      "platform package simulation service should preview one active package when simulating the descriptor into the current environment"))
      (let ((downgrade-path "/tmp/platform-downgrade-service-contract.aop"))
        (let ((downgrade-package-response
                (sbcl-agent::command-platform-package-service downgrade-path
                                                             :package-id "demo-kit"
                                                             :package-version "1.1.0"
                                                             :title "Demo Kit"
                                                             :capability-ids '(:proc/run)
                                                             :session session)))
          (assert-service-metadata-shape downgrade-package-response "platform downgrade package service"))
        (let ((downgrade-session (make-test-session :cwd "/tmp/platform-downgrade-service-contract/")))
          (sbcl-agent::command-platform-import-package-service output-path
                                                              :session downgrade-session)
          (let* ((downgrade-simulate-response
                   (sbcl-agent::query-platform-simulate-package-service downgrade-path
                                                                       :session downgrade-session))
                 (downgrade-simulate-result (sbcl-agent::service-response-data downgrade-simulate-response)))
            (assert-equal :downgrade
                          (getf downgrade-simulate-result :update-posture)
                          "platform package simulation service should identify downgrades explicitly")
            (assert-equal t
                          (getf downgrade-simulate-result :downgrade-p)
                          "platform package simulation service should flag downgrade posture")
            (assert-equal t
                          (getf downgrade-simulate-result :would-require-override-p)
                          "platform package simulation service should require explicit downgrade override"))
          (assert-signals-error
           (lambda ()
             (sbcl-agent::command-platform-import-package-service downgrade-path
                                                                 :session downgrade-session))
           "Refusing to downgrade platform package"
           "platform package import service should refuse downgrades without explicit override")
          (let* ((downgrade-import-response
                   (sbcl-agent::command-platform-import-package-service downgrade-path
                                                                       :session downgrade-session
                                                                       :allow-downgrade-p t))
                 (downgrade-import-result (sbcl-agent::service-response-data downgrade-import-response)))
            (assert-equal :downgrade
                          (getf (getf downgrade-import-result :package) :update-posture)
                          "platform package import service should mark explicit downgrade imports as downgrade posture")
          (assert-equal t
                        (getf (getf downgrade-import-result :package) :downgrade-p)
                        "platform package import service should preserve downgrade markers when override is granted"))))
      (let ((tampered-path "/tmp/platform-tampered-service-contract.aop"))
        (with-open-file (stream tampered-path
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (write-string (uiop:read-file-string output-path) stream))
        (let* ((contents (uiop:read-file-string tampered-path))
               (needle "\"title\":\"Demo Kit\"")
               (replacement "\"title\":\"Tampered Kit\"")
               (position (search needle contents))
               (tampered (if position
                             (concatenate 'string
                                          (subseq contents 0 position)
                                          replacement
                                          (subseq contents (+ position (length needle))))
                             contents)))
          (with-open-file (stream tampered-path
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
            (write-string tampered stream)))
        (let* ((tampered-response
                 (sbcl-agent::command-platform-validate-package-service tampered-path
                                                                        :session session))
               (tampered-result (sbcl-agent::service-response-data tampered-response)))
          (assert-equal nil
                        (getf tampered-result :valid-p)
                        "platform package validate service should reject tampered package descriptors")
        (assert-equal nil
                      (getf tampered-result :integrity-valid-p)
                      "platform package validate service should report failed integrity for tampered descriptors")
          (assert-true (find "integrity digest does not match package contents"
                             (getf tampered-result :validation-issues)
                             :test #'string=)
                       "platform package validate service should expose integrity mismatches explicitly")))
      (let ((support-tampered-path "/tmp/platform-support-tampered-service-contract.aop"))
        (with-open-file (stream support-tampered-path
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (write-string (uiop:read-file-string output-path) stream))
        (let* ((contents (uiop:read-file-string support-tampered-path))
               (needle "\"update_channel\":\"manual\"")
               (replacement "\"update_channel\":\"unsupported\"")
               (position (search needle contents))
               (tampered (if position
                             (concatenate 'string
                                          (subseq contents 0 position)
                                          replacement
                                          (subseq contents (+ position (length needle))))
                             contents)))
          (with-open-file (stream support-tampered-path
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
            (write-string tampered stream)))
        (let* ((support-tampered-response
                 (sbcl-agent::command-platform-validate-package-service support-tampered-path
                                                                        :session session))
               (support-tampered-result (sbcl-agent::service-response-data support-tampered-response)))
          (assert-equal nil
                        (getf support-tampered-result :valid-p)
                        "platform package validate service should reject invalid support metadata")
          (assert-equal nil
                        (getf support-tampered-result :support-valid-p)
                        "platform package validate service should report invalid support posture explicitly")
          (assert-true (find "support update_channel must be manual, managed, or pinned"
                             (getf support-tampered-result :validation-issues)
                             :test #'string=)
                       "platform package validate service should expose malformed support update channels")))
      (let ((provenance-tampered-path "/tmp/platform-provenance-tampered-service-contract.aop"))
        (with-open-file (stream provenance-tampered-path
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (write-string (uiop:read-file-string output-path) stream))
        (let* ((contents (uiop:read-file-string provenance-tampered-path))
               (needle "\"build_kind\":\"developer-package\"")
               (replacement "\"build_kind\":\"unknown-package\"")
               (position (search needle contents))
               (tampered (if position
                             (concatenate 'string
                                          (subseq contents 0 position)
                                          replacement
                                          (subseq contents (+ position (length needle))))
                             contents)))
          (with-open-file (stream provenance-tampered-path
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
            (write-string tampered stream)))
        (let* ((provenance-tampered-response
                 (sbcl-agent::command-platform-validate-package-service provenance-tampered-path
                                                                        :session session))
               (provenance-tampered-result (sbcl-agent::service-response-data provenance-tampered-response)))
          (assert-equal nil
                        (getf provenance-tampered-result :valid-p)
                        "platform package validate service should reject invalid provenance metadata")
          (assert-equal nil
                        (getf provenance-tampered-result :provenance-valid-p)
                        "platform package validate service should report invalid provenance posture explicitly")
          (assert-true (find "provenance build_kind must be developer-package, release-package, or internal-package"
                             (getf provenance-tampered-result :validation-issues)
                             :test #'string=)
                       "platform package validate service should expose malformed provenance build kinds")))
      (let ((manual-recovery-path "/tmp/platform-manual-recovery-service-contract.aop"))
        (let ((manual-recovery-package-response
                (sbcl-agent::command-platform-package-service manual-recovery-path
                                                             :package-id "ops-kit"
                                                             :package-version "3.0.0"
                                                             :title "Ops Kit"
                                                             :rollback-strategy "manual-recovery"
                                                             :failure-mode "manual-intervention"
                                                             :recovery-runbook "ops://runbooks/ops-kit"
                                                             :capability-ids '(:proc/run)
                                                             :session session)))
          (assert-service-metadata-shape manual-recovery-package-response "platform manual-recovery package service"))
        (let* ((manual-recovery-validate-response
                 (sbcl-agent::command-platform-validate-package-service manual-recovery-path
                                                                        :session session))
               (manual-recovery-validate-result (sbcl-agent::service-response-data manual-recovery-validate-response)))
          (assert-equal t
                        (getf manual-recovery-validate-result :valid-p)
                        "platform package validate service should accept structurally valid manual-recovery packages")
          (assert-equal t
                        (getf manual-recovery-validate-result :recovery-override-required-p)
                        "platform package validate service should mark manual-recovery packages as requiring explicit override"))
        (let* ((manual-recovery-simulate-response
                 (sbcl-agent::query-platform-simulate-package-service manual-recovery-path
                                                                     :session session))
               (manual-recovery-simulate-result (sbcl-agent::service-response-data manual-recovery-simulate-response)))
          (assert-equal t
                        (getf manual-recovery-simulate-result :would-require-recovery-override-p)
                        "platform package simulation service should require explicit recovery override for manual-recovery packages"))
        (assert-signals-error
         (lambda ()
           (sbcl-agent::command-platform-import-package-service manual-recovery-path
                                                               :session session))
         "Refusing to import manual-recovery platform package"
         "platform package import service should refuse manual-recovery packages without explicit override")
        (let* ((manual-recovery-import-response
                 (sbcl-agent::command-platform-import-package-service manual-recovery-path
                                                                     :session session
                                                                     :allow-manual-recovery-p t))
               (manual-recovery-import-result (sbcl-agent::service-response-data manual-recovery-import-response)))
          (assert-equal t
                        (getf (getf manual-recovery-import-result :package) :manual-recovery-p)
                        "platform package import service should preserve manual-recovery posture after override"))
        (let ((recovery-tampered-path "/tmp/platform-recovery-tampered-service-contract.aop"))
          (with-open-file (stream recovery-tampered-path
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
            (write-string (uiop:read-file-string manual-recovery-path) stream))
          (let* ((contents (uiop:read-file-string recovery-tampered-path))
                 (needle "\"recovery_runbook\":\"ops://runbooks/ops-kit\"")
                 (replacement "\"recovery_runbook\":\"\"")
                 (position (search needle contents))
                 (tampered (if position
                               (concatenate 'string
                                            (subseq contents 0 position)
                                            replacement
                                            (subseq contents (+ position (length needle))))
                               contents)))
            (with-open-file (stream recovery-tampered-path
                                    :direction :output
                                    :if-exists :supersede
                                    :if-does-not-exist :create)
              (write-string tampered stream)))
          (let* ((recovery-tampered-response
                   (sbcl-agent::command-platform-validate-package-service recovery-tampered-path
                                                                          :session session))
                 (recovery-tampered-result (sbcl-agent::service-response-data recovery-tampered-response)))
            (assert-equal nil
                          (getf recovery-tampered-result :valid-p)
                          "platform package validate service should reject invalid recovery metadata")
            (assert-equal nil
                          (getf recovery-tampered-result :recovery-valid-p)
                          "platform package validate service should report invalid recovery posture explicitly")
            (assert-true (find "recovery recovery_runbook is required for manual recovery posture"
                               (getf recovery-tampered-result :validation-issues)
                               :test #'string=)
                         "platform package validate service should expose malformed recovery metadata"))))
      (let ((untrusted-path "/tmp/platform-untrusted-service-contract.aop"))
        (let ((untrusted-package-response
                (sbcl-agent::command-platform-package-service untrusted-path
                                                             :package-id "untrusted-kit"
                                                             :package-version "1.0.0"
                                                             :title "Untrusted Kit"
                                                             :publisher "unknown-publisher"
                                                             :attested-p nil
                                                             :capability-ids '(:proc/run)
                                                             :session session)))
          (assert-service-metadata-shape untrusted-package-response "platform untrusted package service"))
        (let* ((untrusted-validate-response
                 (sbcl-agent::command-platform-validate-package-service untrusted-path
                                                                        :session session))
               (untrusted-validate-result (sbcl-agent::service-response-data untrusted-validate-response)))
          (assert-equal t
                        (getf untrusted-validate-result :valid-p)
                        "platform package validate service should accept structurally valid but untrusted provenance")
          (assert-equal nil
                        (getf untrusted-validate-result :provenance-trusted-p)
                        "platform package validate service should mark unknown unattested publishers as untrusted")
          (assert-true (find "package publisher is not in the trusted publisher set"
                             (getf untrusted-validate-result :provenance-trust-issues)
                             :test #'string=)
                       "platform package validate service should expose unknown publisher trust issues")
          (assert-true (find "package provenance is unattested"
                             (getf untrusted-validate-result :provenance-trust-issues)
                             :test #'string=)
                       "platform package validate service should expose unattested provenance trust issues"))
        (let* ((untrusted-simulate-response
                 (sbcl-agent::query-platform-simulate-package-service untrusted-path
                                                                      :session session))
               (untrusted-simulate-result (sbcl-agent::service-response-data untrusted-simulate-response)))
          (assert-equal t
                        (getf untrusted-simulate-result :would-require-trust-override-p)
                        "platform package simulation service should require an explicit trust override for untrusted packages"))
        (assert-signals-error
         (lambda ()
           (sbcl-agent::command-platform-import-package-service untrusted-path
                                                               :session session))
         "Refusing to import untrusted platform package"
         "platform package import service should refuse untrusted provenance without explicit override")
        (let* ((untrusted-import-response
                 (sbcl-agent::command-platform-import-package-service untrusted-path
                                                                     :session session
                                                                     :allow-untrusted-p t))
               (untrusted-import-result (sbcl-agent::service-response-data untrusted-import-response)))
          (assert-equal nil
                        (getf (getf untrusted-import-result :package) :provenance-trusted-p)
                        "platform package import service should preserve untrusted posture when explicitly overridden")))
      (let ((deprecated-path "/tmp/platform-deprecated-service-contract.aop"))
        (let ((deprecated-package-response
                (sbcl-agent::command-platform-package-service deprecated-path
                                                             :package-id "legacy-kit"
                                                             :package-version "2.0.0"
                                                             :title "Legacy Kit"
                                                             :release-status "deprecated"
                                                             :replacement-package-id "modern-kit"
                                                             :capability-ids '(:proc/run)
                                                             :session session)))
          (assert-service-metadata-shape deprecated-package-response "platform deprecated package service"))
        (let* ((deprecated-validate-response
                 (sbcl-agent::command-platform-validate-package-service deprecated-path
                                                                        :session session))
               (deprecated-validate-result (sbcl-agent::service-response-data deprecated-validate-response)))
          (assert-equal t
                        (getf deprecated-validate-result :valid-p)
                        "platform package validate service should accept structurally valid deprecated packages")
          (assert-equal t
                        (getf deprecated-validate-result :lifecycle-valid-p)
                        "platform package validate service should preserve lifecycle validity for deprecated packages")
          (assert-equal t
                        (getf deprecated-validate-result :lifecycle-override-required-p)
                        "platform package validate service should mark deprecated packages as requiring lifecycle override"))
        (let* ((deprecated-simulate-response
                 (sbcl-agent::query-platform-simulate-package-service deprecated-path
                                                                      :session session))
               (deprecated-simulate-result (sbcl-agent::service-response-data deprecated-simulate-response)))
          (assert-equal t
                        (getf deprecated-simulate-result :would-require-lifecycle-override-p)
                        "platform package simulation service should require lifecycle override for deprecated packages"))
        (assert-signals-error
         (lambda ()
           (sbcl-agent::command-platform-import-package-service deprecated-path
                                                               :session session))
         "Refusing to import deprecated platform package"
         "platform package import service should refuse deprecated packages without explicit lifecycle override")
        (let* ((deprecated-import-response
                 (sbcl-agent::command-platform-import-package-service deprecated-path
                                                                     :session session
                                                                     :allow-deprecated-p t))
               (deprecated-import-result (sbcl-agent::service-response-data deprecated-import-response)))
          (assert-equal t
                        (getf (getf deprecated-import-result :package) :deprecated-p)
                        "platform package import service should preserve deprecated posture when override is granted")))
      (let* ((audit-response
               (sbcl-agent::query-platform-audit-service :session session))
             (audit-result (sbcl-agent::service-response-data audit-response))
             (legacy-entry (find "legacy-kit"
                                 (getf audit-result :packages)
                                 :key (lambda (entry) (getf entry :package-id))
                                 :test #'string=))
             (ops-entry (find "ops-kit"
                              (getf audit-result :packages)
                              :key (lambda (entry) (getf entry :package-id))
                              :test #'string=))
             (untrusted-entry (find "untrusted-kit"
                                    (getf audit-result :packages)
                                    :key (lambda (entry) (getf entry :package-id))
                                    :test #'string=)))
        (assert-true (>= (getf audit-result :override-count) 3)
                     "platform audit service should count explicit override-granted imports")
        (assert-true (>= (getf audit-result :attention-count) 3)
                     "platform audit service should surface attention-required package posture")
        (assert-equal 1
                      (getf audit-result :untrusted-count)
                      "platform audit service should count untrusted imported packages")
        (assert-equal 1
                      (getf audit-result :deprecated-count)
                      "platform audit service should count deprecated imported packages")
        (assert-equal 1
                      (getf audit-result :manual-recovery-count)
                      "platform audit service should count manual-recovery imported packages")
        (assert-equal 1
                      (getf legacy-entry :override-count)
                      "platform audit service should preserve lifecycle override history per package")
        (assert-equal 1
                      (getf ops-entry :override-count)
                      "platform audit service should preserve manual-recovery override history per package")
        (assert-equal 1
                      (getf untrusted-entry :override-count)
                      "platform audit service should preserve trust override history per package"))
      (let* ((harness-response
               (sbcl-agent::query-platform-harness-service :session session))
             (harness-result (sbcl-agent::service-response-data harness-response)))
        (assert-equal :harness
                      (getf harness-response :operation)
                      "platform harness service should identify the harness inventory operation")
        (assert-service-metadata-shape harness-response "platform harness service")
        (assert-true (> (getf harness-result :count) 0)
                     "platform harness service should expose at least one harness")
        (assert-true (find :internal-evaluations
                           (getf harness-result :harnesses)
                           :key (lambda (entry) (getf entry :harness-id))
                           :test #'eq)
                     "platform harness service should expose the internal evaluations harness"))
      (let* ((run-harness-response
               (sbcl-agent::command-platform-run-harness-service :harness-id :internal-evaluations
                                                                 :session session))
             (run-harness-result (sbcl-agent::service-response-data run-harness-response)))
        (assert-equal :run-harness
                      (getf run-harness-response :operation)
                      "platform harness run service should identify the harness run operation")
        (assert-service-metadata-shape run-harness-response "platform harness run service")
        (assert-equal :internal-evaluations
                      (getf (getf run-harness-result :harness) :harness-id)
                      "platform harness run service should preserve the requested harness id")
        (assert-true (>= (getf (getf run-harness-result :report) :implemented-family-count) 4)
                     "platform harness run service should return the internal evaluation report"))
      (let* ((invalid-path "/tmp/platform-invalid-service-contract.aop"))
        (with-open-file (stream invalid-path
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (write-string "{\"package_format\":\"intentos.aop.v1\",\"package_id\":\"broken-kit\",\"package_version\":\"1.0.0\",\"requires\":{\"supported_package_format\":\"intentos.aop.v1\",\"supported_manifest_version\":1,\"required_kernel_class\":\"execution-kernel\",\"required_kernel_api\":[\"invoke\",\"inspect\",\"control\"],\"required_desktop_contract\":\"desktop-shell-v0\",\"required_surface_contract\":\"execution-surfaces-v1\"},\"title\":\"Broken Kit\",\"contents\":{\"capability_ids\":[],\"policy_ids\":[],\"workflow_ids\":[],\"sdk_command_ids\":[],\"compatibility_kinds\":[]},\"manifest\":{\"manifest_version\":1,\"kernel_class\":\"execution-kernel\",\"kernel_api\":[\"invoke\",\"inspect\",\"control\"],\"capabilities\":[],\"policies\":[],\"workflows\":[{\"workflow_id\":\"broken\",\"entrypoints\":[\"missing-command\"],\"required_capabilities\":[],\"control_actions\":[]}],\"sdk_commands\":[],\"compatibility_kinds\":[]}}" stream))
        (let* ((invalid-response
                 (sbcl-agent::command-platform-validate-package-service invalid-path
                                                                        :session session))
               (invalid-result (sbcl-agent::service-response-data invalid-response)))
          (assert-equal nil
                        (getf invalid-result :valid-p)
                        "platform package validate service should reject invalid workflow entrypoints")
          (assert-equal nil
                        (getf invalid-result :contract-compatible-p)
                        "platform package validate service should reject incompatible runtime contract requirements")
          (assert-true (find "manifest workflows contain invalid entrypoints or capability references"
                             (getf invalid-result :validation-issues)
                             :test #'string=)
                       "platform package validate service should expose structural workflow validation failures")
          (assert-true (find "requires required_desktop_contract does not match the supported desktop host contract"
                             (getf invalid-result :validation-issues)
                             :test #'string=)
                       "platform package validate service should expose incompatible desktop host contract requirements")))))

(defun execution-service-contract-test ()
  (let ((session (make-test-session :cwd (current-workspace-root)))
        (provider (make-test-provider)))
    (let ((ask-response (sbcl-agent::command-conversation-execution-service session
                                                                            provider
                                                                            "ping"
                                                                            '()
                                                                            :source :ask
                                                                            :operator-mode :repl-bridge)))
      (assert-equal :execution
                    (getf ask-response :domain)
                    "execution service should report execution domain")
      (assert-equal :ask
                    (getf ask-response :operation)
                    "execution service should identify ask execution")
      (assert-service-metadata-shape ask-response "execution ask service")
      (assert-true (typep (getf (sbcl-agent::service-response-data ask-response) :response)
                          'sbcl-agent::assistant-response)
                   "execution ask service should return an assistant response"))
    (let* ((action (sbcl-agent::make-assistant-action :type :eval :payload "(+ 1 2)"))
           (action-response (sbcl-agent::command-execute-assistant-action-service session action)))
      (assert-equal :assistant-action
                    (getf action-response :operation)
                    "assistant action execution service should identify assistant-action execution")
      (assert-service-metadata-shape action-response "assistant action execution service")
      (assert-equal 3
                    (getf (sbcl-agent::service-response-data action-response) :result)
                    "assistant action execution service should execute the action payload"))
    (let ((staged-action (sbcl-agent::make-assistant-action :type :eval :payload "(+ 2 3)")))
      (sbcl-agent::stage-pending-actions session (list staged-action))
      (let ((pending-response (sbcl-agent::command-execute-pending-actions-service session)))
        (assert-equal :pending-actions
                      (getf pending-response :operation)
                      "pending actions service should identify pending action execution")
        (assert-service-metadata-shape pending-response "pending actions execution service")
        (assert-equal 5
                      (getf (getf (first (sbcl-agent::service-response-data pending-response)) :result) :result)
                      "pending actions service should execute staged actions")
        (assert-equal 0
                      (length (sbcl-agent::agent-session-pending-actions session))
                      "pending actions service should clear staged actions after execution")))
    (let ((tool-response (sbcl-agent::command-invoke-tool-service session :fs/read '(:path "src/main.lisp"))))
      (assert-equal :tool
                    (getf tool-response :operation)
                    "tool execution service should identify tool execution")
      (assert-service-metadata-shape tool-response "tool execution service")
      (assert-equal :fs/read
                    (getf (sbcl-agent::service-response-data tool-response) :tool)
                    "tool execution service should preserve tool payload shape"))
    (sbcl-agent::approve-policy session :workspace-write)
    (let ((patch-response (sbcl-agent::command-apply-patch-service session '((:write "tmp/execution-service.txt" "ok")))))
      (assert-equal :patch
                    (getf patch-response :operation)
                    "patch execution service should identify patch execution")
      (assert-service-metadata-shape patch-response "patch execution service")
      (assert-equal :write
                    (getf (first (getf (sbcl-agent::service-response-data patch-response) :patch)) :operation)
                    "patch execution service should preserve patch payload shape"))))

(defun interaction-state-boundary-service-contract-test ()
  (labels ((assert-non-mutating-turn (prompt expected-mode)
             (let* ((session (make-test-session :cwd (current-workspace-root)))
                    (provider (make-test-provider))
                    (decision (sbcl-agent::classify-interaction-decision prompt))
                    (response (sbcl-agent::command-conversation-execution-service session
                                                                                  provider
                                                                                  prompt
                                                                                  '()
                                                                                  :source :say
                                                                                  :operator-mode :conversation))
                    (data (sbcl-agent::service-response-data response)))
               (assert-equal expected-mode
                             (sbcl-agent::interaction-decision-mode decision)
                             "interaction boundary execution should classify the prompt as expected")
               (assert-service-metadata-shape response "interaction boundary execution service")
               (assert-equal :execution
                             (getf response :domain)
                             "interaction boundary execution should report execution domain")
               (assert-equal :say
                             (getf response :operation)
                             "interaction boundary execution should identify say operation")
               (assert-equal :completed
                             (getf (getf data :turn) :status)
                             "non-mutating prompts should complete immediately")
               (assert-equal 0
                             (getf data :staged-action-count)
                             "non-mutating prompts should not stage actions")
               (assert-equal 0
                             (getf data :deferred-action-count)
                             "non-mutating prompts should not defer actions")
               (assert-equal 0
                             (getf data :immediate-action-count)
                             "non-mutating prompts should not execute actions immediately")
               (assert-equal 0
                             (length (sbcl-agent::agent-session-pending-actions session))
                             "non-mutating prompts should not leave pending actions behind")
               (assert-equal 0
                             (length (sbcl-agent::agent-session-work-items session))
                             "non-mutating prompts should not create governed work items")
               (assert-true (null (getf data :direct-runtime-eval-p))
                            "non-mutating prompts should not silently route into direct runtime eval"))))
    (assert-non-mutating-turn "Explain the current architecture and why it is structured this way."
                              :conversation)
    (assert-non-mutating-turn "Why is this runtime failing right now?"
                              :inspect)
    (assert-non-mutating-turn "What would you change to fix this failure before implementing anything?"
                              :prepare)
    (let* ((session (make-test-session :cwd (current-workspace-root)))
           (provider (make-instance 'mutating-eval-provider))
           (prompt "Implement the fix by mutating runtime state.")
           (decision (sbcl-agent::classify-interaction-decision prompt))
           (response (sbcl-agent::command-conversation-execution-service session
                                                                         provider
                                                                         prompt
                                                                         '()
                                                                         :source :say
                                                                         :operator-mode :conversation))
           (data (sbcl-agent::service-response-data response)))
      (assert-equal :mutate
                    (sbcl-agent::interaction-decision-mode decision)
                    "direct implementation prompts should classify as mutate")
      (assert-service-metadata-shape response "mutating interaction boundary execution service")
      (assert-equal :awaiting-approval
                    (getf (getf data :turn) :status)
                    "mutating prompts should enter governed approval flow")
      (assert-equal 1
                    (getf data :staged-action-count)
                    "mutating prompts should stage a governed action")
      (assert-equal 1
                    (length (sbcl-agent::agent-session-pending-actions session))
                    "mutating prompts should leave one pending governed action")
      (assert-equal 1
                    (length (sbcl-agent::agent-session-work-items session))
                    "mutating prompts should create one governed work item"))))

(defun project-authoring-tool-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/project-authoring-tool-service-contract/"))
         (project (sbcl-agent::create-project-record session
                                                     :title "Tooling Project"
                                                     :summary "Governed authoring by tool."))
         (project-id (sbcl-agent::project-record-id project)))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::command-invoke-tool-service
        session
        :project/append-requirement
        (list :project-id project-id
              :title "Blocked requirement"
              :summary "Should require governed approval.")))
     "Approval required for :PROJECT-GOVERNANCE-WRITE"
     "project authoring tools should enforce governed approval before mutation")
    (sbcl-agent::approve-policy session :project-governance-write)
    (let ((constitution-response
            (sbcl-agent::command-invoke-tool-service
             session
             :project/set-constitution
             (list :project-id project-id
                   :constitution '(:purpose "Governed SDLC execution"
                                   :principles ("traceability" "quality gates"))))))
      (assert-equal :tool
                    (getf constitution-response :operation)
                    "project constitution tool execution should identify tool execution")
      (assert-service-metadata-shape constitution-response "project constitution tool execution")
      (assert-equal "Governed SDLC execution"
                    (getf (getf (getf (sbcl-agent::service-response-data constitution-response) :project)
                                :constitution)
                          :purpose)
                    "project constitution tool should persist the constitution payload"))
    (let ((requirement-response
            (sbcl-agent::command-invoke-tool-service
             session
             :project/append-requirement
             (list :project-id project-id
                   :title "Capture requirements"
                   :summary "Requirements must be governed."
                   :priority "high"
                   :kind "functional"))))
      (assert-equal :project/append-requirement
                    (getf (sbcl-agent::service-response-data requirement-response) :tool)
                    "project requirement tool should preserve the executed tool id")
      (assert-equal 1
                    (length (getf (getf (sbcl-agent::service-response-data requirement-response) :project)
                                  :requirements))
                    "project requirement tool should append a requirement"))
    (let* ((detail (sbcl-agent::service-response-data
                    (sbcl-agent::query-project-detail-service session project-id)))
           (requirement-id (getf (first (getf detail :requirements)) :id))
           (decision-response
             (sbcl-agent::command-invoke-tool-service
              session
              :project/append-architecture-decision
              (list :project-id project-id
                    :title "Adopt governed project tools"
                    :summary "Project authoring flows through governed tools."
                    :status "accepted"
                    :linked-requirement-ids (list requirement-id)))))
      (assert-equal 1
                    (length (getf (getf (sbcl-agent::service-response-data decision-response) :project)
                                  :architecture-decisions))
                    "project architecture decision tool should append a decision")
      (assert-true (find :requirement
                         (mapcar (lambda (entry) (getf entry :target-kind))
                                 (getf (getf (getf (sbcl-agent::service-response-data decision-response) :project)
                                             :trace-neighborhood)
                                       :outbound)))
                   "project architecture decision tool should emit trace linkage to linked requirements"))))

(defun project-create-conversation-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/project-create-conversation-service-contract/"))
         (provider (make-instance 'project-create-action-provider))
         (command (sbcl-agent::normalize-form-command '(say "Create the governed project foundation through the conversation thread."))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (declare (ignore updated-session))
      (assert-equal :say kind "project create conversation tool execution should dispatch as :say")
      (let ((data result))
    (assert-equal :awaiting-approval
                  (getf (getf data :turn) :status)
                  "project create conversation tool execution should wait for approval")
    (assert-true (> (getf data :staged-action-count) 0)
                 "project create conversation tool execution should stage a governed action")
    (assert-equal 1
                  (length (sbcl-agent::agent-session-pending-actions session))
                  "project create conversation tool execution should leave one pending action")
    (assert-equal 1
                  (length (sbcl-agent::agent-session-work-items session))
                  "project create conversation tool execution should create one governed work item")
    (let ((tool-op (find "assistant-tool"
                         (sbcl-agent::agent-session-operations session)
                         :key #'sbcl-agent::operation-name
                         :test #'string=)))
      (assert-true tool-op "project create conversation tool execution should record a tool operation")
      (assert-equal :project-governance-write
                    (getf (sbcl-agent::operation-policy-decision tool-op) :policy-id)
                    "project create conversation tool execution should apply project governance policy"))
      (assert-equal :approve-policy
                    (getf (sbcl-agent::command-approve-policy-service session :project-governance-write) :operation)
                    "project create conversation tool execution should expose policy approval"))
    (multiple-value-bind (resume-result resume-kind resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (declare (ignore resume-result resumed-session))
      (assert-equal :turn-resume resume-kind
                    "project create conversation tool execution should resume through turn/resume"))
    (assert-equal 0
                  (length (sbcl-agent::agent-session-pending-actions session))
                  "project create conversation tool execution should clear pending actions after resume")
    (assert-equal 1
                  (length (sbcl-agent::list-project-records session))
                  "project create conversation tool execution should persist one project")
    (let* ((project (first (sbcl-agent::list-project-records session)))
           (project-id (sbcl-agent::project-record-id project))
           (detail (sbcl-agent::service-response-data
                    (sbcl-agent::query-project-detail-service session project-id))))
      (assert-equal "Agent Governed Project"
                    (getf detail :title)
                    "project create conversation tool execution should persist the created project title")
      (assert-equal "Deliver an end-to-end governed SDLC loop."
                    (getf (getf detail :constitution) :purpose)
                    "project create conversation tool execution should persist the constitution")
      (assert-equal 2
                    (length (or (getf detail :requirements) '()))
                    "project create conversation tool execution should persist requirements")
      (assert-equal 1
                    (length (or (getf detail :feature-specifications) '()))
                    "project create conversation tool execution should persist feature specifications")
      (assert-equal 1
                    (length (or (getf detail :user-journeys) '()))
                    "project create conversation tool execution should persist user journeys")
      (assert-equal 1
                    (length (or (getf detail :architecture-decisions) '()))
                    "project create conversation tool execution should persist architecture decisions")
      (assert-equal 1
                    (length (or (getf detail :source-roots) '()))
                    "project create conversation tool execution should persist source roots")
      (assert-true (find :requirement
                         (mapcar (lambda (entry) (getf entry :target-kind))
                                 (getf (getf detail :trace-neighborhood) :outbound)))
                   "project create conversation tool execution should emit project trace links")
      (assert-equal :committed
                    (sbcl-agent::work-item-status
                     (first (sbcl-agent::agent-session-work-items session)))
                    "project create conversation tool execution should commit the governed work item after resume")))))

(defun project-augment-conversation-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/project-augment-conversation-service-contract/"))
         (project (sbcl-agent::create-project-record
                   session
                   :title "Thread Augmentation Project"
                   :summary "Selected project for governed thread authoring."
                   :requirements
                   (list (sbcl-agent::make-project-requirement
                          :id "req-thread-authoring"
                          :title "Support thread-driven governance"
                          :summary "Conversations should append governed artifacts."
                          :kind :functional
                          :priority :high
                          :status :proposed
                          :verification-kind :acceptance-test))))
         (_selected (sbcl-agent::select-project-record session (sbcl-agent::project-record-id project)))
         (provider (make-instance 'project-augment-action-provider
                                  :requirement-id "req-thread-authoring"))
         (command (sbcl-agent::normalize-form-command '(say "Expand the selected project with governed specifications, journeys, testing, and quality gates."))))
    (declare (ignore _selected))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (declare (ignore updated-session))
      (assert-equal :say kind "project augment conversation tool execution should dispatch as :say")
      (let ((data result))
    (assert-equal :awaiting-approval
                  (getf (getf data :turn) :status)
                  "project augment conversation tool execution should wait for approval")
    (assert-true (> (getf data :staged-action-count) 1)
                 "project augment conversation tool execution should stage multiple governed actions")
    (assert-equal 8
                  (length (sbcl-agent::agent-session-pending-actions session))
                  "project augment conversation tool execution should stage every project authoring action")
      (assert-equal :approve-policy
                    (getf (sbcl-agent::command-approve-policy-service session :project-governance-write) :operation)
                    "project augment conversation tool execution should expose policy approval"))
    (multiple-value-bind (resume-result resume-kind resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (declare (ignore resume-result resumed-session))
      (assert-equal :turn-resume resume-kind
                    "project augment conversation tool execution should resume through turn/resume"))
    (assert-equal 0
                  (length (sbcl-agent::agent-session-pending-actions session))
                  "project augment conversation tool execution should clear pending actions after resume")
    (let* ((detail (sbcl-agent::service-response-data
                    (sbcl-agent::query-project-detail-service
                     session
                     (sbcl-agent::project-record-id project))))
           (trace-target-kinds (mapcar (lambda (entry) (getf entry :target-kind))
                                       (getf (getf detail :trace-neighborhood) :outbound))))
      (assert-equal "high"
                    (getf (getf detail :design-system) :density)
                    "project augment conversation tool execution should persist design-system updates")
      (assert-equal "precise"
                    (getf (getf detail :style-guide) :tone)
                    "project augment conversation tool execution should persist style-guide updates")
      (assert-equal 1
                    (length (or (getf detail :feature-specifications) '()))
                    "project augment conversation tool execution should append a feature specification")
      (assert-equal 1
                    (length (or (getf detail :user-journeys) '()))
                    "project augment conversation tool execution should append a user journey")
      (assert-equal 1
                    (length (or (getf detail :architecture-decisions) '()))
                    "project augment conversation tool execution should append an architecture decision")
      (assert-equal 1
                    (length (or (getf detail :source-roots) '()))
                    "project augment conversation tool execution should append a source root")
      (assert-true (member :full-suite (or (getf detail :linked-testing-harness-ids) '()) :test #'eq)
                   "project augment conversation tool execution should bind the required testing harness")
      (assert-equal 1
                    (length (or (getf detail :quality-gates) '()))
                    "project augment conversation tool execution should append a quality gate")
      (assert-true (find :testing-harness trace-target-kinds)
                   "project augment conversation tool execution should emit testing harness trace evidence")
      (assert-true (find :source-root trace-target-kinds)
                   "project augment conversation tool execution should emit source root trace evidence")))))

(defun conversation-execution-end-to-end-scenario-service-contract-test ()
  (labels ((assert-clean-turn-state (session response prompt expected-mode message)
             (let ((data (sbcl-agent::service-response-data response)))
               (assert-service-metadata-shape response message)
               (assert-equal expected-mode
                             (sbcl-agent::interaction-decision-mode
                              (sbcl-agent::classify-interaction-decision
                               prompt))
                             (format nil "~A should preserve the expected interaction mode" message))
               (assert-equal :completed
                             (getf (getf data :turn) :status)
                             (format nil "~A should complete without governed blocking" message))
               (assert-equal 0
                             (length (sbcl-agent::agent-session-pending-actions session))
                             (format nil "~A should not leave pending governed actions" message))
               (assert-equal 0
                             (length (sbcl-agent::agent-session-work-items session))
                             (format nil "~A should not create governed work-items" message)))))
    (let* ((conversation-session (make-test-session :cwd (current-workspace-root)))
           (conversation-provider (make-test-provider))
           (conversation-response
             (sbcl-agent::command-conversation-execution-service
              conversation-session
              conversation-provider
              "Explain the current engineering environment and what it is waiting on."
              '()
              :source :say
              :operator-mode :conversation)))
      (assert-clean-turn-state conversation-session
                               conversation-response
                               "Explain the current engineering environment and what it is waiting on."
                               :conversation
                               "conversation-only scenario")
      (let* ((turn-id (getf (getf (sbcl-agent::service-response-data conversation-response) :turn) :id))
             (detail (sbcl-agent::turn-detail conversation-session turn-id)))
        (assert-equal 2
                      (length (getf detail :messages))
                      "conversation-only scenario should retain a simple user/assistant turn history")))
    (let* ((prepare-session (make-test-session :cwd (current-workspace-root)))
           (prepare-provider (make-test-provider))
           (prepare-response
             (sbcl-agent::command-conversation-execution-service
              prepare-session
              prepare-provider
              "What would you change to fix this issue before implementing anything?"
              '()
              :source :say
              :operator-mode :conversation)))
      (assert-clean-turn-state prepare-session
                               prepare-response
                               "What would you change to fix this issue before implementing anything?"
                               :prepare
                               "prepare-before-confirmation scenario")
      (let* ((confirm-provider (make-instance 'mutating-eval-provider))
             (confirm-response
               (sbcl-agent::command-conversation-execution-service
                prepare-session
                confirm-provider
                "Implement the fix now and continue the governed work."
                '()
                :source :say
                :operator-mode :conversation))
             (confirm-data (sbcl-agent::service-response-data confirm-response)))
        (assert-service-metadata-shape confirm-response "prepare-then-confirm mutation scenario")
        (assert-equal :awaiting-approval
                      (getf (getf confirm-data :turn) :status)
                      "explicit confirmation should transition the prepared conversation into governed approval")
        (assert-equal 1
                      (getf confirm-data :staged-action-count)
                      "explicit confirmation should stage one governed action")
        (assert-equal 1
                      (length (sbcl-agent::agent-session-pending-actions prepare-session))
                      "explicit confirmation should leave one pending governed action")
        (assert-equal 1
                      (length (sbcl-agent::agent-session-work-items prepare-session))
                      "explicit confirmation should create one governed work-item")))
    (let* ((mutation-session (make-test-session :cwd (current-workspace-root)))
           (mutation-provider (make-instance 'followup-patch-provider))
           (mutation-response
             (sbcl-agent::command-conversation-execution-service
              mutation-session
              mutation-provider
              "Prepare patch and continue."
              '()
              :source :say
              :operator-mode :conversation))
           (mutation-data (sbcl-agent::service-response-data mutation-response)))
      (assert-service-metadata-shape mutation-response "governed mutation scenario")
      (assert-equal :awaiting-approval
                    (getf (getf mutation-data :turn) :status)
                    "governed mutation scenario should block on approval before mutation")
      (assert-equal 1
                    (length (sbcl-agent::agent-session-pending-actions mutation-session))
                    "governed mutation scenario should stage one pending action")
      (assert-equal 1
                    (length (sbcl-agent::agent-session-work-items mutation-session))
                    "governed mutation scenario should create one governed work item")
      (assert-equal :approve-policy
                    (getf (sbcl-agent::command-approve-policy-service mutation-session :workspace-write) :operation)
                    "governed mutation scenario should expose approval through the command service")
      (multiple-value-bind (resume-result resume-kind resumed-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(turn/resume))
           mutation-provider
           mutation-session)
        (declare (ignore resumed-session))
        (assert-equal :turn-resume resume-kind
                      "governed mutation scenario should resume through the real turn/resume path")
        (assert-true (getf (getf resume-result :followup) :followup-p)
                     "governed mutation scenario should produce a provider follow-up after approval")
        (assert-equal 0
                      (length (sbcl-agent::agent-session-pending-actions mutation-session))
                      "governed mutation scenario should clear staged actions after resume")
        (assert-true (search "Patch applied successfully"
                             (sbcl-agent::assistant-response-message
                              (getf (getf resume-result :followup) :response)))
                     "governed mutation scenario should record the successful follow-up summary"))
      (let* ((turn (sbcl-agent::most-recent-thread-turn mutation-session))
             (detail (sbcl-agent::turn-detail mutation-session (sbcl-agent::turn-id turn))))
        (assert-equal :completed
                      (getf detail :status)
                      "governed mutation scenario should finish the resumed turn")
        (assert-equal :completed
                      (getf (getf detail :metadata) :followup-state)
                      "governed mutation scenario should persist completed follow-up metadata")
        (assert-equal 3
                      (length (getf detail :operations))
                      "governed mutation scenario should preserve initial provider, governed action, and follow-up operations")))))

(defun mutation-review-and-rgp-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/mutation-review-rgp-service-contract/")))
    (sbcl-agent::ensure-environment)
    (assert-signals-error
     (lambda ()
       (sbcl-agent::query-mutation-review-service session))
     "No turns recorded for the current thread"
     "mutation review service should preserve the no-turns error contract")
    (let* ((thread (sbcl-agent::current-thread session))
           (user-message (sbcl-agent::create-message session thread :user "review"))
           (turn (sbcl-agent::start-turn session thread user-message))
           (assistant-message (sbcl-agent::create-message session thread :assistant "done" :turn-id (sbcl-agent::turn-id turn))))
      (sbcl-agent::complete-turn session thread turn assistant-message)
      (let ((review-response (sbcl-agent::query-mutation-review-service session)))
        (assert-equal :mutation
                      (getf review-response :domain)
                      "mutation review service should report mutation domain")
        (assert-equal :review
                      (getf review-response :operation)
                      "mutation review service should identify review operation")
        (assert-service-metadata-shape review-response "mutation review service")
        (assert-true (member :primary-execution-handle
                             (getf (sbcl-agent::service-response-data review-response) :turn))
                     "mutation review turn payload should advertise the primary execution-handle field")
        (assert-equal "conversation"
                      (getf (getf (getf (sbcl-agent::service-response-data review-response) :turn)
                                  :execution-surface)
                            :surface-kind)
                      "mutation review turn payload should expose the compact turn execution surface")
        (assert-true (listp (getf (getf (sbcl-agent::service-response-data review-response) :turn)
                                  :execution-handles))
                     "mutation review turn payload should include execution-handle listings")
        (assert-equal nil
                      (getf (getf (sbcl-agent::service-response-data review-response) :governance)
                            :work-item-surface)
                      "mutation review should not invent governed work surfaces when no work-item exists")))
    (let ((bind-response (sbcl-agent::command-rgp-bind-service session
                                                               :request-id "req-1"
                                                               :agent-session-id "sess-1"
                                                               :rgp-agent-id "agent-1"
                                                               :operator-id "operator-1"
                                                               :employment-model :contractor
                                                               :trust-profile :elevated
                                                               :visibility-profile :bounded
                                                               :billing-profile :contractor-metered
                                                               :accepted-policy-profiles '(:high-assurance
                                                                                           :artifact-validation))))
      (assert-equal :rgp
                    (getf bind-response :domain)
                    "rgp bind service should report rgp domain")
      (assert-equal :bind
                    (getf bind-response :operation)
                    "rgp bind service should identify bind operation")
      (assert-service-metadata-shape bind-response "rgp bind service")
      (assert-equal "req-1"
                    (getf (getf (sbcl-agent::service-response-data bind-response) :binding) :request-id)
                    "rgp bind service should return the bound request id")
      (assert-equal "agent-1"
                    (getf (getf (sbcl-agent::service-response-data bind-response) :node-profile) :rgp-agent-id)
                    "rgp bind service should include the configured node profile"))
    (let* ((node-response (sbcl-agent::query-rgp-node-service session))
           (node-state (sbcl-agent::service-response-data node-response))
           (node-profile (getf node-state :node-profile))
           (workspace-summary (getf node-state :workspace-summary)))
      (assert-equal :node
                    (getf node-response :operation)
                    "rgp node service should identify the node operation")
      (assert-service-metadata-shape node-response "rgp node service")
      (assert-equal "contractor"
                    (getf node-profile :employment-model)
                    "rgp node service should preserve the employment model")
      (assert-equal "artifact-validation"
                    (second (getf node-profile :accepted-policy-profiles))
                    "rgp node service should preserve accepted policy profiles")
      (assert-equal "idle"
                    (getf (getf node-state :publication-posture) :readiness)
                    "rgp node service should expose publication posture")
      (assert-equal "contractor"
                    (getf (getf workspace-summary :node-mode) :employment-model)
                    "rgp node service should expose workspace node mode")
      (assert-equal "idle"
                    (getf (getf (getf node-state :publication-posture) :operator-attention)
                          :class)
                    "rgp node service should expose initial operator attention posture")
      (assert-equal "none"
                    (getf (getf node-state :business-posture) :current-gate)
                    "rgp node service should expose initial business posture")
      (assert-equal "sbcl_agent"
                    (getf (getf node-state :governed-runtime) :runtime-subtype)
                    "rgp node service should expose governed runtime summary"))
    (let* ((receive-response (sbcl-agent::command-rgp-receive-assignment-service
                             session
                             :assignment-id "asg-inbound-contractor"
                              :goal "Inbound contractor assignment"
                              :rgp-work-id "work-inbound-contractor"
                              :operator-model :contractor
                              :compensation-profile :metered
                              :evidence-profile :high-assurance
                              :visibility-profile :bounded
                             :billing-state :pending))
           (receive-data (sbcl-agent::service-response-data receive-response)))
      (assert-equal :receive-assignment
                    (getf receive-response :operation)
                    "rgp receive command should identify inbound assignment handling")
      (assert-service-metadata-shape receive-response "rgp receive command")
      (assert-equal "asg-inbound-contractor"
                    (getf (getf receive-data :assignment) :assignment-id)
                    "rgp receive command should persist the inbound assignment")
      (assert-equal "decision-required"
                    (getf (getf receive-data :acceptance-posture) :readiness)
                    "contractor inbound assignment should remain explicit by default")
      (assert-equal "assignment-decision"
                    (getf (getf receive-data :materialization) :projection-kind)
                    "contractor inbound assignment should materialize into a local decision workflow")
      (assert-equal :assignment-decision
                    (getf (getf (getf receive-data :materialization) :next-action) :type)
                    "contractor inbound assignment should point the local work-item at assignment review")
      (assert-true (stringp (getf (getf receive-data :work-item) :id))
                   "rgp receive command should materialize a local work-item"))
    (let* ((seeded-work-item (sbcl-agent::create-work-item session "Seeded RGP assignment work item"
                                                           :transaction-scope :rgp-assignment))
           (record-response (sbcl-agent::command-rgp-record-assignment-service session
                                                                               :assignment-id "asg-1"
                                                                               :rgp-work-id "work-1"
                                                                               :operator-model :contractor
                                                                               :compensation-profile :metered
                                                                               :evidence-profile :high-assurance
                                                                               :acceptance-state :pending
                                                                               :billing-state :pending
                                                                               :visibility-profile :bounded
                                                                               :linked-local-work-item-ids
                                                                               (list (sbcl-agent::work-item-id seeded-work-item))
                                                                               :linked-thread-id "thread-1"
                                                                               :linked-incident-ids '("incident-1")))
           (assignment (getf (sbcl-agent::service-response-data record-response) :assignment)))
      (assert-equal :record-assignment
                    (getf record-response :operation)
                    "rgp assignment command should identify assignment recording")
      (assert-service-metadata-shape record-response "rgp assignment command")
      (assert-equal "asg-1"
                    (getf assignment :assignment-id)
                    "rgp assignment command should preserve assignment id")
      (assert-equal "pending"
                    (getf assignment :acceptance-state)
                    "rgp assignment command should preserve acceptance state"))
    (sbcl-agent::command-rgp-record-assignment-service session
                                                       :assignment-id "asg-clarify"
                                                       :rgp-work-id "work-clarify"
                                                       :operator-model :contractor
                                                       :compensation-profile :metered
                                                       :evidence-profile :high-assurance
                                                       :acceptance-state :pending
                                                       :billing-state :pending
                                                       :visibility-profile :bounded
                                                       :linked-local-work-item-ids
                                                       (list (sbcl-agent::work-item-id
                                                              (sbcl-agent::create-work-item session
                                                                                           "Clarification RGP assignment work item"
                                                                                           :transaction-scope :rgp-assignment)))
                                                       :linked-thread-id "thread-1")
    (let* ((clarification-response
            (sbcl-agent::command-rgp-request-assignment-clarification-service
             session
             "asg-clarify"
             :note "Need scope clarification"))
           (clarified-assignment (getf (sbcl-agent::service-response-data clarification-response)
                                       :assignment))
           (clarification-lifecycle (getf (sbcl-agent::service-response-data clarification-response)
                                          :lifecycle))
           (clarification-publication (getf (sbcl-agent::service-response-data clarification-response)
                                            :publication)))
      (assert-equal :request-assignment-clarification
                    (getf clarification-response :operation)
                    "rgp clarification command should identify assignment clarification")
      (assert-service-metadata-shape clarification-response "rgp clarification command")
      (assert-equal "no-op"
                    (first (getf (getf (sbcl-agent::service-response-data clarification-response)
                                       :decision-terms)
                                 :allowed-actions))
                    "clarification command should return updated decision terms")
      (assert-equal "clarification-requested"
                    (getf clarified-assignment :acceptance-state)
                    "rgp clarification command should update the acceptance state")
      (assert-equal "waiting-for-clarification"
                    (getf clarification-lifecycle :lifecycle-stage)
                    "rgp clarification command should project a waiting clarification lifecycle")
      (assert-equal "assignment.clarification_requested"
                    (getf clarification-publication :topic)
                    "rgp clarification command should enqueue the clarification publication"))
    (let* ((accept-response (sbcl-agent::command-rgp-accept-assignment-service session
                                                                               "asg-1"
                                                                               :note "Terms accepted"))
           (accepted-assignment (getf (sbcl-agent::service-response-data accept-response) :assignment))
           (accepted-lifecycle (getf (sbcl-agent::service-response-data accept-response) :lifecycle))
           (accepted-publication (getf (sbcl-agent::service-response-data accept-response) :publication)))
      (assert-equal :accept-assignment
                    (getf accept-response :operation)
                    "rgp accept command should identify assignment acceptance")
      (assert-service-metadata-shape accept-response "rgp accept command")
      (assert-equal "no-op"
                    (first (getf (getf (sbcl-agent::service-response-data accept-response)
                                       :decision-terms)
                                 :allowed-actions))
                    "accept command should return updated decision terms")
      (assert-equal "accepted"
                    (getf accepted-assignment :acceptance-state)
                    "rgp accept command should update the acceptance state")
      (assert-equal "ready-for-local-execution"
                    (getf accepted-lifecycle :lifecycle-stage)
                    "rgp accept command should project a ready execution lifecycle when contractor policy is satisfied")
      (assert-equal "assignment.accepted"
                    (getf accepted-publication :topic)
                    "rgp accept command should enqueue the acceptance publication"))
    (let* ((assignments-response (sbcl-agent::query-rgp-assignments-service session))
           (assignments (sbcl-agent::service-response-data assignments-response)))
      (assert-equal :assignments
                    (getf assignments-response :operation)
                    "rgp assignments service should identify local assignments")
      (assert-service-metadata-shape assignments-response "rgp assignments service")
      (assert-equal "asg-1"
                    (getf (first assignments) :assignment-id)
                    "rgp assignments service should expose persisted local assignment state")
      (assert-equal "accepted"
                    (getf (getf (first assignments) :acceptance-posture) :readiness)
                    "rgp assignments service should expose acceptance posture")
      (assert-equal "no-op"
                    (first (getf (getf (first assignments) :decision-terms) :allowed-actions))
                    "rgp assignments service should expose resolved decision terms for accepted assignments")
      (assert-equal "ready-for-local-execution"
                    (getf (getf (first assignments) :lifecycle) :lifecycle-stage)
                    "rgp assignments service should expose assignment lifecycle")
      (assert-equal "high-assurance"
                    (getf (getf (first assignments) :evidence-summary) :evidence-profile)
                    "rgp assignments service should expose evidence summary")
      (assert-equal "accept"
                    (first (getf (getf (find "asg-inbound-contractor"
                                             assignments
                                             :key (lambda (entry) (getf entry :assignment-id))
                                             :test #'string=)
                                       :decision-terms)
                                 :allowed-actions))
                    "rgp assignments service should expose pending contractor decision terms"))
    (let* ((employee-config (sbcl-agent::command-rgp-configure-node-service
                             session
                             :employment-model :employee
                             :accepted-policy-profiles '(:standard-evidence)))
           (employee-receive (sbcl-agent::command-rgp-receive-assignment-service
                              session
                              :assignment-id "asg-inbound-employee"
                              :goal "Inbound employee assignment"
                              :rgp-work-id "work-inbound-employee"
                              :operator-model :employee
                              :compensation-profile :organization-funded
                              :evidence-profile :standard
                              :visibility-profile :standard
                              :billing-state :covered))
           (employee-data (sbcl-agent::service-response-data employee-receive)))
      (declare (ignore employee-config))
      (assert-equal "accepted"
                    (getf (getf employee-data :assignment) :acceptance-state)
                    "employee inbound assignment should auto-accept when policy posture permits it")
      (assert-equal "accepted"
                    (getf (getf employee-data :acceptance-posture) :readiness)
                    "employee inbound assignment should report accepted readiness")
      (assert-equal "no-op"
                    (first (getf (getf employee-data :decision-terms) :allowed-actions))
                    "employee inbound assignment should expose resolved decision terms after auto-accept")
      (assert-equal "execution-ready"
                    (getf (getf employee-data :materialization) :projection-kind)
                    "employee inbound assignment should materialize into an execution-ready workflow")
      (assert-equal :execute-assignment
                    (getf (getf (getf employee-data :materialization) :next-action) :type)
                    "employee inbound assignment should point the local work-item toward execution")
      (assert-true (getf employee-data :auto-accepted-publication)
                   "employee inbound assignment should emit an auto-accept publication"))
    (let* ((minimal-receive (sbcl-agent::command-rgp-receive-assignment-service
                             session
                             :assignment-id "asg-inbound-minimal"
                             :goal "Inbound minimal evidence assignment"
                             :rgp-work-id "work-inbound-minimal"
                             :operator-model :employee
                             :compensation-profile :organization-funded
                             :evidence-profile :minimal
                             :visibility-profile :standard
                             :billing-state :covered))
           (minimal-data (sbcl-agent::service-response-data minimal-receive)))
      (assert-equal "accepted"
                    (getf (getf minimal-data :assignment) :acceptance-state)
                    "minimal inbound assignment should auto-accept under employee policy posture")
      (assert-equal "minimal"
                    (getf (getf minimal-data :evidence-summary) :evidence-profile)
                    "minimal inbound assignment should preserve minimal evidence posture"))
    (let* ((node-response (sbcl-agent::query-rgp-node-service session))
           (node-state (sbcl-agent::service-response-data node-response))
           (workspace-summary (getf node-state :workspace-summary)))
      (assert-equal "request-clarification"
                    (first (getf (getf (find "asg-inbound-contractor"
                                             (getf node-state :local-assignments)
                                             :key (lambda (entry) (getf entry :assignment-id))
                                             :test #'string=)
                                       :decision-terms)
                                 :allowed-actions))
                    "rgp node service should expose post-policy decision terms once assignments are materialized")
      (assert-equal "none"
                    (getf (getf node-state :business-posture) :current-gate)
                    "rgp node service should preserve business posture before billing milestones exist")
      (assert-equal 5
                    (getf (getf workspace-summary :assignment-terms) :assignment-count)
                    "rgp node service should expose workspace assignment-term counts")
      (assert-equal 3
                    (getf (getf workspace-summary :assignment-terms) :policy-blocked-count)
                    "rgp node service should expose workspace policy-blocked counts")
      (assert-equal "assignment-policy"
                    (getf (getf (getf workspace-summary :attention-queue) :top-item) :kind)
                    "rgp node service should expose an ordered workspace attention queue")
      (assert-equal "publishing"
                    (getf (getf (getf node-state :publication-posture) :operator-attention)
                          :class)
                    "rgp node service should preserve publishing operator attention before outbound business backlog exists"))
    (let* ((event-response (sbcl-agent::query-service-event-stream
                            :environment (sbcl-agent::ensure-environment)
                            :limit 50
                            :family :governance))
           (events (getf (sbcl-agent::service-response-data event-response) :events)))
      (assert-true (find :rgp-assignment-materialized
                         events
                         :key (lambda (entry) (getf entry :kind)))
                   "inbound assignments should project a local materialization event")
      (assert-true (find :rgp-assignment-awaiting-decision
                         events
                         :key (lambda (entry) (getf entry :kind)))
                   "explicit inbound assignments should emit a local awaiting-decision event")
      (assert-true (find :rgp-assignment-ready-to-execute
                         events
                         :key (lambda (entry) (getf entry :kind)))
                   "implicit inbound assignments should emit a local ready-to-execute event")
      (assert-true (find :rgp-assignment-clarification-requested-locally
                         events
                         :key (lambda (entry) (getf entry :kind)))
                   "clarification decisions should emit a local clarification lifecycle event")
      (assert-true (find :rgp-assignment-accepted-locally
                         events
                         :key (lambda (entry) (getf entry :kind)))
                   "accept decisions should emit a local acceptance lifecycle event"))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::command-rgp-accept-assignment-service session "asg-inbound-contractor"))
     "does not allow accept"
     "policy-blocked inbound contractor assignments should reject illegal accept commands")
    (let* ((evidence-response (sbcl-agent::query-rgp-evidence-service session "asg-1"))
           (evidence (sbcl-agent::service-response-data evidence-response)))
      (assert-equal :evidence
                    (getf evidence-response :operation)
                    "rgp evidence service should identify assignment evidence projection")
      (assert-service-metadata-shape evidence-response "rgp evidence service")
      (assert-equal "high-assurance"
                    (getf evidence :evidence-profile)
                    "rgp evidence service should preserve the assignment evidence profile")
      (assert-equal "needs-more-evidence"
                    (getf evidence :readiness)
                    "rgp evidence service should project current evidence readiness"))
    (let* ((usage-command (sbcl-agent::command-rgp-record-usage-service session
                                                                        :provider "openai"
                                                                        :model "gpt-5.4"
                                                                        :input-tokens 120
                                                                        :output-tokens 45
                                                                        :cached-tokens 12
                                                                        :execution-seconds 8
                                                                        :blocked-seconds 2
                                                                        :tool-invocations 3
                                                                        :artifact-count 1
                                                                        :validation-effort 4))
           (usage-response (sbcl-agent::query-rgp-usage-service session))
           (usage (sbcl-agent::service-response-data usage-response)))
      (assert-equal :record-usage
                    (getf usage-command :operation)
                    "rgp usage command should identify usage recording")
      (assert-service-metadata-shape usage-command "rgp usage command")
      (assert-equal :usage
                    (getf usage-response :operation)
                    "rgp usage service should identify usage telemetry")
      (assert-service-metadata-shape usage-response "rgp usage service")
      (assert-equal 120
                    (getf usage :total-input-tokens)
                    "rgp usage service should preserve token totals")
      (assert-equal "openai"
                    (getf (getf usage :last-report) :provider)
                    "rgp usage service should preserve the last usage report"))
    (let* ((fact-command (sbcl-agent::command-rgp-record-execution-fact-service
                          session
                          :assignment-id "asg-1"
                          :fact-kind :execution-progress
                          :status :running
                          :note "Validation is in progress"
                          :artifact-count 2
                          :checkpoint-count 1
                          :validation-count 1))
           (fact-data (sbcl-agent::service-response-data fact-command))
           (facts-response (sbcl-agent::query-rgp-facts-service session))
           (facts (sbcl-agent::service-response-data facts-response)))
      (assert-equal :record-execution-fact
                    (getf fact-command :operation)
                    "rgp execution fact command should identify fact recording")
      (assert-service-metadata-shape fact-command "rgp execution fact command")
      (assert-equal :facts
                    (getf facts-response :operation)
                    "rgp facts service should identify execution facts")
      (assert-service-metadata-shape facts-response "rgp facts service")
      (assert-equal "execution-progress"
                    (getf (getf fact-data :fact) :fact-kind)
                    "rgp execution fact command should preserve fact kind")
      (assert-equal 4
                    (length (getf fact-data :publications))
                    "rgp execution fact command should emit execution, artifact, checkpoint, and validation publications for high-assurance evidence")
      (assert-equal "asg-1"
                    (getf (first facts) :assignment-id)
                    "rgp facts service should expose persisted execution facts"))
    (let* ((standard-fact-command (sbcl-agent::command-rgp-record-execution-fact-service
                                   session
                                   :assignment-id "asg-inbound-employee"
                                   :fact-kind :execution-progress
                                   :status :running
                                   :note "Standard validation is in progress"
                                   :artifact-count 1
                                   :checkpoint-count 1
                                   :validation-count 1))
           (standard-fact-data (sbcl-agent::service-response-data standard-fact-command)))
      (assert-equal 4
                    (length (getf standard-fact-data :publications))
                    "standard evidence execution facts should emit execution, artifact, checkpoint, and validation publications"))
    (let* ((minimal-fact-command (sbcl-agent::command-rgp-record-execution-fact-service
                                  session
                                  :assignment-id "asg-inbound-minimal"
                                  :fact-kind :execution-progress
                                  :status :running
                                  :note "Minimal status only"
                                  :artifact-count 1
                                  :checkpoint-count 1
                                  :validation-count 1))
           (minimal-fact-data (sbcl-agent::service-response-data minimal-fact-command)))
      (assert-equal 1
                    (length (getf minimal-fact-data :publications))
                    "minimal evidence execution facts should emit only the primary execution publication"))
    (let* ((billing-command (sbcl-agent::command-rgp-record-billing-milestone-service
                             session
                             :assignment-id "asg-1"
                             :milestone-kind :deliverable-submitted
                             :status :reached
                             :note "Submission is ready for review"))
           (billing-data (sbcl-agent::service-response-data billing-command))
           (billing-response (sbcl-agent::query-rgp-billing-service session))
           (billing (sbcl-agent::service-response-data billing-response)))
      (assert-equal :record-billing-milestone
                    (getf billing-command :operation)
                    "rgp billing milestone command should identify milestone recording")
      (assert-service-metadata-shape billing-command "rgp billing milestone command")
      (assert-equal :billing
                    (getf billing-response :operation)
                    "rgp billing service should identify billing milestones")
      (assert-service-metadata-shape billing-response "rgp billing service")
      (assert-equal "deliverable-submitted"
                    (getf (getf billing-data :milestone) :milestone-kind)
                    "rgp billing milestone command should preserve the milestone kind")
      (assert-equal 2
                    (length (getf billing-data :publications))
                    "deliverable submission milestones should emit billing and deliverable publications")
      (assert-equal "asg-1"
                    (getf (first billing) :assignment-id)
                    "rgp billing service should expose persisted billing milestones"))
    (let* ((acceptance-requested-command (sbcl-agent::command-rgp-record-billing-milestone-service
                                          session
                                          :assignment-id "asg-1"
                                          :milestone-kind :acceptance-requested
                                          :status :reached
                                          :note "Waiting for customer acceptance"))
           (acceptance-requested-data (sbcl-agent::service-response-data acceptance-requested-command))
           (payment-authorized-command (sbcl-agent::command-rgp-record-billing-milestone-service
                                        session
                                        :assignment-id "asg-1"
                                        :milestone-kind :payment-authorized
                                        :status :reached
                                        :note "Payment was authorized"))
           (payment-authorized-data (sbcl-agent::service-response-data payment-authorized-command)))
      (assert-equal 2
                    (length (getf acceptance-requested-data :publications))
                    "acceptance-requested milestones should emit billing and acceptance publications")
      (assert-equal 2
                    (length (getf payment-authorized-data :publications))
                    "payment-authorized milestones should emit billing and payment publications"))
    (let* ((publications-response (sbcl-agent::query-rgp-publications-service session))
           (publications-payload (sbcl-agent::service-response-data publications-response))
           (publications (getf publications-payload :entries))
           (accept-publication (find "assignment.accepted" publications
                                     :key (lambda (entry) (getf entry :topic))
                                     :test #'string=))
           (usage-publication (find "usage.reported" publications
                                    :key (lambda (entry) (getf entry :topic))
                                    :test #'string=))
           (execution-publication (find "execution.fact_reported" publications
                                        :key (lambda (entry) (getf entry :topic))
                                        :test #'string=))
           (artifact-publication (find "artifact.reported" publications
                                       :key (lambda (entry) (getf entry :topic))
                                       :test #'string=))
           (checkpoint-publication (find "checkpoint.reported" publications
                                         :key (lambda (entry) (getf entry :topic))
                                         :test #'string=))
           (validation-publication (find "validation.reported" publications
                                         :key (lambda (entry) (getf entry :topic))
                                         :test #'string=))
           (billing-publication (find "billing.milestone_reached" publications
                                      :key (lambda (entry) (getf entry :topic))
                                      :test #'string=))
           (deliverable-publication (find "deliverable.submitted" publications
                                          :key (lambda (entry) (getf entry :topic))
                                          :test #'string=))
           (acceptance-requested-publication (find "acceptance.requested" publications
                                                  :key (lambda (entry) (getf entry :topic))
                                                  :test #'string=))
           (payment-authorized-publication (find "payment.authorized" publications
                                                 :key (lambda (entry) (getf entry :topic))
                                                 :test #'string=))
           (standard-execution-publication
             (find-if (lambda (entry)
                        (and (string= (getf entry :topic) "execution.fact_reported")
                             (string= (getf entry :assignment-id) "asg-inbound-employee")))
                      publications))
           (minimal-execution-publication
             (find-if (lambda (entry)
                        (and (string= (getf entry :topic) "execution.fact_reported")
                             (string= (getf entry :assignment-id) "asg-inbound-minimal")))
                      publications))
           (failed-response (sbcl-agent::command-rgp-mark-publication-service
                             session
                             (getf accept-publication :id)
                             :state :failed
                             :failure-reason "network-timeout"))
           (failed-publication (sbcl-agent::service-response-data failed-response))
           (retry-response (sbcl-agent::command-rgp-retry-publication-service
                            session
                            (getf accept-publication :id)
                            :next-attempt-at 3985764000))
           (retried-publication (sbcl-agent::service-response-data retry-response))
           (mark-response (sbcl-agent::command-rgp-mark-publication-service
                           session
                           (getf accept-publication :id)
                           :state :published))
           (updated-publication (sbcl-agent::service-response-data mark-response))
           (post-update-publications (sbcl-agent::service-response-data
                                      (sbcl-agent::query-rgp-publications-service session))))
      (assert-equal :publications
                    (getf publications-response :operation)
                    "rgp publications service should identify the publication backlog")
      (assert-service-metadata-shape publications-response "rgp publications service")
      (assert-equal "publishing"
                    (getf (getf publications-payload :posture) :readiness)
                    "rgp publications service should expose publication posture")
      (assert-equal 9
                    (getf (getf publications-payload :posture) :execution-count)
                    "rgp publication posture should summarize execution-family backlog pressure")
      (assert-equal 1
                    (getf (getf publications-payload :posture) :usage-count)
                    "rgp publication posture should summarize usage backlog pressure")
      (assert-equal 6
                    (getf (getf publications-payload :posture) :billing-count)
                    "rgp publication posture should summarize billing-family backlog pressure")
      (assert-equal 2
                    (getf (getf publications-payload :posture) :payment-gated-count)
                    "rgp publication posture should summarize payment-gated backlog pressure")
      (assert-equal 4
                    (getf (getf publications-payload :posture) :assignment-count)
                    "rgp publication posture should summarize assignment decision backlog pressure")
      (assert-equal "payment-gated"
                    (getf (getf (getf publications-payload :posture) :operator-attention) :class)
                    "rgp publication posture should expose explicit operator attention class")
      (assert-equal t
                    (getf (getf (getf publications-payload :posture) :operator-attention)
                          :payment-gated-p)
                    "rgp publication posture should expose payment-gated operator attention")
      (assert-true usage-publication
                   "rgp publications service should include usage-report publications")
      (assert-true execution-publication
                   "rgp publications service should include execution fact publications")
      (assert-true artifact-publication
                   "rgp publications service should include artifact publications")
      (assert-true checkpoint-publication
                   "rgp publications service should include checkpoint publications")
      (assert-true validation-publication
                   "rgp publications service should include validation publications")
      (assert-true billing-publication
                   "rgp publications service should include billing milestone publications")
      (assert-true deliverable-publication
                   "rgp publications service should include deliverable submission publications")
      (assert-true acceptance-requested-publication
                   "rgp publications service should include acceptance-requested publications")
      (assert-true payment-authorized-publication
                   "rgp publications service should include payment-authorized publications")
      (assert-equal :mark-publication
                    (getf failed-response :operation)
                    "rgp publication failure command should identify publication updates")
      (assert-service-metadata-shape failed-response "rgp publication failure command")
      (assert-equal "failed"
                    (getf failed-publication :state)
                    "rgp publication failure command should mark the publication failed")
      (assert-equal "network-timeout"
                    (getf failed-publication :failure-reason)
                    "rgp publication failure command should preserve the failure reason")
      (assert-equal :retry-publication
                    (getf retry-response :operation)
                    "rgp retry command should identify retry transitions")
      (assert-service-metadata-shape retry-response "rgp retry publication command")
      (assert-equal "retrying"
                    (getf retried-publication :state)
                    "rgp retry command should mark publication retrying")
      (assert-equal 1
                    (getf retried-publication :attempt-count)
                    "rgp retry command should increment publication attempts")
      (assert-equal :mark-publication
                    (getf mark-response :operation)
                    "rgp publication command should identify publication updates")
      (assert-service-metadata-shape mark-response "rgp publication command")
      (assert-equal "published"
                    (getf updated-publication :state)
                    "rgp publication command should update publication state")
      (assert-equal 2
                    (getf updated-publication :attempt-count)
                    "rgp publication command should preserve retry history")
      (assert-equal "publishing"
                    (getf (getf post-update-publications :posture) :readiness)
                    "rgp publication posture should continue reporting active backlog when other publications remain")
      (assert-equal "payment-gated"
                    (getf (getf (getf post-update-publications :posture) :operator-attention) :class)
                    "rgp publication posture should continue reporting payment-gated attention after retry resolution")
      (assert-equal "high-assurance"
                    (getf (getf (getf accept-publication :payload) :evidence) :evidence-profile)
                    "assignment decision publications should carry evidence posture")
      (assert-equal 1
                    (getf (getf (getf execution-publication :payload) :evidence) :incident-count)
                    "high-assurance execution publications should carry richer incident evidence")
      (assert-equal 1
                    (getf (getf standard-execution-publication :payload) :validation-count)
                    "standard execution publications should carry validation evidence")
      (assert-equal nil
                    (getf (getf (getf standard-execution-publication :payload) :evidence) :incident-count)
                    "standard execution publications should not carry incident evidence")
      (assert-equal nil
                    (getf (getf (getf minimal-execution-publication :payload) :evidence) :artifact-count)
                    "minimal execution publications should omit artifact evidence")
      (assert-equal nil
                    (getf (getf (getf minimal-execution-publication :payload) :evidence) :validation-count)
                    "minimal execution publications should omit validation evidence"))
    (let ((show-response (sbcl-agent::query-rgp-show-service session)))
      (assert-equal :show
                    (getf show-response :operation)
                    "rgp show service should identify show operation")
      (assert-service-metadata-shape show-response "rgp show service")
      (assert-true (find "asg-1"
                         (getf (sbcl-agent::service-response-data show-response) :local-assignments)
                         :key (lambda (entry) (getf entry :assignment-id))
                         :test #'string=)
                   "rgp show service should project local assignments")
      (assert-equal "request-clarification"
                    (first (getf (getf (find "asg-1"
                                             (getf (sbcl-agent::service-response-data show-response)
                                                   :local-assignments)
                                             :key (lambda (entry) (getf entry :assignment-id))
                                             :test #'string=)
                                       :decision-terms)
                                 :allowed-actions))
                    "rgp show service should project assignment decision terms")
      (assert-equal "operator-1"
                    (getf (getf (sbcl-agent::service-response-data show-response) :node-profile)
                          :operator-id)
                    "rgp show service should project node profile")
      (assert-equal 120
                    (getf (getf (sbcl-agent::service-response-data show-response) :usage-telemetry)
                          :total-input-tokens)
                    "rgp show service should project usage telemetry")
      (assert-true (find "asg-1"
                         (getf (sbcl-agent::service-response-data show-response) :execution-facts)
                         :key (lambda (entry) (getf entry :assignment-id))
                         :test #'string=)
                   "rgp show service should project execution facts")
      (assert-true (find "asg-1"
                         (getf (sbcl-agent::service-response-data show-response) :billing-milestones)
                         :key (lambda (entry) (getf entry :assignment-id))
                         :test #'string=)
                   "rgp show service should project billing milestones")
      (assert-equal "payment-authorized"
                    (getf (getf (sbcl-agent::service-response-data show-response) :business-posture)
                          :current-gate)
                    "rgp show service should project business posture")
      (assert-true (find "asg-1"
                         (getf (sbcl-agent::service-response-data show-response) :assignment-evidence)
                         :key (lambda (entry) (getf entry :assignment-id))
                         :test #'string=)
                   "rgp show service should project assignment evidence")
      (assert-equal "policy-blocked"
                    (getf (find "asg-1"
                                (getf (sbcl-agent::service-response-data show-response)
                                      :assignment-acceptance)
                                :key (lambda (entry) (getf entry :assignment-id))
                                :test #'string=)
                          :readiness)
                    "rgp show service should project updated contractor assignment acceptance posture")
      (assert-equal "accepted"
                    (getf (find "asg-inbound-employee"
                                (getf (sbcl-agent::service-response-data show-response)
                                      :assignment-acceptance)
                                :key (lambda (entry) (getf entry :assignment-id))
                                :test #'string=)
                          :readiness)
                    "rgp show service should project accepted inbound employee assignment posture")
      (assert-equal "publishing"
                    (getf (getf (sbcl-agent::service-response-data show-response)
                                :publication-posture)
                          :readiness)
                    "rgp show service should project publication posture")
      (assert-equal 6
                    (getf (getf (sbcl-agent::service-response-data show-response)
                                :publication-posture)
                          :billing-count)
                    "rgp show service should project publication-family billing pressure")
      (assert-equal "payment-gated"
                    (getf (getf (getf (sbcl-agent::service-response-data show-response)
                                      :publication-posture)
                                :operator-attention)
                          :class)
                    "rgp show service should project publication operator attention")
      (assert-equal "payment-authorized"
                    (getf (getf (getf (sbcl-agent::service-response-data show-response)
                                      :governed-runtime)
                                :business-posture)
                          :current-gate)
                    "rgp show service should project business posture in governed runtime summary")
      (assert-equal "employee"
                    (getf (getf (getf (sbcl-agent::service-response-data show-response)
                                      :workspace-summary)
                                :node-mode)
                          :employment-model)
                    "rgp show service should project workspace summary node mode")
      (assert-equal "payment-gated"
                    (getf (getf (getf (getf (sbcl-agent::service-response-data show-response)
                                            :governed-runtime)
                                      :publication-posture)
                                :operator-attention)
                          :class)
                    "rgp show service should project publication attention in governed runtime summary")
      (assert-true (find "assignment.clarification_requested"
                         (getf (sbcl-agent::service-response-data show-response) :publication-backlog)
                         :key (lambda (entry) (getf entry :topic))
                         :test #'string=)
                   "rgp show service should project publication backlog state"))
    (let* ((workspace-response (sbcl-agent::query-rgp-workspace-service session))
           (workspace (sbcl-agent::service-response-data workspace-response)))
      (assert-equal :workspace-summary
                    (getf workspace-response :operation)
                    "rgp workspace service should identify the workspace-summary operation")
      (assert-service-metadata-shape workspace-response "rgp workspace service")
      (assert-equal "employee"
                    (getf (getf workspace :node-mode) :employment-model)
                    "rgp workspace service should expose node mode")
      (assert-equal 1
                    (getf (getf workspace :node-mode) :accepted-policy-profile-count)
                    "rgp workspace service should expose accepted policy profile counts")
      (assert-equal 3
                    (getf (getf workspace :assignment-terms) :policy-blocked-count)
                    "rgp workspace service should summarize assignment policy pressure")
      (assert-true (member :execution-surfaces workspace :test #'eq)
                   "rgp workspace service should expose compact execution-surface workspace data")
      (assert-true (integerp (getf (getf workspace :execution-surfaces) :count))
                   "rgp workspace service should report an execution-surface count")
      (assert-equal 5
                    (getf (getf workspace :attention-queue) :count)
                    "rgp workspace service should summarize ordered operator attention items")
      (assert-equal "assignment-policy"
                    (getf (getf (getf workspace :attention-queue) :top-item) :kind)
                    "rgp workspace service should surface the strongest next attention item")
      (assert-equal "payment-gated"
                    (getf (getf workspace :publication-summary) :attention-class)
                    "rgp workspace service should summarize publication attention")
      (assert-equal "payment-authorized"
                    (getf (getf workspace :business-summary) :current-gate)
                    "rgp workspace service should summarize business state")
      (assert-equal "openai"
                    (getf (getf workspace :usage-summary) :last-provider)
                    "rgp workspace service should summarize last usage provider")
      (assert-equal 1
                    (getf (getf workspace :evidence-posture) :minimal-count)
                    "rgp workspace service should summarize evidence profiles"))
    (let* ((path "/tmp/service-rgp-state.sexp"))
      (sbcl-agent::command-environment-save-service path)
      (let* ((loaded-environment (sbcl-agent::load-environment path))
             (loaded-snapshot (sbcl-agent::environment-rgp-snapshot loaded-environment)))
        (assert-equal "agent-1"
                      (getf (getf loaded-snapshot :node-profile) :rgp-agent-id)
                      "loading the environment should restore rgp node profile state")
        (assert-true (member :execution-surfaces
                             (getf loaded-snapshot :workspace-summary)
                             :test #'eq)
                     "loading the environment should restore compact workspace surface data")
        (assert-true (integerp (getf (getf (getf loaded-snapshot :workspace-summary)
                                           :execution-surfaces)
                                     :count))
                     "loading the environment should restore workspace surface counts")
        (assert-true (find "asg-1"
                           (getf loaded-snapshot :local-assignments)
                           :key (lambda (entry) (getf entry :assignment-id))
                           :test #'string=)
                     "loading the environment should restore local assignment state")
        (assert-equal "request-clarification"
                      (first (getf (getf (find "asg-1"
                                               (getf loaded-snapshot :local-assignments)
                                               :key (lambda (entry) (getf entry :assignment-id))
                                               :test #'string=)
                                         :decision-terms)
                                   :allowed-actions))
                      "loading the environment should restore assignment decision terms")
        (assert-equal 120
                      (getf (getf loaded-snapshot :usage-telemetry) :total-input-tokens)
                      "loading the environment should restore usage telemetry")
        (assert-true (find "asg-1"
                           (getf loaded-snapshot :execution-facts)
                           :key (lambda (entry) (getf entry :assignment-id))
                           :test #'string=)
                     "loading the environment should restore execution fact state")
        (assert-true (find "asg-1"
                           (getf loaded-snapshot :billing-milestones)
                           :key (lambda (entry) (getf entry :assignment-id))
                           :test #'string=)
                     "loading the environment should restore billing milestone state")
        (assert-equal "payment-authorized"
                      (getf (getf loaded-snapshot :business-posture) :current-gate)
                      "loading the environment should restore business posture")
        (assert-equal "payment-gated"
                      (getf (getf (getf loaded-snapshot :publication-posture) :operator-attention)
                            :class)
                      "loading the environment should restore publication attention posture")
        (assert-equal "payment-authorized"
                      (getf (getf (getf loaded-snapshot :workspace-summary) :business-summary)
                            :current-gate)
                      "loading the environment should restore workspace summary posture")
        (assert-equal "assignment-policy"
                      (getf (getf (getf (getf loaded-snapshot :workspace-summary) :attention-queue)
                                  :top-item)
                            :kind)
                      "loading the environment should restore workspace attention posture")
        (assert-true (find "asg-1"
                           (getf loaded-snapshot :assignment-evidence)
                           :key (lambda (entry) (getf entry :assignment-id))
                           :test #'string=)
                     "loading the environment should restore assignment evidence state")
        (assert-true (find "asg-1"
                           (getf loaded-snapshot :assignment-acceptance)
                           :key (lambda (entry) (getf entry :assignment-id))
                           :test #'string=)
                     "loading the environment should restore assignment acceptance posture")
        (assert-true (find "assignment.accepted"
                           (getf loaded-snapshot :publication-backlog)
                           :key (lambda (entry) (getf entry :topic))
                           :test #'string=)
                     "loading the environment should restore publication backlog state")))
    (let* ((work-item (sbcl-agent::create-work-item session "RGP approval goal"))
           (work-item-id (sbcl-agent::work-item-id work-item)))
      (sbcl-agent::command-request-work-item-approval-service session
                                                              work-item-id
                                                              :workspace-write
                                                              :reason "Need governed approval in the RGP surface")
      (let* ((approval-response (sbcl-agent::query-rgp-approvals-service session))
             (approvals (sbcl-agent::service-response-data approval-response))
             (approval (find work-item-id approvals
                             :key (lambda (entry) (getf entry :id))
                             :test #'string=)))
        (assert-equal :approvals
                      (getf approval-response :operation)
                      "rgp approvals service should identify the approvals operation")
        (assert-service-metadata-shape approval-response "rgp approvals service")
        (assert-true approval
                     "rgp approvals service should include approval-blocked work-items")
        (assert-equal :approval-required
                      (getf approval :wait-reason)
                      "rgp approvals service should preserve approval-required wait reason")
        (assert-equal :workspace-write
                      (getf (first (getf approval :approval-requirements)) :policy)
                      "rgp approvals service should preserve the governing policy id")
        (assert-true (member :primary-execution-handle approval)
                     "rgp approvals service should advertise the primary execution-handle field")
        (assert-true (consp (getf approval :execution-handles))
                     "rgp approvals service should expose the governing execution handle list")
        (assert-equal "governed-work"
                      (getf (getf approval :execution-surface) :surface-kind)
                      "rgp approvals service should expose the governing execution surface")))))

(defun task-worker-and-workflow-ops-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/task-worker-workflow-service-contract/")))
    (sbcl-agent::ensure-environment)
    (let* ((form '(say "queued"))
           (command (sbcl-agent::normalize-form-command form))
           (enqueue-response (sbcl-agent::command-task-enqueue-service session form command 0)))
      (assert-equal :task
                    (getf enqueue-response :domain)
                    "task enqueue service should report task domain")
      (assert-equal :enqueue
                    (getf enqueue-response :operation)
                    "task enqueue service should identify enqueue operation")
      (assert-service-metadata-shape enqueue-response "task enqueue service")
      (let* ((task-id (getf (sbcl-agent::service-response-data enqueue-response) :id))
             (detail-response (sbcl-agent::query-task-detail-service session task-id))
             (monitor-response (sbcl-agent::query-task-monitor-service session task-id))
             (cancel-response (sbcl-agent::command-task-cancel-service session task-id)))
        (assert-equal "task"
                      (getf (getf (sbcl-agent::service-response-data enqueue-response) :execution-surface) :surface-kind)
                      "task enqueue service should expose a task execution surface")
        (assert-equal task-id
                      (getf (sbcl-agent::service-response-data detail-response) :id)
                      "task detail service should return the requested task")
        (assert-equal "task"
                      (getf (getf (sbcl-agent::service-response-data detail-response) :execution-surface) :surface-kind)
                      "task detail service should expose a task execution surface")
        (assert-service-metadata-shape monitor-response "task monitor service")
        (assert-equal "task"
                      (getf (getf (sbcl-agent::service-response-data monitor-response) :execution-surface) :surface-kind)
                      "task monitor service should expose a task execution surface")
        (assert-equal :cancelled
                      (getf (sbcl-agent::service-response-data cancel-response) :status)
                      "task cancel service should cancel the task")
        (assert-equal "task"
                      (getf (getf (sbcl-agent::service-response-data cancel-response) :execution-surface) :surface-kind)
                      "task cancel service should preserve the task execution surface")))
    (let* ((worker-start-response (sbcl-agent::command-worker-start-service session (make-test-provider)))
           (worker-id (getf (sbcl-agent::service-response-data worker-start-response) :id))
           (worker-detail-response (sbcl-agent::query-worker-detail-service session worker-id))
           (worker-stop-response (sbcl-agent::command-worker-stop-service session worker-id)))
      (assert-equal :worker
                    (getf worker-start-response :domain)
                    "worker start service should report worker domain")
      (assert-equal "worker"
                    (getf (getf (sbcl-agent::service-response-data worker-start-response) :execution-surface) :surface-kind)
                    "worker start service should expose a worker execution surface")
      (assert-service-metadata-shape worker-detail-response "worker detail service")
      (assert-equal worker-id
                    (getf (sbcl-agent::service-response-data worker-detail-response) :id)
                    "worker detail service should return the requested worker")
      (assert-equal "worker"
                    (getf (getf (sbcl-agent::service-response-data worker-detail-response) :execution-surface) :surface-kind)
                    "worker detail service should expose a worker execution surface")
      (assert-equal nil
                    (getf (sbcl-agent::service-response-data worker-stop-response) :running-p)
                    "worker stop service should stop the worker")
      (assert-equal "worker"
                    (getf (getf (sbcl-agent::service-response-data worker-stop-response) :execution-surface) :surface-kind)
                    "worker stop service should preserve the worker execution surface"))
    (let* ((work-item (sbcl-agent::create-work-item session "Workflow ops goal"))
           (work-item-id (sbcl-agent::work-item-id work-item))
           (wait-response (sbcl-agent::query-work-item-wait-service session work-item-id))
           (quarantine-response (sbcl-agent::command-work-item-quarantine-service session work-item-id "Need review"))
           (resume-response (sbcl-agent::command-work-item-resume-service session work-item-id :note "Resume it"))
           (steer-response (sbcl-agent::command-work-item-steer-service session
                                                                        work-item-id
                                                                        :phase :validate
                                                                        :next-step :run-cold-validation
                                                                        :note "Validation first"))
           (plan-response (sbcl-agent::query-work-item-plan-service session work-item-id)))
      (assert-service-metadata-shape wait-response "work-item wait service")
      (assert-equal :pending-validation
                    (getf (sbcl-agent::service-response-data wait-response) :why)
                    "work-item wait service should preserve the existing validation wait state")
      (assert-equal :quarantined
                    (getf (sbcl-agent::service-response-data quarantine-response) :status)
                    "work-item quarantine service should quarantine the work-item")
      (assert-equal :resumed
                    (getf (sbcl-agent::service-response-data resume-response) :status)
                    "work-item resume service should resume the work-item")
      (assert-equal :steer-work-item
                    (getf steer-response :operation)
                    "work-item steer service should identify the steering operation")
      (assert-service-metadata-shape steer-response "work-item steer service")
      (assert-equal :operator-steered
                    (getf (getf (sbcl-agent::service-response-data steer-response) :next-action) :type)
                    "work-item steer service should update the next action with operator steering")
      (assert-equal :validate
                    (getf (getf (sbcl-agent::service-response-data plan-response) :plan-steering) :operator-directed-phase)
                    "work-item plan query should surface the operator-directed phase")
      (assert-equal :run-cold-validation
                    (getf (getf (sbcl-agent::service-response-data plan-response) :plan-steering) :operator-directed-next-step)
                    "work-item plan query should surface the operator-directed next step")
      (assert-true (> (length (or (getf (sbcl-agent::service-response-data plan-response) :operator-steering-history) '())) 0)
                   "work-item plan query should preserve operator steering history"))
    (let* ((provider (make-test-provider))
           (result (progn
                     (sbcl-agent::execute-command
                      (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
                      provider
                      session)
                     (nth-value
                      0
                      (sbcl-agent::execute-command
                       (sbcl-agent::normalize-form-command
                        '(runtime/eval "(progn (defparameter sbcl-agent-user::*workflow-validation-probe* nil) (setf sbcl-agent-user::*workflow-validation-probe* :ok) sbcl-agent-user::*workflow-validation-probe*)" :mutating t))
                       provider
                       session))))
           (work-item-id (getf result :work-item-id))
           (complete-response (sbcl-agent::command-work-item-complete-validations-service session work-item-id :status :passed)))
      (assert-equal :complete-validations
                    (getf complete-response :operation)
                    "workflow complete-validations service should identify the validation completion operation")
      (assert-equal :committed
                    (getf (sbcl-agent::service-response-data complete-response) :status)
                    "workflow complete-validations service should finalize awaiting cold validation work"))))

(defun operator-memory-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/operator-memory-service/"))
         (thread (sbcl-agent::current-thread session))
         (turn (sbcl-agent::start-turn
                session
                thread
                (sbcl-agent::create-message session thread :user "Remember my preferences.")
                :metadata '(:source :test))))
    (sbcl-agent::remember-operator-memory-candidates
     session
     thread
     turn
     '((:category :preference
        :attribute "preferred language"
        :value "Common Lisp"
        :summary "The operator explicitly prefers Common Lisp."
        :confidence 0.9)))
    (let* ((memory-id "operator-memory-preference-preferred-language")
           (list-response (sbcl-agent::query-memory-list-service session))
           (detail-response (sbcl-agent::query-memory-detail-service session memory-id))
           (update-response (sbcl-agent::command-memory-update-service
                             session
                             memory-id
                             :value "Common Lisp and SBCL"
                             :summary "The operator prefers Common Lisp and SBCL."))
           (delete-response (sbcl-agent::command-memory-delete-service session memory-id)))
      (assert-equal :memory
                    (getf list-response :domain)
                    "memory list service should report the memory domain")
      (assert-equal :list
                    (getf list-response :operation)
                    "memory list service should identify the list operation")
      (assert-service-metadata-shape list-response "memory list service")
      (assert-equal memory-id
                    (getf (sbcl-agent::service-response-data detail-response) :memory-id)
                    "memory detail service should return the requested entry")
      (assert-equal "Common Lisp and SBCL"
                    (getf (sbcl-agent::service-response-data update-response) :value)
                    "memory update service should persist the updated value")
      (assert-equal t
                    (getf (sbcl-agent::service-response-data delete-response) :deleted-p)
                    "memory delete service should confirm deletion"))))
