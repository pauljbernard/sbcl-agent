(in-package #:sbcl-agent)

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
