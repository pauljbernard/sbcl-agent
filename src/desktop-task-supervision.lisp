(in-package #:sbcl-agent)

(defun actor-supervision-incident-p (incident)
  (eq :actor-supervision
      (getf (incident-metadata incident) :source)))

(defun desktop-task-supervision-mailbox-for-record (record)
  (cond
    ((and (fboundp 'context-chat-mailbox-record-p)
          (context-chat-mailbox-record-p record))
     :context-chat-mailbox)
    ((and (eq (desktop-task-record-target record) :editor)
          (desktop-task-record-pending-action-id record))
     :editor-pending-mutation-mailbox)
    ((eq (desktop-task-record-target record) :runtime)
     :runtime-inbox)
    ((desktop-task-record-approval-id record)
     :governance-inbox)
    (t nil)))

(defun desktop-task-supervision-mailbox-summary (record mailbox)
  (case mailbox
    (:context-chat-mailbox
     (context-chat-mailbox-entry-summary record))
    (:editor-pending-mutation-mailbox
     (editor-pending-mutation-summary record))
    (:runtime-inbox
     (runtime-eval-mailbox-entry-summary record))
    (:governance-inbox
     (governance-approval-request-summary record))
    (otherwise
     (desktop-task-record-summary record))))

(defun find-supervision-mailbox-entry-for-record (session record mailbox)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (entries (copy-list (or (getf mailboxes mailbox) '())))
         (request-id (desktop-task-record-request-id record))
         (actor-message (desktop-task-record-actor-message record))
         (actor-message-id (and actor-message
                                (actor-message-id actor-message))))
    (or (and actor-message-id
             (find-if (lambda (entry)
                        (let ((entry-actor-message-id
                                (actor-mailbox-entry-actor-message-id entry)))
                          (and entry-actor-message-id
                               (string= actor-message-id entry-actor-message-id))))
                      entries))
        (and request-id
             (find-if (lambda (entry)
                        (let ((entry-request-id
                                (actor-mailbox-entry-request-id entry)))
                          (and entry-request-id
                               (string= request-id entry-request-id))))
                      entries)))))

(defun maybe-record-runtime-actor-job-supervision-failure (session job error)
  (let* ((context (and job
                       (actor-execution-job-context job)))
         (request-id (and context
                          (actor-execution-context-request-id context)))
         (record (or (and request-id
                          (find-desktop-task-record-by-request-id session request-id))
                     (and context
                          (let ((metadata (actor-execution-context-metadata context)))
                            (when (listp metadata)
                              (let ((actor-message-id (or (getf metadata :actor-message-id)
                                                          (getf metadata :ACTOR-MESSAGE-ID))))
                                (and actor-message-id
                                     (find-desktop-task-record-by-actor-message-id session
                                                                                   actor-message-id))))))))
         (mailbox (and record
                       (desktop-task-supervision-mailbox-for-record record))))
    (when (and record mailbox)
      (let* ((entry (or (find-supervision-mailbox-entry-for-record session record mailbox)
                        (make-actor-mailbox-entry-for-record
                         record
                         mailbox
                         (desktop-task-supervision-mailbox-summary record mailbox))))
             (summary (or (and (listp error)
                               (or (getf error :summary)
                                   (getf error :SUMMARY)
                                   (getf error :error)
                                   (getf error :ERROR)))
                          (princ-to-string error))))
        (command-desktop-task-fail-mailbox-entry-service
         session
         mailbox
         (actor-mailbox-entry-id entry)
         :session-id (desktop-task-record-session-id record)
         :actor-message-id (actor-mailbox-entry-actor-message-id entry)
         :summary summary
         :condition-string (princ-to-string error)
         :supervision-action :automatic-runtime-failure)))))

(defun mailbox-entry-supervision-policy (session entry)
  (let ((definition (actor-mailbox-entry-actor-definition session entry)))
    (and definition
         (actor-definition-supervision-policy definition))))

(defun mailbox-entry-supervision-escalation-target (session entry)
  (let* ((definition (actor-mailbox-entry-actor-definition session entry))
         (policy (and definition
                      (actor-definition-supervision-policy definition))))
    (or (and policy
             (actor-supervision-policy-escalation-target policy))
        (and definition
             (actor-definition-parent-actor-id definition)))))

(defun mailbox-entry-supervision-restart-count (entry)
  (or (getf (actor-mailbox-entry-metadata entry) :supervision-restart-count)
      0))

(defun mailbox-entry-supervision-restart-timestamps (entry)
  (copy-list
   (or (getf (actor-mailbox-entry-metadata entry) :supervision-restart-timestamps)
       '())))

(defun mailbox-entry-supervision-escalation-count (entry)
  (or (getf (actor-mailbox-entry-metadata entry) :supervision-escalation-count)
      0))

(defun supervision-metadata-escalation-count (metadata)
  (or (and (listp metadata)
           (getf metadata :supervision-escalation-count))
      0))

(defun supervision-metadata-group-replacement-count (metadata)
  (or (and (listp metadata)
           (getf metadata :supervision-group-replacement-count))
      0))

(defun supervision-restart-timestamps-in-window (timestamps window-seconds &key now)
  (let ((effective-now (or now (get-universal-time))))
    (if (and window-seconds (> window-seconds 0))
        (remove-if-not (lambda (timestamp)
                         (and timestamp
                              (<= (- effective-now timestamp) window-seconds)))
                       timestamps)
        timestamps)))

(defun mailbox-entry-supervision-restart-attempts-in-window (policy entry &key now)
  (let* ((window-seconds (and policy
                              (actor-supervision-policy-restart-window-seconds policy)))
         (timestamps (mailbox-entry-supervision-restart-timestamps entry)))
    (length (supervision-restart-timestamps-in-window timestamps
                                                      window-seconds
                                                      :now now))))

(defun actor-supervision-restart-budget-available-p (policy entry)
  (let* ((max-restarts (and policy
                            (actor-supervision-policy-max-restarts policy)))
         (attempt-count (if (and policy
                                 (actor-supervision-policy-restart-window-seconds policy))
                            (mailbox-entry-supervision-restart-attempts-in-window policy entry)
                            (mailbox-entry-supervision-restart-count entry))))
    (and policy
         max-restarts
         (> max-restarts attempt-count))))

(defun next-supervision-restart-history (entry policy &key now)
  (let* ((effective-now (or now (get-universal-time)))
         (window-seconds (and policy
                              (actor-supervision-policy-restart-window-seconds policy)))
         (existing (mailbox-entry-supervision-restart-timestamps entry))
         (retained (supervision-restart-timestamps-in-window existing
                                                             window-seconds
                                                             :now effective-now)))
    (append retained (list effective-now))))

(defun automatic-supervision-action-for-entry (session entry)
  (let* ((policy (mailbox-entry-supervision-policy session entry))
         (on-failure (and policy
                          (actor-supervision-policy-on-failure policy))))
    (case on-failure
      (:restart
       (if (actor-supervision-restart-budget-available-p policy entry)
           :restart-child
           :escalate-to-parent))
      (:replace-member :replace-child)
      (:quarantine :quarantine)
      (:dead-letter :dead-letter)
      (:escalate :escalate-to-parent)
      (otherwise nil))))

(defun apply-automatic-supervision-policy (session incident mailbox entry)
  (let ((action (automatic-supervision-action-for-entry session entry)))
    (when action
      (multiple-value-bind (updated-entry recovery-summary)
          (apply-supervision-action-to-mailbox-entry
           session
           mailbox
           (actor-mailbox-entry-id entry)
           action
           "Applied automatically from actor supervision policy.")
        (setf (incident-status incident)
              (case action
                (:quarantine :quarantined)
                (otherwise :resolved))
              (incident-metadata incident)
              (append (list :automatic-supervision-p t
                            :requested-action :automatic-policy
                            :resolution-action action
                            :resolution-note "Applied automatically from actor supervision policy."
                            :recovery (copy-tree recovery-summary)
                            :resolved-at (get-universal-time))
                      (copy-tree (incident-metadata incident))))
        (when (fboundp 'record-actor-supervision-runtime-history)
          (record-actor-supervision-runtime-history session
                                                    updated-entry
                                                    action
                                                    :incident incident
                                                    :recovery-summary recovery-summary
                                                    :automatic-p t))
        (values updated-entry recovery-summary action)))))

(defun payload-pending-action-ids (payload)
  (remove-duplicates
   (remove nil
           (append (copy-list (or (and (listp payload)
                                       (getf payload :pending-action-ids))
                                  '()))
                   (let ((pending-action-id (and (listp payload)
                                                 (getf payload :pending-action-id))))
                     (and pending-action-id
                          (list pending-action-id)))))
   :test #'string=))

(defun recoverable-work-item-turn-resume-candidate (session
                                                    &key pending-action-id
                                                      work-item-id workflow-record-id turn-id)
  (labels ((candidate-for-work-item (work-item)
             (let* ((record (and work-item
                                 (work-item-workflow-record session work-item)))
                    (wait-report (and record
                                      (work-item-wait-report session work-item)))
                    (resume-payload (and (listp wait-report)
                                         (getf wait-report :resume-payload)))
                    (next-action (and (listp wait-report)
                                      (getf wait-report :next-action)))
                    (payload-pending-action-ids
                      (append (payload-pending-action-ids resume-payload)
                              (payload-pending-action-ids next-action)))
                    (resolved-turn-id (or turn-id
                                          (getf resume-payload :turn-id)
                                          (getf next-action :turn-id)))
                    (turn (and resolved-turn-id
                               (find-turn session resolved-turn-id)))
                    (checkpoint (and turn
                                     (fboundp 'incomplete-turn-resume-checkpoint-for-turn)
                                     (incomplete-turn-resume-checkpoint-for-turn
                                      record
                                      turn))))
               (when (and record
                          turn
                          checkpoint
                          (or (null pending-action-id)
                              (member pending-action-id payload-pending-action-ids
                                      :test #'string=)))
                 (list :work-item work-item
                       :workflow-record record
                       :turn turn
                       :checkpoint checkpoint
                       :resume-payload resume-payload
                       :next-action next-action)))))
    (cond
      (work-item-id
       (candidate-for-work-item (find-work-item session work-item-id)))
      (workflow-record-id
       (let* ((record (find-workflow-record session workflow-record-id))
              (work-item (and record
                              (find-work-item session
                                              (workflow-record-work-item-id record)))))
         (candidate-for-work-item work-item)))
      (pending-action-id
       (loop for work-item in (agent-session-work-items session)
             for candidate = (candidate-for-work-item work-item)
             when candidate
               return candidate)))))

(defun supervision-checkpoint-recovery-summary (candidate)
  (when candidate
    (let* ((work-item (getf candidate :work-item))
           (record (getf candidate :workflow-record))
           (turn (getf candidate :turn))
           (checkpoint (getf candidate :checkpoint)))
      (list :recoverable-p t
            :recovery-command :turn/resume
            :work-item-id (and work-item (work-item-id work-item))
            :workflow-record-id (and record (workflow-record-id record))
            :turn-id (and turn (turn-id turn))
            :checkpoint-kind (and checkpoint (getf checkpoint :kind))
            :checkpoint-status (and checkpoint (getf checkpoint :status))
            :checkpoint-captured-at (and checkpoint (getf checkpoint :captured-at))
            :pending-action-count (and checkpoint
                                       (getf checkpoint :pending-action-count))
            :actor-execution-job-id (and checkpoint
                                         (getf checkpoint :actor-execution-job-id))))))

(defun find-work-item-for-supervision-metadata (session metadata)
  (let ((work-item-id (getf metadata :work-item-id))
        (workflow-record-id (getf metadata :workflow-record-id)))
    (or (and work-item-id
             (find-work-item session work-item-id))
        (and workflow-record-id
             (find workflow-record-id
                   (agent-session-work-items session)
                   :key #'work-item-workflow-record-ref
                   :test #'string=)))))

(defun supervision-work-item-recovery-options (status)
  (case status
    (:awaiting-cold-validation '(:complete-validations :quarantine :dead-letter))
    (:failed '(:rollback-work-item :quarantine :dead-letter))
    (:quarantined '(:resume-work-item :rollback-work-item :dead-letter))
    (otherwise '(:dead-letter :quarantine :restart-child :replace-child))))

(defun supervision-work-item-state-class (status)
  (case status
    (:awaiting-cold-validation :cold-validation-pending)
    (:failed :failed-work-item)
    (:quarantined :quarantined-work-item)
    (:awaiting-approval :approval-blocked-work-item)
    (otherwise :generic-mailbox-failure)))

(defun supervision-work-item-recommended-action (status)
  (case status
    (:awaiting-cold-validation :complete-validations)
    (:failed :rollback-work-item)
    (:quarantined :resume-work-item)
    (otherwise nil)))

(defun supervision-work-item-replay-class (status)
  (case status
    (:awaiting-approval :approval-resume)
    (:awaiting-cold-validation :validation-replay)
    (:failed :rollback-replay)
    (:quarantined :operator-review-replay)
    (:resumed :workflow-resume)
    (otherwise :state-restoration)))

(defun supervision-workflow-recovery-policy (session metadata)
  (let* ((work-item (find-work-item-for-supervision-metadata session metadata))
         (workflow-record (and work-item
                               (work-item-workflow-record session work-item)))
         (turn-id (getf metadata :turn-id))
         (candidate
           (recoverable-work-item-turn-resume-candidate
            session
            :pending-action-id (getf metadata :pending-action-id)
            :work-item-id (and work-item (work-item-id work-item))
            :workflow-record-id (or (getf metadata :workflow-record-id)
                                    (and workflow-record
                                         (workflow-record-id workflow-record)))
            :turn-id turn-id)))
    (cond
      (candidate
       (let ((checkpoint (getf candidate :checkpoint)))
         (list :workflow-state-class :checkpoint-resumable-turn
               :recommended-supervision-action :resume-from-checkpoint
               :recovery-options '(:resume-from-checkpoint :quarantine :dead-letter)
               :recoverable-p t
               :turn-id (getf candidate :turn-id)
               :work-item-id (getf candidate :work-item-id)
               :workflow-record-id (getf candidate :workflow-record-id)
               :checkpoint-p (not (null checkpoint))
               :checkpoint-status (and checkpoint (getf checkpoint :status))
               :workflow-status (and workflow-record
                                     (workflow-record-status workflow-record))
               :work-item-status (and work-item
                                      (work-item-status work-item)))))
      (work-item
       (let ((status (work-item-status work-item)))
         (list :workflow-state-class (supervision-work-item-state-class status)
               :recommended-supervision-action
               (supervision-work-item-recommended-action status)
               :recovery-options (supervision-work-item-recovery-options status)
               :recoverable-p (not (null (member status
                                                '(:awaiting-cold-validation :failed :quarantined)
                                                :test #'eq)))
               :replay-class (supervision-work-item-replay-class status)
               :work-item-id (work-item-id work-item)
               :workflow-record-id (and workflow-record
                                        (workflow-record-id workflow-record))
               :workflow-status (and workflow-record
                                     (workflow-record-status workflow-record))
               :work-item-status status
               :plan-health (when (fboundp 'work-item-plan-health)
                              (work-item-plan-health work-item))
               :current-phase (when (fboundp 'work-item-plan-current-phase)
                                (work-item-plan-current-phase work-item))
               :next-action-type (getf (work-item-next-action work-item) :type)
               :resume-command (getf (work-item-resume-payload work-item) :resume-command))))
      (t
       (list :workflow-state-class :generic-mailbox-failure
             :recommended-supervision-action nil
             :recovery-options '(:dead-letter :quarantine :restart-child :replace-child :escalate-to-parent)
             :recoverable-p nil)))))

(defun actor-supervision-incident-summary (session incident)
  (append
   (incident-record-summary incident)
   (let ((metadata (incident-metadata incident)))
     (append
      (list :incident-id (incident-id incident)
            :actor-id (getf metadata :actor-id)
            :actor-role (getf metadata :actor-role)
            :parent-actor-id (getf metadata :parent-actor-id)
            :escalation-target (getf metadata :escalation-target)
            :open-p (eq (incident-status incident) :open)
            :mailbox (getf metadata :mailbox)
            :mailbox-entry-id (getf metadata :mailbox-entry-id)
            :delivery-status (getf metadata :delivery-status)
            :supervision-escalation-count
            (supervision-metadata-escalation-count metadata)
            :supervision-group-replacement-count
            (supervision-metadata-group-replacement-count metadata)
            :supervision-policy (getf metadata :supervision-policy)
            :execution-policy (getf metadata :execution-policy)
            :session-id (getf metadata :session-id)
            :approval-id (getf metadata :approval-id)
            :pending-action-id (getf metadata :pending-action-id)
            :actor-message-id (getf metadata :actor-message-id)
           :request-id (getf metadata :request-id)
           :supervision-action (getf metadata :supervision-action)
           :requested-action (getf metadata :requested-action)
           :resolution-action (getf metadata :resolution-action))
      (supervision-workflow-recovery-policy session metadata)))))

(defun record-actor-supervision-incident (session mailbox entry
                                          &key summary condition-string
                                            (supervision-action :escalate-to-parent))
  (let* ((definition (actor-mailbox-entry-actor-definition session entry))
         (policy (and definition
                      (actor-definition-supervision-policy definition)))
         (execution-policy (and definition
                                (actor-definition-execution-policy definition)))
         (actor-id (and definition
                        (actor-definition-id definition)))
         (actor-role (and definition
                          (actor-definition-role definition)))
         (parent-actor-id (and definition
                               (actor-definition-parent-actor-id definition)))
         (escalation-target (mailbox-entry-supervision-escalation-target session entry))
         (title (format nil "Actor mailbox failure: ~A"
                        (or actor-id
                            (actor-mailbox-entry-id entry))))
         (resolved-summary
           (or summary
               (format nil "Actor ~A mailbox entry ~A failed in ~A."
                       (or actor-id actor-role :unknown)
                       (actor-mailbox-entry-id entry)
                       mailbox))))
    (create-incident
     session
     :actor-supervision
     title
     resolved-summary
     :condition condition-string
     :metadata
     (list :source :actor-supervision
           :actor-id actor-id
           :actor-role actor-role
           :parent-actor-id parent-actor-id
           :escalation-target escalation-target
           :mailbox mailbox
           :mailbox-entry-id (actor-mailbox-entry-id entry)
           :delivery-status (actor-mailbox-entry-delivery-status entry)
           :supervision-policy (actor-supervision-policy-summary policy)
           :execution-policy (actor-execution-policy-summary execution-policy)
           :session-id (actor-mailbox-entry-session-id entry)
           :approval-id (actor-mailbox-entry-approval-id entry)
           :pending-action-id (actor-mailbox-entry-pending-action-id entry)
           :turn-id (getf (actor-mailbox-entry-metadata entry) :turn-id)
           :work-item-id (getf (actor-mailbox-entry-metadata entry) :work-item-id)
           :workflow-record-id (getf (actor-mailbox-entry-metadata entry) :workflow-record-id)
           :actor-message-id (actor-mailbox-entry-actor-message-id entry)
           :request-id (actor-mailbox-entry-request-id entry)
           :supervision-action supervision-action))))

(defun update-session-actor-mailbox-entry (session mailbox matcher updater &key reason (error-p t))
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (entries (copy-list (or (getf mailboxes mailbox) '())))
         (updated-entry nil)
         (updated-entries
           (mapcar (lambda (entry)
                     (if (and (null updated-entry)
                              (funcall matcher entry))
                         (let ((next-entry (funcall updater (copy-actor-mailbox-entry entry))))
                           (setf updated-entry next-entry)
                           next-entry)
                         entry))
                   entries)))
    (unless updated-entry
      (when error-p
        (error "Unknown mailbox entry in ~A." mailbox))
      (return-from update-session-actor-mailbox-entry nil))
    (setf (getf mailboxes mailbox) updated-entries
          (agent-session-actor-mailboxes session) mailboxes)
    (persist-session-actor-mailboxes session)
    (note-actor-mailbox-transition session mailbox updated-entry reason)
    updated-entry))

(defun append-session-actor-mailbox-entry (session mailbox entry &key reason)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (entries (copy-list (or (getf mailboxes mailbox) '()))))
    (push entry entries)
    (setf (getf mailboxes mailbox)
          (sort entries #'> :key #'actor-mailbox-entry-order-key)
          (agent-session-actor-mailboxes session) mailboxes)
    (persist-session-actor-mailboxes session)
    (note-actor-mailbox-transition session mailbox entry reason)
    entry))

(defun query-desktop-task-supervision-incidents-service (session
                                                         &key actor-id parent-actor-id mailbox
                                                           mailbox-entry-id session-id latest-only-p)
  (let* ((incidents
           (remove-if-not
            (lambda (incident)
              (and (actor-supervision-incident-p incident)
                   (let ((metadata (incident-metadata incident)))
                     (and (or (null actor-id)
                              (string= (or (getf metadata :actor-id) "")
                                       actor-id))
                          (or (null parent-actor-id)
                              (string= (or (getf metadata :parent-actor-id) "")
                                       parent-actor-id))
                          (or (null mailbox)
                              (eq (getf metadata :mailbox) mailbox))
                          (or (null mailbox-entry-id)
                              (string= (or (getf metadata :mailbox-entry-id) "")
                                       mailbox-entry-id))
                          (or (null session-id)
                              (string= (or (getf metadata :session-id) "")
                                       session-id))))))
            (copy-list (agent-session-incidents session))))
         (ordered
           (sort incidents #'> :key #'incident-created-at))
         (selected
           (if latest-only-p
               (if ordered (list (first ordered)) '())
               ordered)))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :supervision-incidents-latest :supervision-incidents)
     (list :incident-count (length selected)
           :incidents (mapcar (lambda (incident)
                                (actor-supervision-incident-summary session incident))
                              selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-supervision-incidents-latest-v1
                                                      :desktop-task-supervision-incidents-v1)
                                      :session session))))

(defun find-actor-supervision-incident-for-mailbox-entry (session mailbox-entry-id
                                                          &key mailbox session-id actor-message-id
                                                            open-only-p)
  (find-if
   (lambda (incident)
     (and (actor-supervision-incident-p incident)
          (let ((metadata (incident-metadata incident)))
            (and (string= (or (getf metadata :mailbox-entry-id) "")
                          mailbox-entry-id)
                 (or (null mailbox)
                     (eq (getf metadata :mailbox) mailbox))
                 (or (null session-id)
                     (string= (or (getf metadata :session-id) "")
                              session-id))
                 (or (null actor-message-id)
                     (string= (or (getf metadata :actor-message-id) "")
                              actor-message-id))
                 (or (not open-only-p)
                     (eq (incident-status incident) :open))))))
   (agent-session-incidents session)))

(defun root-supervision-escalation-target-p (target-id)
  (and target-id
       (string= target-id
                (make-actor-address-id :actor-system))))

(defun supervision-escalation-target-definition (session target-id)
  (and target-id
       (or (and (fboundp 'actor-registry-definition-by-id)
                (actor-registry-definition-by-id session target-id))
           (find target-id
                 (actor-system-registry-definitions session)
                 :key #'actor-definition-id
                 :test #'string=))))

(defun auto-supervision-escalation-target-p (session target-id)
  (or (root-supervision-escalation-target-p target-id)
      (let* ((definition (supervision-escalation-target-definition session target-id))
             (metadata (and definition
                            (actor-definition-metadata definition)))
             (capabilities (and definition
                                (actor-definition-capabilities definition))))
        (or (and definition
                 (member :supervision capabilities :test #'eq))
            (and (listp metadata)
                 (getf metadata :auto-supervision-escalation-p))))))

(defparameter *automatic-supervision-escalation-limit* 2)

(defun supervision-escalation-target-address (session target-id)
  (or (and target-id
           (fboundp 'actor-registry-definition-by-id)
           (let ((definition (actor-registry-definition-by-id session target-id)))
             (and definition
                  (make-actor-address
                   :id (actor-definition-id definition)
                   :kind :internal
                   :role (actor-definition-role definition)
                   :display-name (actor-definition-display-name definition)
                   :metadata (copy-tree (or (actor-definition-metadata definition) '()))))))
      (and target-id
           (make-standard-actor-address :actor-system
                                        :scope (agent-session-id session)))))

(defun enqueue-routed-supervision-escalation-processing (session target-id session-id
                                                         &key actor-id
                                                           (action :recommended)
                                                           note
                                                           metadata)
  (let* ((target-address (supervision-escalation-target-address session target-id))
         (request
           (make-governed-desktop-task-request
            :requester :context-chat
            :target :desktop-task-admin
            :operation :process-supervision-escalation
            :capability :desktop-task/process-supervision-escalation
            :payload (list :session-id session-id
                           :actor-id actor-id
                           :parent-actor-id target-id
                           :action action
                           :note (or note
                                     "Automatically processed by the supervisor escalation lane."))
            :metadata (append (list :session-id session-id
                                    :actor-id actor-id
                                    :parent-actor-id target-id
                                    :actor-slice :desktop-task-supervision-v1
                                    :action action)
                              metadata))))
    (when (and request target-address)
      (let ((message (desktop-task-request-actor-message request)))
        (when message
          (setf (actor-message-receiver message) target-address))))
    (call-with-actor-worker-for-request-async
     session
     request
     (lambda ()
       (process-next-supervision-escalation
        session
        :session-id session-id
        :actor-id actor-id
        :parent-actor-id target-id
        :action action
        :note (or note
                  "Automatically processed by the supervisor escalation lane.")))
     :context (make-actor-execution-context
               :actor-id (and target-address
                              (actor-address-id target-address))
               :capability :desktop-task/process-supervision-escalation
               :authority :environment
               :target :desktop-task-admin
               :operation :process-supervision-escalation
               :request-id (desktop-task-request-id request)
               :metadata (append (list :session-id session-id
                                       :actor-id actor-id
                                       :parent-actor-id target-id
                                       :actor-slice :desktop-task-supervision-v1
                                       :automatic-supervision-p t
                                       :action action)
                                 metadata)))))

(defun matching-supervision-escalation-entry-p (entry &key session-id actor-id parent-actor-id)
  (and (eq (actor-mailbox-entry-delivery-status entry) :queued)
       (or (null session-id)
           (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
             (and entry-session-id
                  (string= session-id entry-session-id))))
       (or (null actor-id)
           (let ((entry-actor-id
                   (or (getf (actor-mailbox-entry-payload entry) :actor-id)
                       (getf (actor-mailbox-entry-metadata entry) :actor-id))))
             (and entry-actor-id
                  (string= actor-id entry-actor-id))))
       (or (null parent-actor-id)
           (let ((entry-parent-actor-id
                   (or (getf (actor-mailbox-entry-payload entry) :escalation-target)
                       (getf (actor-mailbox-entry-metadata entry) :escalation-target))))
             (and entry-parent-actor-id
                  (string= parent-actor-id entry-parent-actor-id))))))

(defun find-next-supervision-escalation-entry (session
                                               &key session-id actor-id parent-actor-id)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (entries
           (remove-if-not
            (lambda (entry)
              (matching-supervision-escalation-entry-p
               entry
               :session-id session-id
               :actor-id actor-id
               :parent-actor-id parent-actor-id))
            (copy-list (or (getf mailboxes :supervision-escalation-inbox) '())))))
    (first (sort entries #'<
                 :key (lambda (entry)
                        (or (actor-mailbox-entry-sent-at entry) 0))))))

(defun process-selected-supervision-escalation (session selected
                                                &key session-id action note)
  (let ((response
          (command-desktop-task-apply-supervision-escalation-service
           session
           (actor-mailbox-entry-id selected)
           :session-id (or session-id
                           (actor-mailbox-entry-session-id selected))
           :actor-message-id (actor-mailbox-entry-actor-message-id selected)
           :action action
           :note note)))
    (append (service-response-data response)
            (list :selected-mailbox-entry-id (actor-mailbox-entry-id selected)
                  :selected-parent-actor-id
                  (or (getf (actor-mailbox-entry-payload selected) :escalation-target)
                      (getf (actor-mailbox-entry-metadata selected) :escalation-target))))))

(defun process-next-supervision-escalation (session
                                            &key session-id actor-id parent-actor-id
                                              (action :recommended) note)
  (let ((selected
          (find-next-supervision-escalation-entry
           session
           :session-id session-id
           :actor-id actor-id
           :parent-actor-id parent-actor-id)))
    (unless selected
      (error "No queued supervision escalation entry matched the requested parent/actor scope."))
    (process-selected-supervision-escalation session
                                             selected
                                             :session-id session-id
                                             :action action
                                             :note note)))

(defun maybe-auto-process-routed-supervision-escalation (session entry &key note)
  (let* ((target-id
           (or (getf (actor-mailbox-entry-payload entry) :escalation-target)
               (getf (actor-mailbox-entry-metadata entry) :escalation-target)))
         (session-id (actor-mailbox-entry-session-id entry))
         (escalation-count (mailbox-entry-supervision-escalation-count entry)))
    (when (and (auto-supervision-escalation-target-p session target-id)
               (< escalation-count *automatic-supervision-escalation-limit*))
      (ignore-errors
        (if (and (fboundp 'enqueue-routed-supervision-escalation-processing)
                 (fboundp 'call-with-actor-worker-for-request-async))
            (enqueue-routed-supervision-escalation-processing
             session
             target-id
             session-id
             :action :recommended
             :note note)
            (if (fboundp 'command-desktop-task-process-supervision-escalation-admin-service)
                (command-desktop-task-process-supervision-escalation-admin-service
                 session
                 :session-id session-id
                 :parent-actor-id target-id
                 :action :recommended
                 :note (or note
                           "Automatically processed by the supervisor escalation lane.")
                 :async-p t)
            (command-desktop-task-process-supervision-escalation-service
             session
             :session-id session-id
             :parent-actor-id target-id
             :action :recommended
             :note (or note
                       "Automatically processed by the supervisor escalation lane."))))))))

(defun command-desktop-task-fail-mailbox-entry-service (session mailbox mailbox-entry-id
                                                        &key session-id approval-id pending-action-id
                                                          actor-message-id summary condition-string
                                                          (supervision-action :escalate-to-parent))
  (let* ((entry
           (update-session-actor-mailbox-entry
            session
            mailbox
            (lambda (current-entry)
              (and (or (null mailbox-entry-id)
                       (string= mailbox-entry-id
                                (actor-mailbox-entry-id current-entry)))
                   (or (null session-id)
                       (let ((entry-session-id (actor-mailbox-entry-session-id current-entry)))
                         (and entry-session-id
                              (string= session-id entry-session-id))))
                   (or (null approval-id)
                       (let ((entry-approval-id (actor-mailbox-entry-approval-id current-entry)))
                         (and entry-approval-id
                              (string= approval-id entry-approval-id))))
                   (or (null pending-action-id)
                       (let ((entry-pending-action-id
                               (actor-mailbox-entry-pending-action-id current-entry)))
                         (and entry-pending-action-id
                              (string= pending-action-id entry-pending-action-id))))
                   (or (null actor-message-id)
                       (let ((entry-actor-message-id
                               (actor-mailbox-entry-actor-message-id current-entry)))
                         (and entry-actor-message-id
                              (string= actor-message-id entry-actor-message-id))))))
            (lambda (current-entry)
              (setf (actor-mailbox-entry-delivery-status current-entry) :failed
                    (actor-mailbox-entry-completed-at current-entry)
                    (or (actor-mailbox-entry-completed-at current-entry)
                        (get-universal-time))
                    (actor-mailbox-entry-metadata current-entry)
                    (append (list :failure-summary summary
                                  :failure-condition condition-string
                                  :supervision-action supervision-action)
                            (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
              current-entry)
            :reason :actor-mailbox-failed))
         (incident
           (record-actor-supervision-incident session
                                              mailbox
                                              entry
                                              :summary summary
                                              :condition-string condition-string
                                              :supervision-action supervision-action))
         (resolved-entry entry)
         (recovery-summary nil)
         (automatic-action nil)
         (escalation-target (mailbox-entry-supervision-escalation-target session entry)))
    (multiple-value-setq (resolved-entry recovery-summary automatic-action)
      (or (apply-automatic-supervision-policy session incident mailbox entry)
          (values entry nil nil)))
    (make-service-command-response
     :desktop-task
     :fail-mailbox-entry
     (list :mailbox mailbox
           :mailbox-entry (actor-mailbox-entry-summary resolved-entry)
           :incident (actor-supervision-incident-summary session incident)
           :automatic-action automatic-action
           :escalation-target escalation-target
           :recovery recovery-summary)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :desktop-task-fail-mailbox-entry-v1
                                      :session session))))

(defun recommended-parent-supervision-action (incident)
  (let* ((metadata (incident-metadata incident))
         (policy-summary (and (listp metadata)
                              (getf metadata :supervision-policy)))
         (strategy (and (listp policy-summary)
                        (getf policy-summary :strategy)))
         (escalation-count (supervision-metadata-escalation-count metadata))
         (group-replacement-count (supervision-metadata-group-replacement-count metadata)))
    (if (>= escalation-count *automatic-supervision-escalation-limit*)
        (case strategy
          (:one-for-all (if (>= group-replacement-count
                                *automatic-supervision-escalation-limit*)
                            :quarantine
                            :replace-child))
          (:root :quarantine)
          (:one-for-one :quarantine)
          (otherwise :dead-letter))
        (case strategy
          (:one-for-all (if (>= group-replacement-count
                                *automatic-supervision-escalation-limit*)
                            :quarantine
                            :replace-child))
          (:one-for-one :restart-child)
          (:root :quarantine)
          (otherwise :quarantine)))))

(defun actor-definition-supervision-strategy* (definition)
  (let ((policy (and definition
                     (actor-definition-supervision-policy definition))))
    (and policy
         (actor-supervision-policy-strategy policy))))

(defun actor-definition-supervision-group-key (definition)
  (let ((allocation (and definition
                         (actor-definition-allocation-strategy definition))))
    (when definition
      (list :parent-actor-id (actor-definition-parent-actor-id definition)
            :role (actor-definition-role definition)
            :shared-inbox-id (and allocation
                                  (actor-allocation-strategy-shared-inbox-id allocation))
            :inbox-id (actor-definition-inbox-id definition)))))

(defun supervision-related-sibling-entries (session failed-entry mailbox)
  (let* ((failed-definition (actor-mailbox-entry-actor-definition session failed-entry))
         (failed-key (actor-definition-supervision-group-key failed-definition))
         (failed-id (actor-mailbox-entry-id failed-entry)))
    (if (null failed-key)
        '()
        (remove-if-not
         (lambda (entry)
           (and (not (string= failed-id (actor-mailbox-entry-id entry)))
                (member (actor-mailbox-entry-delivery-status entry)
                        '(:queued :dequeued :authorized :pending :available :issued :in-flight)
                        :test #'eq)
                (let ((definition (actor-mailbox-entry-actor-definition session entry)))
                  (equal failed-key
                         (actor-definition-supervision-group-key definition)))))
         (actor-mailbox-entries session mailbox)))))

(defun resolve-supervision-action (session incident requested-action)
  (if (eq requested-action :recommended)
      (or (getf (supervision-workflow-recovery-policy session
                                                      (incident-metadata incident))
                :recommended-supervision-action)
          (recommended-parent-supervision-action incident)
          (error "Supervision incident ~A does not have a recommended recovery action"
                 (incident-id incident)))
      requested-action))

(defun apply-work-item-supervision-recovery-action (session mailbox mailbox-entry-id action note)
  (let* ((failed-entry
           (find-actor-mailbox-entry session
                                     mailbox
                                     :mailbox-entry-id mailbox-entry-id))
         (metadata (and failed-entry
                        (actor-mailbox-entry-metadata failed-entry)))
         (work-item-id (or (and metadata (getf metadata :work-item-id))
                           (error "Mailbox entry ~A does not identify a work item"
                                  mailbox-entry-id)))
         (response
           (case action
             (:resume-work-item
              (command-work-item-resume-service session work-item-id :note note))
             (:complete-validations
              (command-work-item-complete-validations-service session work-item-id))
             (:rollback-work-item
              (command-work-item-rollback-service session
                                                  work-item-id
                                                  :reason :supervision-recovery
                                                  :note note))
             (otherwise
              (error "Unsupported workflow supervision recovery action ~A" action))))
         (workflow-result (service-response-data response)))
    (values
     (update-session-actor-mailbox-entry
      session
      mailbox
      (lambda (current-entry)
        (string= mailbox-entry-id
                 (actor-mailbox-entry-id current-entry)))
      (lambda (current-entry)
        (setf (actor-mailbox-entry-delivery-status current-entry) :recovered
              (actor-mailbox-entry-completed-at current-entry)
              (or (actor-mailbox-entry-completed-at current-entry)
                  (get-universal-time))
              (actor-mailbox-entry-metadata current-entry)
              (append (list :supervision-resolution-action action
                            :supervision-resolution-note note
                            :workflow-recovery-p t
                            :recovery-origin :supervision
                            :recovered-work-item-id work-item-id
                            :recovered-work-item-status (getf workflow-result :status))
                      (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
        current-entry)
      :reason :actor-supervision-workflow-recovery)
     (list :recoverable-p t
           :recovery-origin :supervision
           :workflow-action action
           :replay-class (case action
                           (:complete-validations :validation-replay)
                           (:rollback-work-item :rollback-replay)
                           (:resume-work-item :operator-review-replay)
                           (otherwise :state-restoration))
           :work-item-id work-item-id
           :work-item-status (getf workflow-result :status)
           :workflow-record-id (getf workflow-result :workflow-record-id)
           :workflow-result workflow-result))))

(defun apply-supervision-action-to-mailbox-entry (session mailbox mailbox-entry-id action note)
  (ecase action
    (:dead-letter
     (update-session-actor-mailbox-entry
      session
      mailbox
      (lambda (current-entry)
        (string= mailbox-entry-id
                 (actor-mailbox-entry-id current-entry)))
      (lambda (current-entry)
        (setf (actor-mailbox-entry-delivery-status current-entry) :dead-lettered
              (actor-mailbox-entry-completed-at current-entry)
              (or (actor-mailbox-entry-completed-at current-entry)
                  (get-universal-time))
              (actor-mailbox-entry-metadata current-entry)
              (append (list :supervision-resolution-action action
                            :supervision-resolution-note note)
                      (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
        current-entry)
      :reason :actor-supervision-dead-letter))
    (:quarantine
     (update-session-actor-mailbox-entry
      session
      mailbox
      (lambda (current-entry)
        (string= mailbox-entry-id
                 (actor-mailbox-entry-id current-entry)))
      (lambda (current-entry)
        (setf (actor-mailbox-entry-delivery-status current-entry) :quarantined
              (actor-mailbox-entry-completed-at current-entry)
              (or (actor-mailbox-entry-completed-at current-entry)
                  (get-universal-time))
              (actor-mailbox-entry-metadata current-entry)
              (append (list :supervision-resolution-action action
                            :supervision-resolution-note note)
                      (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
        current-entry)
      :reason :actor-supervision-quarantine))
    (:escalate-to-parent
     (let* ((failed-entry
              (find-actor-mailbox-entry session
                                        mailbox
                                        :mailbox-entry-id mailbox-entry-id))
            (escalation-count
              (and failed-entry
                   (1+ (mailbox-entry-supervision-escalation-count failed-entry))))
            (escalation-target
              (and failed-entry
                   (mailbox-entry-supervision-escalation-target session failed-entry)))
            (escalation-owner
              (or (and escalation-target
                       (make-standard-actor-address
                        :actor-system
                        :scope (actor-mailbox-entry-session-id failed-entry)
                        :display-name "Actor System"
                        :metadata (append (when (actor-mailbox-entry-session-id failed-entry)
                                            (list :session-id
                                                  (actor-mailbox-entry-session-id failed-entry)))
                                          (list :actor-id escalation-target
                                                :escalation-target escalation-target
                                                :actor-class :supervision-target))))
                  (actor-mailbox-entry-owner failed-entry)))
            (escalation-entry
              (make-actor-mailbox-entry
               :id (format nil "~A/escalation-~D-~D"
                           mailbox-entry-id
                           (get-universal-time)
                           (random 1000000))
               :owner escalation-owner
               :mailbox :supervision-escalation-inbox
               :direction :inbox
               :session-id (actor-mailbox-entry-session-id failed-entry)
               :approval-id (actor-mailbox-entry-approval-id failed-entry)
               :pending-action-id (actor-mailbox-entry-pending-action-id failed-entry)
               :actor-message-id (actor-mailbox-entry-actor-message-id failed-entry)
               :request-id (actor-mailbox-entry-request-id failed-entry)
               :target (actor-mailbox-entry-target failed-entry)
               :operation (actor-mailbox-entry-operation failed-entry)
               :status :queued
               :governance-status (actor-mailbox-entry-governance-status failed-entry)
               :approval-status (actor-mailbox-entry-approval-status failed-entry)
               :delivery-status :queued
               :sent-at (get-universal-time)
               :delivered-at (get-universal-time)
               :reply-to (actor-mailbox-entry-reply-to failed-entry)
               :originator (actor-mailbox-entry-originator failed-entry)
               :sender (actor-mailbox-entry-sender failed-entry)
               :receiver escalation-owner
               :payload (list :mailbox-entry-id mailbox-entry-id
                              :request-id (actor-mailbox-entry-request-id failed-entry)
                              :actor-message-id (actor-mailbox-entry-actor-message-id failed-entry)
                              :actor-id (and (actor-mailbox-entry-owner failed-entry)
                                             (actor-address-id (actor-mailbox-entry-owner failed-entry)))
                              :target (actor-mailbox-entry-target failed-entry)
                              :operation (actor-mailbox-entry-operation failed-entry)
                              :supervision-escalation-count escalation-count
                              :escalation-target escalation-target
                              :summary "Escalated actor supervision event.")
               :metadata (append (list :escalated-from-mailbox-entry-id mailbox-entry-id
                                       :supervision-resolution-action action
                                       :supervision-resolution-note note
                                       :supervision-escalation-count escalation-count
                                       :escalation-target escalation-target)
                                 (copy-tree (or (actor-mailbox-entry-metadata failed-entry) '()))))))
       (append-session-actor-mailbox-entry session
                                           :supervision-escalation-inbox
                                           escalation-entry
                                           :reason :actor-supervision-escalation)
       (maybe-auto-process-routed-supervision-escalation
        session
        escalation-entry
        :note "Automatically processed from root supervisor escalation routing.")
       (values
        (update-session-actor-mailbox-entry
         session
         mailbox
         (lambda (current-entry)
           (string= mailbox-entry-id
                    (actor-mailbox-entry-id current-entry)))
         (lambda (current-entry)
           (setf (actor-mailbox-entry-delivery-status current-entry) :quarantined
                 (actor-mailbox-entry-completed-at current-entry)
                 (or (actor-mailbox-entry-completed-at current-entry)
                     (get-universal-time))
                 (actor-mailbox-entry-metadata current-entry)
                 (append (list :supervision-resolution-action action
                               :supervision-resolution-note note
                               :supervision-escalated-p t
                               :supervision-escalation-count escalation-count
                               :escalation-target escalation-target
                               :escalation-mailbox-entry-id
                               (actor-mailbox-entry-id escalation-entry))
                         (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
           current-entry)
         :reason :actor-supervision-escalate-to-parent)
        (list :recoverable-p t
              :recovery-origin :supervision
              :escalated-p t
              :supervision-escalation-count escalation-count
              :escalation-target escalation-target
              :escalation-mailbox :supervision-escalation-inbox
              :escalation-mailbox-entry-id (actor-mailbox-entry-id escalation-entry)
              :replay-class :parent-escalation
              :workflow-action action))))
    (:restart-child
     (let* ((failed-entry
              (find-actor-mailbox-entry session
                                        mailbox
                                        :mailbox-entry-id mailbox-entry-id))
            (policy (and failed-entry
                         (mailbox-entry-supervision-policy session failed-entry)))
            (restart-timestamps
              (next-supervision-restart-history failed-entry policy))
            (restart-count
              (length restart-timestamps))
            (restarted-entry
              (make-actor-mailbox-entry
               :id (format nil "~A/restart-~D-~D"
                           mailbox-entry-id
                           (get-universal-time)
                           (random 1000000))
               :owner (actor-mailbox-entry-owner failed-entry)
               :mailbox mailbox
               :direction (actor-mailbox-entry-direction failed-entry)
               :session-id (actor-mailbox-entry-session-id failed-entry)
               :approval-id (actor-mailbox-entry-approval-id failed-entry)
               :pending-action-id (actor-mailbox-entry-pending-action-id failed-entry)
               :actor-message-id (actor-mailbox-entry-actor-message-id failed-entry)
               :request-id (actor-mailbox-entry-request-id failed-entry)
               :target (actor-mailbox-entry-target failed-entry)
               :operation (actor-mailbox-entry-operation failed-entry)
               :status :queued
               :governance-status (actor-mailbox-entry-governance-status failed-entry)
               :approval-status (actor-mailbox-entry-approval-status failed-entry)
               :delivery-status :queued
               :sent-at (get-universal-time)
               :delivered-at (get-universal-time)
               :reply-to (actor-mailbox-entry-reply-to failed-entry)
               :originator (actor-mailbox-entry-originator failed-entry)
               :sender (actor-mailbox-entry-sender failed-entry)
               :receiver (actor-mailbox-entry-receiver failed-entry)
               :payload (copy-tree (actor-mailbox-entry-payload failed-entry))
               :metadata (append (list :restarted-from-mailbox-entry-id mailbox-entry-id
                                       :supervision-resolution-action action
                                       :supervision-resolution-note note
                                       :supervision-restart-count restart-count
                                       :supervision-restart-timestamps restart-timestamps)
                                 (copy-tree (or (actor-mailbox-entry-metadata failed-entry) '()))))))
       (append-session-actor-mailbox-entry session
                                           mailbox
                                           restarted-entry
                                           :reason :actor-supervision-restart-child)))
    (:replace-child
     (let* ((failed-entry
              (find-actor-mailbox-entry session
                                        mailbox
                                        :mailbox-entry-id mailbox-entry-id))
            (failed-definition
              (and failed-entry
                   (actor-mailbox-entry-actor-definition session failed-entry)))
            (strategy (actor-definition-supervision-strategy* failed-definition))
            (group-replacement-count
              (1+ (supervision-metadata-group-replacement-count
                   (and failed-entry
                        (actor-mailbox-entry-metadata failed-entry)))))
            (sibling-entries
              (if (eq strategy :one-for-all)
                  (supervision-related-sibling-entries session failed-entry mailbox)
                  '()))
            (owner (actor-mailbox-entry-owner failed-entry))
            (replacement-owner
              (and owner
                   (make-standard-actor-address
                    (actor-address-role owner)
                    :kind (actor-address-kind owner)
                    :display-name (actor-address-display-name owner)
                    :scope (or (getf (actor-address-metadata owner) :scope-id)
                               (getf (actor-address-metadata owner) :session-id)
                               (actor-mailbox-entry-session-id failed-entry))
                    :metadata (append (copy-tree (or (actor-address-metadata owner) '()))
                                      (list :replacement-issued-at (get-universal-time))))))
            (replacement-entry
              (make-actor-mailbox-entry
               :id (format nil "~A/replacement-~D-~D"
                           mailbox-entry-id
                           (get-universal-time)
                           (random 1000000))
               :owner replacement-owner
               :mailbox mailbox
               :direction (actor-mailbox-entry-direction failed-entry)
               :session-id (actor-mailbox-entry-session-id failed-entry)
               :approval-id (actor-mailbox-entry-approval-id failed-entry)
               :pending-action-id (actor-mailbox-entry-pending-action-id failed-entry)
               :actor-message-id (actor-mailbox-entry-actor-message-id failed-entry)
               :request-id (actor-mailbox-entry-request-id failed-entry)
               :target (actor-mailbox-entry-target failed-entry)
               :operation (actor-mailbox-entry-operation failed-entry)
               :status :queued
               :governance-status (actor-mailbox-entry-governance-status failed-entry)
               :approval-status (actor-mailbox-entry-approval-status failed-entry)
               :delivery-status :queued
               :sent-at (get-universal-time)
               :delivered-at (get-universal-time)
               :reply-to (actor-mailbox-entry-reply-to failed-entry)
               :originator (actor-mailbox-entry-originator failed-entry)
               :sender (actor-mailbox-entry-sender failed-entry)
               :receiver (actor-mailbox-entry-receiver failed-entry)
               :payload (copy-tree (actor-mailbox-entry-payload failed-entry))
               :metadata (append (list :replaced-from-mailbox-entry-id mailbox-entry-id
                                       :supervision-resolution-action action
                                       :supervision-resolution-note note
                                       :supervision-group-replacement-count group-replacement-count)
                                 (copy-tree (or (actor-mailbox-entry-metadata failed-entry) '()))))))
       (append-session-actor-mailbox-entry session
                                           mailbox
                                           replacement-entry
                                           :reason :actor-supervision-replace-child)
       (dolist (sibling sibling-entries)
         (let ((sibling-id (actor-mailbox-entry-id sibling))
               (sibling-owner (actor-mailbox-entry-owner sibling)))
           (append-session-actor-mailbox-entry
            session
            mailbox
            (make-actor-mailbox-entry
             :id (format nil "~A/replacement-~D-~D"
                         sibling-id
                         (get-universal-time)
                         (random 1000000))
             :owner (and sibling-owner
                         (make-standard-actor-address
                          (actor-address-role sibling-owner)
                          :kind (actor-address-kind sibling-owner)
                          :display-name (actor-address-display-name sibling-owner)
                          :scope (or (getf (actor-address-metadata sibling-owner) :scope-id)
                                     (getf (actor-address-metadata sibling-owner) :session-id)
                                     (actor-mailbox-entry-session-id sibling))
                          :metadata (append (copy-tree (or (actor-address-metadata sibling-owner) '()))
                                            (list :replacement-issued-at (get-universal-time)
                                                  :one-for-all-replacement-p t))))
             :mailbox mailbox
             :direction (actor-mailbox-entry-direction sibling)
             :session-id (actor-mailbox-entry-session-id sibling)
             :approval-id (actor-mailbox-entry-approval-id sibling)
             :pending-action-id (actor-mailbox-entry-pending-action-id sibling)
             :actor-message-id (actor-mailbox-entry-actor-message-id sibling)
             :request-id (actor-mailbox-entry-request-id sibling)
             :target (actor-mailbox-entry-target sibling)
             :operation (actor-mailbox-entry-operation sibling)
             :status :queued
             :governance-status (actor-mailbox-entry-governance-status sibling)
             :approval-status (actor-mailbox-entry-approval-status sibling)
             :delivery-status :queued
             :sent-at (get-universal-time)
             :delivered-at (get-universal-time)
             :reply-to (actor-mailbox-entry-reply-to sibling)
             :originator (actor-mailbox-entry-originator sibling)
             :sender (actor-mailbox-entry-sender sibling)
             :receiver (actor-mailbox-entry-receiver sibling)
             :payload (copy-tree (actor-mailbox-entry-payload sibling))
             :metadata (append (list :replaced-from-mailbox-entry-id sibling-id
                                     :supervision-resolution-action action
                                     :supervision-resolution-note note
                                     :supervision-group-replacement-count group-replacement-count
                                     :one-for-all-replacement-p t
                                     :group-trigger-mailbox-entry-id mailbox-entry-id)
                               (copy-tree (or (actor-mailbox-entry-metadata sibling) '()))))
            :reason :actor-supervision-replace-child)
           (update-session-actor-mailbox-entry
            session
            mailbox
            (lambda (current-entry)
              (string= sibling-id
                       (actor-mailbox-entry-id current-entry)))
            (lambda (current-entry)
              (setf (actor-mailbox-entry-delivery-status current-entry) :quarantined
                    (actor-mailbox-entry-completed-at current-entry)
                    (or (actor-mailbox-entry-completed-at current-entry)
                        (get-universal-time))
                    (actor-mailbox-entry-metadata current-entry)
                    (append (list :supervision-resolution-action action
                                  :supervision-resolution-note note
                                  :supervision-group-replacement-count group-replacement-count
                                  :one-for-all-sibling-p t
                                  :group-trigger-mailbox-entry-id mailbox-entry-id)
                            (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
              current-entry)
            :reason :actor-supervision-replace-child)))
       (update-session-actor-mailbox-entry
        session
        mailbox
        (lambda (current-entry)
          (string= mailbox-entry-id
                   (actor-mailbox-entry-id current-entry)))
        (lambda (current-entry)
          (setf (actor-mailbox-entry-metadata current-entry)
                (append (list :supervision-group-replacement-count group-replacement-count)
                        (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
          current-entry)
        :reason :actor-supervision-replace-child)
       (values replacement-entry
               (list :recoverable-p t
                     :recovery-origin :supervision
                     :workflow-action action
                     :replay-class (if (eq strategy :one-for-all)
                                       :sibling-group-replacement
                                       :state-restoration)
                     :supervision-group-replacement-count group-replacement-count
                     :sibling-replacement-count (length sibling-entries)
                     :sibling-mailbox-entry-ids
                     (mapcar #'actor-mailbox-entry-id sibling-entries)))))
    (:resume-from-checkpoint
     (let* ((failed-entry
              (find-actor-mailbox-entry session
                                        mailbox
                                        :mailbox-entry-id mailbox-entry-id))
            (pending-action-id (and failed-entry
                                    (actor-mailbox-entry-pending-action-id failed-entry)))
            (metadata (and failed-entry
                           (actor-mailbox-entry-metadata failed-entry)))
            (candidate (recoverable-work-item-turn-resume-candidate
                        session
                        :pending-action-id pending-action-id
                        :work-item-id (and metadata (getf metadata :work-item-id))
                        :workflow-record-id (and metadata (getf metadata :workflow-record-id))
                        :turn-id (and metadata (getf metadata :turn-id))))
            (recovery-summary (supervision-checkpoint-recovery-summary candidate)))
       (unless failed-entry
         (error "Unknown mailbox entry ~A in ~A" mailbox-entry-id mailbox))
       (unless candidate
         (error "Mailbox entry ~A does not map to a recoverable workflow continuation checkpoint"
                mailbox-entry-id))
       (unless (fboundp 'recover-turn-resume-from-workflow-checkpoint)
         (error "Workflow checkpoint recovery support is unavailable"))
       (recover-turn-resume-from-workflow-checkpoint
        session
        (getf candidate :turn)
        :recovery-origin :supervision)
       (values
        (update-session-actor-mailbox-entry
         session
         mailbox
         (lambda (current-entry)
           (string= mailbox-entry-id
                    (actor-mailbox-entry-id current-entry)))
         (lambda (current-entry)
           (setf (actor-mailbox-entry-delivery-status current-entry) :recovered
                 (actor-mailbox-entry-completed-at current-entry)
                 (or (actor-mailbox-entry-completed-at current-entry)
                     (get-universal-time))
                 (actor-mailbox-entry-metadata current-entry)
                 (append (list :supervision-resolution-action action
                               :supervision-resolution-note note
                               :checkpoint-recovery-p t
                               :recovery-origin :supervision
                               :recovered-turn-id (getf recovery-summary :turn-id)
                               :recovered-work-item-id (getf recovery-summary :work-item-id))
                         (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
           current-entry)
         :reason :actor-supervision-resume-from-checkpoint)
        recovery-summary)))
    ((:resume-work-item :complete-validations :rollback-work-item)
     (apply-work-item-supervision-recovery-action session
                                                  mailbox
                                                  mailbox-entry-id
                                                  action
                                                  note))))

(defun command-desktop-task-apply-supervision-action-service (session incident-id
                                                              &key (action :dead-letter)
                                                                note)
  (let* ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown supervision incident ~A" incident-id))
    (unless (actor-supervision-incident-p incident)
      (error "Incident ~A is not an actor supervision incident" incident-id))
    (let* ((metadata (incident-metadata incident))
           (mailbox (or (getf metadata :mailbox)
                        (error "Supervision incident ~A does not identify a mailbox" incident-id)))
           (mailbox-entry-id (or (getf metadata :mailbox-entry-id)
                                 (error "Supervision incident ~A does not identify a mailbox entry" incident-id)))
           (effective-action (resolve-supervision-action session incident action))
           (entry nil)
           (recovery-summary nil))
      (multiple-value-setq (entry recovery-summary)
        (apply-supervision-action-to-mailbox-entry session
                                                   mailbox
                                                   mailbox-entry-id
                                                   effective-action
                                                   note))
      (unless entry
        (error "Unknown mailbox entry ~A in ~A" mailbox-entry-id mailbox))
      (setf (incident-status incident)
            (case effective-action
              (:escalate-to-parent :resolved)
              (:quarantine :quarantined)
              (otherwise :resolved))
            (incident-metadata incident)
            (append (list :resolution-action effective-action
                          :requested-action action
                          :resolution-note note
                          :recovery (copy-tree recovery-summary)
                          :resolved-at (get-universal-time))
                    (copy-tree metadata)))
      (when (fboundp 'append-session-event)
        (append-session-event session
                              :actor-supervision-action-applied
                              (list :incident-id incident-id
                                    :action effective-action
                                    :requested-action action
                                    :mailbox mailbox
                                    :mailbox-entry-id mailbox-entry-id
                                    :recovery recovery-summary)
                              :family :actor
                              :entity-id incident-id
                              :metadata (list :mailbox mailbox
                                              :mailbox-entry-id mailbox-entry-id
                                              :action effective-action
                                              :requested-action action
                                              :recovery-origin (and recovery-summary
                                                                    :supervision)
                                              :replay-class (and recovery-summary
                                                                 (or (getf recovery-summary :replay-class)
                                                                     (case effective-action
                                                                       (:escalate-to-parent :parent-escalation)
                                                                       (:resume-from-checkpoint :turn-resume-replay)
                                                                       (:complete-validations :validation-replay)
                                                                       (:rollback-work-item :rollback-replay)
                                                                       (:resume-work-item :operator-review-replay)
                                                                       (otherwise nil)))))))
      (when (fboundp 'record-actor-supervision-runtime-history)
        (record-actor-supervision-runtime-history session
                                                  entry
                                                  effective-action
                                                  :incident incident
                                                  :recovery-summary recovery-summary
                                                  :automatic-p nil))
      (make-service-command-response
       :desktop-task
       :apply-supervision-action
       (list :incident (actor-supervision-incident-summary session incident)
             :mailbox mailbox
             :mailbox-entry (actor-mailbox-entry-summary entry)
             :recovery recovery-summary
             :requested-action action
             :action effective-action)
       :metadata (make-service-metadata :authority :environment
                                        :command-model :desktop-task-apply-supervision-action-v1
                                        :session session)))))

(defun command-desktop-task-apply-supervision-escalation-service (session mailbox-entry-id
                                                                  &key session-id actor-message-id
                                                                    (action :recommended)
                                                                    note)
  (let* ((escalation-entry
           (find-actor-mailbox-entry session
                                     :supervision-escalation-inbox
                                     :mailbox-entry-id mailbox-entry-id
                                     :session-id session-id
                                     :actor-message-id actor-message-id))
         (failed-mailbox-entry-id
           (and escalation-entry
                (or (getf (actor-mailbox-entry-payload escalation-entry) :mailbox-entry-id)
                    (getf (actor-mailbox-entry-metadata escalation-entry)
                          :escalated-from-mailbox-entry-id))))
         (incident
           (and failed-mailbox-entry-id
                (find-actor-supervision-incident-for-mailbox-entry
                 session
                 failed-mailbox-entry-id
                 :session-id (or session-id
                                 (and escalation-entry
                                      (actor-mailbox-entry-session-id escalation-entry)))
                 :actor-message-id (or actor-message-id
                                       (and escalation-entry
                                            (actor-mailbox-entry-actor-message-id escalation-entry)))
                 :open-only-p t))))
    (unless escalation-entry
      (error "Unknown supervision escalation mailbox entry ~A." mailbox-entry-id))
    (unless failed-mailbox-entry-id
      (error "Supervision escalation mailbox entry ~A is missing the failed mailbox entry reference."
             mailbox-entry-id))
    (unless incident
      (error "No open actor supervision incident remains for escalated mailbox entry ~A."
             failed-mailbox-entry-id))
    (let* ((response
             (service-response-data
              (command-desktop-task-apply-supervision-action-service
               session
               (incident-id incident)
               :action action
               :note note)))
           (resolved-action (getf response :action))
           (recovery (getf response :recovery))
           (updated-entry
             (update-session-actor-mailbox-entry
              session
              :supervision-escalation-inbox
              (lambda (current-entry)
                (string= mailbox-entry-id
                         (actor-mailbox-entry-id current-entry)))
              (lambda (current-entry)
                (setf (actor-mailbox-entry-delivery-status current-entry) :resolved
                      (actor-mailbox-entry-dequeued-at current-entry)
                      (or (actor-mailbox-entry-dequeued-at current-entry)
                          (get-universal-time))
                      (actor-mailbox-entry-acknowledged-at current-entry)
                      (or (actor-mailbox-entry-acknowledged-at current-entry)
                          (get-universal-time))
                      (actor-mailbox-entry-completed-at current-entry)
                      (or (actor-mailbox-entry-completed-at current-entry)
                          (get-universal-time))
                      (actor-mailbox-entry-metadata current-entry)
                      (append (list :supervision-resolution-action resolved-action
                                    :supervision-resolution-note note
                                    :linked-incident-id (incident-id incident)
                                    :recovery (copy-tree recovery))
                              (copy-tree (or (actor-mailbox-entry-metadata current-entry) '()))))
                current-entry)
              :reason :actor-supervision-escalation-applied)))
      (make-service-command-response
       :desktop-task
       :apply-supervision-escalation
       (list :mailbox-entry (actor-mailbox-entry-summary updated-entry)
             :incident (actor-supervision-incident-summary session incident)
             :failed-mailbox-entry-id failed-mailbox-entry-id
             :requested-action action
             :action resolved-action
             :recovery recovery)
       :metadata (make-service-metadata :authority :environment
                                        :command-model :desktop-task-apply-supervision-escalation-v1
                                        :session session)))))

(defun command-desktop-task-process-supervision-escalation-service (session
                                                                    &key session-id actor-id
                                                                      parent-actor-id
                                                                      (action :recommended)
                                                                      note)
  (make-service-command-response
   :desktop-task
   :process-supervision-escalation
   (process-next-supervision-escalation
    session
    :session-id session-id
    :actor-id actor-id
    :parent-actor-id parent-actor-id
    :action action
    :note note)
   :metadata (make-service-metadata :authority :environment
                                    :command-model :desktop-task-process-supervision-escalation-v1
                                    :session session)))

(defun desktop-task-actor-role-for-record (record &key (direction :receiver))
  (let ((message (desktop-task-actor-message-for-record record)))
    (when message
      (case direction
        (:sender (and (actor-message-sender message)
                      (actor-address-role (actor-message-sender message))))
        (otherwise (and (actor-message-receiver message)
                        (actor-address-role (actor-message-receiver message))))))))

(defun desktop-task-actor-address-for-record (record &key (direction :receiver))
  (let ((message (desktop-task-actor-message-for-record record)))
    (when message
      (case direction
        (:sender (actor-message-sender message))
        (otherwise (actor-message-receiver message))))))

(defun actor-allocation-strategy-summary (strategy)
  (when strategy
    (list :type (actor-allocation-strategy-type strategy)
          :shared-inbox-id (actor-allocation-strategy-shared-inbox-id strategy)
          :pool-size (actor-allocation-strategy-pool-size strategy)
          :consumption-policy (actor-allocation-strategy-consumption-policy strategy)
          :metadata (copy-tree (or (actor-allocation-strategy-metadata strategy) '())))))
