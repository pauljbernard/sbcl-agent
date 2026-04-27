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

(defun split-assistant-actions (actions)
  (let ((immediate '())
        (staged '()))
    (dolist (action actions)
      (if (and (eq (assistant-action-type action) :eval)
               (not (mutating-eval-action-p action)))
          (push action immediate)
          (push action staged)))
    (values (nreverse immediate) (nreverse staged))))

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

(defun partition-governed-staged-actions (actions)
  (let ((allowed '())
        (deferred '()))
    (dolist (action actions)
      (if (governed-assistant-action-p action)
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
                   (if (member intent-category '(:code-change :runtime-mutation :runtime-debugging)
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

(defun process-response-actions (response session &key reasoning-brief retrieval-dossier cognition-bundle)
  (multiple-value-bind (immediate staged)
      (split-assistant-actions (assistant-response-actions response))
    (multiple-value-bind (staged-actions deferred-actions assessments)
        (partition-weakly-grounded-governed-actions staged retrieval-dossier)
      (multiple-value-bind (strategy-allowed strategy-deferred-actions)
          (if (cognition-strategy-defers-governed-mutations-p cognition-bundle
                                                              :retrieval-dossier retrieval-dossier)
              (partition-governed-staged-actions staged-actions)
              (values staged-actions '()))
        (multiple-value-bind (final-staged-actions blocker-deferred-actions)
            (if (governed-mutation-blocked-p session reasoning-brief)
                (partition-governed-staged-actions strategy-allowed)
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
                :action-assessments assessments)))))))

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
               (ignore-errors (parse-runtime-form trimmed)))
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
                     (result (run-conversation-turn provider
                                                   session
                                                   prompt
                                                   :stream-p stream-p
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
                                                                                 :turn-id (getf (getf result :turn) :id)))
                 :session session
                 :intention prompt
                 :capability (ecase source
                               (:ask :conversation/ask)
                               (:say :conversation/say))
                 :authority operator-mode
                 :context (list :stream-p stream-p :operator-mode operator-mode))))))))

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
