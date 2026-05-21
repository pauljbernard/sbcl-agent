(in-package #:sbcl-agent)

(defun actorize-desktop-task-command-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (keyword-plist-p data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun actorize-desktop-task-query-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (keyword-plist-p data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun command-desktop-task-actor-system-panel-service (session &key session-id)
  (call-with-desktop-task-admin-actor
   session
   (make-desktop-task-admin-request session
                                    :actor-system-panel
                                    :desktop-task/actor-system-panel
                                    :payload (list :session-id session-id)
                                    :metadata (list :session-id session-id))
   (lambda ()
     (query-desktop-task-actor-system-panel-service session :session-id session-id))
   :desktop-task/actor-system-panel
   :actor-system-panel
   :metadata (list :session-id session-id)))

(defun command-desktop-task-runtime-state-service (session
                                                   &key session-id package-name symbol-name)
  (call-with-desktop-task-admin-actor
   session
   (make-desktop-task-admin-request session
                                    :runtime-state
                                    :desktop-task/runtime-state
                                    :payload (list :session-id session-id
                                                   :package-name package-name
                                                   :symbol-name symbol-name)
                                    :metadata (list :session-id session-id
                                                    :package-name package-name
                                                    :symbol-name symbol-name))
   (lambda ()
     (query-desktop-task-runtime-state-service session
                                               :session-id session-id
                                               :package-name package-name
                                               :symbol-name symbol-name))
   :desktop-task/runtime-state
   :runtime-state
   :metadata (list :session-id session-id
                   :package-name package-name
                   :symbol-name symbol-name)))

(defun command-desktop-task-supervision-incidents-service (session
                                                           &key actor-id parent-actor-id mailbox
                                                             mailbox-entry-id session-id
                                                             open-only-p latest-only-p)
  (call-with-desktop-task-admin-actor
   session
   (make-desktop-task-admin-request session
                                    :supervision-incidents
                                    :desktop-task/supervision-incidents
                                    :payload (list :actor-id actor-id
                                                   :parent-actor-id parent-actor-id
                                                   :mailbox mailbox
                                                   :mailbox-entry-id mailbox-entry-id
                                                   :session-id session-id
                                                   :open-only-p open-only-p
                                                   :latest-only-p latest-only-p)
                                    :metadata (list :session-id session-id
                                                    :actor-id actor-id
                                                    :mailbox mailbox))
   (lambda ()
     (query-desktop-task-supervision-incidents-service
      session
      :actor-id actor-id
      :parent-actor-id parent-actor-id
      :mailbox mailbox
      :mailbox-entry-id mailbox-entry-id
      :session-id session-id
      :latest-only-p latest-only-p))
   :desktop-task/supervision-incidents
   :supervision-incidents
   :metadata (list :session-id session-id
                   :actor-id actor-id
                   :mailbox mailbox)))

(defun command-desktop-task-supervision-escalation-inbox-service (session
                                                                  &key session-id actor-id
                                                                    parent-actor-id mailbox-entry-id
                                                                    latest-only-p)
  (call-with-desktop-task-admin-query-actor
   session
   (make-desktop-task-admin-request session
                                    :supervision-escalation-inbox
                                    :desktop-task/supervision-escalation-inbox
                                    :payload (list :session-id session-id
                                                   :actor-id actor-id
                                                   :parent-actor-id parent-actor-id
                                                   :mailbox-entry-id mailbox-entry-id
                                                   :latest-only-p latest-only-p)
                                    :metadata (list :session-id session-id
                                                    :actor-id actor-id
                                                    :parent-actor-id parent-actor-id
                                                    :mailbox-entry-id mailbox-entry-id))
   (lambda ()
     (query-desktop-task-supervision-escalation-inbox-service
      session
      :session-id session-id
      :actor-id actor-id
      :parent-actor-id parent-actor-id
      :mailbox-entry-id mailbox-entry-id
      :latest-only-p latest-only-p))
   :desktop-task/supervision-escalation-inbox
   :supervision-escalation-inbox
   :metadata (list :session-id session-id
                   :actor-id actor-id
                   :parent-actor-id parent-actor-id
                   :mailbox-entry-id mailbox-entry-id)))

(defun command-desktop-task-ack-supervision-escalation-admin-service (session mailbox-entry-id
                                                                      &key session-id actor-message-id)
  (call-with-desktop-task-admin-actor
   session
   (make-desktop-task-admin-request session
                                    :ack-supervision-escalation
                                    :desktop-task/ack-supervision-escalation
                                    :payload (list :mailbox-entry-id mailbox-entry-id
                                                   :session-id session-id
                                                   :actor-message-id actor-message-id)
                                    :metadata (list :mailbox-entry-id mailbox-entry-id
                                                    :session-id session-id
                                                    :actor-message-id actor-message-id))
   (lambda ()
     (command-desktop-task-ack-supervision-escalation-service
      session
      mailbox-entry-id
      :session-id session-id
      :actor-message-id actor-message-id))
   :desktop-task/ack-supervision-escalation
   :ack-supervision-escalation
   :metadata (list :mailbox-entry-id mailbox-entry-id
                   :session-id session-id
                   :actor-message-id actor-message-id)))

(defun command-desktop-task-apply-supervision-escalation-admin-service (session mailbox-entry-id
                                                                        &key session-id actor-message-id
                                                                          (action :recommended)
                                                                          note)
  (call-with-desktop-task-admin-actor
   session
   (make-desktop-task-admin-request session
                                    :apply-supervision-escalation
                                    :desktop-task/apply-supervision-escalation
                                    :payload (list :mailbox-entry-id mailbox-entry-id
                                                   :session-id session-id
                                                   :actor-message-id actor-message-id
                                                   :action action
                                                   :note note)
                                    :metadata (list :mailbox-entry-id mailbox-entry-id
                                                    :session-id session-id
                                                    :actor-message-id actor-message-id
                                                    :action action))
   (lambda ()
     (command-desktop-task-apply-supervision-escalation-service
      session
      mailbox-entry-id
      :session-id session-id
      :actor-message-id actor-message-id
      :action action
      :note note))
   :desktop-task/apply-supervision-escalation
   :apply-supervision-escalation
   :metadata (list :mailbox-entry-id mailbox-entry-id
                   :session-id session-id
                   :actor-message-id actor-message-id
                   :action action)))

(defun command-desktop-task-process-supervision-escalation-admin-service (session
                                                                          &key session-id actor-id
                                                                            parent-actor-id
                                                                            (action :recommended)
                                                                            note
                                                                            async-p)
  (let* ((request
           (make-desktop-task-admin-request session
                                            :process-supervision-escalation
                                            :desktop-task/process-supervision-escalation
                                            :payload (list :session-id session-id
                                                           :actor-id actor-id
                                                           :parent-actor-id parent-actor-id
                                                           :action action
                                                           :note note)
                                            :receiver-actor-id (and async-p
                                                                    parent-actor-id)
                                            :metadata (list :session-id session-id
                                                            :actor-id actor-id
                                                            :parent-actor-id parent-actor-id
                                                            :action action)))
         (thunk
           (lambda ()
             (command-desktop-task-process-supervision-escalation-service
              session
              :session-id session-id
              :actor-id actor-id
              :parent-actor-id parent-actor-id
              :action action
              :note note)))
         (metadata (list :session-id session-id
                         :actor-id actor-id
                         :parent-actor-id parent-actor-id
                         :action action)))
    (if async-p
        (if (and parent-actor-id
                 (fboundp 'enqueue-routed-supervision-escalation-processing))
            (let* ((dispatch
                     (enqueue-routed-supervision-escalation-processing
                      session
                      parent-actor-id
                      session-id
                      :actor-id actor-id
                      :action action
                      :note note
                      :metadata '(:dispatch-origin :desktop-task-admin-surface)))
                   (mode (and (listp dispatch)
                              (getf dispatch :mode))))
              (case mode
                (:queued
                 (let* ((job (getf dispatch :job))
                        (job-id (and job (actor-execution-job-id job))))
                   (make-queued-desktop-task-admin-response
                    session
                    :process-supervision-escalation
                    :desktop-task/process-supervision-escalation
                    metadata
                    job-id)))
                (:inline
                 (let ((*current-session* session)
                       (*current-environment* (session-bound-environment session)))
                   (funcall (getf dispatch :thunk))))
                (otherwise
                 (call-with-desktop-task-admin-actor-async
                  session
                  request
                  thunk
                  :desktop-task/process-supervision-escalation
                  :process-supervision-escalation
                  :metadata metadata))))
            (call-with-desktop-task-admin-actor-async
             session
             request
             thunk
             :desktop-task/process-supervision-escalation
             :process-supervision-escalation
             :metadata metadata))
        (call-with-desktop-task-admin-actor
         session
         request
         thunk
         :desktop-task/process-supervision-escalation
         :process-supervision-escalation
         :metadata metadata))))

(defun command-desktop-task-actor-trace-service (session
                                                 &key actor-message-id actor-role phase
                                                   latest-only-p dead-letters-only-p)
  (call-with-desktop-task-admin-actor
   session
   (make-desktop-task-admin-request session
                                    :actor-trace
                                    :desktop-task/actor-trace
                                    :payload (list :actor-message-id actor-message-id
                                                   :actor-role actor-role
                                                   :phase phase
                                                   :latest-only-p latest-only-p
                                                   :dead-letters-only-p dead-letters-only-p)
                                    :metadata (list :actor-message-id actor-message-id
                                                    :actor-role actor-role
                                                    :phase phase))
   (lambda ()
     (query-desktop-task-actor-trace-service
      session
      :actor-message-id actor-message-id
      :actor-role actor-role
      :phase phase
      :latest-only-p latest-only-p
      :dead-letters-only-p dead-letters-only-p))
   :desktop-task/actor-trace
   :actor-trace
   :metadata (list :actor-message-id actor-message-id
                   :actor-role actor-role
                   :phase phase)))

(defun command-desktop-task-dead-letter-queue-service (session &key actor-role)
  (call-with-desktop-task-admin-actor
   session
   (make-desktop-task-admin-request session
                                    :dead-letter-queue
                                    :desktop-task/dlq
                                    :payload (list :actor-role actor-role)
                                    :metadata (list :actor-role actor-role))
   (lambda ()
     (query-desktop-task-dead-letter-queue-service session :actor-role actor-role))
   :desktop-task/dlq
   :dead-letter-queue
   :metadata (list :actor-role actor-role)))

(defun desktop-task-admin-target-actor-address (session actor-id)
  (or (and actor-id
           (fboundp 'actor-registry-definition-by-id)
           (let ((definition (actor-registry-definition-by-id session actor-id)))
             (and definition
                  (make-actor-address
                   :id (actor-definition-id definition)
                   :kind :internal
                   :role (actor-definition-role definition)
                   :display-name (actor-definition-display-name definition)
                   :metadata (copy-tree (or (actor-definition-metadata definition) '()))))))
      (make-standard-actor-address :desktop-task-admin
                                   :scope (agent-session-id session))))

(defun make-desktop-task-admin-request (session action capability
                                        &key payload metadata receiver-actor-id)
  (let ((request
          (make-governed-desktop-task-request
           :requester :context-chat
           :target :desktop-task-admin
           :operation action
           :capability capability
           :payload payload
           :metadata (append (list :session-id (agent-session-id session)
                                   :actor-slice :desktop-task-admin-v1)
                             metadata))))
    (when receiver-actor-id
      (let ((message (desktop-task-request-actor-message request)))
        (when message
          (setf (actor-message-receiver message)
                (desktop-task-admin-target-actor-address session receiver-actor-id)))))
    request))

(defun make-desktop-task-admin-actor-context (session request capability action metadata)
  (let ((actor-address
          (or (and (desktop-task-request-actor-message request)
                   (actor-message-receiver
                    (desktop-task-request-actor-message request)))
              (make-standard-actor-address :desktop-task-admin
                                           :scope (agent-session-id session)))))
    (make-actor-execution-context
     :actor-id (actor-address-id actor-address)
     :capability capability
     :authority :environment
     :target :desktop-task-admin
     :operation action
     :request-id (desktop-task-request-id request)
     :metadata metadata)))

(defun make-queued-desktop-task-admin-response (session action capability metadata job-id)
  (actorize-desktop-task-command-response
   (make-service-command-response
    :desktop-task
    action
    (list :status :queued
          :queued-p t
          :actor-execution-job-id job-id)
    :metadata (append (make-service-metadata :authority :environment
                                             :command-model :desktop-task-admin-command-v1
                                             :session session
                                             :policy-id capability)
                      metadata))
   :actor-execution-job-id job-id))

(defun call-with-desktop-task-admin-actor (session request thunk capability action &key metadata)
  (call-with-actor-worker-for-request
   session
   request
   (lambda ()
     (actorize-desktop-task-command-response
      (funcall thunk)
      :actor-execution-job-id (current-actor-execution-job-id)))
   :context (make-desktop-task-admin-actor-context
             session request capability action metadata)))

(defun call-with-desktop-task-admin-actor-async (session request thunk capability action
                                                         &key metadata)
  (let* ((dispatch
           (call-with-actor-worker-for-request-async
            session
            request
            (lambda ()
              (actorize-desktop-task-command-response
               (funcall thunk)
               :actor-execution-job-id (current-actor-execution-job-id)))
            :context (make-desktop-task-admin-actor-context
                      session request capability action metadata)))
         (mode (getf dispatch :mode)))
    (case mode
      (:queued
       (let* ((job (getf dispatch :job))
              (job-id (and job (actor-execution-job-id job))))
         (make-queued-desktop-task-admin-response session action capability metadata job-id)))
      (:inline
       (let ((*current-session* session)
             (*current-environment* (session-bound-environment session)))
         (funcall (getf dispatch :thunk))))
      (otherwise
       (error "Unknown desktop-task admin actor execution mode ~S." mode)))))

(defun call-with-desktop-task-admin-query-actor (session request thunk capability action &key metadata)
  (call-with-actor-worker-for-request
   session
   request
   (lambda ()
     (actorize-desktop-task-query-response
      (funcall thunk)
      :actor-execution-job-id (current-actor-execution-job-id)))
   :context (make-desktop-task-admin-actor-context
             session request capability action metadata)))

(defun command-desktop-task-manifest-list-query-service (session)
  (call-with-desktop-task-admin-query-actor
   session
   (make-desktop-task-admin-request session
                                    :manifest-list
                                    :desktop-task/manifests)
   (lambda ()
     (query-desktop-task-manifest-list-service session))
   :desktop-task/manifests
   :manifest-list))

(defun command-desktop-task-record-list-query-service (session &key thread-id status approval-status)
  (call-with-desktop-task-admin-query-actor
   session
   (make-desktop-task-admin-request session
                                    :record-list
                                    :desktop-task/records
                                    :payload (list :thread-id thread-id
                                                   :status status
                                                   :approval-status approval-status)
                                    :metadata (list :thread-id thread-id
                                                    :status status
                                                    :approval-status approval-status))
   (lambda ()
     (query-desktop-task-record-list-service session
                                             :thread-id thread-id
                                             :status status
                                             :approval-status approval-status))
   :desktop-task/records
   :record-list
   :metadata (list :thread-id thread-id
                   :status status
                   :approval-status approval-status)))

(defun command-desktop-task-pending-approval-query-service (session)
  (call-with-desktop-task-admin-query-actor
   session
   (make-desktop-task-admin-request session
                                    :pending-approval
                                    :desktop-task/pending-approval)
   (lambda ()
     (query-desktop-task-pending-approval-service session))
   :desktop-task/pending-approval
   :pending-approval))

(defun command-desktop-task-actor-flow-query-service (session
                                                      &key session-id approval-id pending-action-id
                                                        actor-message-id scope-id latest-only-p)
  (call-with-desktop-task-admin-query-actor
   session
   (make-desktop-task-admin-request session
                                    :actor-flow
                                    :desktop-task/actor-flow
                                    :payload (list :session-id session-id
                                                   :approval-id approval-id
                                                   :pending-action-id pending-action-id
                                                   :actor-message-id actor-message-id
                                                   :scope-id scope-id
                                                   :latest-only-p latest-only-p)
                                    :metadata (list :session-id session-id
                                                    :approval-id approval-id
                                                    :pending-action-id pending-action-id
                                                    :actor-message-id actor-message-id
                                                    :scope-id scope-id))
   (lambda ()
     (query-desktop-task-actor-flow-service session
                                            :session-id session-id
                                            :approval-id approval-id
                                            :pending-action-id pending-action-id
                                            :actor-message-id actor-message-id
                                            :scope-id scope-id
                                            :latest-only-p latest-only-p))
   :desktop-task/actor-flow
   :actor-flow
   :metadata (list :session-id session-id
                   :approval-id approval-id
                   :pending-action-id pending-action-id
                   :actor-message-id actor-message-id
                   :scope-id scope-id)))

(defun command-desktop-task-mcp-server-list-query-service (session)
  (call-with-desktop-task-admin-query-actor
   session
   (make-desktop-task-admin-request session
                                    :mcp-server-list
                                    :desktop-task/mcp-servers)
   (lambda ()
     (query-desktop-task-mcp-server-list-service session))
   :desktop-task/mcp-servers
   :mcp-server-list))

(defun command-desktop-task-mcp-server-detail-query-service (session server-id)
  (call-with-desktop-task-admin-query-actor
   session
   (make-desktop-task-admin-request session
                                    :mcp-server-detail
                                    :desktop-task/mcp-server
                                    :payload (list :server-id server-id)
                                    :metadata (list :server-id server-id))
   (lambda ()
     (query-desktop-task-mcp-server-detail-service session server-id))
   :desktop-task/mcp-server
   :mcp-server-detail
   :metadata (list :server-id server-id)))

(defun perform-desktop-task-approve-actor-message-service (session provider actor-message-id
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
             (actor-execution-job-ids
               (remove-duplicates
                (remove nil
                        (mapcar (lambda (entry)
                                  (or (getf entry :actor-execution-job-id)
                                      (and (listp (getf entry :metadata))
                                           (getf (getf entry :metadata) :actor-execution-job-id))))
                                result-task-results))
                :test #'string=))
             (execution-ids
               (remove-duplicates
                (remove nil
                        (mapcar (lambda (entry)
                                  (or (getf entry :execution-id)
                                      (and (listp (getf entry :metadata))
                                           (getf (getf entry :metadata) :execution-id))))
                                result-task-results))
                :test #'string=))
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
               :actor-execution-job-ids actor-execution-job-ids
               :execution-ids execution-ids
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

(defun command-desktop-task-approve-actor-message-service (session provider actor-message-id
                                                            &key (source :say)
                                                              (operator-mode :conversation))
  (let* ((session-id (agent-session-id session))
         (actor-address (make-standard-actor-address :governance
                                                     :scope session-id))
         (request
           (make-governed-desktop-task-request
            :requester :context-chat
            :target :governance
            :operation :approve-actor-message
            :capability :approval
            :payload (list :actor-message-id actor-message-id
                           :source source
                           :operator-mode operator-mode)
            :metadata (list :session-id session-id
                            :approval-id actor-message-id
                            :actor-slice :governance-approval-control-v1))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-desktop-task-command-response
        (perform-desktop-task-approve-actor-message-service
         session
         provider
         actor-message-id
         :source source
         :operator-mode operator-mode)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability :approval
               :authority :governance
               :target :governance
               :operation :approve-actor-message
               :request-id (desktop-task-request-id request)))))

(defun perform-desktop-task-approve-approval-service (session provider approval-id
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
      (perform-desktop-task-approve-actor-message-service
       session
       provider
       (actor-message-id actor-message)
       :source source
       :operator-mode operator-mode))))

(defun command-desktop-task-approve-approval-service (session provider approval-id
                                                      &key session-id
                                                        (source :say)
                                                        (operator-mode :conversation))
  (let* ((effective-session-id (or session-id (agent-session-id session)))
         (actor-address (make-standard-actor-address :governance
                                                     :scope effective-session-id))
         (request
           (make-governed-desktop-task-request
            :requester :context-chat
            :target :governance
            :operation :approve-approval
            :capability :approval
            :payload (list :approval-id approval-id
                           :source source
                           :operator-mode operator-mode)
            :metadata (list :session-id effective-session-id
                            :approval-id approval-id
                            :actor-slice :governance-approval-control-v1))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-desktop-task-command-response
        (perform-desktop-task-approve-approval-service
         session
         provider
         approval-id
         :session-id effective-session-id
         :source source
         :operator-mode operator-mode)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability :approval
               :authority :governance
               :target :governance
               :operation :approve-approval
               :request-id (desktop-task-request-id request)))))

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

(defun perform-desktop-task-configure-mcp-server-service (session &key server-id name transport command arguments
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

(defun command-desktop-task-configure-mcp-server-service (session &key server-id name transport command arguments
                                                                   environment-variables working-directory endpoint
                                                                   capabilities retry-policy health-status
                                                                   enabled-p discoverable-p metadata)
  (call-with-desktop-task-admin-actor
   session
   (make-desktop-task-admin-request session
                                    :configure-mcp-server
                                    :desktop-task/configure-mcp-server
                                    :payload (list :server-id server-id
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
                                                   :enabled-p enabled-p
                                                   :discoverable-p discoverable-p
                                                   :metadata metadata)
                                    :metadata (list :server-id server-id
                                                    :name name))
   (lambda ()
     (perform-desktop-task-configure-mcp-server-service
      session
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
      :enabled-p enabled-p
      :discoverable-p discoverable-p
      :metadata metadata))
   :desktop-task/configure-mcp-server
   :configure-mcp-server
   :metadata (list :server-id server-id
                   :name name)))

(defun perform-desktop-task-remove-mcp-server-service (session server-id)
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

(defun command-desktop-task-remove-mcp-server-service (session server-id)
  (call-with-desktop-task-admin-actor
   session
   (make-desktop-task-admin-request session
                                    :remove-mcp-server
                                    :desktop-task/remove-mcp-server
                                    :payload (list :server-id server-id)
                                    :metadata (list :server-id server-id))
   (lambda ()
     (perform-desktop-task-remove-mcp-server-service session server-id))
   :desktop-task/remove-mcp-server
   :remove-mcp-server
   :metadata (list :server-id server-id)))
