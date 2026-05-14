(in-package #:sbcl-agent)

(defstruct desktop-task-request
  id
  protocol-version
  requester
  actor-message
  target
  operation
  payload
  capability
  idempotency-key
  surface-context
  surface-actions
  metadata
  created-at)

(defstruct desktop-task-manifest
  id
  target
  operation
  capability
  description
  request-schema
  result-schema
  approval-policy
  execution-mode
  retry-policy
  backend-kind
  backend-ref
  version
  tags
  discoverable-p
  metadata)

(defstruct desktop-task-record
  id
  protocol-version
  request-id
  requester
  actor-message
  target
  operation
  capability
  backend-kind
  backend-ref
  status
  governance-status
  approval-status
  retry-policy
  retry-count
  max-attempts
  idempotency-key
  payload
  request-metadata
  thread-id
  turn-id
  conversation-operation-id
  created-at
  approved-at
  started-at
  completed-at
  last-error
  resolution
  result
  metadata)

(defstruct desktop-task-resolution
  request-id
  target
  operation
  summary
  actions
  executor
  metadata)

(defun serializable-desktop-task-resolution (resolution)
  (when resolution
    (let ((copy (copy-desktop-task-resolution resolution)))
      (setf (desktop-task-resolution-actions copy)
            (copy-tree (or (desktop-task-resolution-actions resolution) '()))
            (desktop-task-resolution-executor copy) nil
            (desktop-task-resolution-metadata copy)
            (copy-tree (or (desktop-task-resolution-metadata resolution) '())))
      copy)))

(defun serializable-desktop-task-record (record)
  (let ((copy (copy-desktop-task-record record)))
    (setf (desktop-task-record-payload copy)
          (copy-tree (or (desktop-task-record-payload record) '()))
          (desktop-task-record-retry-policy copy)
          (copy-tree (or (desktop-task-record-retry-policy record) '()))
          (desktop-task-record-request-metadata copy)
          (copy-tree (or (desktop-task-record-request-metadata record) '()))
          (desktop-task-record-last-error copy)
          (copy-tree (or (desktop-task-record-last-error record) '()))
          (desktop-task-record-resolution copy)
          (serializable-desktop-task-resolution
           (desktop-task-record-resolution record))
          (desktop-task-record-result copy)
          (copy-tree (or (desktop-task-record-result record) '()))
          (desktop-task-record-metadata copy)
          (copy-tree (or (desktop-task-record-metadata record) '())))
    copy))

(defstruct desktop-task-result
  request-id
  target
  operation
  status
  summary
  action-results
  metadata)

(defstruct actor-address
  id
  kind
  role
  display-name
  metadata)

(defstruct actor-allocation-strategy
  type
  shared-inbox-id
  pool-size
  consumption-policy
  metadata)

(defstruct actor-supervision-policy
  strategy
  max-restarts
  restart-window-seconds
  on-failure
  escalation-target
  metadata)

(defstruct actor-execution-policy
  model
  thread-name
  mailbox-mode
  max-concurrency
  metadata)

(defstruct actor-definition
  id
  role
  display-name
  parent-actor-id
  inbox-id
  outbox-id
  handler-mode
  llm-profile
  capabilities
  allocation-strategy
  supervision-policy
  execution-policy
  metadata)

(defstruct actor-message
  id
  protocol-version
  sender
  reply-to
  originator
  receiver
  request-id
  correlation-id
  session-id
  approval-id
  actor-slice
  pending-action-id
  target
  operation
  capability
  state
  payload
  metadata
  created-at
  received-at
  completed-at)

(defstruct actor-mailbox-entry
  id
  owner
  mailbox
  direction
  session-id
  approval-id
  pending-action-id
  actor-message-id
  request-id
  target
  operation
  status
  governance-status
  approval-status
  delivery-status
  sent-at
  delivered-at
  dequeued-at
  acknowledged-at
  completed-at
  reply-to
  originator
  sender
  receiver
  payload
  metadata)

(defparameter +desktop-task-dlq-actor-role+ :dead-letter-queue)
(defparameter +desktop-task-governance-actor-role+ :governance)

(defstruct mcp-server-config
  id
  name
  transport
  command
  arguments
  environment-variables
  working-directory
  endpoint
  capabilities
  retry-policy
  health-status
  enabled-p
  discoverable-p
  metadata
  created-at
  updated-at)

(defparameter +desktop-task-protocol-version+ 1)
(defparameter +desktop-actor-protocol-version+ 1)
(defparameter +desktop-task-mcp-server-registry-key+ :desktop-task-mcp-server-registry)
(defparameter *desktop-task-receiver-registry* (make-hash-table :test #'equal))
(defparameter *desktop-task-manifest-registry* (make-hash-table :test #'equal))
(defparameter *desktop-task-planner-registry* (make-hash-table :test #'equal))
(defparameter *desktop-task-backend-invoker-registry* (make-hash-table :test #'equal))

(defun make-desktop-task-request-id ()
  (format nil "desktop-task-~D-~D" (get-universal-time) (random 1000000)))

(defun make-desktop-task-record-id ()
  (format nil "desktop-task-record-~D-~D" (get-universal-time) (random 1000000)))

(defun make-actor-message-id ()
  (format nil "actor-message-~D-~D" (get-universal-time) (random 1000000)))

(defun make-actor-mailbox-entry-id (&key mailbox actor-message-id request-id pending-action-id session-id)
  (let ((identity (or actor-message-id request-id pending-action-id session-id "anonymous")))
    (format nil "actor-mailbox-entry/~(~A~)/~A" mailbox identity)))

(defun make-governance-approval-id ()
  (format nil "approval-~D-~D" (get-universal-time) (random 1000000)))

(defun make-pending-action-id (role)
  (format nil "~(~A~)-pending-~D-~D"
          (normalize-actor-role role :pending-action)
          (get-universal-time)
          (random 1000000)))

(defun make-actor-address-id (role &key scope)
  (if (and scope (stringp scope) (> (length scope) 0))
      (format nil "actor/~(~A~)/~A" role scope)
      (format nil "actor/~(~A~)" role)))

(defun normalize-actor-role (value fallback)
  (typecase value
    (keyword value)
    (symbol (intern (string-upcase (symbol-name value)) "KEYWORD"))
    (string (intern (string-upcase value) "KEYWORD"))
    (t fallback)))

(defun make-standard-actor-address (role &key kind display-name metadata scope)
  (let ((effective-role (normalize-actor-role role :unknown)))
    (make-actor-address
     :id (make-actor-address-id effective-role :scope scope)
     :kind (or kind :internal)
     :role effective-role
     :display-name (or display-name
                       (string-capitalize
                        (substitute #\Space #\- (string-downcase (string effective-role)))))
     :metadata metadata)))

(defun desktop-task-requester-actor-address-for-request (request)
  (let* ((requester (desktop-task-request-requester request))
         (request-metadata (desktop-task-request-metadata request))
         (session-id (and (listp request-metadata)
                          (or (getf request-metadata :session-id)
                              (getf request-metadata :SESSION-ID))))
         (role (normalize-actor-role requester :context-chat)))
    (case role
      (:context-chat
       (make-standard-actor-address :context-chat
                                    :kind :internal
                                    :display-name "Context Chat"
                                    :scope session-id
                                    :metadata (append '(:actor-class :conversation-client)
                                                      (when session-id
                                                        (list :session-id session-id)))))
      (otherwise
       (make-standard-actor-address role
                                    :kind :internal
                                    :scope session-id
                                    :metadata (append '(:actor-class :conversation-client)
                                                      (when session-id
                                                        (list :session-id session-id))))))))

(defun desktop-task-receiver-actor-address (target &key capability backend-kind backend-ref scope)
  (let ((role (normalize-actor-role target :capability-server)))
    (make-standard-actor-address role
                                 :kind (or backend-kind :internal)
                                 :scope scope
                                 :display-name (format nil "~A Actor"
                                                       (string-capitalize
                                                        (substitute #\Space #\-
                                                                    (string-downcase
                                                                     (string role)))))
                                 :metadata (append (list :actor-class :capability-server)
                                                   (when capability
                                                     (list :capability capability))
                                                   (when backend-ref
                                                     (list :backend-ref backend-ref))))))

(defun actor-address-summary (address)
  (and address
       (list :id (actor-address-id address)
             :kind (actor-address-kind address)
             :role (actor-address-role address)
             :display-name (actor-address-display-name address)
             :metadata (actor-address-metadata address))))

(defun make-dead-letter-actor-address ()
  (make-standard-actor-address +desktop-task-dlq-actor-role+
                               :kind :internal
                               :display-name "Dead Letter Queue"
                               :metadata '(:actor-class :dead-letter-queue)))

(defun make-governance-actor-address (&key session-id)
  (make-standard-actor-address +desktop-task-governance-actor-role+
                               :kind :internal
                               :scope session-id
                               :display-name "Governance"
                               :metadata (append '(:actor-class :governance-coordinator)
                                                 (when session-id
                                                   (list :session-id session-id)))))

(defun actor-message-summary (message)
  (and message
       (list :id (actor-message-id message)
             :protocol-version (actor-message-protocol-version message)
             :sender (actor-address-summary (actor-message-sender message))
             :reply-to (actor-address-summary (actor-message-reply-to message))
             :originator (actor-address-summary (actor-message-originator message))
             :receiver (actor-address-summary (actor-message-receiver message))
             :request-id (actor-message-request-id message)
             :correlation-id (actor-message-correlation-id message)
             :session-id (or (actor-message-session-id message)
                             (getf (actor-message-metadata message) :session-id)
                             (getf (actor-message-metadata message) :SESSION-ID))
             :approval-id (or (actor-message-approval-id message)
                              (getf (actor-message-metadata message) :approval-id)
                              (getf (actor-message-metadata message) :APPROVAL-ID))
             :actor-slice (or (actor-message-actor-slice message)
                              (getf (actor-message-metadata message) :slice)
                              (getf (actor-message-metadata message) :SLICE))
             :pending-action-id (or (actor-message-pending-action-id message)
                                    (getf (actor-message-metadata message) :pending-action-id)
                                    (getf (actor-message-metadata message) :PENDING-ACTION-ID))
             :target (actor-message-target message)
             :operation (actor-message-operation message)
             :capability (actor-message-capability message)
             :state (actor-message-state message)
             :metadata (actor-message-metadata message)
             :created-at (actor-message-created-at message)
             :received-at (actor-message-received-at message)
             :completed-at (actor-message-completed-at message))))

(defun transition-actor-message (message state &key received-at completed-at metadata)
  (when message
    (setf (actor-message-state message) state)
    (when received-at
      (setf (actor-message-received-at message) received-at))
    (when completed-at
      (setf (actor-message-completed-at message) completed-at))
    (when metadata
      (when (getf metadata :session-id)
        (setf (actor-message-session-id message) (getf metadata :session-id)))
      (when (getf metadata :approval-id)
        (setf (actor-message-approval-id message) (getf metadata :approval-id)))
      (when (getf metadata :slice)
        (setf (actor-message-actor-slice message) (getf metadata :slice)))
      (when (getf metadata :pending-action-id)
        (setf (actor-message-pending-action-id message) (getf metadata :pending-action-id)))
      (setf (actor-message-metadata message)
            (append (actor-message-metadata message) metadata))))
  message)

(defun actor-message-dead-letter-p (message)
  (and message
       (or (eq (actor-message-state message) :dead-letter)
           (getf (actor-message-metadata message) :dead-letter-p)
           (getf (actor-message-metadata message) :DEAD-LETTER-P))))

(defun dead-letter-actor-message (message &key reason completed-at metadata)
  (when message
    (setf (actor-message-receiver message) (make-dead-letter-actor-address))
    (transition-actor-message
     message
     :dead-letter
     :completed-at (or completed-at (get-universal-time))
     :metadata (append (list :dead-letter-p t)
                       (when reason
                         (list :dead-letter-reason reason))
                       metadata))))

(defun actor-message-transport-summary (message phase &key record reason metadata)
  (let ((sender (and message
                     (actor-message-sender message)))
        (receiver (and message
                       (actor-message-receiver message))))
    (list :phase phase
          :record-id (and record
                          (desktop-task-record-id record))
          :request-id (and message
                           (actor-message-request-id message))
          :actor-message-id (and message
                                 (actor-message-id message))
          :target (and message
                       (actor-message-target message))
          :operation (and message
                          (actor-message-operation message))
          :sender (actor-address-summary sender)
          :receiver (actor-address-summary receiver)
          :state (and message
                      (actor-message-state message))
          :reason reason
          :dead-letter-p (actor-message-dead-letter-p message)
          :metadata metadata
          :actor-message (actor-message-summary message))))

(defun append-actor-message-transport-event (session phase record &key reason metadata)
  (let ((message (desktop-task-record-actor-message record)))
    (when message
      (append-session-event
       session
       :actor-message-transport
       (actor-message-transport-summary message
                                        phase
                                        :record record
                                        :reason reason
                                        :metadata metadata)
       :family :assistant
       :entity-id (or (actor-message-id message)
                      (desktop-task-record-id record))
       :thread-id (desktop-task-record-thread-id record)
       :turn-id (desktop-task-record-turn-id record)
       :visibility :operator))))

(defun make-desktop-task-actor-message (request &key capability backend-kind backend-ref state metadata)
  (let* ((request-metadata (desktop-task-request-metadata request))
         (session-id (or (getf metadata :session-id)
                         (and (listp request-metadata)
                              (or (getf request-metadata :session-id)
                                  (getf request-metadata :SESSION-ID)))))
         (approval-id (or (getf metadata :approval-id)
                          (and (listp request-metadata)
                               (or (getf request-metadata :approval-id)
                                   (getf request-metadata :APPROVAL-ID)))))
         (actor-slice (or (getf metadata :slice)
                          (and (listp request-metadata)
                               (or (getf request-metadata :actor-slice)
                                   (getf request-metadata :ACTOR-SLICE)))))
         (pending-action-id (or (getf metadata :pending-action-id)
                                (and (listp request-metadata)
                                     (or (getf request-metadata :pending-action-id)
                                         (getf request-metadata :PENDING-ACTION-ID)))
                                (when (eq (desktop-task-request-target request) :editor)
                                  (make-pending-action-id :editor))))
         (sender-address (desktop-task-requester-actor-address-for-request request))
         (receiver-scope (or (and (listp request-metadata)
                                  (or (getf request-metadata :receiver-scope)
                                      (getf request-metadata :RECEIVER-SCOPE)))
                             (and (listp request-metadata)
                                  (or (getf request-metadata :scope-id)
                                      (getf request-metadata :SCOPE-ID)))
                             session-id)))
  (make-actor-message
   :id (make-actor-message-id)
   :protocol-version +desktop-actor-protocol-version+
   :sender sender-address
   :reply-to sender-address
   :originator sender-address
   :receiver (desktop-task-receiver-actor-address
              (desktop-task-request-target request)
              :capability (or capability
                              (desktop-task-request-capability request))
              :backend-kind backend-kind
              :backend-ref backend-ref
              :scope receiver-scope)
   :request-id (desktop-task-request-id request)
   :correlation-id (desktop-task-request-idempotency-key request)
   :session-id session-id
   :approval-id approval-id
   :actor-slice actor-slice
   :pending-action-id pending-action-id
   :target (desktop-task-request-target request)
   :operation (desktop-task-request-operation request)
   :capability (or capability
                   (desktop-task-request-capability request))
   :state (or state :queued)
   :payload (desktop-task-request-payload request)
   :metadata metadata
   :created-at (or (desktop-task-request-created-at request)
                   (get-universal-time)))))

(defun make-mcp-server-config-id (&optional name)
  (if (and name (stringp name) (> (length (string-trim " " name)) 0))
      (let ((normalized
              (string-downcase
               (substitute #\- #\Space (string-trim " " name)))))
        (format nil "mcp-~A-~D" normalized (random 1000000)))
      (format nil "mcp-~D-~D" (get-universal-time) (random 1000000))))

(defun desktop-task-receiver-key (target operation)
  (list (string-downcase (string target))
        (string-downcase (string operation))))

(defun register-desktop-task-receiver (target operation handler)
  (setf (gethash (desktop-task-receiver-key target operation)
                 *desktop-task-receiver-registry*)
        handler)
  handler)

(defun register-desktop-task-manifest (target operation &key capability description
                                                          request-schema result-schema
                                                          approval-policy execution-mode
                                                          retry-policy backend-kind backend-ref
                                                          (version +desktop-task-protocol-version+)
                                                          tags (discoverable-p t) metadata)
  (let ((manifest (make-desktop-task-manifest
                   :id (format nil "~(~A~)/~(~A~)" target operation)
                   :target target
                   :operation operation
                   :capability capability
                   :description description
                   :request-schema request-schema
                   :result-schema result-schema
                   :approval-policy approval-policy
                   :execution-mode (or execution-mode :synchronous)
                   :retry-policy retry-policy
                   :backend-kind (or backend-kind :internal)
                   :backend-ref backend-ref
                   :version version
                   :tags tags
                   :discoverable-p discoverable-p
                   :metadata metadata)))
    (setf (gethash (desktop-task-receiver-key target operation)
                   *desktop-task-manifest-registry*)
          manifest)
    manifest))

(defun find-desktop-task-receiver (target operation)
  (gethash (desktop-task-receiver-key target operation)
           *desktop-task-receiver-registry*))

(defun find-desktop-task-manifest (target operation)
  (gethash (desktop-task-receiver-key target operation)
           *desktop-task-manifest-registry*))

(defun register-desktop-task-planner (target operation planner)
  (setf (gethash (desktop-task-receiver-key target operation)
                 *desktop-task-planner-registry*)
        planner)
  planner)

(defun find-desktop-task-planner (target operation)
  (gethash (desktop-task-receiver-key target operation)
           *desktop-task-planner-registry*))

(defun plan-governed-desktop-task-requests (prompt surface-context surface-actions
                                            &key (discoverable-only-p t))
  (let ((requests '()))
    (dolist (manifest (list-registered-desktop-task-manifests
                       :discoverable-only-p discoverable-only-p)
             (nreverse requests))
      (let ((planner (find-desktop-task-planner (desktop-task-manifest-target manifest)
                                                (desktop-task-manifest-operation manifest))))
        (when planner
          (setf requests
                (nconc (nreverse (copy-list (or (funcall planner
                                                         prompt
                                                         surface-context
                                                         surface-actions)
                                                '())))
                       requests)))))))

(defun register-desktop-task-backend-invoker (backend-kind invoker)
  (setf (gethash backend-kind *desktop-task-backend-invoker-registry*)
        invoker)
  invoker)

(defun find-desktop-task-backend-invoker (backend-kind)
  (gethash backend-kind *desktop-task-backend-invoker-registry*))

(defun register-desktop-task-operation (target operation handler &rest manifest-keys
                                         &key capability description request-schema result-schema
                                           approval-policy execution-mode retry-policy
                                           backend-kind backend-ref version tags
                                           discoverable-p metadata
                                         &allow-other-keys)
  (declare (ignore capability description request-schema result-schema
                   approval-policy execution-mode retry-policy
                   backend-kind backend-ref version tags
                   discoverable-p metadata))
  (register-desktop-task-receiver target operation handler)
  (apply #'register-desktop-task-manifest target operation manifest-keys)
  handler)

(defun register-mcp-desktop-task-operation (target operation backend-ref &rest manifest-keys
                                             &key capability description request-schema result-schema
                                               approval-policy execution-mode retry-policy
                                               version tags (discoverable-p t) metadata
                                             &allow-other-keys)
  (declare (ignore capability description request-schema result-schema
                   approval-policy execution-mode retry-policy
                   version tags discoverable-p metadata))
  (apply #'register-desktop-task-manifest
         target
         operation
         :backend-kind :mcp
         :backend-ref backend-ref
         manifest-keys))

(defun list-registered-desktop-task-manifests (&key discoverable-only-p)
  (let ((manifests
          (loop for manifest being the hash-values of *desktop-task-manifest-registry*
                collect manifest)))
    (sort (if discoverable-only-p
              (remove-if-not #'desktop-task-manifest-discoverable-p manifests)
              manifests)
          #'string<
          :key #'desktop-task-manifest-id)))

(defun desktop-task-manifest-summary (manifest)
  (list :id (desktop-task-manifest-id manifest)
        :target (desktop-task-manifest-target manifest)
        :operation (desktop-task-manifest-operation manifest)
        :capability (desktop-task-manifest-capability manifest)
        :description (desktop-task-manifest-description manifest)
        :request-schema (desktop-task-manifest-request-schema manifest)
        :result-schema (desktop-task-manifest-result-schema manifest)
        :approval-policy (desktop-task-manifest-approval-policy manifest)
        :execution-mode (desktop-task-manifest-execution-mode manifest)
        :retry-policy (desktop-task-manifest-retry-policy manifest)
        :backend-kind (desktop-task-manifest-backend-kind manifest)
        :backend-ref (desktop-task-manifest-backend-ref manifest)
        :version (desktop-task-manifest-version manifest)
        :tags (desktop-task-manifest-tags manifest)
        :discoverable-p (desktop-task-manifest-discoverable-p manifest)
        :metadata (desktop-task-manifest-metadata manifest)))

(defun mcp-server-manifests (server-id)
  (remove-if-not
   (lambda (manifest)
     (and (eq (desktop-task-manifest-backend-kind manifest) :mcp)
          (stringp (desktop-task-manifest-backend-ref manifest))
          (string= server-id (desktop-task-manifest-backend-ref manifest))))
   (list-registered-desktop-task-manifests)))

(defun mcp-server-config-summary (config)
  (let ((manifests (mcp-server-manifests (mcp-server-config-id config))))
    (list :id (mcp-server-config-id config)
          :name (mcp-server-config-name config)
          :transport (mcp-server-config-transport config)
          :command (mcp-server-config-command config)
          :arguments (mcp-server-config-arguments config)
          :environment-variables (mcp-server-config-environment-variables config)
          :working-directory (mcp-server-config-working-directory config)
          :endpoint (mcp-server-config-endpoint config)
          :capabilities (mcp-server-config-capabilities config)
          :retry-policy (mcp-server-config-retry-policy config)
          :health-status (mcp-server-config-health-status config)
          :enabled-p (mcp-server-config-enabled-p config)
          :discoverable-p (mcp-server-config-discoverable-p config)
          :created-at (mcp-server-config-created-at config)
          :updated-at (mcp-server-config-updated-at config)
          :operation-count (length manifests)
          :operations (mapcar #'desktop-task-manifest-summary manifests)
          :metadata (mcp-server-config-metadata config))))

(defun load-desktop-task-mcp-server-registry (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (metadata (environment-metadata active-environment))
         (registry (getf metadata +desktop-task-mcp-server-registry-key+)))
    (if (listp registry) registry '())))

(defun save-desktop-task-mcp-server-registry (registry &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (metadata (copy-list (or (environment-metadata active-environment) '()))))
    (setf (getf metadata +desktop-task-mcp-server-registry-key+) registry
          (environment-metadata active-environment) metadata)
    registry))

(defun list-desktop-task-mcp-server-configs (&optional environment)
  (sort (copy-list (load-desktop-task-mcp-server-registry environment))
        #'string<
        :key #'mcp-server-config-id))

(defun find-desktop-task-mcp-server-config (server-id &optional environment)
  (find server-id
        (load-desktop-task-mcp-server-registry environment)
        :key #'mcp-server-config-id
        :test #'string=))

(defun register-desktop-task-mcp-server-config (&key server-id name transport command arguments
                                                  environment-variables working-directory endpoint
                                                  capabilities retry-policy health-status
                                                  (enabled-p t) (discoverable-p t)
                                                  metadata environment)
  (let* ((registry (load-desktop-task-mcp-server-registry environment))
         (config-id (or server-id (make-mcp-server-config-id name)))
         (existing (find-desktop-task-mcp-server-config config-id environment))
         (created-at (or (and existing (mcp-server-config-created-at existing))
                         (get-universal-time)))
         (config (make-mcp-server-config
                  :id config-id
                  :name (or name config-id)
                  :transport (or transport :stdio)
                  :command command
                  :arguments arguments
                  :environment-variables environment-variables
                  :working-directory working-directory
                  :endpoint endpoint
                  :capabilities capabilities
                  :retry-policy retry-policy
                  :health-status (or health-status :unknown)
                  :enabled-p enabled-p
                  :discoverable-p discoverable-p
                  :metadata metadata
                  :created-at created-at
                  :updated-at (get-universal-time))))
    (save-desktop-task-mcp-server-registry
     (cons config
           (remove config-id registry
                   :key #'mcp-server-config-id
                   :test #'string=))
     environment)
    config))

(defun remove-desktop-task-mcp-server-config (server-id &optional environment)
  (let* ((registry (load-desktop-task-mcp-server-registry environment))
         (existing (find server-id registry
                         :key #'mcp-server-config-id
                         :test #'string=)))
    (unless existing
      (error "Unknown MCP server config ~A" server-id))
    (save-desktop-task-mcp-server-registry
     (remove server-id registry
             :key #'mcp-server-config-id
             :test #'string=)
     environment)
    existing))

(defun make-governed-desktop-task-request (&key requester target operation payload
                                             capability surface-context surface-actions metadata
                                             actor-message)
  (let* ((request-id (make-desktop-task-request-id))
         (created-at (get-universal-time))
         (idempotency-key (format nil "~(~A~)/~(~A~)/~D"
                                  target
                                  operation
                                  (sxhash payload)))
         (request (make-desktop-task-request
                   :id request-id
                   :protocol-version +desktop-task-protocol-version+
                   :requester requester
                   :target target
                   :operation operation
                   :payload payload
                   :capability capability
                   :idempotency-key idempotency-key
                   :surface-context surface-context
                   :surface-actions surface-actions
                   :metadata metadata
                   :created-at created-at)))
    (setf (desktop-task-request-actor-message request)
          (or actor-message
              (make-desktop-task-actor-message
               request
               :capability capability
               :state :queued
               :metadata (list :slice (or (and (listp metadata)
                                               (or (getf metadata :actor-slice)
                                                   (getf metadata :ACTOR-SLICE)))
                                          :context-chat-capability-actor-v1)))))
    request))

(defun ensure-governed-desktop-task-request-state (request &key session-id manifest)
  (let* ((metadata (copy-list (or (desktop-task-request-metadata request) '())))
         (actor-message (desktop-task-request-actor-message request))
         (effective-session-id
           (or session-id
               (getf metadata :session-id)
               (getf metadata :SESSION-ID)
               (and actor-message
                    (or (actor-message-session-id actor-message)
                        (getf (actor-message-metadata actor-message) :session-id)
                        (getf (actor-message-metadata actor-message) :SESSION-ID)))))
         (approval-required-p
           (and manifest
                (desktop-task-manifest-approval-required-p manifest)))
         (effective-approval-id
           (or (getf metadata :approval-id)
               (getf metadata :APPROVAL-ID)
               (and actor-message
                    (or (actor-message-approval-id actor-message)
                        (getf (actor-message-metadata actor-message) :approval-id)
                        (getf (actor-message-metadata actor-message) :APPROVAL-ID)))
               (and approval-required-p
                    (make-governance-approval-id))))
         (effective-pending-action-id
           (or (getf metadata :pending-action-id)
               (getf metadata :PENDING-ACTION-ID)
               (and actor-message
                    (or (actor-message-pending-action-id actor-message)
                        (getf (actor-message-metadata actor-message) :pending-action-id)
                        (getf (actor-message-metadata actor-message) :PENDING-ACTION-ID)))
               (and (eq (desktop-task-request-target request) :editor)
                    (make-pending-action-id :editor))))
         (message-metadata (copy-list (or (and actor-message
                                               (actor-message-metadata actor-message))
                                          '()))))
    (when effective-session-id
      (remf metadata :session-id)
      (setf (getf metadata :session-id) effective-session-id)
      (remf message-metadata :session-id)
      (setf (getf message-metadata :session-id) effective-session-id))
    (when effective-approval-id
      (remf metadata :approval-id)
      (setf (getf metadata :approval-id) effective-approval-id)
      (remf message-metadata :approval-id)
      (setf (getf message-metadata :approval-id) effective-approval-id))
    (when effective-pending-action-id
      (remf metadata :pending-action-id)
      (setf (getf metadata :pending-action-id) effective-pending-action-id)
      (remf message-metadata :pending-action-id)
      (setf (getf message-metadata :pending-action-id) effective-pending-action-id))
    (setf (desktop-task-request-metadata request) metadata
          (desktop-task-request-actor-message request)
          (let* ((rebuilt-message
                   (make-desktop-task-actor-message
                    request
                    :capability (or (and manifest
                                         (desktop-task-manifest-capability manifest))
                                    (desktop-task-request-capability request))
                    :backend-kind (and manifest
                                       (desktop-task-manifest-backend-kind manifest))
                    :backend-ref (and manifest
                                      (desktop-task-manifest-backend-ref manifest))
                    :state (or (and actor-message
                                    (actor-message-state actor-message))
                               :queued)
                    :metadata message-metadata))
                 (message
                   (if actor-message
                       (progn
                         (setf (actor-message-id rebuilt-message)
                               (actor-message-id actor-message)
                               (actor-message-created-at rebuilt-message)
                               (or (actor-message-created-at actor-message)
                                   (actor-message-created-at rebuilt-message))
                               (actor-message-received-at rebuilt-message)
                               (actor-message-received-at actor-message)
                               (actor-message-completed-at rebuilt-message)
                               (actor-message-completed-at actor-message))
                         rebuilt-message)
                       rebuilt-message)))
            (when effective-session-id
              (setf (actor-message-session-id message) effective-session-id))
            (when effective-approval-id
              (setf (actor-message-approval-id message) effective-approval-id))
            (when effective-pending-action-id
              (setf (actor-message-pending-action-id message) effective-pending-action-id))
            (setf (actor-message-metadata message) message-metadata)
            message))
    request))

(defun make-desktop-task-request-from-record (record)
  (make-desktop-task-request
   :id (or (desktop-task-record-request-id record)
           (make-desktop-task-request-id))
   :protocol-version (desktop-task-record-protocol-version record)
   :requester (desktop-task-record-requester record)
   :actor-message (desktop-task-record-actor-message record)
   :target (desktop-task-record-target record)
   :operation (desktop-task-record-operation record)
   :payload (desktop-task-record-payload record)
   :capability (desktop-task-record-capability record)
   :idempotency-key (desktop-task-record-idempotency-key record)
   :surface-context nil
   :surface-actions nil
   :metadata (desktop-task-record-request-metadata record)
   :created-at (or (desktop-task-record-created-at record)
                   (get-universal-time))))

(defun desktop-task-retry-policy-max-attempts (retry-policy)
  (or (and (listp retry-policy)
           (or (getf retry-policy :max-attempts)
               (getf retry-policy :MAX-ATTEMPTS)))
      1))

(defun desktop-task-retry-policy-value (retry-policy key)
  (and (listp retry-policy)
       (or (getf retry-policy key)
           (getf retry-policy (intern (string-upcase (string key)) "KEYWORD")))))

(defun desktop-task-retry-policy-enabled-p (retry-policy)
  (let ((flag (desktop-task-retry-policy-value retry-policy :retryable-p)))
    (if (null flag)
        (> (desktop-task-retry-policy-max-attempts retry-policy) 1)
        flag)))

(defun desktop-task-retry-policy-backoff-seconds (retry-policy)
  (or (desktop-task-retry-policy-value retry-policy :backoff-seconds)
      0))

(defun desktop-task-retry-policy-classification (retry-policy)
  (or (desktop-task-retry-policy-value retry-policy :failure-classification)
      :transient))

(defun desktop-task-manifest-approval-required-p (manifest)
  (eq (and manifest
           (desktop-task-manifest-approval-policy manifest))
      :explicit))

(defun make-desktop-task-record-for-request (request manifest &key session-id thread-id turn-id conversation-operation-id metadata)
  (make-desktop-task-record
   :id (make-desktop-task-record-id)
   :protocol-version (desktop-task-request-protocol-version request)
   :request-id (desktop-task-request-id request)
   :requester (desktop-task-request-requester request)
   :actor-message (transition-actor-message
                   (or (desktop-task-request-actor-message request)
                       (make-desktop-task-actor-message
                        request
                        :capability (or (and manifest
                                             (desktop-task-manifest-capability manifest))
                                        (desktop-task-request-capability request))
                        :backend-kind (and manifest
                                           (desktop-task-manifest-backend-kind manifest))
                        :backend-ref (and manifest
                                          (desktop-task-manifest-backend-ref manifest))))
                   :governance-review
                   :metadata (list :manifest-id (and manifest
                                                    (desktop-task-manifest-id manifest))
                                   :session-id session-id
                                   :slice (or (getf (desktop-task-request-metadata request) :actor-slice)
                                              (getf (desktop-task-request-metadata request) :ACTOR-SLICE))
                                   :pending-action-id (or (getf (desktop-task-request-metadata request) :pending-action-id)
                                                          (getf (desktop-task-request-metadata request) :PENDING-ACTION-ID))))
   :target (desktop-task-request-target request)
   :operation (desktop-task-request-operation request)
   :capability (or (desktop-task-manifest-capability manifest)
                   (desktop-task-request-capability request))
   :backend-kind (or (and manifest (desktop-task-manifest-backend-kind manifest))
                     :internal)
   :backend-ref (and manifest (desktop-task-manifest-backend-ref manifest))
   :status :requested
   :governance-status :pending-assessment
   :approval-status :not-required
   :retry-policy (and manifest (desktop-task-manifest-retry-policy manifest))
   :retry-count 0
   :max-attempts (desktop-task-retry-policy-max-attempts
                  (and manifest (desktop-task-manifest-retry-policy manifest)))
   :idempotency-key (desktop-task-request-idempotency-key request)
   :payload (desktop-task-request-payload request)
   :request-metadata (append (desktop-task-request-metadata request)
                             (when manifest
                               (list :manifest-id (desktop-task-manifest-id manifest)
                                     :manifest-version (desktop-task-manifest-version manifest))))
   :thread-id thread-id
   :turn-id turn-id
   :conversation-operation-id conversation-operation-id
   :created-at (get-universal-time)
   :approved-at nil
   :started-at nil
   :completed-at nil
   :last-error nil
   :resolution nil
   :result nil
   :metadata metadata))

(defun desktop-task-record-summary (record)
  (let ((resolution (desktop-task-record-resolution record))
        (result (desktop-task-record-result record))
        (last-error (desktop-task-record-last-error record))
        (request-metadata (desktop-task-record-request-metadata record))
        (actor-message (desktop-task-record-actor-message record)))
    (list :id (desktop-task-record-id record)
          :protocol-version (desktop-task-record-protocol-version record)
          :request-id (desktop-task-record-request-id record)
          :requester (desktop-task-record-requester record)
          :session-id (or (and (listp request-metadata)
                               (or (getf request-metadata :session-id)
                                   (getf request-metadata :SESSION-ID)))
                          (and actor-message
                               (or (getf (actor-message-metadata actor-message) :session-id)
                                   (getf (actor-message-metadata actor-message) :SESSION-ID))))
          :approval-id (or (and (listp request-metadata)
                                (or (getf request-metadata :approval-id)
                                    (getf request-metadata :APPROVAL-ID)))
                           (and actor-message
                                (or (getf (actor-message-metadata actor-message) :approval-id)
                                    (getf (actor-message-metadata actor-message) :APPROVAL-ID))))
          :actor-message (actor-message-summary actor-message)
          :sender-actor (and actor-message
                             (actor-address-summary (actor-message-sender actor-message)))
          :receiver-actor (and actor-message
                               (actor-address-summary (actor-message-receiver actor-message)))
          :reply-to-actor (and actor-message
                               (actor-address-summary (actor-message-reply-to actor-message)))
          :originator-actor (and actor-message
                                 (actor-address-summary (actor-message-originator actor-message)))
          :actor-slice (or (and actor-message
                                (or (actor-message-actor-slice actor-message)
                                    (getf (actor-message-metadata actor-message) :slice)))
                           (and (listp request-metadata)
                                (or (getf request-metadata :actor-slice)
                                    (getf request-metadata :ACTOR-SLICE))))
          :pending-action-id (or (and actor-message
                                      (or (actor-message-pending-action-id actor-message)
                                          (getf (actor-message-metadata actor-message) :pending-action-id)
                                          (getf (actor-message-metadata actor-message) :PENDING-ACTION-ID)))
                                 (and (listp request-metadata)
                                      (or (getf request-metadata :pending-action-id)
                                          (getf request-metadata :PENDING-ACTION-ID))))
          :target (desktop-task-record-target record)
          :operation (desktop-task-record-operation record)
          :capability (desktop-task-record-capability record)
          :backend-kind (desktop-task-record-backend-kind record)
          :backend-ref (desktop-task-record-backend-ref record)
          :status (desktop-task-record-status record)
          :governance-status (desktop-task-record-governance-status record)
          :approval-status (desktop-task-record-approval-status record)
          :retry-policy (desktop-task-record-retry-policy record)
          :retry-count (desktop-task-record-retry-count record)
          :max-attempts (desktop-task-record-max-attempts record)
          :retryable-p (desktop-task-retryable-p record)
          :idempotency-key (desktop-task-record-idempotency-key record)
          :thread-id (desktop-task-record-thread-id record)
          :turn-id (desktop-task-record-turn-id record)
          :conversation-operation-id (desktop-task-record-conversation-operation-id record)
          :created-at (desktop-task-record-created-at record)
          :approved-at (desktop-task-record-approved-at record)
          :started-at (desktop-task-record-started-at record)
          :completed-at (desktop-task-record-completed-at record)
          :last-error (and (listp last-error)
                           (list :summary (or (getf last-error :summary)
                                              (getf last-error :SUMMARY)
                                              (getf last-error :error)
                                              (getf last-error :ERROR))
                                 :status (or (getf last-error :status)
                                             (getf last-error :STATUS)
                                             (desktop-task-record-status record))
                                 :metadata (or (getf last-error :metadata)
                                               (getf last-error :METADATA))))
          :resolution (and resolution
                           (desktop-task-resolution-summary-data resolution))
          :result (and (listp result)
                       (list :summary (or (getf result :summary)
                                          (getf result :SUMMARY)
                                          (getf result :message)
                                          (getf result :MESSAGE))
                             :status (or (getf result :status)
                                         (getf result :STATUS)
                                         (desktop-task-record-status record))
                             :request-id (or (getf result :request-id)
                                             (getf result :REQUEST-ID)
                                             (desktop-task-record-request-id record))
                             :target (or (getf result :target)
                                         (getf result :TARGET)
                                         (desktop-task-record-target record))
                             :operation (or (getf result :operation)
                                            (getf result :OPERATION)
                                            (desktop-task-record-operation record))
                             :metadata (or (getf result :metadata)
                                           (getf result :METADATA))))
          :request-metadata request-metadata
          :metadata (desktop-task-record-metadata record))))

(defun desktop-task-record-events (session record)
  (let ((record-id (desktop-task-record-id record)))
    (remove-if-not (lambda (event)
                     (and (event-entity-id event)
                          (string= record-id (event-entity-id event))))
                   (agent-session-events session))))

(defun desktop-task-audit-event-p (event)
  (member (event-kind event)
          '(:desktop-task-record-transition
            :desktop-task-governance-check
            :desktop-task-invocation
            :desktop-task-invocation-result
            :desktop-task-invocation-failed)
          :test #'eq))

(defun desktop-task-record-event-summary (event)
  (list :id (event-id event)
        :timestamp (event-timestamp event)
        :kind (event-kind event)
        :family (event-family event)
        :entity-id (event-entity-id event)
        :thread-id (event-thread-id event)
        :turn-id (event-turn-id event)
        :visibility (event-visibility event)
        :metadata (event-metadata event)
        :payload (event-payload event)))

(defun desktop-task-record-audit-summary (session record)
  (let* ((events (desktop-task-record-events session record))
         (audit-events (remove-if-not #'desktop-task-audit-event-p events)))
    (list :event-count (length audit-events)
          :recent-events (mapcar #'desktop-task-record-event-summary
                                 (last audit-events (min 8 (length audit-events))))
          :transition-kinds (remove-duplicates
                             (remove nil
                                     (mapcar (lambda (event)
                                               (and (eq (event-kind event)
                                                        :desktop-task-record-transition)
                                                    (getf (event-payload event)
                                                          :transition)))
                                             audit-events))
                             :test #'eq)
          :invoked-p (not (null (find-if (lambda (event)
                                           (eq (event-kind event)
                                               :desktop-task-invocation))
                                         audit-events)))
          :completed-p (not (null (find-if (lambda (event)
                                             (eq (event-kind event)
                                                 :desktop-task-invocation-result))
                                           audit-events)))
          :failed-p (not (null (find-if (lambda (event)
                                          (eq (event-kind event)
                                              :desktop-task-invocation-failed))
                                        audit-events))))))

(defun desktop-task-record-summary-with-audit (session record)
  (append (desktop-task-record-summary record)
          (list :audit (desktop-task-record-audit-summary session record))))

(defun register-desktop-task-record (session record)
  (multiple-value-bind (tasks tail)
      (append-linked-item (agent-session-desktop-tasks session)
                          (agent-session-desktop-tasks-tail session)
                          record)
    (setf (agent-session-desktop-tasks session) tasks
          (agent-session-desktop-tasks-tail session) tail))
  (when (fboundp 'refresh-session-actor-mailboxes)
    (refresh-session-actor-mailboxes session))
  (refresh-bound-environment-agent-state session)
  (append-actor-message-transport-event session :sent record)
  (append-actor-message-transport-event session :delivered record
                                        :metadata '(:mailbox :inbox
                                                    :delivery-kind :receiver-inbox))
  record)

(defun list-desktop-task-records (session)
  (agent-session-desktop-tasks session))

(defun find-desktop-task-record (session task-record-id)
  (find task-record-id (agent-session-desktop-tasks session)
        :key #'desktop-task-record-id :test #'string=))

(defun find-desktop-task-record-by-request-id (session request-id)
  (find request-id (agent-session-desktop-tasks session)
        :key #'desktop-task-record-request-id :test #'string=))

(defun update-desktop-task-record (session record &key status governance-status approval-status
                                                  approved-at started-at completed-at
                                                  last-error resolution result metadata
                                                  actor-message
                                                  increment-retry-p)
  (when status
    (setf (desktop-task-record-status record) status))
  (when governance-status
    (setf (desktop-task-record-governance-status record) governance-status))
  (when approval-status
    (setf (desktop-task-record-approval-status record) approval-status))
  (when approved-at
    (setf (desktop-task-record-approved-at record) approved-at))
  (when started-at
    (setf (desktop-task-record-started-at record) started-at))
  (when completed-at
    (setf (desktop-task-record-completed-at record) completed-at))
  (when last-error
    (setf (desktop-task-record-last-error record) last-error))
  (when resolution
    (setf (desktop-task-record-resolution record) resolution))
  (when result
    (setf (desktop-task-record-result record) result))
  (when actor-message
    (setf (desktop-task-record-actor-message record) actor-message))
  (when metadata
    (setf (desktop-task-record-metadata record)
          (append (desktop-task-record-metadata record) metadata)))
  (when increment-retry-p
    (incf (desktop-task-record-retry-count record)))
  (when (fboundp 'refresh-session-actor-mailboxes)
    (refresh-session-actor-mailboxes session))
  (refresh-bound-environment-agent-state session)
  record)

(defun append-desktop-task-record-transition-event (session transition record)
  (append-session-event session
                        :desktop-task-record-transition
                        (append (desktop-task-record-summary record)
                                (list :transition transition))
                        :family :assistant
                        :entity-id (desktop-task-record-id record)
                        :thread-id (desktop-task-record-thread-id record)
                        :turn-id (desktop-task-record-turn-id record)
                        :visibility :operator))

(defun desktop-task-retryable-p (record)
  (and (desktop-task-retry-policy-enabled-p (desktop-task-record-retry-policy record))
       (> (desktop-task-record-max-attempts record) 1)
       (< (desktop-task-record-retry-count record)
          (desktop-task-record-max-attempts record))))

(defun desktop-task-record-policy-id (record)
  (or (getf (desktop-task-record-request-metadata record) :policy-id)
      (getf (desktop-task-record-request-metadata record) :POLICY-ID)
      (desktop-task-record-capability record)))

(defun desktop-task-record-session-id (record)
  (or (getf (desktop-task-record-request-metadata record) :session-id)
      (getf (desktop-task-record-request-metadata record) :SESSION-ID)
      (let ((actor-message (desktop-task-record-actor-message record)))
        (and actor-message
             (or (actor-message-session-id actor-message)
                 (getf (actor-message-metadata actor-message) :session-id)
                 (getf (actor-message-metadata actor-message) :SESSION-ID))))))

(defun desktop-task-record-approval-id (record)
  (or (getf (desktop-task-record-request-metadata record) :approval-id)
      (getf (desktop-task-record-request-metadata record) :APPROVAL-ID)
      (let ((actor-message (desktop-task-record-actor-message record)))
        (and actor-message
             (or (actor-message-approval-id actor-message)
                 (getf (actor-message-metadata actor-message) :approval-id)
                 (getf (actor-message-metadata actor-message) :APPROVAL-ID))))))

(defun mark-desktop-task-record-awaiting-approval (session record &key policy-id)
  (let* ((approval-id (or (desktop-task-record-approval-id record)
                          (make-governance-approval-id)))
         (_request-metadata
           (setf (desktop-task-record-request-metadata record)
                 (append (desktop-task-record-request-metadata record)
                         (when policy-id (list :policy-id policy-id))
                         (list :approval-id approval-id
                               :session-id (agent-session-id session)))))
         (updated
          (update-desktop-task-record
           session
           record
           :status :awaiting-approval
           :governance-status :awaiting-approval
           :approval-status :awaiting-approval
           :metadata (append (when policy-id (list :policy-id policy-id))
                             (list :approval-id approval-id
                                   :session-id (agent-session-id session))
                             '(:approval-required-p t))
           :actor-message (transition-actor-message
                           (desktop-task-record-actor-message record)
                           :awaiting-approval
                           :metadata (list :approval-id approval-id
                                           :session-id (agent-session-id session)
                                           :governance-actor-id
                                           (actor-address-id (make-governance-actor-address
                                                              :session-id (agent-session-id session))))))))
    (append-actor-message-transport-event session :governance-review updated
                                          :metadata (append (when policy-id
                                                              (list :policy-id policy-id))
                                                            (list :approval-id approval-id
                                                                  :session-id (agent-session-id session))))
    (append-actor-message-transport-event session :governance-requested updated
                                          :metadata (append (when policy-id
                                                              (list :policy-id policy-id))
                                                            (list :approval-id approval-id
                                                                  :session-id (agent-session-id session)
                                                                  :governance-actor
                                                                  (actor-address-summary
                                                                   (make-governance-actor-address)))))
    (append-desktop-task-record-transition-event session :awaiting-approval updated)
    updated))

(defun mark-desktop-task-record-approved (session record &key approved-at)
  (let ((updated
          (update-desktop-task-record
           session
           record
           :governance-status :approved
           :approval-status :approved
           :approved-at (or approved-at (get-universal-time))
           :metadata '(:approval-required-p t :approval-granted-p t)
           :actor-message (transition-actor-message
                           (desktop-task-record-actor-message record)
                           :approved
                           :metadata (list :approval-id (desktop-task-record-approval-id record)
                                           :session-id (agent-session-id session)
                                           :governance-authorized-p t)))))
    (append-actor-message-transport-event session :governance-authorized updated
                                          :metadata (list :approval-id (desktop-task-record-approval-id record)
                                                          :session-id (agent-session-id session)
                                                          :governance-actor
                                                          (actor-address-summary
                                                           (make-governance-actor-address))))
    (append-desktop-task-record-transition-event session :approved updated)
    updated))

(defun mark-desktop-task-record-executing (session record &key started-at)
  (let ((updated
          (update-desktop-task-record
           session
           record
           :status :executing
           :governance-status :approved
           :started-at (or started-at (get-universal-time))
           :actor-message
           (transition-actor-message
           (desktop-task-record-actor-message record)
           :executing
           :received-at (or started-at (get-universal-time))))))
    (append-actor-message-transport-event session :dequeued updated
                                          :metadata '(:mailbox :inbox
                                                      :dequeue-kind :execute))
    (append-desktop-task-record-transition-event session :executing updated)
    updated))

(defun mark-desktop-task-record-retrying (session record &key started-at reason)
  (let ((updated
          (update-desktop-task-record
           session
           record
           :status :retrying
           :governance-status :approved
           :started-at (or started-at (get-universal-time))
           :metadata (append (when reason (list :retry-reason reason))
                             (list :retryable-p t
                                   :backoff-seconds (desktop-task-retry-policy-backoff-seconds
                                                     (desktop-task-record-retry-policy record))
                                   :failure-classification (desktop-task-retry-policy-classification
                                                            (desktop-task-record-retry-policy record))))
           :actor-message
           (transition-actor-message
           (desktop-task-record-actor-message record)
           :executing
           :received-at (or started-at (get-universal-time))
           :metadata (when reason
                       (list :retry-reason reason))))))
    (append-actor-message-transport-event session :dequeued updated
                                          :reason reason
                                          :metadata '(:mailbox :inbox
                                                      :dequeue-kind :retry))
    (append-desktop-task-record-transition-event session :retrying updated)
    updated))

(defun mark-desktop-task-record-completed (session record result &key completed-at)
  (let ((updated
          (update-desktop-task-record
           session
           record
           :status :completed
           :governance-status :approved
           :completed-at (or completed-at (get-universal-time))
           :result result
           :actor-message
           (transition-actor-message
           (desktop-task-record-actor-message record)
           :completed
           :completed-at (or completed-at (get-universal-time))))))
    (append-actor-message-transport-event session :completed updated)
    (append-desktop-task-record-transition-event session :completed updated)
    updated))

(defun mark-desktop-task-record-failed (session record error &key retryable-p completed-at)
  (let* ((effective-retryable-p (and retryable-p
                                     (desktop-task-retryable-p record)))
         (backoff-seconds (and effective-retryable-p
                               (desktop-task-retry-policy-backoff-seconds
                                (desktop-task-record-retry-policy record))))
         (failure-classification
           (or (and (listp error)
                    (or (getf error :failure-classification)
                        (getf error :FAILURE-CLASSIFICATION)))
               (desktop-task-retry-policy-classification
                (desktop-task-record-retry-policy record)))))
    (let* ((dead-letter-p (eq failure-classification :undeliverable))
           (updated
            (update-desktop-task-record
             session
             record
             :status (if effective-retryable-p :retryable-failure :failed)
             :completed-at (or completed-at (get-universal-time))
             :last-error error
             :increment-retry-p effective-retryable-p
             :metadata (append (list :retryable-p effective-retryable-p
                                     :failure-classification failure-classification)
                               (when backoff-seconds
                                 (list :backoff-seconds backoff-seconds)))
             :actor-message
             (if dead-letter-p
                 (dead-letter-actor-message
                  (desktop-task-record-actor-message record)
                  :reason (or (and (listp error)
                                   (or (getf error :summary)
                                       (getf error :SUMMARY)
                                       (getf error :error)
                                       (getf error :ERROR)))
                              "Undeliverable actor message.")
                  :completed-at (or completed-at (get-universal-time))
                  :metadata (list :retryable-p effective-retryable-p))
                 (transition-actor-message
                  (desktop-task-record-actor-message record)
                  :failed
                  :completed-at (or completed-at (get-universal-time))
                  :metadata (list :retryable-p effective-retryable-p))))))
      (append-actor-message-transport-event
       session
       (if dead-letter-p :dead-lettered :failed)
       updated
       :reason (or (and (listp error)
                        (or (getf error :summary)
                            (getf error :SUMMARY)
                            (getf error :error)
                            (getf error :ERROR)))
                   nil))
      (append-desktop-task-record-transition-event
       session
       (if effective-retryable-p :retryable-failure :failed)
       updated)
      updated)))

(defun mark-desktop-task-record-canceled (session record &key reason completed-at)
  (let ((updated
          (update-desktop-task-record
           session
           record
           :status :canceled
           :completed-at (or completed-at (get-universal-time))
           :last-error (when reason
                         (list :summary reason
                               :failure-classification :canceled))
           :metadata (append (when reason
                               (list :cancel-reason reason))
                             '(:canceled-p t))
           :actor-message
           (transition-actor-message
           (desktop-task-record-actor-message record)
           :canceled
           :completed-at (or completed-at (get-universal-time))
           :metadata (when reason
                       (list :cancel-reason reason))))))
    (append-actor-message-transport-event session :canceled updated :reason reason)
    (append-desktop-task-record-transition-event session :canceled updated)
    updated))

(defun desktop-task-records-for-turn (session turn-id)
  (remove-if-not (lambda (record)
                   (and (desktop-task-record-turn-id record)
                        (string= turn-id (desktop-task-record-turn-id record))))
                 (agent-session-desktop-tasks session)))

(defun desktop-task-records-awaiting-policy (session policy-id)
  (remove-if-not (lambda (record)
                   (and (eq (desktop-task-record-approval-status record) :awaiting-approval)
                        (eql policy-id (desktop-task-record-policy-id record))))
                 (agent-session-desktop-tasks session)))

(defun desktop-task-records-awaiting-approval-for-turn (session turn-id)
  (remove-if-not (lambda (record)
                   (and (desktop-task-record-turn-id record)
                        (string= turn-id (desktop-task-record-turn-id record))
                        (eq (desktop-task-record-approval-status record)
                            :awaiting-approval)))
                 (agent-session-desktop-tasks session)))

(defun desktop-task-records-awaiting-approval (session)
  (remove-if-not (lambda (record)
                   (eq (desktop-task-record-approval-status record)
                       :awaiting-approval))
                 (agent-session-desktop-tasks session)))

(defun latest-awaiting-approval-desktop-task-records (session)
  (let* ((records (desktop-task-records-awaiting-approval session))
         (latest (car (sort (copy-list records)
                            #'>
                            :key (lambda (record)
                                   (or (desktop-task-record-created-at record)
                                       0))))))
    (when latest
      (let ((turn-id (desktop-task-record-turn-id latest)))
        (if turn-id
            (desktop-task-records-awaiting-approval-for-turn session turn-id)
            (list latest))))))

(defun make-desktop-task-resolution-summary (request summary actions &key metadata executor)
  (make-desktop-task-resolution
   :request-id (desktop-task-request-id request)
   :target (desktop-task-request-target request)
   :operation (desktop-task-request-operation request)
   :summary summary
   :actions actions
   :executor executor
   :metadata metadata))

(defun make-desktop-task-resolution-native (request summary executor &key metadata)
  (make-desktop-task-resolution-summary request summary '() :metadata metadata :executor executor))

(defun desktop-task-resolution-native-executor-p (resolution)
  (not (null (desktop-task-resolution-executor resolution))))

(defun desktop-task-resolution-action-approval-required-p (resolution)
  (some #'assistant-action-requires-approval-p
        (desktop-task-resolution-actions resolution)))

(defun desktop-task-resolution-summary-data (resolution)
  (list :request-id (desktop-task-resolution-request-id resolution)
        :target (desktop-task-resolution-target resolution)
        :operation (desktop-task-resolution-operation resolution)
        :summary (desktop-task-resolution-summary resolution)
        :action-count (length (desktop-task-resolution-actions resolution))
        :native-executor-p (desktop-task-resolution-native-executor-p resolution)
        :metadata (desktop-task-resolution-metadata resolution)))

(defun desktop-task-result-summary-data (result)
  (list :request-id (desktop-task-result-request-id result)
        :target (desktop-task-result-target result)
        :operation (desktop-task-result-operation result)
        :status (desktop-task-result-status result)
        :summary (desktop-task-result-summary result)
        :action-result-count (length (desktop-task-result-action-results result))
        :metadata (desktop-task-result-metadata result)))

(defun desktop-task-record-result-summary-text (record)
  (or (and (listp (desktop-task-record-result record))
           (or (getf (desktop-task-record-result record) :summary)
               (getf (desktop-task-record-result record) :SUMMARY)
               (getf (desktop-task-record-result record) :message)
               (getf (desktop-task-record-result record) :MESSAGE)))
      (and (listp (desktop-task-record-last-error record))
           (or (getf (desktop-task-record-last-error record) :summary)
               (getf (desktop-task-record-last-error record) :SUMMARY)
               (getf (desktop-task-record-last-error record) :error)
               (getf (desktop-task-record-last-error record) :ERROR)))))

(defun make-desktop-task-record-completed-result (request resolution invocation-result)
  (list :request-id (desktop-task-request-id request)
        :target (desktop-task-request-target request)
        :operation (desktop-task-request-operation request)
        :status :completed
        :summary (desktop-task-invocation-result-summary
                  invocation-result
                  (desktop-task-resolution-summary resolution))
        :invocation-result invocation-result
        :actor-message (actor-message-summary
                        (desktop-task-request-actor-message request))
        :metadata (append (copy-list (or (desktop-task-resolution-metadata resolution) '()))
                          (list :native-executor-p
                                (desktop-task-resolution-native-executor-p resolution)))))

(defun desktop-task-record-canonical-result-summary (record)
  (let ((result (desktop-task-record-result record))
        (last-error (desktop-task-record-last-error record)))
    (list :task-record-id (desktop-task-record-id record)
          :request-id (desktop-task-record-request-id record)
          :target (desktop-task-record-target record)
          :operation (desktop-task-record-operation record)
          :status (desktop-task-record-status record)
          :governance-status (desktop-task-record-governance-status record)
          :approval-status (desktop-task-record-approval-status record)
          :summary (or (and (listp result)
                            (or (getf result :summary)
                                (getf result :SUMMARY)
                                (getf result :message)
                                (getf result :MESSAGE)))
                       (and (listp last-error)
                            (or (getf last-error :summary)
                                (getf last-error :SUMMARY)
                                (getf last-error :error)
                                (getf last-error :ERROR)))
                       (case (desktop-task-record-status record)
                         (:awaiting-approval "Awaiting approval before execution.")
                         (:completed "Completed the requested desktop task.")
                         ((:failed :retryable-failure) "The requested desktop task failed.")
                         (otherwise nil)))
          :retryable-p (desktop-task-retryable-p record)
          :retry-count (desktop-task-record-retry-count record)
          :max-attempts (desktop-task-record-max-attempts record)
          :actor-message (actor-message-summary
                          (desktop-task-record-actor-message record))
          :result result
          :last-error last-error
          :metadata (desktop-task-record-metadata record))))

(defun desktop-task-invocation-result-summary (result fallback-summary)
  (or (and (listp result)
           (or (getf result :summary)
               (getf result :SUMMARY)
               (getf result :message)
               (getf result :MESSAGE)))
      fallback-summary))

(defun desktop-task-invocation-action-results (result)
  (copy-list
   (or (and (listp result)
            (or (getf result :action-results)
                (getf result :ACTION-RESULTS)))
       '())))

(defun desktop-task-request-approval-required-p (request manifest resolution)
  (declare (ignore request))
  (or (desktop-task-manifest-approval-required-p manifest)
      (desktop-task-resolution-action-approval-required-p resolution)))

(defun make-manifest-default-desktop-task-resolution (request manifest)
  (make-desktop-task-resolution-summary
   request
   (or (desktop-task-manifest-description manifest)
       (format nil "Invoke ~A on ~A."
               (desktop-task-request-operation request)
               (desktop-task-request-target request)))
   '()
   :metadata (append (when manifest
                       (list :manifest-id (desktop-task-manifest-id manifest)
                             :backend-kind (desktop-task-manifest-backend-kind manifest)
                             :backend-ref (desktop-task-manifest-backend-ref manifest)))
                     '(:generic-resolution-p t))))

(defun ensure-desktop-task-resolution (request resolved)
  (cond
    ((desktop-task-resolution-p resolved) resolved)
    ((listp resolved)
     (make-desktop-task-resolution-summary
      request
      (or (getf resolved :summary)
          (getf resolved :SUMMARY)
          "Resolved desktop task request.")
      (copy-list (or (getf resolved :actions)
                     (getf resolved :ACTIONS)
                     '()))
      :executor (or (getf resolved :executor)
                    (getf resolved :EXECUTOR))
      :metadata (or (getf resolved :metadata)
                    (getf resolved :METADATA))))
    (t
     (error "Desktop task receiver returned unsupported resolution ~S" resolved))))

(defun desktop-task-request-summary (request)
  (list :id (desktop-task-request-id request)
        :requester (desktop-task-request-requester request)
        :actor-message (actor-message-summary
                        (desktop-task-request-actor-message request))
        :target (desktop-task-request-target request)
        :operation (desktop-task-request-operation request)
        :capability (desktop-task-request-capability request)
        :payload (desktop-task-request-payload request)
        :metadata (desktop-task-request-metadata request)
        :created-at (desktop-task-request-created-at request)))

(defun desktop-task-manifest-for-request (request)
  (or (find-desktop-task-manifest (desktop-task-request-target request)
                                  (desktop-task-request-operation request))
      (error "No desktop task manifest is registered for ~S/~S"
             (desktop-task-request-target request)
             (desktop-task-request-operation request))))

(defun desktop-task-request-policy-id (request manifest)
  (or (desktop-task-request-capability request)
      (and manifest (desktop-task-manifest-capability manifest))
      (getf (desktop-task-request-metadata request) :policy-id)
      (getf (desktop-task-request-metadata request) :POLICY-ID)))

(defun desktop-task-request-record (session request)
  (and session
       (find-desktop-task-record-by-request-id session
                                               (desktop-task-request-id request))))

(defun append-desktop-task-audit-event (session event-kind request payload)
  (let ((record (desktop-task-request-record session request)))
    (append-session-event session
                          event-kind
                          payload
                          :family :assistant
                          :entity-id (and record (desktop-task-record-id record))
                          :thread-id (and record (desktop-task-record-thread-id record))
                          :turn-id (and record (desktop-task-record-turn-id record))
                          :visibility :operator)))

(defun resolve-governed-desktop-task-request (request session)
  (let* ((manifest (find-desktop-task-manifest (desktop-task-request-target request)
                                               (desktop-task-request-operation request)))
         (handler (find-desktop-task-receiver (desktop-task-request-target request)
                                              (desktop-task-request-operation request))))
    (cond
      (handler
       (ensure-desktop-task-resolution request
                                       (funcall handler request session)))
      ((and manifest
            (eq (desktop-task-manifest-backend-kind manifest) :mcp))
       (make-manifest-default-desktop-task-resolution request manifest))
      (t
       (error "No desktop task receiver is registered for ~S/~S"
              (desktop-task-request-target request)
              (desktop-task-request-operation request))))))

(defun execute-governed-desktop-task-resolution (resolution session request manifest)
  (flet ((perform-execution ()
           (cond
             ((desktop-task-resolution-native-executor-p resolution)
              (funcall (desktop-task-resolution-executor resolution) session))
             (t
              (let ((invoker (find-desktop-task-backend-invoker
                              (desktop-task-manifest-backend-kind manifest))))
                (unless invoker
                  (error "No backend invoker is registered for desktop task backend ~S (~S/~S)."
                         (desktop-task-manifest-backend-kind manifest)
                         (desktop-task-request-target request)
                         (desktop-task-request-operation request)))
                (funcall invoker manifest request resolution session))))))
    (let ((actor-worker-dispatcher
            (and (fboundp 'call-with-actor-worker-for-request)
                 (symbol-function 'call-with-actor-worker-for-request))))
      (if actor-worker-dispatcher
          (funcall actor-worker-dispatcher session request #'perform-execution)
          (perform-execution)))))

(defun invoke-governed-desktop-task-request (request session &key resolution manifest)
  (let* ((effective-manifest (or manifest
                                 (desktop-task-manifest-for-request request)))
         (effective-resolution (or resolution
                                   (resolve-governed-desktop-task-request request session)))
         (policy-id (desktop-task-request-policy-id request effective-manifest))
         (approval-required-p (desktop-task-request-approval-required-p
                               request
                               effective-manifest
                               effective-resolution)))
    (append-desktop-task-audit-event
     session
     :desktop-task-governance-check
     request
     (list :request (desktop-task-request-summary request)
           :manifest (desktop-task-manifest-summary effective-manifest)
           :resolution (desktop-task-resolution-summary-data effective-resolution)
           :policy-id policy-id
           :approval-required-p approval-required-p))
    (when approval-required-p
      (unless policy-id
        (error "Desktop task ~S/~S requires approval, but no policy id is available."
               (desktop-task-request-target request)
               (desktop-task-request-operation request)))
      (ensure-policy-approved session policy-id))
    (append-desktop-task-audit-event
     session
     :desktop-task-invocation
     request
     (list :request (desktop-task-request-summary request)
           :manifest (desktop-task-manifest-summary effective-manifest)
           :resolution (desktop-task-resolution-summary-data effective-resolution)
           :policy-id policy-id
           :approval-required-p approval-required-p))
    (handler-case
        (let ((result (execute-governed-desktop-task-resolution
                       effective-resolution
                       session
                       request
                       effective-manifest)))
          (append-desktop-task-audit-event
           session
           :desktop-task-invocation-result
           request
           (list :request-id (desktop-task-request-id request)
                 :target (desktop-task-request-target request)
                 :operation (desktop-task-request-operation request)
                 :policy-id policy-id
                 :approval-required-p approval-required-p
                 :summary (desktop-task-invocation-result-summary
                           result
                           (desktop-task-resolution-summary effective-resolution))
                 :status (or (and (listp result)
                                  (or (getf result :status)
                                      (getf result :STATUS)))
                             :completed)))
          (list :manifest effective-manifest
                :resolution effective-resolution
                :result result))
      (error (condition)
        (append-desktop-task-audit-event
         session
         :desktop-task-invocation-failed
         request
         (list :request-id (desktop-task-request-id request)
               :target (desktop-task-request-target request)
               :operation (desktop-task-request-operation request)
               :policy-id policy-id
               :approval-required-p approval-required-p
               :error (princ-to-string condition)
               :failure-classification :execution))
        (error condition)))))
