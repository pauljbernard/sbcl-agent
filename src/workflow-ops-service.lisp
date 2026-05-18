(in-package #:sbcl-agent)

(defun make-workflow-control-actor-address (session)
  (make-standard-actor-address :workflow
                               :scope (agent-session-id session)))

(defun make-workflow-control-request (session work-item action capability
                                      &key payload metadata)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :workflow
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :work-item-id (work-item-id work-item)
                           :workflow-record-id (work-item-workflow-record-ref work-item)
                           :actor-slice :workflow-control-v1)
                     metadata)))

(defun make-workflow-query-request (session action capability
                                    &key payload metadata work-item-id workflow-record-id plan-id)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :workflow
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :workflow-query-v1)
                     (when work-item-id
                       (list :work-item-id work-item-id))
                     (when workflow-record-id
                       (list :workflow-record-id workflow-record-id))
                     (when plan-id
                       (list :plan-id plan-id))
                     metadata)))

(defun call-with-workflow-actor (session work-item request thunk capability action)
  (let ((actor-address (make-workflow-control-actor-address session)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-desktop-task-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :operator
               :target :workflow
               :operation action
               :request-id (desktop-task-request-id request)
               :work-item-id (work-item-id work-item)
               :workflow-record-id (work-item-workflow-record-ref work-item)))))

(defun actorize-workflow-query-response (response &key actor-execution-job-id)
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

(defun call-with-workflow-query-actor (session request thunk capability action
                                       &key work-item-id workflow-record-id metadata)
  (let ((actor-address (make-workflow-control-actor-address session)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-workflow-query-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :operator
               :target :workflow
               :operation action
               :request-id (desktop-task-request-id request)
               :work-item-id work-item-id
               :workflow-record-id workflow-record-id
               :metadata metadata))))

(defun perform-work-item-quarantine-service (session work-item-id reason)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (quarantine-work-item session work-item reason :evidence (work-item-summary work-item))
    (kernelize-service-command-response
     (make-service-command-response :workflow
                                    :quarantine-work-item
                                    (enriched-work-item-service-detail session work-item)
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :workflow-command-v1
                                                                     :session session
                                                                     :work-item-id work-item-id))
     :session session
     :intention (format nil "Quarantine work item ~A for governed review." work-item-id)
     :capability :workflow/quarantine
     :authority :operator
     :constraints (list :reason reason))))

(defun command-work-item-quarantine-service (session work-item-id reason)
  (let ((work-item (or (find-work-item session work-item-id)
                       (error "Unknown work-item ~A" work-item-id))))
    (call-with-workflow-actor
     session
     work-item
     (make-workflow-control-request session
                                    work-item
                                    :quarantine-work-item
                                    :workflow/quarantine
                                    :payload (list :reason reason)
                                    :metadata (list :reason reason))
     (lambda ()
       (perform-work-item-quarantine-service session work-item-id reason))
     :workflow/quarantine
     :quarantine-work-item)))

(defun perform-work-item-resume-service (session work-item-id &key note)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (when (fboundp 'recover-work-item-control-state)
      (recover-work-item-control-state session
                                       work-item
                                       :recovery-origin :resume-work-item))
    (resume-work-item session work-item :note note)
    (kernelize-service-command-response
     (make-service-command-response :workflow
                                    :resume-work-item
                                    (enriched-work-item-service-detail session work-item)
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :workflow-command-v1
                                                                     :session session
                                                                     :work-item-id work-item-id))
     :session session
     :intention (format nil "Resume governed work item ~A." work-item-id)
     :capability :workflow/resume
     :authority :operator
     :constraints (list :note note))))

(defun command-work-item-resume-service (session work-item-id &key note)
  (let ((work-item (or (find-work-item session work-item-id)
                       (error "Unknown work-item ~A" work-item-id))))
    (call-with-workflow-actor
     session
     work-item
     (make-workflow-control-request session
                                    work-item
                                    :resume-work-item
                                    :workflow/resume
                                    :payload (list :note note)
                                    :metadata (when note (list :note note)))
     (lambda ()
       (perform-work-item-resume-service session work-item-id :note note))
     :workflow/resume
     :resume-work-item)))

(defun perform-work-item-rollback-service (session work-item-id &key reason note)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (when (fboundp 'recover-work-item-control-state)
      (recover-work-item-control-state session
                                       work-item
                                       :recovery-origin :rollback-work-item))
    (rollback-work-item session work-item :reason reason :note note)
    (kernelize-service-command-response
     (make-service-command-response :workflow
                                    :rollback-work-item
                                    (enriched-work-item-service-detail session work-item)
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :workflow-command-v1
                                                                     :session session
                                                                     :work-item-id work-item-id))
     :session session
     :intention (format nil "Rollback governed work item ~A." work-item-id)
     :capability :workflow/rollback
     :authority :operator
     :constraints (list :reason reason
                        :note note))))

(defun command-work-item-rollback-service (session work-item-id &key reason note)
  (let ((work-item (or (find-work-item session work-item-id)
                       (error "Unknown work-item ~A" work-item-id))))
    (call-with-workflow-actor
     session
     work-item
     (make-workflow-control-request session
                                    work-item
                                    :rollback-work-item
                                    :workflow/rollback
                                    :payload (list :reason reason
                                                   :note note)
                                    :metadata (append (when reason (list :reason reason))
                                                      (when note (list :note note))))
     (lambda ()
       (perform-work-item-rollback-service session
                                           work-item-id
                                           :reason reason
                                           :note note))
     :workflow/rollback
     :rollback-work-item)))

(defun perform-work-item-complete-validations-service (session work-item-id &key (status :passed))
  (let* ((work-item (find-work-item session work-item-id))
         (cold-validator (and work-item
                              (find :cold
                                    (work-item-validator-tasks work-item)
                                    :key #'validator-task-record-kind))))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (when (fboundp 'recover-work-item-control-state)
      (recover-work-item-control-state session
                                       work-item
                                       :recovery-origin :complete-validations))
    (setf cold-validator (find :cold
                               (work-item-validator-tasks work-item)
                               :key #'validator-task-record-kind))
    (unless cold-validator
      (error "Work-item ~A has no cold validator task to complete" work-item-id))
    (execute-validator-task-record session
                                   work-item
                                   (validator-task-record-id cold-validator)
                                   :status status)
    (kernelize-service-command-response
     (make-service-command-response :workflow
                                    :complete-validations
                                    (enriched-work-item-service-detail session work-item)
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :workflow-command-v1
                                                                     :session session
                                                                     :work-item-id work-item-id))
     :session session
     :intention (format nil "Complete governed cold validation for work item ~A." work-item-id)
     :capability :workflow/complete-validations
     :authority :operator
     :constraints (list :status status))))

(defun command-work-item-complete-validations-service (session work-item-id &key (status :passed))
  (let ((work-item (or (find-work-item session work-item-id)
                       (error "Unknown work-item ~A" work-item-id))))
    (call-with-workflow-actor
     session
     work-item
     (make-workflow-control-request session
                                    work-item
                                    :complete-validations
                                    :workflow/complete-validations
                                    :payload (list :status status)
                                    :metadata (list :status status))
     (lambda ()
       (perform-work-item-complete-validations-service session
                                                       work-item-id
                                                       :status status))
     :workflow/complete-validations
     :complete-validations)))

(defun perform-work-item-steer-service (session work-item-id &key phase next-step note)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (steer-work-item-plan session work-item
                          :phase phase
                          :next-step next-step
                          :note note)
    (make-service-command-response :workflow
                                   :steer-work-item
                                   (enriched-work-item-service-detail session work-item)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :workflow-command-v1
                                                                    :session session
                                                                    :work-item-id work-item-id))))

(defun command-work-item-steer-service (session work-item-id &key phase next-step note)
  (let ((work-item (or (find-work-item session work-item-id)
                       (error "Unknown work-item ~A" work-item-id))))
    (call-with-workflow-actor
     session
     work-item
     (make-workflow-control-request session
                                    work-item
                                    :steer-work-item
                                    :workflow/steer-plan
                                    :payload (list :phase phase
                                                   :next-step next-step
                                                   :note note)
                                    :metadata (append (when phase (list :phase phase))
                                                      (when next-step (list :next-step next-step))
                                                      (when note (list :note note))))
     (lambda ()
       (perform-work-item-steer-service session
                                        work-item-id
                                        :phase phase
                                        :next-step next-step
                                        :note note))
     :workflow/steer-plan
     :steer-work-item)))

(defun query-work-item-wait-service (session work-item-id)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (let* ((handles (or (work-item-associated-execution-summaries session work-item)
                        '()))
           (surface (or (compact-execution-surface-summary
                         (primary-execution-surface-summary session handles))
                        (list :surface-id (format nil "surface-work-item-~A" work-item-id)
                              :surface-kind "governed-work"
                              :attention-rank 1
                              :execution-id nil
                              :title (work-item-goal work-item)
                              :status (work-item-status work-item)
                              :object-kind "work-item"
                              :work-item-id work-item-id
                              :primary-execution-handle (first handles)))))
      (make-service-query-response :workflow
                                   :work-item-wait
                                   (append (work-item-wait-report session work-item)
                                           (list :primary-execution-handle (first handles)
                                                 :execution-handles handles
                                                 :execution-surface surface))
                                   :metadata (make-service-metadata :authority :environment
                                    :read-model :work-item-wait-v1
                                    :session session
                                    :work-item-id work-item-id)))))

(defun command-work-item-wait-query-service (session work-item-id)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :work-item-wait-query
                                :workflow/work-item-wait
                                :payload (list :work-item-id work-item-id)
                                :work-item-id work-item-id
                                :metadata (list :work-item-id work-item-id))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Read wait state for work item ~A." work-item-id)
                                    "workflow/work-item-wait"
                                    :authority :operator
                                    :payload (list :work-item-id work-item-id)))
   :workflow/work-item-wait
   :work-item-wait-query
   :work-item-id work-item-id
   :metadata (list :work-item-id work-item-id)))

(defun query-replay-groups-service (session)
  (make-service-query-response :workflow
                               :replay-groups
                               (session-validator-replay-groups session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :replay-groups-v1
                                                                :session session)))

(defun query-image-reconciliations-service (session)
  (make-service-query-response :workflow
                               :image-reconciliations
                               (session-image-reconciliation-summary session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :image-reconciliations-v1
                                                                :session session)))

(defun command-replay-validator-task-service (session work-item-id validator-task-id &key status)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (execute-validator-task-record session work-item validator-task-id :status status)
    (make-service-command-response :workflow
                                   :replay-validator-task
                                   (enriched-work-item-service-detail session work-item)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :workflow-command-v1
                                                                    :session session
                                                                    :work-item-id work-item-id))))

(defun command-replay-validator-set-service (session work-item-id replay-id &key status statuses)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (execute-validator-replay-set session work-item replay-id :status status :statuses statuses)
    (make-service-command-response :workflow
                                   :replay-validator-set
                                   (enriched-work-item-service-detail session work-item)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :workflow-command-v1
                                                                    :session session
                                                                    :work-item-id work-item-id))))

(defun command-reconcile-image-only-source-service (session work-item-id summary)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (reconcile-image-only-work-item-to-source session work-item summary)
    (make-service-command-response :workflow
                                   :reconcile-image-only-source
                                   (enriched-work-item-service-detail session work-item)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :workflow-command-v1
                                                                    :session session
                                                                    :work-item-id work-item-id))))
