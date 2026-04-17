(in-package #:sbcl-agent)

(defstruct thread
  id
  title
  created-at
  updated-at
  summary
  message-ids
  turn-ids
  artifact-ids
  status
  metadata)

(defstruct message
  id
  thread-id
  role
  content
  content-type
  created-at
  turn-id
  stream-fragments
  finalized-p
  metadata)

(defstruct turn
  id
  thread-id
  user-message-id
  assistant-message-id
  status
  started-at
  completed-at
  operation-ids
  artifact-ids
  error-state
  metadata)

(defstruct operation
  id
  thread-id
  turn-id
  kind
  name
  input
  policy-decision
  status
  output
  started-at
  completed-at
  metadata)

(defstruct artifact
  id
  kind
  path
  title
  summary
  thread-id
  turn-id
  operation-id
  work-item-id
  source-ref
  image-ref
  created-at
  metadata)

(defun make-thread-id ()
  (format nil "thread-~D-~D" (get-universal-time) (random 1000000)))

(defun make-message-id ()
  (format nil "message-~D-~D" (get-universal-time) (random 1000000)))

(defun make-turn-id ()
  (format nil "turn-~D-~D" (get-universal-time) (random 1000000)))

(defun make-operation-id ()
  (format nil "op-~D-~D" (get-universal-time) (random 1000000)))

(defun make-artifact-id ()
  (format nil "artifact-~D-~D" (get-universal-time) (random 1000000)))

(defun make-session-thread (&key title summary metadata)
  (let ((timestamp (get-universal-time)))
    (make-thread :id (make-thread-id)
                 :title (or title "Default Thread")
                 :created-at timestamp
                 :updated-at timestamp
                 :summary summary
                 :message-ids '()
                 :turn-ids '()
                 :artifact-ids '()
                 :status :active
                 :metadata metadata)))

(defun thread-record-summary (thread)
  (list :id (thread-id thread)
        :title (thread-title thread)
        :created-at (thread-created-at thread)
        :updated-at (thread-updated-at thread)
        :status (thread-status thread)
        :message-count (length (thread-message-ids thread))
        :turn-count (length (thread-turn-ids thread))
        :artifact-count (length (thread-artifact-ids thread))
        :summary (thread-summary thread)
        :metadata (thread-metadata thread)))

(defun find-thread (session thread-id)
  (find thread-id (agent-session-threads session)
        :key #'thread-id :test #'string=))

(defun ensure-default-thread (session)
  (or (and (agent-session-current-thread-id session)
           (find-thread session (agent-session-current-thread-id session)))
      (let ((existing (first (agent-session-threads session))))
        (if existing
            (progn
              (setf (agent-session-current-thread-id session) (thread-id existing))
              existing)
            (let ((thread (make-session-thread :title "Default Thread"
                                               :summary "Auto-created default conversation thread."
                                               :metadata '(:default-p t))))
              (setf (agent-session-threads session) (list thread)
                    (agent-session-current-thread-id session) (thread-id thread))
              thread)))))

(defun current-thread (session)
  (ensure-default-thread session))

(defun create-thread (session &key title summary metadata)
  (ensure-default-thread session)
  (let ((thread (make-session-thread :title (or title
                                                (format nil "Thread ~D"
                                                        (1+ (length (agent-session-threads session)))))
                                     :summary summary
                                     :metadata metadata)))
    (setf (agent-session-threads session)
          (append (agent-session-threads session) (list thread))
          (agent-session-current-thread-id session) (thread-id thread))
    (append-session-event session
                          :thread-created
                          (thread-record-summary thread)
                          :family :conversation
                          :entity-id (thread-id thread)
                          :thread-id (thread-id thread)
                          :visibility :operator)
    thread))

(defun use-thread (session thread-id)
  (let ((thread (find-thread session thread-id)))
    (unless thread
      (error "Unknown thread ~A" thread-id))
    (setf (agent-session-current-thread-id session) thread-id
          (thread-updated-at thread) (get-universal-time))
    (append-session-event session
                          :thread-selected
                          (thread-record-summary thread)
                          :family :conversation
                          :entity-id thread-id
                          :thread-id thread-id
                          :visibility :operator)
    thread))

(defun list-thread-summaries (session)
  (ensure-default-thread session)
  (mapcar #'thread-record-summary (agent-session-threads session)))

(defun thread-state-summary (session)
  (let ((thread (current-thread session)))
    (list :current-thread-id (thread-id thread)
          :current-thread-title (thread-title thread)
          :thread-count (length (agent-session-threads session))
          :threads (list-thread-summaries session))))

(defun message-record-summary (message)
  (list :id (message-id message)
        :thread-id (message-thread-id message)
        :role (message-role message)
        :content (message-content message)
        :content-type (message-content-type message)
        :created-at (message-created-at message)
        :turn-id (message-turn-id message)
        :finalized-p (message-finalized-p message)
        :metadata (message-metadata message)))

(defun turn-record-summary (turn)
  (list :id (turn-id turn)
        :thread-id (turn-thread-id turn)
        :user-message-id (turn-user-message-id turn)
        :assistant-message-id (turn-assistant-message-id turn)
        :status (turn-status turn)
        :started-at (turn-started-at turn)
        :completed-at (turn-completed-at turn)
        :operation-count (length (turn-operation-ids turn))
        :artifact-count (length (turn-artifact-ids turn))
        :error-state (turn-error-state turn)
        :metadata (turn-metadata turn)))

(defun turn-status-from-operations (operations &key current-error-state)
  (cond
    (current-error-state :failed)
    ((find :awaiting-approval operations :key #'operation-status) :awaiting-approval)
    ((find :failed operations :key #'operation-status) :failed)
    (t :completed)))

(defun operation-record-summary (operation)
  (list :id (operation-id operation)
        :thread-id (operation-thread-id operation)
        :turn-id (operation-turn-id operation)
        :kind (operation-kind operation)
        :name (operation-name operation)
        :input (operation-input operation)
        :policy-decision (operation-policy-decision operation)
        :status (operation-status operation)
        :output (operation-output operation)
        :started-at (operation-started-at operation)
        :completed-at (operation-completed-at operation)
        :metadata (operation-metadata operation)))

(defun artifact-record-summary (artifact)
  (list :id (artifact-id artifact)
        :kind (artifact-kind artifact)
        :path (artifact-path artifact)
        :title (artifact-title artifact)
        :summary (artifact-summary artifact)
        :thread-id (artifact-thread-id artifact)
        :turn-id (artifact-turn-id artifact)
        :operation-id (artifact-operation-id artifact)
        :work-item-id (artifact-work-item-id artifact)
        :source-ref (artifact-source-ref artifact)
        :image-ref (artifact-image-ref artifact)
        :created-at (artifact-created-at artifact)
        :metadata (artifact-metadata artifact)))

(defun find-message (session message-id)
  (find message-id (agent-session-messages session)
        :key #'message-id :test #'string=))

(defun find-turn (session turn-id)
  (find turn-id (agent-session-turns session)
        :key #'turn-id :test #'string=))

(defun find-operation (session operation-id)
  (find operation-id (agent-session-operations session)
        :key #'operation-id :test #'string=))

(defun find-artifact (session artifact-id)
  (find artifact-id (agent-session-artifacts session)
        :key #'artifact-id :test #'string=))

(defun list-thread-messages (session thread-id)
  (remove-if-not (lambda (message)
                   (string= thread-id (message-thread-id message)))
                 (agent-session-messages session)))

(defun list-thread-turns (session thread-id)
  (remove-if-not (lambda (turn)
                   (string= thread-id (turn-thread-id turn)))
                 (agent-session-turns session)))

(defun list-turn-operations (session turn-id)
  (remove-if-not (lambda (operation)
                   (string= turn-id (operation-turn-id operation)))
                 (agent-session-operations session)))

(defun list-thread-artifacts (session thread-id)
  (remove-if-not (lambda (artifact)
                   (string= thread-id (artifact-thread-id artifact)))
                 (agent-session-artifacts session)))

(defun list-turn-artifacts (session turn-id)
  (remove-if-not (lambda (artifact)
                   (string= turn-id (artifact-turn-id artifact)))
                 (agent-session-artifacts session)))

(defun create-message (session thread role content &key turn-id (content-type :text) stream-fragments (finalized-p t) metadata)
  (let ((message (make-message :id (make-message-id)
                               :thread-id (thread-id thread)
                               :role role
                               :content content
                               :content-type content-type
                               :created-at (get-universal-time)
                               :turn-id turn-id
                               :stream-fragments stream-fragments
                               :finalized-p finalized-p
                               :metadata metadata)))
    (setf (agent-session-messages session)
          (append (agent-session-messages session) (list message))
          (thread-message-ids thread)
          (append (thread-message-ids thread) (list (message-id message)))
          (thread-updated-at thread) (get-universal-time))
    (append-session-event session
                          :message-created
                          (message-record-summary message)
                          :family :conversation
                          :entity-id (message-id message)
                          :thread-id (thread-id thread)
                          :visibility :operator)
    message))

(defun start-turn (session thread user-message &key metadata)
  (let ((turn (make-turn :id (make-turn-id)
                         :thread-id (thread-id thread)
                         :user-message-id (message-id user-message)
                         :assistant-message-id nil
                         :status :running
                         :started-at (message-created-at user-message)
                         :completed-at nil
                         :operation-ids '()
                         :artifact-ids '()
                         :error-state nil
                         :metadata metadata)))
    (setf (message-turn-id user-message) (turn-id turn)
          (agent-session-turns session)
          (append (agent-session-turns session) (list turn))
          (thread-turn-ids thread)
          (append (thread-turn-ids thread) (list (turn-id turn)))
          (thread-updated-at thread) (get-universal-time))
    (append-session-event session
                          :turn-started
                          (turn-record-summary turn)
                          :family :conversation
                          :entity-id (turn-id turn)
                          :thread-id (thread-id thread)
                          :turn-id (turn-id turn)
                          :visibility :operator)
    turn))

(defun complete-turn (session thread turn assistant-message &key error-state status metadata)
  (setf (turn-assistant-message-id turn) (message-id assistant-message)
        (message-turn-id assistant-message) (turn-id turn)
        (turn-status turn) (or status
                               (if error-state :failed :completed))
        (turn-completed-at turn) (get-universal-time)
        (turn-error-state turn) error-state
        (turn-metadata turn) (append (turn-metadata turn) metadata)
        (thread-updated-at thread) (get-universal-time))
  (append-session-event session
                        :turn-completed
                        (turn-record-summary turn)
                        :family :conversation
                        :entity-id (turn-id turn)
                        :thread-id (thread-id thread)
                        :turn-id (turn-id turn)
                        :visibility :operator)
  turn)

(defun refresh-turn-status (session turn &key status metadata)
  (let* ((thread (find-thread session (turn-thread-id turn)))
         (operations (list-turn-operations session (turn-id turn)))
         (next-status (or status
                          (turn-status-from-operations operations
                                                       :current-error-state (turn-error-state turn)))))
    (setf (turn-status turn) next-status
          (turn-metadata turn) (append (turn-metadata turn) metadata))
    (when thread
      (setf (thread-updated-at thread) (get-universal-time)))
    (append-session-event session
                          :turn-status-updated
                          (turn-record-summary turn)
                          :family :conversation
                          :entity-id (turn-id turn)
                          :thread-id (turn-thread-id turn)
                          :turn-id (turn-id turn)
                          :visibility :operator)
    turn))

(defun start-operation (session thread turn kind name input &key policy-decision metadata)
  (let ((operation (make-operation :id (make-operation-id)
                                   :thread-id (thread-id thread)
                                   :turn-id (turn-id turn)
                                   :kind kind
                                   :name name
                                   :input input
                                   :policy-decision policy-decision
                                   :status :running
                                   :output nil
                                   :started-at (get-universal-time)
                                   :completed-at nil
                                   :metadata metadata)))
    (setf (agent-session-operations session)
          (append (agent-session-operations session) (list operation))
          (turn-operation-ids turn)
          (append (turn-operation-ids turn) (list (operation-id operation))))
    (append-session-event session
                          :operation-started
                          (operation-record-summary operation)
                          :family :conversation
                          :entity-id (operation-id operation)
                          :thread-id (thread-id thread)
                          :turn-id (turn-id turn)
                          :visibility :operator)
    operation))

(defun complete-operation (session thread turn operation output &key failed-p status metadata)
  (declare (ignore turn))
  (setf (operation-status operation) (or status
                                        (if failed-p :failed :completed))
        (operation-output operation) output
        (operation-completed-at operation) (get-universal-time)
        (operation-metadata operation) (append (operation-metadata operation) metadata))
  (append-session-event session
                        :operation-completed
                        (operation-record-summary operation)
                        :family :conversation
                        :entity-id (operation-id operation)
                        :thread-id (thread-id thread)
                        :turn-id (operation-turn-id operation)
                        :visibility :operator)
  operation)

(defun create-artifact (session thread turn operation kind path
                        &key title summary metadata source-ref image-ref work-item-id)
  (let ((artifact (make-artifact :id (make-artifact-id)
                                 :kind kind
                                 :path path
                                 :title title
                                 :summary summary
                                 :thread-id (thread-id thread)
                                 :turn-id (and turn (turn-id turn))
                                 :operation-id (and operation (operation-id operation))
                                 :work-item-id work-item-id
                                 :source-ref source-ref
                                 :image-ref image-ref
                                 :created-at (get-universal-time)
                                 :metadata metadata)))
    (setf (agent-session-artifacts session)
          (append (agent-session-artifacts session) (list artifact))
          (thread-artifact-ids thread)
          (append (thread-artifact-ids thread) (list (artifact-id artifact)))
          (thread-updated-at thread) (get-universal-time))
    (when turn
      (setf (turn-artifact-ids turn)
            (append (turn-artifact-ids turn) (list (artifact-id artifact)))))
    (append-session-event session
                          :artifact-created
                          (artifact-record-summary artifact)
                          :family :artifact
                          :entity-id (artifact-id artifact)
                          :thread-id (thread-id thread)
                          :turn-id (and turn (turn-id turn))
                          :visibility :operator)
    artifact))

(defun maybe-create-patch-artifacts (session thread turn operation output)
  (let ((patch-results (getf (getf output :result) :patch)))
    (when (listp patch-results)
      (mapcar (lambda (entry)
                (let ((path (getf entry :path)))
                  (create-artifact session
                                   thread
                                   turn
                                   operation
                                   :file
                                   path
                                   :title (and path
                                               (file-namestring path))
                                   :summary "Patch write completed."
                                   :metadata (list :source :patch
                                                   :bytes (getf entry :bytes)
                                                   :operation (getf entry :operation)
                                                   :sandbox-profile (getf entry :sandbox-profile)))))
              patch-results))))

(defun conversation-turn-summary (thread user-message assistant-message turn)
  (list :thread (thread-record-summary thread)
        :user-message (message-record-summary user-message)
        :assistant-message (message-record-summary assistant-message)
        :turn (turn-record-summary turn)))

(defun turn-awaiting-approval-summary (operations)
  (let ((blocked
          (remove nil
                  (mapcar (lambda (operation)
                            (let ((decision (operation-policy-decision operation)))
                              (when (and (eq (getf decision :decision) :approval-required)
                                         (member (operation-status operation)
                                                 '(:awaiting-approval :staged)))
                                (list :operation-id (operation-id operation)
                                      :name (operation-name operation)
                                      :policy-id (getf decision :policy-id)
                                      :reason (getf decision :reason)
                                      :status (operation-status operation)))))
                          operations))))
    (list :awaiting-approval-p (not (null blocked))
          :blocked-operation-count (length blocked)
          :blocked-operations blocked)))

(defun thread-detail (session &optional thread-id)
  (let* ((thread (if thread-id
                     (or (find-thread session thread-id)
                         (error "Unknown thread ~A" thread-id))
                     (current-thread session)))
         (messages (mapcar #'message-record-summary
                           (list-thread-messages session (thread-id thread))))
         (turns (mapcar #'turn-record-summary
                        (list-thread-turns session (thread-id thread))))
         (artifacts (mapcar #'artifact-record-summary
                            (list-thread-artifacts session (thread-id thread)))))
    (append (thread-record-summary thread)
            (list :messages messages
                  :artifacts artifacts
                  :turns turns))))

(defun most-recent-thread-turn (session &optional thread-id)
  (let* ((thread (if thread-id
                     (or (find-thread session thread-id)
                         (error "Unknown thread ~A" thread-id))
                     (current-thread session)))
         (turns (list-thread-turns session (thread-id thread))))
    (car (last turns))))

(defun turn-detail (session &optional turn-id)
  (let* ((turn (if turn-id
                   (or (find-turn session turn-id)
                       (error "Unknown turn ~A" turn-id))
                   (or (most-recent-thread-turn session)
                       (error "No turns recorded for the current thread"))))
         (thread (find-thread session (turn-thread-id turn)))
         (user-message (find-message session (turn-user-message-id turn)))
         (assistant-message (find-message session (turn-assistant-message-id turn)))
         (operation-records (list-turn-operations session (turn-id turn)))
         (operations (mapcar #'operation-record-summary operation-records))
         (approval-summary (turn-awaiting-approval-summary operation-records))
         (artifacts (mapcar #'artifact-record-summary
                            (list-turn-artifacts session (turn-id turn)))))
    (append (turn-record-summary turn)
            (list :thread (and thread (thread-record-summary thread))
                  :user-message (and user-message (message-record-summary user-message))
                  :assistant-message (and assistant-message (message-record-summary assistant-message))
                  :operations operations
                  :artifacts artifacts
                  :awaiting-approval approval-summary))))
