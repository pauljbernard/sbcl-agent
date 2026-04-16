(in-package #:tutor-codex)

(defstruct agent-session
  id
  cwd
  package
  transcript
  plan
  events
  approved-policies
  pending-actions)

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
   :approved-policies '()
   :pending-actions '()))

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

(defun approve-policy (session policy)
  (unless (member policy (agent-session-approved-policies session))
    (setf (agent-session-approved-policies session)
          (append (agent-session-approved-policies session) (list policy))))
  (append-session-event session :approval policy)
  policy)

(defun policy-approved-p (session policy)
  (member policy (agent-session-approved-policies session)))

(defun ensure-policy-approved (session policy)
  (unless (policy-approved-p session policy)
    (append-session-event session :approval-required policy)
    (error "Approval required for ~S. Run (approve ~S) first." policy policy))
  t)

(defun session-summary (session)
  (list :id (agent-session-id session)
        :cwd (agent-session-cwd session)
        :package (agent-session-package session)
        :plan (agent-session-plan session)
        :approved-policies (agent-session-approved-policies session)
        :pending-action-count (length (agent-session-pending-actions session))
        :transcript-count (length (agent-session-transcript session))
        :event-count (length (agent-session-events session))))

(defun save-session (session path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (let ((*print-circle* t)
          (*print-pretty* t))
      (write session :stream stream)))
  path)

(defun load-session (path)
  (with-open-file (stream path :direction :input)
    (let ((session (read stream nil nil)))
      (unless (typep session 'agent-session)
        (error "Session file ~A did not contain an AGENT-SESSION" path))
      (setf *current-session* session)
      session)))

(defun reset-session (&optional session)
  (declare (ignore session))
  (setf *current-session* (make-default-session)))
