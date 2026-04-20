(in-package #:sbcl-agent)

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
  (make-service-query-response :conversation
                               :turn-detail
                               (turn-detail session turn-id)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :turn-detail-v1
                                                                :session session
                                                                :turn-id turn-id)))
