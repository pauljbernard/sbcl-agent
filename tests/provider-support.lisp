(in-package #:sbcl-agent/tests)

(defun make-test-provider ()
  (sbcl-agent::make-provider
   (sbcl-agent::make-config :provider "mock"
                            :model "gpt-5"
                            :working-directory "/tmp/")))

(defclass mixed-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider mixed-action-provider))
  "mixed-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider mixed-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider mixed-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Executing eval now and staging the file read."
   :actions (list (sbcl-agent::make-assistant-action :type :eval :payload '(:form "(+ 100 203)"))
                  (sbcl-agent::make-assistant-action :type :tool :payload '(:tool-id :fs/read :arguments (:path "src/main.lisp"))))
   :metadata '(:provider :mixed-action-test)))

(defclass patch-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider patch-action-provider))
  "patch-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider patch-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider patch-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a patch that requires workspace write approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :patch
                   :payload '((:write "tmp/generated.txt" "hello from patch"))))
   :metadata '(:provider :patch-action-test)))

(defclass weak-grounding-patch-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider weak-grounding-patch-provider))
  "weak-grounding-patch-test")

(defmethod sbcl-agent::provider-capabilities ((provider weak-grounding-patch-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider weak-grounding-patch-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a patch even though the request was historical recall."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :patch
                   :payload '((:write "tmp/weak-grounding.txt" "weak grounding patch"))))
   :metadata '(:provider :weak-grounding-patch-test)))

(defclass journal-date-time-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider journal-date-time-provider))
  "journal-date-time-test")

(defmethod sbcl-agent::provider-capabilities ((provider journal-date-time-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider journal-date-time-provider) request)
  (declare (ignore provider))
  (let* ((prompt (sbcl-agent::provider-request-prompt request))
         (summary (sbcl-agent::provider-request-session-summary request))
         (transcript (getf summary :recent-transcript))
         (assistant-turn (find :assistant transcript :from-end t :key (lambda (entry) (getf entry :role))))
         (prior-message (and assistant-turn (getf assistant-turn :content)))
         (code "(multiple-value-bind (sec min hour day month year) (get-decoded-time) (format nil \"~D-~D-~D ~D:~D:~D\" year month day hour min sec))"))
    (cond
      ((search "current data and time" prompt :test #'char-equal)
       (sbcl-agent::make-assistant-response
        :message code
        :actions '()
        :metadata '(:provider :journal-date-time-test :step :suggest)))
      ((search "now go execute that" prompt :test #'char-equal)
       (unless (and prior-message (search "get-decoded-time" prior-message :test #'char-equal))
         (error "journal-date-time-provider expected the prior assistant suggestion in recent transcript"))
       (sbcl-agent::make-assistant-response
        :message "Executing the previously suggested date/time code."
        :actions (list (sbcl-agent::make-assistant-action :type :eval :payload prior-message))
        :metadata '(:provider :journal-date-time-test :step :execute)))
      (t
       (error "journal-date-time-provider received unexpected prompt ~S" prompt)))))

(defclass mutating-eval-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider mutating-eval-provider))
  "mutating-eval-test")

(defmethod sbcl-agent::provider-capabilities ((provider mutating-eval-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider mutating-eval-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a mutating eval that requires runtime approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :eval
                   :payload '(:form "(progn (defparameter sbcl-agent-user::*governed-runtime-flag* nil) (setf sbcl-agent-user::*governed-runtime-flag* :mutated) sbcl-agent-user::*governed-runtime-flag*)"
                             :mutating t)))
   :metadata '(:provider :mutating-eval-test)))

(defclass git-write-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider git-write-action-provider))
  "git-write-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider git-write-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider git-write-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a git write action that requires approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :tool
                   :payload '(:tool-id :git/add :arguments (:paths ("README.md")))))
   :metadata '(:provider :git-write-action-test)))

(defclass project-create-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider project-create-action-provider))
  "project-create-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider project-create-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider project-create-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a governed project creation action that requires approval."
   :actions
   (list
    (sbcl-agent::make-assistant-action
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
        :metadata (:origin "conversation-tooling-test")))))
   :metadata '(:provider :project-create-action-test)))

(defclass project-augment-action-provider (sbcl-agent::provider)
  ((requirement-id :initarg :requirement-id :reader project-augment-requirement-id)))

(defmethod sbcl-agent::provider-name ((provider project-augment-action-provider))
  "project-augment-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider project-augment-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider project-augment-action-provider) request)
  (declare (ignore request))
  (let ((requirement-id (project-augment-requirement-id provider)))
    (sbcl-agent::make-assistant-response
     :message "Prepared governed project authoring actions that require approval."
     :actions
     (list
      (sbcl-agent::make-assistant-action
       :type :tool
       :payload
       '(:tool-id :project/set-design-system
         :arguments (:design-system (:surface "projects" :mode "governed" :density "high"))))
      (sbcl-agent::make-assistant-action
       :type :tool
       :payload
       '(:tool-id :project/set-style-guide
         :arguments (:style-guide (:tone "precise" :principles ("evidence-first" "minimal chrome")))))
      (sbcl-agent::make-assistant-action
       :type :tool
       :payload
       `(:tool-id :project/append-feature-specification
         :arguments (:title "Conversation-managed authoring"
                     :summary "The thread can expand governed project artifacts."
                     :status "draft"
                     :acceptance-criteria ("Append specification from the thread."
                                           "Link the specification to requirements.")
                     :linked-requirement-ids (,requirement-id))))
      (sbcl-agent::make-assistant-action
       :type :tool
       :payload
       '(:tool-id :project/append-user-journey
         :arguments (:title "Iterate governance through a conversation"
                     :summary "An operator steers design intent while the agent persists artifacts."
                     :actors ("operator" "agent")
                     :steps ("Review requirement." "Add specification." "Add quality gate.")
                     :outcomes ("Project governance becomes operationally testable."))))
      (sbcl-agent::make-assistant-action
       :type :tool
       :payload
       `(:tool-id :project/append-architecture-decision
         :arguments (:title "Use governed tool execution for project authoring"
                     :summary "Project artifact mutations must remain approval-gated and traceable."
                     :status "accepted"
                     :drivers ("governance" "traceability")
                     :linked-requirement-ids (,requirement-id))))
      (sbcl-agent::make-assistant-action
       :type :tool
       :payload
       '(:tool-id :project/append-source-root
         :arguments (:source-root "/tmp/agent-governed-project/tests")))
      (sbcl-agent::make-assistant-action
       :type :tool
       :payload
       '(:tool-id :project/bind-testing-harness
         :arguments (:harness-id "full-suite")))
      (sbcl-agent::make-assistant-action
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
                     :require-recovery-ready-p t))))
     :metadata '(:provider :project-augment-action-test))))

(defclass runtime-reload-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider runtime-reload-action-provider))
  "runtime-reload-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider runtime-reload-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider runtime-reload-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a runtime reload action that requires approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :tool
                   :payload '(:tool-id :runtime/reload-file
                             :arguments (:path "tmp/conversation-reload-target.lisp"))))
   :metadata '(:provider :runtime-reload-action-test)))

(defclass failing-mutating-eval-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider failing-mutating-eval-provider))
  "failing-mutating-eval-test")

(defmethod sbcl-agent::provider-capabilities ((provider failing-mutating-eval-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider failing-mutating-eval-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a mutating eval that will fail at runtime."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :eval
                   :payload '(:form "(error \"runtime incident boom\")"
                             :mutating t)))
   :metadata '(:provider :failing-mutating-eval-test)))

(defclass followup-patch-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider followup-patch-provider))
  "followup-patch-test")

(defmethod sbcl-agent::provider-capabilities ((provider followup-patch-provider))
  '(:chat :structured-response :action-proposals :turn-followup))

(defmethod sbcl-agent::send-request ((provider followup-patch-provider) request)
  (declare (ignore provider))
  (let* ((turn-context (sbcl-agent::provider-request-turn-context request))
         (retrieval-dossier (sbcl-agent::provider-request-retrieval-dossier request))
         (outcome-brief (sbcl-agent::provider-request-outcome-brief request))
         (operations (getf turn-context :operations))
         (completed-patch (find "assistant-patch"
                                operations
                                :key (lambda (entry) (getf entry :name))
                                :test #'string=)))
    (if (and completed-patch
             (eq (getf completed-patch :status) :completed))
        (progn
          (unless (eq (getf retrieval-dossier :phase) :post-mutation)
            (error "followup-patch-provider expected a post-mutation retrieval dossier"))
          (unless (eq (getf outcome-brief :outcome-mode) :expectation-vs-observation)
            (error "followup-patch-provider expected an outcome brief for closed-loop reasoning"))
          (sbcl-agent::make-assistant-response
           :message "Patch applied successfully. Follow-up summary recorded."
           :actions '()
           :metadata (list :provider :followup-patch-test
                           :phase :followup
                           :retrieval-phase (getf retrieval-dossier :phase)
                           :outcome-next-step (getf outcome-brief :recommended-next-step)
                           :observed-consequences-count
                           (length (or (getf retrieval-dossier :observed-consequences) '())))))
        (sbcl-agent::make-assistant-response
         :message "Prepared a patch that requires approval before follow-up."
         :actions (list (sbcl-agent::make-assistant-action
                         :type :patch
                         :payload '((:write "tmp/followup-generated.txt" "hello from followup patch"))))
         :metadata '(:provider :followup-patch-test :phase :initial)))))

(defclass followup-validation-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider followup-validation-provider))
  "followup-validation-test")

(defmethod sbcl-agent::provider-capabilities ((provider followup-validation-provider))
  '(:chat :structured-response :action-proposals :turn-followup))

(defmethod sbcl-agent::send-request ((provider followup-validation-provider) request)
  (declare (ignore provider))
  (let* ((turn-context (sbcl-agent::provider-request-turn-context request))
         (retrieval-dossier (sbcl-agent::provider-request-retrieval-dossier request))
         (outcome-brief (sbcl-agent::provider-request-outcome-brief request))
         (operations (getf turn-context :operations))
         (completed-eval (find "assistant-eval"
                               operations
                               :key (lambda (entry) (getf entry :name))
                               :test #'string=)))
    (if (and completed-eval
             (eq (getf completed-eval :status) :completed))
        (sbcl-agent::make-assistant-response
         :message "Runtime mutation completed. Proposing a follow-up patch before validation."
         :actions (list (sbcl-agent::make-assistant-action
                         :type :patch
                         :payload '((:write "tmp/followup-validation-generated.txt"
                                            "should defer until validation"))))
         :metadata (list :provider :followup-validation-test
                         :phase :followup
                         :retrieval-phase (getf retrieval-dossier :phase)
                         :outcome-next-step (and outcome-brief
                                                 (getf outcome-brief :recommended-next-step))))
        (sbcl-agent::make-assistant-response
         :message "Prepared a mutating eval that requires approval before follow-up."
         :actions (list (sbcl-agent::make-assistant-action
                         :type :eval
                         :payload '(:form "(progn (defparameter *followup-validation-state* nil) (setf *followup-validation-state* :mutated))"
                                   :mutating t)))
         :metadata '(:provider :followup-validation-test :phase :initial)))))

(defclass slow-test-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider slow-test-provider))
  "slow-test-provider")

(defmethod sbcl-agent::provider-capabilities ((provider slow-test-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider slow-test-provider) request)
  (declare (ignore provider))
  (sleep 0.2)
  (sbcl-agent::make-assistant-response
   :message (format nil "Completed ~A" (sbcl-agent::provider-request-prompt request))
   :actions '()
   :metadata '(:provider :slow-test-provider)))
