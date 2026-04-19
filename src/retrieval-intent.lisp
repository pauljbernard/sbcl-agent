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
