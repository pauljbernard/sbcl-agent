(in-package #:sbcl-agent)

(defparameter *retrieval-ranking-mode* :auto)

(defun configure-retrieval-ranking-mode (mode)
  (setf *retrieval-ranking-mode* (or mode :auto)))

(defun retrieval-ranking-tokenize (text)
  (let ((normalized (string-downcase (or text "")))
        (current "")
        (tokens '()))
    (labels ((flush-token ()
               (when (> (length current) 2)
                 (push current tokens))
               (setf current "")))
      (loop for ch across normalized
            do (if (alphanumericp ch)
                   (setf current (concatenate 'string current (string ch)))
                   (flush-token)))
      (flush-token))
    (remove-duplicates (nreverse tokens) :test #'string=)))

(defun retrieval-ranking-enabled-p (prompt plan)
  (case *retrieval-ranking-mode*
    (:off nil)
    (:on t)
    (otherwise
     (or (retrieval-plan-semantic-ranking-p plan)
         (retrieval-plan-governance-detail-p plan)
         (prompt-contains-any-needle-p prompt
                                       '("earlier" "before" "previous" "prior"
                                         "history" "what happened" "that change"
                                         "that patch" "that issue" "that incident"))))))

(defun retrieval-candidate-score (prompt text)
  (let ((prompt-tokens (retrieval-ranking-tokenize prompt))
        (text-tokens (retrieval-ranking-tokenize text)))
    (count-if (lambda (token)
                (member token text-tokens :test #'string=))
              prompt-tokens)))

(defun governance-ranked-domain-bonus (plan label)
  (if (and (retrieval-plan-governance-detail-p plan)
           (member (retrieval-plan-expansion-posture plan)
                   '(:expand-on-gap :expanded)
                   :test #'eq))
      (case label
        (:incident 6)
        (:workflow 5)
        (:artifact 4)
        (:environment 3)
        (:conversation 1)
        (:events 4)
        (otherwise 0))
      0))

(defun retrieval-ranking-candidate (prompt label payload plan)
  (let* ((summary (provider-summary-content payload :limit 240))
         (text (princ-to-string summary))
         (base-score (retrieval-candidate-score prompt text))
         (governance-bonus (governance-ranked-domain-bonus plan label)))
    (list :label label
          :score (+ base-score governance-bonus)
          :base-score base-score
          :governance-bonus governance-bonus
          :summary summary)))

(defun build-retrieval-ranking (prompt dossier)
  (let* ((plan (retrieval-dossier-plan dossier))
         (enabled-p (retrieval-ranking-enabled-p prompt plan))
         (conversation-context (retrieval-dossier-conversation-context dossier))
         (runtime-context (retrieval-dossier-runtime-context dossier))
         (workflow-context (retrieval-dossier-workflow-context dossier))
         (incident-context (retrieval-dossier-incident-context dossier))
         (artifact-context (retrieval-dossier-artifact-context dossier))
         (environment-context (retrieval-dossier-environment-context dossier))
         (event-context (and environment-context
                             (getf environment-context :events)))
         (source-context (retrieval-dossier-source-context dossier))
         (candidates (remove nil
                             (list (and conversation-context
                                        (retrieval-ranking-candidate prompt :conversation conversation-context plan))
                                   (and runtime-context
                                        (retrieval-ranking-candidate prompt :runtime runtime-context plan))
                                   (and workflow-context
                                        (retrieval-ranking-candidate prompt :workflow workflow-context plan))
                                   (and incident-context
                                        (retrieval-ranking-candidate prompt :incident incident-context plan))
                                   (and artifact-context
                                        (retrieval-ranking-candidate prompt :artifact artifact-context plan))
                                   (and environment-context
                                        (retrieval-ranking-candidate prompt :environment environment-context plan))
                                   (and event-context
                                        (retrieval-ranking-candidate prompt :events event-context plan))
                                   (and source-context
                                        (retrieval-ranking-candidate prompt :workspace source-context plan)))))
         (ranked (sort candidates #'> :key (lambda (entry) (getf entry :score)))))
    (list :enabled-p enabled-p
          :strategy (if enabled-p :keyword-overlap :disabled)
          :top-candidates (if enabled-p
                              (subseq ranked 0 (min 4 (length ranked)))
                              '())
          :explanation (if enabled-p
                           (if (retrieval-plan-governance-detail-p plan)
                               "Ranking metadata emphasizes governance-relevant retrieved domains when the environment is under operational burden."
                               "Ranking metadata emphasizes the most relevant retrieved domains for historical or vague lookups.")
                           "Ranking is disabled for direct symbolic retrieval."))))
