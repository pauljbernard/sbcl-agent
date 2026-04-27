(in-package #:sbcl-agent)

(defstruct retrieval-intent
  category
  domains
  historical-p
  runtime-inspection-p
  governance-context-p
  source-context-p
  mutation-likely-p
  explanation)

(defstruct interaction-decision
  mode
  environment-effect
  approval-posture
  output-target
  explanation)

(defun prompt-contains-any-needle-p (prompt needles)
  (not (null (some (lambda (needle)
                     (search needle prompt :test #'char-equal))
                   needles))))

(defun classify-retrieval-intent (prompt &key (operator-mode :repl-bridge))
  (let* ((normalized-prompt (or prompt ""))
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
                           (when runtime-p '(:runtime))
                           (when workflow-p '(:workflow))
                           (when incident-p '(:incident))
                           (when (or workflow-p incident-p mutation-p) '(:artifact :events))
                           (when source-p '(:workspace)))
                   :test #'eq))
         (category (cond
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
     :runtime-inspection-p runtime-p
     :governance-context-p (or workflow-p incident-p mutation-p)
     :source-context-p source-p
     :mutation-likely-p mutation-p
     :explanation (cond
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
