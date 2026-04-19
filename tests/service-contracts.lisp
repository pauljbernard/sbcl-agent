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
                   "thread list service should return at least one thread"))))

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
                    "approval request should move the workflow record into awaiting-approval"))
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
                    "session summary service should expose the current plan"))
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
      (assert-service-metadata-shape review-response "mutation review service")))
    (let ((bind-response (sbcl-agent::command-rgp-bind-service session
                                                               :request-id "req-1"
                                                               :agent-session-id "sess-1")))
      (assert-equal :rgp
                    (getf bind-response :domain)
                    "rgp bind service should report rgp domain")
      (assert-equal :bind
                    (getf bind-response :operation)
                    "rgp bind service should identify bind operation")
      (assert-service-metadata-shape bind-response "rgp bind service")
      (assert-equal "req-1"
                    (getf (getf (sbcl-agent::service-response-data bind-response) :binding) :request-id)
                    "rgp bind service should return the bound request id"))
    (let ((show-response (sbcl-agent::query-rgp-show-service session)))
      (assert-equal :show
                    (getf show-response :operation)
                    "rgp show service should identify show operation")
      (assert-service-metadata-shape show-response "rgp show service"))
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
                      "rgp approvals service should preserve the governing policy id")))))

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
        (assert-equal task-id
                      (getf (sbcl-agent::service-response-data detail-response) :id)
                      "task detail service should return the requested task")
        (assert-service-metadata-shape monitor-response "task monitor service")
        (assert-equal :cancelled
                      (getf (sbcl-agent::service-response-data cancel-response) :status)
                      "task cancel service should cancel the task")))
    (let* ((worker-start-response (sbcl-agent::command-worker-start-service session (make-test-provider)))
           (worker-id (getf (sbcl-agent::service-response-data worker-start-response) :id))
           (worker-detail-response (sbcl-agent::query-worker-detail-service session worker-id))
           (worker-stop-response (sbcl-agent::command-worker-stop-service session worker-id)))
      (assert-equal :worker
                    (getf worker-start-response :domain)
                    "worker start service should report worker domain")
      (assert-service-metadata-shape worker-detail-response "worker detail service")
      (assert-equal worker-id
                    (getf (sbcl-agent::service-response-data worker-detail-response) :id)
                    "worker detail service should return the requested worker")
      (assert-equal nil
                    (getf (sbcl-agent::service-response-data worker-stop-response) :running-p)
                    "worker stop service should stop the worker"))
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
                   "work-item plan query should preserve operator steering history"))))
