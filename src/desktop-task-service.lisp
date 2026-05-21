(in-package #:sbcl-agent)

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

(defun command-desktop-task-invoke-service (session
                                            &key request
                                              requester
                                              target
                                              operation
                                              payload
                                              capability
                                              surface-context
                                              surface-actions
                                              metadata
                                              actor-message
                                              manifest
                                              resolution
                                              (register-record-p t)
                                              (async-p nil)
                                              retry-reason
                                              thread-id
                                              turn-id
                                              conversation-operation-id)
  (let* ((effective-request
           (or request
               (make-governed-desktop-task-request
                :requester (or requester :kernel)
                :target target
                :operation operation
                :payload payload
                :capability capability
                :surface-context surface-context
                :surface-actions surface-actions
                :metadata metadata
                :actor-message actor-message)))
         (effective-manifest
           (or manifest
               (desktop-task-manifest-for-request effective-request)))
         (prepared-request
           (ensure-governed-desktop-task-request-state
            effective-request
            :session-id (agent-session-id session)
            :manifest effective-manifest))
         (existing-record
           (find-desktop-task-record-by-request-id
            session
            (desktop-task-request-id prepared-request)))
         (prepared-execution
           (prepare-governed-desktop-task-execution
            prepared-request
            session
            :manifest effective-manifest
            :resolution (or resolution
                            (resolve-governed-desktop-task-request prepared-request session))))
         (task-record
           (or existing-record
               (and register-record-p
                    (register-desktop-task-record
                     session
                     (make-desktop-task-record-for-request
                      prepared-request
                      effective-manifest
                      :session-id (agent-session-id session)
                      :thread-id thread-id
                      :turn-id turn-id
                      :conversation-operation-id conversation-operation-id)))))
         (effective-resolution (getf prepared-execution :resolution))
         (policy-id (getf prepared-execution :policy-id))
         (approval-required-p (getf prepared-execution :approval-required-p))
         (approval-granted-p (getf prepared-execution :approval-granted-p))
         (record-metadata
           (append (when policy-id
                     (list :policy-id policy-id))
                   (list :request-summary
                         (desktop-task-request-summary prepared-request))))
         (_record-resolution
           (when task-record
             (update-desktop-task-record
              session
              task-record
              :resolution effective-resolution
              :metadata record-metadata)))
         (result-envelope
           (cond
             ((and task-record approval-required-p (not approval-granted-p))
              (mark-desktop-task-record-awaiting-approval session
                                                         task-record
                                                         :policy-id policy-id)
              (list :manifest effective-manifest
                    :resolution effective-resolution
                    :result (list :status :awaiting-approval
                                  :summary (desktop-task-resolution-summary
                                            effective-resolution))))
             ((and async-p task-record)
              (when approval-required-p
                (mark-desktop-task-record-approved session task-record))
              (let* ((dispatch-context
                       (getf prepared-execution :actor-execution-context))
                     (dispatch
                       (call-with-actor-worker-for-request-async
                        session
                        prepared-request
                        (lambda ()
                          (when task-record
                            (if (eq (desktop-task-record-status task-record) :retryable-failure)
                                (mark-desktop-task-record-retrying
                                 session
                                 task-record
                                 :reason (or retry-reason
                                             "Retrying governed desktop task through authoritative ingress."))
                                (mark-desktop-task-record-executing session task-record)))
                          (handler-case
                              (let ((envelope
                                      (invoke-governed-desktop-task-request
                                       prepared-request
                                       session
                                       :resolution effective-resolution
                                       :manifest effective-manifest)))
                                (when task-record
                                  (mark-desktop-task-record-completed
                                   session
                                   task-record
                                   (make-desktop-task-record-completed-result
                                    prepared-request
                                    (getf envelope :resolution)
                                    (getf envelope :result)))
                                  (when (fboundp 'reconcile-work-item-promotion-task-completion)
                                    (reconcile-work-item-promotion-task-completion
                                     session
                                     task-record
                                     (getf envelope :result))))
                                envelope)
                            (error (condition)
                              (when task-record
                                (mark-desktop-task-record-failed
                                 session
                                 task-record
                                 (list :summary "Desktop task invocation failed."
                                       :error (princ-to-string condition)
                                       :failure-classification :execution)
                                 :retryable-p (desktop-task-retryable-p task-record)))
                              (error condition))))
                        :context dispatch-context))
                     (job (getf dispatch :job))
                     (job-id (and job (actor-execution-job-id job))))
                (when (and task-record job-id)
                  (update-desktop-task-record
                   session
                   task-record
                   :metadata (list :actor-execution-job-id job-id)))
                (list :manifest effective-manifest
                      :resolution effective-resolution
                      :result (list :status :queued
                                    :summary (desktop-task-resolution-summary
                                              effective-resolution)
                                    :actor-execution-job-id job-id
                                    :queued-p t))))
             (t
              (when task-record
                (when approval-required-p
                  (mark-desktop-task-record-approved session task-record))
                (if (eq (desktop-task-record-status task-record) :retryable-failure)
                    (mark-desktop-task-record-retrying
                     session
                     task-record
                     :reason (or retry-reason
                                 "Retrying governed desktop task through authoritative ingress."))
                    (mark-desktop-task-record-executing session task-record)))
              (handler-case
                  (let ((envelope
                          (invoke-governed-desktop-task-request
                           prepared-request
                           session
                           :resolution effective-resolution
                           :manifest effective-manifest)))
                    (when task-record
                      (mark-desktop-task-record-completed
                       session
                       task-record
                       (make-desktop-task-record-completed-result
                        prepared-request
                        (getf envelope :resolution)
                        (getf envelope :result)))
                      (when (fboundp 'reconcile-work-item-promotion-task-completion)
                        (reconcile-work-item-promotion-task-completion
                         session
                         task-record
                         (getf envelope :result))))
                    envelope)
                (error (condition)
                  (when task-record
                    (mark-desktop-task-record-failed
                     session
                     task-record
                     (list :summary "Desktop task invocation failed."
                           :error (princ-to-string condition)
                           :failure-classification :execution)
                     :retryable-p (desktop-task-retryable-p task-record)))
                  (error condition))))))
         (actual-manifest (getf result-envelope :manifest))
         (actual-resolution (getf result-envelope :resolution))
         (result (getf result-envelope :result))
         (resolved-record
           (or (find-desktop-task-record-by-request-id
                session
                (desktop-task-request-id prepared-request))
               task-record))
         (request-metadata (desktop-task-request-metadata prepared-request))
         (resolved-record-metadata (and resolved-record
                                        (desktop-task-record-metadata resolved-record)))
         (actor-execution-job-id
           (or (and (listp resolved-record-metadata)
                    (getf resolved-record-metadata :actor-execution-job-id))
               (and (listp request-metadata)
                    (getf request-metadata :actor-execution-job-id))))
         (actor-execution-authority
           (or (and (listp resolved-record-metadata)
                    (getf resolved-record-metadata :actor-execution-authority))
               (and (listp request-metadata)
                    (getf request-metadata :actor-execution-authority))))
         (actor-execution-capability
           (or (and (listp resolved-record-metadata)
                    (getf resolved-record-metadata :actor-execution-capability))
               (and (listp request-metadata)
                    (getf request-metadata :actor-execution-capability)))))
    (make-service-command-response
     :desktop-task
     :invoke
     (list :request (desktop-task-request-summary prepared-request)
           :manifest (desktop-task-manifest-summary actual-manifest)
           :resolution (desktop-task-resolution-summary-data actual-resolution)
           :result result
           :task-record (and resolved-record
                             (desktop-task-record-summary-with-audit session
                                                                    resolved-record))
           :policy-id policy-id
           :approval-required-p approval-required-p
           :approval-granted-p approval-granted-p
           :governance-authority :actor-runtime
           :actor-execution-job-id actor-execution-job-id
           :actor-execution-authority actor-execution-authority
           :actor-execution-capability actor-execution-capability)
      :metadata (make-service-metadata :authority :environment
                                       :command-model :desktop-task-invoke-v1
                                       :session session
                                       :policy-id policy-id
                                       :governance-authority :actor-runtime
                                       :thread-id thread-id
                                       :turn-id turn-id
                                       :work-item-id (or (getf request-metadata :work-item-id)
                                                         (getf request-metadata :WORK-ITEM-ID))
                                       :workflow-record-id (or (getf request-metadata :workflow-record-id)
                                                               (getf request-metadata :WORKFLOW-RECORD-ID))))))

(defun command-desktop-task-runtime-eval-service (session form
                                                  &key package mutating requester metadata
                                                    register-record-p async-p thread-id turn-id
                                                    conversation-operation-id)
  (let* ((response
           (command-desktop-task-invoke-service
            session
            :requester (or requester :surface-runtime)
            :target :runtime
            :operation :evaluate-form
            :payload (append (list :form form)
                             (when mutating
                               (list :mutating t))
                             (when package
                               (list :package-name package
                                     :reason :surface-runtime-eval)))
            :capability (if mutating :runtime-eval-mutate :runtime-eval-safe)
            :metadata metadata
            :register-record-p register-record-p
            :async-p async-p
            :thread-id thread-id
            :turn-id turn-id
            :conversation-operation-id conversation-operation-id))
         (data (service-response-data response))
         (result (copy-list (or (getf data :result) '()))))
    (make-service-command-response
     :runtime
     :eval
     (append result
             (when (getf data :actor-execution-job-id)
               (list :actor-execution-job-id (getf data :actor-execution-job-id)))
             (when (getf data :actor-execution-authority)
               (list :actor-execution-authority (getf data :actor-execution-authority)))
             (when (getf data :actor-execution-capability)
               (list :actor-execution-capability (getf data :actor-execution-capability)))
             (when (getf data :task-record)
               (list :task-record (getf data :task-record))))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :runtime-command-v1
                                      :session session
                                      :runtime-id (default-runtime-id)
                                      :policy-id (if mutating
                                                     :runtime-eval-mutate
                                                     :runtime-eval-safe)))))

(defun command-desktop-task-runtime-reload-file-service (session path
                                                         &key requester metadata
                                                           register-record-p async-p thread-id turn-id
                                                           conversation-operation-id)
  (let* ((response
           (command-desktop-task-invoke-service
            session
            :requester (or requester :surface-runtime)
            :target :runtime
            :operation :reload-file
            :payload (list :path path)
            :metadata metadata
            :register-record-p register-record-p
            :async-p async-p
            :thread-id thread-id
            :turn-id turn-id
            :conversation-operation-id conversation-operation-id))
         (data (service-response-data response))
         (result (copy-list (or (getf data :result) '()))))
    (make-service-command-response
     :runtime
     :reload-file
     (append result
             (when (getf data :actor-execution-job-id)
               (list :actor-execution-job-id (getf data :actor-execution-job-id)))
             (when (getf data :actor-execution-authority)
               (list :actor-execution-authority (getf data :actor-execution-authority)))
             (when (getf data :actor-execution-capability)
               (list :actor-execution-capability (getf data :actor-execution-capability)))
             (when (getf data :task-record)
               (list :task-record (getf data :task-record))))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :runtime-command-v1
                                      :session session
                                      :runtime-id (default-runtime-id)
                                      :policy-id :runtime-reload))))

(defun command-desktop-task-runtime-set-package-service (session package-name
                                                         &key requester metadata
                                                           register-record-p async-p
                                                           thread-id turn-id
                                                           conversation-operation-id)
  (let* ((response
           (command-desktop-task-invoke-service
            session
            :requester (or requester :surface-runtime)
            :target :runtime
            :operation :set-package
            :payload (list :package package-name)
            :capability :runtime-package-switch
            :metadata metadata
            :register-record-p register-record-p
            :async-p async-p
            :thread-id thread-id
            :turn-id turn-id
            :conversation-operation-id conversation-operation-id))
         (data (service-response-data response))
         (result (copy-list (or (getf data :result) '()))))
    (make-service-command-response
     :runtime
     :set-package
     (append result
             (when (getf data :actor-execution-job-id)
               (list :actor-execution-job-id (getf data :actor-execution-job-id)))
             (when (getf data :actor-execution-authority)
               (list :actor-execution-authority (getf data :actor-execution-authority)))
             (when (getf data :actor-execution-capability)
               (list :actor-execution-capability (getf data :actor-execution-capability)))
             (when (getf data :task-record)
               (list :task-record (getf data :task-record))))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :runtime-command-v1
                                      :session session
                                      :runtime-id (default-runtime-id)
                                      :policy-id :runtime-package-switch))))

(defun command-desktop-task-platform-command-service (session operation payload
                                                      &key capability requester metadata
                                                        register-record-p async-p
                                                        thread-id turn-id
                                                        conversation-operation-id)
  (let* ((response
           (command-desktop-task-invoke-service
            session
            :requester (or requester :surface-platform)
            :target :platform
            :operation operation
            :payload payload
            :capability capability
            :metadata metadata
            :register-record-p register-record-p
            :async-p async-p
            :thread-id thread-id
            :turn-id turn-id
            :conversation-operation-id conversation-operation-id))
         (data (service-response-data response))
         (result (copy-list (or (getf data :result) '()))))
    (make-service-command-response
     :platform
     operation
     (append result
             (when (getf data :actor-execution-job-id)
               (list :actor-execution-job-id (getf data :actor-execution-job-id)))
             (when (getf data :actor-execution-authority)
               (list :actor-execution-authority (getf data :actor-execution-authority)))
             (when (getf data :actor-execution-capability)
               (list :actor-execution-capability (getf data :actor-execution-capability)))
             (when (getf data :task-record)
               (list :task-record (getf data :task-record))))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :platform-desktop-task-command-v1
                                      :session session
                                      :policy-id capability))))

(defun command-desktop-task-compatibility-launch-service (session app-id app-arguments
                                                          &key capability requester metadata
                                                            register-record-p async-p
                                                            thread-id turn-id
                                                            conversation-operation-id)
  (let* ((response
           (command-desktop-task-invoke-service
            session
            :requester (or requester :surface-compatibility)
            :target :compatibility
            :operation :launch-app
            :payload (list :app-id app-id
                           :app-arguments app-arguments)
            :capability capability
            :metadata metadata
            :register-record-p register-record-p
            :async-p async-p
            :thread-id thread-id
            :turn-id turn-id
            :conversation-operation-id conversation-operation-id))
         (data (service-response-data response))
         (result (copy-list (or (getf data :result) '()))))
    (make-service-command-response
     :compatibility
     :launch-app
     (append result
             (when (getf data :actor-execution-job-id)
               (list :actor-execution-job-id (getf data :actor-execution-job-id)))
             (when (getf data :actor-execution-authority)
               (list :actor-execution-authority (getf data :actor-execution-authority)))
             (when (getf data :actor-execution-capability)
               (list :actor-execution-capability (getf data :actor-execution-capability)))
             (when (getf data :task-record)
               (list :task-record (getf data :task-record))))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :compatibility-app-execution-v1
                                      :session session
                                      :policy-id capability))))

(defun command-desktop-task-apply-patch-service (session operations
                                                 &key requester metadata
                                                   register-record-p async-p thread-id turn-id
                                                   conversation-operation-id)
  (let* ((response
           (command-desktop-task-invoke-service
            session
            :requester (or requester :surface-source)
            :target :workspace
            :operation :apply-patch
            :payload (list :operations operations)
            :metadata metadata
            :register-record-p register-record-p
            :async-p async-p
            :thread-id thread-id
            :turn-id turn-id
            :conversation-operation-id conversation-operation-id))
         (data (service-response-data response))
         (result (copy-list (or (getf data :result) '()))))
    (make-service-command-response
     :workspace
     :patch
     (append result
             (when (getf data :actor-execution-job-id)
               (list :actor-execution-job-id (getf data :actor-execution-job-id)))
             (when (getf data :actor-execution-authority)
               (list :actor-execution-authority (getf data :actor-execution-authority)))
             (when (getf data :actor-execution-capability)
               (list :actor-execution-capability (getf data :actor-execution-capability)))
             (when (getf data :task-record)
               (list :task-record (getf data :task-record))))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :patch-execution-v1
                                      :session session
                                      :policy-id :workspace-write))))

(defun command-desktop-task-promote-patch-workspace-service (session payload
                                                             &key requester metadata
                                                               register-record-p async-p
                                                               thread-id turn-id
                                                               conversation-operation-id)
  (let* ((response
           (command-desktop-task-invoke-service
            session
            :requester (or requester :surface-source)
            :target :workspace
            :operation :promote-patch
            :payload payload
            :metadata metadata
            :register-record-p register-record-p
            :async-p async-p
            :thread-id thread-id
            :turn-id turn-id
            :conversation-operation-id conversation-operation-id))
         (data (service-response-data response))
         (result (copy-list (or (getf data :result) '()))))
    (make-service-command-response
     :workspace
     :promote-patch
     (append result
             (when (getf data :actor-execution-job-id)
               (list :actor-execution-job-id (getf data :actor-execution-job-id)))
             (when (getf data :actor-execution-authority)
               (list :actor-execution-authority (getf data :actor-execution-authority)))
             (when (getf data :actor-execution-capability)
               (list :actor-execution-capability (getf data :actor-execution-capability)))
             (when (getf data :task-record)
               (list :task-record (getf data :task-record))))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :patch-promotion-execution-v1
                                      :session session
                                      :policy-id :workspace-write))))

(defun command-desktop-task-stage-source-change-service (session path content
                                                         &key requester metadata
                                                           register-record-p thread-id turn-id
                                                           conversation-operation-id)
  (let* ((response
           (command-desktop-task-invoke-service
            session
            :requester (or requester :surface-source)
            :target :workspace
            :operation :apply-patch
            :payload (list :operations
                           (list (list :write path content)))
            :metadata metadata
            :register-record-p register-record-p
            :thread-id thread-id
            :turn-id turn-id
            :conversation-operation-id conversation-operation-id))
         (data (service-response-data response))
         (result (copy-list (or (getf data :result) '())))
         (patch (getf result :patch))
         (first-write (and (listp patch) (first patch))))
    (make-service-command-response
     :source
     :stage-change
     (append result
             (when first-write
               (list :path (getf first-write :path)
                     :bytes-written (getf first-write :bytes)
                     :artifact-ids '()))
             (unless first-write
               (list :artifact-ids '()))
             (when (getf data :actor-execution-job-id)
               (list :actor-execution-job-id (getf data :actor-execution-job-id)))
             (when (getf data :actor-execution-authority)
               (list :actor-execution-authority (getf data :actor-execution-authority)))
             (when (getf data :actor-execution-capability)
               (list :actor-execution-capability (getf data :actor-execution-capability)))
             (when (getf data :task-record)
               (list :task-record (getf data :task-record))))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :source-mutation-v1
                                      :session session
                                      :policy-id :workspace-write))))

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
         (supervision-escalation-inbox
           (copy-list (or (getf existing-mailboxes :supervision-escalation-inbox) '())))
         (pending-approval-entries
           (latest-pending-approval-mailbox-entries context-chat-approval-inbox))
         (mailboxes
           (list :context-chat-mailbox context-chat-mailbox
                 :context-chat-approval-inbox context-chat-approval-inbox
                 :governance-inbox governance-inbox
                 :governance-decision-outbox governance-decision-outbox
                 :runtime-inbox runtime-inbox
                 :runtime-outbox runtime-outbox
                 :supervision-escalation-inbox supervision-escalation-inbox
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

(defun query-desktop-task-supervision-escalation-inbox-service (session
                                                                &key session-id actor-id parent-actor-id
                                                                  mailbox-entry-id latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (entries
           (remove-if-not
            (lambda (entry)
              (and (or (null session-id)
                       (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                         (and entry-session-id
                              (string= session-id entry-session-id))))
                   (or (null mailbox-entry-id)
                       (string= mailbox-entry-id
                                (actor-mailbox-entry-id entry)))
                   (or (null actor-id)
                       (let ((entry-actor-id
                               (or (getf (actor-mailbox-entry-payload entry) :actor-id)
                                   (getf (actor-mailbox-entry-metadata entry) :actor-id))))
                         (and entry-actor-id
                              (string= actor-id entry-actor-id))))
                   (or (null parent-actor-id)
                       (let ((entry-parent-actor-id
                               (or (getf (actor-mailbox-entry-payload entry) :escalation-target)
                                   (getf (actor-mailbox-entry-metadata entry) :escalation-target))))
                         (and entry-parent-actor-id
                              (string= parent-actor-id entry-parent-actor-id))))))
            (copy-list (or (getf mailboxes :supervision-escalation-inbox) '()))))
         (selected (if latest-only-p
                       (if entries
                           (list (first entries))
                           '())
                       entries))
         (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected)))))
         (effective-parent-actor-id
           (or parent-actor-id
               (and selected
                    (or (getf (actor-mailbox-entry-payload (first selected)) :escalation-target)
                        (getf (actor-mailbox-entry-metadata (first selected)) :escalation-target)))))
         (messages
           (mapcar (lambda (entry)
                     (let* ((failed-mailbox-entry-id
                              (or (getf (actor-mailbox-entry-payload entry) :mailbox-entry-id)
                                  (getf (actor-mailbox-entry-metadata entry)
                                        :escalated-from-mailbox-entry-id)))
                            (incident
                              (and failed-mailbox-entry-id
                                   (fboundp 'find-actor-supervision-incident-for-mailbox-entry)
                                   (find-actor-supervision-incident-for-mailbox-entry
                                    session
                                    failed-mailbox-entry-id
                                    :session-id (actor-mailbox-entry-session-id entry)
                                    :actor-message-id (actor-mailbox-entry-actor-message-id entry)))))
                       (append (actor-mailbox-entry-summary entry)
                               (when incident
                                 (list :incident
                                       (actor-supervision-incident-summary session incident))))))
                   selected)))
    (make-service-query-response
     :desktop-task
     (if latest-only-p
         :supervision-escalation-inbox-latest
         :supervision-escalation-inbox)
     (list :session-id effective-session-id
           :parent-actor-id effective-parent-actor-id
           :mailbox :supervision-escalation-inbox
           :message-count (length selected)
           :messages messages)
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-supervision-escalation-inbox-latest-v2
                                                      :desktop-task-supervision-escalation-inbox-v2)
                                      :session session))))

(defun command-desktop-task-ack-supervision-escalation-service (session mailbox-entry-id
                                                                &key session-id actor-message-id)
  (let ((entry
          (update-session-actor-mailbox-entry
           session
           :supervision-escalation-inbox
           (lambda (current-entry)
             (and (string= mailbox-entry-id
                           (actor-mailbox-entry-id current-entry))
                  (or (null session-id)
                      (let ((entry-session-id (actor-mailbox-entry-session-id current-entry)))
                        (and entry-session-id
                             (string= session-id entry-session-id))))
                  (or (null actor-message-id)
                      (let ((entry-actor-message-id
                              (actor-mailbox-entry-actor-message-id current-entry)))
                        (and entry-actor-message-id
                             (string= actor-message-id entry-actor-message-id))))))
           (lambda (current-entry)
             (setf (actor-mailbox-entry-delivery-status current-entry) :resolved
                   (actor-mailbox-entry-acknowledged-at current-entry)
                   (or (actor-mailbox-entry-acknowledged-at current-entry)
                       (get-universal-time))
                   (actor-mailbox-entry-completed-at current-entry)
                   (or (actor-mailbox-entry-completed-at current-entry)
                       (get-universal-time)))
             current-entry)
           :reason :supervision-escalation-acknowledged)))
    (make-service-command-response
     :desktop-task
     :ack-supervision-escalation
     (actor-mailbox-entry-summary entry)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :desktop-task-ack-supervision-escalation-v1
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
         (context-chat-context
           (service-response-data
            (query-desktop-task-context-chat-context-service session)))
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
         (supervision-escalation-inbox
           (service-response-data
            (query-desktop-task-supervision-escalation-inbox-service
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
           :context-chat-context context-chat-context
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
           :supervision-escalation-inbox supervision-escalation-inbox
           :runtime-state runtime-state
           :editor-pending-mutations editor-pending-mutations
           :editor-authorizations editor-authorizations)
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-actor-flow-latest-v2
                                                      :desktop-task-actor-flow-v2)
                                      :session session))))

(defun query-desktop-task-dead-letter-queue-service (session &key actor-role)
  (query-desktop-task-actor-trace-service session
                                          :actor-role actor-role
                                          :dead-letters-only-p t))


;; Desktop-task admin actor/query orchestration lives in desktop-task-admin-surface.lisp.
