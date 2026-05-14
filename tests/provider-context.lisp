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

(defun provider-request-cached-conversation-context-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-cached-conversation/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-cached-conversation/"
                       :session session))
         (thread nil)
         (turn nil))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::append-transcript-entry session :user "We reviewed open incidents in the runtime earlier.")
    (sbcl-agent::append-transcript-entry session :assistant "The runtime was stable but there was pending governed work.")
    (setf thread (sbcl-agent::current-thread session)
          turn (sbcl-agent::start-turn
                session
                thread
                (sbcl-agent::create-message
                 session
                 thread
                 :user
                 "Before we continue, give me a conversational recap of what we were just discussing and remind me what you think the most relevant next topic is, without proposing any code changes or tool actions yet.")
                :metadata '(:source :test)))
    (let* ((request (sbcl-agent::make-provider-request-from-session
                     "Before we continue, give me a conversational recap of what we were just discussing and remind me what you think the most relevant next topic is, without proposing any code changes or tool actions yet."
                     session
                     :thread thread
                     :turn turn
                     :operator-mode :conversation
                     :stream-p t))
           (dossier (sbcl-agent::provider-request-retrieval-dossier request))
           (conversation-context (getf dossier :conversation-context)))
      (assert-equal :cached-conversation
                    (getf dossier :phase)
                    "conversation requests should use the cached conversational retrieval phase")
      (assert-equal :cached-search
                    (getf (getf dossier :plan) :expansion-posture)
                    "conversation requests should use cached-search expansion posture")
      (assert-true (null (sbcl-agent::provider-request-cognition-bundle request))
                   "cached conversational requests should skip cognition bundle construction")
      (assert-true (null (sbcl-agent::provider-request-reasoning-brief request))
                   "cached conversational requests should skip reasoning brief construction")
      (assert-true (null (sbcl-agent::provider-request-planning-brief request))
                   "cached conversational requests should skip planning brief construction")
      (assert-true (listp (getf dossier :ranking))
                   "cached conversational requests should expose ranked cached-context hits")
      (assert-true (> (length (getf dossier :ranking)) 0)
                   "cached conversational requests should rank at least one warm-context hit")
      (assert-true (listp (getf conversation-context :recent-transcript))
                   "cached conversational requests should preserve recent transcript context"))))

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

(defun provider-rendering-cached-conversation-prompt-test ()
  (let* ((request (sbcl-agent::make-provider-request
                   :prompt "Before we continue, remind me what we were discussing."
                   :session-summary '(:recent-transcript ((:role :user :content "Earlier we discussed runtime posture.")
                                                         (:role :assistant :content "There was pending governed work.")))
                   :thread-context '(:id "thread-1" :title "Default Thread" :summary "Runtime review")
                   :turn-context '(:id "turn-1" :status :running)
                   :runtime-summary '(:cwd "/tmp/project" :package "SBCL-AGENT-USER" :open-incident-count 1)
                   :workspace-summary '(:cwd "/tmp/project" :artifact-count 2 :incident-count 1 :work-item-count 1)
                   :policy-summary '(:approved-policies (:safe-read) :open-incident-count 1)
                   :retrieval-dossier '(:phase :cached-conversation
                                       :intent (:category :general :domains (:conversation :runtime))
                                       :plan (:expansion-posture :cached-search)
                                       :ranking ((:label "Recent Transcript" :domain "conversation" :score 5)
                                                 (:label "Runtime Summary" :domain "runtime" :score 3)))
                   :operator-mode :conversation
                   :stream-p t))
         (prompt (sbcl-agent::build-openai-user-prompt request))
         (request-body (sbcl-agent::build-openai-request-body
                        (make-instance 'sbcl-agent::openai-compatible-provider
                                       :provider-id "openai-compatible"
                                       :model "gpt-5"
                                       :fast-model "gpt-5-mini"
                                       :api-base "http://localhost"
                                       :api-key "test")
                        request
                        :stream t
                        :stream-protocol t)))
    (assert-true (search "Cached context hits:" prompt)
                 "cached conversation prompt should render cached context hits")
    (assert-true (search "Recent transcript:" prompt)
                 "cached conversation prompt should render recent transcript")
    (assert-true (null (search "Canonical cognition bundle:" prompt))
                 "cached conversation prompt should omit the full cognition bundle section")
    (assert-true (null (search "Planning brief:" prompt))
                 "cached conversation prompt should omit the full planning brief section")
    (assert-true (search "Respond naturally, use the cached warm context as background memory" prompt)
                 "cached conversation prompt should describe the compact cached-context posture")
    (assert-true (search "Stream the operator-facing answer as plain text immediately." request-body)
                 "cached conversation requests should use the lightweight streaming system prompt")
    (assert-true (search "\"model\":\"gpt-5-mini\"" request-body)
                 "cached conversation requests should prefer the fast model path even when the prompt sounds analytical")))

(defun provider-rendering-cached-conversation-with-surface-actions-test ()
  (let* ((request (sbcl-agent::make-provider-request
                   :prompt "Summarize what we were just discussing."
                   :session-summary '(:recent-transcript ((:role :user :content "Earlier we discussed runtime posture.")
                                                         (:role :assistant :content "There was pending governed work.")))
                   :thread-context '(:id "thread-1" :title "Default Thread" :summary "Runtime review")
                   :turn-context '(:id "turn-1" :status :running)
                   :surface-context '(:workspace "notifications" :focused-panel "context-chat")
                   :surface-actions '((:tool-id ":desktop/show" :label "Open surface")
                                      (:tool-id "calculator/append-token" :label "Append calculator token"))
                   :runtime-summary '(:cwd "/tmp/project" :package "SBCL-AGENT-USER" :open-incident-count 1)
                   :workspace-summary '(:cwd "/tmp/project" :artifact-count 2 :incident-count 1 :work-item-count 1)
                   :policy-summary '(:approved-policies (:safe-read) :open-incident-count 1)
                   :retrieval-dossier '(:phase :cached-conversation
                                       :intent (:category :general :domains (:conversation :runtime))
                                       :plan (:expansion-posture :cached-search)
                                       :ranking ((:label "Recent Transcript" :domain "conversation" :score 5)
                                                 (:label "Runtime Summary" :domain "runtime" :score 3)))
                   :operator-mode :conversation
                   :stream-p t))
         (prompt (sbcl-agent::build-openai-user-prompt request))
         (request-body (sbcl-agent::build-openai-request-body
                        (make-instance 'sbcl-agent::openai-compatible-provider
                                       :provider-id "openai-compatible"
                                       :model "gpt-5"
                                       :fast-model "gpt-5-mini"
                                       :api-base "http://localhost"
                                       :api-key "test")
                        request
                        :stream t
                        :stream-protocol t)))
    (assert-true (search "Available Surface actions:" prompt)
                 "cached conversation prompts should retain compact surface action guidance")
    (assert-true (search "\"model\":\"gpt-5-mini\"" request-body)
                 "surface-aware cached conversation requests should stay on the fast model path")
    (assert-true (null (search "Canonical cognition bundle:" prompt))
                 "surface-aware cached conversation prompts should still avoid the full cognition bundle")))

(defun provider-rendering-lightweight-conversation-transcript-test ()
  (let* ((request (sbcl-agent::make-provider-request
                   :prompt "yes the full text"
                   :session-summary '(:recent-transcript ((:role :user :content "tell me the gettysburg address")
                                                         (:role :assistant :content "Would you like me to provide the full text?")))
                   :thread-context '(:id "thread-1" :title "Default Thread" :summary "Gettysburg Address request")
                   :turn-context '(:id "turn-2" :status :running)
                   :runtime-summary '(:cwd "/tmp/project" :package "SBCL-AGENT-USER" :open-incident-count 0)
                   :operator-mode :conversation
                   :stream-p t))
         (prompt (sbcl-agent::build-openai-user-prompt request)))
    (assert-true (search "Recent transcript:" prompt)
                 "lightweight conversation prompts should retain recent transcript context")
    (assert-true (search "Would you like me to provide the full text?" prompt)
                 "lightweight conversation prompts should preserve the prior assistant turn for follow-up resolution")
    (assert-true (search "Resolve short follow-up replies against the recent transcript when possible." prompt)
                 "lightweight conversation prompts should instruct the provider to resolve short follow-ups from transcript context")))

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

(defun provider-request-snapshot-precomputes-cached-context-entries-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot-cache/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot-cache/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-work-item session "Warm cached context" :transaction-scope :test)
    (let* ((snapshot (sbcl-agent::build-prompt-independent-provider-request-snapshot
                      session
                      :surface-context '(:active-workspace "conversations")))
           (entries (sbcl-agent::provider-request-snapshot-cached-context-entries snapshot))
           (index (sbcl-agent::provider-request-snapshot-cached-context-index snapshot))
           (dossier (sbcl-agent::build-cached-conversation-retrieval-dossier
                     "What were we discussing about runtime posture?"
                     snapshot
                     :operator-mode :conversation)))
      (assert-true (consp entries)
                   "prompt-independent provider request snapshots should precompute cached context entries")
      (assert-true (hash-table-p index)
                   "prompt-independent provider request snapshots should precompute a cached context token index")
      (assert-true (> (hash-table-count index) 0)
                   "cached context token index should contain searchable postings")
      (assert-true (find "Recent Transcript"
                         (mapcar (lambda (entry) (getf entry :label)) entries)
                         :test #'string=)
                   "precomputed cached context entries should include transcript coverage")
      (assert-true (consp (gethash "runtime" index))
                   "cached context token index should expose runtime postings directly")
      (assert-true (every (lambda (entry)
                            (listp (getf entry :text-tokens)))
                          entries)
                   "precomputed cached context entries should carry tokenized search fields")
      (assert-equal :cached-conversation
                    (getf dossier :phase)
                    "cached conversation dossier should preserve the cached-conversation phase")
      (assert-true (consp (getf dossier :ranking))
                   "cached conversation dossier should rank warm snapshot entries"))))

(defun provider-request-snapshot-freshness-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot-freshness/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot-freshness/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((snapshot (sbcl-agent::build-prompt-independent-provider-request-snapshot session))
           (generated-at (sbcl-agent::provider-request-snapshot-generated-at snapshot))
           (fresh-clone (sbcl-agent::clone-provider-request-snapshot snapshot))
           (old-snapshot (sbcl-agent::provider-request-snapshot-with-overrides snapshot)))
      (setf (sbcl-agent::provider-request-snapshot-generated-at old-snapshot)
            (- generated-at (+ sbcl-agent::+provider-request-snapshot-stale-seconds+ 5)))
      (assert-true (integerp generated-at)
                   "prompt-independent provider request snapshots should record a generation timestamp")
      (assert-equal generated-at
                    (sbcl-agent::provider-request-snapshot-generated-at fresh-clone)
                    "cloned provider request snapshots should preserve generation timestamps")
      (assert-true (not (sbcl-agent::provider-request-snapshot-stale-p snapshot
                                                                       :now generated-at))
                   "fresh provider request snapshots should not be marked stale at generation time")
      (assert-true (sbcl-agent::provider-request-snapshot-stale-p old-snapshot
                                                                  :now generated-at)
                   "older provider request snapshots should be marked stale beyond the configured max age"))))

(defun provider-request-snapshot-domain-freshness-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot-domain-freshness/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot-domain-freshness/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((snapshot (sbcl-agent::build-prompt-independent-provider-request-snapshot session))
           (generated-at (sbcl-agent::provider-request-snapshot-generated-at snapshot))
           (domain-map (copy-tree (sbcl-agent::provider-request-snapshot-domain-generated-at snapshot))))
      (setf (getf domain-map :conversation)
            (- generated-at (+ sbcl-agent::+provider-request-snapshot-stale-seconds+ 5))
            (getf domain-map :runtime)
            generated-at
            (sbcl-agent::provider-request-snapshot-generated-at snapshot)
            (- generated-at (+ sbcl-agent::+provider-request-snapshot-stale-seconds+ 5))
            (sbcl-agent::provider-request-snapshot-domain-generated-at snapshot)
            domain-map)
      (assert-true (sbcl-agent::provider-request-snapshot-domain-stale-p
                    snapshot
                    :conversation
                    :now generated-at)
                   "conversation domain freshness should be evaluated independently")
      (assert-true (not (sbcl-agent::provider-request-snapshot-domain-stale-p
                         snapshot
                         :runtime
                         :now generated-at))
                   "runtime domain freshness should remain valid when its slice is current")
      (assert-true (sbcl-agent::provider-request-snapshot-needs-refresh-p
                    session
                    snapshot
                    :relevant-domains '(:conversation)
                    :now generated-at)
                   "conversation-only requests should refresh when the conversation slice is stale")
      (assert-true (not (sbcl-agent::provider-request-snapshot-needs-refresh-p
                         session
                         snapshot
                         :relevant-domains '(:runtime)
                         :now generated-at))
                   "runtime-only requests should keep using a fresh runtime slice even when the whole snapshot is older"))))

(defun provider-request-snapshot-partial-refresh-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot-partial-refresh/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot-partial-refresh/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((snapshot (sbcl-agent::refresh-provider-request-snapshot-cache session))
           (conversation-generated-at
             (sbcl-agent::provider-request-snapshot-domain-generated-at-value
              snapshot
              :conversation))
           (runtime-generated-at
             (sbcl-agent::provider-request-snapshot-domain-generated-at-value
              snapshot
              :runtime)))
      (sleep 1)
      (let ((refreshed (sbcl-agent::refresh-provider-request-snapshot-cache
                        session
                        :domains '(:runtime))))
        (assert-equal conversation-generated-at
                      (sbcl-agent::provider-request-snapshot-domain-generated-at-value
                       refreshed
                       :conversation)
                      "runtime-only refresh should preserve the conversation slice generation time")
        (assert-true (> (sbcl-agent::provider-request-snapshot-domain-generated-at-value
                         refreshed
                         :runtime)
                        runtime-generated-at)
                     "runtime-only refresh should advance the runtime slice generation time")))))

(defun provider-request-snapshot-partial-entry-refresh-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot-partial-entry-refresh/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot-partial-entry-refresh/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((snapshot (sbcl-agent::refresh-provider-request-snapshot-cache session))
           (entries (sbcl-agent::provider-request-snapshot-cached-context-entries snapshot))
           (conversation-entries
             (remove-if-not (lambda (entry)
                              (string= (getf entry :domain) "conversation"))
                            entries))
           (runtime-entry
             (find "Runtime Summary"
                   entries
                   :test #'string=
                   :key (lambda (entry) (getf entry :label)))))
      (sleep 1)
      (let* ((refreshed (sbcl-agent::refresh-provider-request-snapshot-cache
                         session
                         :domains '(:runtime)))
             (refreshed-entries
               (sbcl-agent::provider-request-snapshot-cached-context-entries refreshed))
             (refreshed-conversation-entries
               (remove-if-not (lambda (entry)
                                (string= (getf entry :domain) "conversation"))
                              refreshed-entries))
             (refreshed-runtime-entry
               (find "Runtime Summary"
                     refreshed-entries
                     :test #'string=
                     :key (lambda (entry) (getf entry :label)))))
        (assert-equal conversation-entries
                      refreshed-conversation-entries
                      "runtime-only refresh should preserve conversation cached-context entries")
        (assert-true refreshed-runtime-entry
                     "runtime-only refresh should retain a runtime cached-context entry")
        (assert-equal (getf runtime-entry :summary)
                      (getf refreshed-runtime-entry :summary)
                      "runtime-only refresh may preserve deterministic runtime summary content")
        (assert-equal (length entries)
                      (length refreshed-entries)
                      "runtime-only refresh should preserve total cached-context entry count")))))

(defun provider-request-snapshot-partial-index-refresh-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot-partial-index-refresh/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot-partial-index-refresh/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((snapshot (sbcl-agent::refresh-provider-request-snapshot-cache session))
           (index (sbcl-agent::provider-request-snapshot-cached-context-index snapshot))
           (recent-postings (copy-tree (gethash "recent" index)))
           (runtime-postings (copy-tree (gethash "runtime" index))))
      (sleep 1)
      (let* ((refreshed (sbcl-agent::refresh-provider-request-snapshot-cache
                         session
                         :domains '(:runtime)))
             (refreshed-index
               (sbcl-agent::provider-request-snapshot-cached-context-index refreshed)))
        (assert-true (hash-table-p refreshed-index)
                     "runtime-only refresh should preserve a cached context postings index")
        (assert-equal recent-postings
                      (gethash "recent" refreshed-index)
                      "runtime-only refresh should preserve unrelated conversation token postings")
        (assert-true (consp (gethash "runtime" refreshed-index))
                     "runtime-only refresh should preserve runtime token postings")
        (assert-true (find "runtime"
                           (gethash "runtime" refreshed-index)
                           :test #'string=
                           :key (lambda (posting)
                                  (getf (car posting) :domain)))
                     "runtime-only refresh should retain runtime-domain postings in the runtime token bucket")))))

(defun provider-request-snapshot-environment-notify-refresh-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot-environment-notify/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot-environment-notify/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((snapshot (sbcl-agent::refresh-provider-request-snapshot-cache session))
           (conversation-generated-at
             (sbcl-agent::provider-request-snapshot-domain-generated-at-value
              snapshot
              :conversation))
           (policy-generated-at
             (sbcl-agent::provider-request-snapshot-domain-generated-at-value
              snapshot
              :policy)))
      (sleep 1)
      (assert-equal '(:policy :environment)
                    (sbcl-agent::notify-provider-request-snapshot-environment-change
                     environment
                     :reason :provider-routing
                     :family :environment
                     :domains '(:policy :environment))
                    "environment-triggered warming should normalize and return the requested refresh domains")
      (sleep 1)
      (let ((refreshed (sbcl-agent::cached-provider-request-snapshot session)))
        (assert-true refreshed
                     "environment-triggered warming should keep a cached provider request snapshot available")
        (assert-equal conversation-generated-at
                      (sbcl-agent::provider-request-snapshot-domain-generated-at-value
                       refreshed
                       :conversation)
                      "environment-triggered warming should not advance unrelated conversation freshness")
        (assert-true (> (sbcl-agent::provider-request-snapshot-domain-generated-at-value
                         refreshed
                         :policy)
                        policy-generated-at)
                     "environment-triggered warming should advance the selected policy freshness domain")))))

(defun provider-request-snapshot-dirty-invalidation-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot-dirty/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot-dirty/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let ((snapshot (sbcl-agent::refresh-provider-request-snapshot-cache session)))
      (assert-true (not (sbcl-agent::provider-request-snapshot-needs-refresh-p session snapshot))
                   "freshly refreshed provider request snapshots should not immediately need refresh")
      (sbcl-agent::mark-provider-request-snapshot-dirty session :reason :command)
      (assert-true (sbcl-agent::provider-request-snapshot-needs-refresh-p session snapshot)
                   "explicit snapshot invalidation should mark provider request snapshots dirty until refresh catches up"))))

(defun provider-request-snapshot-relevant-domain-normalization-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot-domain-normalization/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot-domain-normalization/"
                       :session session))
         (prompt "What approvals or blocked workflow items need attention?"))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((snapshot (sbcl-agent::refresh-provider-request-snapshot-cache session))
           (relevant-domains
             (sbcl-agent::provider-request-relevant-dirty-domains prompt
                                                                  :conversation
                                                                  nil
                                                                  nil)))
      (assert-true (equal '(:workspace) relevant-domains)
                   "workflow-heavy conversation prompts should normalize to workspace snapshot dirtiness")
      (sbcl-agent::mark-provider-request-snapshot-dirty session :reason :pending-actions)
      (assert-true (sbcl-agent::provider-request-snapshot-needs-refresh-p
                    session
                    snapshot
                    :relevant-domains relevant-domains)
                   "normalized workflow domains should observe matching workspace dirtiness")
      (assert-true (not (sbcl-agent::provider-request-snapshot-needs-refresh-p
                         session
                         snapshot
                         :relevant-domains '(:conversation)))
                   "conversation-only refresh checks should ignore unrelated workspace dirtiness"))))

(defun provider-request-snapshot-event-family-dirty-domains-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-request-snapshot-event-family/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-request-snapshot-event-family/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let ((snapshot (sbcl-agent::refresh-provider-request-snapshot-cache session)))
      (assert-true (equal '(:workspace)
                          (sbcl-agent::provider-request-snapshot-dirty-domains-for-event
                           :reason :patch))
                   "patch events should dirty workspace context without broadening to unrelated domains")
      (sbcl-agent::append-session-event session :environment-test '(:ok t) :family :runtime)
      (assert-true (sbcl-agent::provider-request-snapshot-needs-refresh-p
                    session
                    snapshot
                    :relevant-domains '(:runtime))
                   "runtime-family events should invalidate runtime-relevant warm snapshots")
      (assert-true (not (sbcl-agent::provider-request-snapshot-needs-refresh-p
                         session
                         snapshot
                         :relevant-domains '(:conversation)))
                   "runtime-family events should not force refresh for conversation-only context"))))

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

(defun desktop-task-events-for-record (session record-id)
  (remove-if-not (lambda (event)
                   (and (stringp (sbcl-agent::event-entity-id event))
                        (string= record-id
                                 (sbcl-agent::event-entity-id event))))
                 (sbcl-agent::agent-session-events session)))

(defun desktop-task-event-of-kind-p (event kind)
  (eq (sbcl-agent::event-kind event) kind))

(defun desktop-task-transition-event-p (event transition)
  (and (desktop-task-event-of-kind-p event :desktop-task-record-transition)
       (eq (getf (sbcl-agent::event-payload event) :transition)
           transition)))

(defun desktop-task-event-position (events predicate)
  (position-if predicate events))

(defun assert-governed-desktop-task-audit-flow (session prompt requests policy-id)
  (let* ((response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    prompt
                    requests))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (pre-approval-events (desktop-task-events-for-record
                               session
                               (sbcl-agent::desktop-task-record-id record))))
    (declare (ignore response))
    (assert-true record
                 "governed desktop task execution should create a durable task record")
    (assert-equal :awaiting-approval
                  (sbcl-agent::desktop-task-record-status record)
                  "explicit governed desktop task requests should stop in awaiting-approval")
    (assert-equal :awaiting-approval
                  (sbcl-agent::desktop-task-record-approval-status record)
                  "explicit governed desktop task requests should persist awaiting approval posture")
    (assert-true (find-if (lambda (event)
                            (desktop-task-transition-event-p event :awaiting-approval))
                          pre-approval-events)
                 "governed desktop task requests should emit an awaiting-approval transition event before execution")
    (assert-true (null (find-if (lambda (event)
                                  (desktop-task-event-of-kind-p event :desktop-task-invocation))
                                pre-approval-events))
                 "governed desktop task requests should not invoke before approval is granted")
    (assert-true (null (find-if (lambda (event)
                                  (desktop-task-event-of-kind-p event :desktop-task-invocation-result))
                                pre-approval-events))
                 "governed desktop task requests should not emit invocation results before approval is granted")
    (let* ((approval-response
             (sbcl-agent::command-conversation-execution-service session nil "yes" '()))
           (approval-data (sbcl-agent::service-response-data approval-response))
           (approval-task-results (getf approval-data :desktop-task-results))
           (approval-response-message
             (sbcl-agent::assistant-response-message (getf approval-data :response)))
           (post-approval-events (desktop-task-events-for-record
                                  session
                                  (sbcl-agent::desktop-task-record-id record)))
           (policy-events (remove-if-not (lambda (event)
                                           (eq (sbcl-agent::event-kind event)
                                               :capability-granted))
                                         (sbcl-agent::agent-session-events session))))
      (assert-equal :completed
                    (sbcl-agent::desktop-task-record-status record)
                    "approved governed desktop task requests should complete through the shared invocation seam")
      (let* ((detail-response
               (sbcl-agent::query-desktop-task-record-detail-service
                session
                (sbcl-agent::desktop-task-record-id record)))
             (detail (sbcl-agent::service-response-data detail-response))
             (audit (getf detail :audit))
             (recent-events (getf audit :recent-events)))
        (assert-true (listp audit)
                     "desktop task record detail should expose an audit summary")
        (assert-true (>= (getf audit :event-count) 4)
                     "desktop task record detail should expose the governed audit trail")
        (assert-true (member :awaiting-approval
                             (getf audit :transition-kinds)
                             :test #'eq)
                     "desktop task record detail should expose awaiting-approval as a recorded transition")
        (assert-true (member :approved
                             (getf audit :transition-kinds)
                             :test #'eq)
                     "desktop task record detail should expose approved as a recorded transition")
        (assert-true (member :completed
                             (getf audit :transition-kinds)
                             :test #'eq)
                     "desktop task record detail should expose completed as a recorded transition")
        (assert-true (getf audit :invoked-p)
                     "desktop task record detail should report governed invocation")
        (assert-true (getf audit :completed-p)
                     "desktop task record detail should report completed invocation")
        (assert-true (find :desktop-task-invocation
                           recent-events
                           :key (lambda (event)
                                  (getf event :kind))
                           :test #'eq)
                     "desktop task record detail should include invocation events in recent audit history"))
      (assert-true (not (null (sbcl-agent::desktop-task-record-approved-at record)))
                   "approved governed desktop task requests should record approval time")
      (assert-true (not (null (sbcl-agent::desktop-task-record-started-at record)))
                   "approved governed desktop task requests should record execution start time")
      (assert-true (not (null (sbcl-agent::desktop-task-record-completed-at record)))
                   "approved governed desktop task requests should record completion time")
      (assert-equal (sbcl-agent::desktop-task-record-request-id record)
                    (getf (sbcl-agent::desktop-task-record-result record) :request-id)
                    "completed governed desktop task records should preserve the canonical request id in result payload")
      (assert-equal (sbcl-agent::desktop-task-record-target record)
                    (getf (sbcl-agent::desktop-task-record-result record) :target)
                    "completed governed desktop task records should preserve the canonical target in result payload")
      (assert-equal (sbcl-agent::desktop-task-record-operation record)
                    (getf (sbcl-agent::desktop-task-record-result record) :operation)
                    "completed governed desktop task records should preserve the canonical operation in result payload")
      (assert-equal :completed
                    (getf (sbcl-agent::desktop-task-record-result record) :status)
                    "completed governed desktop task records should store a canonical completed status in result payload")
      (assert-true (listp (getf (sbcl-agent::desktop-task-record-result record) :invocation-result))
                   "completed governed desktop task records should retain the normalized invocation result payload")
      (assert-equal 1
                    (length approval-task-results)
                    "approval confirmation responses should publish exactly one canonical desktop task result")
      (assert-equal (sbcl-agent::desktop-task-record-id record)
                    (getf (first approval-task-results) :task-record-id)
                    "approval confirmation responses should publish the resumed task record id")
      (assert-equal :completed
                    (getf (first approval-task-results) :status)
                    "approval confirmation responses should publish canonical completed task status")
      (assert-equal (sbcl-agent::desktop-task-record-result-summary-text record)
                    approval-response-message
                    "approval confirmation responses should derive assistant content from the updated governed task record")
      (assert-true (find-if (lambda (event)
                              (desktop-task-transition-event-p event :approved))
                            post-approval-events)
                   "approval should emit a durable task-record approved transition")
      (assert-true (find-if (lambda (event)
                              (desktop-task-transition-event-p event :executing))
                            post-approval-events)
                   "approved governed desktop task requests should emit an executing transition")
      (assert-true (find-if (lambda (event)
                              (desktop-task-transition-event-p event :completed))
                            post-approval-events)
                   "approved governed desktop task requests should emit a completed transition")
      (assert-true (find-if (lambda (event)
                              (desktop-task-event-of-kind-p event
                                                            :desktop-task-governance-check))
                            post-approval-events)
                   "approved governed desktop task requests should emit a governance-check audit event")
      (assert-true (find-if (lambda (event)
                              (desktop-task-event-of-kind-p event
                                                            :desktop-task-invocation))
                            post-approval-events)
                   "approved governed desktop task requests should emit an invocation audit event")
      (assert-true (find-if (lambda (event)
                              (desktop-task-event-of-kind-p event
                                                            :desktop-task-invocation-result))
                            post-approval-events)
                   "approved governed desktop task requests should emit an invocation-result audit event")
      (assert-true (find policy-id
                         policy-events
                         :key (lambda (event)
                                (getf (sbcl-agent::event-payload event) :policy-id))
                         :test #'eq)
                   "governed desktop task approval should still be recorded through the normal capability-granted event")
      (let ((granted-position
              (desktop-task-event-position
               (sbcl-agent::agent-session-events session)
               (lambda (event)
                 (and (eq (sbcl-agent::event-kind event) :capability-granted)
                      (eq (getf (sbcl-agent::event-payload event) :policy-id)
                          policy-id)))))
            (governance-position
              (desktop-task-event-position
               post-approval-events
               (lambda (event)
                 (desktop-task-event-of-kind-p event :desktop-task-governance-check))))
            (invocation-position
              (desktop-task-event-position
               post-approval-events
               (lambda (event)
                 (desktop-task-event-of-kind-p event :desktop-task-invocation)))))
        (assert-true (and granted-position governance-position invocation-position)
                     "governed desktop task approval flow should expose ordered audit events")
        (assert-true (< granted-position
                        (+ invocation-position
                           (- (length (sbcl-agent::agent-session-events session))
                              (length post-approval-events))))
                     "capability grants should be recorded before governed task invocation occurs")
        (assert-true (< governance-position invocation-position)
                     "governed task invocation should be preceded by governance-check audit")))))

(defun governed-desktop-task-internal-governance-audit-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :test
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)"))))
    (assert-governed-desktop-task-audit-flow
     session
     "append (+ 1 1) to the editor"
     (list request)
     :workspace-write)))

(defun governed-desktop-task-mcp-governance-audit-test ()
  (let* ((session (make-test-session))
         (environment (sbcl-agent::session-bound-environment session))
         (server (sbcl-agent::register-desktop-task-mcp-server-config
                  :environment environment
                  :name "Governance Probe MCP"
                  :transport :stdio
                  :command "cat"
                  :arguments '()
                  :retry-policy '(:max-attempts 1 :retryable-p nil)))
         (target (intern (format nil "MCP-GOVERNANCE-PROBE-~D" (random 1000000))
                         "KEYWORD"))
         (operation :echo)
         (request nil))
    (sbcl-agent::register-mcp-desktop-task-operation
     target
     operation
     (sbcl-agent::mcp-server-config-id server)
     :capability :workspace-write
     :description "Governed MCP probe operation."
     :request-schema '(:text string)
     :result-schema '(:summary string)
     :approval-policy :explicit
     :execution-mode :synchronous
     :retry-policy '(:max-attempts 1 :retryable-p nil)
     :tags '(:test :mcp))
    (setf request
          (sbcl-agent::make-governed-desktop-task-request
           :requester :test
           :target target
           :operation operation
           :capability :workspace-write
           :payload '(:text "hello from governed mcp")))
    (assert-governed-desktop-task-audit-flow
     session
     "send hello through governed mcp"
     (list request)
     :workspace-write)))

(defun governed-desktop-task-actor-approve-message-test ()
  (let* ((session (make-test-session))
         (provider (make-test-provider))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (actor-message-id (and record
                                (sbcl-agent::actor-message-id
                                 (sbcl-agent::desktop-task-record-actor-message record))))
         (pending (sbcl-agent::service-response-data
                   (sbcl-agent::query-desktop-task-pending-approval-service session))))
    (declare (ignore response))
    (assert-true record
                 "actor-native governed desktop task flow should create a durable task record")
    (assert-true (stringp actor-message-id)
                 "actor-native governed desktop task flow should stamp an actor message id")
    (assert-true (member actor-message-id
                         (getf pending :actor-message-ids)
                         :test #'string=)
                 "pending approval query should expose the awaiting actor message id")
    (let* ((approve-response
             (sbcl-agent::command-desktop-task-approve-actor-message-service
              session
              provider
              actor-message-id))
           (approve-data (sbcl-agent::service-response-data approve-response))
           (replies (getf approve-data :replies))
           (latest-reply
             (sbcl-agent::service-response-data
              (sbcl-agent::query-desktop-task-actor-replies-service
               session
               :context-chat
               :latest-only-p t))))
      (assert-equal :completed
                    (sbcl-agent::desktop-task-record-status record)
                    "approving an actor message should complete the governed desktop task record")
      (assert-equal actor-message-id
                    (getf approve-data :actor-message-id)
                    "actor approval command should echo the resumed actor message id")
      (assert-equal 1
                    (length replies)
                    "actor approval command should publish exactly one actor reply for the editor slice")
      (assert-equal :completed
                    (getf (first replies) :status)
                    "actor approval command should publish a completed actor reply")
      (assert-equal actor-message-id
                    (getf (first latest-reply) :actor-message-id)
                    "latest actor reply query should expose the approved actor message")
      (assert-equal :completed
                    (getf (first latest-reply) :status)
                    "latest actor reply query should show the completed result")
      (assert-equal "Appended text to the active editor buffer."
                    (getf (first latest-reply) :summary)
                    "latest actor reply query should expose the canonical receiver summary"))))

(defun governed-desktop-task-governance-approve-approval-id-test ()
  (let* ((session (make-test-session))
         (provider (make-test-provider))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (governance-before
           (sbcl-agent::service-response-data
            (sbcl-agent::query-desktop-task-governance-state-service
             session
             :session-id session-id
             :approval-id approval-id
             :latest-only-p t))))
    (declare (ignore response))
    (assert-true record
                 "governance approval flow should create a durable governed desktop task record")
    (assert-true (stringp approval-id)
                 "governance approval flow should stamp an approval id")
    (assert-true (stringp session-id)
                 "governance approval flow should stamp a session id")
    (assert-equal approval-id
                  (getf governance-before :approval-id)
                  "governance state query should resolve the awaiting approval by approval id")
    (assert-equal 1
                  (getf governance-before :count)
                  "governance state query should expose one awaiting approval request")
    (assert-equal :awaiting-approval
                  (getf (first (getf governance-before :requests)) :approval-status)
                  "governance state should report awaiting approval before confirmation")
    (let* ((approve-response
             (sbcl-agent::command-desktop-task-approve-approval-service
              session
              provider
              approval-id
              :session-id session-id))
           (approve-data (sbcl-agent::service-response-data approve-response))
           (governance-after
             (sbcl-agent::service-response-data
              (sbcl-agent::query-desktop-task-governance-state-service
               session
               :session-id session-id
               :approval-id approval-id
               :latest-only-p t))))
      (assert-equal :completed
                    (sbcl-agent::desktop-task-record-status record)
                    "approving by approval id should complete the governed desktop task record")
      (assert-true (member approval-id
                           (getf approve-data :approval-ids)
                           :test #'string=)
                   "approve approval response should include the approved approval id")
      (assert-equal :approved
                    (getf (first (getf governance-after :requests)) :approval-status)
                    "governance state should report approved after confirmation")
      (assert-equal :completed
                    (getf (first (getf governance-after :requests)) :status)
                    "governance state should report completed after the authorized mutation runs"))))

(defun governed-desktop-task-approval-survives-environment-save-load-test ()
  (let* ((dir (namestring (make-temporary-directory "/tmp/sbcl-agent-approval-persist-XXXXXX/")))
         (path (merge-pathnames "environment.sexp" dir))
         (session (make-test-session :cwd dir))
         (provider (make-test-provider))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor surface."
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record)))
         (pending-action-id (and record
                                 (sbcl-agent::desktop-task-record-pending-action-id record)))
         (actor-message-id (and record
                                (sbcl-agent::actor-message-id
                                 (sbcl-agent::desktop-task-record-actor-message record)))))
    (declare (ignore response))
    (assert-equal session-id
                  (sbcl-agent::actor-message-session-id
                   (sbcl-agent::desktop-task-record-actor-message record))
                  "initial actor message should carry the session id before persistence")
    (assert-equal approval-id
                  (sbcl-agent::actor-message-approval-id
                   (sbcl-agent::desktop-task-record-actor-message record))
                  "initial actor message should carry the approval id before persistence")
    (sbcl-agent::save-environment (sbcl-agent::ensure-environment) path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment))
           (_bound (sbcl-agent::bind-session-to-environment loaded-session loaded-environment))
           (pending (sbcl-agent::service-response-data
                     (sbcl-agent::query-desktop-task-pending-approval-service loaded-session)))
           (flow (sbcl-agent::service-response-data
                  (sbcl-agent::query-desktop-task-actor-flow-service
                   loaded-session
                   :session-id session-id
                   :approval-id approval-id
                   :pending-action-id pending-action-id
                   :actor-message-id actor-message-id
                   :latest-only-p t)))
           (approval-response
             (sbcl-agent::command-conversation-execution-service loaded-session provider "yes" '()))
           (approval-data (sbcl-agent::service-response-data approval-response))
           (updated-record
             (sbcl-agent::find-desktop-task-record-by-actor-message-id
              loaded-session
              actor-message-id)))
      (declare (ignore _bound))
      (assert-true (member approval-id
                           (getf pending :approval-ids)
                           :test #'string=)
                   "pending approval should survive environment save/load")
      (assert-equal approval-id
                    (getf flow :approval-id)
                    "actor flow should preserve approval id across environment save/load")
      (assert-equal actor-message-id
                    (getf flow :actor-message-id)
                    "actor flow should preserve actor message id across environment save/load")
      (assert-true updated-record
                   "reloaded session should retain the governed desktop task record")
      (assert-equal :completed
                    (sbcl-agent::desktop-task-record-status updated-record)
                    "approval after environment reload should complete the governed desktop task")
      (assert-equal "Appended text to the active editor buffer."
                    (getf approval-data :summary)
                    "approval after environment reload should apply the editor mutation"))))

(defun governed-desktop-task-actor-flow-query-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record)))
         (pending-action-id (and record
                                 (sbcl-agent::desktop-task-record-pending-action-id record)))
         (actor-message-id (and record
                                (sbcl-agent::actor-message-id
                                 (sbcl-agent::desktop-task-record-actor-message record))))
         (flow (sbcl-agent::service-response-data
                (sbcl-agent::query-desktop-task-actor-flow-service
                 session
                 :session-id session-id
                 :approval-id approval-id
                 :pending-action-id pending-action-id
                 :actor-message-id actor-message-id
                 :latest-only-p t))))
    (declare (ignore response))
    (assert-true record
                 "actor flow query test should create a governed desktop task record")
    (assert-equal session-id
                  (getf flow :session-id)
                  "actor flow query should preserve the session id")
    (assert-equal approval-id
                  (getf flow :approval-id)
                  "actor flow query should preserve the approval id")
    (assert-equal pending-action-id
                  (getf flow :pending-action-id)
                  "actor flow query should preserve the pending action id")
    (assert-equal actor-message-id
                  (getf flow :actor-message-id)
                  "actor flow query should preserve the actor message id")
    (assert-equal 1
                  (getf (getf flow :context-chat-approval-inbox) :request-count)
                  "actor flow query should expose one chat approval inbox entry")
    (assert-equal 1
                  (getf (getf flow :governance-inbox) :request-count)
                  "actor flow query should expose one governance inbox entry")
    (assert-equal 1
                  (getf (getf flow :editor-pending-mutations) :mutation-count)
                  "actor flow query should expose one editor pending mutation entry")))

(defun governed-desktop-task-governance-inbox-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record)))
         (inbox (sbcl-agent::service-response-data
                 (sbcl-agent::query-desktop-task-governance-inbox-service
                  session
                  :session-id session-id)))
         (requests (getf inbox :requests))
         (entry (first requests)))
    (declare (ignore response))
    (assert-true (stringp session-id)
                 "governance inbox should be keyed by a session id")
    (assert-true (stringp approval-id)
                 "governance inbox should expose a governance approval id")
    (assert-equal session-id
                  (getf inbox :session-id)
                  "governance inbox query should echo the requested session id")
    (assert-equal 1
                  (getf inbox :request-count)
                  "governance inbox query should return the awaiting approval request")
    (assert-true entry
                 "governance inbox query should return one request entry")
    (assert-equal approval-id
                  (getf entry :approval-id)
                  "governance inbox entry should expose the approval id")
    (assert-equal session-id
                  (getf entry :session-id)
                  "governance inbox entry should expose the session id")
    (assert-equal :awaiting-approval
                  (getf entry :status)
                  "governance inbox entry should remain awaiting approval before authorization")
    (assert-equal :awaiting-approval
                  (getf entry :approval-status)
                  "governance inbox entry should expose the awaiting approval status")
    (assert-equal :governance-inbox
                  (getf entry :mailbox)
                  "governance inbox entry should identify its mailbox")
    (assert-equal :queued
                  (getf entry :delivery-status)
                  "governance inbox entry should retain queued delivery state")
    (assert-equal :editor
                  (getf entry :target)
                  "governance inbox entry should identify the receiver target")
    (assert-equal :append-text
                  (getf entry :operation)
                  "governance inbox entry should identify the pending governed operation")))

(defun governed-desktop-task-context-chat-mailbox-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record)))
         (pending-action-id (and record
                                 (sbcl-agent::desktop-task-record-pending-action-id record)))
         (mailbox (sbcl-agent::service-response-data
                   (sbcl-agent::query-desktop-task-context-chat-mailbox-service
                    session
                    :session-id session-id)))
         (messages (getf mailbox :messages))
         (entry (first messages)))
    (declare (ignore response))
    (assert-true (stringp session-id)
                 "context chat mailbox should be keyed by session id")
    (assert-true (stringp approval-id)
                 "context chat mailbox should expose the governance approval id")
    (assert-true (stringp pending-action-id)
                 "context chat mailbox should expose the editor pending action id")
    (assert-equal session-id
                  (getf mailbox :session-id)
                  "context chat mailbox query should echo the requested session id")
    (assert-equal 1
                  (getf mailbox :message-count)
                  "context chat mailbox query should return the awaiting approval message")
    (assert-true entry
                 "context chat mailbox query should return one message entry")
    (assert-equal approval-id
                  (getf entry :approval-id)
                  "context chat mailbox entry should expose the approval id")
    (assert-true (stringp (getf entry :mailbox-entry-id))
                 "context chat mailbox entry should expose a durable mailbox entry id")
    (assert-equal :context-chat-mailbox
                  (getf entry :mailbox)
                  "context chat mailbox entry should identify its mailbox")
    (assert-equal :outbox
                  (getf entry :direction)
                  "context chat mailbox entry should identify its mailbox direction")
    (assert-equal :awaiting-approval
                  (getf entry :delivery-status)
                  "context chat mailbox entry should retain its delivery state")
    (assert-equal pending-action-id
                  (getf entry :pending-action-id)
                  "context chat mailbox entry should expose the pending action id")
    (assert-equal :awaiting-approval
                  (getf entry :status)
                  "context chat mailbox entry should remain awaiting approval before authorization")
    (assert-equal :awaiting-approval
                  (getf entry :approval-status)
                  "context chat mailbox entry should expose the awaiting approval status")
    (assert-equal :editor
                  (getf entry :target)
                  "context chat mailbox entry should identify the receiver target")
    (assert-equal :append-text
                  (getf entry :operation)
                  "context chat mailbox entry should identify the pending governed operation")))

(defun governed-desktop-task-context-chat-approval-inbox-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record)))
         (pending-action-id (and record
                                 (sbcl-agent::desktop-task-record-pending-action-id record)))
         (inbox (sbcl-agent::service-response-data
                 (sbcl-agent::query-desktop-task-context-chat-approval-inbox-service
                  session
                  :session-id session-id)))
         (requests (getf inbox :requests))
         (entry (first requests)))
    (declare (ignore response))
    (assert-equal session-id
                  (getf inbox :session-id)
                  "context chat approval inbox should echo the session id")
    (assert-equal 1
                  (getf inbox :request-count)
                  "context chat approval inbox should expose one approval request")
    (assert-equal approval-id
                  (getf entry :approval-id)
                  "context chat approval inbox should expose the approval id")
    (assert-equal :context-chat-approval-inbox
                  (getf entry :mailbox)
                  "context chat approval inbox entry should identify its mailbox")
    (assert-equal :inbox
                  (getf entry :direction)
                  "context chat approval inbox entry should identify its mailbox direction")
    (assert-equal :available
                  (getf entry :delivery-status)
                  "context chat approval inbox entry should retain its delivery state")
    (assert-equal pending-action-id
                  (getf entry :pending-action-id)
                  "context chat approval inbox should expose the pending editor action id")
    (assert-equal :awaiting-approval
                  (getf entry :approval-status)
                  "context chat approval inbox should expose an awaiting approval request")))

(defun governed-desktop-task-editor-authorization-mailbox-test ()
  (let* ((session (make-test-session))
         (provider (make-test-provider))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (pending-action-id (and record
                                 (sbcl-agent::desktop-task-record-pending-action-id record))))
    (declare (ignore response))
    (sbcl-agent::command-desktop-task-approve-approval-service
     session provider approval-id :session-id session-id)
    (let* ((mailbox (sbcl-agent::service-response-data
                     (sbcl-agent::query-desktop-task-editor-authorization-mailbox-service
                      session
                      :session-id session-id
                      :pending-action-id pending-action-id)))
           (entries (getf mailbox :authorizations))
           (entry (first entries)))
      (assert-equal session-id
                    (getf mailbox :session-id)
                    "editor authorization mailbox should echo the session id")
      (assert-equal 1
                    (getf mailbox :authorization-count)
                    "editor authorization mailbox should expose one authorized mutation")
      (assert-equal approval-id
                    (getf entry :approval-id)
                    "editor authorization mailbox should expose the approval id")
      (assert-equal :editor-authorization-mailbox
                    (getf entry :mailbox)
                    "editor authorization mailbox entry should identify its mailbox")
      (assert-equal :applied
                    (getf entry :delivery-status)
                    "editor authorization mailbox entry should retain consumed delivery state after apply")
      (assert-true (getf entry :delivered-at)
                   "editor authorization mailbox entry should retain delivery timing")
      (assert-true (getf entry :dequeued-at)
                   "editor authorization mailbox entry should retain dequeue timing")
      (assert-equal pending-action-id
                    (getf entry :pending-action-id)
                    "editor authorization mailbox should expose the pending action id")
      (assert-equal :approved
                    (getf entry :approval-status)
                    "editor authorization mailbox should expose the approved governance state"))))

(defun governed-desktop-task-editor-pending-mutation-mailbox-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (pending-action-id (and record
                                 (sbcl-agent::desktop-task-record-pending-action-id record)))
         (mailbox (sbcl-agent::service-response-data
                   (sbcl-agent::query-desktop-task-editor-mailbox-service
                    session
                    :session-id session-id
                    :pending-action-id pending-action-id)))
         (entries (getf mailbox :mutations))
         (entry (first entries)))
    (declare (ignore response))
    (assert-equal session-id
                  (getf mailbox :session-id)
                  "editor pending mutation mailbox should echo the session id")
    (assert-equal 1
                  (getf mailbox :mutation-count)
                  "editor pending mutation mailbox should expose one editor intent")
    (assert-equal pending-action-id
                  (getf entry :pending-action-id)
                  "editor pending mutation mailbox should expose the pending action id")
    (assert-equal :awaiting-approval
                  (getf entry :delivery-status)
                  "editor pending mutation mailbox should retain awaiting approval delivery state before approval")
    (assert-equal :awaiting-approval
                  (getf entry :approval-status)
                  "editor pending mutation mailbox should retain awaiting approval governance state before approval")))

(defun governed-desktop-task-editor-pending-mutation-mailbox-authorized-test ()
  (let* ((session (make-test-session))
         (provider (make-test-provider))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (pending-action-id (and record
                                 (sbcl-agent::desktop-task-record-pending-action-id record))))
    (declare (ignore response))
    (sbcl-agent::command-desktop-task-approve-approval-service
     session provider approval-id :session-id session-id)
    (sbcl-agent::refresh-session-actor-mailboxes session)
    (let* ((mailbox (sbcl-agent::service-response-data
                     (sbcl-agent::query-desktop-task-editor-mailbox-service
                      session
                      :session-id session-id
                      :pending-action-id pending-action-id)))
           (entries (getf mailbox :mutations))
           (entry (first entries)))
      (assert-equal 1
                    (getf mailbox :mutation-count)
                    "editor pending mutation mailbox should retain one editor intent after approval")
      (assert-equal pending-action-id
                    (getf entry :pending-action-id)
                    "editor pending mutation mailbox should retain the pending action id after approval")
      (assert-equal :applied
                    (getf entry :delivery-status)
                    "editor pending mutation mailbox should reflect that the pending editor intent was applied after approval")
      (assert-equal :approved
                    (getf entry :approval-status)
                    "editor pending mutation mailbox should retain approved governance state after approval")
      (assert-true (getf entry :acknowledged-at)
                   "editor pending mutation mailbox should retain approval timing after approval")
      (assert-true (getf entry :completed-at)
                   "editor pending mutation mailbox should retain completion timing after apply"))))

(defun governed-desktop-task-context-chat-approval-inbox-consumed-test ()
  (let* ((session (make-test-session))
         (provider (make-test-provider))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record))))
    (declare (ignore response))
    (sbcl-agent::command-desktop-task-approve-approval-service
     session provider approval-id :session-id session-id)
    (let* ((inbox (sbcl-agent::service-response-data
                   (sbcl-agent::query-desktop-task-context-chat-approval-inbox-service
                    session
                    :session-id session-id)))
           (requests (getf inbox :requests))
           (entry (first requests)))
      (assert-equal 1
                    (getf inbox :request-count)
                    "context chat approval inbox should retain the approval message after consume")
      (assert-equal approval-id
                    (getf entry :approval-id)
                    "context chat approval inbox should retain the same approval id after consume")
      (assert-equal :consumed
                    (getf entry :delivery-status)
                    "context chat approval inbox entry should retain a consumed delivery state after approval")
      (assert-equal :approved
                    (getf entry :approval-status)
                    "context chat approval inbox entry should retain the approved status after approval")
      (assert-true (getf entry :acknowledged-at)
                   "context chat approval inbox entry should retain acknowledgement timing after approval"))))

(defun governed-desktop-task-context-chat-approval-acknowledge-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record)))
         (ack-response
           (sbcl-agent::command-desktop-task-ack-context-chat-approval-service
            session
            approval-id
            :session-id session-id))
         (ack-data (sbcl-agent::service-response-data ack-response)))
    (declare (ignore response))
    (assert-equal approval-id
                  (getf ack-data :approval-id)
                  "chat approval acknowledge should echo the approval id")
    (assert-equal :consumed
                  (getf ack-data :delivery-status)
                  "chat approval acknowledge should mark the mailbox entry consumed")
    (assert-true (getf ack-data :acknowledged-at)
                 "chat approval acknowledge should stamp acknowledgement timing")
    (sbcl-agent::refresh-session-actor-mailboxes session)
    (let* ((inbox (sbcl-agent::service-response-data
                   (sbcl-agent::query-desktop-task-context-chat-approval-inbox-service
                    session
                    :session-id session-id)))
           (entry (first (getf inbox :requests))))
      (assert-equal 1
                    (getf inbox :request-count)
                    "chat approval inbox should retain one request after explicit acknowledge")
      (assert-equal :consumed
                    (getf entry :delivery-status)
                    "chat approval inbox should retain consumed state across mailbox refresh")
      (assert-true (getf entry :acknowledged-at)
                   "chat approval inbox should retain acknowledgement timing across mailbox refresh"))))

(defun governed-desktop-task-pending-approval-mailbox-state-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record))))
    (declare (ignore response))
    (sbcl-agent::command-desktop-task-ack-context-chat-approval-service
     session
     approval-id
     :session-id session-id)
    (sbcl-agent::refresh-session-actor-mailboxes session)
    (let* ((pending (sbcl-agent::service-response-data
                     (sbcl-agent::query-desktop-task-pending-approval-service session)))
           (requests (getf pending :requests))
           (entry (first requests)))
      (assert-equal session-id
                    (getf pending :session-id)
                    "pending approval summary should retain the chat session id from mailbox state")
      (assert-true (member approval-id
                           (getf pending :approval-ids)
                           :test #'string=)
                   "pending approval summary should retain the approval id from mailbox state")
      (assert-equal 1
                    (length requests)
                    "pending approval summary should expose the retained approval inbox entry")
      (assert-equal :consumed
                    (getf entry :delivery-status)
                    "pending approval summary should reflect mailbox delivery state instead of recomputing from records")
      (assert-true (getf entry :acknowledged-at)
                   "pending approval summary should retain mailbox acknowledgement timing"))))

(defun governed-desktop-task-context-chat-mailbox-entry-id-stable-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (first-mailbox (sbcl-agent::service-response-data
                         (sbcl-agent::query-desktop-task-context-chat-mailbox-service
                          session
                          :session-id session-id)))
         (first-entry (first (getf first-mailbox :messages)))
         (first-id (getf first-entry :mailbox-entry-id)))
    (declare (ignore response))
    (sbcl-agent::refresh-session-actor-mailboxes session)
    (let* ((second-mailbox (sbcl-agent::service-response-data
                            (sbcl-agent::query-desktop-task-context-chat-mailbox-service
                             session
                             :session-id session-id)))
           (second-entry (first (getf second-mailbox :messages)))
           (second-id (getf second-entry :mailbox-entry-id)))
      (assert-true (stringp first-id)
                   "context chat mailbox entry should expose a stable mailbox entry id")
      (assert-equal first-id
                    second-id
                    "context chat mailbox entry id should remain stable across mailbox refreshes"))))

(defun governed-desktop-task-apply-editor-authorization-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (policy-id (and record
                         (sbcl-agent::desktop-task-record-policy-id record)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (pending-action-id (and record
                                 (sbcl-agent::desktop-task-record-pending-action-id record))))
    (declare (ignore response))
    (assert-true (stringp pending-action-id)
                 "authorized editor apply test should start from a persisted pending action id")
    (assert-true policy-id
                 "authorized editor apply test should start from a governed policy id")
    (sbcl-agent::approve-policy session policy-id)
    (sbcl-agent::mark-desktop-task-record-approved session record)
    (let* ((apply-response
             (sbcl-agent::command-desktop-task-apply-editor-authorization-service
              session
              pending-action-id
              :session-id session-id))
           (apply-data (sbcl-agent::service-response-data apply-response))
           (updated-record (first (sbcl-agent::agent-session-desktop-tasks session))))
      (assert-equal session-id
                    (getf apply-data :session-id)
                    "editor authorization apply response should echo the session id")
      (assert-equal pending-action-id
                    (getf apply-data :pending-action-id)
                    "editor authorization apply response should echo the pending action id")
      (assert-equal "Appended text to the active editor buffer."
                    (getf apply-data :summary)
                    "editor authorization apply response should summarize the applied mutation")
      (assert-equal :completed
                    (sbcl-agent::desktop-task-record-status updated-record)
                    "editor authorization apply should complete the governed editor mutation")
      (assert-equal :approved
                    (sbcl-agent::desktop-task-record-approval-status updated-record)
                    "editor authorization apply should preserve approved governance posture on the completed record"))))

(defun governed-desktop-task-consume-editor-authorization-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (policy-id (and record
                         (sbcl-agent::desktop-task-record-policy-id record)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (pending-action-id (and record
                                 (sbcl-agent::desktop-task-record-pending-action-id record))))
    (declare (ignore response))
    (assert-true policy-id
                 "editor authorization consume test should start from a governed policy id")
    (sbcl-agent::approve-policy session policy-id)
    (sbcl-agent::mark-desktop-task-record-approved session record)
    (let* ((consume-response
             (sbcl-agent::command-desktop-task-consume-editor-authorization-service
              session
              pending-action-id
              :session-id session-id))
           (consume-data (sbcl-agent::service-response-data consume-response)))
      (assert-equal pending-action-id
                    (getf consume-data :pending-action-id)
                    "editor authorization consume should echo the pending action id")
      (assert-equal :dequeued
                    (getf consume-data :delivery-status)
                    "editor authorization consume should dequeue the authorization entry")
      (assert-true (getf consume-data :dequeued-at)
                   "editor authorization consume should stamp dequeue timing"))
    (sbcl-agent::refresh-session-actor-mailboxes session)
    (let* ((mailbox (sbcl-agent::service-response-data
                     (sbcl-agent::query-desktop-task-editor-authorization-mailbox-service
                      session
                      :session-id session-id
                      :pending-action-id pending-action-id)))
           (entry (first (getf mailbox :authorizations))))
      (assert-equal 1
                    (getf mailbox :authorization-count)
                    "editor authorization mailbox should retain one authorization after dequeue")
      (assert-equal :dequeued
                    (getf entry :delivery-status)
                    "editor authorization mailbox should retain dequeued state across mailbox refresh")
      (assert-true (getf entry :dequeued-at)
                   "editor authorization mailbox should retain dequeue timing across mailbox refresh"))))

(defun governed-desktop-task-governance-decision-outbox-test ()
  (let* ((session (make-test-session))
         (request (sbcl-agent::make-governed-desktop-task-request
                   :requester :context-chat
                   :target :editor
                   :operation :append-text
                   :capability :workspace-write
                   :payload '(:text "(+ 1 1)")
                   :metadata '(:actor-slice :context-chat-editor-v1)))
         (response (sbcl-agent::run-direct-conversation-desktop-task-requests
                    session
                    "append (+ 1 1) to the editor"
                    (list request)))
         (record (first (sbcl-agent::agent-session-desktop-tasks session)))
         (policy-id (and record
                         (sbcl-agent::desktop-task-record-policy-id record)))
         (session-id (and record
                          (sbcl-agent::desktop-task-record-session-id record)))
         (approval-id (and record
                           (sbcl-agent::desktop-task-record-approval-id record)))
         (pending-action-id (and record
                                 (sbcl-agent::desktop-task-record-pending-action-id record))))
    (declare (ignore response))
    (assert-true policy-id
                 "governance decision outbox test should start from a governed policy id")
    (sbcl-agent::approve-policy session policy-id)
    (sbcl-agent::mark-desktop-task-record-approved session record)
    (sbcl-agent::refresh-session-actor-mailboxes session)
    (let* ((issued-mailbox (sbcl-agent::service-response-data
                            (sbcl-agent::query-desktop-task-governance-decision-outbox-service
                             session
                             :session-id session-id
                             :approval-id approval-id
                             :pending-action-id pending-action-id)))
           (issued-entry (first (getf issued-mailbox :decisions))))
      (assert-equal 1
                    (getf issued-mailbox :decision-count)
                    "governance decision outbox should expose one retained decision entry")
      (assert-equal :issued
                    (getf issued-entry :delivery-status)
                    "governance decision outbox should mark the approved authorization as issued before editor dequeue")
      (assert-true (getf issued-entry :delivered-at)
                   "governance decision outbox should stamp delivery timing when the decision is issued"))
    (sbcl-agent::command-desktop-task-consume-editor-authorization-service
     session
     pending-action-id
     :session-id session-id)
    (let* ((dequeued-mailbox (sbcl-agent::service-response-data
                              (sbcl-agent::query-desktop-task-governance-decision-outbox-service
                               session
                               :session-id session-id
                               :approval-id approval-id
                               :pending-action-id pending-action-id)))
           (dequeued-entry (first (getf dequeued-mailbox :decisions))))
      (assert-equal :dequeued
                    (getf dequeued-entry :delivery-status)
                    "governance decision outbox should retain dequeued state after the editor actor consumes the authorization")
      (assert-true (getf dequeued-entry :dequeued-at)
                   "governance decision outbox should retain dequeue timing after editor authorization consumption"))
    (sbcl-agent::command-desktop-task-apply-editor-authorization-service
     session
     pending-action-id
     :session-id session-id)
    (let* ((applied-mailbox (sbcl-agent::service-response-data
                             (sbcl-agent::query-desktop-task-governance-decision-outbox-service
                              session
                              :session-id session-id
                              :approval-id approval-id
                              :pending-action-id pending-action-id)))
           (applied-entry (first (getf applied-mailbox :decisions))))
      (assert-equal :applied
                    (getf applied-entry :delivery-status)
                    "governance decision outbox should retain applied state after the editor actor applies the authorized mutation")
      (assert-true (getf applied-entry :completed-at)
                   "governance decision outbox should retain completion timing after the editor actor applies the authorized mutation"))))
