(in-package #:sbcl-agent)

(defstruct environment-conversation-state
  threads
  active-thread-id
  messages
  turns
  operations
  artifacts
  summaries)

(defun environment-artifact-summary-from-conversation-state (conversation-state)
  (artifact-summary-from-records
   (or (and conversation-state
            (environment-conversation-state-artifacts conversation-state))
       '())))

(defun environment-conversation-domain-summary (environment)
  (let ((conversation-state (environment-conversation-state environment)))
    (and conversation-state
         (environment-conversation-state-summaries conversation-state))))

(defun make-environment-conversation-state-from-session (session)
  (make-environment-conversation-state
   :threads (mapcar #'thread-record-summary (agent-session-threads session))
   :active-thread-id (agent-session-current-thread-id session)
   :messages (mapcar #'message-record-summary (agent-session-messages session))
   :turns (mapcar #'turn-record-summary (agent-session-turns session))
   :operations (mapcar #'operation-record-summary (agent-session-operations session))
   :artifacts (mapcar #'artifact-record-summary (agent-session-artifacts session))
   :summaries (list :thread-count (length (agent-session-threads session))
                    :message-count (length (agent-session-messages session))
                    :turn-count (length (agent-session-turns session))
                    :operation-count (length (agent-session-operations session))
                    :artifact-count (length (agent-session-artifacts session))
                    :artifact-summary (artifact-summary-from-records
                                       (mapcar #'artifact-record-summary
                                               (agent-session-artifacts session)))
                    :active-thread-id (agent-session-current-thread-id session))))

(defun ensure-environment-conversation-state (environment session)
  (or (environment-conversation-state environment)
      (let ((conversation-state
              (make-environment-conversation-state-from-session session)))
        (setf (environment-conversation-state environment) conversation-state)
        conversation-state)))

(defun refresh-environment-conversation-domain (environment session)
  (let ((conversation-state (ensure-environment-conversation-state environment session)))
    (setf (environment-conversation-state-active-thread-id conversation-state)
          (agent-session-current-thread-id session)
          (environment-conversation-state-threads conversation-state)
          (mapcar #'thread-record-summary (agent-session-threads session))
          (environment-conversation-state-messages conversation-state)
          (mapcar #'message-record-summary (agent-session-messages session))
          (environment-conversation-state-turns conversation-state)
          (mapcar #'turn-record-summary (agent-session-turns session))
          (environment-conversation-state-operations conversation-state)
          (mapcar #'operation-record-summary (agent-session-operations session))
          (environment-conversation-state-artifacts conversation-state)
          (mapcar #'artifact-record-summary (agent-session-artifacts session))
          (environment-conversation-state-summaries conversation-state)
          (list :thread-count (length (environment-conversation-state-threads conversation-state))
                :message-count (length (environment-conversation-state-messages conversation-state))
                :turn-count (length (environment-conversation-state-turns conversation-state))
                :operation-count (length (environment-conversation-state-operations conversation-state))
                :artifact-count (length (environment-conversation-state-artifacts conversation-state))
                :artifact-summary (environment-artifact-summary-from-conversation-state conversation-state)
                :active-thread-id (agent-session-current-thread-id session)))
    (setf (environment-artifact-index environment)
          (environment-conversation-state-artifacts conversation-state))
    environment))

(defun environment-summary-active-thread-id (environment)
  (let* ((conversation-state (environment-conversation-state environment))
         (conversation-summary (environment-conversation-domain-summary environment)))
    (or (and conversation-summary
             (getf conversation-summary :active-thread-id))
        (and conversation-state
             (environment-conversation-state-active-thread-id conversation-state))
        (environment-active-thread-id environment))))

(defun environment-active-thread-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (conversation-state (environment-conversation-state active-environment))
         (active-thread-id (environment-summary-active-thread-id active-environment)))
    (when (and conversation-state active-thread-id)
      (find active-thread-id
            (environment-conversation-state-threads conversation-state)
            :key (lambda (entry) (getf entry :id))
            :test #'string=))))

(defun environment-active-turn-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (conversation-state (environment-conversation-state active-environment))
         (active-thread-id (environment-summary-active-thread-id active-environment))
         (turns (and conversation-state
                     (environment-conversation-state-turns conversation-state))))
    (when (and active-thread-id turns)
      (loop for turn in (reverse turns)
            when (string= (or (getf turn :thread-id) "")
                          active-thread-id)
              do (return turn)))))
