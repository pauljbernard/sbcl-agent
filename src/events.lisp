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

(defparameter +event-correlation-keys+
  '(:environment-id :session-id :run-id :operation-id :work-item-id :artifact-id :incident-id :agent-id))

(defun plist-keys (plist)
  (loop for (key nil) on plist by #'cddr
        collect key))

(defun event-correlation-metadata (&key environment-id session-id run-id operation-id work-item-id artifact-id incident-id agent-id)
  (let ((metadata '()))
    (when environment-id
      (setf metadata (append metadata (list :environment-id environment-id))))
    (when session-id
      (setf metadata (append metadata (list :session-id session-id))))
    (when run-id
      (setf metadata (append metadata (list :run-id run-id))))
    (when operation-id
      (setf metadata (append metadata (list :operation-id operation-id))))
    (when work-item-id
      (setf metadata (append metadata (list :work-item-id work-item-id))))
    (when artifact-id
      (setf metadata (append metadata (list :artifact-id artifact-id))))
    (when incident-id
      (setf metadata (append metadata (list :incident-id incident-id))))
    (when agent-id
      (setf metadata (append metadata (list :agent-id agent-id))))
    metadata))

(defun merge-event-metadata (&rest metadata-plists)
  (let ((merged '()))
    (dolist (plist metadata-plists)
      (loop for (key value) on plist by #'cddr
            do (setf (getf merged key) value)))
    merged))

(defun event-envelope-summary (event)
  (list :id (event-id event)
        :kind (event-kind event)
        :family (event-family event)
        :entity-id (event-entity-id event)
        :thread-id (event-thread-id event)
        :turn-id (event-turn-id event)
        :visibility (event-visibility event)
        :metadata-keys (plist-keys (event-metadata event))))

(defun normalize-event-family (kind explicit-family)
  (or explicit-family
      (case kind
        (:provider-stream :provider)
        (:transcript :conversation)
        ((:turn-followup-started :turn-followup-completed) :conversation)
        ((:thread-created :thread-selected :message-created :turn-started :turn-completed
          :artifact-created :artifact-linked)
         :conversation)
        ((:workflow-record-created :work-item-created :validation-started :validation-completed
          :reconciliation-created :rollback-started :rollback-completed
          :workflow-record-quarantined :workflow-record-resumed :workflow-record-closed)
         :workflow)
        ((:incident-created) :incident)
        ((:assistant-response :assistant-actions-executed :pending-actions :pending-actions-cleared)
         :assistant)
        ((:task-enqueued :task-started :task-completed :task-failed :task-cancelled :worker-started :worker-stopped)
         :runtime)
        ((:capability-granted :capability-required) :policy)
        (t :session))))

(defun make-event-now (kind payload &key family entity-id thread-id turn-id (visibility :operator) metadata
                              environment-id session-id run-id operation-id work-item-id artifact-id incident-id agent-id)
  (make-event :id (make-event-id)
              :timestamp (get-universal-time)
              :kind kind
              :family (normalize-event-family kind family)
              :entity-id entity-id
              :thread-id thread-id
              :turn-id turn-id
              :visibility visibility
              :metadata (merge-event-metadata
                         (event-correlation-metadata :environment-id environment-id
                                                     :session-id session-id
                                                     :run-id run-id
                                                     :operation-id operation-id
                                                     :work-item-id work-item-id
                                                     :artifact-id artifact-id
                                                     :incident-id incident-id
                                                     :agent-id agent-id)
                         metadata)
              :payload payload))
