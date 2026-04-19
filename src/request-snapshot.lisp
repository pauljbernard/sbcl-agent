(in-package #:sbcl-agent)

(defstruct provider-environment-snapshot
  environment
  environment-summary
  conversation-state
  workflow-state
  incident-summary)

(defstruct provider-context-bundle
  snapshot
  session-summary
  thread-context
  turn-context
  environment-context
  runtime-summary
  workspace-summary
  policy-summary)

(defstruct provider-request-snapshot
  session-summary
  thread-context
  turn-context
  environment-context
  runtime-summary
  workspace-summary
  policy-summary)

(defun provider-bound-environment (session)
  (let ((environment (and (boundp '*current-environment*)
                          *current-environment*)))
    (when (and environment
               (eq (environment-compatibility-session environment) session))
      environment)))

(defun build-provider-environment-snapshot (session)
  (let ((environment (provider-bound-environment session)))
    (when environment
      (make-provider-environment-snapshot
       :environment environment
       :environment-summary (environment-summary environment)
       :conversation-state (environment-conversation-state environment)
       :workflow-state (environment-workflow-state environment)
       :incident-summary (getf (environment-summaries environment) :incident-summary)))))

(defun ensure-provider-environment-snapshot (session snapshot)
  (or snapshot
      (build-provider-environment-snapshot session)))

(defun provider-snapshot-environment-summary-value (snapshot key)
  (and snapshot
       (getf (provider-environment-snapshot-environment-summary snapshot) key)))

(defun provider-snapshot-runtime-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :runtime-state)
             key)))

(defun provider-snapshot-conversation-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :conversation-state)
             key)))

(defun provider-snapshot-workflow-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :workflow-state)
             key)))

(defun provider-snapshot-agent-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :agent-state)
             key)))

(defun provider-snapshot-policy-state-value (snapshot key)
  (let ((environment (and snapshot
                          (provider-environment-snapshot-environment snapshot))))
    (and environment
         (getf (environment-policy-state environment) key))))

(defun provider-snapshot-open-incident-count (snapshot)
  (and snapshot
       (getf (provider-snapshot-environment-summary-value snapshot :incident-summary)
             :open-count)))

(defun provider-snapshot-operator-status-value (snapshot key)
  (and snapshot
       (getf (provider-snapshot-environment-summary-value snapshot :operator-status)
             key)))

(defun provider-session-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :id (provider-snapshot-environment-summary-value snapshot :session-id)
              :cwd (provider-snapshot-environment-summary-value snapshot :storage-root)
              :package (provider-snapshot-runtime-summary-value snapshot :package)
              :current-thread-id (provider-snapshot-environment-summary-value snapshot :active-thread-id)
              :thread-count (provider-snapshot-environment-summary-value snapshot :thread-count)
              :message-count (provider-snapshot-conversation-summary-value snapshot :message-count)
              :turn-count (provider-snapshot-conversation-summary-value snapshot :turn-count)
              :operation-count (provider-snapshot-conversation-summary-value snapshot :operation-count)
              :incident-count (provider-snapshot-environment-summary-value snapshot :incident-count)
              :open-incident-count (provider-snapshot-open-incident-count snapshot)
              :plan (provider-snapshot-environment-summary-value snapshot :plan)
              :approved-policies (provider-snapshot-policy-state-value snapshot :approved-policies)
              :pending-action-count (provider-snapshot-agent-summary-value snapshot :pending-action-count)
              :active-worker-count (provider-snapshot-agent-summary-value snapshot :active-worker-count)
              :environment-id (and environment (environment-id environment))
              :active-runtime-id (and environment (environment-active-runtime-id environment))
              :artifact-summary (provider-snapshot-environment-summary-value snapshot :artifact-summary)
              :transcript-count (length (agent-session-transcript session))
              :recent-transcript (mapcar #'provider-transcript-entry
                                         (recent-session-transcript session)))
        (list :id (agent-session-id session)
              :cwd (agent-session-cwd session)
              :package (agent-session-package session)
              :current-thread-id (agent-session-current-thread-id session)
              :thread-count (length (agent-session-threads session))
              :message-count (length (agent-session-messages session))
              :turn-count (length (agent-session-turns session))
              :operation-count (length (agent-session-operations session))
              :incident-count (length (agent-session-incidents session))
              :open-incident-count (getf (session-incident-summary session) :open-count)
              :plan (agent-session-plan session)
              :approved-policies (session-approved-policies session)
              :pending-action-count (length (agent-session-pending-actions session))
              :active-worker-count (active-worker-count session)
              :environment-id nil
              :active-runtime-id nil
              :artifact-summary (session-artifact-summary session)
              :transcript-count (length (agent-session-transcript session))
              :recent-transcript (mapcar #'provider-transcript-entry
                                         (recent-session-transcript session))))))

(defun provider-runtime-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :cwd (provider-snapshot-environment-summary-value snapshot :storage-root)
              :package (provider-snapshot-runtime-summary-value snapshot :package)
              :approved-policies (provider-snapshot-policy-state-value snapshot :approved-policies)
              :pending-action-count (provider-snapshot-agent-summary-value snapshot :pending-action-count)
              :active-worker-count (provider-snapshot-agent-summary-value snapshot :active-worker-count)
              :incident-count (provider-snapshot-environment-summary-value snapshot :incident-count)
              :open-incident-count (provider-snapshot-open-incident-count snapshot)
              :environment-id (and environment (environment-id environment))
              :active-runtime-id (and environment (environment-active-runtime-id environment)))
        (list :cwd (agent-session-cwd session)
              :package (agent-session-package session)
              :approved-policies (session-approved-policies session)
              :pending-action-count (length (agent-session-pending-actions session))
              :active-worker-count (active-worker-count session)
              :incident-count (length (agent-session-incidents session))
              :open-incident-count (getf (session-incident-summary session) :open-count)
              :environment-id nil
              :active-runtime-id nil))))

(defun provider-workspace-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :cwd (provider-snapshot-environment-summary-value snapshot :storage-root)
              :artifact-count (provider-snapshot-environment-summary-value snapshot :artifact-count)
              :artifact-summary (provider-snapshot-environment-summary-value snapshot :artifact-summary)
              :work-item-count (provider-snapshot-environment-summary-value snapshot :work-item-count)
              :workflow-record-count (provider-snapshot-workflow-summary-value snapshot :workflow-record-count)
              :incident-count (provider-snapshot-environment-summary-value snapshot :incident-count)
              :quarantined-work-item-count (provider-snapshot-operator-status-value snapshot :quarantined-count)
              :environment-id (and environment (environment-id environment)))
        (list :cwd (agent-session-cwd session)
              :artifact-count (length (agent-session-artifacts session))
              :artifact-summary (session-artifact-summary session)
              :work-item-count (length (agent-session-work-items session))
              :workflow-record-count (length (agent-session-workflow-records session))
              :incident-count (length (agent-session-incidents session))
              :quarantined-work-item-count (getf (session-operator-status session) :quarantined-count)
              :environment-id nil))))

(defun provider-policy-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :approved-policies (provider-snapshot-policy-state-value snapshot :approved-policies)
              :capability-grants (provider-snapshot-policy-state-value snapshot :capability-grants)
              :open-incident-count (provider-snapshot-open-incident-count snapshot)
              :environment-id (and environment (environment-id environment)))
        (list :approved-policies (session-approved-policies session)
              :capability-grants (session-capability-grants-summary session)
              :open-incident-count (getf (session-incident-summary session) :open-count)
              :environment-id nil))))

(defun provider-thread-context (session &optional thread snapshot)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (active-thread (or thread
                            (and snapshot
                                 (environment-active-thread-summary
                                  (provider-environment-snapshot-environment snapshot)))
                            (current-thread session))))
    (when active-thread
      (if (typep active-thread 'thread)
          (thread-record-summary active-thread)
          active-thread))))

(defun provider-turn-context (session &optional turn snapshot)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (active-turn (or turn
                          (and snapshot
                               (environment-active-turn-summary
                                (provider-environment-snapshot-environment snapshot)))
                          (most-recent-thread-turn session))))
    (when active-turn
      (if (typep active-turn 'turn)
          (turn-detail session (turn-id active-turn))
          active-turn))))

(defun limited-record-refs (records id-key &key (limit 5) extra-keys)
  (mapcar (lambda (record)
            (append (list :id (getf record id-key))
                    (loop for key in extra-keys
                          append (list key (getf record key)))))
          (subseq records 0 (min limit (length records)))))

(defun provider-work-item-refs (work-items &key (limit 5))
  (limited-record-refs (mapcar #'work-item-summary work-items)
                       :id
                       :limit limit
                       :extra-keys '(:status :goal :closure-decision)))

(defun provider-environment-context (session &optional snapshot)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot
                           (provider-environment-snapshot-environment snapshot))))
    (when environment
      (let* ((conversation-state (provider-environment-snapshot-conversation-state snapshot))
             (workflow-state (provider-environment-snapshot-workflow-state snapshot))
             (conversation-summary (and conversation-state
                                        (environment-conversation-state-summaries conversation-state)))
             (workflow-summary (and workflow-state
                                    (environment-workflow-state-summaries workflow-state)))
             (threads (and conversation-state
                           (environment-conversation-state-threads conversation-state)))
             (artifacts (and conversation-state
                             (environment-conversation-state-artifacts conversation-state)))
             (work-items (and workflow-state
                              (environment-workflow-state-work-items workflow-state)))
             (incidents (provider-environment-snapshot-incident-summary snapshot)))
        (list :environment-id (environment-id environment)
              :active-runtime-id (environment-active-runtime-id environment)
              :active-thread-id (environment-active-thread-id environment)
              :thread-count (getf conversation-summary :thread-count)
              :artifact-count (getf conversation-summary :artifact-count)
              :work-item-count (getf workflow-summary :work-item-count)
              :reconciliation-count (getf workflow-summary :reconciliation-count)
              :open-incident-count (getf incidents :open-count)
              :thread-refs (limited-record-refs threads :id :extra-keys '(:title :status))
              :artifact-refs (limited-record-refs artifacts :id :extra-keys '(:kind :title :turn-id))
              :work-item-refs (provider-work-item-refs work-items)
              :recent-incident-refs (limited-record-refs (or (getf incidents :recent) '())
                                                         :id
                                                         :extra-keys '(:kind :status :turn-id)))))))

(defun build-provider-context-bundle (session &key thread turn)
  (ensure-default-thread session)
  (let* ((snapshot (build-provider-environment-snapshot session))
         (thread-context (provider-thread-context session thread snapshot))
         (turn-context (provider-turn-context session turn snapshot)))
    (make-provider-context-bundle
     :snapshot snapshot
     :session-summary (provider-session-summary session snapshot)
     :thread-context thread-context
     :turn-context turn-context
     :environment-context (provider-environment-context session snapshot)
     :runtime-summary (provider-runtime-summary session snapshot)
     :workspace-summary (provider-workspace-summary session snapshot)
     :policy-summary (provider-policy-summary session snapshot))))

(defun provider-context-bundle->request-snapshot (bundle)
  (when bundle
    (make-provider-request-snapshot
     :session-summary (provider-context-bundle-session-summary bundle)
     :thread-context (provider-context-bundle-thread-context bundle)
     :turn-context (provider-context-bundle-turn-context bundle)
     :environment-context (provider-context-bundle-environment-context bundle)
     :runtime-summary (provider-context-bundle-runtime-summary bundle)
     :workspace-summary (provider-context-bundle-workspace-summary bundle)
     :policy-summary (provider-context-bundle-policy-summary bundle))))

(defun make-provider-request-from-snapshot (prompt request-snapshot
                                           &key (operator-mode :repl-bridge)
                                             stream-p)
  (make-provider-request :prompt prompt
                         :session-summary (and request-snapshot
                                               (provider-request-snapshot-session-summary request-snapshot))
                         :thread-context (and request-snapshot
                                              (provider-request-snapshot-thread-context request-snapshot))
                         :turn-context (and request-snapshot
                                            (provider-request-snapshot-turn-context request-snapshot))
                         :environment-context (and request-snapshot
                                                  (provider-request-snapshot-environment-context request-snapshot))
                         :runtime-summary (and request-snapshot
                                               (provider-request-snapshot-runtime-summary request-snapshot))
                         :workspace-summary (and request-snapshot
                                                 (provider-request-snapshot-workspace-summary request-snapshot))
                         :policy-summary (and request-snapshot
                                              (provider-request-snapshot-policy-summary request-snapshot))
                         :operator-mode operator-mode
                         :stream-p stream-p))

(defun make-provider-request-from-session (prompt session
                                          &key thread turn
                                            (operator-mode :repl-bridge)
                                            stream-p)
  (let* ((active-session (or session (ignore-errors (ensure-session))))
         (bundle (and active-session
                      (build-provider-context-bundle active-session
                                                     :thread thread
                                                     :turn turn)))
         (request-snapshot (provider-context-bundle->request-snapshot bundle)))
    (make-provider-request-from-snapshot prompt
                                         request-snapshot
                                         :operator-mode operator-mode
                                         :stream-p stream-p)))
