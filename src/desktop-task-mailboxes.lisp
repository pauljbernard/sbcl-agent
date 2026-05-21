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
     (:supervision-escalation-inbox
      '(:queued :dequeued :resolved))
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
             :capabilities (copy-list (or (actor-definition-capabilities definition) '()))
             :provenance :actor-registry))
     (list :mailbox-direction (if (eq role :context-chat) :outbox :inbox)
           :projection-kind :desktop-task-mailbox-summary
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
                                   :supervision-escalation-inbox
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
