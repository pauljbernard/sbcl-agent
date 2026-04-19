(in-package #:sbcl-agent)

(defun say-provider-operation-policy-decision ()
  (mutation-policy-decision-summary :safe-read
                                    :decision :allowed
                                    :reason "Conversation provider runs are currently read-only orchestrator operations."))

(defun staged-assistant-action-disposition (action)
  (if (assistant-action-requires-approval-p action)
      :approval-required
      :staged))

(defun staged-assistant-action-status (action)
  (if (assistant-action-requires-approval-p action)
      :awaiting-approval
      :staged))

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
         (run-id (format nil "provider-run-~A" (operation-id operation)))
         (events '()))
    (let* ((response (stream-prompt provider
                                    prompt
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
                                      (setf events (handle-provider-stream-event session
                                                                                event
                                                                                events
                                                                                :thread-id (thread-id thread)
                                                                                :turn-id (turn-id turn)
                                                                                :run-id run-id
                                                                                :operation-id (operation-id operation))))
                                    session
                                    :thread thread
                                    :turn turn
                                    :operator-mode operator-mode))
           (action-report (process-response-actions response session))
           (work-item (ensure-turn-mutation-work-item session thread turn action-report prompt))
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
         (work-item (ensure-turn-mutation-work-item session thread turn action-report prompt))
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
           (work-item (ensure-turn-mutation-work-item session thread turn action-report prompt))
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

(defun operation-assistant-action (operation)
  (getf (operation-metadata operation) :assistant-action))

(defun turn-pending-action-operations (session turn)
  (remove-if-not (lambda (operation)
                   (or (eq (operation-status operation) :awaiting-approval)
                       (eq (operation-status operation) :staged)))
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
                     (list :action action
                           :status :completed
                           :result (execute-assistant-action action
                                                            session
                                                            :thread thread
                                                            :turn turn
                                                            :operation operation))
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

(defun resume-turn-operation-results (turn operations results &key followup)
  (list :turn-id (turn-id turn)
        :resumed-operation-count (length operations)
        :action-result-count (length results)
        :action-results results
        :followup followup))

(defun resume-conversation-turn (provider session turn
                                  &key (source (or (getf (turn-metadata turn) :source) :say))
                                    (operator-mode :conversation))
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
           (results (execute-turn-pending-actions session
                                                  operations
                                                  :thread thread
                                                  :turn turn))
           (followup nil))
      (loop for operation in operations
            for result in results
            do (apply-resumed-mutation-result session thread turn operation result))
      (refresh-turn-status session turn :metadata '(:resumed-p t))
      (when (and provider
                 (provider-turn-followup-p provider)
                 (eq (turn-status turn) :completed))
        (setf followup (continue-conversation-turn provider
                                                   session
                                                   thread
                                                   turn
                                                   :source source
                                                   :operator-mode operator-mode)))
      (resume-turn-operation-results turn operations results :followup followup))))
