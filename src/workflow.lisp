(in-package #:sbcl-agent)

(defstruct workflow-entry
  phase
  kind
  timestamp
  payload)

(defstruct workflow-record
  id
  plan-id
  work-item-id
  goal
  status
  created-at
  updated-at
  entries
  entries-tail
  conclusion
  evidence
  waiting-on
  approval-requirements
  pending-validations
  next-action
  resume-payload
  continuation-checkpoints
  suspension-notes
  quarantine-reason
  resume-count
  operator-interventions)

(defun rebuild-workflow-record-tails (session)
  (dolist (record (agent-session-workflow-records session))
    (setf (workflow-record-entries-tail record)
          (last (workflow-record-entries record))))
  session)

(defun make-workflow-record-id ()
  (format nil "wf-~D-~D" (get-universal-time) (random 1000000)))

(defun workflow-record-actor-execution-job-ids (record)
  (delete-duplicates
   (remove nil
           (append
            (mapcar (lambda (entry)
                      (let ((payload (workflow-entry-payload entry)))
                        (and (listp payload)
                             (or (getf payload :execution-id)
                                 (getf payload :actor-execution-job-id)))))
                    (workflow-record-entries record))
            (mapcar (lambda (evidence)
                      (and (listp evidence)
                           (or (getf evidence :actor-execution-job-id)
                               (getf evidence :execution-id))))
                    (workflow-record-evidence record))))
   :test #'string=))

(defun workflow-record-latest-actor-execution-job-id (record)
  (or (loop for evidence in (reverse (workflow-record-evidence record))
            for actor-job-id = (and (listp evidence)
                                    (or (getf evidence :actor-execution-job-id)
                                        (getf evidence :execution-id)))
            thereis actor-job-id)
      (loop for entry in (reverse (workflow-record-entries record))
            for payload = (workflow-entry-payload entry)
            for actor-job-id = (and (listp payload)
                                    (or (getf payload :execution-id)
                                        (getf payload :actor-execution-job-id)))
            thereis actor-job-id)))

(defun workflow-entry-summary (entry)
  (list :phase (workflow-entry-phase entry)
        :kind (workflow-entry-kind entry)
        :timestamp (workflow-entry-timestamp entry)
        :payload (workflow-entry-payload entry)))

(defun workflow-record-summary (record)
  (list :id (workflow-record-id record)
        :plan-id (workflow-record-plan-id record)
        :work-item-id (workflow-record-work-item-id record)
        :goal (workflow-record-goal record)
        :status (workflow-record-status record)
        :created-at (workflow-record-created-at record)
        :updated-at (workflow-record-updated-at record)
        :waiting-on (workflow-record-waiting-on record)
        :approval-requirements (workflow-record-approval-requirements record)
        :pending-validations (workflow-record-pending-validations record)
        :next-action (workflow-record-next-action record)
        :resume-payload (workflow-record-resume-payload record)
        :continuation-checkpoint-count (length (workflow-record-continuation-checkpoints record))
        :suspension-notes (workflow-record-suspension-notes record)
        :quarantine-reason (workflow-record-quarantine-reason record)
        :actor-execution-job-id (workflow-record-latest-actor-execution-job-id record)
        :actor-execution-job-ids (workflow-record-actor-execution-job-ids record)
        :resume-count (workflow-record-resume-count record)
        :operator-intervention-count (length (workflow-record-operator-interventions record))
        :entry-count (length (workflow-record-entries record))
        :conclusion (workflow-record-conclusion record)))

(defun workflow-record-detail (record)
  (append (workflow-record-summary record)
          (list :entries (mapcar #'workflow-entry-summary (workflow-record-entries record))
                :continuation-checkpoints (copy-tree (workflow-record-continuation-checkpoints record))
                :operator-interventions (workflow-record-operator-interventions record)
                :evidence (workflow-record-evidence record))))

(defun latest-workflow-record-continuation-checkpoint (record)
  (car (last (workflow-record-continuation-checkpoints record))))

(defun append-workflow-record-continuation-checkpoint (record checkpoint)
  (setf (workflow-record-continuation-checkpoints record)
        (append (workflow-record-continuation-checkpoints record)
                (list checkpoint))
        (workflow-record-updated-at record) (get-universal-time))
  checkpoint)

(defun update-latest-workflow-record-continuation-checkpoint (record updater)
  (let* ((checkpoints (workflow-record-continuation-checkpoints record))
         (tail (last checkpoints))
         (latest (car tail)))
    (when latest
      (let ((updated (funcall updater latest)))
        (when (and updated
                   (listp updated)
                   (or (null updated)
                       (keywordp (first updated))))
          (setf (car tail) updated)))
      (setf (workflow-record-updated-at record) (get-universal-time)))
    latest))

(defun current-workflow-entry-actor-metadata ()
  (let* ((job (and (fboundp 'current-actor-execution-job)
                   (current-actor-execution-job)))
         (context (and job (actor-execution-job-context job)))
         (summary (and context (actor-execution-context-summary context))))
    (when summary
      (list :actor-execution-job-id (or (and (fboundp 'current-actor-execution-job-id)
                                             (current-actor-execution-job-id))
                                        (getf summary :request-id))
            :actor-id (getf summary :actor-id)
            :actor-capability (getf summary :capability)
            :actor-authority (getf summary :authority)
            :actor-target (getf summary :target)
            :actor-operation (getf summary :operation)
            :work-item-id (getf summary :work-item-id)
            :workflow-record-id (getf summary :workflow-record-id)
            :plan-id (getf summary :plan-id)))))

(defun current-workflow-event-metadata ()
  (let ((actor-metadata (current-workflow-entry-actor-metadata)))
    (when actor-metadata
      (append actor-metadata
              (list :actor-event-stream :workflow
                    :event-origin :actor-runtime
                    :actor-origin-p t)))))

(defun workflow-checkpoint-recovery-event-metadata (session record checkpoint
                                                            &key (recovery-origin :session-load))
  (let ((actor-id (or (and checkpoint (getf checkpoint :actor-id))
                      (format nil "actor/workflow/~A" (agent-session-id session)))))
    (list :actor-id actor-id
          :actor-execution-job-id (and checkpoint
                                       (getf checkpoint :actor-execution-job-id))
          :actor-capability :workflow/recover-turn-resume
          :actor-authority (if (eq recovery-origin :session-load)
                               :system-recovery
                               :operator)
          :actor-target :workflow
          :actor-operation :recover-turn-resume
          :replay-class :turn-resume-replay
          :work-item-id (workflow-record-work-item-id record)
          :workflow-record-id (workflow-record-id record)
          :plan-id (workflow-record-plan-id record)
          :actor-event-stream :workflow
          :event-origin :workflow-checkpoint-recovery
          :actor-origin-p t
          :recovery-origin recovery-origin)))

(defun enrich-workflow-entry-payload-with-actor-metadata (payload)
  (let ((actor-metadata (current-workflow-entry-actor-metadata)))
    (cond
      ((null actor-metadata)
       payload)
      ((and (listp payload)
            (or (null payload)
                (keywordp (first payload))))
       (append payload
               (loop for (key value) on actor-metadata by #'cddr
                     unless (getf payload key)
                     append (list key value))))
      (t
       (append (list :value payload)
               actor-metadata)))))

(defun workflow-record-native-actor-links (session record)
  (let* ((session-id (agent-session-id session))
         (context-chat-actor-id (format nil "actor/context-chat/~A" session-id))
         (workflow-actor-id (format nil "actor/workflow/~A" session-id))
         (governance-actor-id (format nil "actor/governance/~A" session-id)))
    (remove nil
            (mapcar
             (lambda (entry)
               (let ((kind (workflow-entry-kind entry))
                     (timestamp (workflow-entry-timestamp entry))
                     (payload (workflow-entry-payload entry)))
                 (cond
                   ((eq kind :turn-resume-started)
                    (list :from-actor-id context-chat-actor-id
                          :to-actor-id workflow-actor-id
                          :from-role :context-chat
                          :to-role :workflow
                          :provenance :workflow-record
                          :workflow-record-id (workflow-record-id record)
                          :work-item-id (workflow-record-work-item-id record)
                          :plan-id (workflow-record-plan-id record)
                          :phase :resume
                          :operation :resume-turn
                          :message-count 1
                          :recent-count 1
                          :failed-count 0
                          :latest-status :resumed
                          :latest-created-at timestamp
                          :actor-execution-job-id (and (listp payload)
                                                       (getf payload :actor-execution-job-id))))
                   ((eq kind :turn-resume-failed)
                    (list :from-actor-id workflow-actor-id
                          :to-actor-id context-chat-actor-id
                          :from-role :workflow
                          :to-role :context-chat
                          :provenance :workflow-record
                          :workflow-record-id (workflow-record-id record)
                          :work-item-id (workflow-record-work-item-id record)
                          :plan-id (workflow-record-plan-id record)
                          :phase :resume
                          :operation :resume-turn-failed
                          :message-count 1
                          :recent-count 1
                          :failed-count 1
                          :latest-status :failed
                          :latest-created-at timestamp
                          :actor-execution-job-id (and (listp payload)
                                                       (getf payload :actor-execution-job-id))))
                   ((eq kind :turn-resume-recovered)
                    (list :from-actor-id (or (and (listp payload)
                                                  (getf payload :actor-id))
                                             workflow-actor-id)
                          :to-actor-id workflow-actor-id
                          :from-role :workflow
                          :to-role :workflow
                          :provenance :workflow-record
                          :workflow-record-id (workflow-record-id record)
                          :work-item-id (workflow-record-work-item-id record)
                          :plan-id (workflow-record-plan-id record)
                          :phase :recovery
                          :operation :recover-turn-resume
                          :message-count 1
                          :recent-count 1
                          :failed-count 0
                          :latest-status :recovered
                          :latest-created-at timestamp
                          :actor-execution-job-id (and (listp payload)
                                                       (getf payload :actor-execution-job-id))))
                   ((eq kind :approval-requested)
                    (list :from-actor-id (or (and (listp payload)
                                                  (getf payload :actor-id))
                                             governance-actor-id)
                          :to-actor-id workflow-actor-id
                          :from-role (or (and (listp payload)
                                              (getf payload :actor-target))
                                         :governance)
                          :to-role :workflow
                          :provenance :workflow-record
                          :workflow-record-id (workflow-record-id record)
                          :work-item-id (workflow-record-work-item-id record)
                          :plan-id (workflow-record-plan-id record)
                          :phase :approval
                          :operation :request-approval
                          :message-count 1
                          :recent-count 1
                          :failed-count 0
                          :latest-status :awaiting-approval
                          :latest-created-at timestamp
                          :actor-execution-job-id (and (listp payload)
                                                       (getf payload :actor-execution-job-id))))
                   ((eq kind :quarantined)
                    (list :from-actor-id (or (and (listp payload)
                                                  (getf payload :actor-id))
                                             workflow-actor-id)
                          :to-actor-id workflow-actor-id
                          :from-role (or (and (listp payload)
                                              (getf payload :actor-target))
                                         :workflow)
                          :to-role :workflow
                          :provenance :workflow-record
                          :workflow-record-id (workflow-record-id record)
                          :work-item-id (workflow-record-work-item-id record)
                          :plan-id (workflow-record-plan-id record)
                          :phase :operator
                          :operation :quarantine-workflow
                          :message-count 1
                          :recent-count 1
                          :failed-count 0
                          :latest-status :quarantined
                          :latest-created-at timestamp
                          :actor-execution-job-id (and (listp payload)
                                                       (getf payload :actor-execution-job-id))))
                   ((eq kind :resumed)
                    (list :from-actor-id (or (and (listp payload)
                                                  (getf payload :actor-id))
                                             workflow-actor-id)
                          :to-actor-id workflow-actor-id
                          :from-role (or (and (listp payload)
                                              (getf payload :actor-target))
                                         :workflow)
                          :to-role :workflow
                          :provenance :workflow-record
                          :workflow-record-id (workflow-record-id record)
                          :work-item-id (workflow-record-work-item-id record)
                          :plan-id (workflow-record-plan-id record)
                          :phase :operator
                          :operation :resume-workflow
                          :message-count 1
                          :recent-count 1
                          :failed-count 0
                          :latest-status :resumed
                          :latest-created-at timestamp
                          :actor-execution-job-id (and (listp payload)
                                                       (getf payload :actor-execution-job-id))))
                   ((eq kind :control-state-recovered)
                    (list :from-actor-id (or (and (listp payload)
                                                  (getf payload :actor-id))
                                             workflow-actor-id)
                          :to-actor-id workflow-actor-id
                          :from-role (or (and (listp payload)
                                              (getf payload :actor-target))
                                         :workflow)
                          :to-role :workflow
                          :provenance :workflow-record
                          :workflow-record-id (workflow-record-id record)
                          :work-item-id (workflow-record-work-item-id record)
                          :plan-id (workflow-record-plan-id record)
                          :phase :recovery
                          :operation (or (and (listp payload)
                                              (case (getf payload :replay-class)
                                                (:validation-replay :replay-cold-validation)
                                                (:rollback-replay :replay-rollback-review)
                                                (:approval-resume :restore-approval-posture)
                                                (:operator-review-replay :restore-operator-review)
                                                (:workflow-resume :restore-workflow-resume)
                                                (otherwise nil)))
                                         :recover-workflow-control-state)
                          :message-count 1
                          :recent-count 1
                          :failed-count 0
                          :latest-status :recovered
                          :latest-created-at timestamp
                          :actor-execution-job-id (and (listp payload)
                                                       (getf payload :actor-execution-job-id))
                          :replay-class (and (listp payload)
                                             (getf payload :replay-class))))
                   (t nil))))
             (workflow-record-entries record)))))

(defun find-workflow-record (session workflow-record-id)
  (find workflow-record-id (agent-session-workflow-records session)
        :key #'workflow-record-id :test #'string=))

(defun find-workflow-record-by-plan-id (session plan-id)
  (find plan-id (agent-session-workflow-records session)
        :key #'workflow-record-plan-id :test #'string=))

(defun list-workflow-record-summaries (session)
  (mapcar #'workflow-record-summary (agent-session-workflow-records session)))

(defun append-workflow-record-event (session kind record payload &key metadata)
  (append-session-event session
                        kind
                        payload
                        :family :workflow
                        :entity-id (workflow-record-id record)
                        :metadata (merge-event-metadata
                                   (list :workflow-record-id (workflow-record-id record)
                                         :plan-id (workflow-record-plan-id record)
                                         :work-item-id (workflow-record-work-item-id record))
                                   (current-workflow-event-metadata)
                                   metadata)
                        :work-item-id (workflow-record-work-item-id record)))

(defun create-workflow-record (session goal &key plan-id work-item-id initial-phase initial-kind initial-payload)
  (let* ((record (make-workflow-record
                  :id (make-workflow-record-id)
                  :plan-id plan-id
                  :work-item-id work-item-id
                  :goal goal
                  :status :open
                  :created-at (get-universal-time)
                  :updated-at (get-universal-time)
                  :entries '()
                  :entries-tail nil
                  :conclusion nil
                  :evidence '()
                  :waiting-on nil
                  :approval-requirements '()
                  :pending-validations '(:live :cold)
                  :next-action nil
                  :resume-payload nil
                  :continuation-checkpoints '()
                  :suspension-notes '()
                  :quarantine-reason nil
                  :resume-count 0
                  :operator-interventions '())))
    (multiple-value-bind (records tail)
        (append-linked-item (agent-session-workflow-records session)
                            (agent-session-workflow-records-tail session)
                            record)
      (setf (agent-session-workflow-records session) records
            (agent-session-workflow-records-tail session) tail))
    (let ((environment (session-bound-environment session)))
      (when environment
        (environment-append-workflow-record environment session record)))
    (append-workflow-record-event session
                                  :workflow-record-created
                                  record
                                  (workflow-record-summary record))
    (when (or initial-phase initial-kind initial-payload)
      (append-workflow-record-entry session record
                                    (or initial-phase :inspect)
                                    (or initial-kind :created)
                                    initial-payload))
    record))

(defun append-workflow-record-entry (session record phase kind payload &key status)
  (declare (ignore session))
  (let ((entry (make-workflow-entry :phase phase
                                    :kind kind
                                    :timestamp (get-universal-time)
                                    :payload payload)))
    (multiple-value-bind (entries tail)
        (append-linked-item (workflow-record-entries record)
                            (workflow-record-entries-tail record)
                            entry)
      (setf (workflow-record-entries record) entries
            (workflow-record-entries-tail record) tail))
    (setf (workflow-record-updated-at record) (get-universal-time))
    (when status
      (setf (workflow-record-status record) status))
    entry))

(defun append-workflow-record-evidence (record evidence)
  (setf (workflow-record-evidence record)
        (append (workflow-record-evidence record) (list evidence))
        (workflow-record-updated-at record) (get-universal-time))
  evidence)

(defun record-operator-intervention (session record kind payload &key status)
  (let ((intervention (list :kind kind
                            :timestamp (get-universal-time)
                            :payload payload)))
    (setf (workflow-record-operator-interventions record)
          (append (workflow-record-operator-interventions record) (list intervention))
          (workflow-record-updated-at record) (get-universal-time))
    (append-workflow-record-entry session
                                  record
                                  :operator
                                  kind
                                  (enrich-workflow-entry-payload-with-actor-metadata payload)
                                  :status status)
    intervention))

(defun mark-workflow-record-awaiting-approval (session record policy &key reason)
  (let ((requirement (list :policy policy
                           :reason reason
                           :requested-at (get-universal-time))))
    (setf (workflow-record-status record) :awaiting-approval
          (workflow-record-waiting-on record) :approval
          (workflow-record-next-action record)
          (list :type :resume-after-approval
                :policy policy
                :operator-step :grant-approval)
          (workflow-record-resume-payload record)
          (list :resume-command :resume-work-item
                :policy policy
                :reason reason)
          (workflow-record-suspension-notes record)
          (append (workflow-record-suspension-notes record)
                  (list (list :kind :approval
                              :reason reason
                              :timestamp (get-universal-time))))
          (workflow-record-approval-requirements record)
          (append (workflow-record-approval-requirements record) (list requirement))
          (workflow-record-updated-at record) (get-universal-time))
    (record-operator-intervention session record :approval-requested requirement :status :awaiting-approval)
    requirement))

(defun update-workflow-record-pending-validations (record validations &key session)
  (let ((previous (workflow-record-pending-validations record)))
    (setf (workflow-record-pending-validations record) validations
          (workflow-record-updated-at record) (get-universal-time))
    (unless (equal previous validations)
      (append-workflow-record-entry session
                                    record
                                    :validate
                                    :pending-validations-updated
                                    (list :previous previous
                                          :current validations))))
  validations)

(defun update-workflow-record-next-action (record next-action &key session)
  (let ((previous (workflow-record-next-action record)))
    (setf (workflow-record-next-action record) next-action
          (workflow-record-updated-at record) (get-universal-time))
    (unless (equal previous next-action)
      (append-workflow-record-entry session
                                    record
                                    :plan
                                    :next-action-updated
                                    (list :previous previous
                                          :current next-action))))
  next-action)

(defun update-workflow-record-resume-payload (record resume-payload &key session)
  (let ((previous (workflow-record-resume-payload record)))
    (setf (workflow-record-resume-payload record) resume-payload
          (workflow-record-updated-at record) (get-universal-time))
    (unless (equal previous resume-payload)
      (append-workflow-record-entry session
                                    record
                                    :plan
                                    :resume-payload-updated
                                    (list :previous previous
                                          :current resume-payload))))
  resume-payload)

(defun quarantine-workflow-record (session record reason &key evidence)
  (when evidence
    (append-workflow-record-evidence record evidence))
  (setf (workflow-record-status record) :quarantined
        (workflow-record-waiting-on record) :operator-review
        (workflow-record-next-action record)
        (list :type :operator-review
              :reason reason
              :operator-step :decide-resume-or-rollback)
        (workflow-record-resume-payload record)
        (list :resume-command :resume-work-item
              :decision-set '(:resume :rollback)
              :reason reason)
        (workflow-record-suspension-notes record)
        (append (workflow-record-suspension-notes record)
                (list (list :kind :quarantine
                            :reason reason
                            :timestamp (get-universal-time))))
        (workflow-record-quarantine-reason record) reason
        (workflow-record-updated-at record) (get-universal-time))
  (record-operator-intervention session record :quarantined reason :status :quarantined)
  (append-workflow-record-event session
                                :workflow-record-quarantined
                                record
                                (list :reason reason
                                      :status (workflow-record-status record)
                                      :waiting-on (workflow-record-waiting-on record)
                                      :next-action (workflow-record-next-action record)))
  record)

(defun resume-workflow-record (session record &key note)
  (setf (workflow-record-status record) :resumed
        (workflow-record-waiting-on record) nil
        (workflow-record-next-action record)
        (list :type :continue-transaction
              :operator-step :resume-execution
              :note note)
        (workflow-record-resume-payload record)
        (list :resume-command :continue-transaction
              :note note)
        (workflow-record-quarantine-reason record) nil
        (workflow-record-updated-at record) (get-universal-time)
        (workflow-record-resume-count record) (1+ (workflow-record-resume-count record)))
  (record-operator-intervention session record :resumed (or note :resume-requested) :status :resumed)
  (append-workflow-record-event session
                                :workflow-record-resumed
                                record
                                (list :note note
                                      :status (workflow-record-status record)
                                      :resume-count (workflow-record-resume-count record)))
  record)

(defun mark-workflow-record-turn-resume-started (session record turn
                                                 &key source actor-execution-job-id
                                                   operations governed-records)
  (let* ((actor-metadata (current-workflow-entry-actor-metadata))
         (latest-checkpoint (latest-workflow-record-continuation-checkpoint record))
         (reuse-checkpoint-p
           (and latest-checkpoint
                (eq (getf latest-checkpoint :kind) :turn-resume)
                (eq (getf latest-checkpoint :status) :started)
                (string= (or (getf latest-checkpoint :turn-id) "")
                         (turn-id turn))))
         (payload (list :turn-id (turn-id turn)
                       :thread-id (turn-thread-id turn)
                       :source source
                       :actor-id (getf actor-metadata :actor-id)
                       :actor-execution-job-id actor-execution-job-id
                       :resume-count (1+ (workflow-record-resume-count record))))
        (checkpoint (list :kind :turn-resume
                          :status :started
                          :captured-at (get-universal-time)
                          :turn-id (turn-id turn)
                          :thread-id (turn-thread-id turn)
                          :actor-id (getf actor-metadata :actor-id)
                          :actor-execution-job-id actor-execution-job-id
                          :resume-count (1+ (workflow-record-resume-count record))
                          :pending-action-operation-ids
                          (mapcar #'operation-id (or operations '()))
                          :pending-action-count (length (or operations '()))
                          :pending-governed-record-ids
                          (mapcar #'desktop-task-record-id (or governed-records '()))
                          :pending-governed-record-count (length (or governed-records '()))
                          :resume-payload (copy-tree (workflow-record-resume-payload record)))))
    (setf (workflow-record-status record) :resumed
          (workflow-record-waiting-on record) nil
          (workflow-record-next-action record)
          (list :type :resume-turn
                :turn-id (turn-id turn)
                :operator-step :continue-turn)
          (workflow-record-resume-payload record)
          (list :resume-command :resume-turn
                :turn-id (turn-id turn)
                :thread-id (turn-thread-id turn)
                :source source)
          (workflow-record-quarantine-reason record) nil
          (workflow-record-updated-at record) (get-universal-time)
          (workflow-record-resume-count record) (1+ (workflow-record-resume-count record)))
    (if reuse-checkpoint-p
        (update-latest-workflow-record-continuation-checkpoint
         record
         (lambda (existing)
           (setf (getf existing :captured-at) (get-universal-time)
                 (getf existing :actor-id) (or (getf actor-metadata :actor-id)
                                               (getf existing :actor-id))
                 (getf existing :actor-execution-job-id)
                 (or actor-execution-job-id
                     (getf existing :actor-execution-job-id))
                 (getf existing :resume-count) (workflow-record-resume-count record)
                 (getf existing :pending-action-operation-ids)
                 (mapcar #'operation-id (or operations '()))
                 (getf existing :pending-action-count) (length (or operations '()))
                 (getf existing :pending-governed-record-ids)
                 (mapcar #'desktop-task-record-id (or governed-records '()))
                 (getf existing :pending-governed-record-count)
                 (length (or governed-records '()))
                 (getf existing :resume-payload)
                 (copy-tree (workflow-record-resume-payload record)))
           existing))
        (append-workflow-record-continuation-checkpoint record checkpoint))
    (append-workflow-record-entry session
                                  record
                                  :resume
                                  :turn-resume-started
                                  payload
                                  :status :resumed)
    (append-workflow-record-event session
                                  :workflow-turn-resume-started
                                  record
                                  payload)
    record))

(defun mark-workflow-record-turn-resume-completed (session record turn results
                                                   &key followup actor-execution-job-id)
  (let ((payload (list :turn-id (turn-id turn)
                       :thread-id (turn-thread-id turn)
                       :result-count (length results)
                       :failed-result-count (count-if (lambda (entry)
                                                       (eq (getf entry :status) :failed))
                                                     results)
                       :followup-present-p (not (null followup))
                       :actor-execution-job-id actor-execution-job-id)))
    (setf (workflow-record-updated-at record) (get-universal-time))
    (update-latest-workflow-record-continuation-checkpoint
     record
     (lambda (checkpoint)
       (setf (getf checkpoint :status) :completed
             (getf checkpoint :completed-at) (get-universal-time)
             (getf checkpoint :result-count) (length results)
             (getf checkpoint :failed-result-count)
             (count-if (lambda (entry)
                         (eq (getf entry :status) :failed))
                       results)
             (getf checkpoint :followup-present-p) (not (null followup))
             (getf checkpoint :actor-execution-job-id)
             (or actor-execution-job-id
                 (getf checkpoint :actor-execution-job-id)))))
    (append-workflow-record-entry session
                                  record
                                  :resume
                                  :turn-resume-completed
                                  payload
                                  :status (workflow-record-status record))
    (append-workflow-record-evidence record payload)
    (append-workflow-record-event session
                                  :workflow-turn-resume-completed
                                  record
                                  payload)
    record))

(defun mark-workflow-record-turn-resume-failed (session record turn condition
                                                &key actor-execution-job-id)
  (let ((payload (list :turn-id (turn-id turn)
                       :thread-id (turn-thread-id turn)
                       :error (princ-to-string condition)
                       :actor-execution-job-id actor-execution-job-id)))
    (setf (workflow-record-status record) :failed
          (workflow-record-waiting-on record) :operator-review
          (workflow-record-next-action record)
          (list :type :repair-turn-resume
                :turn-id (turn-id turn)
                :operator-step :inspect-failure)
          (workflow-record-updated-at record) (get-universal-time))
    (update-latest-workflow-record-continuation-checkpoint
     record
     (lambda (checkpoint)
       (setf (getf checkpoint :status) :failed
             (getf checkpoint :failed-at) (get-universal-time)
             (getf checkpoint :error) (princ-to-string condition)
             (getf checkpoint :actor-execution-job-id)
             (or actor-execution-job-id
                 (getf checkpoint :actor-execution-job-id)))))
    (append-workflow-record-entry session
                                  record
                                  :resume
                                  :turn-resume-failed
                                  payload
                                  :status :failed)
    (append-workflow-record-evidence record payload)
    (append-workflow-record-event session
                                  :workflow-turn-resume-failed
                                  record
                                  payload)
    record))

(defun mark-workflow-record-turn-resume-recovered (session record turn checkpoint
                                                   &key restaged-count
                                                     (recovery-origin :session-load))
  (let* ((metadata (workflow-checkpoint-recovery-event-metadata session
                                                                record
                                                                checkpoint
                                                                :recovery-origin recovery-origin))
         (payload (list :turn-id (turn-id turn)
                        :thread-id (turn-thread-id turn)
                        :restaged-count restaged-count
                        :checkpoint-kind (and checkpoint
                                              (getf checkpoint :kind))
                        :checkpoint-status (and checkpoint
                                                (getf checkpoint :status))
                        :actor-id (getf metadata :actor-id)
                        :actor-execution-job-id (getf metadata :actor-execution-job-id)
                        :replay-class :turn-resume-replay
                        :recovery-origin recovery-origin)))
    (update-latest-workflow-record-continuation-checkpoint
     record
     (lambda (latest)
       (append latest
               (list :recovered-during-load-p (eq recovery-origin :session-load)
                     :recovered-during-resume-p (eq recovery-origin :turn-resume)
                     :recovered-at (get-universal-time)
                     :recovery-origin recovery-origin
                     :replay-class :turn-resume-replay
                     :recovered-pending-action-count restaged-count
                     :recovered-turn-status :awaiting-approval))))
    (append-workflow-record-entry session
                                  record
                                  :recovery
                                  :turn-resume-recovered
                                  payload
                                  :status :resumed)
    (append-workflow-record-event session
                                  :workflow-turn-resume-recovered
                                  record
                                  payload
                                  :metadata metadata)
    record))

(defun close-workflow-record (session record conclusion &key status evidence)
  (when evidence
    (append-workflow-record-evidence record evidence))
  (setf (workflow-record-conclusion record) conclusion
        (workflow-record-status record) (or status :closed)
        (workflow-record-waiting-on record) nil
        (workflow-record-next-action record) nil
        (workflow-record-resume-payload record) nil
        (workflow-record-continuation-checkpoints record)
        (copy-tree (workflow-record-continuation-checkpoints record))
        (workflow-record-pending-validations record) '()
        (workflow-record-updated-at record) (get-universal-time))
  (append-workflow-record-event session
                                :workflow-record-closed
                                record
                                (list :status (workflow-record-status record)
                                      :conclusion conclusion))
  record)
