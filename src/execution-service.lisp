(in-package #:sbcl-agent)

(defparameter *stream-event-listener* nil)
(defparameter *default-ask-streaming* nil)

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

(defun command-invoke-tool-service (session tool-id tool-args &key thread turn operation)
  (make-service-command-response :execution
                                 :tool
                                 (let ((*runtime-governance-thread* thread)
                                       (*runtime-governance-turn* turn)
                                       (*runtime-governance-operation* operation))
                                   (declare (special *runtime-governance-thread*
                                                     *runtime-governance-turn*
                                                     *runtime-governance-operation*))
                                   (apply #'invoke-tool tool-id session tool-args))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :tool-execution-v1
                                                                  :session session
                                                                  :thread-id (and thread (thread-id thread))
                                                                  :turn-id (and turn (turn-id turn)))))

(defun command-apply-patch-service (session operations &key thread turn operation)
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
                                                                  :turn-id (and turn (turn-id turn)))))

(defun command-conversation-execution-service (session provider prompt options
                                                &key (source :say) (operator-mode :conversation))
  (let ((enqueue-p (plist-value options :enqueue nil)))
    (if enqueue-p
        (let* ((task-form (execution-task-form source prompt options))
               (command (normalize-form-command task-form))
               (task (enqueue-task session command :payload task-form)))
          (make-service-command-response :execution
                                         source
                                         (list :queued-task (task-summary task)
                                               :enqueued-p t)
                                         :metadata (make-service-metadata :authority :environment
                                                                          :command-model :conversation-execution-v1
                                                                          :session session)))
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
          (make-service-command-response :execution
                                         source
                                         result
                                         :metadata (make-service-metadata :authority :environment
                                                                          :command-model :conversation-execution-v1
                                                                          :session session
                                                                          :thread-id (getf (getf result :thread) :id)
                                                                          :turn-id (getf (getf result :turn) :id)))))))

(defun command-execute-assistant-action-service (session action &key thread turn operation)
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
                                                                  :turn-id (and turn (turn-id turn)))))

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
      (make-service-command-response :execution
                                     :pending-actions
                                     results
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :assistant-action-execution-v1
                                                                      :session session
                                                                      :thread-id (and thread (thread-id thread))
                                                                      :turn-id (and turn (turn-id turn)))))))
