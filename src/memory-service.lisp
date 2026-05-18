(in-package #:sbcl-agent)

(defun query-memory-list-service (session)
  (make-service-query-response :memory
                               :list
                               (list :entries (list-operator-memory-entries session)
                                     :entry-count (length (list-operator-memory-entries session)))
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :operator-memory-list-v1
                                                                :session session)))

(defun query-memory-detail-service (session memory-id)
  (let ((entry (find-operator-memory-entry session memory-id)))
    (unless (and entry (environment-memory-operator-memory-entry-p entry))
      (error "Unknown operator memory entry ~S" memory-id))
    (make-service-query-response :memory
                                 :detail
                                 entry
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :operator-memory-detail-v1
                                                                  :session session))))

(defun make-memory-control-actor-address (session)
  (make-standard-actor-address :memory
                               :scope (agent-session-id session)))

(defun actorize-memory-command-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (listp data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun actorize-memory-query-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (and (listp data)
                   (keywordp (first data)))
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun make-memory-control-request (session action capability &key payload metadata memory-id)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :memory
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :memory-control-v1)
                     (when memory-id
                       (list :memory-id memory-id))
                     metadata)))

(defun call-with-memory-actor (session request thunk capability action &key memory-id)
  (let ((actor-address (make-memory-control-actor-address session)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-memory-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :governance
               :target :memory
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata (when memory-id
                           (list :memory-id memory-id))))))

(defun call-with-memory-query-actor (session request thunk capability action &key memory-id)
  (let ((actor-address (make-memory-control-actor-address session)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-memory-query-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :environment
               :target :memory
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata (when memory-id
                           (list :memory-id memory-id))))))

(defun command-memory-list-query-service (session)
  (call-with-memory-query-actor
   session
   (make-memory-control-request session
                                :list-query
                                :memory/list)
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read operator memory list."
                                    "memory/list"
                                    :authority :environment
                                    :payload '()))
   :memory/list
   :list-query))

(defun command-memory-detail-query-service (session memory-id)
  (call-with-memory-query-actor
   session
   (make-memory-control-request session
                                :detail-query
                                :memory/detail
                                :payload (list :memory-id memory-id)
                                :memory-id memory-id)
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Read operator memory ~A." memory-id)
                                    "memory/detail"
                                    :authority :environment
                                    :payload (list :memory-id memory-id)))
   :memory/detail
   :detail-query
   :memory-id memory-id))

(defun perform-memory-update-service (session memory-id &key category attribute value summary confidence)
  (make-service-command-response :memory
                                 :update
                                 (compact-operator-memory-entry
                                  (update-operator-memory-entry session
                                                                memory-id
                                                                :category category
                                                                :attribute attribute
                                                                :value value
                                                                :summary summary
                                                                :confidence confidence))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :operator-memory-command-v1
                                                                  :session session)))

(defun command-memory-update-service (session memory-id &key category attribute value summary confidence)
  (call-with-memory-actor
   session
   (make-memory-control-request session
                                :update
                                :memory/update
                                :payload (list :memory-id memory-id
                                               :category category
                                               :attribute attribute
                                               :value value
                                               :summary summary
                                               :confidence confidence)
                                :memory-id memory-id)
   (lambda ()
     (command-kernel-invoke-service session
                                    (or summary
                                        (format nil "Update operator memory ~A." memory-id))
                                    "memory/update"
                                    :authority :governance
                                    :payload (list :memory-id memory-id
                                                   :category category
                                                   :attribute attribute
                                                   :value value
                                                   :summary summary
                                                   :confidence confidence)))
   :memory/update
   :update
   :memory-id memory-id))

(defun perform-memory-delete-service (session memory-id)
  (delete-operator-memory-entry session memory-id)
  (make-service-command-response :memory
                                 :delete
                                 (list :memory-id memory-id
                                       :deleted-p t)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :operator-memory-command-v1
                                                                  :session session)))

(defun command-memory-delete-service (session memory-id)
  (call-with-memory-actor
   session
   (make-memory-control-request session
                                :delete
                                :memory/delete
                                :payload (list :memory-id memory-id)
                                :memory-id memory-id)
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Delete operator memory ~A." memory-id)
                                    "memory/delete"
                                    :authority :governance
                                    :payload (list :memory-id memory-id)))
   :memory/delete
   :delete
   :memory-id memory-id))
