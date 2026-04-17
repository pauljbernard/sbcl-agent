(in-package #:sbcl-agent)

(defun policy-decision-summary (policy &key (decision :allowed) reason)
  (let ((policy-record (ensure-capability-policy policy)))
    (list :policy-id (capability-policy-id policy-record)
          :decision decision
          :risk-level (capability-policy-risk-level policy-record)
          :default-grant-mode (capability-policy-default-grant-mode policy-record)
          :reason reason)))

(defun say-provider-operation-policy-decision ()
  (policy-decision-summary :safe-read
                           :decision :allowed
                           :reason "Conversation provider runs are currently read-only orchestrator operations."))

(defun assistant-action-policy-decision (action disposition)
  (let ((policy-id (assistant-action-policy-id action)))
    (if policy-id
        (policy-decision-summary policy-id
                                 :decision disposition
                                 :reason "Assistant action recorded from conversation response handling.")
        (list :policy-id nil
              :decision disposition
              :reason "Assistant action recorded without a known policy mapping."))))

(defun assistant-action-policy-id (action)
  (case (assistant-action-type action)
    (:eval
     (if (mutating-eval-action-p action)
         :runtime-eval-mutate
         :runtime-eval-safe))
    (:tool
     (let* ((payload (assistant-action-payload action))
            (tool-id (or (getf payload :TOOL-ID)
                         (getf payload :TOOL_ID))))
       (and tool-id
            (ignore-errors (getf (describe-tool tool-id) :policy)))))
    (:patch :workspace-write)
    (t nil)))

(defun assistant-action-requires-approval-p (action)
  (let ((policy-id (assistant-action-policy-id action)))
    (and policy-id
         (let ((policy (ensure-capability-policy policy-id)))
           (not (eq (capability-policy-default-grant-mode policy) :implicit))))))

(defun governed-assistant-action-p (action)
  (let ((policy-id (assistant-action-policy-id action)))
    (or (eq (assistant-action-type action) :patch)
        (eq policy-id :runtime-eval-mutate)
        (member policy-id '(:workspace-write :git-write :process-run) :test #'eq))))

(defun staged-assistant-action-disposition (action)
  (if (assistant-action-requires-approval-p action)
      :approval-required
      :staged))

(defun staged-assistant-action-status (action)
  (if (assistant-action-requires-approval-p action)
      :awaiting-approval
      :staged))

(defun action-operation-name (action)
  (case (assistant-action-type action)
    (:eval "assistant-eval")
    (:tool "assistant-tool")
    (:patch "assistant-patch")
    (t "assistant-action")))

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

(defun governed-actions-present-p (action-report)
  (find-if #'governed-assistant-action-p
           (append (getf action-report :immediate-actions)
                   (getf action-report :staged-actions))))

(defun turn-bound-work-item-id (turn)
  (getf (turn-metadata turn) :work-item-id))

(defun ensure-turn-work-item (session thread turn action-report prompt)
  (let ((existing-id (turn-bound-work-item-id turn)))
    (cond
      (existing-id
       (find-work-item session existing-id))
      ((not (governed-actions-present-p action-report))
       nil)
      (t
       (let ((work-item (create-work-item session
                                          (format nil "Conversation turn ~A mutation" (turn-id turn))
                                          :mutation-intent (list :source :conversation-turn
                                                                 :thread-id (thread-id thread)
                                                                 :turn-id (turn-id turn)
                                                                 :prompt prompt
                                                                 :action-types (mapcar #'assistant-action-type
                                                                                       (append (getf action-report :immediate-actions)
                                                                                               (getf action-report :staged-actions))))
                                          :transaction-scope :conversation-turn)))
         (append-work-item-checkpoint session work-item
                                      :validation-baseline (list :turn-id (turn-id turn)
                                                                 :thread-id (thread-id thread)
                                                                 :prompt prompt))
         (append-work-item-runtime-observation session
                                               work-item
                                               :conversation-turn-bound
                                               (list :thread-id (thread-id thread)
                                                     :turn-id (turn-id turn)
                                                     :prompt prompt))
         (setf (turn-metadata turn)
               (append (turn-metadata turn)
                       (list :work-item-id (work-item-id work-item))))
         (let ((approval-action (find-if #'assistant-action-requires-approval-p
                                         (append (getf action-report :immediate-actions)
                                                 (getf action-report :staged-actions)))))
           (when approval-action
             (let ((policy-id (assistant-action-policy-id approval-action)))
               (request-work-item-approval session
                                           work-item
                                           policy-id
                                           :reason "Governed conversation turn requires explicit approval before mutation."))))
         work-item)))))

(defun record-assistant-action-operations (session thread turn action-report &key work-item)
  (let ((records '()))
    (dolist (entry (getf action-report :immediate-results))
      (let* ((action (getf entry :action))
             (result (getf entry :result))
         (operation (start-operation session
                                         thread
                                         turn
                                         :assistant-action
                                         (action-operation-name action)
                                         (assistant-action-payload action)
                                         :policy-decision (assistant-action-policy-decision action :allowed)
                                         :metadata (list :assistant-action-type (assistant-action-type action)
                                                         :assistant-action action
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
         (operation (start-operation session
                                         thread
                                         turn
                                         :assistant-action
                                         (action-operation-name action)
                                         (assistant-action-payload action)
                                         :policy-decision (assistant-action-policy-decision action disposition)
                                         :metadata (list :assistant-action-type (assistant-action-type action)
                                                         :assistant-action action
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
    (nreverse records)))

(defun make-say-turn-result (thread user-message assistant-message turn response action-report
                              &key streamed-p stream-event-count stream-events action-results)
  (append (list :response response
                :staged-action-count (length (getf action-report :staged-actions))
                :immediate-action-count (length (getf action-report :immediate-actions))
                :action-results action-results
                :streamed-p streamed-p
                :stream-event-count stream-event-count)
          (when stream-events
            (list :stream-events stream-events))
          (conversation-turn-summary thread user-message assistant-message turn)))

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

(defun run-conversation-turn-streaming (provider session thread prompt
                                         &key (source :say) (operator-mode :conversation))
  (let* ((user-message (create-message session thread :user prompt
                                       :metadata (list :source source)))
         (turn (start-turn session thread user-message
                           :metadata (list :source source :streamed-p t)))
         (operation (start-operation session
                                     thread
                                     turn
                                     :provider-run
                                     (provider-name provider)
                                     (list :prompt prompt :streamed-p t)
                                     :policy-decision (say-provider-operation-policy-decision)
                                     :metadata (list :source source)))
         (events '()))
    (let* ((response (stream-prompt provider
                                    prompt
                                    (lambda (event)
                                      (setf events (handle-provider-stream-event session event events)))
                                    session
                                    :thread thread
                                    :turn turn
                                    :operator-mode operator-mode))
           (action-report (process-response-actions response session))
           (work-item (ensure-turn-work-item session thread turn action-report prompt))
           (immediate-results (getf action-report :immediate-results))
           (completed-operation (complete-operation session
                                                   thread
                                                   turn
                                                   operation
                                                   (list :message (assistant-response-message response)
                                                         :stream-event-count (length events)
                                                         :staged-action-count (length (getf action-report :staged-actions)))
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
                                              :metadata (list :source source :streamed-p t)))
           (completed-turn (complete-turn session
                                          thread
                                          turn
                                          assistant-message
                                          :status (turn-status-from-action-operations action-operations)
                                          :metadata (list :stream-event-count (length events)
                                                          :operation-id (operation-id completed-operation)
                                                          :action-operation-ids (mapcar #'operation-id action-operations)))))
      (append-transcript-entry session :assistant (assistant-response->string response))
      (append-session-event session :assistant-response response)
      (emit-conversation-progress (conversation-progress-phase source :response)
                                  (list :message (assistant-response-message response)
                                        :staged-action-count (length (getf action-report :staged-actions))
                                        :immediate-action-count (length (getf action-report :immediate-actions))
                                        :stream-event-count (length events)
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
                            :action-results immediate-results))))

(defun run-conversation-turn-sync (provider session thread prompt
                                    &key (source :say) (operator-mode :conversation))
  (let* ((user-message (create-message session thread :user prompt
                                       :metadata (list :source source)))
         (turn (start-turn session thread user-message
                           :metadata (list :source source :streamed-p nil)))
         (operation (start-operation session
                                     thread
                                     turn
                                     :provider-run
                                     (provider-name provider)
                                     (list :prompt prompt :streamed-p nil)
                                     :policy-decision (say-provider-operation-policy-decision)
                                     :metadata (list :source source)))
         (response (send-prompt provider
                                prompt
                                session
                                :thread thread
                                :turn turn
                                :operator-mode operator-mode))
         (action-report (process-response-actions response session))
         (work-item (ensure-turn-work-item session thread turn action-report prompt))
         (immediate-results (getf action-report :immediate-results))
         (completed-operation (complete-operation session
                                                 thread
                                                 turn
                                                 operation
                                                 (list :message (assistant-response-message response)
                                                       :stream-event-count 0
                                                       :staged-action-count (length (getf action-report :staged-actions)))
                                                 :metadata (list :model-response-p t)))
         (action-operations (record-assistant-action-operations session
                                                                thread
                                                                turn
                                                                action-report
                                                                :work-item work-item))
         (assistant-message (create-message session thread :assistant (assistant-response->string response)
                                            :content-type :text
                                            :metadata (list :source source :streamed-p nil)))
         (completed-turn (complete-turn session
                                        thread
                                        turn
                                        assistant-message
                                        :status (turn-status-from-action-operations action-operations)
                                        :metadata (list :stream-event-count 0
                                                        :operation-id (operation-id completed-operation)
                                                        :action-operation-ids (mapcar #'operation-id action-operations)))))
    (append-transcript-entry session :assistant (assistant-response->string response))
    (append-session-event session :assistant-response response)
    (emit-conversation-progress (conversation-progress-phase source :response)
                                (list :message (assistant-response-message response)
                                      :staged-action-count (length (getf action-report :staged-actions))
                                      :immediate-action-count (length (getf action-report :immediate-actions))
                                      :stream-event-count 0
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
                          :action-results immediate-results)))

(defun run-conversation-turn (provider session prompt
                              &key stream-p (source :say) (operator-mode :conversation))
  (let ((thread (current-thread session)))
    (append-transcript-entry session :user prompt)
    (emit-conversation-progress (conversation-progress-phase source :started)
                                (list :prompt prompt
                                      :stream-p stream-p
                                      :thread-id (thread-id thread)))
    (if stream-p
        (run-conversation-turn-streaming provider session thread prompt
                                         :source source
                                         :operator-mode operator-mode)
        (run-conversation-turn-sync provider session thread prompt
                                    :source source
                                    :operator-mode operator-mode))))

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
                                      (operator-mode :conversation))
  (let* ((user-message (find-message session (turn-user-message-id turn)))
         (prompt (and user-message (message-content user-message))))
    (unless prompt
      (error "Cannot continue turn ~A without a persisted user prompt" (turn-id turn)))
    (mark-turn-followup-started session
                                turn
                                :metadata (list :followup-source source
                                                :followup-operator-mode operator-mode))
    (let* ((operation (start-operation session
                                       thread
                                       turn
                                       :provider-run
                                       (provider-name provider)
                                       (list :prompt prompt :followup-p t)
                                       :policy-decision (say-provider-operation-policy-decision)
                                       :metadata (list :source source
                                                       :followup-p t)))
           (response (send-prompt provider
                                  prompt
                                  session
                                  :thread thread
                                  :turn turn
                                  :operator-mode operator-mode))
           (action-report (process-response-actions response session))
           (work-item (ensure-turn-work-item session thread turn action-report prompt))
           (immediate-results (getf action-report :immediate-results))
           (completed-operation (complete-operation session
                                                   thread
                                                   turn
                                                   operation
                                                   (list :message (assistant-response-message response)
                                                         :stream-event-count 0
                                                         :staged-action-count (length (getf action-report :staged-actions))
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
      (append-session-event session :assistant-response response)
      (mark-turn-followup-completed session
                                    turn
                                    :metadata (list :followup-operation-id (operation-id completed-operation)
                                                    :followup-assistant-message-id (message-id assistant-message)))
      (emit-conversation-progress (conversation-progress-phase source :response)
                                  (list :message (assistant-response-message response)
                                        :staged-action-count (length (getf action-report :staged-actions))
                                        :immediate-action-count (length (getf action-report :immediate-actions))
                                        :stream-event-count 0
                                        :thread-id (thread-id thread)
                                        :turn-id (turn-id completed-turn)
                                        :followup-p t))
      (list :response response
            :staged-action-count (length (getf action-report :staged-actions))
            :immediate-action-count (length (getf action-report :immediate-actions))
            :action-results immediate-results
            :streamed-p nil
            :stream-event-count 0
            :followup-p t
            :thread (thread-record-summary thread)
            :turn (turn-record-summary completed-turn)
            :assistant-message (message-record-summary assistant-message)))))
