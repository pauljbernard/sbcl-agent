(in-package #:sbcl-agent)

(defstruct event
  id
  timestamp
  kind
  family
  entity-id
  thread-id
  turn-id
  visibility
  metadata
  payload)

(defun make-event-id ()
  (format nil "event-~D-~D" (get-universal-time) (random 1000000)))

(defun normalize-event-family (kind explicit-family)
  (or explicit-family
      (case kind
        (:provider-stream :provider)
        (:transcript :conversation)
        ((:assistant-response :assistant-actions-executed :pending-actions :pending-actions-cleared)
         :assistant)
        ((:task-enqueued :task-started :task-completed :task-failed :task-cancelled :worker-started :worker-stopped)
         :runtime)
        ((:capability-granted :capability-required) :policy)
        (t :session))))

(defun make-event-now (kind payload &key family entity-id thread-id turn-id (visibility :operator) metadata)
  (make-event :id (make-event-id)
              :timestamp (get-universal-time)
              :kind kind
              :family (normalize-event-family kind family)
              :entity-id entity-id
              :thread-id thread-id
              :turn-id turn-id
              :visibility visibility
              :metadata metadata
              :payload payload))
