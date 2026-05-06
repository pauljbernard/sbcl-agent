(in-package #:sbcl-agent)

(defclass mock-provider (provider)
  ((model :initarg :model :reader mock-provider-model)))

(defmethod provider-name ((provider mock-provider))
  "mock")

(defmethod provider-capabilities ((provider mock-provider))
  '(:chat :structured-response :action-proposals :streaming))

(defun mock-project-create-actions ()
  (list
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/create
      :arguments
      (:title "Agent Governed Project"
       :summary "Created through a governed conversation tool action."
       :constitution (:purpose "Deliver an end-to-end governed SDLC loop."
                      :principles ("traceability" "quality gates" "operational evidence"))
       :requirements ((:id "req-agent-governance"
                       :title "Capture governed requirements"
                       :summary "Project requirements must persist through the project record."
                       :kind "functional"
                       :priority "high"
                       :status "proposed"
                       :verification-kind "acceptance-test")
                      (:id "nfr-agent-latency"
                       :title "Maintain responsive governed tooling"
                       :summary "Authoring flows should stay operationally responsive."
                       :kind "constraint"
                       :priority "medium"
                       :status "proposed"
                       :verification-kind "performance"
                       :non-functional-p t))
       :feature-specifications ((:id "spec-thread-authoring"
                                 :title "Thread-driven project authoring"
                                 :summary "Conversation threads can create governed project artifacts."
                                 :status "draft"
                                 :acceptance-criteria ("Create a project from a conversation."
                                                       "Persist requirements and architecture.")
                                 :linked-requirement-ids ("req-agent-governance")))
       :design-system (:surface "projects" :density "high")
       :style-guide (:tone "direct" :formatting ("dense"))
       :user-journeys ((:id "journey-project-authoring"
                        :title "Author project governance through the thread"
                        :summary "An operator directs the agent to establish project governance."
                        :actors ("operator" "agent")
                        :steps ("Create the project."
                                "Persist requirements."
                                "Attach architecture evidence.")
                        :outcomes ("Governed project record available to the shell.")))
       :architecture-decisions ((:id "adr-thread-authoring"
                                 :title "Route project authoring through governed tools"
                                 :status "accepted"
                                 :summary "Project artifact creation must use governed tool execution."
                                 :drivers ("traceability" "agent parity")
                                 :linked-requirement-ids ("req-agent-governance")))
       :source-roots ("/tmp/agent-governed-project/src")
       :metadata (:origin "mock-provider-project-authoring"))))))

(defun mock-project-augment-actions ()
  (list
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/set-design-system
      :arguments (:design-system (:surface "projects" :mode "governed" :density "high"))))
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/set-style-guide
      :arguments (:style-guide (:tone "precise" :principles ("evidence-first" "minimal chrome")))))
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/append-feature-specification
      :arguments (:title "Conversation-managed authoring"
                  :summary "The thread can expand governed project artifacts."
                  :status "draft"
                  :acceptance-criteria ("Append specification from the thread."
                                        "Link the specification to requirements.")
                  :linked-requirement-ids ("req-agent-governance"))))
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/append-user-journey
      :arguments (:title "Iterate governance through a conversation"
                  :summary "An operator steers design intent while the agent persists artifacts."
                  :actors ("operator" "agent")
                  :steps ("Review requirement." "Add specification." "Add quality gate.")
                  :outcomes ("Project governance becomes operationally testable."))))
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/append-architecture-decision
      :arguments (:title "Use governed tool execution for project authoring"
                  :summary "Project artifact mutations must remain approval-gated and traceable."
                  :status "accepted"
                  :drivers ("governance" "traceability")
                  :linked-requirement-ids ("req-agent-governance"))))
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/append-source-root
      :arguments (:source-root "/tmp/agent-governed-project/tests")))
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/bind-testing-harness
      :arguments (:harness-id "full-suite")))
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/append-quality-gate
      :arguments (:title "Governed delivery gate"
                  :summary "Project completion requires traceable testing and source evidence."
                  :status "active"
                  :required-harness-ids ("full-suite")
                  :require-source-roots-p t
                  :required-trace-target-kinds ("feature-specification"
                                                "architecture-decision"
                                                "source-root"
                                                "testing-harness")
                  :minimum-linked-work-items 0
                  :maximum-failed-tests 0
                  :require-recovery-ready-p t)))))

(defun mock-project-revise-foundation-actions ()
  (list
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/set-constitution
      :arguments
      (:constitution (:purpose "Sustain governed SDLC closure through iterative evidence."
                      :principles ("traceability"
                                   "quality gates"
                                   "operational evidence"
                                   "conversation revision discipline")))))
   (make-assistant-action
    :type :tool
    :payload
   '(:tool-id :project/append-requirement
      :arguments (:id "req-governed-closure"
                  :title "Track governed closure evidence"
                  :summary "Project closure must remain visible through conversational revision."
                  :kind "functional"
                  :priority "high"
                  :status "proposed"
                  :verification-kind "acceptance-test")))))

(defun mock-project-revise-architecture-actions ()
  (list
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/append-architecture-decision
      :arguments (:id "adr-governed-closure"
                  :title "Make closure evidence part of architecture governance"
                  :summary "Architecture review must explicitly account for closure evidence and revision control."
                  :status "accepted"
                  :drivers ("closure-evidence" "revision-discipline" "traceability")
                  :linked-requirement-ids ("req-governed-closure" "req-agent-governance"))))))

(defun mock-project-revise-testing-posture-actions ()
  (list
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/set-testing-strategy
      :arguments
      (:testing-strategy
       (:required-evidence ("coverage" "performance" "governed-approval")
        :suite-expectations ((:harness-id :full-suite
                              :purpose "governed regression"
                              :evidence-kinds ("coverage" "performance"))
                             (:harness-id :smoke-suite
                              :purpose "operator sanity"
                              :evidence-kinds ("console" "latency")))
        :threshold-policy (:max-failed-tests 1
                           :max-say-turn-latency-seconds 0.5
                           :max-environment-save-load-seconds 3.0
                           :require-coverage t
                           :require-recovery-ready t)))))))

(defun mock-project-revise-release-readiness-actions ()
  (list
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/set-release-readiness
      :arguments
      (:release-readiness
       (:stage "candidate"
        :signoff-status "pending"
        :target-window "2026-05-15"
        :required-approvers ("platform" "ops")
        :observation-plan ("watch latency" "review incidents")
        :open-risks ("coverage regression risk")))))))

(defun mock-project-revise-readiness-obligations-actions ()
  (list
   (make-assistant-action
    :type :tool
    :payload
    '(:tool-id :project/set-readiness-obligations
      :arguments
      (:readiness-obligations
       ((:id "obl-release-signoff"
         :title "Complete operator release signoff"
         :summary "Platform and operations signoff must be explicitly confirmed before closure."
         :status "blocked"
         :blocking-p t
         :owner "ops"
         :due-window "2026-05-15"
         :evidence-kinds ("governed-approval" "performance"))
        (:id "obl-observation-window"
         :title "Track post-release observation window"
         :summary "Observation plan must remain attached for initial release monitoring."
         :status "ready"
         :blocking-p nil
         :owner "platform"
         :due-window "2026-05-16"
         :evidence-kinds ("performance" "console"))))))))

(defun mock-actions-for-prompt (prompt)
  (cond
    ((search "create governed project artifacts" prompt :test #'char-equal)
     (mock-project-create-actions))
    ((search "augment governed project artifacts" prompt :test #'char-equal)
     (mock-project-augment-actions))
    ((search "revise governed project foundations" prompt :test #'char-equal)
     (mock-project-revise-foundation-actions))
    ((search "revise governed architecture posture" prompt :test #'char-equal)
     (mock-project-revise-architecture-actions))
    ((search "revise governed testing posture" prompt :test #'char-equal)
     (mock-project-revise-testing-posture-actions))
    ((search "revise governed release readiness" prompt :test #'char-equal)
     (mock-project-revise-release-readiness-actions))
    ((search "revise governed readiness obligations" prompt :test #'char-equal)
     (mock-project-revise-readiness-obligations-actions))
    ((search "read src/main.lisp" prompt :test #'char-equal)
     (list
      (make-assistant-action
       :type :tool
       :payload (list :tool-id :fs/read
                      :arguments (list :path "src/main.lisp")))))
    ((search "list src" prompt :test #'char-equal)
     (list
      (make-assistant-action
       :type :tool
       :payload (list :tool-id :fs/list
                      :arguments (list :path "src")))))
    (t
     nil)))

(defun build-mock-response (request-or-prompt &optional session-summary)
  (let* ((request (if (typep request-or-prompt 'provider-request)
                      request-or-prompt
                      (make-provider-request :prompt request-or-prompt
                                             :session-summary session-summary)))
         (prompt (provider-request-prompt request))
         (actions (mock-actions-for-prompt prompt)))
    (make-assistant-response
     :message (if actions
                  (format nil
                          "Mock response: ~A~%~%I have prepared ~D proposed action~:P."
                          prompt
                          (length actions))
                  (format nil
                          "Mock response: ~A~%~%This is the SBCL scaffold. Replace the mock provider with a real model adapter next."
                          prompt))
     :actions actions
     :metadata (list :provider :mock
                     :prompt prompt
                     :operator-mode (provider-request-operator-mode request)
                     :thread (provider-request-thread-context request)
                     :turn (provider-request-turn-context request)
                     :environment (provider-request-environment-context request)
                     :cognition (and (provider-request-cognition-bundle request)
                                     (cognition-bundle-summary
                                      (provider-request-cognition-bundle request)))
                     :session (provider-request-session-summary request)))))

(defun split-stream-message (message)
  (let* ((length (length message))
         (chunk-size (max 1 (ceiling length 3))))
    (loop for start from 0 below length by chunk-size
          collect (subseq message start (min length (+ start chunk-size))))))

(defun mock-stream-delay-seconds ()
  (let ((value (ignore-errors
                 (parse-integer (or (getenv "TUTOR_CODEX_MOCK_STREAM_DELAY_MS") "0")
                                :junk-allowed t))))
    (if (and value (> value 0))
        (/ value 1000.0)
        0.0)))

(defun maybe-sleep-for-mock-stream ()
  (let ((delay (mock-stream-delay-seconds)))
    (when (> delay 0.0)
      (sleep delay))))

(defmethod send-request ((provider mock-provider) request)
  (declare (ignore provider))
  (build-mock-response request))

(defmethod stream-request ((provider mock-provider) request event-handler)
  (declare (ignore provider))
  (let* ((response (build-mock-response request))
         (actions (assistant-response-actions response)))
    (emit-provider-event event-handler :message-start nil)
    (maybe-sleep-for-mock-stream)
    (dolist (chunk (split-stream-message (assistant-response-message response)))
      (emit-provider-event event-handler :message-delta chunk)
      (maybe-sleep-for-mock-stream))
    (when actions
      (emit-provider-event event-handler :action-proposal actions))
    (when actions
      (maybe-sleep-for-mock-stream))
    (emit-provider-event event-handler
                         :message-complete
                         (list :response response
                               :metadata (assistant-response-metadata response)))
    response))
