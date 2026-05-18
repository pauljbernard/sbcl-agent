(in-package #:sbcl-agent)

(defun query-intent-list-service (session)
  (let* ((environment (or (session-bound-environment session)
                          (ensure-environment)))
         (current-id (current-intent-id environment)))
    (make-service-query-response
     :intent
     :list
     (list :current-intent-id current-id
           :intents (mapcar #'intent-record-summary (list-intent-records session)))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :intent-list-v1
                                      :session session))))

(defun query-intent-detail-service (session intent-id)
  (let* ((environment (or (session-bound-environment session)
                          (ensure-environment)))
         (intent (or (find-intent-record session intent-id)
                     (error "Unknown intent ~A" intent-id))))
    (make-service-query-response
     :intent
     :detail
     (intent-record-detail intent
                           :currentp (string= intent-id
                                              (or (current-intent-id environment) "")))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :intent-detail-v1
                                      :session session))))

(defun make-intent-control-actor-address (session)
  (make-standard-actor-address :intent
                               :scope (agent-session-id session)))

(defun actorize-intent-command-response (response &key actor-execution-job-id)
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

(defun make-intent-control-request (session action capability &key payload metadata intent-id)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :intent
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :intent-control-v1)
                     (when intent-id
                       (list :intent-id intent-id))
                     metadata)))

(defun call-with-intent-actor (session request thunk capability action &key intent-id)
  (let ((actor-address (make-intent-control-actor-address session)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-intent-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :governance
               :target :intent
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata (when intent-id
                           (list :intent-id intent-id))))))

(defun perform-intent-create-service (session &key description scope constraints
                                              expected-behaviors non-goals priority
                                              (version 1) (status :active)
                                              linked-runtime-objects
                                              linked-source-artifacts
                                              linked-event-ids
                                              linked-mutation-ids
                                              metadata)
  (let ((intent (create-intent-record session
                                      :description description
                                      :scope scope
                                      :constraints constraints
                                      :expected-behaviors expected-behaviors
                                      :non-goals non-goals
                                      :priority priority
                                      :version version
                                      :status status
                                      :linked-runtime-objects linked-runtime-objects
                                      :linked-source-artifacts linked-source-artifacts
                                      :linked-event-ids linked-event-ids
                                      :linked-mutation-ids linked-mutation-ids
                                      :metadata metadata)))
    (make-service-command-response
     :intent
     :create
     (intent-record-detail intent :currentp t)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :intent-command-v1
                                      :session session))))

(defun command-intent-create-service (session &key description scope constraints
                                              expected-behaviors non-goals priority
                                              (version 1) (status :active)
                                              linked-runtime-objects
                                              linked-source-artifacts
                                              linked-event-ids
                                              linked-mutation-ids
                                              metadata)
  (call-with-intent-actor
   session
   (make-intent-control-request session
                                :create
                                :intent/create
                                :payload (list :description description
                                               :scope scope
                                               :constraints constraints
                                               :expected-behaviors expected-behaviors
                                               :non-goals non-goals
                                               :priority priority
                                               :version version
                                               :status status
                                               :linked-runtime-objects linked-runtime-objects
                                               :linked-source-artifacts linked-source-artifacts
                                               :linked-event-ids linked-event-ids
                                               :linked-mutation-ids linked-mutation-ids
                                               :metadata metadata))
   (lambda ()
     (command-kernel-invoke-service session
                                    (or description "Create an intent record.")
                                    "intent/create"
                                    :authority :environment
                                    :payload (list :description description
                                                   :scope scope
                                                   :constraints constraints
                                                   :expected-behaviors expected-behaviors
                                                   :non-goals non-goals
                                                   :priority priority
                                                   :version version
                                                   :status status
                                                   :linked-runtime-objects linked-runtime-objects
                                                   :linked-source-artifacts linked-source-artifacts
                                                   :linked-event-ids linked-event-ids
                                                   :linked-mutation-ids linked-mutation-ids
                                                   :metadata metadata)))
   :intent/create
   :create))

(defun perform-intent-update-service (session intent-id &key description scope constraints
                                              expected-behaviors non-goals priority
                                              version status linked-runtime-objects
                                              linked-source-artifacts linked-event-ids
                                              linked-mutation-ids metadata)
  (let* ((before (or (find-intent-record session intent-id)
                     (error "Unknown intent ~A" intent-id)))
         (updated (update-intent-record
                   session
                   intent-id
                   (lambda (intent)
                     (build-intent-record
                      :id (intent-record-id intent)
                      :description (or description (intent-record-description intent))
                      :scope (or scope (intent-record-scope intent))
                      :constraints (or constraints (intent-record-constraints intent))
                      :expected-behaviors (or expected-behaviors
                                              (intent-record-expected-behaviors intent))
                      :non-goals (or non-goals (intent-record-non-goals intent))
                      :priority (or priority (intent-record-priority intent))
                      :version (or version (1+ (or (intent-record-version intent) 0)))
                      :status (or status (intent-record-status intent))
                      :linked-runtime-objects (or linked-runtime-objects
                                                  (intent-record-linked-runtime-objects intent))
                      :linked-source-artifacts (or linked-source-artifacts
                                                   (intent-record-linked-source-artifacts intent))
                      :linked-event-ids (or linked-event-ids
                                            (intent-record-linked-event-ids intent))
                      :linked-mutation-ids (or linked-mutation-ids
                                               (intent-record-linked-mutation-ids intent))
                      :metadata (or metadata (intent-record-metadata intent)))))))
    (make-service-command-response
     :intent
     :update
     (append (intent-record-detail updated
                                   :currentp (string= (intent-record-id updated)
                                                      (or (current-intent-id (session-bound-environment session))
                                                          "")))
             (list :diff (intent-record-diff before updated)))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :intent-command-v1
                                      :session session))))

(defun command-intent-update-service (session intent-id &key description scope constraints
                                              expected-behaviors non-goals priority
                                              version status linked-runtime-objects
                                              linked-source-artifacts linked-event-ids
                                              linked-mutation-ids metadata)
  (call-with-intent-actor
   session
   (make-intent-control-request session
                                :update
                                :intent/update
                                :payload (list :intent-id intent-id
                                               :description description
                                               :scope scope
                                               :constraints constraints
                                               :expected-behaviors expected-behaviors
                                               :non-goals non-goals
                                               :priority priority
                                               :version version
                                               :status status
                                               :linked-runtime-objects linked-runtime-objects
                                               :linked-source-artifacts linked-source-artifacts
                                               :linked-event-ids linked-event-ids
                                               :linked-mutation-ids linked-mutation-ids
                                               :metadata metadata)
                                :intent-id intent-id)
   (lambda ()
     (command-kernel-invoke-service session
                                    (or description
                                        (format nil "Update intent ~A." intent-id))
                                    "intent/update"
                                    :authority :environment
                                    :payload (list :intent-id intent-id
                                                   :description description
                                                   :scope scope
                                                   :constraints constraints
                                                   :expected-behaviors expected-behaviors
                                                   :non-goals non-goals
                                                   :priority priority
                                                   :version version
                                                   :status status
                                                   :linked-runtime-objects linked-runtime-objects
                                                   :linked-source-artifacts linked-source-artifacts
                                                   :linked-event-ids linked-event-ids
                                                   :linked-mutation-ids linked-mutation-ids
                                                   :metadata metadata)))
   :intent/update
   :update
   :intent-id intent-id))

(defun perform-intent-select-service (session intent-id)
  (let* ((selected (select-intent-record session intent-id)))
    (make-service-command-response
     :intent
     :select
     (intent-record-detail selected :currentp t)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :intent-command-v1
                                      :session session))))

(defun command-intent-select-service (session intent-id)
  (call-with-intent-actor
   session
   (make-intent-control-request session
                                :select
                                :intent/select
                                :payload (list :intent-id intent-id)
                                :intent-id intent-id)
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Select intent ~A." intent-id)
                                    "intent/select"
                                    :authority :environment
                                    :payload (list :intent-id intent-id)))
   :intent/select
   :select
   :intent-id intent-id))
