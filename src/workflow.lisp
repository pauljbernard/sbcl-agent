(in-package #:sbcl-agent)

(defstruct workflow-entry
  phase
  kind
  timestamp
  payload)

(defstruct workflow-record
  id
  work-item-id
  goal
  status
  created-at
  updated-at
  entries
  conclusion
  evidence
  waiting-on
  approval-requirements
  pending-validations
  next-action
  resume-payload
  suspension-notes
  quarantine-reason
  resume-count
  operator-interventions)

(defun make-workflow-record-id ()
  (format nil "wf-~D-~D" (get-universal-time) (random 1000000)))

(defun workflow-entry-summary (entry)
  (list :phase (workflow-entry-phase entry)
        :kind (workflow-entry-kind entry)
        :timestamp (workflow-entry-timestamp entry)
        :payload (workflow-entry-payload entry)))

(defun workflow-record-summary (record)
  (list :id (workflow-record-id record)
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
        :suspension-notes (workflow-record-suspension-notes record)
        :quarantine-reason (workflow-record-quarantine-reason record)
        :resume-count (workflow-record-resume-count record)
        :operator-intervention-count (length (workflow-record-operator-interventions record))
        :entry-count (length (workflow-record-entries record))
        :conclusion (workflow-record-conclusion record)))

(defun workflow-record-detail (record)
  (append (workflow-record-summary record)
          (list :entries (mapcar #'workflow-entry-summary (workflow-record-entries record))
                :operator-interventions (workflow-record-operator-interventions record)
                :evidence (workflow-record-evidence record))))

(defun find-workflow-record (session workflow-record-id)
  (find workflow-record-id (agent-session-workflow-records session)
        :key #'workflow-record-id :test #'string=))

(defun list-workflow-record-summaries (session)
  (mapcar #'workflow-record-summary (agent-session-workflow-records session)))

(defun create-workflow-record (session goal &key work-item-id initial-phase initial-kind initial-payload)
  (let* ((record (make-workflow-record
                  :id (make-workflow-record-id)
                  :work-item-id work-item-id
                  :goal goal
                  :status :open
                  :created-at (get-universal-time)
                  :updated-at (get-universal-time)
                  :entries '()
                  :conclusion nil
                  :evidence '()
                  :waiting-on nil
                  :approval-requirements '()
                  :pending-validations '(:live :cold)
                  :next-action nil
                  :resume-payload nil
                  :suspension-notes '()
                  :quarantine-reason nil
                  :resume-count 0
                  :operator-interventions '())))
    (setf (agent-session-workflow-records session)
          (append (agent-session-workflow-records session) (list record)))
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
    (setf (workflow-record-entries record)
          (append (workflow-record-entries record) (list entry))
          (workflow-record-updated-at record) (get-universal-time))
    (when status
      (setf (workflow-record-status record) status))
    entry))

(defun append-workflow-record-evidence (record evidence)
  (setf (workflow-record-evidence record)
        (append (workflow-record-evidence record) (list evidence))
        (workflow-record-updated-at record) (get-universal-time))
  evidence)

(defun record-operator-intervention (session record kind payload &key status)
  (declare (ignore session))
  (let ((intervention (list :kind kind
                            :timestamp (get-universal-time)
                            :payload payload)))
    (setf (workflow-record-operator-interventions record)
          (append (workflow-record-operator-interventions record) (list intervention))
          (workflow-record-updated-at record) (get-universal-time))
    (append-workflow-record-entry session record :operator kind payload :status status)
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
  record)

(defun close-workflow-record (session record conclusion &key status evidence)
  (declare (ignore session))
  (when evidence
    (append-workflow-record-evidence record evidence))
  (setf (workflow-record-conclusion record) conclusion
        (workflow-record-status record) (or status :closed)
        (workflow-record-waiting-on record) nil
        (workflow-record-next-action record) nil
        (workflow-record-resume-payload record) nil
        (workflow-record-pending-validations record) '()
        (workflow-record-updated-at record) (get-universal-time))
  record)
