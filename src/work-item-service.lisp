(in-package #:sbcl-agent)

(defun work-item-associated-execution-summaries (session work-item)
  (let ((environment (session-bound-environment session)))
    (when environment
      (mapcar #'kernel-execution-summary
              (kernel-find-executions-by-target :work-item-id
                                                (work-item-id work-item)
                                                environment)))))

(defun work-item-linked-incident-count (session work-item)
  (count (work-item-id work-item)
         (agent-session-incidents session)
         :key #'incident-work-item-id
         :test #'string=))

(defun work-item-linked-artifact-count (session work-item)
  (count (work-item-id work-item)
         (agent-session-artifacts session)
         :key #'artifact-work-item-id
         :test #'string=))

(defun enrich-work-item-summary-with-executions (session summary)
  (let* ((work-item-id (getf summary :id))
         (work-item (and work-item-id
                         (find-work-item session work-item-id)))
         (record (and work-item
                      (work-item-workflow-record session work-item)))
         (pending-validations (or (getf summary :pending-validations) '()))
         (waiting-on (and record (workflow-record-waiting-on record)))
         (wait-reason (cond
                        ((eq waiting-on :approval) :approval-required)
                        ((eq waiting-on :operator-review) :operator-review-required)
                        ((eq (work-item-status work-item) :awaiting-cold-validation)
                         :cold-validation-required)
                        ((equal pending-validations '(:cold))
                         :cold-validation-required)
                        ((null pending-validations) :ready)
                        (t :pending-validation)))
         (handles (and work-item
                       (work-item-associated-execution-summaries session work-item)))
         (incident-count (and work-item
                              (work-item-linked-incident-count session work-item)))
         (artifact-count (and work-item
                              (work-item-linked-artifact-count session work-item))))
    (append summary
            (when work-item
              (list :waiting-on waiting-on
                    :wait-reason wait-reason
                    :incident-count incident-count
                    :artifact-count artifact-count
                    :approval-requirements (and record (workflow-record-approval-requirements record))))
            (list :primary-execution-handle (first handles)
                  :execution-handles (or handles '())
                  :execution-surface (compact-execution-surface-summary
                                      (primary-execution-surface-summary session handles))))))

(defun enriched-work-item-service-detail (session work-item)
  (let ((detail (work-item-detail work-item))
        (record (work-item-workflow-record session work-item)))
    (append detail
            (when record
              (list :workflow-record (workflow-record-summary record)))
            (let ((handles (or (work-item-associated-execution-summaries session work-item)
                               '())))
              (list :primary-execution-handle (first handles)
                    :execution-handles handles
                    :execution-surface (compact-execution-surface-summary
                                        (primary-execution-surface-summary session handles))
                    :trace-neighborhood
                    (trace-neighborhood-summary session :work-item (work-item-id work-item)))))))

(defun query-work-item-list-service (session)
  (make-service-query-response :work-item
                               :list
                               (mapcar (lambda (summary)
                                         (enrich-work-item-summary-with-executions session summary))
                                       (list-work-item-summaries session))
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :work-item-list-v1
                                                                :session session)))

(defun command-work-item-list-query-service (session)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :work-item-list-query
                                :workflow/work-item-list)
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read governed work-item list."
                                    "workflow/work-item-list"
                                    :authority :operator
                                    :payload '()))
   :workflow/work-item-list
   :work-item-list-query))

(defun query-work-item-detail-service (session work-item-id)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (make-service-query-response :work-item
                                 :detail
                                 (enriched-work-item-service-detail session work-item)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :work-item-detail-v1
                                                                  :session session
                                                                  :work-item-id work-item-id))))

(defun command-work-item-detail-query-service (session work-item-id)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :work-item-detail-query
                                :workflow/work-item-detail
                                :payload (list :work-item-id work-item-id)
                                :work-item-id work-item-id
                                :metadata (list :work-item-id work-item-id))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Read detail for work item ~A." work-item-id)
                                    "workflow/work-item-detail"
                                    :authority :operator
                                    :payload (list :work-item-id work-item-id)))
   :workflow/work-item-detail
   :work-item-detail-query
   :work-item-id work-item-id
   :metadata (list :work-item-id work-item-id)))

(defun query-work-item-plan-service (session work-item-id)
  (let ((work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (make-service-query-response
     :work-item
     :plan
     (let ((handles (or (work-item-associated-execution-summaries session work-item)
                        '())))
       (list :id (work-item-id work-item)
             :status (work-item-status work-item)
             :goal (work-item-goal work-item)
             :long-horizon-plan (work-item-long-horizon-plan work-item)
             :plan-health (work-item-plan-health work-item)
             :plan-steering (work-item-plan-steering work-item)
             :operator-steering-history (work-item-operator-steering-history work-item)
             :next-action (work-item-next-action work-item)
             :resume-payload (work-item-resume-payload work-item)
             :pending-validations (work-item-pending-validations work-item)
             :primary-execution-handle (first handles)
             :execution-handles handles
             :execution-surface (compact-execution-surface-summary
                                 (primary-execution-surface-summary session handles))))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :work-item-plan-v1
                                      :session session
                                      :work-item-id work-item-id))))

(defun command-work-item-plan-query-service (session work-item-id)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :work-item-plan-query
                                :workflow/work-item-plan
                                :payload (list :work-item-id work-item-id)
                                :work-item-id work-item-id
                                :metadata (list :work-item-id work-item-id))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Read plan state for work item ~A." work-item-id)
                                    "workflow/work-item-plan"
                                    :authority :operator
                                    :payload (list :work-item-id work-item-id)))
   :workflow/work-item-plan
   :work-item-plan-query
   :work-item-id work-item-id
   :metadata (list :work-item-id work-item-id)))
