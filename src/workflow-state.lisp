(in-package #:sbcl-agent)

(defstruct environment-workflow-state
  work-items
  workflow-records
  approvals
  replay-groups
  reconciliations
  summaries)

(defun environment-workflow-domain-summary (environment)
  (let ((workflow-state (environment-workflow-state environment)))
    (and workflow-state
         (environment-workflow-state-summaries workflow-state))))

(defun environment-workflow-wait-summary (environment)
  (let* ((workflow-state (environment-workflow-state environment))
         (work-items (and workflow-state
                          (environment-workflow-state-work-items workflow-state)))
         (waiting '())
         (blocked '()))
    (dolist (work-item work-items)
      (let* ((report (work-item-wait-report (environment-session environment) work-item))
             (category (getf report :why)))
        (push (list :work-item-id (work-item-id work-item)
                    :why category
                    :waiting-on (getf report :waiting-on)
                    :pending-validations (getf report :pending-validations)
                    :next-action (getf report :next-action)
                    :resume-payload (getf report :resume-payload))
              blocked)
        (let ((entry (assoc category waiting)))
          (if entry
              (incf (cdr entry))
              (push (cons category 1) waiting)))))
    (list :blocked-count (length blocked)
          :by-reason (mapcar (lambda (entry)
                               (list :why (car entry) :count (cdr entry)))
                             (nreverse waiting))
          :blocked-work-items (nreverse blocked))))

(defun environment-validator-replay-groups (environment)
  (let* ((workflow-state (environment-workflow-state environment)))
    (and workflow-state
         (environment-workflow-state-replay-groups workflow-state))))

(defun environment-image-reconciliation-summary (environment)
  (let* ((workflow-state (environment-workflow-state environment)))
    (and workflow-state
         (environment-workflow-state-reconciliations workflow-state))))

(defun make-environment-workflow-state-from-session (session)
  (make-environment-workflow-state
   :work-items (agent-session-work-items session)
   :workflow-records (agent-session-workflow-records session)
   :approvals (session-capability-grants-summary session)
   :replay-groups (raw-session-validator-replay-groups session)
   :reconciliations (raw-session-image-reconciliation-summary session)
   :summaries (list :work-item-count (length (agent-session-work-items session))
                    :workflow-record-count (length (agent-session-workflow-records session))
                    :approval-count (length (agent-session-capability-grants session))
                    :replay-group-count (length (raw-session-validator-replay-groups session))
                    :reconciliation-count (length (raw-session-image-reconciliation-summary session)))))

(defun ensure-environment-workflow-state (environment session)
  (or (environment-workflow-state environment)
      (let ((workflow-state
              (make-environment-workflow-state-from-session session)))
        (setf (environment-workflow-state environment) workflow-state)
        workflow-state)))

(defun refresh-environment-workflow-domain (environment session)
  (let ((workflow-state (ensure-environment-workflow-state environment session)))
    (setf (environment-workflow-state-approvals workflow-state)
          (session-capability-grants-summary session)
          (environment-workflow-state-replay-groups workflow-state)
          (raw-session-validator-replay-groups session)
          (environment-workflow-state-reconciliations workflow-state)
          (raw-session-image-reconciliation-summary session)
          (environment-workflow-state-summaries workflow-state)
          (list :work-item-count (length (environment-workflow-state-work-items workflow-state))
                :workflow-record-count (length (environment-workflow-state-workflow-records workflow-state))
                :approval-count (length (agent-session-capability-grants session))
                :replay-group-count (length (raw-session-validator-replay-groups session))
                :reconciliation-count (length (raw-session-image-reconciliation-summary session))))
    (setf (environment-work-item-graph environment)
          (mapcar #'work-item-summary
                  (environment-workflow-state-work-items workflow-state)))
    environment))

(defun environment-append-workflow-record (environment session record)
  (let* ((workflow-state (ensure-environment-workflow-state environment session))
         (records (environment-workflow-state-workflow-records workflow-state)))
    (unless (find (workflow-record-id record) records
                  :key #'workflow-record-id
                  :test #'string=)
      (setf (environment-workflow-state-workflow-records workflow-state)
            (append records (list record))))
    (refresh-environment-workflow-domain environment session)))

(defun environment-append-work-item (environment session work-item)
  (let* ((workflow-state (ensure-environment-workflow-state environment session))
         (work-items (environment-workflow-state-work-items workflow-state)))
    (unless (find (work-item-id work-item) work-items
                  :key #'work-item-id
                  :test #'string=)
      (setf (environment-workflow-state-work-items workflow-state)
            (append work-items (list work-item))))
    (refresh-environment-workflow-domain environment session)))
