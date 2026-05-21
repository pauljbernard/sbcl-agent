(in-package #:sbcl-agent)

(defun context-chat-mailbox-entry-summary (record)
  (let* ((message (desktop-task-record-actor-message record))
         (request-metadata (desktop-task-record-request-metadata record))
         (record-metadata (desktop-task-record-metadata record))
         (reply-summary (desktop-task-actor-reply-summary record)))
    (list :session-id (desktop-task-record-session-id record)
          :approval-id (desktop-task-record-approval-id record)
          :record-id (desktop-task-record-id record)
          :request-id (desktop-task-record-request-id record)
          :actor-message-id (and message
                                 (actor-message-id message))
          :pending-action-id (desktop-task-record-pending-action-id record)
          :sender (and message
                       (actor-address-summary (actor-message-sender message)))
          :reply-to (and message
                         (actor-address-summary (actor-message-reply-to message)))
          :originator (and message
                           (actor-address-summary (actor-message-originator message)))
          :receiver (and message
                         (actor-address-summary (actor-message-receiver message)))
          :chat-actor (actor-address-summary
                       (make-standard-actor-address :context-chat
                                                    :scope (desktop-task-record-session-id record)
                                                    :metadata (when (desktop-task-record-session-id record)
                                                                (list :session-id (desktop-task-record-session-id record)))))
          :governance-actor (actor-address-summary
                             (make-governance-actor-address
                              :session-id (desktop-task-record-session-id record)))
          :target (desktop-task-record-target record)
          :operation (desktop-task-record-operation record)
          :capability (desktop-task-record-capability record)
          :actor-slice (or (and message
                                (actor-message-actor-slice message))
                           (getf request-metadata :actor-slice))
          :status (desktop-task-record-status record)
          :governance-status (desktop-task-record-governance-status record)
          :approval-status (desktop-task-record-approval-status record)
          :created-at (desktop-task-record-created-at record)
          :approved-at (desktop-task-record-approved-at record)
          :completed-at (desktop-task-record-completed-at record)
          :summary (or (getf record-metadata :summary)
                       (getf request-metadata :summary))
          :reply (and (member (desktop-task-record-status record) '(:completed :failed))
                      reply-summary)
          :actor-message (actor-message-summary message))))

(defun context-chat-mailbox-record-p (record)
  (let ((message (desktop-task-record-actor-message record)))
    (and message
         (or (eq (desktop-task-actor-role-for-record record :direction :sender) :context-chat)
             (eq (desktop-task-actor-role-for-record record :direction :receiver) :context-chat)
             (let ((originator (actor-message-originator message))
                   (reply-to (actor-message-reply-to message)))
               (or (and originator
                        (eq (actor-address-role originator) :context-chat))
                   (and reply-to
                        (eq (actor-address-role reply-to) :context-chat))))))))

(defun query-desktop-task-context-chat-mailbox-service (session
                                                        &key session-id status approval-status
                                                          latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (project-selection (and session
                                 (context-chat-project-selection-summary session)))
         (messages (remove-if-not
                    (lambda (entry)
                      (and (or (null session-id)
                               (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                                 (and entry-session-id
                                      (string= session-id entry-session-id))))
                           (or (null status)
                               (eq status (actor-mailbox-entry-status entry)))
                           (or (null approval-status)
                               (eq approval-status
                                   (actor-mailbox-entry-approval-status entry)))))
                    (copy-list (or (getf mailboxes :context-chat-mailbox) '()))))
        (selected (if latest-only-p
                       (if messages
                           (list (first messages))
                           '())
                       messages))
        (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected))))))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :context-chat-mailbox-latest :context-chat-mailbox)
     (list :session-id effective-session-id
           :chat-actor (actor-address-summary
                        (make-standard-actor-address :context-chat
                                                     :scope effective-session-id
                                                     :metadata (when effective-session-id
                                                                 (list :session-id effective-session-id))))
           :project-selection project-selection
           :message-count (length selected)
           :messages (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-context-chat-mailbox-latest-v1
                                                      :desktop-task-context-chat-mailbox-v1)
                                      :session session))))

(defun context-chat-approval-request-summary (record)
  (let ((entry (context-chat-mailbox-entry-summary record)))
    (list :session-id (getf entry :session-id)
          :thread-id (desktop-task-record-thread-id record)
          :turn-id (desktop-task-record-turn-id record)
          :policy-id (desktop-task-record-policy-id record)
          :approval-id (getf entry :approval-id)
          :record-id (getf entry :record-id)
          :request-id (getf entry :request-id)
          :actor-message-id (getf entry :actor-message-id)
          :pending-action-id (getf entry :pending-action-id)
          :chat-actor (getf entry :chat-actor)
          :governance-actor (getf entry :governance-actor)
          :sender (or (getf entry :governance-actor)
                      (getf entry :sender))
          :receiver (getf entry :chat-actor)
          :receiver-role (let ((receiver (getf entry :receiver)))
                           (and (listp receiver)
                                (or (getf receiver :role)
                                    (getf receiver :ROLE))))
          :target (getf entry :target)
          :operation (getf entry :operation)
          :status (getf entry :status)
          :governance-status (getf entry :governance-status)
          :approval-status (getf entry :approval-status)
          :summary (getf entry :summary)
          :created-at (getf entry :created-at)
          :actor-message (getf entry :actor-message))))

(defun query-desktop-task-context-chat-approval-inbox-service (session
                                                               &key session-id latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (project-selection (and session
                                 (context-chat-project-selection-summary session)))
         (requests (remove-if-not
                    (lambda (entry)
                      (or (null session-id)
                          (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                            (and entry-session-id
                                 (string= session-id entry-session-id)))))
                    (copy-list (or (getf mailboxes :context-chat-approval-inbox) '()))))
        (selected (if latest-only-p
                       (if requests (list (first requests)) '())
                       requests))
        (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected))))))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :context-chat-approval-inbox-latest :context-chat-approval-inbox)
     (list :session-id effective-session-id
           :chat-actor (actor-address-summary
                        (make-standard-actor-address :context-chat
                                                     :scope effective-session-id
                                                     :metadata (when effective-session-id
                                                                 (list :session-id effective-session-id))))
           :project-selection project-selection
           :request-count (length selected)
           :requests (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-context-chat-approval-inbox-latest-v1
                                                      :desktop-task-context-chat-approval-inbox-v1)
                                      :session session))))

(defun query-desktop-task-context-chat-context-service (session)
  (make-service-query-response
   :desktop-task
   :context-chat-context
   (append
    (list :session-id (agent-session-id session)
          :chat-actor (actor-address-summary
                       (make-standard-actor-address :context-chat
                                                    :scope (agent-session-id session)
                                                    :metadata (list :session-id (agent-session-id session)))))
    (context-chat-project-selection-summary session))
   :metadata (make-service-metadata :authority :environment
                                    :read-model :desktop-task-context-chat-context-v1
                                    :session session)))

(defun command-desktop-task-set-context-chat-projects-service (session project-ids
                                                               &key primary-project-id)
  (let ((selection
          (set-context-chat-project-selection session
                                              project-ids
                                              :primary-project-id primary-project-id)))
    (make-service-command-response
     :desktop-task
     :set-context-chat-projects
     (append (list :session-id (agent-session-id session))
             selection)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :desktop-task-set-context-chat-projects-v1
                                      :session session))))
