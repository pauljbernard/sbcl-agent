(in-package #:sbcl-agent)

(defun mutation-review-surface-summary (session execution-handles &key preferred-surface-kind)
  (let ((surfaces (remove nil
                          (mapcar (lambda (summary)
                                    (let ((execution-id (getf summary :execution-id)))
                                      (and execution-id
                                           (query-execution-surface-by-id session execution-id))))
                                  (or execution-handles '())))))
    (compact-execution-surface-summary
     (if preferred-surface-kind
         (find preferred-surface-kind surfaces
               :key (lambda (surface)
                      (getf surface :surface-kind))
               :test #'string=)
         (or (first surfaces)
             (primary-execution-surface-summary session execution-handles))))))

(defun mutation-review-turn-surface-summary (session turn)
  (or (mutation-review-surface-summary session
                                      (getf turn :execution-handles)
                                      :preferred-surface-kind "conversation")
      (compact-execution-surface-summary
       (list :surface-id (format nil "surface-turn-~A" (getf turn :id))
             :surface-kind "conversation"
             :attention-rank 5
             :execution-id nil
             :title "Conversation turn"
             :status (getf turn :status)
             :object-kind "turn"
             :thread-id (getf turn :thread-id)
             :turn-id (getf turn :id)))))

(defun mutation-review-work-item-surface-summary (session work-item)
  (or (mutation-review-surface-summary session
                                      (getf work-item :execution-handles)
                                      :preferred-surface-kind "governed-work")
      (compact-execution-surface-summary
       (list :surface-id (format nil "surface-work-item-~A" (getf work-item :id))
             :surface-kind "governed-work"
             :attention-rank 1
             :execution-id nil
             :title (or (getf work-item :goal)
                        "Governed work item")
             :status (getf work-item :status)
             :object-kind "work-item"
             :work-item-id (getf work-item :id)
             :workflow-record-id (getf work-item :workflow-record-id)
             :thread-id (getf work-item :thread-id)))))

(defun mutation-review-workflow-surface-summary (session workflow-record)
  (or (mutation-review-surface-summary session
                                      (getf workflow-record :execution-handles)
                                      :preferred-surface-kind "workflow")
      (compact-execution-surface-summary
       (list :surface-id (format nil "surface-workflow-~A" (getf workflow-record :id))
             :surface-kind "workflow"
             :attention-rank 1
             :execution-id nil
             :title (or (getf workflow-record :goal)
                        "Workflow record")
             :status (getf workflow-record :status)
             :object-kind "workflow-record"
             :workflow-record-id (getf workflow-record :id)
             :work-item-id (getf workflow-record :work-item-id)
             :thread-id (getf workflow-record :thread-id)))))

(defun enrich-mutation-review-governance (session governance)
  (let* ((work-item (getf governance :work-item))
         (workflow-record (getf governance :workflow-record)))
    (append governance
            (list :work-item-surface (and work-item
                                          (mutation-review-work-item-surface-summary
                                           session
                                           work-item))
                  :workflow-record-surface (and workflow-record
                                                (mutation-review-workflow-surface-summary
                                                 session
                                                 workflow-record))))))

(defun enrich-mutation-review-incidents (session incidents)
  (mapcar (lambda (incident)
            (let* ((incident-id (getf incident :id))
                   (resolved (and incident-id
                                  (find-incident session incident-id))))
              (if resolved
                  (enrich-incident-summary-with-executions session incident)
                  incident)))
          incidents))

(defun enrich-mutation-review-payload (session review)
  (let* ((turn (getf review :turn))
         (governance (getf review :governance))
         (incidents (getf review :incidents)))
    (plist-put
     (plist-put
      (plist-put review
                        :turn
                        (append turn
                                (list :execution-surface
                                      (mutation-review-turn-surface-summary session turn))))
      :governance
      (enrich-mutation-review-governance session governance))
     :incidents
     (enrich-mutation-review-incidents session incidents))))

(defun query-mutation-review-service (session &optional turn-id)
  (make-service-query-response :mutation
                               :review
                               (enrich-mutation-review-payload session
                                                               (mutation-review session turn-id))
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :mutation-review-v1
                                                                :session session
                                                                :turn-id turn-id)))
