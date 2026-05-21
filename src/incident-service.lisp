(in-package #:sbcl-agent)

(defun incident-associated-execution-summaries (session incident)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let* ((direct (find-execution-handles-by-target :incident-id
                                                       (incident-id incident)
                                                       environment))
             (via-work-item (and (incident-work-item-id incident)
                                 (find-execution-handles-by-target :work-item-id
                                                                   (incident-work-item-id incident)
                                                                   environment)))
             (via-turn (and (incident-turn-id incident)
                            (find-execution-handles-by-target :turn-id
                                                              (incident-turn-id incident)
                                                              environment)))
             (combined (append direct via-work-item via-turn)))
        (mapcar #'execution-handle-summary
                (remove-duplicates combined
                                   :key #'execution-handle-execution-id
                                   :test #'string=))))))

(defun incident-execution-surface-summary (incident handles)
  (let ((primary-handle (first handles)))
    (list :surface-id (format nil "surface-incident-~A" (incident-id incident))
          :surface-kind "incident"
          :attention-rank (if (member (incident-status incident)
                                      '(:open :failed :awaiting-approval :quarantined
                                        :awaiting-cold-validation)
                                      :test #'eq)
                              1
                              5)
          :execution-id (and primary-handle
                             (getf primary-handle :execution-id))
          :title (or (incident-title incident)
                     "Incident")
          :status (incident-status incident)
          :capability (and primary-handle
                           (getf primary-handle :capability))
          :object-kind "incident"
          :thread-id (incident-thread-id incident)
          :turn-id (incident-turn-id incident)
          :work-item-id (incident-work-item-id incident)
          :workflow-record-id (incident-workflow-record-id incident)
          :incident-id (incident-id incident)
          :runtime-id (and primary-handle
                           (getf primary-handle :runtime-id))
          :primary-execution-handle primary-handle)))

(defun enrich-incident-summary-with-executions (session summary)
  (let* ((incident-id (getf summary :id))
         (incident (and incident-id
                        (find-incident session incident-id)))
         (handles (and incident
                       (incident-associated-execution-summaries session incident))))
    (append summary
            (list :primary-execution-handle (first handles)
                  :execution-handles (or handles '())
                  :execution-surface (and incident
                                          (compact-execution-surface-summary
                                           (incident-execution-surface-summary incident handles)))))))

(defun query-incident-list-service (session &key thread-id turn-id)
  (make-service-query-response :incident
                               :list
                               (mapcar (lambda (summary)
                                         (enrich-incident-summary-with-executions session summary))
                                       (list-incident-summaries session :thread-id thread-id :turn-id turn-id))
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :incident-list-v1
                                                                :session session
                                                                :thread-id thread-id
                                                                :turn-id turn-id)))

(defun query-incident-detail-service (session incident-id)
  (let ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown incident ~A" incident-id))
    (make-service-query-response :incident
                                 :detail
                                 (let ((handles (or (incident-associated-execution-summaries session incident)
                                                    '())))
                                   (append (incident-detail session incident)
                                           (list :primary-execution-handle (first handles)
                                                 :execution-handles handles
                                                 :execution-surface (compact-execution-surface-summary
                                                                     (incident-execution-surface-summary incident handles)))))
                                  :metadata (make-service-metadata :authority :environment
                                                                   :read-model :incident-detail-v1
                                                                   :session session
                                                                   :incident-id incident-id))))

(defun query-incident-condition-service (session incident-id)
  (let ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown incident ~A" incident-id))
    (make-service-query-response :incident
                                 :condition
                                 (list :incident-id (incident-id incident)
                                       :kind (incident-kind incident)
                                       :status (incident-status incident)
                                       :condition (incident-condition-string incident)
                                       :condition-summary (incident-condition-summary incident)
                                       :condition-detail (incident-condition-detail incident))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :incident-condition-v1
                                                                  :session session
                                                                  :incident-id incident-id))))

(defun query-incident-restarts-service (session incident-id)
  (let ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown incident ~A" incident-id))
    (let ((restart-suggestions (incident-restart-suggestions incident)))
      (make-service-query-response :incident
                                   :restarts
                                   (list :incident-id (incident-id incident)
                                         :kind (incident-kind incident)
                                         :status (incident-status incident)
                                         :restart-count (length restart-suggestions)
                                         :restart-suggestions restart-suggestions
                                         :recommended-actions
                                         (remove-if-not (lambda (action)
                                                          (eq (getf action :type) :consider-restart))
                                                        (incident-recommended-actions session incident)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :read-model :incident-restarts-v1
                                                                    :session session
                                                                    :incident-id incident-id)))))

(defun make-incident-control-actor-address (session)
  (make-standard-actor-address :incident
                               :scope (agent-session-id session)))

(defun actorize-incident-command-response (response &key actor-execution-job-id)
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

(defun actorize-incident-query-response (response &key actor-execution-job-id)
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

(defun command-incident-list-query-service (session &key thread-id turn-id)
  (let* ((payload (append (when thread-id (list :thread-id thread-id))
                          (when turn-id (list :turn-id turn-id))))
         (metadata (append (list :session-id (agent-session-id session)
                                 :actor-slice :incident-query-v1)
                           (when thread-id (list :thread-id thread-id))
                           (when turn-id (list :turn-id turn-id))))
         (actor-address (make-incident-control-actor-address session))
         (request (make-governed-desktop-task-request
                   :requester :context-chat
                   :target :incident
                   :operation :incident-list-query
                   :capability :incident/list
                   :payload payload
                   :metadata metadata)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-incident-query-response
        (query-incident-list-service session :thread-id thread-id :turn-id turn-id)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability :incident/list
               :authority :operator
               :target :incident
               :operation :incident-list-query
               :request-id (desktop-task-request-id request)
               :metadata metadata))))

(defun command-incident-detail-query-service (session incident-id)
  (let* ((payload (list :incident-id incident-id))
         (metadata (list :session-id (agent-session-id session)
                         :incident-id incident-id
                         :actor-slice :incident-query-v1))
         (actor-address (make-incident-control-actor-address session))
         (request (make-governed-desktop-task-request
                   :requester :context-chat
                   :target :incident
                   :operation :incident-detail-query
                   :capability :incident/detail
                   :payload payload
                   :metadata metadata)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-incident-query-response
        (query-incident-detail-service session incident-id)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability :incident/detail
               :authority :operator
               :target :incident
               :operation :incident-detail-query
               :request-id (desktop-task-request-id request)
               :metadata metadata))))

(defun perform-incident-remediation-plan-service (session incident-id remediation-plan)
  (let ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown incident ~A" incident-id))
    (update-incident-remediation-plan session incident remediation-plan)
    (make-service-command-response :incident
                                   :set-remediation-plan
                                   (incident-detail session incident)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :incident-command-v1
                                                                    :session session
                                                                    :incident-id incident-id))))

(defun command-incident-remediation-plan-service (session incident-id remediation-plan)
  (let* ((incident (or (find-incident session incident-id)
                       (error "Unknown incident ~A" incident-id)))
         (actor-address (make-incident-control-actor-address session))
         (request (make-governed-desktop-task-request
                   :requester :context-chat
                   :target :incident
                   :operation :set-remediation-plan
                   :capability :incident/remediation
                   :payload (list :incident-id incident-id
                                  :remediation-plan remediation-plan)
                   :metadata (append (list :session-id (agent-session-id session)
                                           :incident-id incident-id
                                           :actor-slice :incident-control-v1)
                                     (when (incident-work-item-id incident)
                                       (list :work-item-id (incident-work-item-id incident)))
                                     (when (incident-workflow-record-id incident)
                                       (list :workflow-record-id
                                             (incident-workflow-record-id incident)))))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-incident-command-response
        (perform-incident-remediation-plan-service session incident-id remediation-plan)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability :incident/remediation
               :authority :governance
               :target :incident
               :operation :set-remediation-plan
               :request-id (desktop-task-request-id request)
               :work-item-id (incident-work-item-id incident)
               :workflow-record-id (incident-workflow-record-id incident)
               :metadata (list :incident-id incident-id)))))
