(in-package #:sbcl-agent)

(defun alphanumeric-char-p (character)
  (or (alpha-char-p character)
      (digit-char-p character)))

(defun make-memory-entry-id ()
  (format nil "memory-~D-~D" (get-universal-time) (random 1000000)))

(defun prompt-keyword-tokens (prompt)
  (let ((buffer "")
        (tokens '()))
    (labels ((flush-buffer ()
               (when (> (length buffer) 2)
                 (push buffer tokens))
               (setf buffer "")))
      (loop for character across (string-downcase (or prompt ""))
            do (if (alphanumeric-char-p character)
                   (setf buffer (concatenate 'string buffer (string character)))
                   (flush-buffer)))
      (flush-buffer))
    (remove-duplicates (nreverse tokens) :test #'string=)))

(defun turn-user-prompt (session turn)
  (let ((message (and (turn-user-message-id turn)
                      (find-message session (turn-user-message-id turn)))))
    (and message (message-content message))))

(defun turn-assistant-response-text (session turn)
  (let ((message (and (turn-assistant-message-id turn)
                      (find-message session (turn-assistant-message-id turn)))))
    (and message (message-content message))))

(defun token-overlap-score (left right)
  (let* ((left-tokens (prompt-keyword-tokens left))
         (right-tokens (prompt-keyword-tokens right))
         (matches (intersection left-tokens right-tokens :test #'string=)))
    (length matches)))

(defun prior-turn-similarity-entry (session prompt turn)
  (let* ((turn-prompt (turn-user-prompt session turn))
         (score (token-overlap-score prompt turn-prompt)))
    (when (> score 0)
      (let* ((turn-id (turn-id turn))
             (incidents (turn-incidents session turn-id))
             (detail (turn-detail session turn-id))
             (summary (getf detail :detail-summary)))
        (list :turn-id turn-id
              :score score
              :status (turn-status turn)
              :prompt turn-prompt
              :assistant-message (turn-assistant-response-text session turn)
              :incident-count (length incidents)
              :weakly-grounded-operation-count
              (getf summary :weakly-grounded-operation-count)
              :deferred-weakly-grounded-operation-count
              (getf summary :deferred-weakly-grounded-operation-count)
              :work-item-status (getf summary :work-item-status)
              :source :turn)))))

(defun environment-memory-entries (session)
  (let ((environment (session-bound-environment session)))
    (if environment
        (copy-list (or (environment-memory environment) '()))
        '())))

(defun environment-memory-turn-outcome-entry-p (entry)
  (eq (getf entry :kind) :turn-outcome))

(defun environment-memory-playbook-entry-p (entry)
  (eq (getf entry :kind) :playbook))

(defun environment-memory-failure-cluster-entry-p (entry)
  (eq (getf entry :kind) :failure-cluster))

(defun environment-memory-orchestration-outcome-entry-p (entry)
  (eq (getf entry :kind) :orchestration-outcome))

(defun environment-memory-orchestration-playbook-entry-p (entry)
  (eq (getf entry :kind) :orchestration-playbook))

(defun environment-memory-decomposition-playbook-entry-p (entry)
  (eq (getf entry :kind) :decomposition-playbook))

(defun environment-memory-evaluation-run-entry-p (entry)
  (eq (getf entry :kind) :evaluation-run))

(defun environment-memory-evaluation-failure-entry-p (entry)
  (eq (getf entry :kind) :evaluation-failure))

(defun environment-memory-operator-memory-entry-p (entry)
  (eq (getf entry :kind) :operator-memory))

(defun operator-memory-category-keyword (value)
  (cond
    ((keywordp value) value)
    ((stringp value)
     (intern (string-upcase (string-trim '(#\Space #\Tab #\Newline #\Return) value))
             :keyword))
    (t :general)))

(defun operator-memory-normalize-attribute (value)
  (let* ((text (string-downcase (string-trim '(#\Space #\Tab #\Newline #\Return)
                                             (princ-to-string (or value "fact")))))
         (normalized
           (with-output-to-string (stream)
             (loop with pending-separator-p = nil
                   for character across text
                   do (cond
                        ((alphanumeric-char-p character)
                         (when pending-separator-p
                           (write-char #\- stream)
                           (setf pending-separator-p nil))
                         (write-char character stream))
                        (t
                         (setf pending-separator-p t)))))))
    (if (> (length normalized) 0)
        normalized
        "fact")))

(defun operator-memory-entry-id (category attribute)
  (format nil "operator-memory-~A-~A"
          (string-downcase (string (operator-memory-category-keyword category)))
          (operator-memory-normalize-attribute attribute)))

(defun compact-operator-memory-entry (entry)
  (list :memory-id (getf entry :memory-id)
        :kind :operator-memory
        :category (getf entry :category)
        :attribute (getf entry :attribute)
        :value (getf entry :value)
        :summary (getf entry :summary)
        :confidence (getf entry :confidence)
        :source-turn-id (getf entry :source-turn-id)
        :recorded-at (getf entry :recorded-at)
        :updated-at (getf entry :updated-at)))

(defun operator-memory-document-text (entry)
  (format nil "~{~A~^ ~}"
          (remove nil
                  (list (getf entry :category)
                        (getf entry :attribute)
                        (getf entry :value)
                        (getf entry :summary)))))

(defun scored-operator-memory-entry (prompt entry)
  (let* ((category (getf entry :category))
         (base-score (retrieval-token-match-score prompt
                                                  (operator-memory-document-text entry)))
         (identity-bonus (if (member category '(:identity :self-description :attribution)
                                     :test #'eq)
                             2
                             0))
         (confidence-bonus (round (* 10 (or (getf entry :confidence) 0.0))))
         (score (+ base-score identity-bonus confidence-bonus)))
    (when (> score 0)
      (append (compact-operator-memory-entry entry)
              (list :score score)))))

(defun ranked-operator-memory-entries (session prompt &key (limit 6))
  (let* ((entries (remove-if-not #'environment-memory-operator-memory-entry-p
                                 (environment-memory-entries session)))
         (scored (remove nil
                         (mapcar (lambda (entry)
                                   (scored-operator-memory-entry prompt entry))
                                 entries)))
         (fill (remove-if (lambda (entry)
                            (find (getf entry :memory-id)
                                  scored
                                  :key (lambda (candidate) (getf candidate :memory-id))
                                  :test #'string=))
                          (sort (mapcar #'compact-operator-memory-entry entries)
                                #'>
                                :key (lambda (entry)
                                       (+ (if (member (getf entry :category)
                                                      '(:identity :preference :self-description :attribution :working-style)
                                                      :test #'eq)
                                              100
                                              0)
                                          (or (getf entry :updated-at)
                                              (getf entry :recorded-at)
                                              0)))))))
    (subseq (append (sort scored #'>
                           :key (lambda (entry)
                                  (or (getf entry :score) 0)))
                    fill)
            0
            (min limit (+ (length scored) (length fill))))))

(defun list-operator-memory-entries (session)
  (sort (mapcar #'compact-operator-memory-entry
                (remove-if-not #'environment-memory-operator-memory-entry-p
                               (environment-memory-entries session)))
        #'>
        :key (lambda (entry)
               (or (getf entry :updated-at)
                   (getf entry :recorded-at)
                   0))))

(defun find-operator-memory-entry (session memory-id)
  (find memory-id
        (environment-memory-entries session)
        :key (lambda (entry) (getf entry :memory-id))
        :test #'string=))

(defun remove-environment-memory-entry (environment memory-id)
  (let* ((entries (or (environment-memory environment) '())))
    (setf (environment-memory environment)
          (remove memory-id entries
                  :key (lambda (entry) (getf entry :memory-id))
                  :test #'string=))
    t))

(defun delete-operator-memory-entry (session memory-id)
  (let ((environment (session-bound-environment session)))
    (unless environment
      (error "Cannot delete operator memory without a bound environment."))
    (let ((entry (find-operator-memory-entry session memory-id)))
      (unless (and entry (environment-memory-operator-memory-entry-p entry))
        (error "Unknown operator memory entry ~S" memory-id))
      (remove-environment-memory-entry environment memory-id)
      (append-session-event session
                            :operator-memory-entry-deleted
                            (compact-operator-memory-entry entry)
                            :family :assistant
                            :entity-id memory-id
                            :thread-id (getf entry :thread-id)
                            :turn-id (getf entry :source-turn-id)
                            :visibility :operator)
      t)))

(defun update-operator-memory-entry (session memory-id &key category attribute value summary confidence)
  (let* ((environment (session-bound-environment session))
         (entry (find-operator-memory-entry session memory-id)))
    (unless environment
      (error "Cannot update operator memory without a bound environment."))
    (unless (and entry (environment-memory-operator-memory-entry-p entry))
      (error "Unknown operator memory entry ~S" memory-id))
    (let* ((resolved-category (or category (getf entry :category) :general))
           (resolved-attribute (or attribute (getf entry :attribute) "fact"))
           (updated (copy-list entry)))
      (setf (getf updated :memory-id) (operator-memory-entry-id resolved-category resolved-attribute)
            (getf updated :category) (operator-memory-category-keyword resolved-category)
            (getf updated :attribute) (operator-memory-normalize-attribute resolved-attribute)
            (getf updated :value) (or value (getf entry :value))
            (getf updated :summary) (or summary
                                       (getf updated :summary)
                                       (format nil "~A: ~A"
                                               (getf updated :attribute)
                                               (getf updated :value)))
            (getf updated :confidence) (or confidence (getf entry :confidence) 0.5)
            (getf updated :updated-at) (get-universal-time)
            (getf updated :manual-edited-p) t)
      (unless (string= memory-id (getf updated :memory-id))
        (remove-environment-memory-entry environment memory-id))
      (upsert-environment-memory-entry environment updated)
      (append-session-event session
                            :operator-memory-entry-updated
                            (compact-operator-memory-entry updated)
                            :family :assistant
                            :entity-id (getf updated :memory-id)
                            :thread-id (getf updated :thread-id)
                            :turn-id (getf updated :source-turn-id)
                            :visibility :operator)
      updated)))

(defun make-operator-memory-entry (thread turn candidate)
  (let* ((category (operator-memory-category-keyword
                    (or (getf candidate :category)
                        (getf candidate :kind)
                        :general)))
         (attribute (operator-memory-normalize-attribute
                     (or (getf candidate :attribute)
                         (getf candidate :name)
                         (getf candidate :key)
                         "fact")))
         (value (or (getf candidate :value)
                    (getf candidate :fact)
                    (getf candidate :content)
                    ""))
         (summary (or (getf candidate :summary)
                      (getf candidate :evidence)
                      (format nil "~A: ~A" attribute value)))
         (confidence (or (getf candidate :confidence) 0.5)))
    (list :memory-id (operator-memory-entry-id category attribute)
          :kind :operator-memory
          :recorded-at (get-universal-time)
          :updated-at (get-universal-time)
          :thread-id (and thread (thread-id thread))
          :source-turn-id (and turn (turn-id turn))
          :category category
          :attribute attribute
          :value value
          :summary summary
          :confidence confidence
          :source :memory)))

(defun json-array-value (value)
  (cond
    ((null value) '())
    ((json-object-p value) (list (json-object->keyword-plist value)))
    ((listp value)
     (mapcar (lambda (entry)
               (if (json-object-p entry)
                   (json-object->keyword-plist entry)
                   entry))
             value))
    (t '())))

(defun parse-operator-memory-extraction-response (message)
  (let* ((decoded (ignore-errors (parse-json (or message "")))))
    (when (json-object-p decoded)
      (let* ((entries (json-array-value
                       (or (json-object-value decoded "memories")
                           (json-object-value decoded "entries")))))
        (remove nil
                (mapcar (lambda (entry)
                          (when (listp entry)
                            (list :category (or (getf entry :CATEGORY)
                                                (getf entry :category)
                                                :general)
                                  :attribute (or (getf entry :ATTRIBUTE)
                                                 (getf entry :attribute)
                                                 (getf entry :KEY)
                                                 (getf entry :key)
                                                 "fact")
                                  :value (or (getf entry :VALUE)
                                             (getf entry :value)
                                             (getf entry :FACT)
                                             (getf entry :fact)
                                             "")
                                  :summary (or (getf entry :SUMMARY)
                                               (getf entry :summary)
                                               (getf entry :EVIDENCE)
                                               (getf entry :evidence))
                                  :confidence (or (getf entry :CONFIDENCE)
                                                  (getf entry :confidence)
                                                  0.5))))
                        entries))))))

(defun operator-memory-extraction-prompt (prompt assistant-message)
  (format nil
          "Analyze the completed exchange below and decide whether it contains durable facts worth remembering about the operator. Only remember stable identity, preferences, self-description, attribution, or persistent working style. Do not remember transient task details, one-off calculator values, temporary incidents, or implementation specifics unless they clearly describe a durable operator preference. Return your outer provider response with message containing only JSON in the form {\"memories\":[{\"category\":\"identity|preference|self-description|attribution|working-style\",\"attribute\":\"stable_attribute_name\",\"value\":\"remembered fact\",\"summary\":\"short evidence summary\",\"confidence\":0.0}]}. Use an empty memories array when nothing durable should be remembered.~%~%User message: ~A~%Assistant response: ~A"
          (or prompt "")
          (or assistant-message "")))

(defun remember-operator-memory-candidates (session thread turn candidates)
  (let ((environment (session-bound-environment session))
        (recorded '()))
    (when environment
      (dolist (candidate candidates)
        (let ((entry (make-operator-memory-entry thread turn candidate)))
          (upsert-environment-memory-entry environment entry)
          (push entry recorded)
          (append-session-event session
                                :operator-memory-entry-recorded
                                (compact-operator-memory-entry entry)
                                :family :assistant
                                :entity-id (getf entry :memory-id)
                                :thread-id (and thread (thread-id thread))
                                :turn-id (and turn (turn-id turn))
                                :visibility :operator)))
      (nreverse recorded))))

(defun infer-operator-memory (session thread turn prompt assistant-message &key provider)
  (let* ((environment (session-bound-environment session))
         (resolved-provider
           (or provider
               (when environment
                 (let* ((route (ignore-errors
                                 (select-environment-provider-profile prompt
                                                                     :environment environment
                                                                     :session session)))
                        (profile (and route (getf route :selected-profile))))
                   (and profile (ignore-errors (provider-from-profile profile))))))))
    (when resolved-provider
      (let* ((request (make-provider-request-from-session
                       (operator-memory-extraction-prompt prompt assistant-message)
                       session
                       :thread thread
                       :turn turn
                       :operator-mode :conversation
                       :stream-p nil))
             (response (ignore-errors (send-provider-request resolved-provider request)))
             (candidates (and response
                              (parse-operator-memory-extraction-response
                               (assistant-response-message response)))))
        (append-session-event session
                              :operator-memory-inference
                              (list :candidate-count (length candidates)
                                    :prompt (provider-summary-content prompt)
                                    :response-preview (and response
                                                           (provider-summary-content
                                                            (assistant-response-message response))))
                              :family :assistant
                              :entity-id (and turn (turn-id turn))
                              :thread-id (and thread (thread-id thread))
                              :turn-id (and turn (turn-id turn))
                              :visibility :operator)
        (remember-operator-memory-candidates session thread turn candidates)))))

(defun self-improvement-prompt-p (prompt)
  (let ((tokens (prompt-keyword-tokens prompt)))
    (or (intersection tokens
                      '("improve" "improvement" "quality" "benchmark" "benchmarks"
                        "eval" "evaluation" "reasoning" "capability" "capabilities"
                        "engineering" "performance" "agent" "orchestration")
                      :test #'string=)
        nil)))

(defun compact-retrieval-intent-summary (intent)
  (cond
    ((null intent) nil)
    ((typep intent 'retrieval-intent)
     (list :category (retrieval-intent-category intent)
           :domains (copy-list (or (retrieval-intent-domains intent) '()))
           :historical-p (retrieval-intent-historical-p intent)
           :governance-context-p (retrieval-intent-governance-context-p intent)
           :source-context-p (retrieval-intent-source-context-p intent)
           :mutation-likely-p (retrieval-intent-mutation-likely-p intent)))
    ((listp intent)
     (list :category (getf intent :category)
           :domains (copy-list (or (getf intent :domains) '()))
           :historical-p (getf intent :historical-p)
           :governance-context-p (getf intent :governance-context-p)
           :source-context-p (getf intent :source-context-p)
           :mutation-likely-p (getf intent :mutation-likely-p)))
    (t nil)))

(defun prior-memory-similarity-entry (prompt entry)
  (let* ((score (token-overlap-score prompt (or (getf entry :prompt) ""))))
    (when (> score 0)
      (append (list :score score
                    :source :memory)
              entry))))

(defun evaluation-family-improvement-proposals (family-id)
  (case family-id
    (:parallel-orchestration
     '((:kind :parallel-execution-hardening
        :statement "Harden multi-worker execution against contention, scheduling drift, and timeout-sensitive orchestration paths.")))
    (:long-horizon
     '((:kind :resume-plan-hardening
        :statement "Strengthen long-horizon resume checkpoints and plan continuity validation across follow-up turns.")))
    (:governed-mutation
     '((:kind :governed-mutation-safety
        :statement "Tighten approval, evidence, and validation checks around governed mutation flows before execution.")))
    (:runtime-debugging
     '((:kind :runtime-debugging-depth
        :statement "Deepen runtime-state retrieval and incident-aware debugging guidance for live-image investigations.")))
    (:repo-q-and-a
     '((:kind :repo-grounding
        :statement "Improve repository grounding and evidence ranking so repo explanations stay tightly coupled to authoritative context.")))
    (:followup-recovery
     '((:kind :followup-recovery-resilience
        :statement "Improve recovery continuity so resumed work preserves intent, evidence, and validation posture through follow-up turns.")))
    (:self-improvement
     '((:kind :self-improvement-coverage
        :statement "Expand reflective quality signals so the system can propose sharper improvements from its own outcomes.")))
    (t
     '((:kind :evaluation-remediation
        :statement "Investigate the failed evaluation family and turn the failure mode into a durable remediation or playbook.")))))

(defun compact-evaluation-failure-entry (entry &optional score)
  (list :source :evaluation-failure
        :memory-id (getf entry :memory-id)
        :family-id (getf entry :family-id)
        :label (getf entry :label)
        :score score
        :notes (getf entry :notes)
        :improvement-proposals (copy-tree (or (getf entry :improvement-proposals) '()))))

(defun evaluation-failure-entry-document-text (entry)
  (format nil "~{~A ~}"
          (remove nil
                  (list (getf entry :label)
                        (getf entry :description)
                        (getf entry :notes)
                        (mapcar (lambda (proposal)
                                  (getf proposal :statement))
                                (or (getf entry :improvement-proposals) '()))))))

(defun ranked-evaluation-failure-entries (prompt session)
  (let* ((failures (remove-if-not #'environment-memory-evaluation-failure-entry-p
                                  (environment-memory-entries session)))
         (meta-prompt-p (self-improvement-prompt-p prompt))
         (scored (remove nil
                         (mapcar (lambda (entry)
                                   (let* ((keyword-score (token-overlap-score prompt
                                                                              (evaluation-failure-entry-document-text entry)))
                                          (score (+ keyword-score
                                                    (if meta-prompt-p 3 0)
                                                    (max 0 (round (* 10 (- 1.0 (or (getf entry :score) 0.0))))))))
                                     (when (> score 0)
                                       (compact-evaluation-failure-entry entry score))))
                                 failures))))
    (subseq (sort scored #'>
                  :key (lambda (entry) (or (getf entry :score) 0)))
            0
            (min 3 (length scored)))))

(defun similarity-entry-rank (entry)
  (+ (* 10 (or (getf entry :score) 0))
     (if (eq (getf entry :status) :completed) 1 0)
     (if (eq (getf entry :source) :memory) 2 0)
     (if (> (or (getf entry :incident-count) 0) 0) -1 0)))

(defun sort-prior-turn-similarities (entries)
  (sort entries #'>
        :key #'similarity-entry-rank))

(defun similarity-entry-key (entry)
  (or (getf entry :turn-id)
      (getf entry :memory-id)
      (getf entry :prompt)))

(defun deduplicate-prior-similarities (entries)
  (let ((seen '())
        (deduplicated '()))
    (dolist (entry entries)
      (let ((key (similarity-entry-key entry)))
        (unless (member key seen :test #'equal)
          (push key seen)
          (push entry deduplicated))))
    (nreverse deduplicated)))

(defun prior-outcome-success-p (entry)
  (and (eq (getf entry :status) :completed)
       (= (or (getf entry :incident-count) 0) 0)))

(defun prior-outcome-failure-p (entry)
  (or (member (getf entry :status) '(:failed :interrupted) :test #'eq)
      (> (or (getf entry :incident-count) 0) 0)
      (> (or (getf entry :deferred-weakly-grounded-operation-count) 0) 0)))

(defun compact-prior-outcome-entry (entry)
  (list :source (getf entry :source)
        :turn-id (getf entry :turn-id)
        :memory-id (getf entry :memory-id)
        :score (getf entry :score)
        :status (getf entry :status)
        :prompt (provider-summary-content (or (getf entry :prompt) ""))
        :assistant-message (provider-summary-content (or (getf entry :assistant-message) ""))
        :incident-count (getf entry :incident-count)
        :weakly-grounded-operation-count (getf entry :weakly-grounded-operation-count)
        :deferred-weakly-grounded-operation-count
        (getf entry :deferred-weakly-grounded-operation-count)
        :work-item-status (getf entry :work-item-status)
        :retrieval-category (getf entry :retrieval-category)
        :execution-mode (getf entry :execution-mode)
        :validation-mode (getf entry :validation-mode)
        :agenda-primary-step (getf entry :agenda-primary-step)
        :reuse-recommendation (getf entry :reuse-recommendation)))

(defun strategy-pattern-from-entry (entry)
  (when (or (getf entry :execution-mode)
            (getf entry :validation-mode)
            (getf entry :agenda-primary-step))
    (list :execution-mode (getf entry :execution-mode)
          :validation-mode (getf entry :validation-mode)
          :agenda-primary-step (getf entry :agenda-primary-step))))

(defun failure-cluster-signature (entry)
  (list :retrieval-category (getf entry :retrieval-category)
        :incident-heavy-p (> (or (getf entry :incident-count) 0) 0)
        :weak-grounding-p (> (or (getf entry :deferred-weakly-grounded-operation-count) 0) 0)
        :work-item-status (getf entry :work-item-status)))

(defun failure-cluster-title (signature)
  (format nil "~A / incidents=~A / weak-grounding=~A"
          (or (getf signature :retrieval-category) :general)
          (if (getf signature :incident-heavy-p) :yes :no)
          (if (getf signature :weak-grounding-p) :yes :no)))

(defun failure-cluster-guidance (signature)
  (let ((guidance '()))
    (when (getf signature :incident-heavy-p)
      (push "Inspect incident evidence and recovery history before repeating this path." guidance))
    (when (getf signature :weak-grounding-p)
      (push "Collect stronger workspace/runtime evidence before proposing mutations." guidance))
    (when (getf signature :work-item-status)
      (push (format nil "Pay attention to workflow posture ~A when revisiting similar work."
                    (getf signature :work-item-status))
            guidance))
    (if guidance
        (format nil "~{~A~^ ~}" (nreverse guidance))
        "Recurring failure pattern detected.")))

(defun failure-cluster-improvement-proposals (signature)
  (let ((proposals '()))
    (when (getf signature :incident-heavy-p)
      (push (list :kind :incident-preflight
                  :statement "Add incident-aware preflight checks before mutating along this path.")
            proposals))
    (when (getf signature :weak-grounding-p)
      (push (list :kind :grounding-hardening
                  :statement "Require stronger evidence collection before allowing similar mutation proposals.")
            proposals))
    (when (getf signature :work-item-status)
      (push (list :kind :workflow-visibility
                  :statement "Surface workflow state earlier so blocked or validation-heavy paths are obvious before execution.")
            proposals))
    (nreverse proposals)))

(defun derive-failure-cluster-entry (signature failures existing-cluster)
  (let* ((sample-prompts (subseq (remove-duplicates
                                  (remove nil (mapcar (lambda (entry) (getf entry :prompt))
                                                      failures))
                                  :test #'string=)
                                 0
                                 (min 3 (length (remove-duplicates
                                                 (remove nil (mapcar (lambda (entry) (getf entry :prompt))
                                                                     failures))
                                                 :test #'string=)))))
         (cluster-key (or (and existing-cluster (getf existing-cluster :cluster-key))
                          (make-memory-entry-id))))
    (append (copy-list signature)
            (list :kind :failure-cluster
                  :memory-id cluster-key
                  :cluster-key cluster-key
                  :title (failure-cluster-title signature)
                  :recorded-at (get-universal-time)
                  :failure-count (length failures)
                  :sample-prompts sample-prompts
                  :guidance (failure-cluster-guidance signature)
                  :improvement-proposals (failure-cluster-improvement-proposals signature)))))

(defun increment-pattern-count (table pattern)
  (let* ((existing (assoc pattern table :test #'equal))
         (count (if existing (1+ (cdr existing)) 1)))
    (if existing
        (setf (cdr existing) count)
        (push (cons pattern count) table))
    table))

(defun derive-prior-strategy-patterns (entries)
  (let ((counts '()))
    (dolist (entry entries)
      (let ((pattern (strategy-pattern-from-entry entry)))
        (when pattern
          (setf counts (increment-pattern-count counts pattern)))))
    (mapcar (lambda (entry)
              (append (copy-list (car entry))
                      (list :count (cdr entry))))
            (sort counts #'>
                  :key #'cdr))))

(defun turn-outcome-playbook-signature (entry)
  (list :retrieval-category (getf entry :retrieval-category)
        :execution-mode (getf entry :execution-mode)
        :validation-mode (getf entry :validation-mode)
        :agenda-primary-step (getf entry :agenda-primary-step)))

(defun playbook-entry-key (entry)
  (or (getf entry :playbook-key)
      (getf entry :memory-id)))

(defun playbook-title (signature)
  (format nil "~A / ~A / ~A"
          (or (getf signature :retrieval-category) :general)
          (or (getf signature :execution-mode) :unspecified)
          (or (getf signature :validation-mode) :unspecified)))

(defun compact-playbook-entry (entry &optional score)
  (list :source :playbook
        :playbook-key (getf entry :playbook-key)
        :title (getf entry :title)
        :score score
        :retrieval-category (getf entry :retrieval-category)
        :intent (copy-tree (getf entry :intent))
        :execution-mode (getf entry :execution-mode)
        :validation-mode (getf entry :validation-mode)
        :agenda-primary-step (getf entry :agenda-primary-step)
        :success-count (getf entry :success-count)
        :failure-count (getf entry :failure-count)
        :orchestration-pattern-p (getf entry :orchestration-pattern-p)
        :decomposition-pattern-p (getf entry :decomposition-pattern-p)
        :merge-policy (getf entry :merge-policy)
        :parallel-task-count (getf entry :parallel-task-count)
        :ownership-explicit-p (getf entry :ownership-explicit-p)
        :planning-phases (copy-list (or (getf entry :planning-phases) '()))
        :phase-count (getf entry :phase-count)
        :reuse-recommendation (getf entry :reuse-recommendation)
        :guidance (getf entry :guidance)
        :sample-prompts (copy-list (or (getf entry :sample-prompts) '()))))

(defun playbook-guidance (success-count failure-count execution-mode validation-mode)
  (cond
    ((> failure-count success-count)
     "Use this pattern cautiously; similar work has failed often enough that extra evidence and validation are warranted.")
    ((and execution-mode validation-mode)
     (format nil "Preferred pattern: execute with ~A and validate with ~A when the current evidence matches."
             execution-mode
             validation-mode))
    (execution-mode
     (format nil "Preferred execution pattern: ~A." execution-mode))
    (t
     "Reusable historical pattern available.")))

(defun derive-playbook-entry (signature turn-entries existing-playbook)
  (let* ((successes (remove-if-not #'prior-outcome-success-p turn-entries))
         (failures (remove-if-not #'prior-outcome-failure-p turn-entries))
         (representative (first turn-entries))
         (sample-prompts (subseq (remove-duplicates
                                  (remove nil (mapcar (lambda (entry) (getf entry :prompt))
                                                      turn-entries))
                                  :test #'string=)
                                 0
                                 (min 3 (length (remove-duplicates
                                                 (remove nil (mapcar (lambda (entry) (getf entry :prompt))
                                                                     turn-entries))
                                                 :test #'string=)))))
         (playbook-key (or (and existing-playbook (getf existing-playbook :playbook-key))
                           (make-memory-entry-id))))
    (append (copy-list signature)
            (list :kind :playbook
                  :memory-id playbook-key
                  :playbook-key playbook-key
                  :title (playbook-title signature)
                  :recorded-at (get-universal-time)
                  :intent (copy-tree (getf representative :intent))
                  :success-count (length successes)
                  :failure-count (length failures)
                  :sample-prompts sample-prompts
                  :reuse-recommendation (if failures
                                            :reuse-with-caution
                                            :reuse-success-patterns)
                  :guidance (playbook-guidance (length successes)
                                               (length failures)
                                               (getf signature :execution-mode)
                                               (getf signature :validation-mode))))))

(defun decomposition-playbook-signature (entry)
  (list :retrieval-category (getf entry :retrieval-category)
        :execution-mode (getf entry :execution-mode)
        :validation-mode (getf entry :validation-mode)
        :planning-phases (copy-list (or (getf entry :planning-phases) '()))))

(defun decomposition-playbook-title (signature)
  (format nil "~A / decomposition / ~{~A~^ -> ~}"
          (or (getf signature :retrieval-category) :general)
          (or (getf signature :planning-phases) '(:inspect))))

(defun decomposition-playbook-guidance (signature)
  (format nil "Reusable long-horizon pattern: walk the work through phases ~{~A~^, ~} while preserving governed checkpoints and resumability."
          (or (getf signature :planning-phases) '(:inspect))))

(defun derive-decomposition-playbook-entry (signature turn-entries existing-playbook)
  (let* ((successes (remove-if-not #'prior-outcome-success-p turn-entries))
         (failures (remove-if-not #'prior-outcome-failure-p turn-entries))
         (representative (first turn-entries))
         (sample-prompts (subseq (remove-duplicates
                                  (remove nil (mapcar (lambda (entry) (getf entry :prompt))
                                                      turn-entries))
                                  :test #'string=)
                                 0
                                 (min 3 (length (remove-duplicates
                                                 (remove nil (mapcar (lambda (entry) (getf entry :prompt))
                                                                     turn-entries))
                                                 :test #'string=)))))
         (playbook-key (or (and existing-playbook (getf existing-playbook :playbook-key))
                           (make-memory-entry-id))))
    (append (copy-list signature)
            (list :kind :decomposition-playbook
                  :memory-id playbook-key
                  :playbook-key playbook-key
                  :title (decomposition-playbook-title signature)
                  :recorded-at (get-universal-time)
                  :intent (copy-tree (getf representative :intent))
                  :success-count (length successes)
                  :failure-count (length failures)
                  :decomposition-pattern-p t
                  :phase-count (length (or (getf signature :planning-phases) '()))
                  :sample-prompts sample-prompts
                  :reuse-recommendation (if failures
                                            :reuse-with-caution
                                            :reuse-success-patterns)
                  :guidance (decomposition-playbook-guidance signature)))))

(defun orchestration-playbook-signature (entry)
  (list :merge-policy (getf entry :merge-policy)
        :parallel-task-count (getf entry :parallel-task-count)
        :ownership-explicit-p (getf entry :ownership-explicit-p)))

(defun orchestration-playbook-title (signature)
  (format nil "parallel / ~A / tasks=~D / ownership=~A"
          (or (getf signature :merge-policy) :unspecified)
          (or (getf signature :parallel-task-count) 0)
          (if (getf signature :ownership-explicit-p) :explicit :implicit)))

(defun orchestration-playbook-guidance (signature)
  (format nil "Reusable parallel execution pattern: decompose into ~D tasks, keep ownership scopes ~A, and finish with ~A."
          (or (getf signature :parallel-task-count) 0)
          (if (getf signature :ownership-explicit-p) "explicit" "implicit")
          (or (getf signature :merge-policy) :unspecified)))

(defun derive-orchestration-playbook-entry (signature orchestration-entries existing-playbook)
  (let* ((playbook-key (or (and existing-playbook (getf existing-playbook :playbook-key))
                           (make-memory-entry-id)))
         (representative (first orchestration-entries))
         (sample-prompts (subseq (remove-duplicates
                                  (remove nil
                                          (mapcar (lambda (entry)
                                                    (getf entry :prompt))
                                                  orchestration-entries))
                                  :test #'string=)
                                 0
                                 (min 3 (length (remove-duplicates
                                                 (remove nil
                                                         (mapcar (lambda (entry)
                                                                   (getf entry :prompt))
                                                                 orchestration-entries))
                                                 :test #'string=))))))
    (append (copy-list signature)
            (list :kind :orchestration-playbook
                  :memory-id playbook-key
                  :playbook-key playbook-key
                  :title (orchestration-playbook-title signature)
                  :recorded-at (get-universal-time)
                  :intent (copy-tree (or (getf representative :intent)
                                         '(:category :code-change
                                           :domains (:workspace :workflow)
                                           :governance-context-p t
                                           :source-context-p t
                                           :mutation-likely-p t)))
                  :retrieval-category :code-change
                  :execution-mode :parallel-governed
                  :validation-mode :required
                  :agenda-primary-step (list :kind :review-orchestration
                                             :priority :high)
                  :success-count (length orchestration-entries)
                  :failure-count 0
                  :orchestration-pattern-p t
                  :reuse-recommendation :reuse-success-patterns
                  :guidance (orchestration-playbook-guidance signature)
                  :sample-prompts sample-prompts))))

(defun refresh-environment-playbooks (environment)
  (let* ((entries (or (environment-memory environment) '()))
         (turn-entries (remove-if-not #'environment-memory-turn-outcome-entry-p entries))
         (existing-playbooks (remove-if-not #'environment-memory-playbook-entry-p entries))
         (signatures (remove-duplicates (mapcar #'turn-outcome-playbook-signature turn-entries)
                                        :test #'equal))
         (playbooks
           (mapcar (lambda (signature)
                     (let* ((members (remove-if-not (lambda (entry)
                                                     (equal (turn-outcome-playbook-signature entry)
                                                            signature))
                                                   turn-entries))
                            (existing (find signature existing-playbooks
                                            :key #'turn-outcome-playbook-signature
                                            :test #'equal)))
                       (derive-playbook-entry signature members existing)))
                   signatures)))
    (setf (environment-memory environment)
          (append (remove-if #'environment-memory-playbook-entry-p entries)
                  playbooks))
    playbooks))

(defun refresh-environment-orchestration-playbooks (environment)
  (let* ((entries (or (environment-memory environment) '()))
         (orchestration-entries (remove-if-not #'environment-memory-orchestration-outcome-entry-p entries))
         (existing-playbooks (remove-if-not #'environment-memory-orchestration-playbook-entry-p entries))
         (signatures (remove-duplicates (mapcar #'orchestration-playbook-signature orchestration-entries)
                                        :test #'equal))
         (playbooks
           (mapcar (lambda (signature)
                     (let* ((members (remove-if-not (lambda (entry)
                                                     (equal (orchestration-playbook-signature entry)
                                                            signature))
                                                   orchestration-entries))
                            (existing (find signature existing-playbooks
                                            :key #'orchestration-playbook-signature
                                            :test #'equal)))
                       (derive-orchestration-playbook-entry signature members existing)))
                   signatures)))
    (setf (environment-memory environment)
          (append (remove-if #'environment-memory-orchestration-playbook-entry-p entries)
                  playbooks))
    playbooks))

(defun refresh-environment-decomposition-playbooks (environment)
  (let* ((entries (or (environment-memory environment) '()))
         (turn-entries (remove-if-not #'environment-memory-turn-outcome-entry-p entries))
         (existing-playbooks (remove-if-not #'environment-memory-decomposition-playbook-entry-p entries))
         (signatures (remove-duplicates
                      (remove nil
                              (mapcar (lambda (entry)
                                        (when (getf entry :planning-phases)
                                          (decomposition-playbook-signature entry)))
                                      turn-entries))
                      :test #'equal))
         (playbooks
           (mapcar (lambda (signature)
                     (let* ((members (remove-if-not (lambda (entry)
                                                     (equal (decomposition-playbook-signature entry)
                                                            signature))
                                                   turn-entries))
                            (existing (find signature existing-playbooks
                                            :key #'decomposition-playbook-signature
                                            :test #'equal)))
                       (derive-decomposition-playbook-entry signature members existing)))
                   signatures)))
    (setf (environment-memory environment)
          (append (remove-if #'environment-memory-decomposition-playbook-entry-p entries)
                  playbooks))
    playbooks))

(defun refresh-environment-failure-clusters (environment)
  (let* ((entries (or (environment-memory environment) '()))
         (turn-entries (remove-if-not #'environment-memory-turn-outcome-entry-p entries))
         (failures (remove-if-not #'prior-outcome-failure-p turn-entries))
         (existing-clusters (remove-if-not #'environment-memory-failure-cluster-entry-p entries))
         (signatures (remove-duplicates (mapcar #'failure-cluster-signature failures)
                                        :test #'equal))
         (clusters
           (mapcar (lambda (signature)
                     (let* ((members (remove-if-not (lambda (entry)
                                                     (equal (failure-cluster-signature entry)
                                                            signature))
                                                   failures))
                            (existing (find signature existing-clusters
                                            :key #'failure-cluster-signature
                                            :test #'equal)))
                       (derive-failure-cluster-entry signature members existing)))
                   signatures)))
    (setf (environment-memory environment)
          (append (remove-if #'environment-memory-failure-cluster-entry-p entries)
                  clusters))
    clusters))

(defun upsert-environment-memory-entry (environment entry)
  (let* ((entries (or (environment-memory environment) '()))
         (entry-key (or (getf entry :turn-id)
                        (getf entry :memory-id)))
         (updated (if entry-key
                      (remove entry-key entries
                              :key (lambda (candidate)
                                     (or (getf candidate :turn-id)
                                         (getf candidate :memory-id)))
                              :test #'string=)
                      entries)))
    (setf (environment-memory environment)
          (append updated (list entry)))
    entry))

(defun remember-turn-outcome-memory (session thread turn prompt cognition-bundle assistant-message)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let* ((detail (turn-detail session (turn-id turn)))
             (summary (getf detail :detail-summary))
             (entry (list :memory-id (make-memory-entry-id)
                          :kind :turn-outcome
                          :recorded-at (get-universal-time)
                          :thread-id (thread-id thread)
                          :turn-id (turn-id turn)
                          :status (turn-status turn)
                          :prompt prompt
                          :assistant-message assistant-message
                          :incident-count (length (turn-incidents session (turn-id turn)))
                          :weakly-grounded-operation-count
                          (getf summary :weakly-grounded-operation-count)
                          :deferred-weakly-grounded-operation-count
                          (getf summary :deferred-weakly-grounded-operation-count)
                          :work-item-status (getf summary :work-item-status)
                          :retrieval-category
                          (getf (getf (cognition-bundle-retrieval-dossier cognition-bundle) :intent) :category)
                          :intent
                          (compact-retrieval-intent-summary
                           (getf (cognition-bundle-retrieval-dossier cognition-bundle) :intent))
                          :execution-mode
                          (getf (cognition-bundle-execution-strategy cognition-bundle) :mode)
                          :validation-mode
                          (getf (cognition-bundle-validation-strategy cognition-bundle) :mode)
                          :planning-phases
                          (remove nil
                                  (mapcar (lambda (step) (getf step :phase))
                                          (or (getf (cognition-bundle-planning-brief cognition-bundle) :ordered-steps) '())))
                          :agenda-primary-step
                          (getf (cognition-bundle-action-agenda cognition-bundle) :primary-step)
                          :reuse-recommendation
                          (getf (cognition-bundle-prior-outcome-brief cognition-bundle) :reuse-recommendation)
                          :source :memory)))
        (upsert-environment-memory-entry environment entry)
        (refresh-environment-playbooks environment)
        (refresh-environment-decomposition-playbooks environment)
        (refresh-environment-orchestration-playbooks environment)
        (refresh-environment-failure-clusters environment)
        (refresh-environment-agent-domain environment session)
        (append-session-event session
                              :memory-entry-recorded
                              (compact-prior-outcome-entry entry)
                              :family :assistant
                              :entity-id (getf entry :memory-id)
                              :thread-id (thread-id thread)
                              :turn-id (turn-id turn)
                              :visibility :operator)
        entry))))

(defun remember-orchestration-outcome-memory (session group-summary &key prompt)
  (let ((environment (session-bound-environment session)))
    (when (and environment
               (getf group-summary :group-id))
      (let* ((group-id (getf group-summary :group-id))
             (entry (list :memory-id (format nil "orchestration-~A" group-id)
                          :kind :orchestration-outcome
                          :recorded-at (get-universal-time)
                          :group-id group-id
                          :prompt (or prompt
                                      (getf (getf group-summary :shared-context) :goal)
                                      (format nil "Parallel orchestration group ~A" group-id))
                          :merge-policy (getf group-summary :merge-policy)
                          :parallel-task-count (getf group-summary :task-count)
                          :ownership-explicit-p (getf group-summary :ownership-explicit-p)
                          :worker-count (getf group-summary :distinct-worker-count)
                          :shared-context (copy-tree (or (getf group-summary :shared-context) '()))
                          :intent '(:category :code-change
                                    :domains (:workspace :workflow)
                                    :governance-context-p t
                                    :source-context-p t
                                    :mutation-likely-p t)
                          :source :memory)))
        (upsert-environment-memory-entry environment entry)
        (refresh-environment-orchestration-playbooks environment)
        (refresh-environment-agent-domain environment session)
        (append-session-event session
                              :orchestration-memory-recorded
                              entry
                              :family :assistant
                              :entity-id (getf entry :memory-id)
                              :visibility :operator)
        entry))))

(defun remember-evaluation-report-memory (session report)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let* ((generated-at (or (getf report :generated-at) (get-universal-time)))
             (run-entry (list :memory-id (format nil "evaluation-run-~A" generated-at)
                              :kind :evaluation-run
                              :recorded-at generated-at
                              :family-count (getf report :family-count)
                              :implemented-family-count (getf report :implemented-family-count)
                              :passed-family-count (getf report :passed-family-count)
                              :implemented-score (getf report :implemented-score)
                              :source :memory))
             (failed-family-entries
               (mapcar (lambda (entry)
                         (list :memory-id (format nil "evaluation-failure-~A-~A"
                                                  (getf entry :family-id)
                                                  generated-at)
                               :kind :evaluation-failure
                               :recorded-at generated-at
                               :family-id (getf entry :family-id)
                               :label (getf entry :label)
                               :description (getf entry :description)
                               :status (getf entry :status)
                               :score (getf entry :score)
                               :duration-seconds (getf entry :duration-seconds)
                               :notes (getf entry :notes)
                               :improvement-proposals (evaluation-family-improvement-proposals
                                                       (getf entry :family-id))
                               :source :memory))
                       (remove-if-not (lambda (entry)
                                        (eq (getf entry :status) :failed))
                                      (or (getf report :results) '())))))
        (upsert-environment-memory-entry environment run-entry)
        (dolist (entry failed-family-entries)
          (upsert-environment-memory-entry environment entry))
        (refresh-environment-agent-domain environment session)
        (append-session-event session
                              :evaluation-memory-recorded
                              (list :run-entry (getf run-entry :memory-id)
                                    :failure-count (length failed-family-entries))
                              :family :assistant
                              :entity-id (getf run-entry :memory-id)
                              :visibility :operator)
        (list :run-entry run-entry
              :failure-entries failed-family-entries)))))

(defun prior-outcome-avoidance-guidance (failures)
  (let ((guidance '()))
    (when (find-if (lambda (entry)
                     (> (or (getf entry :incident-count) 0) 0))
                   failures)
      (push (list :kind :incident-repeat
                  :statement "Similar prior work triggered incidents; inspect incident evidence before repeating the same mutation path.")
            guidance))
    (when (find-if (lambda (entry)
                     (> (or (getf entry :deferred-weakly-grounded-operation-count) 0) 0))
                   failures)
      (push (list :kind :weak-grounding-repeat
                  :statement "Similar prior work produced weakly grounded mutation proposals; collect stronger workspace/runtime evidence before proposing mutations.")
            guidance))
    (nreverse guidance)))

(defun compact-failure-cluster-entry (entry &optional score)
  (list :source :failure-cluster
        :cluster-key (getf entry :cluster-key)
        :title (getf entry :title)
        :score score
        :retrieval-category (getf entry :retrieval-category)
        :failure-count (getf entry :failure-count)
        :guidance (getf entry :guidance)
        :improvement-proposals (copy-tree (or (getf entry :improvement-proposals) '()))
        :sample-prompts (copy-list (or (getf entry :sample-prompts) '()))))

(defun ranked-failure-cluster-entries (prompt session)
  (let* ((clusters (remove-if-not #'environment-memory-failure-cluster-entry-p
                                  (environment-memory-entries session)))
         (scored (remove nil
                         (mapcar (lambda (entry)
                                   (let ((score (token-overlap-score prompt
                                                                     (format nil "~{~A ~}"
                                                                             (remove nil
                                                                                     (list (getf entry :title)
                                                                                           (getf entry :guidance)
                                                                                           (first (getf entry :sample-prompts))))))))
                                     (when (> score 0)
                                       (compact-failure-cluster-entry entry score))))
                                 clusters))))
    (subseq (sort scored #'>
                  :key (lambda (entry) (or (getf entry :score) 0)))
            0
            (min 3 (length scored)))))

(defun playbook-document-text (entry)
  (format nil "~{~A ~}"
          (remove nil
                  (list (getf entry :title)
                        (getf entry :guidance)
                        (first (getf entry :sample-prompts))))))

(defun playbook-category-bonus (prompt-intent entry)
  (if (eq (retrieval-intent-category prompt-intent)
          (getf entry :retrieval-category))
      6
      0))

(defun playbook-domain-bonus (prompt-intent entry)
  (let* ((entry-intent (getf entry :intent))
         (entry-domains (or (getf entry-intent :domains) '()))
         (prompt-domains (or (retrieval-intent-domains prompt-intent) '())))
    (* 2 (length (intersection prompt-domains entry-domains :test #'eq)))))

(defun playbook-governance-bonus (prompt-intent entry)
  (let ((entry-intent (getf entry :intent)))
    (if (and (retrieval-intent-governance-context-p prompt-intent)
             (getf entry-intent :governance-context-p))
        4
        0)))

(defun playbook-mutation-bonus (prompt-intent entry)
  (let ((entry-intent (getf entry :intent)))
    (if (and (retrieval-intent-mutation-likely-p prompt-intent)
             (getf entry-intent :mutation-likely-p))
        3
        0)))

(defun playbook-source-bonus (prompt-intent entry)
  (let ((entry-intent (getf entry :intent)))
    (if (and (retrieval-intent-source-context-p prompt-intent)
             (getf entry-intent :source-context-p))
        2
        0)))

(defun playbook-success-bonus (entry)
  (min 5 (or (getf entry :success-count) 0)))

(defun playbook-failure-penalty (entry)
  (* 3 (or (getf entry :failure-count) 0)))

(defun score-playbook-entry (prompt prompt-intent entry)
  (let* ((keyword-score (token-overlap-score prompt (playbook-document-text entry)))
         (category-bonus (playbook-category-bonus prompt-intent entry))
         (domain-bonus (playbook-domain-bonus prompt-intent entry))
         (governance-bonus (playbook-governance-bonus prompt-intent entry))
         (mutation-bonus (playbook-mutation-bonus prompt-intent entry))
         (source-bonus (playbook-source-bonus prompt-intent entry))
         (success-bonus (playbook-success-bonus entry))
         (failure-penalty (playbook-failure-penalty entry))
         (score (+ keyword-score
                   category-bonus
                   domain-bonus
                   governance-bonus
                   mutation-bonus
                   source-bonus
                   success-bonus
                   (- failure-penalty))))
    (when (> score 0)
      (let ((explanation
              (remove nil
                      (list (when (> category-bonus 0) :category-match)
                            (when (> domain-bonus 0) :domain-match)
                            (when (> governance-bonus 0) :governance-match)
                            (when (> mutation-bonus 0) :mutation-match)
                            (when (> source-bonus 0) :source-match)
                            (when (> success-bonus 0) :success-bias)
                            (when (> failure-penalty 0) :failure-penalty)))))
        (append (compact-playbook-entry entry score)
                (list :ranking-explanation explanation))))))

(defun ranked-playbook-entries (prompt session)
  (let* ((playbook-entries (remove-if-not (lambda (entry)
                                            (or (environment-memory-playbook-entry-p entry)
                                                (environment-memory-decomposition-playbook-entry-p entry)
                                                (environment-memory-orchestration-playbook-entry-p entry)))
                                          (environment-memory-entries session)))
         (prompt-intent (classify-retrieval-intent prompt :operator-mode :conversation))
         (scored (remove nil
                         (mapcar (lambda (entry)
                                   (score-playbook-entry prompt prompt-intent entry))
                                 playbook-entries))))
    (subseq (sort scored #'>
                  :key (lambda (entry) (or (getf entry :score) 0)))
            0
            (min 3 (length scored)))))

(defun build-prior-outcome-brief (session prompt &key current-turn-id)
  (let* ((candidate-turns
           (remove-if (lambda (turn)
                        (or (and current-turn-id
                                 (string= (turn-id turn) current-turn-id))
                            (null (turn-user-prompt session turn))))
                      (agent-session-turns session)))
         (memory-entries
           (remove-if-not #'environment-memory-turn-outcome-entry-p
                          (environment-memory-entries session)))
         (relevant-playbooks
           (ranked-playbook-entries prompt session))
         (relevant-failure-clusters
           (ranked-failure-cluster-entries prompt session))
         (relevant-evaluation-failures
           (ranked-evaluation-failure-entries prompt session))
         (similarities
           (sort-prior-turn-similarities
            (deduplicate-prior-similarities
             (append
              (remove nil
                      (mapcar (lambda (entry)
                                (prior-memory-similarity-entry prompt entry))
                              memory-entries))
              (remove nil
                      (mapcar (lambda (turn)
                                (prior-turn-similarity-entry session prompt turn))
                              candidate-turns))))))
         (similar-successes
           (mapcar #'compact-prior-outcome-entry
                   (subseq (remove-if-not #'prior-outcome-success-p similarities)
                           0
                           (min 3 (length (remove-if-not #'prior-outcome-success-p similarities))))))
         (similar-failures
           (mapcar #'compact-prior-outcome-entry
                   (subseq (remove-if-not #'prior-outcome-failure-p similarities)
                           0
                           (min 3 (length (remove-if-not #'prior-outcome-failure-p similarities))))))
         (strategy-patterns (derive-prior-strategy-patterns
                             (remove-if-not #'prior-outcome-success-p similarities)))
         (preferred-pattern (first strategy-patterns)))
    (list :mode :historical-analogy
          :memory-match-count (count :memory similarities :key (lambda (entry) (getf entry :source)) :test #'eq)
          :playbook-count (length relevant-playbooks)
          :playbooks relevant-playbooks
          :failure-cluster-count (length relevant-failure-clusters)
          :failure-clusters relevant-failure-clusters
          :evaluation-failure-count (length relevant-evaluation-failures)
          :evaluation-failures relevant-evaluation-failures
          :improvement-proposals (remove-duplicates
                                  (append (mapcan (lambda (entry)
                                                    (copy-list (or (getf entry :improvement-proposals) '())))
                                                  relevant-failure-clusters)
                                          (mapcan (lambda (entry)
                                                    (copy-list (or (getf entry :improvement-proposals) '())))
                                                  relevant-evaluation-failures))
                                  :test #'equal)
          :similar-successes similar-successes
          :similar-failures similar-failures
          :strategy-patterns strategy-patterns
          :preferred-playbook (first relevant-playbooks)
          :preferred-execution-mode (getf preferred-pattern :execution-mode)
          :preferred-validation-mode (getf preferred-pattern :validation-mode)
          :avoidance-guidance (prior-outcome-avoidance-guidance similar-failures)
          :reuse-recommendation
          (cond
            (similar-failures :reuse-with-caution)
            (similar-successes :reuse-success-patterns)
            (t :no-strong-prior-analogy)))))
