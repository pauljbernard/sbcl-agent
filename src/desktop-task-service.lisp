(in-package #:sbcl-agent)

(defun desktop-task-actor-message-for-record (record)
  (desktop-task-record-actor-message record))

(defun desktop-task-record-pending-action-id (record)
  (let ((message (desktop-task-record-actor-message record))
        (request-metadata (desktop-task-record-request-metadata record)))
    (or (and message
             (or (actor-message-pending-action-id message)
                 (getf (actor-message-metadata message) :pending-action-id)
                 (getf (actor-message-metadata message) :PENDING-ACTION-ID)))
        (and (listp request-metadata)
             (or (getf request-metadata :pending-action-id)
                 (getf request-metadata :PENDING-ACTION-ID))))))

(defun desktop-task-record-receiver-scope (record)
  (let ((message (desktop-task-record-actor-message record))
        (request-metadata (desktop-task-record-request-metadata record)))
    (or (and message
             (getf (actor-address-metadata (actor-message-receiver message)) :scope-id))
        (and (listp request-metadata)
             (or (getf request-metadata :receiver-scope)
                 (getf request-metadata :RECEIVER-SCOPE)
                 (getf request-metadata :scope-id)
                 (getf request-metadata :SCOPE-ID))))))

(defun editor-pending-mutation-summary (record)
  (let* ((message (desktop-task-record-actor-message record))
         (request-metadata (desktop-task-record-request-metadata record))
         (payload (desktop-task-record-payload record))
         (result (desktop-task-record-result record)))
    (list :record-id (desktop-task-record-id record)
          :request-id (desktop-task-record-request-id record)
          :actor-message-id (and message
                                 (actor-message-id message))
          :pending-action-id (desktop-task-record-pending-action-id record)
          :session-id (desktop-task-record-session-id record)
          :approval-id (desktop-task-record-approval-id record)
          :sender (and message
                       (actor-address-summary (actor-message-sender message)))
          :reply-to (and message
                         (actor-address-summary (actor-message-reply-to message)))
          :originator (and message
                           (actor-address-summary (actor-message-originator message)))
          :receiver (and message
                         (actor-address-summary (actor-message-receiver message)))
          :actor-slice (or (and message
                                (actor-message-actor-slice message))
                           (and (listp request-metadata)
                                (or (getf request-metadata :actor-slice)
                                    (getf request-metadata :ACTOR-SLICE))))
          :scope-id (or (desktop-task-record-receiver-scope record)
                        (and (listp result)
                             (or (getf result :scope-id)
                                 (getf result :SCOPE-ID))))
          :buffer-id (or (and (listp result)
                              (or (getf result :buffer-id)
                                  (getf result :BUFFER-ID)))
                         (and (listp request-metadata)
                              (or (getf request-metadata :buffer-id)
                                  (getf request-metadata :BUFFER-ID))))
          :package-name (or (and (listp result)
                                 (or (getf result :package-name)
                                     (getf result :PACKAGE-NAME)))
                            (and (listp request-metadata)
                                 (or (getf request-metadata :package-name)
                                     (getf request-metadata :PACKAGE-NAME))))
          :text (and (listp payload)
                     (or (getf payload :text)
                         (getf payload :TEXT)))
          :status (desktop-task-record-status record)
          :governance-status (desktop-task-record-governance-status record)
          :approval-status (desktop-task-record-approval-status record)
          :created-at (desktop-task-record-created-at record)
          :approved-at (desktop-task-record-approved-at record)
          :started-at (desktop-task-record-started-at record)
          :completed-at (desktop-task-record-completed-at record)
          :summary (or (and (listp result)
                            (or (getf result :summary)
                                (getf result :SUMMARY)))
                       (and (listp (desktop-task-record-last-error record))
                            (or (getf (desktop-task-record-last-error record) :summary)
                                (getf (desktop-task-record-last-error record) :SUMMARY))))
          :actor-message (actor-message-summary message))))

(defun runtime-eval-mailbox-entry-summary (record)
  (let* ((message (desktop-task-record-actor-message record))
         (request-metadata (desktop-task-record-request-metadata record))
         (payload (desktop-task-record-payload record))
         (result (desktop-task-record-result record))
         (invocation-result (and (listp result)
                                 (getf result :invocation-result))))
    (list :record-id (desktop-task-record-id record)
          :request-id (desktop-task-record-request-id record)
          :actor-message-id (and message
                                 (actor-message-id message))
          :session-id (desktop-task-record-session-id record)
          :sender (and message
                       (actor-address-summary (actor-message-sender message)))
          :reply-to (and message
                         (actor-address-summary (actor-message-reply-to message)))
          :originator (and message
                           (actor-address-summary (actor-message-originator message)))
          :receiver (and message
                         (actor-address-summary (actor-message-receiver message)))
          :actor-slice (or (and message
                                (actor-message-actor-slice message))
                           (and (listp request-metadata)
                                (or (getf request-metadata :actor-slice)
                                    (getf request-metadata :ACTOR-SLICE))))
          :runtime-id (and (listp request-metadata)
                           (or (getf request-metadata :runtime-id)
                               (getf request-metadata :RUNTIME-ID)))
          :package-name (or (and (listp payload)
                                 (or (getf payload :package-name)
                                     (getf payload :package)
                                     (getf payload :PACKAGE-NAME)
                                     (getf payload :PACKAGE)))
                            (and (listp invocation-result)
                                 (or (getf invocation-result :package)
                                     (getf invocation-result :PACKAGE))))
          :form (and (listp payload)
                     (or (getf payload :form)
                         (getf payload :FORM)))
          :reason (and (listp payload)
                       (or (getf payload :reason)
                           (getf payload :REASON)))
          :status (desktop-task-record-status record)
          :governance-status (desktop-task-record-governance-status record)
          :approval-status (desktop-task-record-approval-status record)
          :created-at (desktop-task-record-created-at record)
          :started-at (desktop-task-record-started-at record)
          :completed-at (desktop-task-record-completed-at record)
          :summary (desktop-task-record-result-summary-text record)
          :result (and (listp invocation-result)
                       (or (getf invocation-result :result)
                           (getf invocation-result :RESULT)
                           (first (or (getf invocation-result :values)
                                      (getf invocation-result :VALUES)))))
          :values (and (listp invocation-result)
                       (or (getf invocation-result :values)
                           (getf invocation-result :VALUES)))
          :actor-message (actor-message-summary message))))

(defun runtime-eval-outbox-entry-summary (record)
  (let* ((entry (runtime-eval-mailbox-entry-summary record))
         (session-id (getf entry :session-id))
         (runtime-actor (actor-address-summary
                         (make-standard-actor-address :runtime
                                                      :scope session-id
                                                      :display-name "Runtime Actor"
                                                      :metadata (when session-id
                                                                  (list :session-id session-id
                                                                        :actor-class :capability-server
                                                                        :runtime-id "runtime-primary"))))))
    (list :session-id session-id
          :record-id (getf entry :record-id)
          :request-id (getf entry :request-id)
          :actor-message-id (getf entry :actor-message-id)
          :runtime-actor runtime-actor
          :sender runtime-actor
          :receiver (or (getf entry :reply-to)
                        (getf entry :originator)
                        (getf entry :sender))
          :reply-to (getf entry :reply-to)
          :originator (getf entry :originator)
          :actor-slice (getf entry :actor-slice)
          :runtime-id (getf entry :runtime-id)
          :package-name (getf entry :package-name)
          :form (getf entry :form)
          :reason (getf entry :reason)
          :status (getf entry :status)
          :governance-status (getf entry :governance-status)
          :approval-status (getf entry :approval-status)
          :created-at (getf entry :created-at)
          :started-at (getf entry :started-at)
          :completed-at (getf entry :completed-at)
          :summary (getf entry :summary)
          :result (getf entry :result)
          :values (getf entry :values)
          :actor-message (getf entry :actor-message))))

(defun runtime-definition-state-summary (record)
  (let* ((entry (runtime-eval-mailbox-entry-summary record))
         (package-name (getf entry :package-name))
         (form-string (getf entry :form))
         (resolved-package (and package-name
                                (ignore-errors
                                  (resolve-runtime-package-designator package-name))))
         (resolved-forms (and form-string
                              resolved-package
                              (ignore-errors
                                (parse-runtime-forms form-string
                                                     :package resolved-package))))
         (defined-name (and resolved-forms
                            (runtime-eval-defined-name resolved-forms))))
    (when defined-name
      (list :session-id (getf entry :session-id)
            :record-id (getf entry :record-id)
            :request-id (getf entry :request-id)
            :actor-message-id (getf entry :actor-message-id)
            :runtime-id (or (getf entry :runtime-id) "runtime-primary")
            :package-name package-name
            :symbol-name (symbol-name defined-name)
            :qualified-symbol-name (format nil "~A::~A"
                                           package-name
                                           (symbol-name defined-name))
            :form form-string
            :status (getf entry :status)
            :created-at (getf entry :created-at)
            :completed-at (getf entry :completed-at)
            :sender (getf entry :sender)
            :reply-to (getf entry :reply-to)
            :originator (getf entry :originator)
            :receiver (getf entry :receiver)
            :actor-message (getf entry :actor-message)))))

(defun runtime-state-summary (runtime-records)
  (let* ((sorted-records
           (sort (copy-list runtime-records)
                 #'>
                 :key (lambda (record)
                        (or (desktop-task-record-completed-at record)
                            (desktop-task-record-started-at record)
                            (desktop-task-record-created-at record)
                            0))))
         (definitions '())
         (seen (make-hash-table :test #'equal)))
    (dolist (record sorted-records)
      (let ((entry (runtime-definition-state-summary record)))
        (when entry
          (let ((key (list (getf entry :package-name)
                           (getf entry :symbol-name))))
            (unless (gethash key seen)
              (setf (gethash key seen) t)
              (push entry definitions))))))
    (list :definition-count (length definitions)
          :definitions (nreverse definitions))))

(defun actor-mailbox-direction-for-mailbox (mailbox)
  (case mailbox
    ((:context-chat-mailbox :governance-decision-outbox :runtime-outbox) :outbox)
    (otherwise :inbox)))

(defun actor-mailbox-entry-owner-address (record mailbox)
  (let ((message (desktop-task-record-actor-message record))
        (session-id (desktop-task-record-session-id record)))
    (case mailbox
      (:context-chat-mailbox
       (or (and message (actor-message-sender message))
           (make-standard-actor-address :context-chat
                                        :scope session-id
                                        :metadata (when session-id
                                                    (list :session-id session-id)))))
      (:context-chat-approval-inbox
       (make-standard-actor-address :context-chat
                                    :scope session-id
                                    :metadata (when session-id
                                                (list :session-id session-id))))
      (:governance-inbox
       (make-governance-actor-address :session-id session-id))
      (:governance-decision-outbox
       (make-governance-actor-address :session-id session-id))
      (:runtime-inbox
       (or (and message (actor-message-receiver message))
           (make-standard-actor-address :runtime
                                        :scope session-id
                                        :metadata (when session-id
                                                    (list :session-id session-id)))))
      (:runtime-outbox
       (make-standard-actor-address :runtime
                                    :scope session-id
                                    :display-name "Runtime Actor"
                                    :metadata (when session-id
                                                (list :session-id session-id
                                                      :actor-class :capability-server
                                                      :runtime-id "runtime-primary"))))
      (:editor-pending-mutation-mailbox
       (or (and message (actor-message-receiver message))
           (make-standard-actor-address :editor
                                        :scope (or (desktop-task-record-receiver-scope record)
                                                   session-id)
                                        :metadata (append (when session-id
                                                            (list :session-id session-id))
                                                          (when (desktop-task-record-receiver-scope record)
                                                            (list :scope-id
                                                                  (desktop-task-record-receiver-scope record)))))))
      (:editor-authorization-mailbox
       (or (and message (actor-message-receiver message))
           (make-standard-actor-address :editor
                                        :scope (or (desktop-task-record-receiver-scope record)
                                                   session-id)
                                        :metadata (append (when session-id
                                                            (list :session-id session-id))
                                                          (when (desktop-task-record-receiver-scope record)
                                                            (list :scope-id
                                                                  (desktop-task-record-receiver-scope record)))))))
      (otherwise
       (or (and message (actor-message-receiver message))
           (make-standard-actor-address :unknown :scope session-id))))))

(defun derive-actor-mailbox-delivery-status (record mailbox)
  (let ((status (desktop-task-record-status record))
        (approval-status (desktop-task-record-approval-status record)))
    (case mailbox
      (:context-chat-mailbox
       (cond
         ((member status '(:completed :failed :retryable-failure :canceled) :test #'eq)
          :replied)
         ((eq approval-status :awaiting-approval) :awaiting-approval)
         ((member status '(:executing :retrying) :test #'eq) :in-flight)
         (t :sent)))
      (:context-chat-approval-inbox
       (if (eq approval-status :awaiting-approval)
           :available
           :consumed))
      (:governance-inbox
       (cond
         ((eq approval-status :awaiting-approval) :queued)
         ((eq approval-status :approved) :authorized)
         ((member status '(:completed :failed :canceled :retryable-failure) :test #'eq)
          :resolved)
         (t :received)))
      (:governance-decision-outbox
       (cond
         ((member status '(:completed :failed :canceled :retryable-failure) :test #'eq)
          :applied)
         ((member status '(:executing :retrying) :test #'eq) :dequeued)
         ((eq approval-status :approved) :issued)
         (t :pending)))
      (:runtime-inbox
       (cond
         ((member status '(:completed :failed :canceled :retryable-failure) :test #'eq)
          :resolved)
         ((member status '(:executing :retrying) :test #'eq) :dequeued)
         (t :queued)))
      (:runtime-outbox
       (cond
         ((member status '(:completed :failed :canceled :retryable-failure) :test #'eq)
          :replied)
         ((member status '(:executing :retrying) :test #'eq) :in-flight)
         (t :pending)))
      (:editor-pending-mutation-mailbox
       (cond
         ((member status '(:completed :failed :retryable-failure :canceled) :test #'eq)
          :applied)
         ((member status '(:executing :retrying) :test #'eq) :dequeued)
         ((eq approval-status :approved) :authorized)
         ((eq approval-status :awaiting-approval) :awaiting-approval)
         (t :pending)))
      (:editor-authorization-mailbox
       (cond
         ((member status '(:completed :failed :retryable-failure :canceled) :test #'eq)
          :applied)
         ((member status '(:executing :retrying) :test #'eq) :dequeued)
         ((eq approval-status :approved) :authorized)
         (t :pending)))
      (otherwise
       :unknown))))

(defun actor-mailbox-entry-timestamps (record mailbox)
  (let ((created-at (desktop-task-record-created-at record))
        (approved-at (desktop-task-record-approved-at record))
        (started-at (desktop-task-record-started-at record))
        (completed-at (desktop-task-record-completed-at record)))
    (case mailbox
      (:context-chat-mailbox
       (list :sent-at created-at
             :delivered-at created-at
             :acknowledged-at approved-at
             :completed-at completed-at))
      (:context-chat-approval-inbox
       (list :sent-at created-at
             :delivered-at created-at
             :acknowledged-at approved-at
             :completed-at completed-at))
      (:governance-inbox
       (list :sent-at created-at
             :delivered-at created-at
             :acknowledged-at approved-at
             :completed-at completed-at))
      (:governance-decision-outbox
       (list :sent-at approved-at
             :delivered-at approved-at
             :dequeued-at started-at
             :completed-at completed-at))
      (:runtime-inbox
       (list :sent-at created-at
             :delivered-at created-at
             :dequeued-at started-at
             :completed-at completed-at))
      (:runtime-outbox
       (list :sent-at started-at
             :delivered-at completed-at
             :completed-at completed-at))
      (:editor-pending-mutation-mailbox
       (list :sent-at created-at
             :delivered-at created-at
             :acknowledged-at approved-at
             :dequeued-at started-at
             :completed-at completed-at))
      (:editor-authorization-mailbox
       (list :sent-at approved-at
             :delivered-at approved-at
             :dequeued-at started-at
             :completed-at completed-at))
      (otherwise
       (list :sent-at created-at
             :completed-at completed-at)))))

(defun make-actor-mailbox-entry-for-record (record mailbox summary)
  (let* ((message (desktop-task-record-actor-message record))
         (timestamps (actor-mailbox-entry-timestamps record mailbox))
         (owner (actor-mailbox-entry-owner-address record mailbox))
         (actor-message-id (and message (actor-message-id message)))
         (request-id (desktop-task-record-request-id record))
         (pending-action-id (desktop-task-record-pending-action-id record))
         (session-id (desktop-task-record-session-id record)))
    (make-actor-mailbox-entry
     :id (make-actor-mailbox-entry-id
          :mailbox mailbox
          :actor-message-id actor-message-id
          :request-id request-id
          :pending-action-id pending-action-id
          :session-id session-id)
     :owner owner
     :mailbox mailbox
     :direction (actor-mailbox-direction-for-mailbox mailbox)
     :session-id session-id
     :approval-id (desktop-task-record-approval-id record)
     :pending-action-id pending-action-id
     :actor-message-id actor-message-id
     :request-id request-id
     :target (desktop-task-record-target record)
     :operation (desktop-task-record-operation record)
     :status (desktop-task-record-status record)
     :governance-status (desktop-task-record-governance-status record)
     :approval-status (desktop-task-record-approval-status record)
     :delivery-status (derive-actor-mailbox-delivery-status record mailbox)
     :sent-at (getf timestamps :sent-at)
     :delivered-at (getf timestamps :delivered-at)
     :dequeued-at (getf timestamps :dequeued-at)
     :acknowledged-at (getf timestamps :acknowledged-at)
     :completed-at (getf timestamps :completed-at)
     :reply-to (and message (actor-message-reply-to message))
     :originator (and message (actor-message-originator message))
     :sender (and message (actor-message-sender message))
     :receiver (and message (actor-message-receiver message))
     :payload summary
     :metadata (list :mailbox mailbox))))

(defun actor-mailbox-entry-summary (entry)
  (let ((payload (actor-mailbox-entry-payload entry)))
    (append
     (if (listp payload) payload (list :payload payload))
     (list :mailbox-entry-id (actor-mailbox-entry-id entry)
           :mailbox (actor-mailbox-entry-mailbox entry)
           :direction (actor-mailbox-entry-direction entry)
           :owner (actor-address-summary (actor-mailbox-entry-owner entry))
           :delivery-status (actor-mailbox-entry-delivery-status entry)
           :metadata (copy-tree (or (actor-mailbox-entry-metadata entry) '()))
           :sent-at (actor-mailbox-entry-sent-at entry)
           :delivered-at (actor-mailbox-entry-delivered-at entry)
           :dequeued-at (actor-mailbox-entry-dequeued-at entry)
           :acknowledged-at (actor-mailbox-entry-acknowledged-at entry)
           :completed-at (actor-mailbox-entry-completed-at entry)))))

(defun actor-mailbox-status-order (mailbox)
  (append
   (case mailbox
     (:context-chat-mailbox
      '(:sent :awaiting-approval :in-flight :replied))
     (:context-chat-approval-inbox
      '(:available :consumed))
     (:governance-inbox
      '(:received :queued :authorized :dequeued :resolved))
     (:governance-decision-outbox
      '(:pending :issued :dequeued :applied))
     (:runtime-inbox
      '(:queued :dequeued :resolved))
     (:runtime-outbox
      '(:pending :in-flight :replied))
     (:editor-pending-mutation-mailbox
      '(:pending :awaiting-approval :authorized :dequeued :applied))
     (:editor-authorization-mailbox
      '(:pending :authorized :dequeued :applied))
     (otherwise
      '(:unknown)))
   '(:failed :quarantined :dead-lettered)))

(defun actor-mailbox-delivery-status-rank (mailbox delivery-status)
  (position delivery-status
            (actor-mailbox-status-order mailbox)
            :test #'eq))

(defun actor-mailbox-timestamp-max (left right)
  (cond
    ((and left right) (max left right))
    (left left)
    (right right)
    (t nil)))

(defun merge-actor-mailbox-entry (mailbox existing fresh)
  (if (null existing)
      fresh
      (let* ((merged (copy-actor-mailbox-entry fresh))
             (existing-status (actor-mailbox-entry-delivery-status existing))
             (fresh-status (actor-mailbox-entry-delivery-status fresh))
             (existing-rank (or (actor-mailbox-delivery-status-rank mailbox existing-status) -1))
             (fresh-rank (or (actor-mailbox-delivery-status-rank mailbox fresh-status) -1)))
        (when (> existing-rank fresh-rank)
          (setf (actor-mailbox-entry-delivery-status merged) existing-status))
        (setf (actor-mailbox-entry-sent-at merged)
              (actor-mailbox-timestamp-max (actor-mailbox-entry-sent-at existing)
                                           (actor-mailbox-entry-sent-at fresh))
              (actor-mailbox-entry-delivered-at merged)
              (actor-mailbox-timestamp-max (actor-mailbox-entry-delivered-at existing)
                                           (actor-mailbox-entry-delivered-at fresh))
              (actor-mailbox-entry-dequeued-at merged)
              (actor-mailbox-timestamp-max (actor-mailbox-entry-dequeued-at existing)
                                           (actor-mailbox-entry-dequeued-at fresh))
              (actor-mailbox-entry-acknowledged-at merged)
              (actor-mailbox-timestamp-max (actor-mailbox-entry-acknowledged-at existing)
                                           (actor-mailbox-entry-acknowledged-at fresh))
              (actor-mailbox-entry-completed-at merged)
              (actor-mailbox-timestamp-max (actor-mailbox-entry-completed-at existing)
                                           (actor-mailbox-entry-completed-at fresh)))
        (unless (actor-mailbox-entry-owner merged)
          (setf (actor-mailbox-entry-owner merged)
                (actor-mailbox-entry-owner existing)))
        (unless (actor-mailbox-entry-reply-to merged)
          (setf (actor-mailbox-entry-reply-to merged)
                (actor-mailbox-entry-reply-to existing)))
        (unless (actor-mailbox-entry-originator merged)
          (setf (actor-mailbox-entry-originator merged)
                (actor-mailbox-entry-originator existing)))
        (unless (actor-mailbox-entry-sender merged)
          (setf (actor-mailbox-entry-sender merged)
                (actor-mailbox-entry-sender existing)))
        (unless (actor-mailbox-entry-receiver merged)
          (setf (actor-mailbox-entry-receiver merged)
                (actor-mailbox-entry-receiver existing)))
        (setf (actor-mailbox-entry-metadata merged)
              (append (copy-tree (or (actor-mailbox-entry-metadata existing) '()))
                      (copy-tree (or (actor-mailbox-entry-metadata fresh) '()))))
        merged)))

(defun actor-mailbox-entry-order-key (entry)
  (or (actor-mailbox-entry-completed-at entry)
      (actor-mailbox-entry-acknowledged-at entry)
      (actor-mailbox-entry-dequeued-at entry)
      (actor-mailbox-entry-delivered-at entry)
      (actor-mailbox-entry-sent-at entry)
      0))

(defun merge-actor-mailbox-entries (mailbox existing fresh)
  (let ((existing-index (make-hash-table :test #'equal))
        (retained '()))
    (dolist (entry existing)
      (setf (gethash (actor-mailbox-entry-id entry) existing-index) entry))
    (dolist (entry fresh)
      (let* ((entry-id (actor-mailbox-entry-id entry))
             (prior (gethash entry-id existing-index)))
        (push (merge-actor-mailbox-entry mailbox prior entry) retained)
        (remhash entry-id existing-index)))
    (maphash (lambda (_id entry)
               (declare (ignore _id))
               (push entry retained))
             existing-index)
    (sort retained #'> :key #'actor-mailbox-entry-order-key)))

(defun actor-mailbox-entries (session mailbox)
  (copy-list (or (getf (ensure-session-actor-mailboxes session) mailbox) '())))

(defun find-actor-mailbox-entry (session mailbox &key mailbox-entry-id session-id approval-id
                                                 pending-action-id actor-message-id)
  (find-if (lambda (entry)
             (and (or (null mailbox-entry-id)
                      (string= mailbox-entry-id
                               (actor-mailbox-entry-id entry)))
                  (or (null session-id)
                      (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                        (and entry-session-id
                             (string= session-id entry-session-id))))
                  (or (null approval-id)
                      (let ((entry-approval-id (actor-mailbox-entry-approval-id entry)))
                        (and entry-approval-id
                             (string= approval-id entry-approval-id))))
                  (or (null pending-action-id)
                      (let ((entry-pending-action-id
                              (actor-mailbox-entry-pending-action-id entry)))
                        (and entry-pending-action-id
                             (string= pending-action-id entry-pending-action-id))))
                  (or (null actor-message-id)
                      (let ((entry-actor-message-id
                              (actor-mailbox-entry-actor-message-id entry)))
                        (and entry-actor-message-id
                             (string= actor-message-id entry-actor-message-id))))))
           (actor-mailbox-entries session mailbox)))

(defun persist-session-actor-mailboxes (session)
  (ensure-environment-actor-registry-for-session session)
  (when (fboundp 'refresh-bound-environment-agent-state)
    (refresh-bound-environment-agent-state session))
  (when (fboundp 'mark-provider-request-snapshot-dirty)
    (mark-provider-request-snapshot-dirty session :reason :actor-mailboxes :family :actor))
  (when (fboundp 'schedule-provider-request-snapshot-refresh)
    (schedule-provider-request-snapshot-refresh session :domains '(:agent :conversation)))
  (agent-session-actor-mailboxes session))

(defun note-actor-mailbox-transition (session mailbox entry reason)
  (when (fboundp 'append-session-event)
    (append-session-event
     session
     :actor-mailbox-transition
     (list :mailbox mailbox
           :mailbox-entry-id (actor-mailbox-entry-id entry)
           :delivery-status (actor-mailbox-entry-delivery-status entry)
           :session-id (actor-mailbox-entry-session-id entry)
           :approval-id (actor-mailbox-entry-approval-id entry)
           :pending-action-id (actor-mailbox-entry-pending-action-id entry)
           :actor-message-id (actor-mailbox-entry-actor-message-id entry)
           :reason reason)
     :family :actor
     :entity-id (actor-mailbox-entry-id entry)
     :metadata (list :mailbox mailbox :reason reason))))

(defun actor-mailbox-entry-actor-definition (session entry)
  (find-actor-definition-for-address session
                                     (or (actor-mailbox-entry-owner entry)
                                         (actor-mailbox-entry-receiver entry)
                                         (actor-mailbox-entry-sender entry))))

(defun actor-supervision-incident-p (incident)
  (eq :actor-supervision
      (getf (incident-metadata incident) :source)))

(defun actor-supervision-incident-summary (incident)
  (append
   (incident-record-summary incident)
   (let ((metadata (incident-metadata incident)))
     (list :incident-id (incident-id incident)
           :actor-id (getf metadata :actor-id)
           :actor-role (getf metadata :actor-role)
           :parent-actor-id (getf metadata :parent-actor-id)
           :open-p (eq (incident-status incident) :open)
           :mailbox (getf metadata :mailbox)
           :mailbox-entry-id (getf metadata :mailbox-entry-id)
           :delivery-status (getf metadata :delivery-status)
           :supervision-policy (getf metadata :supervision-policy)
           :execution-policy (getf metadata :execution-policy)
           :session-id (getf metadata :session-id)
           :approval-id (getf metadata :approval-id)
           :pending-action-id (getf metadata :pending-action-id)
           :actor-message-id (getf metadata :actor-message-id)
           :request-id (getf metadata :request-id)
           :supervision-action (getf metadata :supervision-action)))))

(defun record-actor-supervision-incident (session mailbox entry
                                          &key summary condition-string
                                            (supervision-action :escalate-to-parent))
  (let* ((definition (actor-mailbox-entry-actor-definition session entry))
         (policy (and definition
                      (actor-definition-supervision-policy definition)))
         (execution-policy (and definition
                                (actor-definition-execution-policy definition)))
         (actor-id (and definition
                        (actor-definition-id definition)))
         (actor-role (and definition
                          (actor-definition-role definition)))
         (parent-actor-id (and definition
                               (actor-definition-parent-actor-id definition)))
         (title (format nil "Actor mailbox failure: ~A"
                        (or actor-id
                            (actor-mailbox-entry-id entry))))
         (resolved-summary
           (or summary
               (format nil "Actor ~A mailbox entry ~A failed in ~A."
                       (or actor-id actor-role :unknown)
                       (actor-mailbox-entry-id entry)
                       mailbox))))
    (create-incident
     session
     :actor-supervision
     title
     resolved-summary
     :condition condition-string
     :metadata
     (list :source :actor-supervision
           :actor-id actor-id
           :actor-role actor-role
           :parent-actor-id parent-actor-id
           :mailbox mailbox
           :mailbox-entry-id (actor-mailbox-entry-id entry)
           :delivery-status (actor-mailbox-entry-delivery-status entry)
           :supervision-policy (actor-supervision-policy-summary policy)
           :execution-policy (actor-execution-policy-summary execution-policy)
           :session-id (actor-mailbox-entry-session-id entry)
           :approval-id (actor-mailbox-entry-approval-id entry)
           :pending-action-id (actor-mailbox-entry-pending-action-id entry)
           :actor-message-id (actor-mailbox-entry-actor-message-id entry)
           :request-id (actor-mailbox-entry-request-id entry)
           :supervision-action supervision-action))))

(defun update-session-actor-mailbox-entry (session mailbox matcher updater &key reason (error-p t))
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (entries (copy-list (or (getf mailboxes mailbox) '())))
         (updated-entry nil)
         (updated-entries
           (mapcar (lambda (entry)
                     (if (and (null updated-entry)
                              (funcall matcher entry))
                         (let ((next-entry (funcall updater (copy-actor-mailbox-entry entry))))
                           (setf updated-entry next-entry)
                           next-entry)
                         entry))
                   entries)))
    (unless updated-entry
      (when error-p
        (error "Unknown mailbox entry in ~A." mailbox))
      (return-from update-session-actor-mailbox-entry nil))
    (setf (getf mailboxes mailbox) updated-entries
          (agent-session-actor-mailboxes session) mailboxes)
    (persist-session-actor-mailboxes session)
    (note-actor-mailbox-transition session mailbox updated-entry reason)
    updated-entry))

(defun append-session-actor-mailbox-entry (session mailbox entry &key reason)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (entries (copy-list (or (getf mailboxes mailbox) '()))))
    (push entry entries)
    (setf (getf mailboxes mailbox)
          (sort entries #'> :key #'actor-mailbox-entry-order-key)
          (agent-session-actor-mailboxes session) mailboxes)
    (persist-session-actor-mailboxes session)
    (note-actor-mailbox-transition session mailbox entry reason)
    entry))

(defun query-desktop-task-supervision-incidents-service (session
                                                         &key actor-id parent-actor-id mailbox
                                                           mailbox-entry-id session-id latest-only-p)
  (let* ((incidents
           (remove-if-not
            (lambda (incident)
              (and (actor-supervision-incident-p incident)
                   (let ((metadata (incident-metadata incident)))
                     (and (or (null actor-id)
                              (string= (or (getf metadata :actor-id) "")
                                       actor-id))
                          (or (null parent-actor-id)
                              (string= (or (getf metadata :parent-actor-id) "")
                                       parent-actor-id))
                          (or (null mailbox)
                              (eq (getf metadata :mailbox) mailbox))
                          (or (null mailbox-entry-id)
                              (string= (or (getf metadata :mailbox-entry-id) "")
                                       mailbox-entry-id))
                          (or (null session-id)
                              (string= (or (getf metadata :session-id) "")
                                       session-id))))))
            (copy-list (agent-session-incidents session))))
         (ordered
           (sort incidents #'> :key #'incident-created-at))
         (selected
           (if latest-only-p
               (if ordered (list (first ordered)) '())
               ordered)))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :supervision-incidents-latest :supervision-incidents)
     (list :incident-count (length selected)
           :incidents (mapcar #'actor-supervision-incident-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-supervision-incidents-latest-v1
                                                      :desktop-task-supervision-incidents-v1)
                                      :session session))))

(defun command-desktop-task-fail-mailbox-entry-service (session mailbox mailbox-entry-id
                                                        &key session-id approval-id pending-action-id
                                                          actor-message-id summary condition-string
                                                          (supervision-action :escalate-to-parent))
  (let* ((entry
           (update-session-actor-mailbox-entry
            session
            mailbox
            (lambda (current-entry)
              (and (or (null mailbox-entry-id)
                       (string= mailbox-entry-id
                                (actor-mailbox-entry-id current-entry)))
                   (or (null session-id)
                       (let ((entry-session-id (actor-mailbox-entry-session-id current-entry)))
                         (and entry-session-id
                              (string= session-id entry-session-id))))
                   (or (null approval-id)
                       (let ((entry-approval-id (actor-mailbox-entry-approval-id current-entry)))
                         (and entry-approval-id
                              (string= approval-id entry-approval-id))))
                   (or (null pending-action-id)
                       (let ((entry-pending-action-id
                               (actor-mailbox-entry-pending-action-id current-entry)))
                         (and entry-pending-action-id
                              (string= pending-action-id entry-pending-action-id))))
                   (or (null actor-message-id)
                       (let ((entry-actor-message-id
                               (actor-mailbox-entry-actor-message-id current-entry)))
                         (and entry-actor-message-id
                              (string= actor-message-id entry-actor-message-id))))))
            (lambda (current-entry)
              (setf (actor-mailbox-entry-delivery-status current-entry) :failed
                    (actor-mailbox-entry-completed-at current-entry)
                    (or (actor-mailbox-entry-completed-at current-entry)
                        (get-universal-time))
                    (actor-mailbox-entry-metadata current-entry)
                    (append (list :failure-summary summary
                                  :failure-condition condition-string
                                  :supervision-action supervision-action)
                            (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
              current-entry)
            :reason :actor-mailbox-failed))
         (incident
           (record-actor-supervision-incident session
                                              mailbox
                                              entry
                                              :summary summary
                                              :condition-string condition-string
                                              :supervision-action supervision-action)))
    (make-service-command-response
     :desktop-task
     :fail-mailbox-entry
     (list :mailbox mailbox
           :mailbox-entry (actor-mailbox-entry-summary entry)
           :incident (actor-supervision-incident-summary incident))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :desktop-task-fail-mailbox-entry-v1
                                      :session session))))

(defun apply-supervision-action-to-mailbox-entry (session mailbox mailbox-entry-id action note)
  (ecase action
    (:dead-letter
     (update-session-actor-mailbox-entry
      session
      mailbox
      (lambda (current-entry)
        (string= mailbox-entry-id
                 (actor-mailbox-entry-id current-entry)))
      (lambda (current-entry)
        (setf (actor-mailbox-entry-delivery-status current-entry) :dead-lettered
              (actor-mailbox-entry-completed-at current-entry)
              (or (actor-mailbox-entry-completed-at current-entry)
                  (get-universal-time))
              (actor-mailbox-entry-metadata current-entry)
              (append (list :supervision-resolution-action action
                            :supervision-resolution-note note)
                      (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
        current-entry)
      :reason :actor-supervision-dead-letter))
    (:quarantine
     (update-session-actor-mailbox-entry
      session
      mailbox
      (lambda (current-entry)
        (string= mailbox-entry-id
                 (actor-mailbox-entry-id current-entry)))
      (lambda (current-entry)
        (setf (actor-mailbox-entry-delivery-status current-entry) :quarantined
              (actor-mailbox-entry-completed-at current-entry)
              (or (actor-mailbox-entry-completed-at current-entry)
                  (get-universal-time))
              (actor-mailbox-entry-metadata current-entry)
              (append (list :supervision-resolution-action action
                            :supervision-resolution-note note)
                      (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
        current-entry)
      :reason :actor-supervision-quarantine))
    (:restart-child
     (let* ((failed-entry
              (find-actor-mailbox-entry session
                                        mailbox
                                        :mailbox-entry-id mailbox-entry-id))
            (restart-count
              (1+ (or (getf (actor-mailbox-entry-metadata failed-entry)
                            :supervision-restart-count)
                      0)))
            (restarted-entry
              (make-actor-mailbox-entry
               :id (format nil "~A/restart-~D-~D"
                           mailbox-entry-id
                           (get-universal-time)
                           (random 1000000))
               :owner (actor-mailbox-entry-owner failed-entry)
               :mailbox mailbox
               :direction (actor-mailbox-entry-direction failed-entry)
               :session-id (actor-mailbox-entry-session-id failed-entry)
               :approval-id (actor-mailbox-entry-approval-id failed-entry)
               :pending-action-id (actor-mailbox-entry-pending-action-id failed-entry)
               :actor-message-id (actor-mailbox-entry-actor-message-id failed-entry)
               :request-id (actor-mailbox-entry-request-id failed-entry)
               :target (actor-mailbox-entry-target failed-entry)
               :operation (actor-mailbox-entry-operation failed-entry)
               :status :queued
               :governance-status (actor-mailbox-entry-governance-status failed-entry)
               :approval-status (actor-mailbox-entry-approval-status failed-entry)
               :delivery-status :queued
               :sent-at (get-universal-time)
               :delivered-at (get-universal-time)
               :reply-to (actor-mailbox-entry-reply-to failed-entry)
               :originator (actor-mailbox-entry-originator failed-entry)
               :sender (actor-mailbox-entry-sender failed-entry)
               :receiver (actor-mailbox-entry-receiver failed-entry)
               :payload (copy-tree (actor-mailbox-entry-payload failed-entry))
               :metadata (append (list :restarted-from-mailbox-entry-id mailbox-entry-id
                                       :supervision-resolution-action action
                                       :supervision-resolution-note note
                                       :supervision-restart-count restart-count)
                                 (copy-tree (or (actor-mailbox-entry-metadata failed-entry) '()))))))
       (append-session-actor-mailbox-entry session
                                           mailbox
                                           restarted-entry
                                           :reason :actor-supervision-restart-child)))
    (:replace-child
     (let* ((failed-entry
              (find-actor-mailbox-entry session
                                        mailbox
                                        :mailbox-entry-id mailbox-entry-id))
            (owner (actor-mailbox-entry-owner failed-entry))
            (replacement-owner
              (and owner
                   (make-standard-actor-address
                    (actor-address-role owner)
                    :kind (actor-address-kind owner)
                    :display-name (actor-address-display-name owner)
                    :scope (or (getf (actor-address-metadata owner) :scope-id)
                               (getf (actor-address-metadata owner) :session-id)
                               (actor-mailbox-entry-session-id failed-entry))
                    :metadata (append (copy-tree (or (actor-address-metadata owner) '()))
                                      (list :replacement-issued-at (get-universal-time))))))
            (replacement-entry
              (make-actor-mailbox-entry
               :id (format nil "~A/replacement-~D-~D"
                           mailbox-entry-id
                           (get-universal-time)
                           (random 1000000))
               :owner replacement-owner
               :mailbox mailbox
               :direction (actor-mailbox-entry-direction failed-entry)
               :session-id (actor-mailbox-entry-session-id failed-entry)
               :approval-id (actor-mailbox-entry-approval-id failed-entry)
               :pending-action-id (actor-mailbox-entry-pending-action-id failed-entry)
               :actor-message-id (actor-mailbox-entry-actor-message-id failed-entry)
               :request-id (actor-mailbox-entry-request-id failed-entry)
               :target (actor-mailbox-entry-target failed-entry)
               :operation (actor-mailbox-entry-operation failed-entry)
               :status :queued
               :governance-status (actor-mailbox-entry-governance-status failed-entry)
               :approval-status (actor-mailbox-entry-approval-status failed-entry)
               :delivery-status :queued
               :sent-at (get-universal-time)
               :delivered-at (get-universal-time)
               :reply-to (actor-mailbox-entry-reply-to failed-entry)
               :originator (actor-mailbox-entry-originator failed-entry)
               :sender (actor-mailbox-entry-sender failed-entry)
               :receiver (actor-mailbox-entry-receiver failed-entry)
               :payload (copy-tree (actor-mailbox-entry-payload failed-entry))
               :metadata (append (list :replaced-from-mailbox-entry-id mailbox-entry-id
                                       :supervision-resolution-action action
                                       :supervision-resolution-note note)
                                 (copy-tree (or (actor-mailbox-entry-metadata failed-entry) '()))))))
       (append-session-actor-mailbox-entry session
                                           mailbox
                                           replacement-entry
                                           :reason :actor-supervision-replace-child)))))

(defun command-desktop-task-apply-supervision-action-service (session incident-id
                                                              &key (action :dead-letter)
                                                                note)
  (let* ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown supervision incident ~A" incident-id))
    (unless (actor-supervision-incident-p incident)
      (error "Incident ~A is not an actor supervision incident" incident-id))
    (let* ((metadata (incident-metadata incident))
           (mailbox (or (getf metadata :mailbox)
                        (error "Supervision incident ~A does not identify a mailbox" incident-id)))
           (mailbox-entry-id (or (getf metadata :mailbox-entry-id)
                                 (error "Supervision incident ~A does not identify a mailbox entry" incident-id)))
           (entry (apply-supervision-action-to-mailbox-entry session
                                                             mailbox
                                                             mailbox-entry-id
                                                             action
                                                             note)))
      (unless entry
        (error "Unknown mailbox entry ~A in ~A" mailbox-entry-id mailbox))
      (setf (incident-status incident)
            (case action
              (:quarantine :quarantined)
              (otherwise :resolved))
            (incident-metadata incident)
            (append (list :resolution-action action
                          :resolution-note note
                          :resolved-at (get-universal-time))
                    (copy-tree metadata)))
      (when (fboundp 'append-session-event)
        (append-session-event session
                              :actor-supervision-action-applied
                              (list :incident-id incident-id
                                    :action action
                                    :mailbox mailbox
                                    :mailbox-entry-id mailbox-entry-id)
                              :family :actor
                              :entity-id incident-id
                              :metadata (list :mailbox mailbox
                                              :mailbox-entry-id mailbox-entry-id
                                              :action action)))
      (make-service-command-response
       :desktop-task
       :apply-supervision-action
       (list :incident (actor-supervision-incident-summary incident)
             :mailbox mailbox
             :mailbox-entry (actor-mailbox-entry-summary entry)
             :action action)
       :metadata (make-service-metadata :authority :environment
                                        :command-model :desktop-task-apply-supervision-action-v1
                                        :session session)))))

(defun desktop-task-actor-role-for-record (record &key (direction :receiver))
  (let ((message (desktop-task-actor-message-for-record record)))
    (when message
      (case direction
        (:sender (and (actor-message-sender message)
                      (actor-address-role (actor-message-sender message))))
        (otherwise (and (actor-message-receiver message)
                        (actor-address-role (actor-message-receiver message))))))))

(defun desktop-task-actor-address-for-record (record &key (direction :receiver))
  (let ((message (desktop-task-actor-message-for-record record)))
    (when message
      (case direction
        (:sender (actor-message-sender message))
        (otherwise (actor-message-receiver message))))))

(defun actor-address-equal-p (left right)
  (and left
       right
       (string= (actor-address-id left)
                (actor-address-id right))))

(defun actor-allocation-strategy-summary (strategy)
  (when strategy
    (list :type (actor-allocation-strategy-type strategy)
          :shared-inbox-id (actor-allocation-strategy-shared-inbox-id strategy)
          :pool-size (actor-allocation-strategy-pool-size strategy)
          :consumption-policy (actor-allocation-strategy-consumption-policy strategy)
          :metadata (copy-tree (or (actor-allocation-strategy-metadata strategy) '())))))

(defun actor-supervision-policy-summary (policy)
  (when policy
    (list :strategy (actor-supervision-policy-strategy policy)
          :max-restarts (actor-supervision-policy-max-restarts policy)
          :restart-window-seconds (actor-supervision-policy-restart-window-seconds policy)
          :on-failure (actor-supervision-policy-on-failure policy)
          :escalation-target (actor-supervision-policy-escalation-target policy)
          :metadata (copy-tree (or (actor-supervision-policy-metadata policy) '())))))

(defun actor-execution-policy-summary (policy)
  (when policy
    (list :model (actor-execution-policy-model policy)
          :thread-name (actor-execution-policy-thread-name policy)
          :mailbox-mode (actor-execution-policy-mailbox-mode policy)
          :max-concurrency (actor-execution-policy-max-concurrency policy)
          :metadata (copy-tree (or (actor-execution-policy-metadata policy) '())))))

(defun actor-definition-summary (definition)
  (when definition
    (list :id (actor-definition-id definition)
          :role (actor-definition-role definition)
          :display-name (actor-definition-display-name definition)
          :parent-actor-id (actor-definition-parent-actor-id definition)
          :inbox-id (actor-definition-inbox-id definition)
          :outbox-id (actor-definition-outbox-id definition)
          :handler-mode (actor-definition-handler-mode definition)
          :llm-profile (actor-definition-llm-profile definition)
          :capabilities (copy-list (or (actor-definition-capabilities definition) '()))
          :allocation-strategy
          (actor-allocation-strategy-summary
           (actor-definition-allocation-strategy definition))
          :supervision-policy
          (actor-supervision-policy-summary
           (actor-definition-supervision-policy definition))
          :execution-policy
          (actor-execution-policy-summary
           (actor-definition-execution-policy definition))
          :metadata (copy-tree (or (actor-definition-metadata definition) '())))))

(defun make-default-actor-definition (role &key scope display-name parent-actor-id
                                             capabilities llm-profile
                                             (allocation-type :singleton)
                                             shared-inbox-id
                                             pool-size
                                             consumption-policy
                                             (handler-mode :serial)
                                             (supervision-strategy :one-for-one)
                                             (max-restarts 3)
                                             (restart-window-seconds 60)
                                             (on-failure :escalate)
                                             escalation-target
                                             (execution-model :thread-pool-worker)
                                             thread-name
                                             (mailbox-mode :serial-per-actor)
                                             (max-concurrency 1)
                                             metadata)
  (let* ((address (make-standard-actor-address role
                                               :scope scope
                                               :display-name display-name))
         (actor-id (actor-address-id address)))
    (make-actor-definition
     :id actor-id
     :role (actor-address-role address)
     :display-name (actor-address-display-name address)
     :parent-actor-id parent-actor-id
     :inbox-id (or shared-inbox-id
                   (format nil "~A/inbox" actor-id))
     :outbox-id (format nil "~A/outbox" actor-id)
     :handler-mode handler-mode
     :llm-profile llm-profile
     :capabilities capabilities
     :allocation-strategy
     (make-actor-allocation-strategy
      :type allocation-type
      :shared-inbox-id shared-inbox-id
      :pool-size pool-size
      :consumption-policy consumption-policy
      :metadata (copy-tree (or metadata '())))
     :supervision-policy
     (make-actor-supervision-policy
      :strategy supervision-strategy
      :max-restarts max-restarts
      :restart-window-seconds restart-window-seconds
      :on-failure on-failure
      :escalation-target escalation-target
      :metadata (copy-tree (or metadata '())))
     :execution-policy
     (make-actor-execution-policy
      :model execution-model
      :thread-name thread-name
      :mailbox-mode mailbox-mode
      :max-concurrency max-concurrency
      :metadata (copy-tree (or metadata '())))
     :metadata (append (copy-list (actor-address-metadata address))
                       (copy-tree (or metadata '()))))))

(defun actor-system-registry-definitions (session)
  (let* ((session-id (agent-session-id session))
         (system-id (make-actor-address-id :actor-system))
         (definitions
           (list
            (make-actor-definition
             :id system-id
             :role :actor-system
             :display-name "Actor System"
             :parent-actor-id nil
             :inbox-id (format nil "~A/inbox" system-id)
             :outbox-id (format nil "~A/outbox" system-id)
             :handler-mode :serial
             :llm-profile nil
             :capabilities '(:registry :routing :supervision)
             :allocation-strategy
             (make-actor-allocation-strategy
              :type :singleton
              :shared-inbox-id (format nil "~A/inbox" system-id)
              :pool-size 1
              :consumption-policy :sequential)
             :supervision-policy
             (make-actor-supervision-policy
              :strategy :root
              :max-restarts 0
              :restart-window-seconds 0
              :on-failure :quarantine
              :escalation-target nil)
             :execution-policy
             (make-actor-execution-policy
              :model :coordinator-thread
              :thread-name "actor-system-root"
              :mailbox-mode :serial-per-actor
              :max-concurrency 1)
             :metadata '(:actor-class :system-supervisor))
            (make-default-actor-definition :context-chat
                                           :scope session-id
                                           :display-name "Context Chat"
                                           :parent-actor-id system-id
                                           :capabilities '(:conversation :projection)
                                           :llm-profile :default
                                           :supervision-strategy :one-for-one
                                           :on-failure :restart
                                           :escalation-target system-id
                                           :execution-model :thread-pool-worker
                                           :thread-name "actor-pool/context-chat"
                                           :metadata '(:actor-class :conversation-client))
            (make-default-actor-definition :governance
                                           :scope session-id
                                           :display-name "Governance Actor"
                                           :parent-actor-id system-id
                                           :capabilities '(:approval :authorization :policy)
                                           :llm-profile :default
                                           :supervision-strategy :one-for-one
                                           :on-failure :escalate
                                           :escalation-target system-id
                                           :execution-model :thread-pool-worker
                                           :thread-name "actor-pool/governance"
                                           :metadata '(:actor-class :policy-gateway))
            (make-default-actor-definition :runtime
                                           :scope session-id
                                           :display-name "Runtime Actor"
                                           :parent-actor-id system-id
                                           :capabilities '(:runtime-eval :runtime-state)
                                           :llm-profile :default
                                           :supervision-strategy :one-for-one
                                           :on-failure :restart
                                           :escalation-target system-id
                                           :execution-model :thread-pool-worker
                                           :thread-name "actor-pool/runtime"
                                           :metadata '(:actor-class :capability-server
                                                       :runtime-id "runtime-primary"))
            (make-default-actor-definition :editor
                                           :scope session-id
                                           :display-name "Editor Actor"
                                           :parent-actor-id system-id
                                           :capabilities '(:workspace-write :buffer-mutation)
                                           :supervision-strategy :one-for-one
                                           :on-failure :restart
                                           :escalation-target system-id
                                           :execution-model :thread-pool-worker
                                           :thread-name "actor-pool/editor"
                                           :metadata '(:actor-class :capability-server))
            (make-default-actor-definition :calculator
                                           :scope session-id
                                           :display-name "Calculator Actor"
                                           :parent-actor-id system-id
                                           :capabilities '(:calculator-control)
                                           :supervision-strategy :one-for-one
                                           :on-failure :restart
                                           :escalation-target system-id
                                           :execution-model :thread-pool-worker
                                           :thread-name "actor-pool/calculator"
                                           :metadata '(:actor-class :capability-server))
            (make-default-actor-definition :environment
                                           :scope (or (and (session-bound-environment session)
                                                           (environment-id
                                                            (session-bound-environment session)))
                                                      session-id)
                                           :display-name "Environment Actor"
                                           :parent-actor-id system-id
                                           :capabilities '(:environment-state :persistence)
                                           :supervision-strategy :one-for-one
                                           :on-failure :escalate
                                           :escalation-target system-id
                                           :execution-model :thread-pool-worker
                                           :thread-name "actor-pool/environment"
                                           :metadata '(:actor-class :environment-gateway)))))
    (dolist (manifest (list-registered-desktop-task-manifests :discoverable-only-p nil))
      (let* ((target (desktop-task-manifest-target manifest))
             (backend-ref (desktop-task-manifest-backend-ref manifest))
             (backend-kind (desktop-task-manifest-backend-kind manifest))
             (core-singleton-target-p
               (and (eq backend-kind :internal)
                    (member target '(:context-chat :governance :runtime :editor :calculator :environment)
                            :test #'eq)))
             (pooled-p (eq backend-kind :mcp))
             (shared-inbox-id
               (and pooled-p
                    (format nil "actor/~(~A~)/pool/~A/inbox"
                            target
                            (or backend-ref "default"))))
             (definition
               (make-default-actor-definition
                target
                :scope (and backend-ref (princ-to-string backend-ref))
                :display-name (or (desktop-task-manifest-description manifest)
                                  (format nil "~A Actor" target))
                :parent-actor-id system-id
                :capabilities (list (desktop-task-manifest-capability manifest))
                :allocation-type (if pooled-p :pool :singleton)
                :shared-inbox-id shared-inbox-id
                :pool-size (and pooled-p 4)
                :consumption-policy (and pooled-p :competing-consumers)
                :supervision-strategy (if pooled-p :one-for-all :one-for-one)
                :on-failure (if pooled-p :replace-member :restart)
                :escalation-target system-id
                :execution-model :thread-pool-worker
                :thread-name (format nil "actor-pool/~(~A~)" target)
                :mailbox-mode :serial-per-actor
                :max-concurrency 1
                :metadata (list :actor-class :capability-server
                                :manifest-id (desktop-task-manifest-id manifest)
                                :backend-kind backend-kind
                                :backend-ref backend-ref))))
        (unless core-singleton-target-p
          (push definition definitions))))
    (nreverse
     (delete-duplicates definitions
                        :test (lambda (left right)
                                (string= (actor-definition-id left)
                                         (actor-definition-id right)))))))

(defun ensure-environment-actor-registry-for-session (session)
  (let ((environment (session-bound-environment session)))
    (when environment
      (setf (environment-agent-registry environment)
            (actor-system-registry-definitions session))))
  session)

(defun find-actor-definition-for-address (session actor-address)
  (let* ((environment (session-bound-environment session))
         (definitions (or (and environment
                               (environment-agent-registry environment))
                          (actor-system-registry-definitions session))))
    (or (find (actor-address-id actor-address)
              definitions
              :key #'actor-definition-id
              :test #'string=)
        (find (actor-address-role actor-address)
              definitions
              :key #'actor-definition-role
              :test #'eq))))

(defun canonical-actor-address-for-session (session actor-address)
  (let ((definition (find-actor-definition-for-address session actor-address)))
    (if definition
        (actor-definition-address definition)
        actor-address)))

(defun desktop-task-capability-actor-addresses (session)
  (ensure-environment-actor-registry-for-session session)
  (let ((addresses
          (list (make-standard-actor-address :actor-system
                                             :kind :internal
                                             :display-name "Actor System"
                                             :metadata '(:actor-class :system-supervisor))
                (make-standard-actor-address :context-chat
                                             :kind :internal
                                             :display-name "Context Chat"
                                             :scope (agent-session-id session)
                                             :metadata '(:actor-class :conversation-client))
                (make-governance-actor-address :session-id (agent-session-id session))
                (make-standard-actor-address :runtime
                                             :kind :internal
                                             :display-name "Runtime Actor"
                                             :scope (agent-session-id session)
                                             :metadata '(:actor-class :capability-server
                                                         :runtime-id "runtime-primary")))))
    (dolist (manifest (list-registered-desktop-task-manifests :discoverable-only-p nil))
      (push (desktop-task-receiver-actor-address
             (desktop-task-manifest-target manifest)
             :capability (desktop-task-manifest-capability manifest)
             :backend-kind (desktop-task-manifest-backend-kind manifest)
             :backend-ref (desktop-task-manifest-backend-ref manifest))
            addresses))
    (dolist (record (list-desktop-task-records session))
      (let ((message (desktop-task-actor-message-for-record record)))
        (when (and message (actor-message-sender message))
          (push (actor-message-sender message) addresses))
        (when (and message (actor-message-receiver message))
          (push (actor-message-receiver message) addresses))))
    (nreverse
     (delete-duplicates addresses
                        :test #'actor-address-equal-p))))

(defun desktop-task-actor-records (session actor-role &key (direction :receiver))
  (remove-if-not
   (lambda (record)
     (eq actor-role
         (desktop-task-actor-role-for-record record :direction direction)))
   (list-desktop-task-records session)))

(defun desktop-task-actor-summary (session actor-address)
  (ensure-environment-actor-registry-for-session session)
  (let* ((role (actor-address-role actor-address))
         (definition (find-actor-definition-for-address session actor-address))
         (received-records (desktop-task-actor-records session role :direction :receiver))
         (sent-records (desktop-task-actor-records session role :direction :sender))
         (relevant-records (if (eq role :context-chat) sent-records received-records))
         (runtime-execution-summary
           (when (eq role :runtime)
             (and (fboundp 'actor-runtime-state-summary)
                  (actor-runtime-state-summary session))))
         (recent-records (last relevant-records (min 8 (length relevant-records)))))
    (append
     (actor-address-summary actor-address)
     (when definition
       (list :actor-definition (actor-definition-summary definition)
             :allocation-strategy
             (actor-allocation-strategy-summary
              (actor-definition-allocation-strategy definition))
             :supervision-policy
             (actor-supervision-policy-summary
              (actor-definition-supervision-policy definition))
             :execution-policy
             (actor-execution-policy-summary
              (actor-definition-execution-policy definition))
             :parent-actor-id (actor-definition-parent-actor-id definition)
             :handler-mode (actor-definition-handler-mode definition)
             :llm-profile (actor-definition-llm-profile definition)
             :capabilities (copy-list (or (actor-definition-capabilities definition) '()))))
     (list :mailbox-direction (if (eq role :context-chat) :outbox :inbox)
           :received-count (length received-records)
           :sent-count (length sent-records)
           :message-count (length relevant-records)
           :awaiting-approval-count (count :awaiting-approval relevant-records
                                           :key #'desktop-task-record-status
                                           :test #'eq)
           :dead-letter-count (count-if (lambda (record)
                                          (actor-message-dead-letter-p
                                           (desktop-task-record-actor-message record)))
                                        relevant-records)
           :completed-count (count :completed relevant-records
                                   :key #'desktop-task-record-status
                                   :test #'eq)
           :failed-count (count-if (lambda (status)
                                     (member status '(:failed :retryable-failure)
                                             :test #'eq))
                                   relevant-records
                                   :key #'desktop-task-record-status)
           :runtime-execution runtime-execution-summary
           :recent-messages
           (mapcar (lambda (record)
                     (desktop-task-record-summary-with-audit session record))
                   recent-records)))))

(defun actor-definition-address (definition)
  (make-actor-address
   :id (actor-definition-id definition)
   :kind :internal
   :role (actor-definition-role definition)
   :display-name (actor-definition-display-name definition)
   :metadata (copy-tree (or (actor-definition-metadata definition) '()))))

(defun actor-summary-id (summary)
  (or (getf summary :id)
      (getf summary :actor-id)))

(defun actor-summary-role (summary)
  (or (getf summary :role)
      (getf summary :actor-role)))

(defun actor-summary-parent-id (summary)
  (or (getf summary :parent-actor-id)
      (getf (getf summary :actor-definition) :parent-actor-id)))

(defun actor-mailbox-metrics-for-actor (session actor-id &key (window-seconds 300))
  (let* ((entries
           (remove-if-not
            (lambda (entry)
              (let ((owner (actor-mailbox-entry-owner entry)))
                (and owner
                     (string= actor-id
                              (actor-address-id owner)))))
            (loop for mailbox in '(:context-chat-mailbox
                                   :context-chat-approval-inbox
                                   :governance-inbox
                                   :governance-decision-outbox
                                   :runtime-inbox
                                   :runtime-outbox
                                   :editor-pending-mutation-mailbox
                                   :editor-authorization-mailbox)
                  append (actor-mailbox-entries session mailbox))))
         (recent-threshold (- (get-universal-time) window-seconds))
         (inbox-entries
           (remove-if-not (lambda (entry)
                            (eq :inbox (actor-mailbox-entry-direction entry)))
                          entries))
         (outbox-entries
           (remove-if-not (lambda (entry)
                            (eq :outbox (actor-mailbox-entry-direction entry)))
                          entries))
         (arrival-count
           (count-if (lambda (entry)
                       (let ((timestamp (or (actor-mailbox-entry-delivered-at entry)
                                            (actor-mailbox-entry-sent-at entry)
                                            0)))
                         (>= timestamp recent-threshold)))
                     inbox-entries))
         (departure-count
           (count-if (lambda (entry)
                       (let ((timestamp (or (actor-mailbox-entry-completed-at entry)
                                            (actor-mailbox-entry-acknowledged-at entry)
                                            (actor-mailbox-entry-dequeued-at entry)
                                            0)))
                         (>= timestamp recent-threshold)))
                     outbox-entries))
         (open-supervision-incident-count
           (count-if
            (lambda (incident)
              (and (actor-supervision-incident-p incident)
                   (eq (incident-status incident) :open)
                   (string= actor-id
                            (or (getf (incident-metadata incident) :actor-id) ""))))
            (agent-session-incidents session)))
         (resolved-supervision-incident-count
           (count-if
            (lambda (incident)
              (and (actor-supervision-incident-p incident)
                   (eq (incident-status incident) :resolved)
                   (string= actor-id
                            (or (getf (incident-metadata incident) :actor-id) ""))))
            (agent-session-incidents session)))
         (quarantined-supervision-incident-count
           (count-if
            (lambda (incident)
              (and (actor-supervision-incident-p incident)
                   (eq (incident-status incident) :quarantined)
                   (string= actor-id
                            (or (getf (incident-metadata incident) :actor-id) ""))))
            (agent-session-incidents session)))
         (delivery-status-counts
           (let ((counts (make-hash-table :test #'eq)))
             (dolist (entry entries)
               (incf (gethash (actor-mailbox-entry-delivery-status entry) counts 0)))
             (loop for status being the hash-keys of counts
                     using (hash-value count)
                   collect (list :delivery-status status :count count)))))
    (list :inbox-depth (length inbox-entries)
          :outbox-depth (length outbox-entries)
          :arrival-count arrival-count
          :departure-count departure-count
          :arrival-rate (/ arrival-count (max 1 (/ window-seconds 60.0)))
          :departure-rate (/ departure-count (max 1 (/ window-seconds 60.0)))
          :failed-mailbox-count
          (count-if (lambda (entry)
                      (eq :failed
                          (actor-mailbox-entry-delivery-status entry)))
                    entries)
          :dead-lettered-mailbox-count
          (count-if (lambda (entry)
                      (eq :dead-lettered
                          (actor-mailbox-entry-delivery-status entry)))
                    entries)
          :quarantined-mailbox-count
          (count-if (lambda (entry)
                      (eq :quarantined
                          (actor-mailbox-entry-delivery-status entry)))
                    entries)
          :queued-mailbox-count
          (count-if (lambda (entry)
                      (eq :queued
                          (actor-mailbox-entry-delivery-status entry)))
                    entries)
          :open-supervision-incident-count open-supervision-incident-count
          :resolved-supervision-incident-count resolved-supervision-incident-count
          :quarantined-supervision-incident-count quarantined-supervision-incident-count
          :delivery-status-counts
          (sort delivery-status-counts #'>
                :key (lambda (entry) (or (getf entry :count) 0))))))

(defun actor-system-panel-hierarchy-edges (actors)
  (remove nil
          (mapcar (lambda (actor)
                    (let ((parent-id (actor-summary-parent-id actor))
                          (actor-id (actor-summary-id actor)))
                      (and parent-id
                           actor-id
                           (list :parent-actor-id parent-id
                                 :child-actor-id actor-id))))
                  actors)))

(defun actor-system-panel-workflow-edges (session &key session-id)
  (let ((edges (make-hash-table :test #'equal))
        (recent-threshold (- (get-universal-time) 300)))
    (dolist (record (list-desktop-task-records session))
      (when (or (null session-id)
                (let ((record-session-id (desktop-task-record-session-id record)))
                  (and record-session-id
                       (string= session-id record-session-id))))
        (let* ((message (desktop-task-record-actor-message record))
               (sender (and message (actor-message-sender message)))
               (receiver (and message (actor-message-receiver message))))
          (when (and sender receiver)
            (let* ((key (list (actor-address-id sender)
                              (actor-address-id receiver)
                              (desktop-task-record-target record)
                              (desktop-task-record-operation record)))
                   (bucket (or (gethash key edges)
                               (setf (gethash key edges)
                                     (list :from-actor-id (actor-address-id sender)
                                           :to-actor-id (actor-address-id receiver)
                                           :from-role (actor-address-role sender)
                                           :to-role (actor-address-role receiver)
                                           :target (desktop-task-record-target record)
                                           :operation (desktop-task-record-operation record)
                                           :message-count 0
                                           :recent-count 0
                                           :failed-count 0
                                           :latest-status nil
                                           :latest-created-at nil)))))
              (incf (getf bucket :message-count))
              (when (member (desktop-task-record-status record)
                            '(:failed :retryable-failure :canceled)
                            :test #'eq)
                (incf (getf bucket :failed-count)))
              (when (>= (or (desktop-task-record-created-at record) 0)
                        recent-threshold)
                (incf (getf bucket :recent-count)))
              (when (> (or (desktop-task-record-created-at record) 0)
                       (or (getf bucket :latest-created-at) 0))
                (setf (getf bucket :latest-created-at)
                      (desktop-task-record-created-at record)
                      (getf bucket :latest-status)
                      (desktop-task-record-status record))))))))
    (sort (loop for edge being the hash-values of edges collect edge)
          #'>
          :key (lambda (entry)
                 (or (getf entry :latest-created-at) 0)))))

(defun query-desktop-task-actor-system-panel-service (session &key session-id)
  (ensure-environment-actor-registry-for-session session)
  (let* ((registered-actors
           (mapcar (lambda (definition)
                     (actor-definition-address definition))
                   (actor-system-registry-definitions session)))
         (observed-actors
           (mapcar (lambda (address)
                     (canonical-actor-address-for-session session address))
                   (desktop-task-capability-actor-addresses session)))
         (addresses
           (nreverse
            (delete-duplicates (append registered-actors observed-actors)
                               :test #'actor-address-equal-p)))
         (actors
           (mapcar (lambda (address)
                     (let ((summary (desktop-task-actor-summary session address)))
                       (append summary
                               (list :metrics
                                     (actor-mailbox-metrics-for-actor
                                      session
                                      (actor-summary-id summary))))))
                   addresses))
         (hierarchy-edges (actor-system-panel-hierarchy-edges actors))
         (workflow-edges (actor-system-panel-workflow-edges session
                                                            :session-id session-id))
         (runtime-execution
           (and (fboundp 'actor-runtime-state-summary)
                (actor-runtime-state-summary session)))
         (supervision-incidents
           (service-response-data
            (query-desktop-task-supervision-incidents-service
             session
             :session-id session-id))))
    (make-service-query-response
     :desktop-task
     :actor-system-panel
     (list :root-actor-id "actor/actor-system"
           :session-id (or session-id
                           (agent-session-id session))
           :actor-count (length actors)
           :actors actors
           :hierarchy-edge-count (length hierarchy-edges)
           :hierarchy-edges hierarchy-edges
           :workflow-edge-count (length workflow-edges)
           :workflow-edges workflow-edges
           :runtime-execution runtime-execution
           :supervision-incidents supervision-incidents)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-actor-system-panel-v1
                                      :session session))))

(defun actor-message-transport-event-p (event)
  (eq (event-kind event) :actor-message-transport))

(defun actor-message-transport-event-summary (event)
  (let ((payload (event-payload event)))
    (append (if (listp payload) payload (list :payload payload))
            (list :event-id (event-id event)
                  :recorded-at (event-timestamp event)
                  :thread-id (event-thread-id event)
                  :turn-id (event-turn-id event)
                  :entity-id (event-entity-id event)
                  :family (event-family event)
                  :kind (event-kind event)))))

(defun actor-message-trace-matches-p (event actor-message-id actor-role phase dead-letters-only-p)
  (let* ((payload (event-payload event))
         (sender (let ((value (getf payload :sender)))
                   (and (listp value) value)))
         (receiver (let ((value (getf payload :receiver)))
                     (and (listp value) value)))
         (payload-role (or (getf receiver :role)
                           (getf sender :role)))
         (payload-phase (getf payload :phase))
         (payload-message-id (getf payload :actor-message-id))
         (dead-letter-p (getf payload :dead-letter-p)))
    (and (actor-message-transport-event-p event)
         (or (null actor-message-id)
             (and payload-message-id
                  (string= actor-message-id payload-message-id)))
         (or (null actor-role)
             (eq (normalize-actor-role actor-role :unknown)
                 payload-role))
         (or (null phase)
             (eq phase payload-phase))
         (or (not dead-letters-only-p)
             dead-letter-p))))

(defun query-desktop-task-actor-trace-service (session &key actor-message-id actor-role phase latest-only-p dead-letters-only-p)
  (let* ((events (remove-if-not
                  (lambda (event)
                    (actor-message-trace-matches-p event
                                                   actor-message-id
                                                   actor-role
                                                   phase
                                                   dead-letters-only-p))
                  (agent-session-events session)))
         (ordered (sort (copy-list events)
                        #'>
                        :key #'event-timestamp))
         (selected (if latest-only-p
                       (if ordered
                           (list (first ordered))
                           '())
                       ordered)))
    (make-service-query-response
     :desktop-task
     (if dead-letters-only-p :dead-letter-queue :actor-trace)
     (mapcar #'actor-message-transport-event-summary selected)
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if dead-letters-only-p
                                                      :desktop-task-dead-letter-queue-v1
                                                      :desktop-task-actor-trace-v1)
                                      :session session))))

(defun find-desktop-task-record-by-actor-message-id (session actor-message-id)
  (find actor-message-id
        (list-desktop-task-records session)
        :key (lambda (record)
               (let ((message (desktop-task-actor-message-for-record record)))
                 (and message
                      (actor-message-id message))))
        :test #'string=))

(defun desktop-task-actor-reply-summary (record)
  (let* ((actor-message (desktop-task-record-actor-message record))
         (result (desktop-task-record-result record))
         (last-error (desktop-task-record-last-error record)))
    (list :request-id (desktop-task-record-request-id record)
          :record-id (desktop-task-record-id record)
          :actor-message-id (and actor-message
                                 (actor-message-id actor-message))
          :target (desktop-task-record-target record)
          :operation (desktop-task-record-operation record)
          :actor-slice (or (and actor-message
                                (getf (actor-message-metadata actor-message) :slice))
                           (getf (desktop-task-record-request-metadata record)
                                 :actor-slice))
          :status (desktop-task-record-status record)
          :summary (or (and (listp result)
                            (or (getf result :summary)
                                (getf result :SUMMARY)))
                       (and (listp last-error)
                            (or (getf last-error :summary)
                                (getf last-error :SUMMARY)
                                (getf last-error :error)
                                (getf last-error :ERROR))))
          :error (and (listp last-error)
                      (or (getf last-error :error)
                          (getf last-error :ERROR)))
          :completed-at (desktop-task-record-completed-at record)
          :result (and (listp result)
                       (list :summary (or (getf result :summary)
                                          (getf result :SUMMARY))
                             :status (or (getf result :status)
                                         (getf result :STATUS))))
          :actor-message (actor-message-summary actor-message))))

(defun desktop-task-record-policy-ids* (records)
  (remove-duplicates
   (remove nil (mapcar #'desktop-task-record-policy-id records))
   :test #'eq))

(defun query-desktop-task-manifest-list-service (session)
  (declare (ignore session))
  (make-service-query-response
   :desktop-task
   :manifest-list
   (mapcar #'desktop-task-manifest-summary
           (list-registered-desktop-task-manifests :discoverable-only-p t))
   :metadata (make-service-metadata :authority :environment
                                    :read-model :desktop-task-manifest-list-v1
                                    :session session)))

(defun query-desktop-task-manifest-detail-service (session target operation)
  (declare (ignore session))
  (let ((manifest (find-desktop-task-manifest target operation)))
    (unless manifest
      (error "Unknown desktop task manifest ~S/~S" target operation))
    (make-service-query-response
     :desktop-task
     :manifest-detail
     (desktop-task-manifest-summary manifest)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-manifest-detail-v1
                                      :session session))))

(defun query-desktop-task-record-list-service (session &key thread-id status approval-status)
  (let ((records
          (remove-if-not
           (lambda (record)
             (and (or (null thread-id)
                      (and (desktop-task-record-thread-id record)
                           (string= thread-id (desktop-task-record-thread-id record))))
                  (or (null status)
                      (eq status (desktop-task-record-status record)))
                  (or (null approval-status)
                      (eq approval-status (desktop-task-record-approval-status record)))))
           (list-desktop-task-records session))))
    (make-service-query-response
     :desktop-task
     :record-list
     (mapcar (lambda (record)
               (desktop-task-record-summary-with-audit session record))
             records)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-record-list-v1
                                      :session session
                                      :thread-id thread-id))))

(defun query-desktop-task-record-detail-service (session record-id)
  (let ((record (find-desktop-task-record session record-id)))
    (unless record
      (error "Unknown desktop task record ~A" record-id))
    (make-service-query-response
     :desktop-task
     :record-detail
     (desktop-task-record-summary-with-audit session record)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-record-detail-v1
                                      :session session
                                      :thread-id (desktop-task-record-thread-id record)
                                      :turn-id (desktop-task-record-turn-id record)))))

(defun query-desktop-task-actor-list-service (session)
  (make-service-query-response
   :desktop-task
   :actor-list
   (mapcar (lambda (address)
             (desktop-task-actor-summary session address))
           (desktop-task-capability-actor-addresses session))
   :metadata (make-service-metadata :authority :environment
                                    :read-model :desktop-task-actor-list-v1
                                    :session session)))

(defun query-desktop-task-actor-detail-service (session actor-role)
  (let* ((role (normalize-actor-role actor-role :unknown))
         (actor-address
           (find role
                 (desktop-task-capability-actor-addresses session)
                 :key #'actor-address-role
                 :test #'eq)))
    (unless actor-address
      (error "Unknown desktop task actor ~S" actor-role))
    (make-service-query-response
     :desktop-task
     :actor-detail
     (desktop-task-actor-summary session actor-address)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-actor-detail-v1
                                      :session session))))

(defun query-desktop-task-actor-inbox-service (session actor-role &key status)
  (let* ((role (normalize-actor-role actor-role :unknown))
         (records
           (remove-if-not
            (lambda (record)
              (and (eq role
                       (desktop-task-actor-role-for-record record :direction :receiver))
                   (or (null status)
                       (eq status (desktop-task-record-status record)))))
            (list-desktop-task-records session))))
    (make-service-query-response
     :desktop-task
     :actor-inbox
     (mapcar (lambda (record)
               (desktop-task-record-summary-with-audit session record))
             records)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-actor-inbox-v1
                                      :session session))))

(defun query-desktop-task-actor-outbox-service (session actor-role &key status)
  (let* ((role (normalize-actor-role actor-role :unknown))
         (records
           (remove-if-not
            (lambda (record)
              (and (eq role
                       (desktop-task-actor-role-for-record record :direction :sender))
                   (or (null status)
                       (eq status (desktop-task-record-status record)))))
            (list-desktop-task-records session))))
    (make-service-query-response
     :desktop-task
     :actor-outbox
     (mapcar (lambda (record)
               (desktop-task-record-summary-with-audit session record))
             records)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-actor-outbox-v1
                                      :session session))))

(defun query-desktop-task-actor-message-detail-service (session actor-message-id)
  (let ((record (find-desktop-task-record-by-actor-message-id session actor-message-id)))
    (unless record
      (error "Unknown actor message ~A" actor-message-id))
    (make-service-query-response
     :desktop-task
     :actor-message-detail
     (desktop-task-record-summary-with-audit session record)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-actor-message-detail-v1
                                      :session session
                                      :thread-id (desktop-task-record-thread-id record)
                                      :turn-id (desktop-task-record-turn-id record)))))

(defun query-desktop-task-editor-mailbox-service (session
                                                  &key session-id pending-action-id status
                                                    approval-status scope-id latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (mutations
           (remove-if-not
            (lambda (entry)
              (and (or (null session-id)
                       (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                         (and entry-session-id
                              (string= session-id entry-session-id))))
                   (or (null pending-action-id)
                       (string= pending-action-id
                                (actor-mailbox-entry-pending-action-id entry)))
                   (or (null status)
                       (eq status (actor-mailbox-entry-status entry)))
                   (or (null approval-status)
                       (eq approval-status (actor-mailbox-entry-approval-status entry)))
                   (or (null scope-id)
                       (let ((entry-scope-id (getf (actor-mailbox-entry-payload entry) :scope-id)))
                         (and entry-scope-id
                              (string= scope-id entry-scope-id))))))
            (copy-list (or (getf mailboxes :editor-pending-mutation-mailbox) '()))))
         (selected (if latest-only-p
                       (if mutations (list (first mutations)) '())
                       mutations))
         (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected))))))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :editor-mailbox-latest :editor-mailbox)
     (list :session-id effective-session-id
           :receiver-actor (actor-address-summary
                            (make-standard-actor-address :editor
                                                         :kind :internal
                                                         :scope (or scope-id effective-session-id)
                                                         :display-name "Editor Actor"
                                                         :metadata '(:actor-class :capability-server)))
           :mutation-count (length selected)
           :mutations (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-editor-mailbox-latest-v1
                                                      :desktop-task-editor-mailbox-v1)
                                      :session session))))

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
           :request-count (length selected)
           :requests (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-context-chat-approval-inbox-latest-v1
                                                      :desktop-task-context-chat-approval-inbox-v1)
                                      :session session))))

(defun editor-authorization-summary (record)
  (let ((entry (editor-pending-mutation-summary record)))
    (list :session-id (getf entry :session-id)
          :approval-id (getf entry :approval-id)
          :record-id (getf entry :record-id)
          :request-id (getf entry :request-id)
          :actor-message-id (getf entry :actor-message-id)
          :pending-action-id (getf entry :pending-action-id)
          :sender (actor-address-summary
                   (make-governance-actor-address
                    :session-id (getf entry :session-id)))
          :receiver (getf entry :receiver)
          :reply-to (getf entry :reply-to)
          :originator (getf entry :originator)
          :target (getf entry :target)
          :operation (getf entry :operation)
          :actor-slice (getf entry :actor-slice)
          :scope-id (getf entry :scope-id)
          :buffer-id (getf entry :buffer-id)
          :package-name (getf entry :package-name)
          :text (getf entry :text)
          :status (getf entry :status)
          :governance-status (getf entry :governance-status)
          :approval-status (getf entry :approval-status)
          :summary (getf entry :summary)
          :created-at (getf entry :created-at)
          :approved-at (getf entry :approved-at)
          :completed-at (getf entry :completed-at)
          :actor-message (getf entry :actor-message))))

(defun query-desktop-task-editor-authorization-mailbox-service (session
                                                                &key session-id pending-action-id scope-id
                                                                  latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (authorizations
           (remove-if-not
            (lambda (entry)
              (and (or (null session-id)
                       (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                         (and entry-session-id
                              (string= session-id entry-session-id))))
                   (or (null pending-action-id)
                       (string= pending-action-id
                                (actor-mailbox-entry-pending-action-id entry)))
                   (or (null scope-id)
                       (let ((entry-scope-id (getf (actor-mailbox-entry-payload entry) :scope-id)))
                         (and entry-scope-id
                              (string= scope-id entry-scope-id))))))
            (copy-list (or (getf mailboxes :editor-authorization-mailbox) '()))))
        (selected (if latest-only-p
                       (if authorizations (list (first authorizations)) '())
                       authorizations))
        (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected))))))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :editor-authorization-mailbox-latest :editor-authorization-mailbox)
     (list :session-id effective-session-id
           :receiver-actor (actor-address-summary
                            (make-standard-actor-address :editor
                                                         :scope (or scope-id effective-session-id)
                                                         :metadata (append (when scope-id
                                                                             (list :scope-id scope-id))
                                                                           (when effective-session-id
                                                                             (list :session-id effective-session-id)))))
           :authorization-count (length selected)
           :authorizations (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-editor-authorization-mailbox-latest-v1
                                                      :desktop-task-editor-authorization-mailbox-v1)
                                      :session session))))

(defun editor-authorization-records (session &key session-id pending-action-id scope-id)
  (remove-if-not
   (lambda (record)
     (and (eq (desktop-task-record-target record) :editor)
          (desktop-task-record-pending-action-id record)
          (eq (desktop-task-record-approval-status record) :approved)
          (member (desktop-task-record-status record)
                  '(:awaiting-approval :approved)
                  :test #'eq)
          (or (null session-id)
              (let ((record-session-id (desktop-task-record-session-id record)))
                (and record-session-id
                     (string= session-id record-session-id))))
          (or (null pending-action-id)
              (string= pending-action-id
                       (desktop-task-record-pending-action-id record)))
          (or (null scope-id)
              (let ((record-scope-id (desktop-task-record-receiver-scope record)))
                (and record-scope-id
                     (string= scope-id record-scope-id))))))
   (list-desktop-task-records session)))

(defun command-desktop-task-apply-editor-authorization-service (session pending-action-id
                                                                &key session-id scope-id)
  (let* ((authorization-mailbox-entry
           (find-actor-mailbox-entry session
                                     :editor-authorization-mailbox
                                     :session-id session-id
                                     :pending-action-id pending-action-id))
         (record
           (or (and authorization-mailbox-entry
                    (let ((entry-actor-message-id
                            (actor-mailbox-entry-actor-message-id authorization-mailbox-entry)))
                      (and entry-actor-message-id
                           (find-desktop-task-record-by-actor-message-id session
                                                                         entry-actor-message-id))))
               (first (editor-authorization-records session
                                                    :session-id session-id
                                                    :pending-action-id pending-action-id
                                                    :scope-id scope-id))))
         (records (and record (list record))))
    (unless record
      (error "Unknown approved editor authorization ~A for session ~A."
             pending-action-id
             (or session-id :any)))
    (let* ((authorization-entry
             (service-response-data
              (command-desktop-task-consume-editor-authorization-service
               session
               pending-action-id
               :session-id session-id
               :scope-id scope-id)))
           (thread-id (desktop-task-record-thread-id record))
           (turn-id (desktop-task-record-turn-id record))
           (thread (and thread-id
                        (find-thread session thread-id)))
           (turn (and turn-id
                      (find-turn session turn-id)))
           (execution-results (execute-turn-governed-desktop-task-records session
                                                                          records
                                                                          :thread thread
                                                                          :turn turn))
           (reply-records
             (if turn-id
                 (desktop-task-records-for-turn session turn-id)
                 records))
           (result-task-results
             (mapcar #'desktop-task-record-canonical-result-summary
                     reply-records))
           (result-task-record-summaries
             (mapcar #'desktop-task-record-summary
                     reply-records))
           (assistant-message-text
             (or (some (lambda (entry)
                         (let ((result (getf entry :result)))
                           (and (listp result)
                                (or (getf result :summary)
                                    (getf result :message)))))
                       execution-results)
                 (some (lambda (entry)
                         (let ((result (getf entry :result)))
                           (and (listp result)
                                (getf result :summary))))
                       result-task-results)
                 "Applied the authorized editor mutation."))
           (result-summary assistant-message-text))
      (declare (ignore authorization-entry))
      (update-session-actor-mailbox-entry
       session
       :editor-authorization-mailbox
       (lambda (entry)
         (and (or (null session-id)
                  (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                    (and entry-session-id
                         (string= session-id entry-session-id))))
              (let ((entry-pending-action-id
                      (actor-mailbox-entry-pending-action-id entry)))
                (and entry-pending-action-id
                     (string= pending-action-id entry-pending-action-id)))))
       (lambda (entry)
         (setf (actor-mailbox-entry-delivery-status entry) :applied
               (actor-mailbox-entry-dequeued-at entry)
               (or (actor-mailbox-entry-dequeued-at entry)
                   (get-universal-time))
               (actor-mailbox-entry-completed-at entry)
               (or (actor-mailbox-entry-completed-at entry)
                   (get-universal-time)))
         entry)
       :reason :editor-authorization-applied
       :error-p nil)
      (update-session-actor-mailbox-entry
       session
       :governance-decision-outbox
       (lambda (entry)
         (and (or (null session-id)
                  (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                    (and entry-session-id
                         (string= session-id entry-session-id))))
              (let ((entry-pending-action-id
                      (actor-mailbox-entry-pending-action-id entry)))
                (and entry-pending-action-id
                     (string= pending-action-id entry-pending-action-id)))))
       (lambda (entry)
         (setf (actor-mailbox-entry-delivery-status entry) :applied
               (actor-mailbox-entry-dequeued-at entry)
               (or (actor-mailbox-entry-dequeued-at entry)
                   (get-universal-time))
               (actor-mailbox-entry-completed-at entry)
               (or (actor-mailbox-entry-completed-at entry)
                   (get-universal-time)))
         entry)
       :reason :governance-decision-applied
       :error-p nil)
      (make-service-command-response
       :desktop-task
       :apply-editor-authorization
       (list :session-id (or session-id
                             (desktop-task-record-session-id record))
             :pending-action-id pending-action-id
             :approval-ids (remove-duplicates
                            (remove nil (mapcar #'desktop-task-record-approval-id reply-records))
                            :test #'string=)
             :actor-message-ids (remove nil
                                        (mapcar (lambda (entry)
                                                  (let ((message (desktop-task-record-actor-message entry)))
                                                    (and message
                                                         (actor-message-id message))))
                                                reply-records))
             :thread thread
             :turn turn
             :assistant-message assistant-message-text
             :summary result-summary
             :desktop-task-results result-task-results
             :task-record-summaries result-task-record-summaries
             :replies (mapcar #'desktop-task-actor-reply-summary reply-records)
             :execution-results execution-results
             :result (list :summary result-summary
                           :desktop-task-results result-task-results
                           :task-record-summaries result-task-record-summaries
                           :execution-results execution-results))
       :metadata (make-service-metadata :authority :environment
                                        :command-model :desktop-task-apply-editor-authorization-v1
                                      :session session
                                      :thread-id thread-id
                                      :turn-id turn-id)))))

(defun command-desktop-task-ack-context-chat-approval-service (session approval-id
                                                               &key session-id mailbox-entry-id actor-message-id)
  (let ((entry
          (update-session-actor-mailbox-entry
           session
           :context-chat-approval-inbox
           (lambda (current-entry)
             (and (or (null mailbox-entry-id)
                      (string= mailbox-entry-id
                               (actor-mailbox-entry-id current-entry)))
                  (or (null session-id)
                      (let ((entry-session-id (actor-mailbox-entry-session-id current-entry)))
                        (and entry-session-id
                             (string= session-id entry-session-id))))
                  (or (null approval-id)
                      (let ((entry-approval-id (actor-mailbox-entry-approval-id current-entry)))
                        (and entry-approval-id
                             (string= approval-id entry-approval-id))))
                  (or (null actor-message-id)
                      (let ((entry-actor-message-id
                              (actor-mailbox-entry-actor-message-id current-entry)))
                        (and entry-actor-message-id
                             (string= actor-message-id entry-actor-message-id))))))
           (lambda (current-entry)
             (setf (actor-mailbox-entry-delivery-status current-entry) :consumed
                   (actor-mailbox-entry-acknowledged-at current-entry)
                   (or (actor-mailbox-entry-acknowledged-at current-entry)
                       (get-universal-time)))
             current-entry)
           :reason :context-chat-approval-acknowledged)))
    (make-service-command-response
     :desktop-task
     :ack-context-chat-approval
     (actor-mailbox-entry-summary entry)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :desktop-task-ack-context-chat-approval-v1
                                      :session session))))

(defun command-desktop-task-consume-editor-authorization-service (session pending-action-id
                                                                  &key session-id mailbox-entry-id scope-id)
  (let ((entry
          (update-session-actor-mailbox-entry
           session
           :editor-authorization-mailbox
           (lambda (current-entry)
             (and (or (null mailbox-entry-id)
                      (string= mailbox-entry-id
                               (actor-mailbox-entry-id current-entry)))
                  (or (null session-id)
                      (let ((entry-session-id (actor-mailbox-entry-session-id current-entry)))
                        (and entry-session-id
                             (string= session-id entry-session-id))))
                  (or (null pending-action-id)
                      (let ((entry-pending-action-id
                              (actor-mailbox-entry-pending-action-id current-entry)))
                        (and entry-pending-action-id
                             (string= pending-action-id entry-pending-action-id))))
                  (or (null scope-id)
                      (let ((entry-scope-id
                              (getf (actor-mailbox-entry-payload current-entry) :scope-id)))
                        (and entry-scope-id
                             (string= scope-id entry-scope-id))))))
           (lambda (current-entry)
             (setf (actor-mailbox-entry-delivery-status current-entry) :dequeued
                   (actor-mailbox-entry-dequeued-at current-entry)
                   (or (actor-mailbox-entry-dequeued-at current-entry)
                       (get-universal-time)))
             current-entry)
           :reason :editor-authorization-consumed)))
    (make-service-command-response
     :desktop-task
     :consume-editor-authorization
     (progn
       (update-session-actor-mailbox-entry
        session
        :governance-decision-outbox
        (lambda (current-entry)
          (and (or (null session-id)
                   (let ((entry-session-id (actor-mailbox-entry-session-id current-entry)))
                     (and entry-session-id
                          (string= session-id entry-session-id))))
               (or (null pending-action-id)
                   (let ((entry-pending-action-id
                           (actor-mailbox-entry-pending-action-id current-entry)))
                     (and entry-pending-action-id
                          (string= pending-action-id entry-pending-action-id))))
               (or (null scope-id)
                   (let ((entry-scope-id
                           (getf (actor-mailbox-entry-payload current-entry) :scope-id)))
                     (and entry-scope-id
                          (string= scope-id entry-scope-id))))))
        (lambda (current-entry)
          (setf (actor-mailbox-entry-delivery-status current-entry) :dequeued
                (actor-mailbox-entry-dequeued-at current-entry)
                (or (actor-mailbox-entry-dequeued-at current-entry)
                    (get-universal-time)))
          current-entry)
        :reason :governance-decision-dequeued
        :error-p nil)
       (actor-mailbox-entry-summary entry))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :desktop-task-consume-editor-authorization-v1
                                      :session session))))

(defun command-desktop-task-dequeue-governance-approval-service (session approval-id
                                                                 &key session-id mailbox-entry-id actor-message-id)
  (update-session-actor-mailbox-entry
   session
   :governance-inbox
   (lambda (entry)
     (and (or (null mailbox-entry-id)
              (string= mailbox-entry-id
                       (actor-mailbox-entry-id entry)))
          (or (null session-id)
              (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                (and entry-session-id
                     (string= session-id entry-session-id))))
          (or (null approval-id)
              (let ((entry-approval-id (actor-mailbox-entry-approval-id entry)))
                (and entry-approval-id
                     (string= approval-id entry-approval-id))))
          (or (null actor-message-id)
              (let ((entry-actor-message-id
                      (actor-mailbox-entry-actor-message-id entry)))
                (and entry-actor-message-id
                     (string= actor-message-id entry-actor-message-id))))))
   (lambda (entry)
     (setf (actor-mailbox-entry-delivery-status entry) :dequeued
           (actor-mailbox-entry-dequeued-at entry)
           (or (actor-mailbox-entry-dequeued-at entry)
               (get-universal-time)))
     entry)
   :reason :governance-approval-dequeued
   :error-p nil))

(defun query-desktop-task-actor-replies-service (session actor-role &key latest-only-p)
  (let* ((role (normalize-actor-role actor-role :unknown))
         (records
           (remove-if-not
            (lambda (record)
              (and (eq role
                       (desktop-task-actor-role-for-record record :direction :sender))
                   (member (desktop-task-record-status record)
                           '(:completed :failed :retryable-failure :canceled)
                           :test #'eq)))
            (list-desktop-task-records session)))
         (ordered
           (sort (copy-list records)
                 #'>
                 :key (lambda (record)
                        (or (desktop-task-record-completed-at record)
                            (desktop-task-record-created-at record)
                            0))))
         (selected (if latest-only-p
                       (if ordered
                           (list (first ordered))
                           '())
                       ordered)))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :actor-latest-reply :actor-replies)
     (mapcar #'desktop-task-actor-reply-summary selected)
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-actor-latest-reply-v1
                                                      :desktop-task-actor-replies-v1)
                                      :session session))))

(defun find-desktop-task-record-by-id (session record-id)
  (find record-id
        (list-desktop-task-records session)
        :key #'desktop-task-record-id
        :test #'string=))

(defun latest-pending-approval-mailbox-entries (entries)
  (let* ((awaiting (remove-if-not
                    (lambda (entry)
                      (eq (actor-mailbox-entry-approval-status entry) :awaiting-approval))
                    entries))
         (latest (first awaiting)))
    (when latest
      (let ((latest-approval-id (actor-mailbox-entry-approval-id latest))
            (latest-actor-message-id (actor-mailbox-entry-actor-message-id latest))
            (latest-session-id (actor-mailbox-entry-session-id latest)))
        (remove-if-not
         (lambda (entry)
           (and (eq (actor-mailbox-entry-approval-status entry) :awaiting-approval)
                (or (and latest-approval-id
                         (let ((entry-approval-id (actor-mailbox-entry-approval-id entry)))
                           (and entry-approval-id
                                (string= latest-approval-id entry-approval-id))))
                    (and latest-actor-message-id
                         (let ((entry-actor-message-id
                                 (actor-mailbox-entry-actor-message-id entry)))
                           (and entry-actor-message-id
                                (string= latest-actor-message-id entry-actor-message-id))))
                    (and latest-session-id
                         (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                           (and entry-session-id
                                (string= latest-session-id entry-session-id)))))))
         awaiting)))))

(defun actor-mailbox-entry-receiver-role (entry)
  (let* ((receiver (actor-mailbox-entry-receiver entry))
         (payload (actor-mailbox-entry-payload entry))
         (payload-receiver (and (listp payload)
                                (getf payload :receiver))))
    (or (and receiver
             (actor-address-role receiver))
        (and (listp payload-receiver)
             (or (getf payload-receiver :role)
                 (getf payload-receiver :ROLE)))
        (normalize-actor-role (actor-mailbox-entry-target entry) nil))))

(defun compute-pending-approval-summary-from-mailbox-entries (session entries)
  (let* ((session-id (and entries
                          (actor-mailbox-entry-session-id (first entries))))
         (thread-id (and entries
                         (let ((payload (actor-mailbox-entry-payload (first entries))))
                           (and (listp payload)
                                (or (getf payload :thread-id)
                                    (getf payload :THREAD-ID))))))
         (turn-id (and entries
                       (let ((payload (actor-mailbox-entry-payload (first entries))))
                         (and (listp payload)
                              (or (getf payload :turn-id)
                                  (getf payload :TURN-ID))))))
         (actor-messages
           (remove nil
                   (mapcar (lambda (entry)
                             (let ((payload (actor-mailbox-entry-payload entry)))
                               (and (listp payload)
                                    (getf payload :actor-message))))
                           entries)))
         (receiver-roles
           (remove-duplicates
            (remove nil
                    (mapcar #'actor-mailbox-entry-receiver-role entries))
            :test #'eq))
         (policy-ids
           (remove-duplicates
            (remove nil
                    (mapcar (lambda (entry)
                              (let ((payload (actor-mailbox-entry-payload entry)))
                                (and (listp payload)
                                     (or (getf payload :policy-id)
                                         (getf payload :POLICY-ID)))))
                            entries))
            :test #'eq))
         (approval-ids
           (remove-duplicates
            (remove nil
                    (mapcar #'actor-mailbox-entry-approval-id entries))
            :test #'string=))
         (pending-action-ids
           (remove-duplicates
            (remove nil
                    (mapcar #'actor-mailbox-entry-pending-action-id entries))
            :test #'string=))
         (governance-actor (actor-address-summary (make-governance-actor-address
                                                   :session-id session-id)))
         (record-ids
           (remove nil
                   (mapcar (lambda (entry)
                             (let ((payload (actor-mailbox-entry-payload entry)))
                               (and (listp payload)
                                    (or (getf payload :record-id)
                                        (getf payload :RECORD-ID)))))
                           entries)))
         (records
           (remove nil
                   (mapcar (lambda (record-id)
                             (let ((record (find-desktop-task-record-by-id session record-id)))
                               (and record
                                    (desktop-task-record-summary-with-audit session record))))
                           record-ids))))
    (list :session-id session-id
          :thread-id thread-id
          :turn-id turn-id
          :governance-actor governance-actor
          :record-ids record-ids
          :approval-ids approval-ids
          :policy-ids policy-ids
          :pending-action-ids pending-action-ids
          :receiver-roles receiver-roles
          :actor-message-ids (remove nil
                                     (mapcar #'actor-mailbox-entry-actor-message-id entries))
          :actor-messages actor-messages
          :requests (mapcar #'actor-mailbox-entry-summary entries)
          :records records)))

(defun refresh-session-actor-mailboxes (session)
  (let* ((existing-mailboxes (or (agent-session-actor-mailboxes session) '()))
         (all-records (list-desktop-task-records session))
         (context-chat-records
           (sort (copy-list
                  (remove-if-not #'context-chat-mailbox-record-p all-records))
                 #'>
                 :key (lambda (record)
                        (or (desktop-task-record-created-at record) 0))))
         (governance-records
           (sort (copy-list
                  (remove-if-not (lambda (record)
                                   (desktop-task-record-approval-id record))
                                 all-records))
                 #'>
                 :key (lambda (record)
                        (or (desktop-task-record-created-at record) 0))))
         (governance-decision-records
           (sort (copy-list
                  (remove-if-not
                   (lambda (record)
                     (and (desktop-task-record-approval-id record)
                          (eq (desktop-task-record-target record) :editor)
                          (desktop-task-record-pending-action-id record)
                          (eq (desktop-task-record-approval-status record) :approved)))
                   all-records))
                 #'>
                 :key (lambda (record)
                        (or (desktop-task-record-approved-at record)
                            (desktop-task-record-started-at record)
                            (desktop-task-record-completed-at record)
                            (desktop-task-record-created-at record)
                            0))))
         (editor-authorization-records
           (sort (copy-list
                  (remove-if-not
                   (lambda (record)
                     (and (eq (desktop-task-record-target record) :editor)
                          (desktop-task-record-pending-action-id record)
                          (eq (desktop-task-record-approval-status record) :approved)))
                   all-records))
                 #'>
                 :key (lambda (record)
                        (or (desktop-task-record-approved-at record)
                            (desktop-task-record-created-at record)
                            0))))
         (editor-pending-mutation-records
           (sort (copy-list
                  (remove-if-not
                   (lambda (record)
                     (and (eq (desktop-task-record-target record) :editor)
                          (desktop-task-record-pending-action-id record)))
                   all-records))
                 #'>
                 :key (lambda (record)
                        (or (desktop-task-record-completed-at record)
                            (desktop-task-record-started-at record)
                            (desktop-task-record-approved-at record)
                            (desktop-task-record-created-at record)
                            0))))
         (context-chat-mailbox
           (merge-actor-mailbox-entries
            :context-chat-mailbox
            (copy-list (or (getf existing-mailboxes :context-chat-mailbox) '()))
            (mapcar (lambda (record)
                      (make-actor-mailbox-entry-for-record
                       record
                       :context-chat-mailbox
                       (context-chat-mailbox-entry-summary record)))
                    context-chat-records)))
         (context-chat-approval-inbox
           (merge-actor-mailbox-entries
            :context-chat-approval-inbox
            (copy-list (or (getf existing-mailboxes :context-chat-approval-inbox) '()))
            (mapcar (lambda (record)
                      (make-actor-mailbox-entry-for-record
                       record
                       :context-chat-approval-inbox
                       (context-chat-approval-request-summary record)))
                    (remove-if-not (lambda (record)
                                     (desktop-task-record-approval-id record))
                                   context-chat-records))))
         (governance-inbox
           (merge-actor-mailbox-entries
            :governance-inbox
            (copy-list (or (getf existing-mailboxes :governance-inbox) '()))
            (mapcar (lambda (record)
                      (make-actor-mailbox-entry-for-record
                       record
                       :governance-inbox
                       (governance-approval-request-summary record)))
                    governance-records)))
         (governance-decision-outbox
           (merge-actor-mailbox-entries
            :governance-decision-outbox
            (copy-list (or (getf existing-mailboxes :governance-decision-outbox) '()))
            (mapcar (lambda (record)
                      (make-actor-mailbox-entry-for-record
                       record
                       :governance-decision-outbox
                       (governance-decision-summary record)))
                    governance-decision-records)))
         (runtime-inbox
           (merge-actor-mailbox-entries
            :runtime-inbox
            (copy-list (or (getf existing-mailboxes :runtime-inbox) '()))
            (mapcar (lambda (record)
                      (make-actor-mailbox-entry-for-record
                       record
                       :runtime-inbox
                       (runtime-eval-mailbox-entry-summary record)))
                    (remove-if-not (lambda (record)
                                     (eq (desktop-task-record-target record) :runtime))
                                   all-records))))
         (runtime-outbox
           (merge-actor-mailbox-entries
            :runtime-outbox
            (copy-list (or (getf existing-mailboxes :runtime-outbox) '()))
            (mapcar (lambda (record)
                      (make-actor-mailbox-entry-for-record
                       record
                       :runtime-outbox
                       (runtime-eval-outbox-entry-summary record)))
                    (remove-if-not (lambda (record)
                                     (and (eq (desktop-task-record-target record) :runtime)
                                          (member (desktop-task-record-status record)
                                                  '(:completed :failed :retryable-failure :canceled)
                                                  :test #'eq)))
                                   all-records))))
         (editor-pending-mutation-mailbox
           (merge-actor-mailbox-entries
            :editor-pending-mutation-mailbox
            (copy-list (or (getf existing-mailboxes :editor-pending-mutation-mailbox) '()))
            (mapcar (lambda (record)
                      (make-actor-mailbox-entry-for-record
                       record
                       :editor-pending-mutation-mailbox
                       (editor-pending-mutation-summary record)))
                    editor-pending-mutation-records)))
         (editor-authorization-mailbox
           (merge-actor-mailbox-entries
            :editor-authorization-mailbox
            (copy-list (or (getf existing-mailboxes :editor-authorization-mailbox) '()))
            (mapcar (lambda (record)
                      (make-actor-mailbox-entry-for-record
                       record
                       :editor-authorization-mailbox
                       (editor-authorization-summary record)))
                    editor-authorization-records)))
         (pending-approval-entries
           (latest-pending-approval-mailbox-entries context-chat-approval-inbox))
         (mailboxes
           (list :context-chat-mailbox context-chat-mailbox
                 :context-chat-approval-inbox context-chat-approval-inbox
                 :governance-inbox governance-inbox
                 :governance-decision-outbox governance-decision-outbox
                 :runtime-inbox runtime-inbox
                 :runtime-outbox runtime-outbox
                 :runtime-state (runtime-state-summary
                                 (remove-if-not (lambda (record)
                                                  (eq (desktop-task-record-target record) :runtime))
                                                all-records))
                 :editor-pending-mutation-mailbox editor-pending-mutation-mailbox
                 :editor-authorization-mailbox editor-authorization-mailbox
                 :pending-approval
                 (and pending-approval-entries
                      (compute-pending-approval-summary-from-mailbox-entries
                       session
                       pending-approval-entries)))))
    (setf (agent-session-actor-mailboxes session) mailboxes)
    mailboxes))

(defun ensure-session-actor-mailboxes (session)
  (or (agent-session-actor-mailboxes session)
      (refresh-session-actor-mailboxes session)))

(defun query-desktop-task-pending-approval-service (session)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (pending-approval (or (getf mailboxes :pending-approval)
                               '()))
         (turn-id (getf pending-approval :turn-id)))
    (make-service-query-response
     :desktop-task
     :pending-approval
     pending-approval
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-pending-approval-v1
                                      :session session
                                      :turn-id turn-id))))

(defun governance-approval-request-summary (record)
  (let* ((actor-message (desktop-task-record-actor-message record))
         (request-metadata (desktop-task-record-request-metadata record))
         (record-metadata (desktop-task-record-metadata record)))
    (list :session-id (desktop-task-record-session-id record)
          :approval-id (desktop-task-record-approval-id record)
          :record-id (desktop-task-record-id record)
          :request-id (desktop-task-record-request-id record)
          :actor-message-id (and actor-message
                                 (actor-message-id actor-message))
          :sender (actor-address-summary (and actor-message
                                              (actor-message-sender actor-message)))
          :receiver (actor-address-summary (and actor-message
                                                (actor-message-receiver actor-message)))
          :governance-actor (actor-address-summary (make-governance-actor-address
                                                    :session-id (desktop-task-record-session-id record)))
          :target (desktop-task-record-target record)
          :operation (desktop-task-record-operation record)
          :capability (desktop-task-record-capability record)
          :actor-slice (or (and actor-message
                                (getf (actor-message-metadata actor-message) :slice))
                           (getf request-metadata :actor-slice))
          :status (desktop-task-record-status record)
          :governance-status (desktop-task-record-governance-status record)
          :approval-status (desktop-task-record-approval-status record)
          :policy-id (desktop-task-record-policy-id record)
          :created-at (desktop-task-record-created-at record)
          :approved-at (desktop-task-record-approved-at record)
          :completed-at (desktop-task-record-completed-at record)
          :summary (or (getf record-metadata :summary)
                       (getf request-metadata :summary))
          :request-metadata request-metadata
          :record-metadata record-metadata
          :actor-message (actor-message-summary actor-message))))

(defun governance-decision-summary (record)
  (let ((entry (editor-pending-mutation-summary record)))
    (list :session-id (getf entry :session-id)
          :approval-id (getf entry :approval-id)
          :record-id (getf entry :record-id)
          :request-id (getf entry :request-id)
          :actor-message-id (getf entry :actor-message-id)
          :pending-action-id (getf entry :pending-action-id)
          :governance-actor (actor-address-summary
                             (make-governance-actor-address
                              :session-id (getf entry :session-id)))
          :sender (actor-address-summary
                   (make-governance-actor-address
                    :session-id (getf entry :session-id)))
          :receiver (getf entry :receiver)
          :reply-to (getf entry :reply-to)
          :originator (getf entry :originator)
          :target (getf entry :target)
          :operation (getf entry :operation)
          :actor-slice (getf entry :actor-slice)
          :scope-id (getf entry :scope-id)
          :buffer-id (getf entry :buffer-id)
          :package-name (getf entry :package-name)
          :text (getf entry :text)
          :status (getf entry :status)
          :governance-status (getf entry :governance-status)
          :approval-status (getf entry :approval-status)
          :summary (getf entry :summary)
          :created-at (getf entry :created-at)
          :approved-at (getf entry :approved-at)
          :completed-at (getf entry :completed-at)
          :actor-message (getf entry :actor-message))))

(defun governance-approval-record-matches-p (record &key session-id approval-id actor-message-id status)
  (let* ((message (desktop-task-record-actor-message record))
         (record-session-id (desktop-task-record-session-id record))
         (record-approval-id (desktop-task-record-approval-id record))
         (record-message-id (and message
                                 (actor-message-id message))))
    (and record-approval-id
         (or (null session-id)
             (and record-session-id
                  (string= session-id record-session-id)))
         (or (null approval-id)
             (string= approval-id record-approval-id))
         (or (null actor-message-id)
             (and record-message-id
                  (string= actor-message-id record-message-id)))
         (or (null status)
             (eq status (desktop-task-record-approval-status record))))))

(defun governance-approval-records (session &key session-id approval-id actor-message-id status)
  (remove-if-not
   (lambda (record)
     (governance-approval-record-matches-p
      record
      :session-id session-id
      :approval-id approval-id
      :actor-message-id actor-message-id
      :status status))
   (list-desktop-task-records session)))

(defun query-desktop-task-governance-state-service (session &key session-id approval-id actor-message-id latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (requests (remove-if-not
                    (lambda (entry)
                      (and (or (null session-id)
                               (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                                 (and entry-session-id
                                      (string= session-id entry-session-id))))
                           (or (null approval-id)
                               (string= approval-id (actor-mailbox-entry-approval-id entry)))
                           (or (null actor-message-id)
                               (string= actor-message-id
                                        (actor-mailbox-entry-actor-message-id entry)))))
                    (copy-list (or (getf mailboxes :governance-inbox) '()))))
         (selected (if latest-only-p
                       (if requests
                           (list (first requests))
                           '())
                       requests))
         (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected)))))
         (effective-approval-id (or approval-id
                                    (and selected
                                         (actor-mailbox-entry-approval-id (first selected))))))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :governance-latest-state :governance-state)
     (list :session-id effective-session-id
           :approval-id effective-approval-id
           :governance-actor (actor-address-summary (make-governance-actor-address
                                                     :session-id effective-session-id))
           :count (length selected)
           :requests (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-governance-latest-state-v1
                                                      :desktop-task-governance-state-v1)
                                      :session session))))

(defun query-desktop-task-governance-inbox-service (session
                                                    &key session-id approval-status latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (requests (remove-if-not
                    (lambda (entry)
                      (and (or (null session-id)
                               (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                                 (and entry-session-id
                                      (string= session-id entry-session-id))))
                           (or (null approval-status)
                               (eq approval-status
                                   (actor-mailbox-entry-approval-status entry)))))
                    (copy-list (or (getf mailboxes :governance-inbox) '()))))
         (selected (if latest-only-p
                       (if requests
                           (list (first requests))
                           '())
                       requests))
         (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected))))))
    (make-service-query-response
     :desktop-task
     :governance-inbox
     (list :session-id effective-session-id
           :governance-actor (actor-address-summary (make-governance-actor-address
                                                     :session-id effective-session-id))
           :request-count (length selected)
           :requests (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-governance-inbox-v1
                                      :session session))))

(defun query-desktop-task-governance-decision-outbox-service (session
                                                              &key session-id approval-id pending-action-id
                                                                latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (decisions
           (remove-if-not
            (lambda (entry)
              (and (or (null session-id)
                       (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                         (and entry-session-id
                              (string= session-id entry-session-id))))
                   (or (null approval-id)
                       (let ((entry-approval-id (actor-mailbox-entry-approval-id entry)))
                         (and entry-approval-id
                              (string= approval-id entry-approval-id))))
                   (or (null pending-action-id)
                       (let ((entry-pending-action-id
                               (actor-mailbox-entry-pending-action-id entry)))
                         (and entry-pending-action-id
                              (string= pending-action-id entry-pending-action-id))))))
            (copy-list (or (getf mailboxes :governance-decision-outbox) '()))))
         (selected (if latest-only-p
                       (if decisions
                           (list (first decisions))
                           '())
                       decisions))
         (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected))))))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :governance-decision-outbox-latest :governance-decision-outbox)
     (list :session-id effective-session-id
           :governance-actor (actor-address-summary
                              (make-governance-actor-address
                               :session-id effective-session-id))
           :decision-count (length selected)
           :decisions (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-governance-decision-outbox-latest-v1
                                                      :desktop-task-governance-decision-outbox-v1)
                                      :session session))))

(defun query-desktop-task-runtime-inbox-service (session
                                                 &key session-id latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (entries (remove-if-not
                   (lambda (entry)
                     (or (null session-id)
                         (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                           (and entry-session-id
                                (string= session-id entry-session-id)))))
                   (copy-list (or (getf mailboxes :runtime-inbox) '()))))
         (selected (if latest-only-p
                       (if entries
                           (list (first entries))
                           '())
                       entries))
         (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected))))))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :runtime-inbox-latest :runtime-inbox)
     (list :session-id effective-session-id
           :runtime-actor (actor-address-summary
                           (make-standard-actor-address :runtime
                                                        :scope effective-session-id
                                                        :metadata (when effective-session-id
                                                                    (list :session-id effective-session-id))))
           :message-count (length selected)
           :messages (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-runtime-inbox-latest-v1
                                                      :desktop-task-runtime-inbox-v1)
                                      :session session))))

(defun query-desktop-task-runtime-outbox-service (session
                                                  &key session-id latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (entries (remove-if-not
                   (lambda (entry)
                     (or (null session-id)
                         (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                           (and entry-session-id
                                (string= session-id entry-session-id)))))
                   (copy-list (or (getf mailboxes :runtime-outbox) '()))))
         (selected (if latest-only-p
                       (if entries
                           (list (first entries))
                           '())
                       entries))
         (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected))))))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :runtime-outbox-latest :runtime-outbox)
     (list :session-id effective-session-id
           :runtime-actor (actor-address-summary
                           (make-standard-actor-address :runtime
                                                        :scope effective-session-id
                                                        :display-name "Runtime Actor"
                                                        :metadata (when effective-session-id
                                                                    (list :session-id effective-session-id
                                                                          :actor-class :capability-server
                                                                          :runtime-id "runtime-primary"))))
           :reply-count (length selected)
           :replies (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-runtime-outbox-latest-v1
                                                      :desktop-task-runtime-outbox-v1)
                                      :session session))))

(defun query-desktop-task-runtime-state-service (session
                                                 &key session-id package-name symbol-name)
  (declare (ignore session-id))
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (runtime-state (copy-tree (or (getf mailboxes :runtime-state) '())))
         (definitions (or (getf runtime-state :definitions) '()))
         (filtered-definitions
           (remove-if-not
            (lambda (entry)
              (and (or (null package-name)
                       (string= (or (getf entry :package-name) "") package-name))
                   (or (null symbol-name)
                       (string= (or (getf entry :symbol-name) "") symbol-name))))
            definitions)))
    (make-service-query-response
     :desktop-task
     :runtime-state
     (list :definition-count (length filtered-definitions)
           :definitions filtered-definitions)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-runtime-state-v1
                                      :session session))))

(defun query-desktop-task-actor-flow-service (session
                                              &key session-id approval-id pending-action-id
                                                actor-message-id scope-id latest-only-p)
  (let* ((pending-approval
           (service-response-data
            (query-desktop-task-pending-approval-service session)))
         (effective-session-id
           (or session-id
               (getf pending-approval :session-id)))
         (effective-approval-id
           (or approval-id
               (and (listp pending-approval)
                    (first (getf pending-approval :approval-ids)))))
         (effective-pending-action-id
           (or pending-action-id
               (and (listp pending-approval)
                    (first (getf pending-approval :pending-action-ids)))))
         (context-chat-mailbox
           (service-response-data
            (query-desktop-task-context-chat-mailbox-service
             session
             :session-id effective-session-id
             :latest-only-p latest-only-p)))
         (context-chat-approval-inbox
           (service-response-data
            (query-desktop-task-context-chat-approval-inbox-service
             session
             :session-id effective-session-id
             :latest-only-p latest-only-p)))
         (governance-state
           (service-response-data
            (query-desktop-task-governance-state-service
             session
             :session-id effective-session-id
             :approval-id effective-approval-id
             :actor-message-id actor-message-id
             :latest-only-p latest-only-p)))
         (governance-inbox
           (service-response-data
            (query-desktop-task-governance-inbox-service
             session
             :session-id effective-session-id
             :latest-only-p latest-only-p)))
         (governance-decisions
           (service-response-data
            (query-desktop-task-governance-decision-outbox-service
             session
             :session-id effective-session-id
             :approval-id effective-approval-id
             :pending-action-id effective-pending-action-id
             :latest-only-p latest-only-p)))
         (runtime-inbox
           (service-response-data
            (query-desktop-task-runtime-inbox-service
             session
             :session-id effective-session-id
             :latest-only-p latest-only-p)))
         (runtime-outbox
           (service-response-data
            (query-desktop-task-runtime-outbox-service
             session
             :session-id effective-session-id
             :latest-only-p latest-only-p)))
         (runtime-state
           (service-response-data
            (query-desktop-task-runtime-state-service
             session
             :session-id effective-session-id)))
         (editor-pending-mutations
           (service-response-data
            (query-desktop-task-editor-mailbox-service
             session
             :session-id effective-session-id
             :pending-action-id effective-pending-action-id
             :scope-id scope-id
             :latest-only-p latest-only-p)))
         (editor-authorizations
           (service-response-data
            (query-desktop-task-editor-authorization-mailbox-service
             session
             :session-id effective-session-id
             :pending-action-id effective-pending-action-id
             :scope-id scope-id
             :latest-only-p latest-only-p))))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :actor-flow-latest :actor-flow)
     (list :session-id effective-session-id
           :approval-id effective-approval-id
           :pending-action-id effective-pending-action-id
           :actor-message-id (or actor-message-id
                                 (and (listp pending-approval)
                                      (first (getf pending-approval :actor-message-ids))))
           :chat-actor (or (getf context-chat-mailbox :chat-actor)
                           (getf context-chat-approval-inbox :chat-actor))
           :governance-actor (or (getf governance-state :governance-actor)
                                 (getf governance-inbox :governance-actor)
                                 (getf governance-decisions :governance-actor))
           :editor-actor (or (getf editor-pending-mutations :receiver-actor)
                             (getf editor-authorizations :receiver-actor))
           :pending-approval pending-approval
           :context-chat-mailbox context-chat-mailbox
           :context-chat-approval-inbox context-chat-approval-inbox
           :governance-state governance-state
           :governance-inbox governance-inbox
           :governance-decisions governance-decisions
           :runtime-inbox runtime-inbox
           :runtime-outbox runtime-outbox
           :runtime-state runtime-state
           :editor-pending-mutations editor-pending-mutations
           :editor-authorizations editor-authorizations)
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-actor-flow-latest-v1
                                                      :desktop-task-actor-flow-v1)
                                      :session session))))

(defun query-desktop-task-dead-letter-queue-service (session &key actor-role)
  (query-desktop-task-actor-trace-service session
                                          :actor-role actor-role
                                          :dead-letters-only-p t))

(defun command-desktop-task-approve-actor-message-service (session provider actor-message-id
                                                            &key (source :say)
                                                              (operator-mode :conversation))
  (declare (ignore provider source operator-mode))
  (let* ((approval-entry
           (find-actor-mailbox-entry session
                                     :context-chat-approval-inbox
                                     :actor-message-id actor-message-id))
         (record
           (or (and approval-entry
                    (let ((entry-actor-message-id
                            (actor-mailbox-entry-actor-message-id approval-entry)))
                      (and entry-actor-message-id
                           (find-desktop-task-record-by-actor-message-id session
                                                                         entry-actor-message-id))))
               (find-desktop-task-record-by-actor-message-id session actor-message-id))))
    (unless record
      (error "Unknown actor message ~A" actor-message-id))
    (unless (eq (desktop-task-record-approval-status record) :awaiting-approval)
      (error "Actor message ~A is not awaiting approval." actor-message-id))
    (let* ((turn-id (desktop-task-record-turn-id record))
           (thread-id (desktop-task-record-thread-id record))
           (thread (and thread-id
                        (find-thread session thread-id)))
           (turn (and turn-id
                      (find-turn session turn-id)))
           (entry-session-id (and approval-entry
                                  (actor-mailbox-entry-session-id approval-entry)))
           (entry-approval-id (and approval-entry
                                   (actor-mailbox-entry-approval-id approval-entry)))
           (records (or (and turn-id
                             (desktop-task-records-awaiting-approval-for-turn session turn-id))
                        (list record)))
           (policy-ids (desktop-task-record-policy-ids* records)))
      (dolist (entry records)
        (let ((entry-session-id (or entry-session-id
                                    (desktop-task-record-session-id entry)))
              (entry-approval-id (or entry-approval-id
                                     (desktop-task-record-approval-id entry)))
              (entry-actor-message-id
                (let ((message (desktop-task-record-actor-message entry)))
                  (and message
                       (actor-message-id message)))))
          (when entry-approval-id
            (command-desktop-task-ack-context-chat-approval-service
             session
             entry-approval-id
             :session-id entry-session-id
             :actor-message-id entry-actor-message-id)
            (command-desktop-task-dequeue-governance-approval-service
             session
             entry-approval-id
             :session-id entry-session-id
             :actor-message-id entry-actor-message-id))))
      (dolist (policy-id policy-ids)
        (approve-policy session policy-id))
      (setf records
            (mapcar (lambda (entry)
                      (if (eq (desktop-task-record-approval-status entry) :awaiting-approval)
                          (mark-desktop-task-record-approved session entry)
                          entry))
                    records))
      (let* ((all-editor-p
               (every (lambda (entry)
                        (eq (desktop-task-record-target entry) :editor))
                      records))
             (pending-action-id
               (and all-editor-p
                    (= (length records) 1)
                    (desktop-task-record-pending-action-id (first records))))
             (editor-apply-response
               (and pending-action-id
                    (command-desktop-task-apply-editor-authorization-service
                     session
                     pending-action-id
                     :session-id (desktop-task-record-session-id (first records))
                     :scope-id (desktop-task-record-receiver-scope (first records)))))
             (editor-apply-data (and editor-apply-response
                                     (service-response-data editor-apply-response)))
             (execution-results (or (and editor-apply-data
                                         (getf editor-apply-data :execution-results))
                                    (execute-turn-governed-desktop-task-records session
                                                                                records
                                                                                :thread thread
                                                                                :turn turn)))
             (reply-records (if turn-id
                                (desktop-task-records-for-turn session turn-id)
                                records))
             (result-task-results (or (and editor-apply-data
                                           (getf editor-apply-data :desktop-task-results))
                                      (mapcar #'desktop-task-record-canonical-result-summary
                                              reply-records)))
             (result-task-record-summaries (or (and editor-apply-data
                                                    (getf editor-apply-data :task-record-summaries))
                                               (mapcar #'desktop-task-record-summary
                                                       reply-records)))
             (assistant-message-text
               (or (and editor-apply-data
                        (getf editor-apply-data :assistant-message))
                   (some (lambda (entry)
                           (let ((result (getf entry :result)))
                             (and (listp result)
                                  (or (getf result :summary)
                                      (getf result :message)))))
                         execution-results)
                   (some (lambda (entry)
                           (let ((result (getf entry :result)))
                             (and (listp result)
                                  (getf result :summary))))
                         result-task-results)
                   "Approved and completed the requested action."))
             (result-summary assistant-message-text))
        (make-service-command-response
         :desktop-task
         :approve-actor-message
         (list :session-id (agent-session-id session)
               :actor-message-id actor-message-id
               :governance-actor (actor-address-summary (make-governance-actor-address
                                                         :session-id (agent-session-id session)))
               :turn-id turn-id
               :record-ids (mapcar #'desktop-task-record-id reply-records)
               :approval-ids (remove-duplicates
                              (remove nil (mapcar #'desktop-task-record-approval-id reply-records))
                              :test #'string=)
               :receiver-roles (remove-duplicates
                                (remove nil
                                        (mapcar (lambda (entry)
                                                  (desktop-task-actor-role-for-record entry
                                                                                      :direction :receiver))
                                                reply-records))
                                :test #'eq)
               :policy-ids policy-ids
               :thread thread
               :turn turn
               :assistant-message assistant-message-text
               :summary result-summary
               :desktop-task-results result-task-results
               :task-record-summaries result-task-record-summaries
               :replies (mapcar #'desktop-task-actor-reply-summary reply-records)
               :execution-results execution-results
               :result (list :summary result-summary
                             :desktop-task-results result-task-results
                             :task-record-summaries result-task-record-summaries
                             :execution-results execution-results))
         :metadata (make-service-metadata :authority :environment
                                          :command-model :desktop-task-approve-actor-message-v1
                                          :session session
                                          :thread-id thread-id
                                          :turn-id turn-id))))))

(defun command-desktop-task-approve-approval-service (session provider approval-id
                                                      &key session-id
                                                        (source :say)
                                                        (operator-mode :conversation))
  (let* ((governance-entry
           (or (find-actor-mailbox-entry session
                                         :governance-inbox
                                         :session-id session-id
                                         :approval-id approval-id)
               (and session-id
                    (find-actor-mailbox-entry session
                                              :governance-inbox
                                              :approval-id approval-id))))
         (record
           (or (and governance-entry
                    (let ((entry-actor-message-id
                            (actor-mailbox-entry-actor-message-id governance-entry)))
                      (and entry-actor-message-id
                           (find-desktop-task-record-by-actor-message-id session
                                                                         entry-actor-message-id))))
               (first (governance-approval-records session
                                                   :session-id session-id
                                                   :approval-id approval-id
                                                   :status :awaiting-approval))
               (and session-id
                    (first (governance-approval-records session
                                                        :approval-id approval-id
                                                        :status :awaiting-approval))))))
    (unless record
      (error "Unknown awaiting approval ~A for session ~A."
             approval-id
             (or session-id :any)))
    (let ((actor-message (desktop-task-record-actor-message record)))
      (unless actor-message
        (error "Approval ~A does not have an actor message." approval-id))
      (command-desktop-task-approve-actor-message-service
       session
       provider
       (actor-message-id actor-message)
       :source source
       :operator-mode operator-mode))))

(defun query-desktop-task-mcp-server-list-service (session)
  (declare (ignore session))
  (let ((environment (session-bound-environment session)))
    (make-service-query-response
     :desktop-task
     :mcp-server-list
     (mapcar #'mcp-server-config-summary
             (list-desktop-task-mcp-server-configs environment))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-mcp-server-list-v1
                                      :session session))))

(defun query-desktop-task-mcp-server-detail-service (session server-id)
  (let* ((environment (session-bound-environment session))
         (config (find-desktop-task-mcp-server-config server-id environment)))
    (unless config
      (error "Unknown MCP server config ~A" server-id))
    (make-service-query-response
     :desktop-task
     :mcp-server-detail
     (mcp-server-config-summary config)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-mcp-server-detail-v1
                                      :session session))))

(defun command-desktop-task-configure-mcp-server-service (session &key server-id name transport command arguments
                                                                   environment-variables working-directory endpoint
                                                                   capabilities retry-policy health-status
                                                                   enabled-p discoverable-p metadata)
  (let* ((environment (or (session-bound-environment session)
                          (error "No bound environment is available for MCP server configuration.")))
         (config (register-desktop-task-mcp-server-config
                  :server-id server-id
                  :name name
                  :transport transport
                  :command command
                  :arguments arguments
                  :environment-variables environment-variables
                  :working-directory working-directory
                  :endpoint endpoint
                  :capabilities capabilities
                  :retry-policy retry-policy
                  :health-status health-status
                  :enabled-p (if (null enabled-p) t enabled-p)
                  :discoverable-p (if (null discoverable-p) t discoverable-p)
                  :metadata metadata
                  :environment environment)))
    (append-session-event session
                          :desktop-task-mcp-server-configured
                          (mcp-server-config-summary config)
                          :family :governance
                          :metadata (list :server-id (mcp-server-config-id config)))
    (make-service-command-response
     :desktop-task
     :configure-mcp-server
     (mcp-server-config-summary config)
     :metadata (make-service-metadata :authority :environment
                                      :session session
                                      :read-model :desktop-task-mcp-server-detail-v1))))

(defun command-desktop-task-remove-mcp-server-service (session server-id)
  (let* ((environment (or (session-bound-environment session)
                          (error "No bound environment is available for MCP server removal.")))
         (config (remove-desktop-task-mcp-server-config server-id environment)))
    (append-session-event session
                          :desktop-task-mcp-server-removed
                          (list :id (mcp-server-config-id config)
                                :name (mcp-server-config-name config))
                          :family :governance
                          :metadata (list :server-id (mcp-server-config-id config)))
    (make-service-command-response
     :desktop-task
     :remove-mcp-server
     (list :id (mcp-server-config-id config)
           :removed-p t)
     :metadata (make-service-metadata :authority :environment
                                      :session session
                                      :read-model :desktop-task-mcp-server-list-v1))))
