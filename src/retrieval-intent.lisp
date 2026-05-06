(in-package #:sbcl-agent)

(defstruct retrieval-intent
  category
  domains
  historical-p
  intent-context-p
  runtime-inspection-p
  governance-context-p
  observability-context-p
  testing-context-p
  project-context-p
  source-context-p
  mutation-likely-p
  explanation)

(defstruct interaction-decision
  mode
  environment-effect
  approval-posture
  output-target
  explanation)

(defun prompt-match-tokens (prompt)
  (let ((normalized (string-downcase (or prompt "")))
        (current "")
        (tokens '()))
    (labels ((flush-token ()
               (when (> (length current) 0)
                 (push current tokens))
               (setf current "")))
      (loop for ch across normalized
            do (if (alphanumericp ch)
                   (setf current (concatenate 'string current (string ch)))
                   (flush-token)))
      (flush-token))
    (nreverse tokens)))

(defun simple-word-needle-p (needle)
  (and (> (length needle) 0)
       (every #'alphanumericp needle)))

(defun prompt-contains-any-needle-p (prompt needles)
  (let* ((normalized-prompt (string-downcase (or prompt "")))
         (tokens (prompt-match-tokens normalized-prompt)))
    (not
     (null
      (some (lambda (needle)
              (let ((normalized-needle (string-downcase needle)))
                (if (simple-word-needle-p normalized-needle)
                    (member normalized-needle tokens :test #'string=)
                    (search normalized-needle normalized-prompt :test #'char-equal))))
            needles)))))

(defun classify-retrieval-intent (prompt &key (operator-mode :repl-bridge))
  (let* ((normalized-prompt (or prompt ""))
         (intent-p (prompt-contains-any-needle-p normalized-prompt
                                                 '("intent" "alignment" "aligned"
                                                   "misaligned" "divergence"
                                                   "reconcile" "reconciliation"
                                                   "continuous alignment"
                                                   "expected behavior"
                                                   "expected behaviors")))
         (runtime-p (prompt-contains-any-needle-p normalized-prompt
                                                  '("runtime" "package" "symbol" "method"
                                                    "caller" "callers" "reload" "eval"
                                                    "loaded system" "image")))
         (workflow-p (prompt-contains-any-needle-p normalized-prompt
                                                   '("workflow" "approval" "approve"
                                                     "validation" "reconcile" "reconciliation"
                                                     "work-item" "work item" "quarantine"
                                                     "resume" "blocked")))
         (incident-p (prompt-contains-any-needle-p normalized-prompt
                                                   '("incident" "failure" "failed"
                                                     "error" "recovery" "recover"
                                                     "exception" "quarantine")))
         (history-p (prompt-contains-any-needle-p normalized-prompt
                                                  '("earlier" "before" "last time" "previous"
                                                    "history" "what happened" "prior")))
         (source-p (prompt-contains-any-needle-p normalized-prompt
                                                 '("file" "files" "source" "patch"
                                                   "diff" "code" "repository" "repo"
                                                   "workspace" "implement" "refactor")))
         (observability-p (prompt-contains-any-needle-p normalized-prompt
                                                        '("process" "processes" "cpu" "memory"
                                                          "network" "disk" "i/o" "io"
                                                          "telemetry" "performance" "monitor"
                                                          "monitoring" "console" "log" "logs"
                                                          "diagnostic" "diagnostics" "crash"
                                                          "spin report" "system log")))
         (testing-p (prompt-contains-any-needle-p normalized-prompt
                                                  '("test" "tests" "testing" "test suite"
                                                    "harness" "coverage" "benchmark"
                                                    "benchmarks" "performance test"
                                                    "performance tests" "regression"
                                                    "smoke test" "validation run"
                                                    "validator" "replay")))
         (project-p (prompt-contains-any-needle-p normalized-prompt
                                                  '("project" "projects" "constitution"
                                                    "requirement" "requirements"
                                                    "feature spec" "feature specification"
                                                    "feature specifications"
                                                    "design system" "style guide"
                                                    "testing strategy" "testing posture"
                                                    "release readiness" "release candidate"
                                                    "signoff" "readiness"
                                                    "readiness obligations"
                                                    "quality gate" "quality gates"
                                                    "user journey" "user journeys"
                                                    "non functional" "non-functional"
                                                    "architecture" "architecture decision"
                                                    "technology stack" "tech stack"
                                                    "product spec" "specification")))
         (mutation-p (prompt-contains-any-needle-p normalized-prompt
                                                   '("write" "change" "modify" "mutate" "mutation" "update"
                                                     "patch" "implement" "refactor"
                                                     "fix" "reload" "eval")))
         (conversation-p (or history-p
                             (prompt-contains-any-needle-p normalized-prompt
                                                           '("thread" "turn" "conversation"
                                                             "chat" "assistant said"))))
         (domains (remove-duplicates
                   (append (when conversation-p '(:conversation))
                           (when intent-p '(:intent))
                           (when project-p '(:project))
                           (when runtime-p '(:runtime))
                           (when observability-p '(:telemetry :console :diagnostic))
                           (when testing-p '(:testing))
                           (when workflow-p '(:workflow))
                           (when incident-p '(:incident))
                           (when (or workflow-p incident-p mutation-p testing-p) '(:artifact :events))
                           (when source-p '(:workspace)))
                   :test #'eq))
         (category (cond
                     (project-p :project-governance)
                     (testing-p :testing-feedback)
                     ((and incident-p runtime-p) :runtime-debugging)
                     ((and source-p mutation-p) :code-change)
                     (incident-p :incident-follow-up)
                     (workflow-p :workflow-supervision)
                     ((and runtime-p mutation-p) :runtime-mutation)
                     (runtime-p :runtime-inspection)
                     (source-p :source-inspection)
                     (history-p :historical-recall)
                     (t :general)))
         (resolved-domains (or domains '(:conversation :workspace))))
    (make-retrieval-intent
     :category category
     :domains resolved-domains
     :historical-p history-p
     :intent-context-p intent-p
     :runtime-inspection-p runtime-p
     :governance-context-p (or workflow-p incident-p mutation-p)
     :observability-context-p observability-p
     :testing-context-p testing-p
     :project-context-p project-p
     :source-context-p source-p
     :mutation-likely-p mutation-p
     :explanation (cond
                    (intent-p
                     "Prompt indicates durable intent, alignment, divergence, or reconciliation reasoning.")
                    (project-p
                     "Prompt indicates project governance, requirements, journeys, architecture, or design-system reasoning.")
                    (testing-p
                     "Prompt indicates testing, coverage, benchmark, or validation-feedback reasoning.")
                    (observability-p
                     "Prompt indicates runtime observability, telemetry, console, or diagnostics reasoning.")
                    (incident-p
                     "Prompt indicates incident or recovery reasoning.")
                    (workflow-p
                     "Prompt indicates workflow, approval, or validation reasoning.")
                    (runtime-p
                     "Prompt indicates live runtime inspection or mutation.")
                    (source-p
                     "Prompt indicates source or workspace reasoning.")
                    (history-p
                     "Prompt indicates historical recall across prior turns or artifacts.")
                    (t
                     "Prompt does not strongly select a single retrieval domain.")))))

(defun classify-interaction-decision (prompt &key (operator-mode :conversation))
  (declare (ignore operator-mode))
  (let* ((normalized-prompt (or prompt ""))
         (retrieval-intent (classify-retrieval-intent normalized-prompt
                                                      :operator-mode :conversation))
         (category (retrieval-intent-category retrieval-intent))
         (mutation-likely-p (retrieval-intent-mutation-likely-p retrieval-intent))
         (explicit-explanation-p (prompt-contains-any-needle-p normalized-prompt
                                                               '("explain" "what is"
                                                                 "how does" "why does"
                                                                 "assess" "review"
                                                                 "clarify" "describe"
                                                                 "help me understand")))
         (explicit-preparation-p (prompt-contains-any-needle-p normalized-prompt
                                                               '("what would you change"
                                                                 "what should change"
                                                                 "what needs to change"
                                                                 "what would be required"
                                                                 "plan the change"
                                                                 "prepare the fix"
                                                                 "before changing"
                                                                 "before patching")))
         (explicit-implementation-p (prompt-contains-any-needle-p normalized-prompt
                                                                 '("implement" "fix"
                                                                   "patch" "update"
                                                                   "refactor" "add"
                                                                   "remove" "wire"
                                                                   "create the code"
                                                                   "make the change")))
         (explicit-resume-p (prompt-contains-any-needle-p normalized-prompt
                                                          '("continue the blocked work item"
                                                            "continue the work item"
                                                            "resume the blocked work item"
                                                            "resume the work item"
                                                            "continue this fix"
                                                            "resume this fix")))
         (explicit-inspection-p (prompt-contains-any-needle-p normalized-prompt
                                                              '("why is this failing"
                                                                "why is this broken"
                                                                "diagnose"
                                                                "investigate"
                                                                "inspect"
                                                                "look into"
                                                                "what happened")))
         (mode (cond
                 (explicit-resume-p :mutate)
                 (explicit-preparation-p :prepare)
                 (explicit-implementation-p :mutate)
                 ((and explicit-explanation-p
                       (not explicit-inspection-p)
                       (not mutation-likely-p))
                  :conversation)
                 ((or explicit-inspection-p
                      (member category '(:runtime-debugging
                                         :runtime-inspection
                                         :source-inspection
                                         :incident-follow-up
                                         :workflow-supervision)
                              :test #'eq))
                  :inspect)
                 ((or explicit-explanation-p
                      (member category '(:historical-recall :general) :test #'eq))
                  :conversation)
                 (mutation-likely-p :prepare)
                 (t :conversation)))
         (environment-effect (case mode
                               (:conversation :none)
                               ((:inspect :prepare) :read-only)
                               (:mutate :write-required)))
         (approval-posture (case mode
                             (:conversation :free)
                             ((:inspect :prepare) :supervised)
                             (:mutate :governed)))
         (output-target (cond
                          ((eq mode :conversation) :reply-only)
                          ((eq mode :inspect) :workspace-context)
                          ((eq mode :prepare) :local-work-item)
                          (explicit-resume-p :local-work-item)
                          ((or explicit-implementation-p mutation-likely-p) :source-mutation)
                          (t :reply-only)))
         (explanation (cond
                        ((eq mode :conversation)
                         "Prompt is conversational or explanatory and does not require environment mutation.")
                        ((eq mode :inspect)
                         "Prompt requests diagnosis or inspection and should gather context without mutating the environment.")
                        ((eq mode :prepare)
                         "Prompt points toward change planning, but should stay read-oriented until implementation is explicitly confirmed.")
                        (explicit-resume-p
                         "Prompt explicitly resumes existing work and should continue the governed work item flow.")
                        (t
                         "Prompt explicitly requests implementation or mutation and should enter governed environment change flow."))))
    (make-interaction-decision
     :mode mode
     :environment-effect environment-effect
     :approval-posture approval-posture
     :output-target output-target
     :explanation explanation)))
