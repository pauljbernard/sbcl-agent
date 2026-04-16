(in-package #:tutor-codex)

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
  workers)

(defparameter *current-session* nil)

(defun make-default-session (&key (cwd (namestring (getcwd)))
                                  (package "TUTOR-CODEX-USER"))
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

(defun session-summary (session)
  (list :id (agent-session-id session)
        :cwd (agent-session-cwd session)
        :package (agent-session-package session)
        :plan (agent-session-plan session)
        :approved-policies (session-approved-policies session)
        :capability-grants (session-capability-grants-summary session)
        :pending-action-count (length (agent-session-pending-actions session))
        :task-count (length (agent-session-tasks session))
        :active-worker-count (active-worker-count session)
        :worker-count (length (agent-session-workers session))
        :transcript-count (length (agent-session-transcript session))
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
