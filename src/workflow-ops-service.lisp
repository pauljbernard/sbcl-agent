(in-package #:sbcl-agent)

(defun command-work-item-quarantine-service (session work-item-id reason)
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

(defun command-work-item-resume-service (session work-item-id &key note)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
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

(defun command-work-item-rollback-service (session work-item-id &key reason note)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
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

(defun command-work-item-complete-validations-service (session work-item-id &key (status :passed))
  (let* ((work-item (find-work-item session work-item-id))
         (cold-validator (and work-item
                              (find :cold
                                    (work-item-validator-tasks work-item)
                                    :key #'validator-task-record-kind))))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
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

(defun command-work-item-steer-service (session work-item-id &key phase next-step note)
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
