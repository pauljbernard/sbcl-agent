(in-package #:sbcl-agent)

(defstruct environment-agent-state
  agents
  subscriptions
  memory
  plan
  actor-mailboxes
  pending-actions
  desktop-tasks
  incidents
  tasks
  workers
  summaries)

(defstruct environment
  id
  schema-version
  storage-root
  runtime-state
  conversation-state
  workflow-state
  agent-state
  runtime-set
  active-runtime-id
  thread-set
  active-thread-id
  artifact-index
  work-item-graph
  policy-state
  agent-registry
  memory
  summaries
  event-log
  compatibility-session
  metadata)

(defparameter *current-environment* nil)
(defparameter +environment-schema-version+ 1)

(defun compatibility-session-id (sessionish)
  (typecase sessionish
    (agent-session (agent-session-id sessionish))
    (environment-compatibility-payload
     (environment-compatibility-payload-session-id sessionish))
    (t nil)))

(defun compatibility-session-materialized-p (sessionish)
  (typep sessionish 'agent-session))

(defun make-environment-id ()
  (format nil "environment-~D-~D" (get-universal-time) (random 1000000)))

(defun session-bound-environment (session)
  (let ((environment (and (boundp '*current-environment*)
                          *current-environment*)))
    (when (and environment
               (eq (environment-compatibility-session environment) session))
      environment)))
