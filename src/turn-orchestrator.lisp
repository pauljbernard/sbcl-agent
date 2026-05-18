(in-package #:sbcl-agent)

(defun say-provider-operation-policy-decision ()
  (mutation-policy-decision-summary :safe-read
                                    :decision :allowed
                                    :reason "Conversation provider runs are currently read-only orchestrator operations."))

(defun turn-status-from-action-operations (operations)
  (cond
    ((find :awaiting-approval operations :key #'operation-status)
     :awaiting-approval)
    ((find :failed operations :key #'operation-status)
     :failed)
    (t
     :completed)))

(defun patch-actions-present-p (action-report)
  (find :patch
        (append (getf action-report :immediate-actions)
                (getf action-report :staged-actions))
        :key #'assistant-action-type))

(defun action-report-assessment (action-report action)
  (find action
        (getf action-report :action-assessments)
        :key (lambda (entry) (getf entry :action))
        :test #'eq))

(defun desktop-task-record-ids-for-action (action desktop-task-bindings fallback-record-ids)
  (or (loop for binding in (or desktop-task-bindings '())
            when (find action (getf binding :actions) :test #'eq)
              append (copy-list (or (getf binding :record-ids)
                                    (let ((record-id (getf binding :record-id)))
                                      (and record-id (list record-id)))))
            into matches
            finally (return (remove-duplicates matches :test #'string=)))
      fallback-record-ids))

(defun record-assistant-action-operations (session thread turn action-report
                                           &key work-item desktop-task-records desktop-task-bindings)
  (let ((fallback-record-ids (mapcar #'desktop-task-record-id desktop-task-records))
        (records '()))
    (dolist (entry (getf action-report :immediate-results))
      (let* ((action (getf entry :action))
             (result (getf entry :result))
             (assessment (action-report-assessment action-report action))
             (action-task-record-ids
               (desktop-task-record-ids-for-action action
                                                   desktop-task-bindings
                                                   fallback-record-ids))
             (operation (start-operation session
                                         thread
                                         turn
                                         :assistant-action
                                         (action-operation-name action)
                                         (assistant-action-payload action)
                                         :policy-decision (assistant-action-policy-decision action :allowed)
                                         :metadata (list :assistant-action-type (assistant-action-type action)
                                                         :assistant-action action
                                                         :desktop-task-record-ids action-task-record-ids
                                                         :action-assessment assessment
                                                         :work-item-id (and work-item (work-item-id work-item))
                                                         :source :say))))
        (complete-operation session
                            thread
                            turn
                            operation
                            result
                            :status :completed
                            :metadata '(:execution :immediate))
        (push operation records)))
    (dolist (action (getf action-report :staged-actions))
      (let* ((disposition (staged-assistant-action-disposition action))
             (assessment (action-report-assessment action-report action))
             (action-task-record-ids
               (desktop-task-record-ids-for-action action
                                                   desktop-task-bindings
                                                   fallback-record-ids))
             (operation (start-operation session
                                         thread
                                         turn
                                         :assistant-action
                                         (action-operation-name action)
                                         (assistant-action-payload action)
                                         :policy-decision (assistant-action-policy-decision action disposition)
                                         :metadata (list :assistant-action-type (assistant-action-type action)
                                                         :assistant-action action
                                                         :desktop-task-record-ids action-task-record-ids
                                                         :action-assessment assessment
                                                         :work-item-id (and work-item (work-item-id work-item))
                                                         :source :say))))
        (complete-operation session
                            thread
                            turn
                            operation
                            (list :staged-p t
                                  :approval-required-p (eq disposition :approval-required)
                                  :action-type (assistant-action-type action))
                            :status (staged-assistant-action-status action)
                            :metadata (list :execution (if (eq disposition :approval-required)
                                                           :awaiting-approval
                                                           :staged)))
        (push operation records)))
    (dolist (action (getf action-report :deferred-actions))
      (let* ((disposition (deferred-assistant-action-disposition action))
             (assessment (action-report-assessment action-report action))
             (action-task-record-ids
               (desktop-task-record-ids-for-action action
                                                   desktop-task-bindings
                                                   fallback-record-ids))
             (operation (start-operation session
                                         thread
                                         turn
                                         :assistant-action
                                         (action-operation-name action)
                                         (assistant-action-payload action)
                                         :policy-decision (assistant-action-policy-decision action disposition)
                                         :metadata (list :assistant-action-type (assistant-action-type action)
                                                         :assistant-action action
                                                         :desktop-task-record-ids action-task-record-ids
                                                         :action-assessment assessment
                                                         :work-item-id (and work-item (work-item-id work-item))
                                                         :source :say))))
        (complete-operation session
                            thread
                            turn
                            operation
                            (list :deferred-p t
                                  :reason (or (getf assessment :reason)
                                              "Governed mutation deferred because blockers, incidents, or pending validation remain active.")
                                  :action-type (assistant-action-type action))
                            :status (deferred-assistant-action-status action)
                            :metadata '(:execution :deferred))
        (push operation records)))
    (nreverse records)))

(defun make-say-turn-result (thread user-message assistant-message turn response action-report
                              &key streamed-p stream-event-count stream-events action-results
                                retrieval-summary reasoning-summary planning-summary
                                outcome-summary cognition-summary action-agenda-summary)
  (labels ((assistant-response-metadata-value (key)
             (let ((metadata (and (typep response 'assistant-response)
                                  (assistant-response-metadata response))))
               (when (listp metadata)
                 (or (getf metadata key)
                     (getf metadata (intern (string-upcase (string key)) "KEYWORD"))))))
           (pending-approval-summary (task-record-summaries)
             (let ((awaiting
                     (remove-if-not
                      (lambda (summary)
                        (eq (or (getf summary :approval-status)
                                (getf summary :APPROVAL-STATUS))
                            :awaiting-approval))
                      task-record-summaries)))
               (when awaiting
                 (list :session-id (or (getf (first awaiting) :session-id)
                                       (getf (first awaiting) :SESSION-ID))
                       :thread-id (or (getf (first awaiting) :thread-id)
                                      (getf (first awaiting) :THREAD-ID))
                       :record-ids (mapcar (lambda (summary)
                                             (or (getf summary :id)
                                                 (getf summary :ID)))
                                           awaiting)
                       :approval-ids (remove nil
                                             (mapcar (lambda (summary)
                                                       (or (getf summary :approval-id)
                                                           (getf summary :APPROVAL-ID)))
                                                     awaiting))
                       :policy-ids (remove-duplicates
                                    (remove nil
                                            (mapcar (lambda (summary)
                                                      (let ((request-metadata
                                                              (or (getf summary :request-metadata)
                                                                  (getf summary :REQUEST-METADATA))))
                                                        (and (listp request-metadata)
                                                             (or (getf request-metadata :policy-id)
                                                                 (getf request-metadata :POLICY-ID)))))
                                                    awaiting))
                                    :test #'eq)
                       :actor-message-ids (remove nil
                                                  (mapcar (lambda (summary)
                                                            (or (getf summary :actor-message-id)
                                                                (getf summary :ACTOR-MESSAGE-ID)
                                                                (let ((actor-message
                                                                        (or (getf summary :actor-message)
                                                                            (getf summary :ACTOR-MESSAGE))))
                                                                  (and (listp actor-message)
                                                                       (or (getf actor-message :id)
                                                                           (getf actor-message :ID))))))
                                                          awaiting))
                       :receiver-roles (remove-duplicates
                                        (remove nil
                                                (mapcar (lambda (summary)
                                                          (let ((actor-message
                                                                  (or (getf summary :actor-message)
                                                                      (getf summary :ACTOR-MESSAGE))))
                                                            (when (listp actor-message)
                                                              (let ((receiver (or (getf actor-message :receiver)
                                                                                  (getf actor-message :RECEIVER))))
                                                                (and (listp receiver)
                                                                     (or (getf receiver :role)
                                                                         (getf receiver :ROLE)))))))
                                                        awaiting))
                                        :test #'eq))))))
    (let* ((task-record-summaries
             (assistant-response-metadata-value :desktop-task-records))
           (desktop-task-results
             (assistant-response-metadata-value :desktop-task-results))
           (actor-flow
             (assistant-response-metadata-value :actor-flow))
           (runtime-reply
             (assistant-response-metadata-value :runtime-reply))
           (pending-approval
             (pending-approval-summary task-record-summaries)))
      (append (list :response response
                    :staged-action-count (length (getf action-report :staged-actions))
                    :deferred-action-count (length (getf action-report :deferred-actions))
                    :immediate-action-count (length (getf action-report :immediate-actions))
                    :action-results action-results
                    :streamed-p streamed-p
                    :stream-event-count stream-event-count
                    :retrieval-summary retrieval-summary
                    :reasoning-summary reasoning-summary
                    :planning-summary planning-summary
                    :outcome-summary outcome-summary
                    :cognition-summary cognition-summary
                    :action-agenda-summary action-agenda-summary)
              (when task-record-summaries
                (list :task-record-summaries task-record-summaries))
              (when desktop-task-results
                (list :desktop-task-results desktop-task-results))
              (when actor-flow
                (list :actor-flow actor-flow))
              (when runtime-reply
                (list :runtime-reply runtime-reply))
              (when pending-approval
                (list :pending-approval pending-approval))
              (when stream-events
                (list :stream-events stream-events))
              (conversation-turn-summary thread user-message assistant-message turn)))))

(defun emit-conversation-progress (phase payload)
  (when *task-progress-callback*
    (funcall *task-progress-callback* phase payload)))

(defun emit-say-progress (phase payload)
  (emit-conversation-progress phase payload))

(defun conversation-progress-phase (source suffix)
  (intern (format nil "~A-~A"
                  (string-upcase (string source))
                  (string-upcase (string suffix)))
          :keyword))

(defun internal-elapsed-seconds (started-at completed-at)
  (/ (- completed-at started-at)
     internal-time-units-per-second))

(defun record-turn-latency-sample (session thread turn source kind payload)
  (append-session-event session
                        :conversation-latency
                        payload
                        :family :provider
                        :entity-id (turn-id turn)
                        :thread-id (thread-id thread)
                        :turn-id (turn-id turn)
                        :visibility :operator
                        :metadata (list :source source
                                        :kind kind))
  (emit-conversation-progress (conversation-progress-phase source :timing)
                              (append (list :kind kind
                                            :thread-id (thread-id thread)
                                            :turn-id (turn-id turn))
                                      payload)))

(defun make-provider-timing-listener (session thread turn source)
  (lambda (phase payload)
    (record-turn-latency-sample session
                                thread
                                turn
                                source
                                :provider-phase
                                (append (list :phase phase)
                                        payload))))

(defun provider-request-retrieval-summary (request)
  (let* ((dossier (provider-request-retrieval-dossier request))
         (intent (and dossier (getf dossier :intent)))
         (plan (and dossier (getf dossier :plan))))
    (when dossier
      (list :category (getf intent :category)
            :domains (getf intent :domains)
            :expansion-posture (getf plan :expansion-posture)
            :gap-count (length (or (getf dossier :gaps) '()))))))

(defun provider-request-reasoning-summary (request)
  (let ((brief (provider-request-reasoning-brief request)))
    (when brief
      (list :reasoning-mode (getf brief :reasoning-mode)
            :fact-count (length (or (getf brief :facts) '()))
            :uncertainty-count (length (or (getf brief :uncertainties) '()))
            :blocker-count (length (or (getf brief :blockers) '()))
            :validation-obligation-count (length (or (getf brief :validation-obligations) '()))
            :evidence-action-count (length (or (getf brief :evidence-actions) '()))))))

(defun provider-request-planning-summary (request)
  (let ((brief (provider-request-planning-brief request)))
    (when brief
      (list :planning-mode (getf brief :planning-mode)
            :step-count (length (or (getf brief :ordered-steps) '()))
            :constraint-count (length (or (getf brief :constraints) '()))
            :success-criteria-count (length (or (getf brief :success-criteria) '()))))))

(defun provider-request-outcome-summary (request)
  (let ((brief (provider-request-outcome-brief request)))
    (when brief
      (list :outcome-mode (getf brief :outcome-mode)
            :expected-phase-count (length (or (getf brief :expected-phases) '()))
            :mismatch-count (length (or (getf brief :mismatches) '()))
            :recommended-next-step (getf brief :recommended-next-step)))))

(defun provider-request-cognition-summary (request)
  (let ((bundle (provider-request-cognition-bundle request)))
    (cognition-bundle-summary bundle)))

(defun provider-request-action-agenda-summary (request)
  (let* ((bundle (provider-request-cognition-bundle request))
         (agenda (and bundle (cognition-bundle-action-agenda bundle))))
    (when agenda
      (list :step-count (getf agenda :step-count)
            :primary-step (getf agenda :primary-step)))))

(defun record-turn-memory-entry (session thread turn request prompt assistant-message
                                 &key defer-inference-p)
  (let ((bundle (provider-request-cognition-bundle request)))
    (when bundle
      (remember-turn-outcome-memory session
                                    thread
                                    turn
                                    prompt
                                    bundle
                                    assistant-message))
    (if defer-inference-p
        (append-session-event session
                              :operator-memory-inference-deferred
                              (list :prompt (provider-summary-content prompt)
                                    :assistant-message (provider-summary-content assistant-message)
                                    :reason :streaming-turn-post-response)
                              :family :assistant
                              :entity-id (and turn (turn-id turn))
                              :thread-id (and thread (thread-id thread))
                              :turn-id (and turn (turn-id turn))
                              :visibility :operator)
        (infer-operator-memory session
                               thread
                               turn
                               prompt
                               assistant-message))))

(defun build-turn-provider-request (session prompt thread turn operator-mode stream-p
                                    &key retrieval-dossier attachments
                                      surface-context surface-actions)
  (let* ((user-message (and turn
                            (find-message session (turn-user-message-id turn))))
         (resolved-surface-context (or surface-context
                                       (and turn (getf (turn-metadata turn) :surface-context))
                                       (and user-message
                                            (getf (message-metadata user-message) :surface-context))))
         (resolved-surface-actions (or surface-actions
                                       (and turn (getf (turn-metadata turn) :surface-actions))
                                       (and user-message
                                            (getf (message-metadata user-message) :surface-actions)))))
    (make-provider-request-from-session prompt
                                        session
                                        :thread thread
                                        :turn turn
                                        :attachments attachments
                                        :retrieval-dossier retrieval-dossier
                                        :surface-context resolved-surface-context
                                        :surface-actions resolved-surface-actions
                                        :operator-mode operator-mode
                                        :stream-p stream-p)))

(defun record-turn-retrieval-dossier (session thread turn request source
                                      &key (phase (or (getf (provider-request-retrieval-dossier request) :phase)
                                                      :pre-prompt)))
  (let ((dossier (provider-request-retrieval-dossier request))
        (summary (provider-request-retrieval-summary request)))
    (when dossier
      (append-session-event session
                            :retrieval-dossier
                            dossier
                            :family :retrieval
                            :entity-id (turn-id turn)
                            :thread-id (thread-id thread)
                            :turn-id (turn-id turn)
                            :visibility :operator
                            :metadata (list :source source
                                            :phase phase
                                            :retrieval-summary summary))
      (emit-conversation-progress (conversation-progress-phase source :retrieval)
                                  (list :thread-id (thread-id thread)
                                        :turn-id (turn-id turn)
                                        :phase phase
                                        :retrieval-summary summary)))))

(defun record-turn-reasoning-brief (session thread turn request source
                                    &key (phase (or (getf (provider-request-retrieval-dossier request) :phase)
                                                    :pre-prompt)))
  (let ((brief (provider-request-reasoning-brief request))
        (summary (provider-request-reasoning-summary request)))
    (when brief
      (append-session-event session
                            :reasoning-brief
                            brief
                            :family :retrieval
                            :entity-id (turn-id turn)
                            :thread-id (thread-id thread)
                            :turn-id (turn-id turn)
                            :visibility :operator
                            :metadata (list :source source
                                            :phase phase
                                            :reasoning-summary summary))
      (emit-conversation-progress (conversation-progress-phase source :reasoning)
                                  (list :thread-id (thread-id thread)
                                        :turn-id (turn-id turn)
                                        :phase phase
                                        :reasoning-summary summary)))))

(defun record-turn-planning-brief (session thread turn request source
                                   &key (phase (or (getf (provider-request-retrieval-dossier request) :phase)
                                                   :pre-prompt)))
  (let ((brief (provider-request-planning-brief request))
        (summary (provider-request-planning-summary request)))
    (when brief
      (append-session-event session
                            :planning-brief
                            brief
                            :family :retrieval
                            :entity-id (turn-id turn)
                            :thread-id (thread-id thread)
                            :turn-id (turn-id turn)
                            :visibility :operator
                            :metadata (list :source source
                                            :phase phase
                                            :planning-summary summary))
      (emit-conversation-progress (conversation-progress-phase source :planning)
                                  (list :thread-id (thread-id thread)
                                        :turn-id (turn-id turn)
                                        :phase phase
                                        :planning-summary summary)))))

(defun record-turn-outcome-brief (session thread turn request source
                                  &key (phase (or (getf (provider-request-retrieval-dossier request) :phase)
                                                  :pre-prompt)))
  (let ((brief (provider-request-outcome-brief request))
        (summary (provider-request-outcome-summary request)))
    (when brief
      (append-session-event session
                            :outcome-brief
                            brief
                            :family :retrieval
                            :entity-id (turn-id turn)
                            :thread-id (thread-id thread)
                            :turn-id (turn-id turn)
                            :visibility :operator
                            :metadata (list :source source
                                            :phase phase
                                            :outcome-summary summary))
      (emit-conversation-progress (conversation-progress-phase source :outcome)
                                  (list :thread-id (thread-id thread)
                                        :turn-id (turn-id turn)
                                        :phase phase
                                        :outcome-summary summary)))))

(defun record-turn-cognition-bundle (session thread turn request source
                                     &key (phase (or (getf (provider-request-retrieval-dossier request) :phase)
                                                     :pre-prompt)))
  (let ((bundle (provider-request-cognition-bundle request))
        (summary (provider-request-cognition-summary request)))
    (when bundle
      (append-session-event session
                            :cognition-bundle
                            (list :retrieval-dossier (cognition-bundle-retrieval-dossier bundle)
                                  :retrieval-focus-plan (cognition-bundle-retrieval-focus-plan bundle)
                                  :prior-outcome-brief (cognition-bundle-prior-outcome-brief bundle)
                                  :reasoning-brief (cognition-bundle-reasoning-brief bundle)
                                  :planning-brief (cognition-bundle-planning-brief bundle)
                                  :execution-strategy (cognition-bundle-execution-strategy bundle)
                                  :validation-strategy (cognition-bundle-validation-strategy bundle)
                                  :validation-plan (cognition-bundle-validation-plan bundle)
                                  :action-agenda (cognition-bundle-action-agenda bundle)
                                  :outcome-brief (cognition-bundle-outcome-brief bundle))
                            :family :retrieval
                            :entity-id (turn-id turn)
                            :thread-id (thread-id thread)
                            :turn-id (turn-id turn)
                            :visibility :operator
                            :metadata (list :source source
                                            :phase phase
                                            :cognition-summary summary))
      (emit-conversation-progress (conversation-progress-phase source :cognition)
                                  (list :thread-id (thread-id thread)
                                        :turn-id (turn-id turn)
                                        :phase phase
                                        :cognition-summary summary)))))

(defun record-turn-request-trace (session thread turn request source
                                  &key (phase (or (getf (provider-request-retrieval-dossier request) :phase)
                                                  :pre-prompt)))
  (record-turn-retrieval-dossier session thread turn request source :phase phase)
  (record-turn-reasoning-brief session thread turn request source :phase phase)
  (record-turn-planning-brief session thread turn request source :phase phase)
  (record-turn-cognition-bundle session thread turn request source :phase phase))

(defun materially-mutating-action-result-p (entry)
  (let* ((action (getf entry :action))
         (policy-id (and action (assistant-action-policy-id action))))
    (and action
         (case (assistant-action-type action)
           (:patch t)
           (:eval (mutating-eval-action-p action))
           (:tool (member policy-id '(:workspace-write :git-write :process-run :runtime-reload
                                      :project-governance-write)
                          :test #'eq))
           (otherwise nil)))))

(defun action-results-post-mutation-p (results)
  (find-if #'materially-mutating-action-result-p results))

(defun build-post-mutation-provider-request (session prompt thread turn operator-mode action-results)
  (let* ((dossier (service-response-data
                   (query-post-mutation-retrieval-dossier-service session
                                                                  prompt
                                                                  action-results
                                                                  :operator-mode operator-mode)))
         (reasoning-brief (build-reasoning-brief (provider-session-summary session)
                                                 (provider-environment-context session)
                                                 dossier))
         (planning-brief (build-planning-brief prompt reasoning-brief dossier))
         (outcome-brief (build-outcome-brief planning-brief reasoning-brief dossier)))
    (make-provider-request-from-session prompt
                                        session
                                        :thread thread
                                        :turn turn
                                        :retrieval-dossier dossier
                                        :outcome-brief outcome-brief
                                        :operator-mode operator-mode
                                        :stream-p nil)))

(defun run-conversation-turn-streaming (provider session thread prompt
                                         &key (source :say) (operator-mode :conversation)
                                           attachments surface-context surface-actions)
  (let* ((request-build-started-at (get-internal-real-time))
         (user-message (create-message session thread :user prompt
                                       :metadata (list :source source
                                                       :surface-context surface-context
                                                       :surface-actions surface-actions)
                                       :attachments attachments))
         (turn (start-turn session thread user-message
                           :metadata (list :source source
                                           :streamed-p t
                                           :surface-context surface-context
                                           :surface-actions surface-actions)))
         (request (build-turn-provider-request session prompt thread turn operator-mode t
                                              :attachments attachments
                                              :surface-context surface-context
                                              :surface-actions surface-actions))
         (request-ready-at (get-internal-real-time))
         (operation (start-operation session
                                     thread
                                     turn
                                     :provider-run
                                     (provider-name provider)
                                     (list :prompt prompt :streamed-p t)
                                     :policy-decision (say-provider-operation-policy-decision)
                                     :metadata (list :source source
                                                     :retrieval-summary
                                                     (provider-request-retrieval-summary request)
                                                     :cognition-summary
                                                     (provider-request-cognition-summary request)
                                                     :reasoning-summary
                                                     (provider-request-reasoning-summary request)
                                                     :planning-summary
                                                     (provider-request-planning-summary request))))
         (run-id (format nil "provider-run-~A" (operation-id operation)))
         (events '())
         (first-stream-at nil))
    (record-turn-latency-sample session
                                thread
                                turn
                                source
                                :request-built
                                (list :request-build-seconds
                                      (internal-elapsed-seconds request-build-started-at
                                                                request-ready-at)
                                      :stream-p t))
    (let* ((response (let ((*provider-timing-listener*
                             (make-provider-timing-listener session thread turn source)))
                       (stream-provider-request provider
                                               request
                                               (lambda (event)
                                                 (setf (provider-event-run-id event) run-id
                                                       (provider-event-operation-id event) (operation-id operation)
                                                       (provider-event-thread-id event) (thread-id thread)
                                                       (provider-event-turn-id event) (turn-id turn)
                                                       (provider-event-metadata event)
                                                       (merge-event-metadata
                                                        (provider-event-metadata event)
                                                        (list :run-id run-id
                                                              :operation-id (operation-id operation)
                                                              :thread-id (thread-id thread)
                                                              :turn-id (turn-id turn))))
                                                 (when (and (null first-stream-at)
                                                            (provider-text-delta-event-p event))
                                                   (setf first-stream-at (get-internal-real-time))
                                                   (record-turn-latency-sample
                                                    session
                                                    thread
                                                    turn
                                                    source
                                                    :first-stream
                                                    (list :request-build-seconds
                                                          (internal-elapsed-seconds request-build-started-at
                                                                                    request-ready-at)
                                                          :pre-stream-seconds
                                                          (internal-elapsed-seconds request-ready-at
                                                                                    first-stream-at)
                                                          :total-to-first-stream-seconds
                                                          (internal-elapsed-seconds request-build-started-at
                                                                                    first-stream-at))))
                                                 (setf events (handle-provider-stream-event session
                                                                                           event
                                                                                           events
                                                                                           :thread-id (thread-id thread)
                                                                                           :turn-id (turn-id turn)
                                                                                           :run-id run-id
                                                                                           :operation-id (operation-id operation)))))))
           (action-report (process-response-actions response
                                                   session
                                                   :cognition-bundle
                                                   (provider-request-cognition-bundle request)
                                                   :reasoning-brief
                                                   (provider-request-reasoning-brief request)
                                                   :retrieval-dossier
                                                   (provider-request-retrieval-dossier request)
                                                   :prompt prompt
                                                   :surface-context
                                                   (provider-request-surface-context request)))
           (work-item (ensure-turn-mutation-work-item session
                                                     thread
                                                     turn
                                                     action-report
                                                     prompt
                                                     :cognition-bundle (provider-request-cognition-bundle request)))
           (immediate-results (getf action-report :immediate-results))
           (completed-operation (complete-operation session
                                                   thread
                                                   turn
                                                   operation
                                                   (list :message (assistant-response-message response)
                                                        :stream-event-count (length events)
                                                        :staged-action-count (length (getf action-report :staged-actions))
                                                        :deferred-action-count (length (getf action-report :deferred-actions)))
                                                   :metadata (list :model-response-p t)))
           (action-operations (record-assistant-action-operations session
                                                                  thread
                                                                  turn
                                                                  action-report
                                                                  :work-item work-item))
           (assistant-message (create-message session thread :assistant (assistant-response->string response)
                                              :content-type :text
                                              :stream-fragments (mapcar #'provider-event-payload
                                                                        (remove-if-not #'provider-text-delta-event-p events))
                                              :metadata (list :source source :streamed-p t)
                                              :attachments (getf (assistant-response-metadata response) :attachments)))
           (completed-turn (complete-turn session
                                          thread
                                          turn
                                          assistant-message
                                          :status (turn-status-from-action-operations action-operations)
                                          :metadata (list :stream-event-count (length events)
                                                          :operation-id (operation-id completed-operation)
                                                          :action-operation-ids (mapcar #'operation-id action-operations)))))
      (append-transcript-entry session :assistant (assistant-response->string response))
      ;; Keep provider startup lean for streamed conversation turns by recording
      ;; the richer request trace after the response completes instead of before
      ;; the first delta can be emitted.
      (record-turn-request-trace session thread completed-turn request source)
      (append-session-event session
                            :assistant-response
                            response
                            :family :assistant
                            :thread-id (thread-id thread)
                            :turn-id (turn-id completed-turn)
                            :visibility :operator)
      (when (calculator-control-actions-p (getf action-report :immediate-actions))
        (append-conversation-calculator-control-event session
                                                      thread
                                                      completed-turn
                                                      prompt
                                                      (getf action-report :immediate-actions)
                                                      immediate-results
                                                      :source source))
      (record-turn-memory-entry session
                                thread
                                completed-turn
                                request
                                prompt
                                (assistant-response->string response)
                                :defer-inference-p t)
      (emit-conversation-progress (conversation-progress-phase source :response)
                                  (list :message (assistant-response-message response)
                                        :staged-action-count (length (getf action-report :staged-actions))
                                        :deferred-action-count (length (getf action-report :deferred-actions))
                                        :immediate-action-count (length (getf action-report :immediate-actions))
                                        :stream-event-count (length events)
                                        :retrieval-summary (provider-request-retrieval-summary request)
                                        :cognition-summary (provider-request-cognition-summary request)
                                        :action-agenda-summary (provider-request-action-agenda-summary request)
                                        :reasoning-summary (provider-request-reasoning-summary request)
                                        :planning-summary (provider-request-planning-summary request)
                                        :thread-id (thread-id thread)
                                        :turn-id (turn-id completed-turn)))
      (make-say-turn-result thread
                            user-message
                            assistant-message
                            completed-turn
                            response
                            action-report
                            :streamed-p t
                            :stream-event-count (length events)
                            :stream-events events
                            :action-results immediate-results
                            :retrieval-summary (provider-request-retrieval-summary request)
                            :cognition-summary (provider-request-cognition-summary request)
                            :action-agenda-summary (provider-request-action-agenda-summary request)
                            :reasoning-summary (provider-request-reasoning-summary request)
                            :planning-summary (provider-request-planning-summary request)
                            :outcome-summary (provider-request-outcome-summary request)))))

(defun run-conversation-turn-sync (provider session thread prompt
                                    &key (source :say) (operator-mode :conversation)
                                      attachments surface-context surface-actions)
  (let* ((request-build-started-at (get-internal-real-time))
         (user-message (create-message session thread :user prompt
                                       :metadata (list :source source
                                                       :surface-context surface-context
                                                       :surface-actions surface-actions)
                                       :attachments attachments))
         (turn (start-turn session thread user-message
                           :metadata (list :source source
                                           :streamed-p nil
                                           :surface-context surface-context
                                           :surface-actions surface-actions)))
         (request (build-turn-provider-request session prompt thread turn operator-mode nil
                                              :attachments attachments
                                              :surface-context surface-context
                                              :surface-actions surface-actions))
         (request-ready-at (get-internal-real-time))
         (operation (start-operation session
                                     thread
                                     turn
                                     :provider-run
                                     (provider-name provider)
                                     (list :prompt prompt :streamed-p nil)
                                     :policy-decision (say-provider-operation-policy-decision)
                                     :metadata (list :source source
                                                     :retrieval-summary
                                                     (provider-request-retrieval-summary request)
                                                     :cognition-summary
                                                     (provider-request-cognition-summary request)
                                                     :reasoning-summary
                                                     (provider-request-reasoning-summary request)
                                                     :planning-summary
                                                     (provider-request-planning-summary request))))
         (response-started-at nil)
         (response (progn
                     (record-turn-latency-sample session
                                                 thread
                                                 turn
                                                 source
                                                 :request-built
                                                 (list :request-build-seconds
                                                       (internal-elapsed-seconds request-build-started-at
                                                                                 request-ready-at)
                                                       :stream-p nil))
                     (record-turn-request-trace session thread turn request source)
                     (let ((*provider-timing-listener*
                             (make-provider-timing-listener session thread turn source)))
                       (setf response-started-at (get-internal-real-time))
                       (send-provider-request provider request))))
         (response-completed-at (get-internal-real-time))
         (action-report (process-response-actions response
                                                 session
                                                 :cognition-bundle
                                                 (provider-request-cognition-bundle request)
                                                 :reasoning-brief
                                                 (provider-request-reasoning-brief request)
                                                 :retrieval-dossier
                                                 (provider-request-retrieval-dossier request)
                                                 :prompt prompt
                                                 :surface-context surface-context))
         (work-item (ensure-turn-mutation-work-item session
                                                   thread
                                                   turn
                                                   action-report
                                                   prompt
                                                   :cognition-bundle (provider-request-cognition-bundle request)))
         (immediate-results (getf action-report :immediate-results))
         (completed-operation (complete-operation session
                                                 thread
                                                 turn
                                                 operation
                                                 (list :message (assistant-response-message response)
                                                       :stream-event-count 0
                                                       :staged-action-count (length (getf action-report :staged-actions))
                                                       :deferred-action-count (length (getf action-report :deferred-actions)))
                                                 :metadata (list :model-response-p t)))
         (action-operations (record-assistant-action-operations session
                                                                thread
                                                                turn
                                                                action-report
                                                                :work-item work-item))
         (assistant-message (create-message session thread :assistant (assistant-response->string response)
                                            :content-type :text
                                            :metadata (list :source source :streamed-p nil)
                                            :attachments (getf (assistant-response-metadata response) :attachments)))
         (completed-turn (complete-turn session
                                        thread
                                        turn
                                        assistant-message
                                        :status (turn-status-from-action-operations action-operations)
                                        :metadata (list :stream-event-count 0
                                                        :operation-id (operation-id completed-operation)
                                                        :action-operation-ids (mapcar #'operation-id action-operations)))))
    (record-turn-latency-sample session
                                thread
                                turn
                                source
                                :response-complete
                                (list :request-build-seconds
                                      (internal-elapsed-seconds request-build-started-at
                                                                request-ready-at)
                                      :provider-response-seconds
                                      (internal-elapsed-seconds response-started-at
                                                                response-completed-at)
                                      :total-response-seconds
                                      (internal-elapsed-seconds request-build-started-at
                                                                response-completed-at)
                                      :stream-p nil))
    (append-transcript-entry session :assistant (assistant-response->string response))
    (append-session-event session
                          :assistant-response
                          response
                          :family :assistant
                          :thread-id (thread-id thread)
                          :turn-id (turn-id completed-turn)
                          :visibility :operator)
    (when (calculator-control-actions-p (getf action-report :immediate-actions))
      (append-conversation-calculator-control-event session
                                                    thread
                                                    completed-turn
                                                    prompt
                                                    (getf action-report :immediate-actions)
                                                    immediate-results
                                                    :source source))
    (record-turn-memory-entry session
                              thread
                              completed-turn
                              request
                              prompt
                              (assistant-response->string response))
    (emit-conversation-progress (conversation-progress-phase source :response)
                                (list :message (assistant-response-message response)
                                      :staged-action-count (length (getf action-report :staged-actions))
                                      :deferred-action-count (length (getf action-report :deferred-actions))
                                      :immediate-action-count (length (getf action-report :immediate-actions))
                                      :stream-event-count 0
                                      :retrieval-summary (provider-request-retrieval-summary request)
                                      :cognition-summary (provider-request-cognition-summary request)
                                      :action-agenda-summary (provider-request-action-agenda-summary request)
                                      :reasoning-summary (provider-request-reasoning-summary request)
                                      :planning-summary (provider-request-planning-summary request)
                                      :thread-id (thread-id thread)
                                      :turn-id (turn-id completed-turn)))
    (make-say-turn-result thread
                          user-message
                          assistant-message
                          completed-turn
                          response
                          action-report
                          :streamed-p nil
                          :stream-event-count 0
                          :action-results immediate-results
                          :retrieval-summary (provider-request-retrieval-summary request)
                          :cognition-summary (provider-request-cognition-summary request)
                          :action-agenda-summary (provider-request-action-agenda-summary request)
                          :reasoning-summary (provider-request-reasoning-summary request)
                          :planning-summary (provider-request-planning-summary request)
                          :outcome-summary (provider-request-outcome-summary request))))

(defun run-conversation-turn (provider session prompt
                              &key stream-p (source :say) (operator-mode :conversation)
                                attachments surface-context surface-actions)
  (let ((thread (current-thread session)))
    (append-transcript-entry session :user prompt)
    (emit-conversation-progress (conversation-progress-phase source :started)
                                (list :prompt prompt
                                      :stream-p stream-p
                                      :thread-id (thread-id thread)))
    (if stream-p
        (run-conversation-turn-streaming provider session thread prompt
                                         :source source
                                         :operator-mode operator-mode
                                         :attachments attachments
                                         :surface-context surface-context
                                         :surface-actions surface-actions)
        (run-conversation-turn-sync provider session thread prompt
                                    :source source
                                    :operator-mode operator-mode
                                    :attachments attachments
                                    :surface-context surface-context
                                    :surface-actions surface-actions))))

(defun run-say-turn-streaming (provider session thread prompt)
  (run-conversation-turn-streaming provider session thread prompt
                                   :source :say
                                   :operator-mode :conversation))

(defun run-say-turn-sync (provider session thread prompt)
  (run-conversation-turn-sync provider session thread prompt
                              :source :say
                              :operator-mode :conversation))

(defun run-say-turn (provider session prompt &key stream-p)
  (run-conversation-turn provider session prompt
                         :stream-p stream-p
                         :source :say
                         :operator-mode :conversation))

(defun continue-conversation-turn (provider session thread turn
                                    &key (source (or (getf (turn-metadata turn) :source) :say))
                                      action-results
                                      (operator-mode :conversation))
  (let* ((user-message (find-message session (turn-user-message-id turn)))
         (prompt (and user-message (message-content user-message))))
    (unless prompt
      (error "Cannot continue turn ~A without a persisted user prompt" (turn-id turn)))
    (mark-turn-followup-started session
                                turn
                                :metadata (list :followup-source source
                                                :followup-operator-mode operator-mode))
    (let* ((post-mutation-p (action-results-post-mutation-p action-results))
           (request (if post-mutation-p
                        (build-post-mutation-provider-request session
                                                             prompt
                                                             thread
                                                             turn
                                                             operator-mode
                                                             action-results)
                        (build-turn-provider-request session prompt thread turn operator-mode nil)))
           (operation (start-operation session
                                       thread
                                       turn
                                       :provider-run
                                       (provider-name provider)
                                       (list :prompt prompt :followup-p t)
                                       :policy-decision (say-provider-operation-policy-decision)
                                       :metadata (list :source source
                                                       :followup-p t
                                                       :retrieval-summary
                                                       (provider-request-retrieval-summary request)
                                                       :cognition-summary
                                                       (provider-request-cognition-summary request)
                                                       :reasoning-summary
                                                       (provider-request-reasoning-summary request)
                                                       :planning-summary
                                                       (provider-request-planning-summary request)
                                                       :outcome-summary
                                                       (provider-request-outcome-summary request))))
           (response (progn
                       (record-turn-retrieval-dossier session
                                                      thread
                                                      turn
                                                      request
                                                      source
                                                      :phase (if post-mutation-p
                                                                 :post-mutation
                                                                 :pre-prompt))
                       (record-turn-reasoning-brief session
                                                    thread
                                                    turn
                                                    request
                                                    source
                                                    :phase (if post-mutation-p
                                                               :post-mutation
                                                               :pre-prompt))
                       (record-turn-planning-brief session
                                                   thread
                                                   turn
                                                   request
                                                   source
                                                   :phase (if post-mutation-p
                                                              :post-mutation
                                                              :pre-prompt))
                       (record-turn-cognition-bundle session
                                                     thread
                                                     turn
                                                     request
                                                     source
                                                     :phase (if post-mutation-p
                                                                :post-mutation
                                                                :pre-prompt))
                       (record-turn-outcome-brief session
                                                  thread
                                                  turn
                                                  request
                                                  source
                                                  :phase (if post-mutation-p
                                                             :post-mutation
                                                             :pre-prompt))
                       (send-provider-request provider request)))
           (action-report (process-response-actions response
                                                   session
                                                   :cognition-bundle
                                                   (provider-request-cognition-bundle request)
                                                   :reasoning-brief
                                                   (provider-request-reasoning-brief request)
                                                   :retrieval-dossier
                                                   (provider-request-retrieval-dossier request)
                                                   :prompt prompt
                                                   :surface-context
                                                   (provider-request-surface-context request)))
           (work-item (ensure-turn-mutation-work-item session
                                                     thread
                                                     turn
                                                     action-report
                                                     prompt
                                                     :cognition-bundle (provider-request-cognition-bundle request)))
           (immediate-results (getf action-report :immediate-results))
           (completed-operation (complete-operation session
                                                   thread
                                                   turn
                                                   operation
                                                   (list :message (assistant-response-message response)
                                                         :stream-event-count 0
                                                         :staged-action-count (length (getf action-report :staged-actions))
                                                         :deferred-action-count (length (getf action-report :deferred-actions))
                                                         :followup-p t)
                                                   :metadata (list :model-response-p t
                                                                   :followup-p t)))
           (action-operations (record-assistant-action-operations session
                                                                  thread
                                                                  turn
                                                                  action-report
                                                                  :work-item work-item))
           (assistant-message (create-message session
                                             thread
                                             :assistant
                                             (assistant-response->string response)
                                             :turn-id (turn-id turn)
                                             :content-type :text
                                             :metadata (list :source source
                                                             :followup-p t)))
           (completed-turn (complete-turn session
                                          thread
                                          turn
                                          assistant-message
                                          :status (turn-status-from-action-operations action-operations)
                                          :metadata (list :followup-operation-id (operation-id completed-operation)
                                                          :followup-action-operation-ids (mapcar #'operation-id action-operations)))))
      (append-transcript-entry session :assistant (assistant-response->string response))
      (append-session-event session
                            :assistant-response
                            response
                            :family :assistant
                            :thread-id (thread-id thread)
                            :turn-id (turn-id completed-turn)
                            :visibility :operator)
      (record-turn-memory-entry session
                                thread
                                completed-turn
                                request
                                prompt
                                (assistant-response->string response))
      (mark-turn-followup-completed session
                                    turn
                                    :metadata (list :followup-operation-id (operation-id completed-operation)
                                                    :followup-assistant-message-id (message-id assistant-message)))
      (emit-conversation-progress (conversation-progress-phase source :response)
                                  (list :message (assistant-response-message response)
                                        :staged-action-count (length (getf action-report :staged-actions))
                                        :immediate-action-count (length (getf action-report :immediate-actions))
                                        :stream-event-count 0
                                        :retrieval-summary (provider-request-retrieval-summary request)
                                        :cognition-summary (provider-request-cognition-summary request)
                                        :action-agenda-summary (provider-request-action-agenda-summary request)
                                        :reasoning-summary (provider-request-reasoning-summary request)
                                        :planning-summary (provider-request-planning-summary request)
                                        :outcome-summary (provider-request-outcome-summary request)
                                        :thread-id (thread-id thread)
                                        :turn-id (turn-id completed-turn)
                                        :followup-p t))
      (list :response response
            :staged-action-count (length (getf action-report :staged-actions))
            :deferred-action-count (length (getf action-report :deferred-actions))
            :immediate-action-count (length (getf action-report :immediate-actions))
            :action-results immediate-results
            :streamed-p nil
            :stream-event-count 0
            :retrieval-summary (provider-request-retrieval-summary request)
            :cognition-summary (provider-request-cognition-summary request)
            :action-agenda-summary (provider-request-action-agenda-summary request)
            :reasoning-summary (provider-request-reasoning-summary request)
            :planning-summary (provider-request-planning-summary request)
            :outcome-summary (provider-request-outcome-summary request)
            :followup-p t
            :thread (thread-record-summary thread)
            :turn (turn-record-summary completed-turn)
            :assistant-message (message-record-summary assistant-message)))))

(defun operation-assistant-action (operation)
  (getf (operation-metadata operation) :assistant-action))

(defun operation-desktop-task-record-ids (operation)
  (copy-list (or (getf (operation-metadata operation) :desktop-task-record-ids)
                 '())))

(defun desktop-task-records-for-operations (session operations)
  (let ((record-ids
          (remove-duplicates
           (loop for operation in operations
                 append (operation-desktop-task-record-ids operation))
           :test #'string=)))
    (remove nil
            (mapcar (lambda (record-id)
                      (find-desktop-task-record session record-id))
                    record-ids))))

(defun turn-pending-action-operations (session turn)
  (remove-if-not (lambda (operation)
                   (and (eq (operation-kind operation) :assistant-action)
                        (operation-assistant-action operation)
                        (or (eq (operation-status operation) :awaiting-approval)
                            (eq (operation-status operation) :staged))))
                 (list-turn-operations session (turn-id turn))))

(defun execute-turn-pending-actions (session operations &key thread turn)
  (let ((actions (remove nil (mapcar #'operation-assistant-action operations))))
    (unless actions
      (error "No assistant actions are attached to the selected turn"))
    (let ((results
            (mapcar
             (lambda (operation)
               (let ((action (operation-assistant-action operation)))
                 (handler-case
                     (let* ((response
                              (command-execute-assistant-action-service
                               session
                               action
                               :thread thread
                               :turn turn
                               :operation operation))
                            (metadata (service-response-metadata response)))
                       (list :action action
                             :status :completed
                             :kernel-execution-id (getf metadata :execution-id)
                             :result (service-response-data response)))
                   (error (condition)
                     (let ((incident
                             (or (latest-operation-incident session operation)
                                 (record-runtime-incident session
                                                          condition
                                                          :thread thread
                                                          :turn turn
                                                          :operation operation
                                                          :kind :assistant-action-failure
                                                          :title "Assistant action failed"
                                                          :summary (princ-to-string condition)
                                                          :metadata (list :source :turn-resume
                                                                          :action-type (assistant-action-type action))))))
                       (list :action action
                             :status :failed
                             :error (princ-to-string condition)
                             :incident (incident-record-summary incident)))))))
             operations)))
      (append-session-event session :assistant-actions-executed results)
      (remove-pending-actions session actions)
      results)))

(defun turn-resume-work-item-id (turn)
  (or (turn-bound-work-item-id turn)
      (getf (turn-metadata turn) :work-item-id)))

(defun turn-resume-workflow-record-id (session turn)
  (or (getf (turn-metadata turn) :workflow-record-id)
      (let* ((work-item-id (turn-resume-work-item-id turn))
             (work-item (and work-item-id
                             (find-work-item session work-item-id))))
        (and work-item
             (work-item-workflow-record-ref work-item)))))

(defun turn-resume-plan-id (session turn)
  (or (getf (turn-metadata turn) :plan-id)
      (let* ((workflow-record-id (turn-resume-workflow-record-id session turn))
             (workflow-record (and workflow-record-id
                                   (find-workflow-record session workflow-record-id))))
        (and workflow-record
             (workflow-record-plan-id workflow-record)))))

(defun make-turn-resume-request (session turn source operator-mode)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :workflow
   :operation :resume-turn
   :capability :workflow/resume
   :payload (list :turn-id (turn-id turn)
                  :source source
                  :operator-mode operator-mode)
   :metadata (append (list :session-id (agent-session-id session)
                           :turn-id (turn-id turn)
                           :thread-id (turn-thread-id turn)
                           :actor-slice :workflow-turn-resume-v1)
                     (when (turn-resume-work-item-id turn)
                       (list :work-item-id (turn-resume-work-item-id turn)))
                     (when (turn-resume-workflow-record-id session turn)
                       (list :workflow-record-id (turn-resume-workflow-record-id session turn)))
                     (when (turn-resume-plan-id session turn)
                       (list :plan-id (turn-resume-plan-id session turn))))))

(defun actorize-turn-resume-result (result &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp result))
      (let ((updated (copy-list result)))
        (setf (getf updated :actor-execution-job-id) actor-execution-job-id)
        updated)
      result))

(defun turn-pending-governed-desktop-task-records (session turn)
  (remove-if-not
   (lambda (record)
     (and (eq (desktop-task-record-approval-status record) :awaiting-approval)
          (or (eq (desktop-task-record-status record) :awaiting-approval)
              (eq (desktop-task-record-status record) :retryable-failure))))
   (desktop-task-records-for-turn session (turn-id turn))))

(defun maybe-recover-turn-resume-from-workflow-checkpoint (session turn)
  (when (fboundp 'recover-turn-resume-from-workflow-checkpoint)
    (recover-turn-resume-from-workflow-checkpoint session
                                                  turn
                                                  :recovery-origin :turn-resume))
  turn)

(defun execute-turn-governed-desktop-task-records (session records &key thread turn)
  (let ((results '()))
    (dolist (record records (nreverse results))
      (let* ((request (make-desktop-task-request-from-record record)))
        (handler-case
            (let* ((response
                     (command-desktop-task-invoke-service
                      session
                      :request request
                      :register-record-p nil
                      :retry-reason "Retrying governed desktop task after approval."
                      :thread-id (and thread (thread-id thread))
                      :turn-id (and turn (turn-id turn))))
                   (data (service-response-data response))
                   (task-record (or (find-desktop-task-record session
                                                              (desktop-task-record-id record))
                                    record))
                   (status (desktop-task-record-status task-record))
                   (result (getf data :result)))
              (push (list :record-id (desktop-task-record-id task-record)
                          :request-id (desktop-task-request-id request)
                          :status status
                          :actor-execution-job-id
                          (or (getf data :actor-execution-job-id)
                              (and (listp (desktop-task-record-metadata task-record))
                                   (getf (desktop-task-record-metadata task-record)
                                         :actor-execution-job-id)))
                          :result result)
                    results))
          (error (condition)
            (let* ((error-summary
                     (list :summary "Desktop task execution failed during resumed execution."
                           :error (princ-to-string condition)
                           :failure-classification :execution))
                   (incident
                     (record-runtime-incident session
                                              condition
                                              :thread thread
                                              :turn turn
                                              :kind :desktop-task-failure
                                              :title "Desktop task execution failed"
                                              :summary (princ-to-string condition)
                                              :metadata (list :source :turn-resume
                                                              :desktop-task-record-id
                                                              (desktop-task-record-id record)
                                                              :target (desktop-task-record-target record)
                                                              :operation (desktop-task-record-operation record)))))
              (mark-desktop-task-record-failed
               session
               record
               (append error-summary
                       (list :incident (incident-record-summary incident)))
               :retryable-p (desktop-task-retryable-p record))
              (push (list :record-id (desktop-task-record-id record)
                          :request-id (desktop-task-request-id request)
                          :status :failed
                          :error (princ-to-string condition)
                          :incident (incident-record-summary incident)
                          :result error-summary)
                    results))))))))

(defun resume-turn-operation-results (turn operations results &key followup)
  (list :turn-id (turn-id turn)
        :resumed-operation-count (length operations)
        :action-result-count (length results)
        :action-results results
        :followup followup))

(defun update-turn-desktop-task-records-from-resume-results (session turn operations results)
  (declare (ignore turn))
  (let ((record-results (make-hash-table :test #'equal)))
    (loop for operation in operations
          for result in results
          do (dolist (record-id (operation-desktop-task-record-ids operation))
               (push result (gethash record-id record-results))))
    (maphash
     (lambda (record-id associated-results)
       (let* ((record (find-desktop-task-record session record-id))
              (ordered-results (nreverse associated-results))
              (failed-results
                (remove-if-not (lambda (result)
                                 (eq (getf result :status) :failed))
                               ordered-results)))
         (when record
           (if (eq (desktop-task-record-status record) :retryable-failure)
               (mark-desktop-task-record-retrying
                session
                record
                :reason "Retrying governed desktop task after resumable failure.")
               (mark-desktop-task-record-executing session record))
           (if failed-results
               (mark-desktop-task-record-failed
                session
                record
                (list :summary "Desktop task execution failed during resumed execution."
                      :failed-result-count (length failed-results)
                      :results failed-results
                      :operation-count (length ordered-results))
                :retryable-p (desktop-task-retryable-p record))
               (mark-desktop-task-record-completed
                session
                record
                (list :summary "Desktop task completed during resumed execution."
                      :result-count (length ordered-results)
                      :results ordered-results))))))
     record-results)))

(defun perform-resume-conversation-turn (provider session turn
                                         &key (source (or (getf (turn-metadata turn) :source) :say))
                                           (operator-mode :conversation))
  (maybe-recover-turn-resume-from-workflow-checkpoint session turn)
  (let ((operations (turn-pending-action-operations session turn)))
    (unless (eq (turn-status turn) :awaiting-approval)
      (error "TURN/RESUME requires a turn in :awaiting-approval state"))
    (dolist (operation operations)
      (let* ((decision (operation-policy-decision operation))
             (policy-id (getf decision :policy-id)))
        (when policy-id
          (ensure-policy-approved session policy-id))))
    (let* ((thread (or (find-thread session (turn-thread-id turn))
                       (current-thread session)))
           (governed-records (turn-pending-governed-desktop-task-records session turn))
           (workflow-record-id (turn-resume-workflow-record-id session turn))
           (workflow-record (and workflow-record-id
                                 (find-workflow-record session workflow-record-id)))
           (actor-execution-job-id (current-actor-execution-job-id)))
      (when workflow-record
        (mark-workflow-record-turn-resume-started session
                                                  workflow-record
                                                  turn
                                                  :source source
                                                  :actor-execution-job-id actor-execution-job-id
                                                  :operations operations
                                                  :governed-records governed-records))
      (handler-case
          (let* ((desktop-task-records (desktop-task-records-for-operations session operations))
                 (action-results (if operations
                                     (execute-turn-pending-actions session
                                                                   operations
                                                                   :thread thread
                                                                   :turn turn)
                                     '()))
                 (governed-results (if governed-records
                                       (execute-turn-governed-desktop-task-records session
                                                                                   governed-records
                                                                                   :thread thread
                                                                                   :turn turn)
                                       '()))
                 (results (append action-results governed-results))
                 (followup nil))
            (when desktop-task-records
              (update-turn-desktop-task-records-from-resume-results session
                                                                    turn
                                                                    operations
                                                                    action-results))
            (loop for operation in operations
                  for result in action-results
                  do (apply-resumed-mutation-result session thread turn operation result))
            (refresh-turn-status session
                                 turn
                                 :status (if governed-records
                                             (if (find :failed results :key (lambda (entry)
                                                                              (getf entry :status)))
                                                 :failed
                                                 :completed)
                                             nil)
                                 :metadata '(:resumed-p t))
            (when (and provider
                       (provider-turn-followup-p provider)
                       (eq (turn-status turn) :completed))
              (setf followup (continue-conversation-turn provider
                                                         session
                                                         thread
                                                         turn
                                                         :source source
                                                         :action-results results
                                                         :operator-mode operator-mode)))
            (when workflow-record
              (mark-workflow-record-turn-resume-completed session
                                                          workflow-record
                                                          turn
                                                          results
                                                          :followup followup
                                                          :actor-execution-job-id actor-execution-job-id))
            (resume-turn-operation-results turn operations results :followup followup))
        (error (condition)
          (when workflow-record
            (mark-workflow-record-turn-resume-failed session
                                                     workflow-record
                                                     turn
                                                     condition
                                                     :actor-execution-job-id actor-execution-job-id))
          (error condition))))))

(defun resume-conversation-turn (provider session turn
                                 &key (source (or (getf (turn-metadata turn) :source) :say))
                                   (operator-mode :conversation))
  (let* ((request (make-turn-resume-request session turn source operator-mode))
         (actor-address (make-standard-actor-address :workflow
                                                     :scope (agent-session-id session))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-turn-resume-result
        (perform-resume-conversation-turn provider
                                          session
                                          turn
                                          :source source
                                          :operator-mode operator-mode)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability :workflow/resume
               :authority :operator
               :target :workflow
               :operation :resume-turn
               :request-id (desktop-task-request-id request)
               :thread-id (turn-thread-id turn)
               :turn-id (turn-id turn)
               :work-item-id (turn-resume-work-item-id turn)
               :workflow-record-id (turn-resume-workflow-record-id session turn)
               :plan-id (turn-resume-plan-id session turn)))))
