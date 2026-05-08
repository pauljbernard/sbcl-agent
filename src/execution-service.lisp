(in-package #:sbcl-agent)

(defparameter *stream-event-listener* nil)
(defparameter *default-ask-streaming* nil)

(declaim (special *runtime-governance-thread*
                  *runtime-governance-turn*
                  *runtime-governance-operation*))

(defun plist-value (plist indicator &optional default)
  (if (and (listp plist) (member indicator plist))
      (getf plist indicator)
      default))

(defun option-present-p (plist key)
  (and (listp plist)
       (member key plist)))

(defun remove-plist-key (plist key)
  (cond
    ((null plist) '())
    ((eq (first plist) key)
     (remove-plist-key (cddr plist) key))
    (t
     (list* (first plist)
            (second plist)
            (remove-plist-key (cddr plist) key)))))

(defun immediate-assistant-action-p (action)
  (case (assistant-action-type action)
    (:eval
     (not (mutating-eval-action-p action)))
    (:tool
     (let ((policy-id (assistant-action-policy-id action)))
       (and policy-id
            (not (assistant-action-requires-approval-p action))
            (not (governed-assistant-action-p action)))))
    (t nil)))

(defun split-assistant-actions (actions)
  (let ((immediate '())
        (staged '()))
    (dolist (action actions)
      (if (immediate-assistant-action-p action)
          (push action immediate)
          (push action staged)))
    (values (nreverse immediate) (nreverse staged))))

(defun calculator-focused-surface-context-p (surface-context)
  (let ((calculator (and (listp surface-context)
                         (getf surface-context :calculator))))
    (and (listp calculator)
         (getf calculator :focused))))

(defun prompt-contains-any-p (prompt needles)
  (some (lambda (needle)
          (search needle prompt :test #'char-equal))
        needles))

(defun digit-char-string-p (value)
  (and (stringp value)
       (= (length value) 1)
       (digit-char-p (char value 0))))

(defun extract-calculator-single-token (prompt)
  (let ((text (string-downcase (or prompt ""))))
    (when (and (search "calculator" text :test #'char=)
               (prompt-contains-any-p text '("press" "select" "enter" "type" "key" "button")))
      (or (loop for char across text
                when (digit-char-p char)
                  return (string char))
          (when (search "plus" text :test #'char=) "+")
          (when (search "minus" text :test #'char=) "-")
          (when (or (search "times" text :test #'char=)
                    (search "multiply" text :test #'char=))
            "*")
          (when (or (search "divide" text :test #'char=)
                    (search "over" text :test #'char=))
            "/")))))

(defun replace-all-substrings (text old new)
  (with-output-to-string (out)
    (loop with old-length = (length old)
          for start = 0 then (+ position old-length)
          for position = (search old text :start2 start :test #'char-equal)
          do (if position
                 (progn
                   (write-string text out :start start :end position)
                   (write-string new out))
                 (progn
                   (write-string text out :start start)
                   (loop-finish))))))

(defun normalize-calculator-expression-text (prompt)
  (let ((text (string-downcase (or prompt ""))))
    (dolist (pair '(("multiplied by" . "*")
                    ("times" . "*")
                    ("plus" . "+")
                    ("minus" . "-")
                    ("divided by" . "/")
                    ("divide by" . "/")
                    ("over" . "/")
                    ("open paren" . "(")
                    ("close paren" . ")")))
      (setf text (replace-all-substrings text (car pair) (cdr pair))))
    text))

(defun extract-calculator-expression (prompt)
  (let* ((text (normalize-calculator-expression-text prompt))
         (chars
           (loop for char across text
                 when (or (digit-char-p char)
                          (member char '(#\+ #\- #\* #\/ #\( #\) #\.)))
                   collect char into kept
                 when (and kept
                           (or (char= char #\Space)
                               (char= char #\Tab)
                               (char= char #\Newline)))
                   collect #\Space into kept
                 finally (return kept)))
         (raw (string-trim " " (coerce chars 'string))))
    (when (and (> (length raw) 0)
               (some #'digit-char-p raw)
               (or (prompt-contains-any-p text '("evaluate" "calculate" "compute"))
                   (find-if (lambda (char)
                              (member char '(#\+ #\- #\* #\/) :test #'char=))
                            raw)))
      (replace-all-substrings raw " " ""))))

(defun calculator-expression-request-p (prompt)
  (let ((text (string-downcase (or prompt ""))))
    (and (search "calculator" text :test #'char=)
         (or (prompt-contains-any-p text '("evaluate" "calculate" "compute"))
             (find-if (lambda (char)
                        (member char '(#\+ #\- #\* #\/ #\( #\)) :test #'char=))
                      text)
             (prompt-contains-any-p text '("times" "plus" "minus" "divide" "multiplied"))))))

(defun synthesize-calculator-actions-from-prompt (prompt surface-context)
  (when (calculator-focused-surface-context-p surface-context)
    (let ((token (extract-calculator-single-token prompt))
          (expression (extract-calculator-expression prompt)))
      (cond
        ((and (calculator-expression-request-p prompt)
              expression
              (> (length expression) 0))
         (list (make-assistant-action
                :type :tool
                :payload (list :tool-id :calculator/set-expression
                               :arguments (list :expression expression)))
               (make-assistant-action
                :type :tool
                :payload (list :tool-id :calculator/evaluate
                               :arguments (list :expression expression)))))
        ((and token
              (= (length token) 1))
         (list (make-assistant-action
                :type :tool
                :payload (list :tool-id :calculator/append-token
                               :arguments (list :token token)))))
        (t nil)))))

(defun effective-response-actions (response prompt surface-context session)
  (let ((actions (assistant-response-actions response)))
    (or actions
        (let ((fallback (synthesize-calculator-actions-from-prompt prompt surface-context)))
          (when fallback
            (append-session-event session
                                  :assistant-action-fallback-synthesized
                                  (list :prompt prompt
                                        :action-count (length fallback)
                                        :actions fallback)
                                  :family :assistant
                                  :visibility :operator))
          fallback)
        '())))

(defun direct-calculator-actions-for-prompt (prompt surface-context)
  (let ((actions (synthesize-calculator-actions-from-prompt prompt surface-context)))
    (and actions
         (every (lambda (action)
                  (and (eq (assistant-action-type action) :tool)
                       (let* ((payload (assistant-action-payload action))
                              (tool-id (or (getf payload :tool-id)
                                           (getf payload :TOOL-ID))))
                         (member tool-id
                                 '(:calculator/append-token
                                   :calculator/set-expression
                                   :calculator/evaluate
                                   :calculator/clear
                                   :calculator/backspace
                                   :calculator/set-mode
                                   :calculator/set-base
                                   :calculator/set-word-size
                                   :calculator/set-angle-unit)
                                 :test #'eq))))
                actions)
         actions)))

(defun calculator-action-expression (action)
  (let* ((payload (assistant-action-payload action))
         (arguments (or (getf payload :arguments)
                        (getf payload :ARGUMENTS))))
    (or (and (listp arguments) (getf arguments :expression))
        (and (listp arguments) (getf arguments :EXPRESSION)))))

(defun calculator-action-token (action)
  (let* ((payload (assistant-action-payload action))
         (arguments (or (getf payload :arguments)
                        (getf payload :ARGUMENTS))))
    (or (and (listp arguments) (getf arguments :token))
        (and (listp arguments) (getf arguments :TOKEN)))))

(defun direct-calculator-assistant-message (actions results)
  (let* ((first-action (first actions))
         (last-result (and results (getf (first (last results)) :result)))
         (latest-result-summary (and (listp last-result) (getf last-result :summary)))
         (latest-display-value (and (listp last-result) (getf last-result :display-value)))
         (token (and first-action (calculator-action-token first-action)))
         (expression (or (and first-action (calculator-action-expression first-action))
                         (and (> (length actions) 1)
                              (calculator-action-expression (second actions))))))
    (cond
      ((and expression latest-display-value)
       (format nil
               "Set the calculator expression to ~S and evaluated it. Result: ~A."
               expression
               latest-display-value))
      (latest-result-summary
       (format nil
               "Set the calculator expression to ~S and evaluated it. ~A"
               expression
               latest-result-summary))
      (token
       (format nil
               "Appended the token ~S in the focused calculator expression buffer."
               token))
      (expression
       (format nil
               "Set the focused calculator expression to ~S."
               expression))
      (t
       "Updated the focused calculator."))))

(defun run-direct-conversation-calculator-actions (session prompt actions
                                                    &key (source :say) (operator-mode :conversation)
                                                      surface-context surface-actions)
  (declare (ignore operator-mode))
  (let* ((thread (current-thread session)))
    (append-transcript-entry session :user prompt)
    (emit-conversation-progress (conversation-progress-phase source :started)
                                (list :prompt prompt
                                      :stream-p nil
                                      :thread-id (thread-id thread)
                                      :auto-routed-p t
                                      :direct-calculator-p t))
    (let* ((user-message (create-message session thread :user prompt
                                         :metadata (list :source source
                                                         :auto-routed-p t
                                                         :direct-calculator-p t
                                                         :surface-context surface-context
                                                         :surface-actions surface-actions)))
           (turn (start-turn session thread user-message
                             :metadata (list :source source
                                             :streamed-p nil
                                             :auto-routed-p t
                                             :direct-calculator-p t
                                             :surface-context surface-context
                                             :surface-actions surface-actions)))
           (immediate-results (execute-assistant-action-list actions session :thread thread :turn turn))
           (action-report (list :immediate-actions actions
                                :immediate-results immediate-results
                                :staged-actions '()
                                :deferred-actions '()
                                :action-assessments '()))
           (action-operations (record-assistant-action-operations session thread turn action-report))
           (assistant-content (direct-calculator-assistant-message actions immediate-results))
           (assistant-message (create-message session thread :assistant assistant-content
                                              :content-type :text
                                              :metadata (list :source source
                                                              :streamed-p nil
                                                              :auto-routed-p t
                                                              :direct-calculator-p t)))
           (completed-turn (complete-turn session
                                          thread
                                          turn
                                          assistant-message
                                          :status (turn-status-from-action-operations action-operations)
                                          :metadata (list :stream-event-count 0
                                                          :action-operation-ids (mapcar #'operation-id action-operations)
                                                          :auto-routed-p t
                                                          :direct-calculator-p t))))
      (append-transcript-entry session :assistant assistant-content)
      (append-session-event session
                            :conversation-calculator-control
                            (list :prompt prompt
                                  :action-count (length actions)
                                  :actions actions
                                  :result-count (length immediate-results))
                            :family :calculator
                            :thread-id (thread-id thread)
                            :turn-id (turn-id completed-turn)
                            :visibility :operator
                            :metadata (list :source source
                                            :auto-routed-p t
                                            :direct-calculator-p t))
      (emit-conversation-progress (conversation-progress-phase source :response)
                                  (list :message assistant-content
                                        :staged-action-count 0
                                        :deferred-action-count 0
                                        :immediate-action-count (length actions)
                                        :stream-event-count 0
                                        :thread-id (thread-id thread)
                                        :turn-id (turn-id completed-turn)
                                        :auto-routed-p t
                                        :direct-calculator-p t))
      (make-say-turn-result thread
                            user-message
                            assistant-message
                            completed-turn
                            nil
                            action-report
                            :streamed-p nil
                            :stream-event-count 0
                            :action-results immediate-results))))

(defun governed-mutation-blocked-p (session reasoning-brief)
  (or (find-if (lambda (entry)
                 (member (getf entry :kind)
                         '(:blocked :quarantined :awaiting-cold-validation)
                         :test #'eq))
               (getf reasoning-brief :blockers))
      (getf reasoning-brief :validation-obligations)
      (> (or (getf (provider-session-summary session) :open-incident-count) 0)
         0)))

(defun cognition-strategy-defers-governed-mutations-p (cognition-bundle &key retrieval-dossier)
  (let ((execution-strategy (and cognition-bundle
                                 (cognition-bundle-execution-strategy cognition-bundle)))
        (validation-strategy (and cognition-bundle
                                  (cognition-bundle-validation-strategy cognition-bundle)))
        (action-agenda (and cognition-bundle
                            (cognition-bundle-action-agenda cognition-bundle)))
        (outcome-brief (and cognition-bundle
                            (cognition-bundle-outcome-brief cognition-bundle)))
        (post-mutation-p (eq (and retrieval-dossier
                                  (if (typep retrieval-dossier 'retrieval-dossier)
                                      (retrieval-dossier-phase retrieval-dossier)
                                      (getf retrieval-dossier :phase)))
                             :post-mutation)))
    (or (member (getf (getf action-agenda :primary-step) :kind)
                '(:resolve-blockers :collect-evidence :run-validations)
                :test #'eq)
        (eq (getf execution-strategy :next-step) :collect-evidence)
        (and (eq (getf validation-strategy :mode) :required)
             (eq (getf validation-strategy :next-step) :run-required-validations))
        (and post-mutation-p
             (member (getf outcome-brief :recommended-next-step)
                     '(:validate :resolve-blockers)
                     :test #'eq)))))

(defun project-governance-intent-p (retrieval-dossier)
  (let* ((intent (if (typep retrieval-dossier 'retrieval-dossier)
                     (retrieval-dossier-intent retrieval-dossier)
                     (getf retrieval-dossier :intent)))
         (intent-category (if (typep intent 'retrieval-intent)
                              (retrieval-intent-category intent)
                              (getf intent :category))))
    (eq intent-category :project-governance)))

(defun partition-governed-staged-actions (actions &key project-governance-intent-p)
  (let ((allowed '())
        (deferred '()))
    (dolist (action actions)
      (if (and (governed-assistant-action-p action)
               (not (and project-governance-intent-p
                         (eq (assistant-action-policy-id action) :project-governance-write))))
          (push action deferred)
          (push action allowed)))
    (values (nreverse allowed) (nreverse deferred))))

(defun retrieval-ranking-top-labels (retrieval-dossier)
  (let ((ranking (if (typep retrieval-dossier 'retrieval-dossier)
                     (retrieval-dossier-ranking retrieval-dossier)
                     (getf retrieval-dossier :ranking))))
  (mapcar (lambda (entry) (getf entry :label))
          (or (getf ranking :top-candidates) '()))))

(defun governed-action-grounding-domains (action)
  (let ((policy-id (assistant-action-policy-id action)))
    (case (assistant-action-type action)
      (:patch '(:workspace :artifact :workflow))
      (:eval (if (mutating-eval-action-p action)
                 '(:runtime :workflow :incident :artifact)
                 '(:runtime)))
      (:tool (case policy-id
               ((:workspace-write :git-write) '(:workspace :artifact :workflow))
               (:project-governance-write '(:project :trace :workflow))
               ((:process-run :runtime-reload) '(:runtime :workflow :incident :artifact))
               (otherwise '(:workspace :runtime :workflow))))
      (otherwise '()))))

(defun assess-assistant-action-grounding (action retrieval-dossier)
  (let* ((intent (if (typep retrieval-dossier 'retrieval-dossier)
                     (retrieval-dossier-intent retrieval-dossier)
                     (getf retrieval-dossier :intent)))
         (intent-category (if (typep intent 'retrieval-intent)
                              (retrieval-intent-category intent)
                              (getf intent :category)))
         (mutation-likely-p (if (typep intent 'retrieval-intent)
                                (retrieval-intent-mutation-likely-p intent)
                                (getf intent :mutation-likely-p)))
         (relevant-domains (governed-action-grounding-domains action))
         (top-labels (retrieval-ranking-top-labels retrieval-dossier))
         (matched-labels (intersection relevant-domains top-labels :test #'eq))
         (score (+ (if mutation-likely-p 2 0)
                   (if matched-labels 2 0)
                   (if (member intent-category '(:code-change :runtime-mutation :runtime-debugging
                                                :project-governance)
                               :test #'eq)
                       1
                       0)))
         (weakly-grounded-p
           (case (assistant-action-type action)
             (:patch
              (and (not mutation-likely-p)
                   (not (member intent-category '(:code-change) :test #'eq))
                   (not (member :workspace matched-labels :test #'eq))))
             (:eval
              (if (mutating-eval-action-p action)
                  (and (not mutation-likely-p)
                       (not (member intent-category '(:runtime-mutation :runtime-debugging) :test #'eq))
                       (not (member :runtime matched-labels :test #'eq)))
                  nil))
             (:tool
              (if (governed-assistant-action-p action)
                  (and (not mutation-likely-p)
                       (not (eq intent-category :project-governance))
                       (null matched-labels))
                  nil))
             (otherwise
              (< score 2)))))
    (list :action action
          :relevant-domains relevant-domains
          :matched-top-labels matched-labels
          :grounding-score score
          :weakly-grounded-p weakly-grounded-p
          :reason (if weakly-grounded-p
                      "Governed mutation proposal is weakly grounded in the retrieved context for this request."
                      "Governed mutation proposal is grounded in the retrieved context for this request."))))

(defun action-assessment-for (action assessments)
  (find action assessments :key (lambda (entry) (getf entry :action)) :test #'eq))

(defun partition-weakly-grounded-governed-actions (actions retrieval-dossier)
  (let ((allowed '())
        (deferred '())
        (assessments '()))
    (dolist (action actions)
      (let ((assessment (if (governed-assistant-action-p action)
                            (assess-assistant-action-grounding action retrieval-dossier)
                            (list :action action
                                  :grounding-score 3
                                  :weakly-grounded-p nil
                                  :reason "Read-oriented action does not require governed grounding checks."))))
        (push assessment assessments)
        (if (and (governed-assistant-action-p action)
                 (getf assessment :weakly-grounded-p))
            (push action deferred)
            (push action allowed))))
    (values (nreverse allowed) (nreverse deferred) (nreverse assessments))))

(defun process-response-actions (response session &key reasoning-brief retrieval-dossier cognition-bundle prompt surface-context)
  (multiple-value-bind (immediate staged)
      (split-assistant-actions (effective-response-actions response prompt surface-context session))
    (multiple-value-bind (staged-actions deferred-actions assessments)
        (partition-weakly-grounded-governed-actions staged retrieval-dossier)
      (let ((project-governance-intent-p (project-governance-intent-p retrieval-dossier)))
      (multiple-value-bind (strategy-allowed strategy-deferred-actions)
          (if (cognition-strategy-defers-governed-mutations-p cognition-bundle
                                                              :retrieval-dossier retrieval-dossier)
              (partition-governed-staged-actions staged-actions
                                                 :project-governance-intent-p project-governance-intent-p)
              (values staged-actions '()))
        (multiple-value-bind (final-staged-actions blocker-deferred-actions)
            (if (governed-mutation-blocked-p session reasoning-brief)
                (partition-governed-staged-actions strategy-allowed
                                                   :project-governance-intent-p project-governance-intent-p)
                (values strategy-allowed '()))
        (let* ((deferred-actions (append deferred-actions
                                         strategy-deferred-actions
                                         blocker-deferred-actions))
               (immediate-results (when immediate
                                    (execute-assistant-action-list immediate session))))
          (if final-staged-actions
              (stage-pending-actions session final-staged-actions)
              (clear-pending-actions session))
          (when blocker-deferred-actions
            (append-session-event session
                                  :governed-mutations-deferred
                                  (list :count (length blocker-deferred-actions)
                                        :actions blocker-deferred-actions
                                        :reasoning-brief reasoning-brief)
                                  :family :assistant
                                  :visibility :operator))
          (when strategy-deferred-actions
            (append-session-event session
                                  :strategy-governed-mutations-deferred
                                  (list :count (length strategy-deferred-actions)
                                        :actions strategy-deferred-actions
                                        :post-mutation-p
                                        (eq (and retrieval-dossier
                                                 (if (typep retrieval-dossier 'retrieval-dossier)
                                                     (retrieval-dossier-phase retrieval-dossier)
                                                     (getf retrieval-dossier :phase)))
                                            :post-mutation)
                                        :execution-strategy
                                        (and cognition-bundle
                                             (cognition-bundle-execution-strategy cognition-bundle))
                                        :validation-strategy
                                        (and cognition-bundle
                                             (cognition-bundle-validation-strategy cognition-bundle))
                                        :action-agenda
                                        (and cognition-bundle
                                             (cognition-bundle-action-agenda cognition-bundle))
                                        :outcome-brief
                                        (and cognition-bundle
                                             (cognition-bundle-outcome-brief cognition-bundle)))
                                  :family :assistant
                                  :visibility :operator))
          (let ((weakly-grounded-actions
                  (remove-if-not (lambda (entry) (getf entry :weakly-grounded-p))
                                 assessments)))
            (when weakly-grounded-actions
              (append-session-event session
                                    :weakly-grounded-mutations-deferred
                                    (list :count (length weakly-grounded-actions)
                                          :assessments weakly-grounded-actions
                                          :ranking (and retrieval-dossier
                                                        (if (typep retrieval-dossier 'retrieval-dossier)
                                                            (retrieval-dossier-ranking retrieval-dossier)
                                                            (getf retrieval-dossier :ranking))))
                                    :family :assistant
                                    :visibility :operator)))
          (list :immediate-actions immediate
                :immediate-results immediate-results
                :staged-actions final-staged-actions
                :deferred-actions deferred-actions
                :action-assessments assessments))))))))

(defun handle-provider-stream-event (session event events
                                   &key thread-id turn-id run-id operation-id)
  (let* ((resolved-thread-id (or thread-id
                                 (provider-event-thread-id event)))
         (resolved-turn-id (or turn-id
                               (provider-event-turn-id event)))
         (resolved-run-id (or run-id
                              (provider-event-run-id event)))
         (resolved-operation-id (or operation-id
                                    (provider-event-operation-id event)))
         (metadata (merge-event-metadata
                    (list :canonical-type (provider-event-effective-type event)
                          :legacy-type (provider-event-legacy-type event)
                          :provider-family (provider-event-family event))
                    (provider-event-metadata event))))
    (append-session-event session
                          :provider-stream
                          event
                          :family :provider
                          :entity-id (or (provider-event-entity-id event)
                                         resolved-run-id
                                         resolved-operation-id)
                          :thread-id resolved-thread-id
                          :turn-id resolved-turn-id
                          :visibility (provider-event-visibility event)
                          :metadata metadata
                          :run-id resolved-run-id
                          :operation-id resolved-operation-id)
    (when *task-progress-callback*
      (funcall *task-progress-callback* :provider-stream event))
    (when *stream-event-listener*
      (funcall *stream-event-listener* event))
    (append events (list event))))

(defun execution-task-form (source prompt options)
  (cons source (cons prompt (remove-plist-key options :enqueue))))

(defun ask-task-form (prompt options)
  (execution-task-form 'ask prompt options))

(defun trim-conversation-prompt (prompt)
  (string-trim '(#\Space #\Tab #\Newline #\Return) (or prompt "")))

(defun explicit-runtime-eval-form-prompt (prompt)
  (let ((trimmed (trim-conversation-prompt prompt)))
    (when (and (> (length trimmed) 0)
               (char= (char trimmed 0) #\()
               (ignore-errors (parse-runtime-forms trimmed)))
      trimmed)))

(defun affirmative-runtime-eval-confirmation-p (prompt)
  (member (string-downcase (trim-conversation-prompt prompt))
          '("y"
            "yes"
            "yes."
            "yes please"
            "please do"
            "go ahead"
            "do it"
            "run it"
            "evaluate it"
            "evaluate that"
            "execute it"
            "execute that")
          :test #'string=))

(defun assistant-runtime-eval-offer-p (content)
  (let ((text (string-downcase (or content ""))))
    (or (search "would you like me to evaluate" text :test #'char=)
        (search "would you like me to execute" text :test #'char=)
        (search "evaluate this expression directly" text :test #'char=)
        (search "evaluate this directly" text :test #'char=))))

(defun pending-thread-runtime-eval-confirmation-form (session &optional thread)
  (let* ((active-thread (or thread (current-thread session)))
         (last-turn (most-recent-thread-turn session (thread-id active-thread)))
         (user-message (and last-turn
                            (find-message session (turn-user-message-id last-turn))))
         (assistant-message (and last-turn
                                 (find-message session (turn-assistant-message-id last-turn))))
         (form (and user-message
                    (explicit-runtime-eval-form-prompt (message-content user-message)))))
    (when (and form
               assistant-message
               (assistant-runtime-eval-offer-p (message-content assistant-message)))
      form)))

(defun resolve-conversation-runtime-eval-form (session prompt)
  (or (let ((form (explicit-runtime-eval-form-prompt prompt)))
        (and form
             (list :form form
                   :reason :direct-form)))
      (let ((form (and (affirmative-runtime-eval-confirmation-p prompt)
                       (pending-thread-runtime-eval-confirmation-form session))))
        (and form
             (list :form form
                   :reason :confirmed-prior-form)))))

(defun runtime-eval-assistant-message (tool-result reason)
  (let* ((form (getf tool-result :form))
         (package (getf tool-result :package))
         (values (or (getf tool-result :values) '())))
    (format nil "~A in ~A. Result: ~S.~@[ Values: ~S.~]"
            (if (eq reason :confirmed-prior-form)
                "Evaluated the previously requested form"
                (format nil "Evaluated ~A" form))
            package
            (first values)
            (and (rest values) values))))

(defun run-direct-conversation-runtime-eval (session prompt form reason
                                              &key (source :say) (operator-mode :conversation))
  (declare (ignore operator-mode))
  (let* ((thread (current-thread session)))
    (append-transcript-entry session :user prompt)
    (emit-conversation-progress (conversation-progress-phase source :started)
                                (list :prompt prompt
                                      :stream-p nil
                                      :thread-id (thread-id thread)
                                      :auto-routed-p t
                                      :direct-runtime-eval-p t))
    (let* ((user-message (create-message session thread :user prompt
                                         :metadata (list :source source
                                                         :auto-routed-p t
                                                         :direct-runtime-eval-p t
                                                         :direct-runtime-eval-reason reason)))
           (turn (start-turn session thread user-message
                             :metadata (list :source source
                                             :streamed-p nil
                                             :auto-routed-p t
                                             :direct-runtime-eval-p t
                                             :direct-runtime-eval-reason reason)))
           (operation (start-operation session
                                       thread
                                       turn
                                       :runtime
                                       "conversation-runtime-eval"
                                       (list :prompt prompt
                                             :form form
                                             :reason reason)
                                       :policy-decision
                                       (mutation-policy-decision-summary
                                        :runtime-eval-safe
                                        :decision :allowed
                                        :reason "Conversation prompt was recognized as a direct runtime evaluation request.")
                                       :metadata (list :source source
                                                       :auto-routed-p t
                                                       :direct-runtime-eval-p t
                                                       :direct-runtime-eval-reason reason)))
           (tool-result (let ((*runtime-governance-thread* thread)
                              (*runtime-governance-turn* turn)
                              (*runtime-governance-operation* operation))
                          (tool-runtime-eval session :form form)))
           (completed-operation (complete-operation session
                                                   thread
                                                   turn
                                                   operation
                                                   tool-result
                                                   :status :completed
                                                   :metadata (list :auto-routed-p t
                                                                   :direct-runtime-eval-p t
                                                                   :direct-runtime-eval-reason reason)))
           (assistant-content (runtime-eval-assistant-message tool-result reason))
           (assistant-message (create-message session thread :assistant assistant-content
                                              :content-type :text
                                              :metadata (list :source source
                                                              :streamed-p nil
                                                              :auto-routed-p t
                                                              :direct-runtime-eval-p t
                                                              :direct-runtime-eval-reason reason
                                                              :operation-id (operation-id completed-operation))))
           (completed-turn (complete-turn session
                                          thread
                                          turn
                                          assistant-message
                                          :status :completed
                                          :metadata (list :stream-event-count 0
                                                          :operation-id (operation-id completed-operation)
                                                          :auto-routed-p t
                                                          :direct-runtime-eval-p t
                                                          :direct-runtime-eval-reason reason))))
      (append-transcript-entry session :assistant assistant-content)
      (append-session-event session
                            :conversation-runtime-eval
                            (list :form form
                                  :reason reason
                                  :result (first (getf tool-result :values))
                                  :values (getf tool-result :values))
                            :family :runtime
                            :entity-id (operation-id completed-operation)
                            :thread-id (thread-id thread)
                            :turn-id (turn-id completed-turn)
                            :visibility :operator
                            :metadata (list :source source
                                            :direct-runtime-eval-p t
                                            :direct-runtime-eval-reason reason))
      (emit-conversation-progress (conversation-progress-phase source :response)
                                  (list :message assistant-content
                                        :staged-action-count 0
                                        :deferred-action-count 0
                                        :immediate-action-count 1
                                        :stream-event-count 0
                                        :thread-id (thread-id thread)
                                        :turn-id (turn-id completed-turn)
                                        :auto-routed-p t
                                        :direct-runtime-eval-p t))
      (append (list :response nil
                    :staged-action-count 0
                    :deferred-action-count 0
                    :immediate-action-count 1
                    :action-results (list tool-result)
                    :streamed-p nil
                    :stream-event-count 0
                    :direct-runtime-eval-p t
                    :direct-runtime-eval-reason reason
                    :runtime-result tool-result)
              (conversation-turn-summary thread
                                         user-message
                                         assistant-message
                                         completed-turn)))))

(defun command-invoke-tool-service (session tool-id tool-args &key thread turn operation)
  (let* ((base-compatibility-target (tool-compatibility-target tool-id session tool-args))
         (result (let ((*runtime-governance-thread* thread)
                       (*runtime-governance-turn* turn)
                       (*runtime-governance-operation* operation))
                   (declare (special *runtime-governance-thread*
                                     *runtime-governance-turn*
                                     *runtime-governance-operation*))
                   (apply #'invoke-tool tool-id session tool-args)))
         (compatibility-target
           (and base-compatibility-target
                (append (copy-list base-compatibility-target)
                        (when (getf result :backend-implementation)
                          (list :backend-implementation (getf result :backend-implementation)))
                        (when (getf result :window-state)
                          (list :window-state (getf result :window-state)))
                        (when (getf result :bridge-session-id)
                          (list :bridge-session-id (getf result :bridge-session-id)))
                        (when (member :bridge-attached-p result)
                          (list :bridge-attached-p (getf result :bridge-attached-p)))
                        (when (getf result :recovery-note)
                          (list :recovery-note (getf result :recovery-note)))
                        (when (getf result :control-token)
                          (list :control-token (getf result :control-token)))
                        (when (getf result :pid)
                          (list :pid (getf result :pid)))
                        (when (getf result :registered-at)
                          (list :registered-at (getf result :registered-at)))
                        (when (getf result :status)
                          (list :status (getf result :status)
                                :last-observed-status (getf result :status)
                                :last-status-change-at (get-universal-time)))
                        (when (eq tool-id :proc/spawn)
                          (list :execution-mode :detached)))))
         (payload (if compatibility-target
                      (append (copy-list result)
                              (list :compatibility-target compatibility-target))
                      result)))
    (kernelize-service-command-response
     (make-service-command-response :execution
                                    :tool
                                    payload
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :tool-execution-v1
                                                                     :session session
                                                                     :thread-id (and thread (thread-id thread))
                                                                     :turn-id (and turn (turn-id turn))))
   :session session
   :intention (format nil "Invoke tool ~A." tool-id)
   :capability (kernel-tool-capability-id tool-id)
   :authority :environment
   :context (list :thread-id (and thread (thread-id thread))
                  :turn-id (and turn (turn-id turn))
                  :tool-arguments tool-args))))

(defun command-invoke-compatibility-app-service (session app-id app-args &key thread turn operation)
  (let* ((definition (or (find-compatibility-app app-id
                                                 :session session
                                                 :environment (session-bound-environment session))
                         (error "Unknown compatibility app ~S" app-id)))
         (backend-profile-id (compatibility-app-definition-backend-profile-id definition))
         (argv (compatibility-app-command-argv app-id app-args
                                               :session session
                                               :environment (session-bound-environment session)))
         (base-target (compatibility-app-target app-id session app-args
                                                :environment (session-bound-environment session)))
         (result (let ((*runtime-governance-thread* thread)
                       (*runtime-governance-turn* turn)
                       (*runtime-governance-operation* operation))
                   (declare (special *runtime-governance-thread*
                                     *runtime-governance-turn*
                                     *runtime-governance-operation*))
                   (compatibility-backend-launch backend-profile-id
                                                session
                                                argv
                                                :display-surface-kind
                                                (compatibility-app-definition-display-surface-kind
                                                 definition))))
         (compatibility-target
           (append (copy-list base-target)
                   (when (getf result :backend-implementation)
                     (list :backend-implementation (getf result :backend-implementation)))
                   (when (getf result :window-state)
                     (list :window-state (getf result :window-state)))
                   (when (getf result :bridge-session-id)
                     (list :bridge-session-id (getf result :bridge-session-id)))
                   (when (member :bridge-attached-p result)
                     (list :bridge-attached-p (getf result :bridge-attached-p)))
                   (when (getf result :recovery-note)
                     (list :recovery-note (getf result :recovery-note)))
                   (when (getf result :control-token)
                     (list :control-token (getf result :control-token)))
                   (when (getf result :pid)
                     (list :pid (getf result :pid)))
                   (when (getf result :registered-at)
                     (list :registered-at (getf result :registered-at)))
                   (when (getf result :status)
                          (list :status (getf result :status)
                                :last-observed-status (getf result :status)
                                :last-status-change-at (get-universal-time)))))
         (payload (append (copy-list result)
                          (list :app-id app-id
                                :compatibility-target compatibility-target))))
    (kernelize-service-command-response
     (make-service-command-response :execution
                                    :compatibility-app
                                    payload
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :compatibility-app-execution-v1
                                                                     :session session
                                                                     :thread-id (and thread (thread-id thread))
                                                                     :turn-id (and turn (turn-id turn))))
     :session session
     :intention (format nil "Invoke compatibility app ~A." app-id)
     :capability app-id
     :authority :environment
     :context (list :thread-id (and thread (thread-id thread))
                    :turn-id (and turn (turn-id turn))
                    :app-arguments app-args))))

(defun command-apply-patch-service (session operations &key thread turn operation)
  (kernelize-service-command-response
   (make-service-command-response :execution
                                  :patch
                                  (apply-patch-operations session
                                                          operations
                                                          :thread thread
                                                          :turn turn
                                                          :operation operation)
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :patch-execution-v1
                                                                   :session session
                                                                   :thread-id (and thread (thread-id thread))
                                                                   :turn-id (and turn (turn-id turn))))
   :session session
   :intention "Apply a governed patch to the workspace."
   :capability :workspace/patch
   :authority :workspace-write
   :context (list :thread-id (and thread (thread-id thread))
                  :turn-id (and turn (turn-id turn))
                  :operation operation)))

(defun command-conversation-execution-service (session provider prompt options
                                                &key (source :say) (operator-mode :conversation))
  (let ((enqueue-p (plist-value options :enqueue nil)))
    (if enqueue-p
        (let* ((task-form (execution-task-form source prompt options))
               (command (normalize-form-command task-form))
               (task (enqueue-task session command :payload task-form)))
          (kernelize-service-command-response
           (make-service-command-response :execution
                                          source
                                          (list :queued-task (task-summary task)
                                                :enqueued-p t)
                                          :metadata (make-service-metadata :authority :environment
                                                                           :command-model :conversation-execution-v1
                                                                           :session session))
           :session session
           :intention prompt
           :capability (ecase source
                         (:ask :conversation/ask)
                         (:say :conversation/say))
           :authority operator-mode
           :context (list :enqueue-p t :operator-mode operator-mode)))
        (let ((direct-runtime-eval (resolve-conversation-runtime-eval-form session prompt)))
          (if direct-runtime-eval
              (let ((result (run-direct-conversation-runtime-eval session
                                                                  prompt
                                                                  (getf direct-runtime-eval :form)
                                                                  (getf direct-runtime-eval :reason)
                                                                  :source source
                                                                  :operator-mode operator-mode)))
                (kernelize-service-command-response
                 (make-service-command-response :execution
                                                source
                                                result
                                                :metadata (make-service-metadata :authority :environment
                                                                                 :command-model :conversation-execution-v1
                                                                                 :session session
                                                                                 :thread-id (getf (getf result :thread) :id)
                                                                                 :turn-id (getf (getf result :turn) :id)
                                                                                 :runtime-id (default-runtime-id)
                                                                                 :policy-id :runtime-eval-safe))
                 :session session
                 :intention prompt
                 :capability :runtime/eval
                 :authority operator-mode
                 :constraints (list :direct-runtime-eval-p t :policy-id :runtime-eval-safe)))
              (let* ((stream-p (or (and (option-present-p options :stream)
                                        (plist-value options :stream nil))
                                   *default-ask-streaming*
                                   (not (null *task-progress-callback*))))
                     (attachments (plist-value options :attachments nil))
                     (surface-context (plist-value options :surface-context nil))
                     (surface-actions (plist-value options :surface-actions nil))
                     (direct-calculator-actions
                       (direct-calculator-actions-for-prompt prompt surface-context))
                     (result
                       (if direct-calculator-actions
                           (run-direct-conversation-calculator-actions session
                                                                      prompt
                                                                      direct-calculator-actions
                                                                      :source source
                                                                      :operator-mode operator-mode
                                                                      :surface-context surface-context
                                                                      :surface-actions surface-actions)
                           (run-conversation-turn provider
                                                  session
                                                  prompt
                                                  :stream-p stream-p
                                                  :attachments attachments
                                                  :surface-context surface-context
                                                  :surface-actions surface-actions
                                                  :source source
                                                  :operator-mode operator-mode))))
                (kernelize-service-command-response
                 (make-service-command-response :execution
                                                source
                                                result
                                                :metadata (make-service-metadata :authority :environment
                                                                                 :command-model :conversation-execution-v1
                                                                                 :session session
                                                                                 :thread-id (getf (getf result :thread) :id)
                                                                                 :turn-id (getf (getf result :turn) :id)))
                 :session session
                 :intention prompt
                 :capability (ecase source
                               (:ask :conversation/ask)
                               (:say :conversation/say))
                 :authority operator-mode
                 :context (append (list :stream-p stream-p
                                        :operator-mode operator-mode)
                                  (when direct-calculator-actions
                                    (list :direct-calculator-p t
                                          :action-count (length direct-calculator-actions)))))))))))

(defun command-execute-assistant-action-service (session action &key thread turn operation)
  (kernelize-service-command-response
   (make-service-command-response :execution
                                  :assistant-action
                                  (execute-assistant-action action
                                                           session
                                                           :thread thread
                                                           :turn turn
                                                           :operation operation)
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :assistant-action-execution-v1
                                                                   :session session
                                                                   :thread-id (and thread (thread-id thread))
                                                                   :turn-id (and turn (turn-id turn))))
   :session session
   :intention "Execute a staged assistant action."
   :capability :assistant/action
   :authority :environment
   :context (list :thread-id (and thread (thread-id thread))
                  :turn-id (and turn (turn-id turn))
                  :operation operation)))

(defun command-execute-pending-actions-service (session &key thread turn operation)
  (let ((actions (agent-session-pending-actions session)))
    (unless actions
      (error "No pending assistant actions are staged in the current session"))
    (let ((results (execute-assistant-action-list actions
                                                  session
                                                  :thread thread
                                                  :turn turn
                                                  :operation operation)))
      (clear-pending-actions session)
      (kernelize-service-command-response
       (make-service-command-response :execution
                                      :pending-actions
                                      results
                                      :metadata (make-service-metadata :authority :environment
                                                                       :command-model :assistant-action-execution-v1
                                                                       :session session
                                                                       :thread-id (and thread (thread-id thread))
                                                                       :turn-id (and turn (turn-id turn))))
       :session session
       :intention "Execute all currently staged pending actions."
       :capability :assistant/pending-actions
       :authority :environment
       :context (list :thread-id (and thread (thread-id thread))
                      :turn-id (and turn (turn-id turn))
                      :operation operation)))))
