(in-package #:sbcl-agent)

(defun environment-event-metadata (environment event)
  (append (event-metadata event)
          (list :environment-id (environment-id environment)
                :environment-schema-version (environment-schema-version environment)
                :source-event-id (event-id event))))

(defun compact-environment-event-payload (event)
  (let ((payload (event-payload event)))
    (cond
      ((eq (event-kind event) :transcript)
       (list :event payload))
      ((eq (event-kind event) :provider-stream)
       (list :event-summary (list :canonical-type (getf (event-metadata event) :canonical-type)
                                  :legacy-type (getf (event-metadata event) :legacy-type)
                                  :provider-family (getf (event-metadata event) :provider-family))))
      ((listp payload)
       (list :event-summary payload))
      (t
       (list :event-summary payload)))))

(defun project-session-event-to-environment (environment event)
  (make-event :id (event-id event)
              :timestamp (event-timestamp event)
              :kind (event-kind event)
              :family (event-family event)
              :entity-id (or (event-entity-id event)
                             (event-id event))
              :thread-id (event-thread-id event)
              :turn-id (event-turn-id event)
              :visibility (event-visibility event)
              :metadata (environment-event-metadata environment event)
              :payload (append (list :environment-id (environment-id environment))
                               (compact-environment-event-payload event))))

(defun environment-event-log-from-session (environment session)
  (mapcar (lambda (event)
            (project-session-event-to-environment environment event))
          (agent-session-events session)))

(defun append-environment-session-event (environment session event)
  (declare (ignore session))
  (let ((projected-event (project-session-event-to-environment environment event)))
    (setf (environment-event-log environment)
          (append (environment-event-log environment)
                  (list projected-event)))
    projected-event))

(defun environment-incident-summary-from-session (session)
  (session-incident-summary session))

(defun environment-operator-status-from-session (session)
  (session-operator-status session))

(defun update-environment-root-summaries-from-session (environment session)
  (setf (environment-summaries environment)
        (list :session-id (agent-session-id session)
              :cwd (agent-session-cwd session)
              :thread-state (thread-state-summary session)
              :message-count (length (agent-session-messages session))
              :turn-count (length (agent-session-turns session))
              :operation-count (length (agent-session-operations session))
              :artifact-count (length (agent-session-artifacts session))
              :artifact-summary (session-artifact-summary session)
              :incident-count (length (agent-session-incidents session))
              :incident-summary (environment-incident-summary-from-session session)
              :operator-status (environment-operator-status-from-session session)))
  environment)

(defun sync-environment-root-bindings-from-session (environment session)
  (setf (environment-compatibility-session environment) session
        (environment-storage-root environment) (agent-session-cwd session)
        (environment-policy-state environment)
        (list :approved-policies (session-approved-policies session)
              :capability-grants (session-capability-grants-summary session)))
  (unless (environment-metadata-value environment :agent-constitution)
    (set-environment-agent-constitution environment (default-agent-constitution)))
  (update-environment-root-summaries-from-session environment session))

(defun sync-environment-runtime-history-from-session (environment session)
  (sync-environment-root-bindings-from-session environment session)
  (sync-environment-runtime-domain-from-session environment session)
  environment)

(defun sync-environment-domains-from-session (environment session)
  (sync-environment-runtime-domain-from-session environment session)
  (setf (environment-conversation-state environment)
        (make-environment-conversation-state-from-session session))
  (let* ((plans (session-plan-set session))
         (active-plan-id (session-active-plan-id session))
         (plan-summaries (session-plan-summaries session)))
    (setf (environment-workflow-state environment)
          (make-environment-workflow-state-from-session session))
    (setf (environment-agent-state environment)
          (make-environment-agent-state
           :agents (environment-agent-registry environment)
           :subscriptions '()
           :memory (environment-memory environment)
           :plan (session-active-plan session)
           :plans plans
           :active-plan-id active-plan-id
           :plan-summaries plan-summaries
           :actor-mailboxes (agent-session-actor-mailboxes session)
           :actor-runtime (and (fboundp 'serializable-actor-runtime-state)
                               (serializable-actor-runtime-state session))
           :pending-actions (agent-session-pending-actions session)
           :desktop-tasks (mapcar #'serializable-desktop-task-record
                                  (agent-session-desktop-tasks session))
           :incidents (agent-session-incidents session)
           :tasks (agent-session-tasks session)
           :workers (serializable-worker-states session)
           :summaries (list :agent-count (length (environment-agent-registry environment))
                            :subscription-count 0
                            :has-plan-p (not (null active-plan-id))
                            :active-plan-id active-plan-id
                            :plan-count (length plans)
                            :plan-summaries plan-summaries
                            :pending-action-count (length (agent-session-pending-actions session))
                            :desktop-task-count (length (agent-session-desktop-tasks session))
                            :incident-count (length (agent-session-incidents session))
                            :open-incident-count (length (remove-if-not (lambda (incident)
                                                                          (eq (incident-status incident) :open))
                                                                        (agent-session-incidents session)))
                            :incident-summary (environment-incident-summary-from-session session)
                            :task-count (length (agent-session-tasks session))
                            :worker-count (length (agent-session-workers session))
                            :active-worker-count (active-worker-count session)
                            :actor-runtime-history-count
                            (length (or (and (fboundp 'serializable-actor-runtime-state)
                                             (getf (serializable-actor-runtime-state session)
                                                   :recent-executions))
                                        '()))
                            :actor-runtime-submitted-job-count
                            (or (and (fboundp 'serializable-actor-runtime-state)
                                     (getf (serializable-actor-runtime-state session)
                                           :submitted-job-count))
                                0)
                            :actor-runtime-completed-job-count
                            (or (and (fboundp 'serializable-actor-runtime-state)
                                     (getf (serializable-actor-runtime-state session)
                                           :completed-job-count))
                                0)
                            :actor-runtime-failed-job-count
                            (or (and (fboundp 'serializable-actor-runtime-state)
                                     (getf (serializable-actor-runtime-state session)
                                           :failed-job-count))
                                0)
                            :memory-entry-count (length (environment-memory environment))))))
  environment)

(defun sync-environment-from-session (environment session)
  (ensure-default-thread session)
  (sync-environment-root-bindings-from-session environment session)
  (setf (environment-thread-set environment)
        (mapcar #'thread-record-summary (agent-session-threads session))
        (environment-active-thread-id environment)
        (agent-session-current-thread-id session)
        (environment-work-item-graph environment)
        (mapcar #'work-item-summary (agent-session-work-items session))
        (environment-event-log environment)
        (environment-event-log-from-session environment session))
  (sync-environment-domains-from-session environment session)
  (refresh-environment-artifact-index environment)
  environment)

(defun ensure-environment-agent-state (environment session)
  (or (environment-agent-state environment)
      (let* ((plans (session-plan-set session))
             (active-plan-id (session-active-plan-id session))
             (plan-summaries (session-plan-summaries session))
             (agent-state
              (make-environment-agent-state
               :agents (environment-agent-registry environment)
               :subscriptions '()
               :memory (environment-memory environment)
               :plan (session-active-plan session)
               :plans plans
               :active-plan-id active-plan-id
               :plan-summaries plan-summaries
               :actor-mailboxes (agent-session-actor-mailboxes session)
               :actor-runtime (and (fboundp 'serializable-actor-runtime-state)
                                   (serializable-actor-runtime-state session))
               :pending-actions (agent-session-pending-actions session)
               :desktop-tasks (agent-session-desktop-tasks session)
               :incidents (agent-session-incidents session)
               :tasks (agent-session-tasks session)
               :workers (serializable-worker-states session)
               :summaries (list :agent-count (length (environment-agent-registry environment))
                                :subscription-count 0
                                :has-plan-p (not (null active-plan-id))
                                :active-plan-id active-plan-id
                                :plan-count (length plans)
                                :plan-summaries plan-summaries
                                :pending-action-count (length (agent-session-pending-actions session))
                                :desktop-task-count (length (agent-session-desktop-tasks session))
                                :incident-count (length (agent-session-incidents session))
                                :open-incident-count (length (remove-if-not (lambda (incident)
                                                                              (eq (incident-status incident) :open))
                                                                            (agent-session-incidents session)))
                                :incident-summary (environment-incident-summary-from-session session)
                                :task-count (length (agent-session-tasks session))
                                :worker-count (length (agent-session-workers session))
                                :active-worker-count (active-worker-count session)
                                :actor-runtime-history-count
                                (length (or (and (fboundp 'serializable-actor-runtime-state)
                                                 (getf (serializable-actor-runtime-state session)
                                                       :recent-executions))
                                            '()))
                                :actor-runtime-submitted-job-count
                                (or (and (fboundp 'serializable-actor-runtime-state)
                                         (getf (serializable-actor-runtime-state session)
                                               :submitted-job-count))
                                    0)
                                :actor-runtime-completed-job-count
                                (or (and (fboundp 'serializable-actor-runtime-state)
                                         (getf (serializable-actor-runtime-state session)
                                               :completed-job-count))
                                    0)
                                :actor-runtime-failed-job-count
                                (or (and (fboundp 'serializable-actor-runtime-state)
                                         (getf (serializable-actor-runtime-state session)
                                               :failed-job-count))
                                    0)
                                :memory-entry-count (length (environment-memory environment))))))
        (setf (environment-agent-state environment) agent-state)
        agent-state)))

(defun refresh-environment-agent-domain (environment session)
  (let* ((agent-state (ensure-environment-agent-state environment session))
         (plans (session-plan-set session))
         (active-plan-id (session-active-plan-id session))
         (plan-summaries (session-plan-summaries session)))
    (setf (environment-agent-state-agents agent-state)
          (environment-agent-registry environment)
          (environment-agent-state-memory agent-state)
          (environment-memory environment)
          (environment-agent-state-plan agent-state)
          (session-active-plan session)
          (environment-agent-state-plans agent-state)
          plans
          (environment-agent-state-active-plan-id agent-state)
          active-plan-id
          (environment-agent-state-plan-summaries agent-state)
          plan-summaries
          (environment-agent-state-actor-mailboxes agent-state)
          (agent-session-actor-mailboxes session)
          (environment-agent-state-actor-runtime agent-state)
          (and (fboundp 'serializable-actor-runtime-state)
               (serializable-actor-runtime-state session))
          (environment-agent-state-pending-actions agent-state)
          (agent-session-pending-actions session)
          (environment-agent-state-desktop-tasks agent-state)
          (mapcar #'serializable-desktop-task-record
                  (agent-session-desktop-tasks session))
          (environment-agent-state-tasks agent-state)
          (agent-session-tasks session)
          (environment-agent-state-workers agent-state)
          (serializable-worker-states session)
          (environment-agent-state-summaries agent-state)
          (list :agent-count (length (environment-agent-registry environment))
                :subscription-count (length (environment-agent-state-subscriptions agent-state))
                :has-plan-p (not (null active-plan-id))
                :active-plan-id active-plan-id
                :plan-count (length plans)
                :plan-summaries plan-summaries
                :pending-action-count (length (environment-agent-state-pending-actions agent-state))
                :desktop-task-count (length (environment-agent-state-desktop-tasks agent-state))
                :incident-count (length (environment-agent-state-incidents agent-state))
                :open-incident-count (length (remove-if-not (lambda (incident)
                                                              (eq (incident-status incident) :open))
                                                            (environment-agent-state-incidents agent-state)))
                :incident-summary (session-incident-summary session)
                :task-count (length (environment-agent-state-tasks agent-state))
                :worker-count (length (environment-agent-state-workers agent-state))
                :active-worker-count (active-worker-count session)
                :actor-runtime-history-count
                (length (or (and (environment-agent-state-actor-runtime agent-state)
                                 (getf (environment-agent-state-actor-runtime agent-state)
                                       :recent-executions))
                            '()))
                :actor-runtime-submitted-job-count
                (or (and (environment-agent-state-actor-runtime agent-state)
                         (getf (environment-agent-state-actor-runtime agent-state)
                               :submitted-job-count))
                    0)
                :actor-runtime-completed-job-count
                (or (and (environment-agent-state-actor-runtime agent-state)
                         (getf (environment-agent-state-actor-runtime agent-state)
                               :completed-job-count))
                    0)
                :actor-runtime-failed-job-count
                (or (and (environment-agent-state-actor-runtime agent-state)
                         (getf (environment-agent-state-actor-runtime agent-state)
                               :failed-job-count))
                    0)
                :memory-entry-count (length (environment-memory environment))))
    environment))

(defun environment-append-incident (environment session incident)
  (let* ((agent-state (ensure-environment-agent-state environment session))
         (incidents (environment-agent-state-incidents agent-state)))
    (unless (find (incident-id incident) incidents
                  :key #'incident-id
                  :test #'string=)
      (setf (environment-agent-state-incidents agent-state)
            (append incidents (list incident))))
    (refresh-environment-agent-domain environment session)))

(defun make-default-environment (&key (storage-root (namestring (getcwd)))
                                      session)
  (let* ((active-session (or session
                             (make-default-session :cwd storage-root)))
         (environment (make-environment
                       :id (make-environment-id)
                       :schema-version +environment-schema-version+
                       :storage-root storage-root
                       :runtime-state nil
                       :conversation-state nil
                       :workflow-state nil
                       :agent-state nil
                       :runtime-set (list (list :id (default-runtime-id)
                                                :kind :sbcl
                                                :cwd (agent-session-cwd active-session)
                                                :package (agent-session-package active-session)
                                                :status :active))
                       :active-runtime-id (default-runtime-id)
                       :thread-set '()
                       :active-thread-id nil
                       :artifact-index '()
                       :work-item-graph '()
                       :policy-state '()
                       :agent-registry '()
                       :memory '()
                       :summaries '()
                       :event-log '()
                       :compatibility-session active-session
                       :metadata '())))
    (sync-environment-from-session environment active-session)))

(defun ensure-environment (&optional environment)
  (let ((active-environment
          (or environment
              *current-environment*
              (setf *current-environment*
                    (make-default-environment :session (or *current-session*
                                                           (setf *current-session*
                                                                 (make-default-session))))))))
    (let ((session (environment-compatibility-session active-environment)))
      (when (compatibility-session-materialized-p session)
        (setf *current-session* session)))
    active-environment))

(defun refresh-environment-root-state-from-session (environment session)
  (setf (environment-compatibility-session environment) session
        (environment-storage-root environment) (agent-session-cwd session)
        (environment-policy-state environment)
        (list :approved-policies (session-approved-policies session)
              :capability-grants (session-capability-grants-summary session)))
  (update-environment-root-summaries-from-session environment session)
  environment)
