(in-package #:sbcl-agent)

(defun incident-associated-execution-summaries (session incident)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let* ((direct (kernel-find-executions-by-target :incident-id
                                                       (incident-id incident)
                                                       environment))
             (via-work-item (and (incident-work-item-id incident)
                                 (kernel-find-executions-by-target :work-item-id
                                                                   (incident-work-item-id incident)
                                                                   environment)))
             (via-turn (and (incident-turn-id incident)
                            (kernel-find-executions-by-target :turn-id
                                                              (incident-turn-id incident)
                                                              environment)))
             (combined (append direct via-work-item via-turn)))
        (mapcar #'kernel-execution-summary
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

(defun command-incident-remediation-plan-service (session incident-id remediation-plan)
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
