(in-package #:sbcl-agent/tests)

(defun session-summary-recent-transcript-test ()
  (let ((session (sbcl-agent::make-default-session)))
    (sbcl-agent::append-transcript-entry session :user "first")
    (sbcl-agent::append-transcript-entry session :assistant "second")
    (let ((summary (sbcl-agent::session-summary session)))
      (assert-equal 2
                    (length (getf summary :recent-transcript))
                    "session summary should include recent transcript entries")
      (assert-equal "second"
                    (getf (second (getf summary :recent-transcript)) :content)
                    "recent transcript should preserve the latest assistant turn"))))

(defun provider-session-summary-compact-test ()
  (let ((session (sbcl-agent::make-default-session)))
    (sbcl-agent::append-transcript-entry session :user (make-string 400 :initial-element #\x))
    (let ((summary (sbcl-agent::provider-session-summary session)))
      (assert-true (null (getf summary :wait-summary))
                   "provider session summary should omit heavyweight workflow fields")
      (assert-true (stringp (getf summary :current-thread-id))
                   "provider session summary should expose the active thread id")
      (assert-true (>= (getf summary :thread-count) 1)
                   "provider session summary should expose thread count")
      (assert-true (integerp (getf summary :message-count))
                   "provider session summary should expose persisted message count")
      (assert-true (integerp (getf summary :turn-count))
                   "provider session summary should expose persisted turn count")
      (assert-true (integerp (getf summary :operation-count))
                   "provider session summary should expose persisted operation count")
      (assert-equal 0
                    (getf summary :incident-count)
                    "provider session summary should expose incident count")
      (assert-equal 1
                    (length (getf summary :recent-transcript))
                    "provider session summary should keep recent transcript entries")
      (assert-true (< (length (getf (first (getf summary :recent-transcript)) :content)) 260)
                   "provider session summary should truncate oversized transcript content"))))

(defun provider-request-context-test ()
  (let* ((session (sbcl-agent::make-default-session))
         (environment (sbcl-agent::make-default-environment :session session))
         (thread (sbcl-agent::current-thread session))
         (user-message (sbcl-agent::create-message session thread :user "inspect provider request"))
         (turn (sbcl-agent::start-turn session thread user-message
                                       :metadata '(:source :test)))
         (assistant-message (sbcl-agent::create-message session thread :assistant "pending"))
         (ignore (sbcl-agent::complete-turn session thread turn assistant-message
                                            :status :completed))
         (request (sbcl-agent::make-provider-request-from-session
                   "inspect provider request"
                   session
                   :thread thread
                   :turn turn
                   :operator-mode :conversation
                   :stream-p t)))
    (declare (ignore ignore))
    (sbcl-agent::bind-session-to-environment session environment)
    (setf request (sbcl-agent::make-provider-request-from-session
                   "inspect provider request"
                   session
                   :thread thread
                   :turn turn
                   :operator-mode :conversation
                   :stream-p t))
    (assert-equal :conversation
                  (sbcl-agent::provider-request-operator-mode request)
                  "provider request should retain the operator mode")
    (assert-true (sbcl-agent::provider-request-stream-p request)
                 "provider request should retain stream intent")
    (assert-equal (sbcl-agent::thread-id thread)
                  (getf (sbcl-agent::provider-request-thread-context request) :id)
                  "provider request should expose thread context separately from session summary")
    (assert-equal (sbcl-agent::turn-id turn)
                  (getf (sbcl-agent::provider-request-turn-context request) :id)
                  "provider request should expose turn context separately from session summary")
    (assert-equal (sbcl-agent::agent-session-cwd session)
                  (getf (sbcl-agent::provider-request-runtime-summary request) :cwd)
                  "provider request should expose runtime summary")
    (assert-equal 0
                  (getf (sbcl-agent::provider-request-runtime-summary request) :open-incident-count)
                  "provider request runtime summary should expose open incident count")
    (assert-equal (sbcl-agent::agent-session-cwd session)
                  (getf (sbcl-agent::provider-request-workspace-summary request) :cwd)
                  "provider request should expose workspace summary")
    (assert-equal 0
                  (getf (sbcl-agent::provider-request-workspace-summary request) :incident-count)
                  "provider request workspace summary should expose incident count")
    (assert-true (listp (getf (sbcl-agent::provider-request-policy-summary request) :approved-policies))
                 "provider request should expose policy summary")
    (assert-equal (sbcl-agent::environment-id environment)
                  (getf (sbcl-agent::provider-request-environment-context request) :environment-id)
                  "provider request should expose linked environment context")
    (assert-true (listp (getf (sbcl-agent::provider-request-environment-context request) :thread-refs))
                 "provider request environment context should expose compact thread refs")
    (assert-true (listp (getf (sbcl-agent::provider-request-retrieval-dossier request) :intent))
                 "provider request should expose a retrieved dossier")
    (assert-true (typep (sbcl-agent::provider-request-cognition-bundle request)
                        'sbcl-agent::cognition-bundle)
                 "provider request should expose a canonical cognition bundle")
    (assert-true (listp (sbcl-agent::cognition-bundle-execution-strategy
                         (sbcl-agent::provider-request-cognition-bundle request)))
                 "provider request cognition bundle should expose execution strategy")
    (assert-true (listp (sbcl-agent::cognition-bundle-validation-strategy
                         (sbcl-agent::provider-request-cognition-bundle request)))
                 "provider request cognition bundle should expose validation strategy")
    (assert-true (listp (sbcl-agent::cognition-bundle-validation-plan
                         (sbcl-agent::provider-request-cognition-bundle request)))
                 "provider request cognition bundle should expose validation plan")
    (assert-true (listp (getf (sbcl-agent::provider-request-reasoning-brief request) :facts))
                 "provider request should expose an environment-grounded reasoning brief")
    (assert-true (listp (getf (sbcl-agent::provider-request-planning-brief request) :ordered-steps))
                 "provider request should expose an environment-grounded planning brief")
    (assert-true (listp (sbcl-agent::provider-request-session-summary request))
                 "provider request should preserve the compact session summary")))

(defun provider-request-transcript-memory-context-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-transcript-memory/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-transcript-memory/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::append-transcript-entry session :user "We previously debugged calculator latency in Surface.")
    (sbcl-agent::append-transcript-entry session :assistant "The root cause was provider round-trip latency.")
    (let* ((request (sbcl-agent::make-provider-request-from-session
                     "Why was the calculator in Surface slow?"
                     session
                     :operator-mode :conversation
                     :stream-p nil))
           (conversation-context (getf (sbcl-agent::provider-request-retrieval-dossier request)
                                       :conversation-context))
           (memory (getf conversation-context :transcript-memory))
           (entries (getf memory :entries)))
      (assert-true (listp conversation-context)
                   "provider request dossier should include conversation context")
      (assert-true (listp entries)
                   "provider request dossier should include transcript memory entries")
      (assert-true (search "calculator"
                           (string-downcase (getf (first entries) :content)))
                   "provider request transcript memory should include calculator-related history"))))

(defun provider-request-operator-memory-context-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-operator-memory/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-operator-memory/"
                       :session session))
         (thread nil)
         (turn nil))
    (sbcl-agent::bind-session-to-environment session environment)
    (setf thread (sbcl-agent::current-thread session)
          turn (sbcl-agent::start-turn
                session
                thread
                (sbcl-agent::create-message session thread :user "Remember my preferences.")
                :metadata '(:source :test)))
    (sbcl-agent::remember-operator-memory-candidates
     session
     thread
     turn
     '((:category :preference
        :attribute "preferred language"
        :value "Common Lisp"
        :summary "The operator explicitly prefers Common Lisp."
        :confidence 0.9)))
    (let* ((request (sbcl-agent::make-provider-request-from-session
                     "What language do I prefer?"
                     session
                     :operator-mode :conversation
                     :stream-p nil))
           (conversation-context (getf (sbcl-agent::provider-request-retrieval-dossier request)
                                       :conversation-context))
           (memory (getf conversation-context :operator-memory))
           (entries (getf memory :entries)))
      (assert-true (listp entries)
                   "provider request dossier should include operator memory entries")
      (assert-equal "operator-memory-preference-preferred-language"
                    (getf (first entries) :memory-id)
                    "provider request operator memory should include the stored preference"))))

(defun environment-provider-context-precedence-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-provider-precedence/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-provider-precedence/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-work-item session "Provider context precedence" :transaction-scope :test)
    (let* ((environment-summary (sbcl-agent::environment-summary environment))
           (session-summary (sbcl-agent::provider-session-summary session))
           (workspace-summary (sbcl-agent::provider-workspace-summary session)))
      (assert-equal (getf environment-summary :thread-count)
                    (getf session-summary :thread-count)
                    "provider session summary should align with environment-owned thread counts when bound")
      (assert-equal (getf environment-summary :artifact-count)
                    (getf workspace-summary :artifact-count)
                    "provider workspace summary should align with environment-owned artifact counts when bound")
      (assert-equal (getf environment-summary :work-item-count)
                    (getf workspace-summary :work-item-count)
                    "provider workspace summary should align with environment-owned workflow counts when bound")
      (assert-equal (getf environment-summary :id)
                    (getf session-summary :environment-id)
                    "provider session summary should expose the active environment identity"))))

(defun provider-rendering-context-test ()
  (let* ((request (sbcl-agent::make-provider-request
                   :prompt "describe the current state"
                   :session-summary '(:recent-transcript ((:role :assistant :content "Earlier")))
                   :thread-context '(:id "thread-1" :title "Default Thread")
                   :turn-context '(:id "turn-1" :status :running)
                   :environment-context '(:environment-id "env-1"
                                          :thread-count 2
                                          :work-item-count 1
                                          :thread-refs ((:id "thread-1" :title "Default Thread" :status :active)))
                   :surface-context '(:active-workspace "conversations"
                                      :selected-conversation-section "draft"
                                      :focus (:kind :approval
                                              :approval-id "approval-1")
                                      :draft-summary "Need approval-aware follow-up.")
                   :surface-actions '((:tool-id :desktop/show
                                       :label "Inspect Surface")
                                      (:tool-id :desktop/action
                                       :label "Open approval in Surface"
                                       :arguments (:action-id "open-approval-1")))
                   :runtime-summary '(:cwd "/tmp/project" :package "SBCL-AGENT-USER" :open-incident-count 1)
                   :workspace-summary '(:cwd "/tmp/project" :artifact-count 2 :incident-count 1)
                   :policy-summary '(:approved-policies (:safe-read) :open-incident-count 1)
                   :retrieval-dossier '(:intent (:category :runtime-inspection)
                                       :ranking (:enabled-p t :strategy :keyword-overlap)
                                       :plan (:expansion-posture :compact-first)
                                       :runtime-context (:summary (:domain :runtime)))
                   :cognition-bundle (sbcl-agent::make-cognition-bundle
                                      :retrieval-dossier '(:intent (:category :runtime-inspection))
                                      :reasoning-brief '(:reasoning-mode :environment-grounded
                                                        :facts ()
                                                        :uncertainties ()
                                                        :blockers ()
                                                        :validation-obligations ()
                                                        :evidence-actions ())
                                      :planning-brief '(:planning-mode :environment-grounded
                                                      :ordered-steps ((:phase :inspect)))
                                      :execution-strategy '(:mode :inspection-first
                                                            :next-step :plan)
                                      :validation-strategy '(:mode :opportunistic
                                                             :next-step :no-additional-validation-required)
                                      :validation-plan '(:mode :opportunistic
                                                         :next-step :no-additional-validation-required
                                                         :priority :low
                                                         :work-item-count 0
                                                         :entries ())
                                      :outcome-brief '(:outcome-mode :expectation-vs-observation
                                                       :recommended-next-step :conclude))
                   :reasoning-brief '(:reasoning-mode :environment-grounded
                                      :facts ((:kind :environment-authority :statement "Environment env-1 is authoritative."))
                                      :uncertainties ()
                                      :blockers ()
                                      :validation-obligations ()
                                      :evidence-actions ())
                   :planning-brief '(:planning-mode :environment-grounded
                                     :primary-goal (:statement "describe the current state")
                                     :ordered-steps ((:phase :inspect :statement "Inspect first."))
                                     :constraints ()
                                     :success-criteria ((:kind :grounding :statement "Stay grounded.")))
                   :outcome-brief '(:outcome-mode :expectation-vs-observation
                                    :expected-phases (:mutate)
                                    :observed-summary (:observed-consequence-count 1)
                                    :mismatches ()
                                    :recommended-next-step :conclude)
                   :operator-mode :conversation
                   :stream-p t))
         (prompt (sbcl-agent::build-openai-user-prompt request))
         (mock-response (sbcl-agent::build-mock-response request)))
    (assert-true (search "Operator mode: :CONVERSATION" prompt)
                 "build-openai-user-prompt should render operator mode")
    (assert-true (search "Thread: (:ID \"thread-1\"" prompt)
                 "build-openai-user-prompt should render thread context")
    (assert-true (search "Environment context: (:ENVIRONMENT-ID \"env-1\"" prompt)
                 "build-openai-user-prompt should render environment context")
    (assert-true (search "Surface context: (:ACTIVE-WORKSPACE \"conversations\"" prompt)
                 "build-openai-user-prompt should render surface context")
    (assert-true (search "Available Surface actions: ((:TOOL-ID :DESKTOP/SHOW" prompt)
                 "build-openai-user-prompt should render available surface actions")
    (assert-true (search "Runtime summary: (:CWD \"/tmp/project\"" prompt)
                 "build-openai-user-prompt should render runtime summary")
    (assert-true (search "Retrieved environment dossier: (:INTENT (:CATEGORY :RUNTIME-INSPECTION)" prompt)
                 "build-openai-user-prompt should render the retrieval dossier")
    (assert-true (search "Canonical cognition bundle:" prompt)
                 "build-openai-user-prompt should render the canonical cognition bundle")
    (assert-true (search ":EXECUTION-STRATEGY" prompt)
                 "build-openai-user-prompt should render cognition execution strategy detail")
    (assert-true (search "Reasoning brief: (:REASONING-MODE :ENVIRONMENT-GROUNDED" prompt)
                 "build-openai-user-prompt should render the reasoning brief")
    (assert-true (search "Planning brief: (:PLANNING-MODE :ENVIRONMENT-GROUNDED" prompt)
                 "build-openai-user-prompt should render the planning brief")
    (assert-true (search "Outcome brief: (:OUTCOME-MODE :EXPECTATION-VS-OBSERVATION" prompt)
                 "build-openai-user-prompt should render the outcome brief when present")
    (assert-true (search "Treat dossier ranking metadata as advisory prioritization" prompt)
                 "build-openai-user-prompt should explain that ranking metadata is advisory")
    (assert-true (search "Treat the canonical cognition bundle as the default reasoning loop" prompt)
                 "build-openai-user-prompt should instruct the provider to follow the canonical cognition loop")
    (assert-true (search "When the cognition bundle carries a retrieval focus plan, prioritize those domains first" prompt)
                 "build-openai-user-prompt should instruct the provider to prioritize retrieval focus when present")
    (assert-true (search "When the cognition bundle carries a validation plan, treat it as the concrete validation agenda" prompt)
                 "build-openai-user-prompt should instruct the provider to follow the validation plan when present")
    (assert-true (search "When the cognition bundle carries an action agenda, treat it as the ordered list of next steps" prompt)
                 "build-openai-user-prompt should instruct the provider to follow the derived action agenda when present")
    (assert-true (search "Reuse similar prior successes when they fit the current evidence" prompt)
                 "build-openai-user-prompt should instruct the provider to reuse prior successful outcomes")
    (assert-true (search "Use the reasoning brief to distinguish environment-backed facts" prompt)
                 "build-openai-user-prompt should instruct the provider to reason from facts and uncertainties")
    (assert-true (search "Use the planning brief as the default execution outline" prompt)
                 "build-openai-user-prompt should instruct the provider to follow the environment-grounded plan by default")
    (assert-true (search ":OPEN-INCIDENT-COUNT 1" prompt)
                 "build-openai-user-prompt should render incident posture in summaries")
    (assert-true (search "Governance directives: The environment is not currently mutation-clean." prompt)
                 "build-openai-user-prompt should render conservative governance directives when incidents are open")
    (assert-true (search "Do not propose new governed mutation actions" prompt)
                 "build-openai-user-prompt should tell the provider to avoid new governed mutations under active governance burden")
    (assert-true (search "Calculator interactions and other transient local UI control actions" prompt)
                 "build-openai-user-prompt should exempt calculator control from governed mutation posture")
    (assert-equal :conversation
                  (getf (sbcl-agent::assistant-response-metadata mock-response) :operator-mode)
                  "mock provider responses should preserve operator mode metadata")
    (assert-equal "thread-1"
                  (getf (getf (sbcl-agent::assistant-response-metadata mock-response) :thread) :id)
                  "mock provider responses should preserve thread context metadata")
    (assert-equal "env-1"
                  (getf (getf (sbcl-agent::assistant-response-metadata mock-response) :environment) :environment-id)
                  "mock provider responses should preserve environment context metadata")))

(defun calculator-control-policy-test ()
  (assert-equal :calculator-control
                (getf (sbcl-agent::describe-tool :calculator/append-token) :policy)
                "calculator append-token should use calculator-control policy")
  (assert-equal :calculator-control
                (getf (sbcl-agent::describe-tool :calculator/evaluate) :policy)
                "calculator evaluate should use calculator-control policy")
  (let ((action (sbcl-agent::make-assistant-action
                 :type :tool
                 :payload '(:tool-id :calculator/append-token :arguments (:token "7")))))
    (assert-true (sbcl-agent::immediate-assistant-action-p action)
                 "calculator control actions should execute immediately")
    (assert-true (not (sbcl-agent::governed-assistant-action-p action))
                 "calculator control actions should not be treated as governed mutations")))

(defun provider-rendering-governance-ready-test ()
  (let* ((request (sbcl-agent::make-provider-request
                   :prompt "inspect and suggest next step"
                   :session-summary '(:recent-transcript ())
                   :thread-context '(:id "thread-1")
                   :turn-context '(:id "turn-1" :status :running)
                   :environment-context '(:environment-id "env-1")
                   :runtime-summary '(:cwd "/tmp/project" :package "SBCL-AGENT-USER" :open-incident-count 0)
                   :workspace-summary '(:cwd "/tmp/project" :artifact-count 0 :incident-count 0)
                   :policy-summary '(:approved-policies (:safe-read))
                   :retrieval-dossier '(:intent (:category :code-change))
                   :reasoning-brief '(:reasoning-mode :environment-grounded
                                      :facts ()
                                      :uncertainties ()
                                      :blockers ()
                                      :validation-obligations ()
                                      :evidence-actions ())
                   :planning-brief '(:planning-mode :environment-grounded
                                     :ordered-steps ((:phase :inspect :statement "Inspect first.")))
                   :operator-mode :conversation
                   :stream-p nil))
         (prompt (sbcl-agent::build-openai-user-prompt request)))
    (assert-true (search "Governance directives: The environment appears mutation-ready." prompt)
                 "build-openai-user-prompt should render mutation-ready governance guidance when the environment is clean")
    (assert-true (search "If you propose a governed mutation, keep it evidence-backed, minimal, and aligned with the planning brief." prompt)
                 "build-openai-user-prompt should render mutation-ready proposal guidance")))

(defun provider-request-single-environment-snapshot-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-environment-snapshot/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-environment-snapshot/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-work-item session "Provider snapshot consistency" :transaction-scope :test)
    (let* ((request (sbcl-agent::make-provider-request-from-session "snapshot check" session))
           (environment-context (sbcl-agent::provider-request-environment-context request))
           (session-summary (sbcl-agent::provider-request-session-summary request))
           (runtime-summary (sbcl-agent::provider-request-runtime-summary request))
           (workspace-summary (sbcl-agent::provider-request-workspace-summary request))
           (policy-summary (sbcl-agent::provider-request-policy-summary request))
           (environment-summary (sbcl-agent::environment-summary environment)))
      (assert-equal (getf environment-summary :id)
                    (getf session-summary :environment-id)
                    "provider session summary should use the request snapshot environment id")
      (assert-equal (getf environment-summary :id)
                    (getf runtime-summary :environment-id)
                    "provider runtime summary should use the request snapshot environment id")
      (assert-equal (getf environment-summary :id)
                    (getf workspace-summary :environment-id)
                    "provider workspace summary should use the request snapshot environment id")
      (assert-equal (getf environment-summary :id)
                    (getf policy-summary :environment-id)
                    "provider policy summary should use the request snapshot environment id")
      (assert-equal (getf environment-summary :id)
                    (getf environment-context :environment-id)
                    "provider environment context should use the same request snapshot environment id")
      (assert-equal (getf environment-summary :work-item-count)
                    (getf workspace-summary :work-item-count)
                    "provider workspace summary should use the request snapshot work-item count")
      (assert-equal (getf environment-summary :work-item-count)
                    (getf environment-context :work-item-count)
                    "provider environment context should use the same request snapshot work-item count"))))

(defun provider-context-bundle-consistency-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-context-bundle/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-context-bundle/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-work-item session "Bundle consistency" :transaction-scope :test)
    (let* ((thread (sbcl-agent::current-thread session))
           (user-message (sbcl-agent::create-message session thread :user "bundle check"))
           (turn (sbcl-agent::start-turn session thread user-message :metadata '(:source :bundle-test)))
           (assistant-message (sbcl-agent::create-message session thread :assistant "bundle response"))
           (ignore (sbcl-agent::complete-turn session thread turn assistant-message :status :completed))
           (surface-context '(:active-workspace "conversations"
                              :selected-conversation-section "draft"
                              :environment-focus (:kind :approval
                                                  :approval-id "approval-1")))
           (surface-actions '((:tool-id :desktop/show
                               :label "Inspect Surface")
                              (:tool-id :desktop/action
                               :label "Open approval"
                               :arguments (:action-id "approval-open-1"))))
           (bundle (sbcl-agent::build-provider-context-bundle session
                                                              :thread thread
                                                              :turn turn
                                                              :prompt "bundle check"
                                                              :surface-context surface-context
                                                              :surface-actions surface-actions
                                                              :operator-mode :repl-bridge))
           (request (sbcl-agent::make-provider-request-from-session "bundle check"
                                                                    session
                                                                    :thread thread
                                                                    :turn turn
                                                                    :surface-context surface-context
                                                                    :surface-actions surface-actions)))
      (declare (ignore ignore))
      (assert-equal (sbcl-agent::provider-context-bundle-session-summary bundle)
                    (sbcl-agent::provider-request-session-summary request)
                    "provider request session summary should come from the provider context bundle")
      (assert-equal (sbcl-agent::provider-context-bundle-thread-context bundle)
                    (sbcl-agent::provider-request-thread-context request)
                    "provider request thread context should come from the provider context bundle")
      (assert-equal (sbcl-agent::provider-context-bundle-turn-context bundle)
                    (sbcl-agent::provider-request-turn-context request)
                    "provider request turn context should come from the provider context bundle")
      (assert-equal (sbcl-agent::provider-context-bundle-environment-context bundle)
                    (sbcl-agent::provider-request-environment-context request)
                    "provider request environment context should come from the provider context bundle")
      (assert-equal (sbcl-agent::provider-context-bundle-runtime-summary bundle)
                    (sbcl-agent::provider-request-runtime-summary request)
                    "provider request runtime summary should come from the provider context bundle")
      (assert-equal (sbcl-agent::provider-context-bundle-workspace-summary bundle)
                    (sbcl-agent::provider-request-workspace-summary request)
                    "provider request workspace summary should come from the provider context bundle")
      (assert-equal (sbcl-agent::provider-context-bundle-policy-summary bundle)
                    (sbcl-agent::provider-request-policy-summary request)
                    "provider request policy summary should come from the provider context bundle")
      (assert-equal surface-context
                    (sbcl-agent::provider-context-bundle-surface-context bundle)
                    "provider context bundle should preserve supplied Surface context")
      (assert-equal surface-actions
                    (sbcl-agent::provider-context-bundle-surface-actions bundle)
                    "provider context bundle should preserve supplied Surface actions")
      (assert-equal (sbcl-agent::provider-context-bundle-surface-context bundle)
                    (sbcl-agent::provider-request-surface-context request)
                    "provider request should preserve Surface context from the context bundle")
      (assert-equal (sbcl-agent::provider-context-bundle-surface-actions bundle)
                    (sbcl-agent::provider-request-surface-actions request)
                    "provider request should preserve Surface actions from the context bundle")
      (assert-equal (sbcl-agent::provider-context-bundle-retrieval-dossier bundle)
                    (sbcl-agent::provider-request-retrieval-dossier request)
                    "provider request retrieval dossier should come from the provider context bundle")
      (assert-equal (sbcl-agent::cognition-bundle-summary
                     (sbcl-agent::provider-context-bundle-cognition-bundle bundle))
                    (sbcl-agent::cognition-bundle-summary
                     (sbcl-agent::provider-request-cognition-bundle request))
                    "provider request cognition bundle should preserve the bundle cognition summary")
      (assert-equal (sbcl-agent::provider-context-bundle-reasoning-brief bundle)
                    (sbcl-agent::provider-request-reasoning-brief request)
                    "provider request reasoning brief should come from the provider context bundle")
      (assert-equal (sbcl-agent::provider-context-bundle-planning-brief bundle)
                    (sbcl-agent::provider-request-planning-brief request)
                    "provider request planning brief should come from the provider context bundle")
      (assert-equal (sbcl-agent::provider-context-bundle-outcome-brief bundle)
                    (sbcl-agent::provider-request-outcome-brief request)
                    "provider request outcome brief should come from the provider context bundle"))))

(defun provider-request-snapshot-conversion-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-work-item session "Request snapshot conversion" :transaction-scope :test)
    (let* ((surface-context '(:active-workspace "browser"
                              :selected-browser-domain "packages"
                              :environment-focus (:kind :runtime
                                                  :runtime-package "SBCL-AGENT.CALCULATOR")))
           (surface-actions '((:tool-id :desktop/show
                               :label "Inspect Surface")
                              (:tool-id :desktop/action
                               :label "Open package browser"
                               :arguments (:action-id "packages-open-1"))))
           (bundle (sbcl-agent::build-provider-context-bundle session
                                                              :prompt "snapshot conversion"
                                                              :surface-context surface-context
                                                              :surface-actions surface-actions
                                                              :operator-mode :repl-bridge))
           (snapshot (sbcl-agent::provider-context-bundle->request-snapshot bundle))
           (request (sbcl-agent::make-provider-request-from-session "snapshot conversion"
                                                                    session
                                                                    :surface-context surface-context
                                                                    :surface-actions surface-actions)))
      (assert-equal (sbcl-agent::provider-context-bundle-session-summary bundle)
                    (sbcl-agent::provider-request-snapshot-session-summary snapshot)
                    "provider request snapshot should preserve the bundle session summary")
      (assert-equal (sbcl-agent::provider-context-bundle-environment-context bundle)
                    (sbcl-agent::provider-request-snapshot-environment-context snapshot)
                    "provider request snapshot should preserve the bundle environment context")
      (assert-equal surface-context
                    (sbcl-agent::provider-request-snapshot-surface-context snapshot)
                    "provider request snapshot should preserve Surface context")
      (assert-equal surface-actions
                    (sbcl-agent::provider-request-snapshot-surface-actions snapshot)
                    "provider request snapshot should preserve Surface actions")
      (assert-equal (sbcl-agent::provider-request-snapshot-surface-context snapshot)
                    (sbcl-agent::provider-request-surface-context request)
                    "provider request should consume the request snapshot Surface context")
      (assert-equal (sbcl-agent::provider-request-snapshot-surface-actions snapshot)
                    (sbcl-agent::provider-request-surface-actions request)
                    "provider request should consume the request snapshot Surface actions")
      (assert-equal (sbcl-agent::provider-request-snapshot-runtime-summary snapshot)
                    (sbcl-agent::provider-request-runtime-summary request)
                    "provider request should consume the request snapshot runtime summary")
      (assert-equal (sbcl-agent::provider-request-snapshot-policy-summary snapshot)
                    (sbcl-agent::provider-request-policy-summary request)
                    "provider request should consume the request snapshot policy summary")
      (assert-equal (sbcl-agent::provider-request-snapshot-retrieval-dossier snapshot)
                    (sbcl-agent::provider-request-retrieval-dossier request)
                    "provider request should consume the request snapshot retrieval dossier")
      (assert-equal (sbcl-agent::cognition-bundle-summary
                     (sbcl-agent::provider-request-snapshot-cognition-bundle snapshot))
                    (sbcl-agent::cognition-bundle-summary
                     (sbcl-agent::provider-request-cognition-bundle request))
                    "provider request should consume the request snapshot cognition bundle")
      (assert-equal (sbcl-agent::provider-request-snapshot-reasoning-brief snapshot)
                    (sbcl-agent::provider-request-reasoning-brief request)
                    "provider request should consume the request snapshot reasoning brief")
      (assert-equal (sbcl-agent::provider-request-snapshot-planning-brief snapshot)
                    (sbcl-agent::provider-request-planning-brief request)
                    "provider request should consume the request snapshot planning brief")
      (assert-equal (sbcl-agent::provider-request-snapshot-outcome-brief snapshot)
                    (sbcl-agent::provider-request-outcome-brief request)
                    "provider request should consume the request snapshot outcome brief"))))

(defun provider-summaries-prefer-environment-snapshot-domains-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-snapshot-domains/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-snapshot-domains/"
                       :session session))
         (command (sbcl-agent::normalize-form-command '(ask "queued from provider snapshot domain test")))
         (action (sbcl-agent::make-assistant-action
                  :type :eval
                  :payload '(:code "(+ 40 2)" :language :lisp))))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::enqueue-task session command :priority 2)
    (let ((worker (sbcl-agent::make-worker-state :id "provider-worker"
                                                 :thread nil
                                                 :running-p t
                                                 :session-id (sbcl-agent::agent-session-id session))))
      (setf (sbcl-agent::agent-session-workers session) (list worker)
            (sbcl-agent::agent-session-workers-tail session) (last (sbcl-agent::agent-session-workers session))))
    (sbcl-agent::stage-pending-actions session (list action))
    (sbcl-agent::create-environment-artifact
     session
     :validation
     nil
     :title "Provider snapshot artifact"
     :summary "Provider summaries should use environment-native artifact evidence.")
    (sbcl-agent::create-incident session
                                 :runtime-condition
                                 "Provider snapshot incident"
                                 "Provider summaries should use environment-native incident counts.")
    (sbcl-agent::refresh-environment-agent-domain environment session)
    (setf (sbcl-agent::agent-session-pending-actions session) '()
          (sbcl-agent::agent-session-workers session) '()
          (sbcl-agent::agent-session-workers-tail session) nil
          (sbcl-agent::agent-session-incidents session) '()
          (sbcl-agent::agent-session-incidents-tail session) nil
          (sbcl-agent::agent-session-artifacts session) '()
          (sbcl-agent::agent-session-artifacts-tail session) nil
          (sbcl-agent::agent-session-tasks session) '()
          (sbcl-agent::agent-session-tasks-tail session) nil)
    (let* ((request (sbcl-agent::make-provider-request-from-session "provider snapshot domains" session))
           (session-summary (sbcl-agent::provider-request-session-summary request))
           (runtime-summary (sbcl-agent::provider-request-runtime-summary request))
           (workspace-summary (sbcl-agent::provider-request-workspace-summary request)))
      (assert-equal 1
                    (getf session-summary :pending-action-count)
                    "provider session summary should prefer environment agent-state pending-action counts")
      (assert-equal 1
                    (getf session-summary :active-worker-count)
                    "provider session summary should prefer environment agent-state worker counts")
      (assert-equal 1
                    (getf session-summary :incident-count)
                    "provider session summary should prefer environment incident counts")
      (assert-equal 1
                    (getf runtime-summary :pending-action-count)
                    "provider runtime summary should prefer environment agent-state pending actions")
      (assert-equal 1
                    (getf runtime-summary :active-worker-count)
                    "provider runtime summary should prefer environment agent-state active workers")
      (assert-true (> (getf workspace-summary :artifact-count) 0)
                   "provider workspace summary should prefer environment artifact counts")
      (assert-true (> (getf (getf workspace-summary :artifact-summary) :validation-count) 0)
                   "provider workspace summary should preserve environment-native artifact evidence")
      (assert-equal 1
                    (getf workspace-summary :incident-count)
                    "provider workspace summary should prefer environment incident counts"))))

(defun provider-summary-does-not-require-session-resync-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-summary-owned-state/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-summary-owned-state/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let ((baseline-artifact-summary (getf (sbcl-agent::environment-summary environment) :artifact-summary)))
      (setf (sbcl-agent::agent-session-cwd session) "/tmp/provider-summary-mutated/"
            (sbcl-agent::agent-session-package session) "COMMON-LISP"
            (sbcl-agent::agent-session-current-thread-id session) "thread-mutated"
            (sbcl-agent::agent-session-plan session) "mutated plan")
      (let ((summary (sbcl-agent::provider-session-summary session)))
        (assert-equal "/tmp/provider-summary-owned-state/"
                      (getf summary :cwd)
                      "provider-session-summary should prefer environment-owned storage root over mutated session cwd")
        (assert-equal "SBCL-AGENT-USER"
                      (getf summary :package)
                      "provider-session-summary should prefer environment-owned runtime package over mutated session package")
        (assert-equal (sbcl-agent::environment-active-thread-id environment)
                      (getf summary :current-thread-id)
                      "provider-session-summary should prefer environment-owned active thread over mutated session state")
        (assert-equal nil
                      (getf summary :plan)
                      "provider-session-summary should prefer the environment-backed plan value")
        (assert-equal baseline-artifact-summary
                      (getf summary :artifact-summary)
                      "provider-session-summary should not call back into session-summary for artifact summary fallback")))))

(defun provider-context-defaults-prefer-environment-conversation-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-context-owned-conversation/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-context-owned-conversation/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((active-thread (sbcl-agent::current-thread session))
           (user-message (sbcl-agent::create-message session active-thread :user "environment-owned provider context"))
           (turn (sbcl-agent::start-turn session active-thread user-message))
           (assistant-message (sbcl-agent::create-message session active-thread :assistant "done")))
      (sbcl-agent::complete-turn session active-thread turn assistant-message :status :completed)
      (sbcl-agent::refresh-environment-conversation-domain environment session)
      (let ((second-thread (sbcl-agent::make-thread :id "thread-session-drift"
                                                    :title "Session drift thread"
                                                    :created-at (get-universal-time)
                                                    :updated-at (get-universal-time)
                                                    :summary "Only the session should see this drift thread."
                                                    :message-ids '()
                                                    :message-ids-tail nil
                                                    :turn-ids '()
                                                    :turn-ids-tail nil
                                                    :artifact-ids '()
                                                    :artifact-ids-tail nil
                                                    :status :active
                                                    :metadata '())))
        (setf (sbcl-agent::agent-session-threads session)
              (append (sbcl-agent::agent-session-threads session) (list second-thread))
              (sbcl-agent::agent-session-threads-tail session)
              (last (sbcl-agent::agent-session-threads session))
              (sbcl-agent::agent-session-current-thread-id session)
              (sbcl-agent::thread-id second-thread)))
      (let* ((request (sbcl-agent::make-provider-request-from-session "context drift" session))
             (thread-context (sbcl-agent::provider-request-thread-context request))
             (turn-context (sbcl-agent::provider-request-turn-context request)))
        (assert-equal (sbcl-agent::thread-id active-thread)
                      (getf thread-context :id)
                      "provider request thread context should prefer environment-owned active thread over drifted session state")
        (assert-equal (sbcl-agent::turn-id turn)
                      (getf turn-context :id)
                      "provider request turn context should prefer environment-owned active turn over drifted session state")
        (assert-equal (sbcl-agent::thread-id active-thread)
                      (getf turn-context :thread-id)
                      "provider request turn context should preserve the environment-owned active thread linkage")))))

(defun provider-policy-and-operator-summary-prefer-snapshot-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-policy-snapshot/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-policy-snapshot/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::grant-capability session :runtime-read)
    (let ((work-item (sbcl-agent::create-work-item session "Provider policy snapshot" :transaction-scope :test)))
      (sbcl-agent::quarantine-work-item session work-item "snapshot quarantine"))
    (sbcl-agent::refresh-bound-environment-agent-state session)
    (setf (sbcl-agent::agent-session-capability-grants session) '()
          (sbcl-agent::agent-session-capability-grants-tail session) nil
          (sbcl-agent::agent-session-incidents session) '()
          (sbcl-agent::agent-session-incidents-tail session) nil
          (sbcl-agent::agent-session-work-items session) '()
          (sbcl-agent::agent-session-work-items-tail session) nil)
    (let* ((request (sbcl-agent::make-provider-request-from-session "provider policy snapshot" session))
           (workspace-summary (sbcl-agent::provider-request-workspace-summary request))
           (policy-summary (sbcl-agent::provider-request-policy-summary request))
           (session-summary (sbcl-agent::provider-request-session-summary request)))
      (assert-true (member :runtime-read
                           (getf policy-summary :approved-policies))
                   "provider policy summary should prefer environment policy state over mutated session grants")
      (assert-true (find :runtime-read
                         (getf policy-summary :capability-grants)
                         :key (lambda (entry) (getf entry :policy-id))
                         :test #'eq)
                   "provider policy summary should preserve environment capability grant summaries")
      (assert-equal 1
                    (getf workspace-summary :quarantined-work-item-count)
                    "provider workspace summary should prefer environment operator posture over mutated session work-items")
      (assert-true (member :runtime-read
                           (getf session-summary :approved-policies))
                   "provider session summary should carry snapshot-backed approved policies"))))
