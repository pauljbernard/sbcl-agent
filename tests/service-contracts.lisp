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

(defun environment-provider-service-contract-test ()
  (let ((sbcl-agent::*current-environment* nil)
        (sbcl-agent::*current-session* nil))
    (let* ((session (make-test-session :cwd "/tmp/environment-provider-service-contract/"))
           (environment (sbcl-agent::ensure-environment)))
      (sbcl-agent::bind-session-to-environment session environment)
      (sbcl-agent::ensure-environment-provider-profile
       :environment environment
       :config (sbcl-agent::make-config :provider "openai-compatible"
                                        :model "gpt-5"
                                        :working-directory "/tmp/environment-provider-service-contract/")
       :profile-name "default")
      (sbcl-agent::command-environment-provider-configure-service
       "local-fast"
       '(:provider "lm-studio"
         :model "qwen-coder"
         :fast-model "qwen-coder-mini"
         :api-base "http://localhost:1234/v1"
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
                      "environment provider service should expose supported routing modes"))
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
                    "turn detail should point back to the governing execution handle"))))

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
      (assert-equal :execution-handle
                    (getf (sbcl-agent::service-response-data runtime-inspect) :resolved-via)
                    "kernel inspect should identify the execution-handle read path"))

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
                    "kernel control should preserve the last observed compatibility status in post-state"))

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

    (let ((self-mod-session (make-test-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
                     "shell inspector service should resolve focused kernel objects"))
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
      (assert-true (> (getf package-result :workflow-count) 0)
                   "platform package service should return workflow inventory counts")
      (assert-true (probe-file output-path)
                   "platform package service should write the requested descriptor")
      (let ((contents (uiop:read-file-string output-path)))
        (assert-true (search "\"package_id\":\"demo-kit\"" contents)
                     "platform package service should persist the package id")
        (assert-true (search "\"capability_count\":1" contents)
                     "platform package service should persist the selected capability filter")
        (assert-true (search "\"workflow_ids\"" contents)
                     "platform package service should persist a top-level workflow contents index")
        (assert-true (search "\"sdk_command_ids\"" contents)
                     "platform package service should persist a top-level sdk command contents index")
        (assert-true (search "\"desktop-host-shell\"" contents)
                     "platform package service should persist desktop host workflow metadata"))
      (let* ((show-response (sbcl-agent::query-platform-package-service output-path
                                                                        :session session))
             (show-result (sbcl-agent::service-response-data show-response)))
        (assert-equal :package
                      (getf show-response :operation)
                      "platform package query service should identify package operation")
        (assert-service-metadata-shape show-response "platform package query service")
        (assert-equal t
                      (getf show-result :valid-p)
                      "platform package query service should report valid descriptors"))
      (let* ((validate-response
               (sbcl-agent::command-platform-validate-package-service output-path
                                                                      :session session))
             (validate-result (sbcl-agent::service-response-data validate-response)))
        (assert-equal :validate-package
                      (getf validate-response :operation)
                      "platform package validate service should identify validation operation")
        (assert-service-metadata-shape validate-response "platform package validate service")
        (assert-equal t
                      (getf validate-result :valid-p)
                      "platform package validate service should report valid descriptors"))
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
                      "platform package import service should return the imported package summary"))
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
                      "platform imported package service should return the imported package by id"))
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
                        "platform package install service should return the applied active-package profile")))
      (let* ((invalid-path "/tmp/platform-invalid-service-contract.aop"))
        (with-open-file (stream invalid-path
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (write-string "{\"package_format\":\"intentos.aop.v1\",\"package_id\":\"broken-kit\",\"title\":\"Broken Kit\",\"contents\":{\"capability_ids\":[],\"policy_ids\":[],\"workflow_ids\":[],\"sdk_command_ids\":[],\"compatibility_kinds\":[]},\"manifest\":{\"manifest_version\":1,\"kernel_class\":\"execution-kernel\",\"kernel_api\":[\"invoke\",\"inspect\",\"control\"],\"capabilities\":[],\"policies\":[],\"workflows\":[{\"workflow_id\":\"broken\",\"entrypoints\":[\"missing-command\"],\"required_capabilities\":[],\"control_actions\":[]}],\"sdk_commands\":[],\"compatibility_kinds\":[]}}" stream))
        (let* ((invalid-response
                 (sbcl-agent::command-platform-validate-package-service invalid-path
                                                                        :session session))
               (invalid-result (sbcl-agent::service-response-data invalid-response)))
          (assert-equal nil
                        (getf invalid-result :valid-p)
                        "platform package validate service should reject invalid workflow entrypoints")
          (assert-true (find "manifest workflows contain invalid entrypoints or capability references"
                             (getf invalid-result :validation-issues)
                             :test #'string=)
                       "platform package validate service should expose structural workflow validation failures"))))))

(defun execution-service-contract-test ()
  (let ((session (make-test-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
             (let* ((session (make-test-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
    (let* ((session (make-test-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
    (let* ((conversation-session (make-test-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
    (let* ((prepare-session (make-test-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
    (let* ((mutation-session (make-test-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
