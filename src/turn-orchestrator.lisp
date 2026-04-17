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
  (case (assistant-action-type action)
    (:eval
     (policy-decision-summary :runtime-eval-safe
                              :decision disposition
                              :reason "Eval actions are currently auto-executed only in the immediate action lane."))
    (:tool
     (let* ((payload (assistant-action-payload action))
            (tool-id (or (getf payload :TOOL-ID)
                         (getf payload :TOOL_ID)))
            (tool-policy (and tool-id
                              (ignore-errors (getf (describe-tool tool-id) :policy)))))
       (if tool-policy
           (policy-decision-summary tool-policy
                                    :decision disposition
                                    :reason "Tool action recorded from assistant response handling.")
           (list :policy-id nil
                 :decision disposition
                 :reason "Tool action recorded without a registered tool policy."))))
    (:patch
     (policy-decision-summary :workspace-write
                              :decision disposition
                              :reason "Patch actions are staged through the workspace write path."))
    (t
     (list :policy-id nil
           :decision disposition
           :reason "Assistant action recorded without a known policy mapping."))))

(defun staged-assistant-action-disposition (action)
  (case (assistant-action-type action)
    (:patch :approval-required)
    (t :staged)))

(defun staged-assistant-action-status (action)
  (case (assistant-action-type action)
    (:patch :awaiting-approval)
    (t :staged)))

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

(defun record-assistant-action-operations (session thread turn action-report)
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

(defun emit-say-progress (phase payload)
  (when *task-progress-callback*
    (funcall *task-progress-callback* phase payload)))

(defun run-say-turn-streaming (provider session thread prompt)
  (let* ((user-message (create-message session thread :user prompt
                                       :metadata (list :source :say)))
         (turn (start-turn session thread user-message
                           :metadata (list :source :say :streamed-p t)))
         (operation (start-operation session
                                     thread
                                     turn
                                     :provider-run
                                     (provider-name provider)
                                     (list :prompt prompt :streamed-p t)
                                     :policy-decision (say-provider-operation-policy-decision)
                                     :metadata (list :source :say)))
         (events '()))
    (let* ((response (stream-prompt provider
                                    prompt
                                    (lambda (event)
                                      (setf events (handle-provider-stream-event session event events)))
                                    session))
           (action-report (process-response-actions response session))
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
                                                                  action-report))
           (assistant-message (create-message session thread :assistant (assistant-response->string response)
                                              :content-type :text
                                              :stream-fragments (mapcar #'provider-event-payload
                                                                        (remove-if-not #'provider-text-delta-event-p events))
                                              :metadata (list :source :say :streamed-p t)))
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
      (emit-say-progress :say-response
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

(defun run-say-turn-sync (provider session thread prompt)
  (let* ((user-message (create-message session thread :user prompt
                                       :metadata (list :source :say)))
         (turn (start-turn session thread user-message
                           :metadata (list :source :say :streamed-p nil)))
         (operation (start-operation session
                                     thread
                                     turn
                                     :provider-run
                                     (provider-name provider)
                                     (list :prompt prompt :streamed-p nil)
                                     :policy-decision (say-provider-operation-policy-decision)
                                     :metadata (list :source :say)))
         (response (send-prompt provider prompt session))
         (action-report (process-response-actions response session))
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
                                                                action-report))
         (assistant-message (create-message session thread :assistant (assistant-response->string response)
                                            :content-type :text
                                            :metadata (list :source :say :streamed-p nil)))
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
    (emit-say-progress :say-response
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

(defun run-say-turn (provider session prompt &key stream-p)
  (let ((thread (current-thread session)))
    (append-transcript-entry session :user prompt)
    (emit-say-progress :say-started
                       (list :prompt prompt
                             :stream-p stream-p
                             :thread-id (thread-id thread)))
    (if stream-p
        (run-say-turn-streaming provider session thread prompt)
        (run-say-turn-sync provider session thread prompt))))
