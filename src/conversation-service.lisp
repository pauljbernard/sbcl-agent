(in-package #:sbcl-agent)

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

(defun command-conversation-create-thread-service (session &key title summary metadata)
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

(defun command-conversation-update-thread-service (session thread-id &key title summary metadata)
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

(defun command-conversation-use-thread-service (session thread-id)
  (make-service-command-response :conversation
                                 :use-thread
                                 (thread-record-summary (use-thread session thread-id))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :thread-command-v1
                                                                  :session session
                                                                  :thread-id thread-id)))

(defun query-conversation-thread-detail-service (session &optional thread-id)
  (make-service-query-response :conversation
                               :thread-detail
                               (thread-detail session thread-id)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :thread-detail-v1
                                                                :session session
                                                                :thread-id thread-id)))

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

(defun query-conversation-latency-service (session &optional turn-id)
  (make-service-query-response :conversation
                               :latency
                               (conversation-latency-summary-data session turn-id)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :conversation-latency-v1
                                                                :session session
                                                                :turn-id turn-id)))
