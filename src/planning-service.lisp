(in-package #:sbcl-agent)

(defun active-plan-or-error (session &optional plan-id)
  (let ((plan (session-active-plan session)))
    (unless plan
      (error "No active plan is available"))
    (when (and plan-id
               (not (string= plan-id (plan-record-id plan))))
      (error "Unknown plan ~A" plan-id))
    plan))

(defun resolve-session-plan (session plan-id)
  (find plan-id (session-plan-set session)
        :key #'plan-record-id :test #'string=))

(defun resolve-orchestration-focus (session &key plan-id workflow-record-id work-item-id)
  (cond
    (plan-id
     (let ((plan (resolve-session-plan session plan-id)))
       (unless plan
         (error "Unknown plan ~A" plan-id))
       (values plan :plan-id nil nil)))
    (workflow-record-id
     (let* ((workflow-record (find-workflow-record session workflow-record-id))
            (resolved-plan-id (and workflow-record
                                   (workflow-record-plan-id workflow-record)))
            (plan (and resolved-plan-id
                       (resolve-session-plan session resolved-plan-id))))
       (unless workflow-record
         (error "Unknown workflow record ~A" workflow-record-id))
       (unless plan
         (error "Workflow record ~A is not linked to a known plan" workflow-record-id))
       (values plan :workflow-record-id workflow-record nil)))
    (work-item-id
     (let* ((work-item (find-work-item session work-item-id))
            (workflow-record (and work-item
                                  (work-item-workflow-record session work-item)))
            (resolved-plan-id (and workflow-record
                                   (workflow-record-plan-id workflow-record)))
            (plan (and resolved-plan-id
                       (resolve-session-plan session resolved-plan-id))))
       (unless work-item
         (error "Unknown work-item ~A" work-item-id))
       (unless workflow-record
         (error "Work-item ~A is not linked to a workflow record" work-item-id))
       (unless plan
         (error "Work-item ~A does not resolve to a known plan" work-item-id))
       (values plan :work-item-id workflow-record work-item)))
    (t
     (let ((plan (session-active-plan session)))
       (unless plan
         (error "No active plan is available"))
       (values plan :active-plan nil nil)))))

(defun planning-service-step-or-error (session plan-id step-id)
  (let* ((plan (active-plan-or-error session plan-id))
         (step (find-plan-step plan step-id)))
    (unless step
      (error "Unknown plan step ~A" step-id))
    (values plan step)))

(defun plan-list-data (session)
  (mapcar #'plan-record-summary (session-plan-set session)))

(defun approval-summary-fields (approval-summary)
  (when approval-summary
    (list :approval-id (getf approval-summary :approval-id)
          :approval-ids (getf approval-summary :approval-ids)
          :actor-message-id (getf approval-summary :actor-message-id)
          :actor-message-ids (getf approval-summary :actor-message-ids)
          :pending-action-id (getf approval-summary :pending-action-id)
          :pending-action-ids (getf approval-summary :pending-action-ids)
          :policy-id (getf approval-summary :policy-id)
          :policy-ids (getf approval-summary :policy-ids)
          :session-id (getf approval-summary :session-id)
          :thread-id (getf approval-summary :thread-id)
          :turn-id (getf approval-summary :turn-id)
          :record-ids (getf approval-summary :record-ids)
          :approve-command (getf approval-summary :approve-command)
          :ack-command (getf approval-summary :ack-command)
          :dequeue-command (getf approval-summary :dequeue-command))))

(defun primary-command-fields (command)
  (when command
    (list :primary-command-kind (getf command :kind)
          :primary-command-label (getf command :label)
          :primary-command-description (getf command :description)
          :primary-command-operator (getf command :operator)
          :primary-command-provider-required-p (getf command :provider-required-p))))

(defun orchestration-command-summary (command)
  (when command
    (list :kind (getf command :kind)
          :label (getf command :label)
          :description (getf command :description)
          :operator (getf command :operator)
          :provider-required-p (getf command :provider-required-p))))

(defun approval-command-summary (operator approval-summary
                                 &key include-actor-message-id-p include-mailbox-entry-id-p)
  (when approval-summary
    (let* ((approval-id (getf approval-summary :approval-id))
           (session-id (getf approval-summary :session-id))
           (actor-message-id (and include-actor-message-id-p
                                  (getf approval-summary :actor-message-id)))
           (mailbox-entry-id (and include-mailbox-entry-id-p
                                  (or (getf approval-summary :mailbox-entry-id)
                                      (first (getf approval-summary :mailbox-entry-ids)))))
           (payload
             (append
              (when approval-id
                (list :approval-id approval-id))
              (when session-id
                (list :session-id session-id))
              (when actor-message-id
                (list :actor-message-id actor-message-id))
              (when mailbox-entry-id
                (list :mailbox-entry-id mailbox-entry-id)))))
      (when payload
        (append
         (case (intern (string-upcase operator) :keyword)
           (:|DESKTOP-TASK/APPROVE-APPROVAL|
            (list :kind :grant-approval
                  :label "Approve"
                  :description "Approve the governed action and continue execution."))
           (:|DESKTOP-TASK/ACK-CONTEXT-CHAT-APPROVAL|
            (list :kind :acknowledge-approval
                  :label "Acknowledge"
                  :description "Acknowledge the approval prompt in the conversation inbox."))
           (:|DESKTOP-TASK/DEQUEUE-GOVERNANCE-APPROVAL|
            (list :kind :dismiss-approval
                  :label "Dismiss"
                  :description "Dismiss or dequeue the governance approval entry."))
           (otherwise
            nil))
         (list :operator operator
               :provider-required-p t
               :payload payload))))))

(defun approval-approve-command-summary (approval-summary)
  (approval-command-summary "desktop-task/approve-approval" approval-summary))

(defun approval-ack-command-summary (approval-summary)
  (approval-command-summary "desktop-task/ack-context-chat-approval"
                            approval-summary
                            :include-actor-message-id-p t
                            :include-mailbox-entry-id-p t))

(defun approval-dequeue-command-summary (approval-summary)
  (approval-command-summary "desktop-task/dequeue-governance-approval"
                            approval-summary
                            :include-actor-message-id-p t
                            :include-mailbox-entry-id-p t))

(defun orchestration-available-commands (approval-summary)
  (remove nil
          (list (approval-approve-command-summary approval-summary)
                (approval-ack-command-summary approval-summary)
                (approval-dequeue-command-summary approval-summary))))

(defun orchestration-primary-command (summary approval-summary)
  (case (orchestration-inbox-action summary)
    (:grant-approval
     (approval-approve-command-summary approval-summary))
    (:operator-review
     (or (approval-dequeue-command-summary approval-summary)
         (approval-ack-command-summary approval-summary)))
    (otherwise
     nil)))

(defun available-command-summaries (commands)
  (remove nil (mapcar #'orchestration-command-summary commands)))

(defun plan-orchestration-summary (session plan)
  (let* ((workflow-record (plan-linked-workflow-record session plan))
         (verification-summary (plan-verification-summary session plan))
         (latest-step (latest-plan-step plan))
         (approval-summary (getf verification-summary :approval-summary))
         (posture-summary (workflow-posture-summary workflow-record
                                                    (getf verification-summary
                                                          :latest-evidence-summary)))
         (summary
           (list :id (plan-record-id plan)
                 :goal (plan-record-goal plan)
                 :status (plan-record-status plan)
                 :active-plan-p (string= (plan-record-id plan)
                                         (or (session-active-plan-id session) ""))
                 :workflow-record-id (and workflow-record
                 (workflow-record-id workflow-record))
                 :workflow-status (and workflow-record
                                       (workflow-record-status workflow-record))
                 :approval-summary approval-summary
                 :posture-summary posture-summary
                 :latest-step-summary (and latest-step
                                           (plan-step-orchestration-summary latest-step))
                 :verification-summary
                 (list :verified-step-count (getf verification-summary :verified-step-count)
                       :failed-step-count (getf verification-summary :failed-step-count)
                       :pending-step-count (getf verification-summary :pending-step-count)
                       :latest-evidence-summary (getf verification-summary :latest-evidence-summary))))
         (primary-command (orchestration-primary-command summary approval-summary))
         (available-commands (orchestration-available-commands approval-summary))
         (available-command-summaries (available-command-summaries available-commands)))
    (append
     (append summary
             (list :primary-command primary-command
                   :available-commands available-commands
                   :available-command-summaries available-command-summaries
                   :available-command-count (length available-commands))
             (primary-command-fields primary-command))
     (approval-summary-fields approval-summary))))

(defun orchestration-actionable-p (summary)
  (let ((posture (getf summary :posture-summary))
        (status (getf summary :status)))
    (or (eq status :awaiting-approval)
        (eq status :quarantined)
        (eq (getf posture :waiting-on) :approval)
        (eq (getf posture :waiting-on) :operator-review)
        (and (getf posture :next-action) t)
        (> (or (getf (getf summary :verification-summary) :failed-step-count) 0) 0)
        (> (or (getf (getf summary :verification-summary) :pending-step-count) 0) 0))))

(defun orchestration-inbox-action (summary)
  (let ((posture (getf summary :posture-summary))
        (verification (getf summary :verification-summary))
        (status (getf summary :status)))
    (cond ((or (eq status :awaiting-approval)
               (eq (getf posture :waiting-on) :approval)
               (getf posture :approval-required-p))
           :grant-approval)
          ((or (eq status :quarantined)
               (eq (getf posture :waiting-on) :operator-review)
               (getf posture :quarantine-reason))
           :operator-review)
          ((> (or (getf verification :failed-step-count) 0) 0)
           :repair-or-replan)
          ((> (or (getf verification :pending-step-count) 0) 0)
           :verify-and-continue)
          ((getf posture :next-action)
           :continue)
          (t
           :inspect))))

(defun orchestration-inbox-urgency (summary)
  (let ((posture (getf summary :posture-summary))
        (verification (getf summary :verification-summary))
        (status (getf summary :status)))
    (cond ((or (eq status :awaiting-approval)
               (eq status :quarantined)
               (eq (getf posture :waiting-on) :approval)
               (eq (getf posture :waiting-on) :operator-review))
           :high)
          ((> (or (getf verification :failed-step-count) 0) 0)
           :high)
          ((> (or (getf verification :pending-step-count) 0) 0)
           :medium)
          ((getf posture :next-action)
           :medium)
          (t
           :low))))

(defun orchestration-inbox-entry (summary)
  (let* ((posture (getf summary :posture-summary))
         (latest-step (getf summary :latest-step-summary))
         (verification (getf summary :verification-summary))
         (approval-summary (getf summary :approval-summary))
         (entry
          (list :id (getf summary :id)
                :goal (getf summary :goal)
                :status (getf summary :status)
                :workflow-record-id (getf summary :workflow-record-id)
                :workflow-status (getf summary :workflow-status)
                :waiting-on (getf posture :waiting-on)
                :action (orchestration-inbox-action summary)
                :urgency (orchestration-inbox-urgency summary)
                :approval-required-p (getf posture :approval-required-p)
                :approval-summary approval-summary
                :next-action (getf posture :next-action)
                :resume-payload (getf posture :resume-payload)
                :quarantine-reason (getf posture :quarantine-reason)
                :latest-step-summary latest-step
                :verified-step-count (getf verification :verified-step-count)
                :failed-step-count (getf verification :failed-step-count)
                :pending-step-count (getf verification :pending-step-count)
                :latest-evidence-summary (getf verification :latest-evidence-summary))))
    (let* ((primary-command (orchestration-primary-command entry approval-summary))
           (available-commands (orchestration-available-commands approval-summary))
           (available-command-summaries (available-command-summaries available-commands)))
      (append
       (append entry
               (list :primary-command primary-command
                     :available-commands available-commands
                     :available-command-summaries available-command-summaries
                     :available-command-count (length available-commands))
               (primary-command-fields primary-command))
       (approval-summary-fields approval-summary)))))

(defun plan-linked-workflow-record (session plan)
  (or (and (plan-record-workflow-record-id plan)
           (find-workflow-record session (plan-record-workflow-record-id plan)))
      (find-workflow-record-by-plan-id session (plan-record-id plan))))

(defun latest-plan-step-evidence (step)
  (car (last (or (plan-step-evidence step) '()))))

(defun latest-plan-step (plan)
  (car (last (or (plan-record-steps plan) '()))))

(defun normalized-string-list (&rest groups)
  (remove-duplicates
   (remove nil
           (apply #'append
                  (mapcar (lambda (group)
                            (cond ((null group) '())
                                  ((listp group) group)
                                  (t (list group))))
                          groups)))
   :test #'string=))

(defun normalized-eq-list (&rest groups)
  (remove-duplicates
   (remove nil
           (apply #'append
                  (mapcar (lambda (group)
                            (cond ((null group) '())
                                  ((listp group) group)
                                  (t (list group))))
                          groups)))
   :test #'eq))

(defun summarized-runtime-post-state (post-state)
  (when (listp post-state)
    (let ((runtime-summary (getf post-state :runtime-summary))
          (describe-symbol (getf post-state :describe-symbol))
          (source-image-divergence (getf post-state :source-image-divergence)))
      (list :package (or (getf post-state :package)
                         (and (listp runtime-summary)
                              (getf runtime-summary :package)))
            :runtime-id (and (listp runtime-summary)
                             (getf runtime-summary :runtime-id))
            :loaded-system-count (and (listp runtime-summary)
                                      (getf runtime-summary :loaded-system-count))
            :symbol (and (listp describe-symbol)
                         (getf describe-symbol :symbol))
            :fboundp (and (listp describe-symbol)
                          (getf describe-symbol :fboundp))
            :home-package (and (listp describe-symbol)
                               (getf describe-symbol :home-package))
            :divergence (and (listp source-image-divergence)
                             (getf source-image-divergence :divergence))
            :runtime-present-p (and (listp source-image-divergence)
                                    (getf source-image-divergence :runtime-present-p))
            :source-present-p (and (listp source-image-divergence)
                                   (getf source-image-divergence :source-present-p))
            :definition-count (and (listp source-image-divergence)
                                   (getf source-image-divergence :definition-count))))))

(defun plan-step-evidence-summary (evidence)
  (when (listp evidence)
    (list :kind (getf evidence :kind)
          :status (getf evidence :status)
          :reconciliation-status (getf evidence :reconciliation-status)
          :session-id (getf evidence :session-id)
          :approval-id (getf evidence :approval-id)
          :actor-execution-job-id (getf evidence :actor-execution-job-id)
          :actor-message-id (getf evidence :actor-message-id)
          :pending-action-id (getf evidence :pending-action-id)
          :target (getf evidence :target)
          :operation (getf evidence :operation)
          :capability (getf evidence :capability)
          :target-observed-p (getf evidence :target-observed-p)
          :operation-observed-p (getf evidence :operation-observed-p)
          :scope-observed-p (getf evidence :scope-observed-p)
          :buffer-observed-p (getf evidence :buffer-observed-p)
          :package-observed-p (getf evidence :package-observed-p)
          :defined-name (getf evidence :defined-name)
          :reason (getf evidence :reason)
          :runtime-post-state
          (summarized-runtime-post-state (getf evidence :post-state)))))

(defun workflow-approval-summary (record &optional latest-evidence-summary)
  (when record
    (let* ((resume-payload (workflow-record-resume-payload record))
           (next-action (workflow-record-next-action record))
           (requirements (workflow-record-approval-requirements record))
           (approval-ids
             (normalized-string-list
              (getf resume-payload :approval-ids)
              (getf resume-payload :approval-id)
              (getf next-action :approval-ids)
              (getf next-action :approval-id)
              (getf latest-evidence-summary :approval-id)))
           (actor-message-ids
             (normalized-string-list
              (getf resume-payload :actor-message-ids)
              (getf resume-payload :actor-message-id)
              (getf next-action :actor-message-ids)
              (getf next-action :actor-message-id)
              (getf latest-evidence-summary :actor-message-id)))
           (pending-action-ids
             (normalized-string-list
              (getf resume-payload :pending-action-ids)
              (getf resume-payload :pending-action-id)
              (getf next-action :pending-action-ids)
              (getf next-action :pending-action-id)
              (getf latest-evidence-summary :pending-action-id)))
           (record-ids
             (normalized-string-list
              (getf resume-payload :record-ids)
              (getf next-action :record-ids)))
           (policy-ids
             (normalized-eq-list
              (getf resume-payload :policy-ids)
              (getf resume-payload :policy-id)
              (getf next-action :policy-ids)
              (getf next-action :policy-id)
              (mapcar (lambda (entry) (getf entry :policy)) requirements)))
           (session-id (or (getf resume-payload :session-id)
                           (getf next-action :session-id)))
           (thread-id (or (getf resume-payload :thread-id)
                          (getf next-action :thread-id)))
           (turn-id (or (getf resume-payload :turn-id)
                        (getf next-action :turn-id)))
           (approval-summary
             (list :approval-id (first approval-ids)
                   :approval-ids approval-ids
                   :actor-message-id (first actor-message-ids)
                   :actor-message-ids actor-message-ids
                   :pending-action-id (first pending-action-ids)
                   :pending-action-ids pending-action-ids
                   :policy-id (first policy-ids)
                   :policy-ids policy-ids
                   :session-id session-id
                   :thread-id thread-id
                   :turn-id turn-id
                   :record-ids record-ids)))
      (when (or approval-ids actor-message-ids pending-action-ids policy-ids
                session-id thread-id turn-id record-ids)
        (append approval-summary
                (list :approve-command (approval-approve-command-summary approval-summary)
                      :ack-command (approval-ack-command-summary approval-summary)
                      :dequeue-command (approval-dequeue-command-summary approval-summary)))))))

(defun plan-step-verification-summary (step)
  (let ((latest-evidence (latest-plan-step-evidence step)))
    (list :step-id (plan-step-id step)
          :goal (plan-step-goal step)
          :status (plan-step-status step)
          :verification-status (plan-step-verification-status step)
          :evidence-summary (plan-step-evidence-summary latest-evidence)
          :latest-evidence-summary (plan-step-evidence-summary latest-evidence)
          :latest-evidence latest-evidence
          :reconciliation-status (and (listp latest-evidence)
                                      (getf latest-evidence :reconciliation-status))
          :updated-at (plan-step-updated-at step))))

(defun plan-step-orchestration-summary (step)
  (let ((verification-summary (plan-step-verification-summary step))
        (resolved-capability (plan-step-resolved-capability step)))
    (list :step-id (plan-step-id step)
          :kind (plan-step-kind step)
          :goal (plan-step-goal step)
          :status (plan-step-status step)
          :verification-status (plan-step-verification-status step)
          :reconciliation-status (getf verification-summary :reconciliation-status)
          :assigned-actor (plan-step-assigned-actor step)
          :execution-id (plan-step-execution-id step)
          :result-summary (plan-step-result-summary step)
          :capability (or (getf resolved-capability :capability)
                          (and (listp resolved-capability)
                               (getf resolved-capability :id)))
          :target (and (listp resolved-capability)
                       (getf resolved-capability :target))
          :operation (and (listp resolved-capability)
                          (getf resolved-capability :operation))
          :updated-at (plan-step-updated-at step)
          :evidence-summary (getf verification-summary :evidence-summary))))

(defun workflow-posture-summary (record &optional latest-evidence-summary)
  (when record
    (list :status (workflow-record-status record)
          :waiting-on (workflow-record-waiting-on record)
          :approval-required-p (eq (workflow-record-waiting-on record) :approval)
          :approval-requirement-count (length (workflow-record-approval-requirements record))
          :approval-summary (workflow-approval-summary record latest-evidence-summary)
          :pending-validation-count (length (workflow-record-pending-validations record))
          :next-action (workflow-record-next-action record)
          :resume-payload (workflow-record-resume-payload record)
          :quarantine-reason (workflow-record-quarantine-reason record)
          :resume-count (workflow-record-resume-count record)
          :operator-intervention-count
          (length (workflow-record-operator-interventions record)))))

(defun plan-verification-summary (session plan)
  (let* ((workflow-record (plan-linked-workflow-record session plan))
         (step-summaries (mapcar #'plan-step-verification-summary
                                 (plan-record-steps plan)))
         (verification-statuses (mapcar (lambda (step)
                                          (plan-step-verification-status step))
                                        (plan-record-steps plan)))
         (latest-step (latest-plan-step plan))
         (latest-step-verification-summary
           (and latest-step
                (plan-step-verification-summary latest-step)))
         (latest-evidence
           (car (last (or (plan-record-evidence plan) '()))))
         (latest-evidence-summary
           (plan-step-evidence-summary latest-evidence)))
    (list :plan-id (plan-record-id plan)
          :plan-status (plan-record-status plan)
          :active-plan-p (string= (plan-record-id plan)
                                  (or (session-active-plan-id session) ""))
          :verification-policy (copy-tree (plan-record-verification-policy plan))
         :workflow-record-id (and workflow-record
                                   (workflow-record-id workflow-record))
          :workflow-status (and workflow-record
                                (workflow-record-status workflow-record))
          :approval-summary
          (workflow-approval-summary workflow-record
                                     latest-evidence-summary)
          :actor-execution-job-id
          (or (and latest-step-verification-summary
                   (getf (getf latest-step-verification-summary
                               :latest-evidence-summary)
                         :actor-execution-job-id))
              (and latest-evidence-summary
                   (getf latest-evidence-summary :actor-execution-job-id)))
          :step-count (length step-summaries)
          :verified-step-count (count :verified verification-statuses)
          :failed-step-count (count :failed verification-statuses)
          :pending-step-count
          (count-if (lambda (status)
                      (or (null status)
                          (eq status :pending)
                          (eq status :verification-unavailable)))
                    verification-statuses)
          :steps step-summaries
          :latest-step-summary (and latest-step
                                    (plan-step-orchestration-summary latest-step))
          :latest-evidence-summary latest-evidence-summary
          :latest-evidence latest-evidence)))

(defun ensure-plan-workflow-record (session plan)
  (or (plan-linked-workflow-record session plan)
      (let ((record (create-workflow-record session
                                            (plan-record-goal plan)
                                            :plan-id (plan-record-id plan)
                                            :work-item-id (plan-record-work-item-id plan)
                                            :initial-phase :plan
                                            :initial-kind :plan-created
                                            :initial-payload (plan-record-summary plan))))
        (setf (plan-record-workflow-record-id plan) (workflow-record-id record))
        record)))

(defun plan-orchestration-detail (session plan)
  (let* ((workflow-record (plan-linked-workflow-record session plan))
         (latest-step (latest-plan-step plan))
         (latest-evidence-summary
           (plan-step-evidence-summary (car (last (or (plan-record-evidence plan) '())))))
         (approval-summary (workflow-approval-summary workflow-record latest-evidence-summary))
         (detail
           (append (plan-record-detail plan)
                   (list :active-plan-p (string= (plan-record-id plan)
                                                 (or (session-active-plan-id session) ""))
                         :approval-summary approval-summary
                         :posture-summary (workflow-posture-summary workflow-record latest-evidence-summary)
                         :latest-step-summary (and latest-step
                                                   (plan-step-orchestration-summary latest-step))
                         :verification-summary (plan-verification-summary session plan)
                         :workflow-record (and workflow-record
                                               (workflow-record-detail workflow-record))
                         :workflow-record-summary (and workflow-record
                                                       (workflow-record-summary workflow-record))))))
    (let* ((primary-command (orchestration-primary-command detail approval-summary))
           (available-commands (orchestration-available-commands approval-summary))
           (available-command-summaries (available-command-summaries available-commands)))
      (append detail
              (list :primary-command primary-command
                    :available-commands available-commands
                    :available-command-summaries available-command-summaries
                    :available-command-count (length available-commands))
              (primary-command-fields primary-command)
              (approval-summary-fields approval-summary)))))

(defun append-plan-workflow-entry (session plan phase kind payload &key status metadata evidence)
  (let ((record (ensure-plan-workflow-record session plan)))
    (append-workflow-record-entry session record phase kind payload :status status)
    (when evidence
      (append-workflow-record-evidence record evidence))
    (append-workflow-record-event session kind record payload :metadata metadata)
    record))

(defun query-plan-list-service (session)
  (make-service-query-response
   :planning
   :list
   (plan-list-data session)
   :metadata (make-service-metadata :authority :environment
                                    :read-model :plan-list-v1
                                    :session session)))

(defun query-orchestration-list-service (session)
  (make-service-query-response
   :planning
   :orchestration-list
   (mapcar (lambda (plan)
             (plan-orchestration-summary session plan))
           (session-plan-set session))
   :metadata (make-service-metadata :authority :environment
                                    :read-model :orchestration-list-v1
                                    :session session)))

(defun command-orchestration-list-query-service (session)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :orchestration-list-query
                                :workflow/orchestration-list)
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read orchestration list."
                                    "workflow/orchestration-list"
                                    :authority :operator
                                    :payload '()))
   :workflow/orchestration-list
   :orchestration-list-query))

(defun query-orchestration-inbox-service (session)
  (let* ((summaries (mapcar (lambda (plan)
                              (plan-orchestration-summary session plan))
                            (session-plan-set session)))
         (actionable (remove-if-not #'orchestration-actionable-p summaries)))
    (make-service-query-response
     :planning
     :orchestration-inbox
     (mapcar #'orchestration-inbox-entry actionable)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :orchestration-inbox-v1
                                      :session session))))

(defun command-orchestration-inbox-query-service (session)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :orchestration-inbox-query
                                :workflow/orchestration-inbox)
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read orchestration inbox."
                                    "workflow/orchestration-inbox"
                                    :authority :operator
                                    :payload '()))
   :workflow/orchestration-inbox
   :orchestration-inbox-query))

(defun query-orchestration-focus-service (session &key plan-id workflow-record-id work-item-id)
  (multiple-value-bind (plan resolved-by workflow-record work-item)
      (resolve-orchestration-focus session
                                   :plan-id plan-id
                                   :workflow-record-id workflow-record-id
                                   :work-item-id work-item-id)
    (make-service-query-response
     :planning
     :orchestration-focus
     (append (plan-orchestration-detail session plan)
             (list :resolved-by resolved-by
                   :requested-plan-id plan-id
                   :requested-workflow-record-id workflow-record-id
                   :requested-work-item-id work-item-id
                   :resolved-workflow-record-id
                   (or (and workflow-record (workflow-record-id workflow-record))
                       (plan-record-workflow-record-id plan))
                   :resolved-work-item-id
                   (and work-item (work-item-id work-item))))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :orchestration-focus-v1
                                      :session session
                                      :work-item-id (and work-item (work-item-id work-item))
                                      :workflow-record-id
                                      (or (and workflow-record (workflow-record-id workflow-record))
                                          (plan-record-workflow-record-id plan))))))

(defun command-orchestration-focus-query-service (session &key plan-id workflow-record-id work-item-id)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :orchestration-focus-query
                                :workflow/orchestration-focus
                                :payload (append (when plan-id (list :plan-id plan-id))
                                                 (when workflow-record-id (list :workflow-record-id workflow-record-id))
                                                 (when work-item-id (list :work-item-id work-item-id)))
                                :work-item-id work-item-id
                                :workflow-record-id workflow-record-id
                                :plan-id plan-id
                                :metadata (append (when plan-id (list :plan-id plan-id))
                                                  (when workflow-record-id (list :workflow-record-id workflow-record-id))
                                                  (when work-item-id (list :work-item-id work-item-id))))
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read orchestration focus."
                                    "workflow/orchestration-focus"
                                    :authority :operator
                                    :payload (append (when plan-id (list :plan-id plan-id))
                                                     (when workflow-record-id (list :workflow-record-id workflow-record-id))
                                                     (when work-item-id (list :work-item-id work-item-id)))))
   :workflow/orchestration-focus
   :orchestration-focus-query
   :work-item-id work-item-id
   :workflow-record-id workflow-record-id
   :metadata (append (when plan-id (list :plan-id plan-id))
                     (when workflow-record-id (list :workflow-record-id workflow-record-id))
                     (when work-item-id (list :work-item-id work-item-id)))))

(defun query-plan-service (session &optional plan-id)
  (let ((plan (active-plan-or-error session plan-id)))
    (make-service-query-response
     :planning
     :detail
     (plan-orchestration-detail session plan)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :plan-detail-v1
                                      :session session))))

(defun query-active-plan-service (session)
  (let ((plan (session-active-plan session)))
    (unless plan
      (error "No active plan is available"))
    (make-service-query-response
     :planning
     :active-plan
     (plan-orchestration-detail session plan)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :active-plan-detail-v1
                                      :session session))))

(defun command-active-plan-query-service (session)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :active-plan-query
                                :workflow/active-plan)
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read active plan."
                                    "workflow/active-plan"
                                    :authority :operator
                                    :payload '()))
   :workflow/active-plan
   :active-plan-query))

(defun query-plan-linked-workflow-service (session &optional plan-id)
  (let* ((plan (active-plan-or-error session plan-id))
         (workflow-record (plan-linked-workflow-record session plan)))
    (unless workflow-record
      (error "No workflow record is linked to plan ~A" (plan-record-id plan)))
    (make-service-query-response
     :planning
     :linked-workflow
     (list :plan-id (plan-record-id plan)
           :workflow-record-id (workflow-record-id workflow-record)
           :workflow-record (workflow-record-detail workflow-record))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :plan-linked-workflow-v1
                                      :session session
                                      :workflow-record-id (workflow-record-id workflow-record)))))

(defun command-plan-linked-workflow-query-service (session &optional plan-id)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :plan-linked-workflow-query
                                :workflow/plan-linked-workflow
                                :payload (when plan-id (list :plan-id plan-id))
                                :plan-id plan-id
                                :metadata (when plan-id (list :plan-id plan-id)))
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read plan-linked workflow."
                                    "workflow/plan-linked-workflow"
                                    :authority :operator
                                    :payload (when plan-id (list :plan-id plan-id))))
   :workflow/plan-linked-workflow
   :plan-linked-workflow-query
   :metadata (when plan-id (list :plan-id plan-id))))

(defun query-orchestration-snapshot-service (session &optional plan-id)
  (let ((plan (active-plan-or-error session plan-id)))
    (make-service-query-response
     :planning
     :orchestration-snapshot
     (plan-orchestration-detail session plan)
      :metadata (make-service-metadata :authority :environment
                                      :read-model :orchestration-snapshot-v1
                                      :session session
                                      :workflow-record-id (plan-record-workflow-record-id plan)))))

(defun command-orchestration-snapshot-query-service (session &optional plan-id)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :orchestration-snapshot-query
                                :workflow/orchestration-snapshot
                                :payload (when plan-id (list :plan-id plan-id))
                                :plan-id plan-id
                                :metadata (when plan-id (list :plan-id plan-id)))
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read orchestration snapshot."
                                    "workflow/orchestration-snapshot"
                                    :authority :operator
                                    :payload (when plan-id (list :plan-id plan-id))))
   :workflow/orchestration-snapshot
   :orchestration-snapshot-query
   :metadata (when plan-id (list :plan-id plan-id))))

(defun query-plan-verification-service (session &optional plan-id)
  (let ((plan (active-plan-or-error session plan-id)))
    (make-service-query-response
     :planning
     :verification
     (plan-verification-summary session plan)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :plan-verification-v1
                                      :session session
                                      :workflow-record-id (plan-record-workflow-record-id plan)))))

(defun command-plan-verification-query-service (session &optional plan-id)
  (call-with-workflow-query-actor
   session
   (make-workflow-query-request session
                                :plan-verification-query
                                :workflow/plan-verification
                                :payload (when plan-id (list :plan-id plan-id))
                                :plan-id plan-id
                                :metadata (when plan-id (list :plan-id plan-id)))
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read plan verification summary."
                                    "workflow/plan-verification"
                                    :authority :operator
                                    :payload (when plan-id (list :plan-id plan-id))))
   :workflow/plan-verification
   :plan-verification-query
   :metadata (when plan-id (list :plan-id plan-id))))

(defun command-create-plan-service (session goal &key parent-plan-id scope steps
                                                   selected-capabilities
                                                   verification-policy
                                                   repair-policy
                                                   evidence
                                                   workflow-record-id
                                                   work-item-id
                                                   assigned-actors
                                                   (status :open))
  (let* ((resolved-steps
           (mapcar (lambda (step)
                     (if (typep step 'plan-step)
                         step
                         (apply #'create-plan-step
                                (or (getf step :goal)
                                    (error "Plan step payload requires :goal"))
                                (loop for (key value) on step by #'cddr
                                      unless (eq key :goal)
                                        append (list key value)))))
                   (or steps '())))
         (plan (create-plan-record goal
                                   :parent-plan-id parent-plan-id
                                   :scope scope
                                   :steps resolved-steps
                                   :selected-capabilities selected-capabilities
                                   :verification-policy verification-policy
                                   :repair-policy repair-policy
                                   :evidence evidence
                                   :workflow-record-id workflow-record-id
                                   :work-item-id work-item-id
                                   :assigned-actors assigned-actors
                                   :status status)))
    (set-session-active-plan session plan)
    (ensure-plan-workflow-record session plan)
    (append-session-event session
                          :plan-created
                          (plan-record-summary plan)
                          :family :planning)
    (make-service-command-response
     :planning
     :create
     (plan-record-detail plan)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :plan-create-v1
                                      :session session
                                      :work-item-id work-item-id
                                      :workflow-record-id workflow-record-id))))

(defun command-expand-plan-service (session plan-id step-payloads)
  (let ((plan (active-plan-or-error session plan-id)))
    (dolist (payload step-payloads)
      (append-plan-step
       plan
       (if (typep payload 'plan-step)
           payload
           (apply #'create-plan-step
                  (or (getf payload :goal)
                      (error "Plan step payload requires :goal"))
                  (loop for (key value) on payload by #'cddr
                        unless (eq key :goal)
                          append (list key value))))))
    (append-plan-workflow-entry session
                                plan
                                :plan
                                :plan-expanded
                                (list :plan-id (plan-record-id plan)
                                      :step-count (length (plan-record-steps plan)))
                                :status (plan-record-status plan))
    (append-session-event session
                          :plan-expanded
                          (list :plan-id (plan-record-id plan)
                                :step-count (length (plan-record-steps plan)))
                          :family :planning)
    (make-service-command-response
     :planning
     :expand
     (plan-record-detail plan)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :plan-expand-v1
                                      :session session))))

(defun resolve-plan-step-capability (session capability-query)
  (when capability-query
    (capability-registry-find session
                              :id (getf capability-query :id)
                              :source-kind (getf capability-query :source-kind)
                              :actor-role (getf capability-query :actor-role)
                              :mutation-class (getf capability-query :mutation-class)
                              :approval-required-p (getf capability-query :approval-required-p)
                              :backend-kind (getf capability-query :backend-kind))))

(defun command-assign-plan-step-service (session plan-id step-id &key actor-id capability-query)
  (multiple-value-bind (plan step)
      (planning-service-step-or-error session plan-id step-id)
    (let* ((resolved-capability
             (or (resolve-plan-step-capability session capability-query)
                 (and (plan-step-capability-query step)
                      (resolve-plan-step-capability session
                                                    (plan-step-capability-query step)))))
           (resolved-actor
             (or (and actor-id
                      (actor-registry-definition-by-id session actor-id))
                 (and resolved-capability
                      (capability-definition-actor-role resolved-capability)
                      (actor-registry-definition-by-role
                       session
                       (capability-definition-actor-role resolved-capability))))))
      (when capability-query
        (setf (plan-step-capability-query step) (copy-tree capability-query)))
      (when resolved-capability
        (setf (plan-step-resolved-capability step)
              (capability-definition-summary resolved-capability)))
      (when resolved-actor
        (setf (plan-step-assigned-actor step)
              (list :id (actor-definition-id resolved-actor)
                    :role (actor-definition-role resolved-actor)
                    :display-name (actor-definition-display-name resolved-actor))))
      (update-plan-step-status step :assigned)
      (update-plan-status plan :in-progress)
      (append-plan-workflow-entry session
                                  plan
                                  :assign
                                  :plan-step-assigned
                                  (list :plan-id (plan-record-id plan)
                                        :step-id (plan-step-id step)
                                        :assigned-actor (plan-step-assigned-actor step)
                                        :resolved-capability (plan-step-resolved-capability step))
                                  :status (plan-record-status plan)
                                  :metadata (list :plan-step-id (plan-step-id step)))
      (append-session-event session
                            :plan-step-assigned
                            (list :plan-id (plan-record-id plan)
                                  :step-id (plan-step-id step)
                                  :assigned-actor (plan-step-assigned-actor step)
                                  :resolved-capability (plan-step-resolved-capability step))
                            :family :planning)
      (make-service-command-response
       :planning
       :assign-step
       (plan-step-detail step)
       :metadata (make-service-metadata :authority :environment
                                        :command-model :plan-assign-step-v1
                                        :session session)))))

 (defun command-complete-plan-step-service (session plan-id step-id &key result-summary execution-id verification-status evidence)
  (multiple-value-bind (plan step)
      (planning-service-step-or-error session plan-id step-id)
    (update-plan-step-status step
                             :completed
                             :result-summary result-summary
                             :execution-id execution-id
                             :verification-status verification-status)
    (when evidence
      (append-plan-step-evidence step evidence)
      (append-plan-evidence plan evidence))
    (when (every (lambda (candidate)
                   (eq (plan-step-status candidate) :completed))
                 (plan-record-steps plan))
      (update-plan-status plan :completed :result-summary result-summary))
    (append-plan-workflow-entry session
                                plan
                                :verify
                                :plan-step-completed
                                (list :plan-id (plan-record-id plan)
                                      :step-id (plan-step-id step)
                                      :execution-id execution-id
                                      :verification-status verification-status
                                      :result-summary result-summary)
                                :status (plan-record-status plan)
                                :metadata (list :plan-step-id (plan-step-id step))
                                :evidence evidence)
    (append-session-event session
                          :plan-step-completed
                          (list :plan-id (plan-record-id plan)
                                :step-id (plan-step-id step)
                                :execution-id execution-id
                                :verification-status verification-status
                                :evidence evidence)
                          :family :planning)
    (make-service-command-response
     :planning
     :complete-step
     (plan-step-detail step)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :plan-complete-step-v1
                                      :session session))))

 (defun command-fail-plan-step-service (session plan-id step-id &key result-summary execution-id verification-status evidence)
  (multiple-value-bind (plan step)
      (planning-service-step-or-error session plan-id step-id)
    (update-plan-step-status step
                             :failed
                             :result-summary result-summary
                             :execution-id execution-id
                             :verification-status verification-status)
    (when evidence
      (append-plan-step-evidence step evidence)
      (append-plan-evidence plan evidence))
    (update-plan-status plan :failed :result-summary result-summary)
    (append-plan-workflow-entry session
                                plan
                                :repair
                                :plan-step-failed
                                (list :plan-id (plan-record-id plan)
                                      :step-id (plan-step-id step)
                                      :execution-id execution-id
                                      :verification-status verification-status
                                      :result-summary result-summary)
                                :status (plan-record-status plan)
                                :metadata (list :plan-step-id (plan-step-id step))
                                :evidence evidence)
    (append-session-event session
                          :plan-step-failed
                          (list :plan-id (plan-record-id plan)
                                :step-id (plan-step-id step)
                                :execution-id execution-id
                                :verification-status verification-status
                                :evidence evidence)
                          :family :planning)
    (make-service-command-response
     :planning
     :fail-step
     (plan-step-detail step)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :plan-fail-step-v1
                                      :session session))))

(defun command-repair-plan-step-service (session plan-id step-id &key note)
  (multiple-value-bind (plan step)
      (planning-service-step-or-error session plan-id step-id)
    (increment-plan-step-repair-count step)
    (update-plan-step-status step :pending :result-summary note)
    (update-plan-status plan :in-progress :result-summary note)
    (append-plan-workflow-entry session
                                plan
                                :repair
                                :plan-step-repair-requested
                                (list :plan-id (plan-record-id plan)
                                      :step-id (plan-step-id step)
                                      :repair-count (plan-step-repair-count step)
                                      :note note)
                                :status (plan-record-status plan)
                                :metadata (list :plan-step-id (plan-step-id step)))
    (append-session-event session
                          :plan-step-repair-requested
                          (list :plan-id (plan-record-id plan)
                                :step-id (plan-step-id step)
                                :repair-count (plan-step-repair-count step)
                                :note note)
                          :family :planning)
    (make-service-command-response
     :planning
     :repair-step
     (plan-step-detail step)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :plan-repair-step-v1
                                      :session session))))
