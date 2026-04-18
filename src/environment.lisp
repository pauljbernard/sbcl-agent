(in-package #:sbcl-agent)

(defstruct environment-agent-state
  agents
  subscriptions
  memory
  plan
  pending-actions
  incidents
  tasks
  workers
  summaries)

(defstruct environment
  id
  schema-version
  storage-root
  runtime-state
  conversation-state
  workflow-state
  agent-state
  runtime-set
  active-runtime-id
  thread-set
  active-thread-id
  artifact-index
  work-item-graph
  policy-state
  agent-registry
  memory
  summaries
  event-log
  compatibility-session
  metadata)

(defparameter *current-environment* nil)
(defparameter +environment-schema-version+ 1)

(defun compatibility-session-id (sessionish)
  (typecase sessionish
    (agent-session (agent-session-id sessionish))
    (environment-compatibility-payload
     (environment-compatibility-payload-session-id sessionish))
    (t nil)))

(defun compatibility-session-materialized-p (sessionish)
  (typep sessionish 'agent-session))

(defun make-environment-id ()
  (format nil "environment-~D-~D" (get-universal-time) (random 1000000)))

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
  (update-environment-root-summaries-from-session environment session))

(defun sync-environment-runtime-history-from-session (environment session)
  (sync-environment-root-bindings-from-session environment session)
  (sync-environment-runtime-domain-from-session environment session)
  environment)

(defun sync-environment-domains-from-session (environment session)
  (sync-environment-runtime-domain-from-session environment session)
  (setf (environment-conversation-state environment)
        (make-environment-conversation-state-from-session session))
  (let ()
    (setf (environment-workflow-state environment)
          (make-environment-workflow-state-from-session session))
    (setf (environment-agent-state environment)
          (make-environment-agent-state
           :agents (environment-agent-registry environment)
           :subscriptions '()
           :memory (environment-memory environment)
           :plan (agent-session-plan session)
           :pending-actions (agent-session-pending-actions session)
           :incidents (agent-session-incidents session)
           :tasks (agent-session-tasks session)
           :workers (serializable-worker-states session)
           :summaries (list :agent-count (length (environment-agent-registry environment))
                            :subscription-count 0
                            :has-plan-p (not (null (agent-session-plan session)))
                            :pending-action-count (length (agent-session-pending-actions session))
                            :incident-count (length (agent-session-incidents session))
                            :open-incident-count (length (remove-if-not (lambda (incident)
                                                                          (eq (incident-status incident) :open))
                                                                        (agent-session-incidents session)))
                            :incident-summary (environment-incident-summary-from-session session)
                            :task-count (length (agent-session-tasks session))
                            :worker-count (length (agent-session-workers session))
                            :active-worker-count (active-worker-count session)
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

(defun session-bound-environment (session)
  (let ((environment (and (boundp '*current-environment*)
                          *current-environment*)))
    (when (and environment
               (eq (environment-compatibility-session environment) session))
      environment)))

(defun ensure-environment-agent-state (environment session)
  (or (environment-agent-state environment)
      (let ((agent-state
              (make-environment-agent-state
               :agents (environment-agent-registry environment)
               :subscriptions '()
               :memory (environment-memory environment)
               :plan (agent-session-plan session)
               :pending-actions (agent-session-pending-actions session)
               :incidents (agent-session-incidents session)
               :tasks (agent-session-tasks session)
               :workers (serializable-worker-states session)
               :summaries (list :agent-count (length (environment-agent-registry environment))
                                :subscription-count 0
                                :has-plan-p (not (null (agent-session-plan session)))
                                :pending-action-count (length (agent-session-pending-actions session))
                                :incident-count (length (agent-session-incidents session))
                                :open-incident-count (length (remove-if-not (lambda (incident)
                                                                              (eq (incident-status incident) :open))
                                                                            (agent-session-incidents session)))
                                :incident-summary (environment-incident-summary-from-session session)
                                :task-count (length (agent-session-tasks session))
                                :worker-count (length (agent-session-workers session))
                                :active-worker-count (active-worker-count session)
                                :memory-entry-count (length (environment-memory environment))))))
        (setf (environment-agent-state environment) agent-state)
        agent-state)))

(defun refresh-environment-agent-domain (environment session)
  (let ((agent-state (ensure-environment-agent-state environment session)))
    (setf (environment-agent-state-agents agent-state)
          (environment-agent-registry environment)
          (environment-agent-state-memory agent-state)
          (environment-memory environment)
          (environment-agent-state-plan agent-state)
          (agent-session-plan session)
          (environment-agent-state-pending-actions agent-state)
          (agent-session-pending-actions session)
          (environment-agent-state-tasks agent-state)
          (agent-session-tasks session)
          (environment-agent-state-workers agent-state)
          (serializable-worker-states session)
          (environment-agent-state-summaries agent-state)
          (list :agent-count (length (environment-agent-registry environment))
                :subscription-count (length (environment-agent-state-subscriptions agent-state))
                :has-plan-p (not (null (environment-agent-state-plan agent-state)))
                :pending-action-count (length (environment-agent-state-pending-actions agent-state))
                :incident-count (length (environment-agent-state-incidents agent-state))
                :open-incident-count (length (remove-if-not (lambda (incident)
                                                              (eq (incident-status incident) :open))
                                                            (environment-agent-state-incidents agent-state)))
                :incident-summary (session-incident-summary session)
                :task-count (length (environment-agent-state-tasks agent-state))
                :worker-count (length (environment-agent-state-workers agent-state))
                :active-worker-count (active-worker-count session)
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

(defun environment-session (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (let ((session (environment-compatibility-session active-environment)))
      (when (typep session 'environment-compatibility-payload)
        (setf session (compatibility-payload->session session active-environment)
              (environment-compatibility-session active-environment) session))
      (when session
        (setf *current-session* session))
      session)))

(defun bind-session-to-environment (session &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (setf (environment-compatibility-session active-environment) session
          *current-session* session
          *current-environment* active-environment)
    (sync-environment-from-session active-environment session)))

(defun refresh-environment-root-state-from-session (environment session)
  (setf (environment-compatibility-session environment) session
        (environment-storage-root environment) (agent-session-cwd session)
        (environment-policy-state environment)
        (list :approved-policies (session-approved-policies session)
              :capability-grants (session-capability-grants-summary session)))
  (update-environment-root-summaries-from-session environment session)
  environment)

(defun environment-summary-count (primary fallback)
  (if (and (integerp primary) (not (minusp primary)))
      primary
      fallback))

(defun event-summary-kind-counts (events)
  (let ((counts '()))
    (dolist (event events)
      (let* ((kind (event-kind event))
             (existing (find kind counts
                             :key (lambda (entry) (getf entry :kind))
                             :test #'eq)))
        (if existing
            (incf (getf existing :count))
            (setf counts (append counts (list (list :kind kind :count 1)))))))
    counts))

(defun event-summary-family-counts (events)
  (let ((counts '()))
    (dolist (event events)
      (let* ((family (event-family event))
             (existing (find family counts
                             :key (lambda (entry) (getf entry :family))
                             :test #'eq)))
        (if existing
            (incf (getf existing :count))
            (setf counts (append counts (list (list :family family :count 1)))))))
    counts))

(defun recent-event-kinds (events &key (limit 8))
  (mapcar #'event-kind
          (let ((count (length events)))
            (if (> count limit)
                (subseq events (- count limit))
                events))))

(defun environment-event-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (events (or (environment-event-log active-environment) '()))
         (kind-counts (event-summary-kind-counts events))
         (family-counts (event-summary-family-counts events)))
    (list :event-count (length events)
          :kind-counts kind-counts
          :family-counts family-counts
          :recent-kinds (recent-event-kinds events)
          :provider-stream-count (or (getf (find :provider-stream kind-counts
                                                :key (lambda (entry) (getf entry :kind))
                                                :test #'eq)
                                           :count)
                                     0)
          :validation-count (or (getf (find :validation-completed kind-counts
                                            :key (lambda (entry) (getf entry :kind))
                                            :test #'eq)
                                       :count)
                                 0)
          :reconciliation-count (or (getf (find :reconciliation-created kind-counts
                                                :key (lambda (entry) (getf entry :kind))
                                                :test #'eq)
                                           :count)
                                     0)
          :incident-count (or (getf (find :incident-created kind-counts
                                          :key (lambda (entry) (getf entry :kind))
                                          :test #'eq)
                                     :count)
                              0)
          :workflow-transition-count (loop for entry in kind-counts
                                           when (member (getf entry :kind)
                                                        '(:workflow-record-created
                                                          :workflow-record-quarantined
                                                          :workflow-record-resumed
                                                          :workflow-record-closed
                                                          :work-item-created)
                                                        :test #'eq)
                                           sum (getf entry :count)))))

(defun environment-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (session (environment-compatibility-session active-environment)))
    (let* ((runtime-state (environment-runtime-state active-environment))
           (conversation-state (environment-conversation-state active-environment))
           (agent-state (environment-agent-state active-environment))
           (root-summary (environment-summaries active-environment))
           (conversation-summary (environment-conversation-domain-summary active-environment))
           (workflow-summary (environment-workflow-domain-summary active-environment))
           (agent-summary (and agent-state
                               (environment-agent-state-summaries agent-state)))
           (runtime-summary (environment-runtime-domain-summary active-environment)))
      (list :id (environment-id active-environment)
            :schema-version (environment-schema-version active-environment)
            :storage-root (environment-storage-root active-environment)
            :active-runtime-id (environment-active-runtime-id active-environment)
            :runtime-count (length (environment-runtime-set active-environment))
            :active-thread-id (environment-summary-active-thread-id active-environment)
            :thread-count (environment-summary-count
                           (getf conversation-summary :thread-count)
                           (length (environment-thread-set active-environment)))
            :artifact-count (environment-summary-count
                             (getf conversation-summary :artifact-count)
                             (environment-artifact-count active-environment))
            :work-item-count (environment-summary-count
                              (getf workflow-summary :work-item-count)
                              (length (environment-work-item-graph active-environment)))
            :agent-count (environment-summary-count
                          (getf agent-summary :agent-count)
                          (length (environment-agent-registry active-environment)))
            :event-count (length (environment-event-log active-environment))
            :runtime-state runtime-summary
            :runtime-history-count (length (or (and runtime-state
                                                   (environment-runtime-state-eval-history runtime-state))
                                              '()))
            :conversation-state conversation-summary
            :workflow-state workflow-summary
            :agent-state agent-summary
            :session-id (compatibility-session-id session)
            :plan (or (and agent-state
                           (environment-agent-state-plan agent-state))
                      (getf root-summary :plan))
            :event-summary (environment-event-summary active-environment)
            :artifact-summary (or (environment-artifact-summary active-environment)
                                  (getf root-summary :artifact-summary))
            :incident-count (or (getf agent-summary :incident-count)
                                (getf root-summary :incident-count))
            :incident-summary (or (getf agent-summary :incident-summary)
                                  (getf root-summary :incident-summary))
            :operator-status (getf root-summary :operator-status)
            :has-session-p (not (null (compatibility-session-id session)))))))

(defun summarize-operator-blockers (operator-status)
  (let* ((blocked (append (or (getf operator-status :blocked-work-items) '())
                          (or (getf operator-status :quarantined-work-items) '()))))
    (list :count (length blocked)
          :approval-count (count :approval-required blocked :key (lambda (entry) (getf entry :why)) :test #'eq)
          :cold-validation-count (count :cold-validation-required blocked :key (lambda (entry) (getf entry :why)) :test #'eq)
          :pending-validation-count (count :pending-validation blocked :key (lambda (entry) (getf entry :why)) :test #'eq)
          :operator-review-count (count :operator-review-required blocked :key (lambda (entry) (getf entry :why)) :test #'eq)
          :items blocked)))

(defun environment-operator-evidence (summary)
  (let* ((operator-status (or (getf summary :operator-status) '()))
         (incident-summary (or (getf summary :incident-summary)
                               (list :count 0 :open-count 0 :recent '())))
         (event-summary (or (getf summary :event-summary)
                            (list :event-count 0 :recent-kinds '())))
         (blocked-summary (summarize-operator-blockers operator-status)))
    (list :posture (list :ready-count (getf operator-status :ready-count)
                         :blocked-count (getf operator-status :blocked-count)
                         :quarantined-count (getf operator-status :quarantined-count)
                         :image-only-count (getf operator-status :image-only-count)
                         :durable-count (getf operator-status :durable-count)
                         :incident-count (getf operator-status :incident-count)
                         :open-incident-count (getf operator-status :open-incident-count))
          :blocked-work blocked-summary
          :incidents incident-summary
          :events event-summary)))

(defun environment-status (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (summary (environment-summary active-environment))
         (operator-evidence (environment-operator-evidence summary))
         (operator-status (getf operator-evidence :posture))
         (active-thread (environment-active-thread-summary active-environment))
         (active-turn (environment-active-turn-summary active-environment))
         (blocked-summary (getf operator-evidence :blocked-work))
         (incident-summary (getf operator-evidence :incidents))
         (runtime-state (getf summary :runtime-state)))
    (list :environment (list :id (getf summary :id)
                             :schema-version (getf summary :schema-version)
                             :storage-root (getf summary :storage-root)
                             :has-session-p (getf summary :has-session-p))
          :active-thread active-thread
          :active-turn active-turn
          :active-runtime (list :runtime-id (getf summary :active-runtime-id)
                                :runtime-count (getf summary :runtime-count)
                                :package (getf runtime-state :package)
                                :loaded-system-count (or (getf runtime-state :loaded-system-count) 0)
                                :summary runtime-state)
          :blocked-work blocked-summary
          :incidents incident-summary
          :operator-posture (append operator-status
                                    (list :outstanding-approval-count (getf blocked-summary :approval-count)
                                          :outstanding-cold-validation-count (getf blocked-summary :cold-validation-count)
                                          :outstanding-pending-validation-count (getf blocked-summary :pending-validation-count)
                                          :outstanding-operator-review-count (getf blocked-summary :operator-review-count)))
          :operator-evidence operator-evidence
          :summary summary)))
