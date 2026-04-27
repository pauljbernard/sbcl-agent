(in-package #:sbcl-agent)

(defstruct thread
  id
  title
  created-at
  updated-at
  summary
  message-ids
  message-ids-tail
  turn-ids
  turn-ids-tail
  artifact-ids
  artifact-ids-tail
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
  operation-ids-tail
  artifact-ids
  artifact-ids-tail
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
                 :message-ids-tail nil
                 :turn-ids '()
                 :turn-ids-tail nil
                 :artifact-ids '()
                 :artifact-ids-tail nil
                 :status :active
                 :metadata metadata)))

(defun rebuild-thread-tails (thread)
  (setf (thread-message-ids-tail thread) (last (thread-message-ids thread))
        (thread-turn-ids-tail thread) (last (thread-turn-ids thread))
        (thread-artifact-ids-tail thread) (last (thread-artifact-ids thread)))
  thread)

(defun rebuild-turn-tails (turn)
  (setf (turn-operation-ids-tail turn) (last (turn-operation-ids turn))
        (turn-artifact-ids-tail turn) (last (turn-artifact-ids turn)))
  turn)

(defun rebuild-conversation-tails (session)
  (dolist (thread (agent-session-threads session))
    (rebuild-thread-tails thread))
  (dolist (turn (agent-session-turns session))
    (rebuild-turn-tails turn))
  session)

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
              (unless (agent-session-threads-tail session)
                (setf (agent-session-threads-tail session)
                      (last (agent-session-threads session))))
              existing)
            (let ((thread (make-session-thread :title "Default Thread"
                                               :summary "Auto-created default conversation thread."
                                               :metadata '(:default-p t))))
              (setf (agent-session-threads session) (list thread)
                    (agent-session-threads-tail session) (last (agent-session-threads session))
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
    (multiple-value-bind (threads tail)
        (append-linked-item (agent-session-threads session)
                            (agent-session-threads-tail session)
                            thread)
      (setf (agent-session-threads session) threads
            (agent-session-threads-tail session) tail))
    (setf (agent-session-current-thread-id session) (thread-id thread))
    (append-session-event session
                          :thread-created
                          (thread-record-summary thread)
                          :family :conversation
                          :entity-id (thread-id thread)
                          :thread-id (thread-id thread)
                          :visibility :operator)
    thread))

(defun update-thread (session thread-id &key title summary metadata)
  (let ((thread (find-thread session thread-id)))
    (unless thread
      (error "Unknown thread ~A" thread-id))
    (when title
      (setf (thread-title thread) title))
    (when summary
      (setf (thread-summary thread) summary))
    (when metadata
      (setf (thread-metadata thread) metadata))
    (setf (thread-updated-at thread) (get-universal-time))
    (append-session-event session
                          :thread-updated
                          (thread-record-summary thread)
                          :family :conversation
                          :entity-id thread-id
                          :thread-id thread-id
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
    ((find :interrupted operations :key #'operation-status) :interrupted)
    ((find :failed operations :key #'operation-status) :failed)
    (t :completed)))

(defun operation-action-assessment-summary (operation)
  (let ((assessment (getf (operation-metadata operation) :action-assessment)))
    (when (listp assessment)
      (list :grounding-score (getf assessment :grounding-score)
            :weakly-grounded-p (getf assessment :weakly-grounded-p)
            :reason (getf assessment :reason)
            :matched-top-labels (copy-list (or (getf assessment :matched-top-labels) '()))
            :relevant-domains (copy-list (or (getf assessment :relevant-domains) '()))))))

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
        :action-assessment (operation-action-assessment-summary operation)
        :metadata (operation-metadata operation)))

(defun turn-action-assessment-summary (operations)
  (let* ((assessed-operations (remove-if-not (lambda (operation)
                                               (getf operation :action-assessment))
                                             operations))
         (weakly-grounded-operations (remove-if-not (lambda (operation)
                                                      (getf (getf operation :action-assessment)
                                                            :weakly-grounded-p))
                                                    assessed-operations))
         (deferred-weakly-grounded-operations
           (remove-if-not (lambda (operation)
                            (and (eq (getf operation :status) :blocked)
                                 (eq (getf (getf operation :policy-decision) :decision)
                                     :deferred)))
                          weakly-grounded-operations)))
    (list :assessed-operation-count (length assessed-operations)
          :weakly-grounded-operation-count (length weakly-grounded-operations)
          :deferred-weakly-grounded-operation-count
          (length deferred-weakly-grounded-operations)
          :weakly-grounded-operation-ids
          (mapcar (lambda (operation) (getf operation :id))
                  weakly-grounded-operations))))

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

(defun artifact-kind-summary (artifacts)
  (let ((table (make-hash-table :test #'eq)))
    (dolist (artifact artifacts)
      (incf (gethash (artifact-kind artifact) table 0)))
    (let (summary)
      (maphash (lambda (kind count)
                 (push (list :kind kind :count count) summary))
               table)
      (sort summary #'string<
            :key (lambda (entry) (symbol-name (getf entry :kind)))))))

(defun artifact-kind-summary-from-records (artifact-records)
  (let ((table (make-hash-table :test #'eq)))
    (dolist (artifact-record artifact-records)
      (incf (gethash (getf artifact-record :kind) table 0)))
    (let (summary)
      (maphash (lambda (kind count)
                 (push (list :kind kind :count count) summary))
               table)
      (sort summary #'string<
            :key (lambda (entry) (symbol-name (getf entry :kind)))))))

(defun artifact-summary-from-records (artifact-records)
  (let* ((kind-summary (artifact-kind-summary-from-records artifact-records)))
    (list :artifact-count (length artifact-records)
          :kind-counts kind-summary
          :validation-count (or (getf (find :validation kind-summary
                                            :key (lambda (entry) (getf entry :kind))
                                            :test #'eq)
                                       :count)
                                0)
          :reconciliation-count (or (getf (find :reconciliation kind-summary
                                                :key (lambda (entry) (getf entry :kind))
                                                :test #'eq)
                                           :count)
                                    0)
          :incident-count (or (getf (find :incident kind-summary
                                          :key (lambda (entry) (getf entry :kind))
                                          :test #'eq)
                                     :count)
                              0)
          :plan-count (or (getf (find :plan kind-summary
                                      :key (lambda (entry) (getf entry :kind))
                                      :test #'eq)
                                 :count)
                          0)
          :runtime-artifact-count (count-if (lambda (artifact-record)
                                              (member (getf artifact-record :kind)
                                                      '(:runtime-state :runtime-eval :runtime-reload)
                                                      :test #'eq))
                                            artifact-records))))

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
  (let ((environment (session-bound-environment session)))
    (or (and environment
             (environment-artifact environment artifact-id))
        (find artifact-id (agent-session-artifacts session)
              :key #'artifact-id :test #'string=))))

(defun list-thread-messages (session thread-id)
  (remove-if-not (lambda (message)
                   (string= thread-id (message-thread-id message)))
                 (agent-session-messages session)))

(defun list-turn-messages (session turn-id)
  (remove-if-not (lambda (message)
                   (string= turn-id (message-turn-id message)))
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
  (let ((environment (session-bound-environment session)))
    (or (and environment
             (environment-thread-artifacts environment thread-id))
        (remove-if-not (lambda (artifact)
                         (string= thread-id (artifact-thread-id artifact)))
                       (agent-session-artifacts session)))))

(defun list-turn-artifacts (session turn-id)
  (let ((environment (session-bound-environment session)))
    (or (and environment
             (environment-turn-artifacts environment turn-id))
        (remove-if-not (lambda (artifact)
                         (string= turn-id (artifact-turn-id artifact)))
                       (agent-session-artifacts session)))))

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
    (multiple-value-bind (messages tail)
        (append-linked-item (agent-session-messages session)
                            (agent-session-messages-tail session)
                            message)
      (setf (agent-session-messages session) messages
            (agent-session-messages-tail session) tail))
    (multiple-value-bind (message-ids tail)
        (append-linked-item (thread-message-ids thread)
                            (thread-message-ids-tail thread)
                            (message-id message))
      (setf (thread-message-ids thread) message-ids
            (thread-message-ids-tail thread) tail))
    (setf (thread-updated-at thread) (get-universal-time))
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
    (setf (message-turn-id user-message) (turn-id turn))
    (multiple-value-bind (turns tail)
        (append-linked-item (agent-session-turns session)
                            (agent-session-turns-tail session)
                            turn)
      (setf (agent-session-turns session) turns
            (agent-session-turns-tail session) tail))
    (multiple-value-bind (turn-ids tail)
        (append-linked-item (thread-turn-ids thread)
                            (thread-turn-ids-tail thread)
                            (turn-id turn))
      (setf (thread-turn-ids thread) turn-ids
            (thread-turn-ids-tail thread) tail))
    (setf (thread-updated-at thread) (get-universal-time))
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

(defun remove-turn-metadata-key (turn key)
  (labels ((strip (plist)
             (cond
               ((null plist) '())
               ((eq (first plist) key)
                (strip (cddr plist)))
               (t
                (list* (first plist)
                       (second plist)
                       (strip (cddr plist)))))))
    (setf (turn-metadata turn) (strip (turn-metadata turn)))
    turn))

(defun mark-turn-followup-started (session turn &key metadata)
  (let ((thread (find-thread session (turn-thread-id turn))))
    (remove-turn-metadata-key turn :followup-state)
    (setf (turn-status turn) :running
          (turn-metadata turn) (append (turn-metadata turn)
                                       (append (list :followup-state :running) metadata)))
    (when thread
      (setf (thread-updated-at thread) (get-universal-time)))
    (append-session-event session
                          :turn-followup-started
                          (turn-record-summary turn)
                          :family :conversation
                          :entity-id (turn-id turn)
                          :thread-id (turn-thread-id turn)
                          :turn-id (turn-id turn)
                          :visibility :operator)
    turn))

(defun mark-turn-followup-completed (session turn &key metadata)
  (let ((thread (find-thread session (turn-thread-id turn))))
    (remove-turn-metadata-key turn :followup-state)
    (setf (turn-metadata turn) (append (turn-metadata turn)
                                       (append (list :followup-state :completed) metadata)))
    (when thread
      (setf (thread-updated-at thread) (get-universal-time)))
    (append-session-event session
                          :turn-followup-completed
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
    (multiple-value-bind (operations tail)
        (append-linked-item (agent-session-operations session)
                            (agent-session-operations-tail session)
                            operation)
      (setf (agent-session-operations session) operations
            (agent-session-operations-tail session) tail))
    (multiple-value-bind (operation-ids tail)
        (append-linked-item (turn-operation-ids turn)
                            (turn-operation-ids-tail turn)
                            (operation-id operation))
      (setf (turn-operation-ids turn) operation-ids
            (turn-operation-ids-tail turn) tail))
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
                                 :thread-id (and thread (thread-id thread))
                                 :turn-id (and turn (turn-id turn))
                                 :operation-id (and operation (operation-id operation))
                                 :work-item-id work-item-id
                                 :source-ref source-ref
                                 :image-ref image-ref
                                 :created-at (get-universal-time)
                                 :metadata metadata)))
    (multiple-value-bind (artifacts tail)
        (append-linked-item (agent-session-artifacts session)
                            (agent-session-artifacts-tail session)
                            artifact)
      (setf (agent-session-artifacts session) artifacts
            (agent-session-artifacts-tail session) tail))
    (when thread
      (multiple-value-bind (artifact-ids tail)
          (append-linked-item (thread-artifact-ids thread)
                              (thread-artifact-ids-tail thread)
                              (artifact-id artifact))
        (setf (thread-artifact-ids thread) artifact-ids
              (thread-artifact-ids-tail thread) tail))
      (setf (thread-updated-at thread) (get-universal-time)))
    (when turn
      (multiple-value-bind (artifact-ids tail)
          (append-linked-item (turn-artifact-ids turn)
                              (turn-artifact-ids-tail turn)
                              (artifact-id artifact))
        (setf (turn-artifact-ids turn) artifact-ids
              (turn-artifact-ids-tail turn) tail)))
    (let ((environment (session-bound-environment session)))
      (when environment
        (environment-append-artifact environment session artifact)))
    (append-session-event session
                          :artifact-created
                          (artifact-record-summary artifact)
                          :family :artifact
                          :entity-id (artifact-id artifact)
                          :thread-id (and thread (thread-id thread))
                          :turn-id (and turn (turn-id turn))
                          :visibility :operator)
    artifact))

(defun create-environment-artifact (session kind path
                                    &key title summary metadata source-ref image-ref work-item-id)
  (create-artifact session
                   nil
                   nil
                   nil
                   kind
                   path
                   :title title
                   :summary summary
                   :metadata (append metadata '(:ownership :environment))
                   :source-ref source-ref
                   :image-ref image-ref
                   :work-item-id work-item-id))

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

(defun turn-recovery-summary (session turn operation-records)
  (let* ((work-item-id (getf (turn-metadata turn) :work-item-id))
         (work-item (and work-item-id
                         (find-work-item session work-item-id)))
         (interrupted-operations
           (remove nil
                   (mapcar (lambda (operation)
                             (when (eq (operation-status operation) :interrupted)
                               (list :operation-id (operation-id operation)
                                     :name (operation-name operation)
                                     :status (operation-status operation)
                                     :recovery-state (getf (operation-metadata operation) :recovery-state)
                                     :interrupted-during-load-p (getf (operation-metadata operation)
                                                                      :interrupted-during-load-p))))
                           operation-records)))
         (resumable-operations
           (remove nil
                   (mapcar (lambda (operation)
                             (when (member (operation-status operation) '(:awaiting-approval :staged))
                               (list :operation-id (operation-id operation)
                                     :name (operation-name operation)
                                     :status (operation-status operation)
                                     :policy-id (getf (operation-policy-decision operation) :policy-id)
                                     :work-item-id (getf (operation-metadata operation) :work-item-id))))
                           operation-records))))
    (list :resumable-p (or (not (null resumable-operations))
                           (and work-item (not (null (work-item-resume-payload work-item)))))
          :interrupted-p (not (null interrupted-operations))
          :interrupted-operation-count (length interrupted-operations)
          :interrupted-operations interrupted-operations
          :resumable-operation-count (length resumable-operations)
          :resumable-operations resumable-operations
          :work-item-id work-item-id
          :work-item-resume-payload (and work-item
                                         (work-item-resume-payload work-item))
          :workflow-record-resume-payload (and work-item
                                               (let ((record (work-item-workflow-record session work-item)))
                                                 (and record
                                                      (workflow-record-resume-payload record)))))))

(defun thread-detail (session &optional thread-id)
  (let* ((thread (if thread-id
                     (or (find-thread session thread-id)
                         (error "Unknown thread ~A" thread-id))
                     (current-thread session)))
         (messages (mapcar #'message-record-summary
                           (list-thread-messages session (thread-id thread))))
         (turns (mapcar #'turn-record-summary
                        (list-thread-turns session (thread-id thread))))
         (incidents (list-incident-summaries session :thread-id (thread-id thread)))
         (artifacts (mapcar #'artifact-record-summary
                            (list-thread-artifacts session (thread-id thread)))))
    (append (thread-record-summary thread)
            (list :messages messages
                  :detail-summary (list :message-count (length messages)
                                        :turn-count (length turns)
                                        :incident-count (length incidents)
                                        :artifact-count (length artifacts)
                                        :runtime-artifact-count (count-if (lambda (artifact)
                                                                            (member (getf artifact :kind)
                                                                                    '(:runtime-state :runtime-eval :runtime-reload)
                                                                                    :test #'eq))
                                                                          artifacts)
                                        :work-item-artifact-count (count-if (lambda (artifact)
                                                                              (getf artifact :work-item-id))
                                                                            artifacts))
                  :incidents incidents
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
         (messages (mapcar #'message-record-summary
                           (list-turn-messages session (turn-id turn))))
         (operation-records (list-turn-operations session (turn-id turn)))
         (operations (mapcar #'operation-record-summary operation-records))
         (approval-summary (turn-awaiting-approval-summary operation-records))
         (incidents (list-incident-summaries session :turn-id (turn-id turn)))
         (artifacts (mapcar #'artifact-record-summary
                            (list-turn-artifacts session (turn-id turn))))
         (work-item-id (getf (turn-metadata turn) :work-item-id))
         (work-item (and work-item-id
                         (find-work-item session work-item-id)))
         (workflow-record (and work-item
                               (work-item-workflow-record session work-item)))
         (recovery-summary (turn-recovery-summary session turn operation-records))
         (action-assessment-summary (turn-action-assessment-summary operations))
         (execution-handles (kernel-execution-summaries-by-target :turn-id
                                                                  (turn-id turn))))
    (append (turn-record-summary turn)
            (list :primary-execution-handle (first execution-handles)
                  :execution-handles execution-handles)
            (list :thread (and thread (thread-record-summary thread))
                  :user-message (and user-message (message-record-summary user-message))
                  :assistant-message (and assistant-message (message-record-summary assistant-message))
                  :messages messages
                  :detail-summary (list :message-count (length messages)
                                        :operation-count (length operations)
                                        :incident-count (length incidents)
                                        :artifact-count (length artifacts)
                                        :runtime-operation-count (count-if (lambda (operation)
                                                                            (let* ((output (getf operation :output))
                                                                                   (tool-result (if (and (listp output) (getf output :tool))
                                                                                                    output
                                                                                                    (and (listp output)
                                                                                                         (getf output :result)))))
                                                                              (member (and (listp tool-result)
                                                                                           (getf tool-result :tool))
                                                                                    '(:runtime/eval :runtime/reload-file :runtime/set-package)
                                                                                    :test #'eq)))
                                                                          operations)
                                        :runtime-artifact-count (count-if (lambda (artifact)
                                                                            (member (getf artifact :kind)
                                                                                    '(:runtime-state :runtime-eval :runtime-reload)
                                                                                    :test #'eq))
                                                                          artifacts)
                                        :assessed-operation-count
                                        (getf action-assessment-summary :assessed-operation-count)
                                        :weakly-grounded-operation-count
                                        (getf action-assessment-summary :weakly-grounded-operation-count)
                                        :deferred-weakly-grounded-operation-count
                                        (getf action-assessment-summary
                                              :deferred-weakly-grounded-operation-count)
                                        :work-item-id work-item-id
                                        :work-item-status (and work-item (work-item-status work-item))
                                        :workflow-record-status (and workflow-record
                                                                     (workflow-record-status workflow-record)))
                  :action-assessment-summary action-assessment-summary
                  :operations operations
                  :incidents incidents
                  :artifacts artifacts
                  :recovery recovery-summary
                  :awaiting-approval approval-summary))))

(defun mutation-review (session &optional turn-id)
  (let* ((detail (turn-detail session turn-id))
         (resolved-turn-id (getf detail :id))
         (operations (getf detail :operations))
         (artifacts (getf detail :artifacts))
         (incidents (getf detail :incidents))
         (detail-summary (getf detail :detail-summary))
         (work-item-id (or (getf detail-summary :work-item-id)
                           (getf (first artifacts) :work-item-id)
                           (getf (first incidents) :work-item-id)
                           (getf (getf detail :recovery) :work-item-id)
                           (loop for operation in operations
                                 for output = (getf operation :output)
                                 for result = (cond
                                                ((and (listp output) (getf output :result))
                                                 (getf output :result))
                                                ((listp output) output)
                                                (t nil))
                                 for candidate = (and (listp result)
                                                      (getf result :work-item-id))
                                 when candidate
                                   return candidate)))
         (work-item (and work-item-id
                         (find-work-item session work-item-id)))
         (workflow-record (and work-item
                               (work-item-workflow-record session work-item)))
         (work-item-summary (and work-item
                                 (kernel-enrich-summary-with-executions
                                  (work-item-summary work-item)
                                  :work-item-id
                                  (work-item-id work-item))))
         (workflow-record-summary (and workflow-record
                                       (kernel-enrich-summary-with-executions
                                        (workflow-record-summary workflow-record)
                                        :workflow-record-id
                                        (workflow-record-id workflow-record))))
         (wait-report (and work-item
                           (work-item-wait-report session work-item)))
         (runtime-artifacts (remove-if-not (lambda (artifact)
                                             (member (getf artifact :kind)
                                                     '(:runtime-state :runtime-eval :runtime-reload)
                                                     :test #'eq))
                                           artifacts))
         (validation-artifacts (remove-if-not (lambda (artifact)
                                                (eq (getf artifact :kind) :validation))
                                              artifacts)))
    (list :turn (list :id resolved-turn-id
                      :status (getf detail :status)
                      :thread-id (getf (getf detail :thread) :id)
                      :primary-execution-handle (getf detail :primary-execution-handle)
                      :execution-handles (getf detail :execution-handles)
                      :user-message (getf (getf detail :user-message) :content)
                      :assistant-message (getf (getf detail :assistant-message) :content)
                      :recovery (getf detail :recovery)
                      :awaiting-approval (getf detail :awaiting-approval))
          :mutation (list :operation-count (length operations)
                          :artifact-count (length artifacts)
                          :runtime-operation-count (getf detail-summary :runtime-operation-count)
                          :runtime-artifact-count (getf detail-summary :runtime-artifact-count)
                          :operations operations
                          :artifacts artifacts)
          :governance (list :work-item work-item-summary
                            :workflow-record workflow-record-summary
                            :wait wait-report
                            :next-action (and wait-report (getf wait-report :next-action))
                            :resume-payload (and wait-report (getf wait-report :resume-payload))
                            :action-assessment-summary
                            (getf detail :action-assessment-summary))
          :evidence (list :checkpoint-count (if work-item
                                                (length (work-item-checkpoints work-item))
                                                0)
                          :latest-checkpoint-id (and work-item
                                                     (latest-work-item-checkpoint-id work-item))
                          :runtime-observation-count (if work-item
                                                         (length (work-item-runtime-observations work-item))
                                                         0)
                          :validator-task-count (if work-item
                                                    (length (work-item-validator-tasks work-item))
                                                    0)
                          :validation-artifacts validation-artifacts
                          :runtime-artifacts runtime-artifacts
                          :latest-runtime-observation (and work-item
                                                          (car (last (work-item-runtime-observations work-item))))
                          :latest-runtime-evidence (or (and work-item
                                                            (car (last (work-item-runtime-observations work-item))))
                                                       (first incidents)))
          :incidents incidents)))
