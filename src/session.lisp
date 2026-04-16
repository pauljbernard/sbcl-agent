(in-package #:sbcl-agent)

(defstruct agent-session
  id
  cwd
  package
  transcript
  plan
  events
  capability-grants
  pending-actions
  tasks
  work-items
  workflow-records
  workers)

(defparameter *current-session* nil)

(defun make-default-session (&key (cwd (namestring (getcwd)))
                                  (package "SBCL-AGENT-USER"))
  (make-agent-session
   :id (format nil "session-~D" (get-universal-time))
   :cwd cwd
   :package package
   :transcript '()
   :plan nil
   :events '()
   :capability-grants '()
   :pending-actions '()
   :tasks '()
   :work-items '()
   :workflow-records '()
   :workers '()))

(defun ensure-session (&optional session)
  (or session
      *current-session*
      (setf *current-session* (make-default-session))))

(defun append-session-event (session kind payload)
  (let ((event (make-event-now kind payload)))
    (setf (agent-session-events session)
          (append (agent-session-events session) (list event)))
    event))

(defun append-transcript-entry (session role content)
  (let ((entry (list :role role :content content)))
    (setf (agent-session-transcript session)
          (append (agent-session-transcript session) (list entry)))
    (append-session-event session :transcript entry)
    entry))

(defun update-session-plan (session goal)
  (setf (agent-session-plan session) goal)
  (append-session-event session :plan goal)
  goal)

(defun stage-pending-actions (session actions)
  (setf (agent-session-pending-actions session) actions)
  (append-session-event session :pending-actions actions)
  actions)

(defun clear-pending-actions (session)
  (setf (agent-session-pending-actions session) '())
  (append-session-event session :pending-actions-cleared :ok)
  '())

(defun capability-grant-summary (grant)
  (list :policy-id (capability-grant-policy-id grant)
        :granted-at (capability-grant-granted-at grant)
        :scope (capability-grant-scope grant)
        :metadata (capability-grant-metadata grant)))

(defun normalize-session-capability-grants (session)
  (let ((grants (agent-session-capability-grants session)))
    (setf (agent-session-capability-grants session)
          (mapcar (lambda (entry)
                    (cond
                      ((typep entry 'capability-grant) entry)
                      ((keywordp entry)
                       (make-capability-grant :policy-id entry
                                              :granted-at nil
                                              :scope :session
                                              :metadata '(:migrated-p t)))
                      (t
                       (error "Invalid capability grant entry ~S" entry))))
                  grants))))

(defun grant-capability (session policy-designator &key (scope :session) metadata)
  (let* ((policy (ensure-capability-policy policy-designator))
         (policy-id (capability-policy-id policy))
         (existing (find policy-id
                         (agent-session-capability-grants session)
                         :key #'capability-grant-policy-id
                         :test #'eq)))
    (unless existing
      (setf existing (make-capability-grant :policy-id policy-id
                                            :granted-at (get-universal-time)
                                            :scope scope
                                            :metadata metadata))
      (setf (agent-session-capability-grants session)
            (append (agent-session-capability-grants session) (list existing))))
    (append-session-event session :capability-granted (capability-grant-summary existing))
    existing))

(defun capability-granted-p (session policy-designator)
  (let* ((policy (ensure-capability-policy policy-designator))
         (policy-id (capability-policy-id policy)))
    (find policy-id
          (agent-session-capability-grants session)
          :key #'capability-grant-policy-id
          :test #'eq)))

(defun ensure-capability-granted (session policy-designator)
  (let ((policy (ensure-capability-policy policy-designator)))
    (unless (or (eq (capability-policy-default-grant-mode policy) :implicit)
                (capability-granted-p session policy))
      (append-session-event session :capability-required (capability-policy-summary policy))
      (error "Approval required for ~S. Run (approve ~S) first."
             (capability-policy-id policy)
             (capability-policy-id policy)))
    t))

(defun approve-policy (session policy)
  (capability-grant-policy-id (grant-capability session policy)))

(defun policy-approved-p (session policy)
  (not (null (capability-granted-p session policy))))

(defun ensure-policy-approved (session policy)
  (ensure-capability-granted session policy))

(defun session-approved-policies (session)
  (mapcar #'capability-grant-policy-id (agent-session-capability-grants session)))

(defun session-capability-grants-summary (session)
  (mapcar #'capability-grant-summary (agent-session-capability-grants session)))

(defun work-item-wait-category (session work-item)
  (getf (work-item-wait-report session work-item) :why))

(defun session-wait-summary (session)
  (let ((waiting '())
        (blocked '()))
    (dolist (work-item (agent-session-work-items session))
      (let* ((report (work-item-wait-report session work-item))
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

(defun session-validator-replay-groups (session)
  (let ((groups (make-hash-table :test #'equal)))
    (dolist (work-item (agent-session-work-items session))
      (dolist (record (work-item-validator-tasks work-item))
        (let* ((replay-id (validator-task-record-replay-id record))
               (current (gethash replay-id groups)))
          (setf (gethash replay-id groups)
                (list :replay-id replay-id
                      :work-item-id (work-item-id work-item)
                      :task-count (1+ (or (getf current :task-count) 0))
                      :statuses (append (or (getf current :statuses) '())
                                        (list (validator-task-record-status record))))))))
    (let ((result '()))
      (maphash (lambda (_ value)
                 (declare (ignore _))
                 (push value result))
               groups)
      (nreverse result))))

(defun session-image-reconciliation-summary (session)
  (let ((items '()))
    (dolist (work-item (agent-session-work-items session))
      (let ((record (work-item-image-reconciliation work-item)))
        (when record
          (push (list :work-item-id (work-item-id work-item)
                      :recorded-at (image-reconciliation-record-recorded-at record)
                      :replay-id (image-reconciliation-record-replay-id record)
                      :status (image-reconciliation-record-status record)
                      :source-summary (image-reconciliation-record-source-summary record))
                items))))
    (nreverse items)))

(defun session-operator-status (session)
  (let ((ready '())
        (blocked '())
        (quarantined '())
        (image-only '())
        (durable '()))
    (dolist (work-item (agent-session-work-items session))
      (let* ((report (work-item-wait-report session work-item))
             (why (getf report :why))
             (entry (list :work-item-id (work-item-id work-item)
                          :status (work-item-status work-item)
                          :why why
                          :waiting-on (getf report :waiting-on)
                          :next-action (getf report :next-action)
                          :resume-payload (getf report :resume-payload))))
        (cond
          ((eq (work-item-status work-item) :quarantined)
           (push entry quarantined))
          ((eq (work-item-status work-item) :image-only)
           (push entry image-only))
          ((eq (work-item-closure-decision work-item) :committed-to-source-and-image)
           (push entry durable))
          ((eq why :ready)
           (push entry ready))
          (t
           (push entry blocked)))))
    (list :ready-count (length ready)
          :blocked-count (length blocked)
          :quarantined-count (length quarantined)
          :image-only-count (length image-only)
          :durable-count (length durable)
          :ready-work-items (nreverse ready)
          :blocked-work-items (nreverse blocked)
          :quarantined-work-items (nreverse quarantined)
          :image-only-work-items (nreverse image-only)
          :durable-work-items (nreverse durable))))

(defun recent-session-transcript (session &key (limit 6))
  (let* ((entries (agent-session-transcript session))
         (count (length entries)))
    (if (> count limit)
        (subseq entries (- count limit))
        entries)))

(defun session-summary (session)
  (list :id (agent-session-id session)
        :cwd (agent-session-cwd session)
        :package (agent-session-package session)
        :plan (agent-session-plan session)
        :approved-policies (session-approved-policies session)
        :capability-grants (session-capability-grants-summary session)
        :pending-action-count (length (agent-session-pending-actions session))
        :task-count (length (agent-session-tasks session))
        :work-item-count (length (agent-session-work-items session))
        :workflow-record-count (length (agent-session-workflow-records session))
        :wait-summary (session-wait-summary session)
        :operator-status (session-operator-status session)
        :validator-replay-groups (session-validator-replay-groups session)
        :image-reconciliations (session-image-reconciliation-summary session)
        :active-worker-count (active-worker-count session)
        :worker-count (length (agent-session-workers session))
        :transcript-count (length (agent-session-transcript session))
        :recent-transcript (recent-session-transcript session)
        :event-count (length (agent-session-events session))))

(defun serializable-session-copy (session)
  (make-agent-session
   :id (agent-session-id session)
   :cwd (agent-session-cwd session)
   :package (agent-session-package session)
   :transcript (agent-session-transcript session)
   :plan (agent-session-plan session)
   :events (agent-session-events session)
   :capability-grants (agent-session-capability-grants session)
   :pending-actions (agent-session-pending-actions session)
   :tasks (agent-session-tasks session)
   :work-items (agent-session-work-items session)
   :workflow-records (agent-session-workflow-records session)
   :workers (serializable-worker-states session)))

(defun save-session (session path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (let ((*print-circle* t)
          (*print-pretty* t))
      (write (serializable-session-copy session) :stream stream)))
  path)

(defun load-session (path)
  (with-open-file (stream path :direction :input)
    (let ((session (read stream nil nil)))
      (unless (typep session 'agent-session)
        (error "Session file ~A did not contain an AGENT-SESSION" path))
      (normalize-session-capability-grants session)
      (setf (agent-session-workers session)
            (serializable-worker-states session))
      (setf *current-session* session)
      session)))

(defun reset-session (&optional session)
  (when session
    (ignore-errors (stop-all-workers session)))
  (setf *current-session* (make-default-session)))
