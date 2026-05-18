(in-package #:sbcl-agent)

(defun actorize-conversation-command-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let ((metadata (copy-list (or (getf response :metadata) '())))
            (updated-data (and (listp (getf response :data))
                               (copy-tree (getf response :data)))))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when updated-data
          (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                (getf response :data) updated-data))
        response)
      response))

(defun make-conversation-thread-request (session action &key payload metadata)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :context-chat
   :operation action
   :capability :conversation
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :context-chat-thread-control-v1)
                     metadata)))

(defun call-with-conversation-actor (session request thunk action &key metadata (capability :conversation))
  (let ((actor-address (make-standard-actor-address :context-chat
                                                    :scope (agent-session-id session))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-conversation-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :environment
               :target :context-chat
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata metadata))))

(defun append-conversation-service-debug-log (stage &rest fields)
  (ignore-errors
    (with-open-file (out #P"/private/tmp/sbcl-agent-conversation-execution-debug.log"
                         :direction :output
                         :if-exists :append
                         :if-does-not-exist :create)
      (format out "~&stage=~A" stage)
      (loop for (key value) on fields by #'cddr
            do (format out " ~A=~S" key value))
      (terpri out))))

(defun turn-latency-events (session &optional turn-id)
  (let ((resolved-turn-id (or turn-id
                              (let ((turn (current-turn session)))
                                (and turn (turn-id turn))))))
    (remove-if-not (lambda (event)
                     (and (eq (event-kind event) :conversation-latency)
                          (or (null resolved-turn-id)
                              (string= (or (event-turn-id event) "")
                                       resolved-turn-id))))
                   (agent-session-events session))))

(defun conversation-latency-summary-data (session &optional turn-id)
  (let* ((events (turn-latency-events session turn-id))
         (ordered-events (reverse events))
         (latest-by-kind '()))
    (dolist (event ordered-events)
      (let ((kind (getf (event-metadata event) :kind)))
        (when (and kind
                   (not (getf latest-by-kind kind)))
          (setf (getf latest-by-kind kind) (event-payload event)))))
    (list :turn-id (or turn-id
                       (let ((turn (current-turn session)))
                         (and turn (turn-id turn))))
          :sample-count (length ordered-events)
          :samples (mapcar (lambda (event)
                             (list :kind (getf (event-metadata event) :kind)
                                   :timestamp (event-timestamp event)
                                   :payload (event-payload event)))
                           ordered-events)
          :request-built (getf latest-by-kind :request-built)
          :first-stream (getf latest-by-kind :first-stream)
          :response-complete (getf latest-by-kind :response-complete)
          :provider-phases
          (remove nil
                  (mapcar (lambda (event)
                            (when (eq (getf (event-metadata event) :kind) :provider-phase)
                              (append (list :timestamp (event-timestamp event))
                                      (event-payload event))))
                          ordered-events)))))

(defun query-conversation-thread-list-service (session)
  (make-service-query-response :conversation
                               :thread-list
                               (list-thread-summaries session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :thread-list-v1
                                                                :session session)))

(defun command-conversation-thread-list-query-service (session)
  (call-with-conversation-actor
   session
   (make-conversation-thread-request session
                                     :thread-list-query
                                     :payload '())
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read conversation thread list."
                                    "conversation/thread-list"
                                    :authority :conversation
                                    :payload '()))
   :thread-list-query
   :capability :conversation/thread-list))

(defun perform-conversation-create-thread-service (session &key title summary metadata)
  (make-service-command-response :conversation
                                 :create-thread
                                 (thread-record-summary
                                  (create-thread session
                                                 :title title
                                                 :summary summary
                                                 :metadata metadata))
                                 :metadata (make-service-metadata :authority :environment
                                                                 :command-model :thread-command-v1
                                                                 :session session)))

(defun command-conversation-create-thread-service (session &key title summary metadata)
  (call-with-conversation-actor
   session
   (make-conversation-thread-request session
                                     :create-thread
                                     :payload (list :title title
                                                    :summary summary
                                                    :metadata metadata)
                                     :metadata (list :title title))
   (lambda ()
     (command-kernel-invoke-service session
                                    (or title "Create a conversation thread.")
                                    "conversation/create-thread"
                                    :authority :conversation
                                    :payload (list :title title
                                                   :summary summary
                                                   :metadata metadata)
                                    :context (list :thread-id (and (current-thread session)
                                                                   (thread-id (current-thread session))))))
   :create-thread
   :metadata (list :title title)))

(defun perform-conversation-update-thread-service (session thread-id &key title summary metadata)
  (make-service-command-response :conversation
                                 :update-thread
                                 (thread-record-summary
                                  (update-thread session
                                                 thread-id
                                                 :title title
                                                 :summary summary
                                                 :metadata metadata))
                                  :metadata (make-service-metadata :authority :environment
                                                                  :command-model :thread-command-v1
                                                                  :session session
                                                                  :thread-id thread-id)))

(defun command-conversation-update-thread-service (session thread-id &key title summary metadata)
  (call-with-conversation-actor
   session
   (make-conversation-thread-request session
                                     :update-thread
                                     :payload (list :thread-id thread-id
                                                    :title title
                                                    :summary summary
                                                    :metadata metadata)
                                     :metadata (list :thread-id thread-id))
   (lambda ()
     (command-kernel-invoke-service session
                                    (or title "Update a conversation thread.")
                                    "conversation/update-thread"
                                    :authority :conversation
                                    :payload (list :thread-id thread-id
                                                   :title title
                                                   :summary summary
                                                   :metadata metadata)
                                    :context (list :thread-id thread-id))
     )
   :update-thread
   :metadata (list :thread-id thread-id)))

(defun perform-conversation-use-thread-service (session thread-id)
  (append-conversation-service-debug-log
   :use-thread-before
   :thread-id thread-id
   :existing-thread-p (not (null (find-thread session thread-id))))
  (make-service-command-response :conversation
                                 :use-thread
                                 (thread-record-summary (use-thread session thread-id))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :thread-command-v1
                                                                  :session session
                                                                  :thread-id thread-id)))

(defun command-conversation-use-thread-service (session thread-id)
  (call-with-conversation-actor
   session
   (make-conversation-thread-request session
                                     :use-thread
                                     :payload (list :thread-id thread-id)
                                     :metadata (list :thread-id thread-id))
   (lambda ()
     (command-kernel-invoke-service session
                                    "Use a conversation thread."
                                    "conversation/use-thread"
                                    :authority :conversation
                                    :payload (list :thread-id thread-id)
                                    :context (list :thread-id thread-id)))
   :use-thread
   :metadata (list :thread-id thread-id)))

(defun query-conversation-thread-detail-service (session &optional thread-id)
  (make-service-query-response :conversation
                               :thread-detail
                               (thread-detail session thread-id)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :thread-detail-v1
                                                                :session session
                                                                :thread-id thread-id)))

(defun command-conversation-thread-detail-query-service (session &optional thread-id)
  (call-with-conversation-actor
   session
   (make-conversation-thread-request session
                                     :thread-detail-query
                                     :payload (list :thread-id thread-id)
                                     :metadata (list :thread-id thread-id))
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read conversation thread detail."
                                    "conversation/thread-detail"
                                    :authority :conversation
                                    :payload (list :thread-id thread-id)
                                    :context (list :thread-id thread-id)))
   :thread-detail-query
   :metadata (list :thread-id thread-id)
   :capability :conversation/thread-detail))

(defun query-conversation-turn-detail-service (session &optional turn-id)
  (let* ((detail (turn-detail session turn-id))
         (surface (compact-execution-surface-summary
                   (primary-execution-surface-summary session
                                                     (getf detail :execution-handles)))))
    (make-service-query-response :conversation
                                 :turn-detail
                                 (append detail
                                         (list :execution-surface surface))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :turn-detail-v1
                                                                  :session session
                                                                  :turn-id turn-id))))

(defun command-conversation-turn-detail-query-service (session &optional turn-id)
  (call-with-conversation-actor
   session
   (make-conversation-thread-request session
                                     :turn-detail-query
                                     :payload (list :turn-id turn-id)
                                     :metadata (list :turn-id turn-id))
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read conversation turn detail."
                                    "conversation/turn-detail"
                                    :authority :conversation
                                    :payload (list :turn-id turn-id)
                                    :context (list :turn-id turn-id)))
   :turn-detail-query
   :metadata (list :turn-id turn-id)
   :capability :conversation/turn-detail))

(defun query-conversation-latency-service (session &optional turn-id)
  (make-service-query-response :conversation
                               :latency
                               (conversation-latency-summary-data session turn-id)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :conversation-latency-v1
                                                                :session session
                                                                :turn-id turn-id)))

(defun command-conversation-latency-query-service (session &optional turn-id)
  (call-with-conversation-actor
   session
   (make-conversation-thread-request session
                                     :latency-query
                                     :payload (list :turn-id turn-id)
                                     :metadata (list :turn-id turn-id))
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read conversation latency telemetry."
                                    "conversation/latency"
                                    :authority :conversation
                                    :payload (list :turn-id turn-id)
                                    :context (list :turn-id turn-id)))
   :latency-query
   :metadata (list :turn-id turn-id)
   :capability :conversation/latency))
