(in-package #:sbcl-agent)

(defun command-work-item-quarantine-service (session work-item-id reason)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (quarantine-work-item session work-item reason :evidence (work-item-summary work-item))
    (make-service-command-response :workflow
                                   :quarantine-work-item
                                   (enriched-work-item-service-detail session work-item)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :workflow-command-v1
                                                                    :session session
                                                                    :work-item-id work-item-id))))

(defun command-work-item-resume-service (session work-item-id &key note)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (resume-work-item session work-item :note note)
    (make-service-command-response :workflow
                                   :resume-work-item
                                   (enriched-work-item-service-detail session work-item)
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :workflow-command-v1
                                                                     :session session
                                                                     :work-item-id work-item-id))))

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
    (make-service-query-response :workflow
                                 :work-item-wait
                                 (work-item-wait-report session work-item)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :work-item-wait-v1
                                                                  :session session
                                                                  :work-item-id work-item-id))))

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
