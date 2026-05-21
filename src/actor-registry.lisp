(in-package #:sbcl-agent.system.registry)

(defun actor-address-equal-p (left right)
  (and left
       right
       (string= (sbcl-agent::actor-address-id left)
                (sbcl-agent::actor-address-id right))))

(defun actor-definition-address (definition)
  (sbcl-agent::make-actor-address
   :id (sbcl-agent::actor-definition-id definition)
   :kind :internal
   :role (sbcl-agent::actor-definition-role definition)
   :display-name (sbcl-agent::actor-definition-display-name definition)
   :metadata (copy-tree (or (sbcl-agent::actor-definition-metadata definition) '()))))

(defun make-default-actor-definition (role &key scope display-name parent-actor-id
                                             capabilities llm-profile
                                             (allocation-type :singleton)
                                             shared-inbox-id
                                             pool-size
                                             consumption-policy
                                             (handler-mode :serial)
                                             (supervision-strategy :one-for-one)
                                             (max-restarts 3)
                                             (restart-window-seconds 60)
                                             (on-failure :escalate)
                                             escalation-target
                                             (execution-model :thread-pool-worker)
                                             thread-name
                                             (mailbox-mode :serial-per-actor)
                                             (max-concurrency 1)
                                             metadata)
  (let* ((address (sbcl-agent::make-standard-actor-address role
                                                           :scope scope
                                                           :display-name display-name))
         (actor-id (sbcl-agent::actor-address-id address)))
    (sbcl-agent::make-actor-definition
     :id actor-id
     :role (sbcl-agent::actor-address-role address)
     :display-name (sbcl-agent::actor-address-display-name address)
     :parent-actor-id parent-actor-id
     :inbox-id (or shared-inbox-id
                   (format nil "~A/inbox" actor-id))
     :outbox-id (format nil "~A/outbox" actor-id)
     :handler-mode handler-mode
     :llm-profile llm-profile
     :capabilities capabilities
     :allocation-strategy
     (sbcl-agent::make-actor-allocation-strategy
      :type allocation-type
      :shared-inbox-id shared-inbox-id
      :pool-size pool-size
      :consumption-policy consumption-policy
      :metadata (copy-tree (or metadata '())))
     :supervision-policy
     (sbcl-agent::make-actor-supervision-policy
      :strategy supervision-strategy
      :max-restarts max-restarts
      :restart-window-seconds restart-window-seconds
      :on-failure on-failure
      :escalation-target escalation-target
      :metadata (copy-tree (or metadata '())))
     :execution-policy
     (sbcl-agent::make-actor-execution-policy
      :model execution-model
      :thread-name thread-name
      :mailbox-mode mailbox-mode
      :max-concurrency max-concurrency
      :metadata (copy-tree (or metadata '())))
     :metadata (append (copy-list (sbcl-agent::actor-address-metadata address))
                       (copy-tree (or metadata '()))))))

(defun actor-registry-core-definitions (session)
  (let* ((session-id (sbcl-agent::agent-session-id session))
         (system-id (sbcl-agent::make-actor-address-id :actor-system))
         (environment (sbcl-agent::session-bound-environment session)))
    (list
     (sbcl-agent::make-actor-definition
      :id system-id
      :role :actor-system
      :display-name "Actor System"
      :parent-actor-id nil
      :inbox-id (format nil "~A/inbox" system-id)
      :outbox-id (format nil "~A/outbox" system-id)
      :handler-mode :serial
      :llm-profile nil
      :capabilities '(:registry :routing :supervision)
      :allocation-strategy
      (sbcl-agent::make-actor-allocation-strategy
       :type :singleton
       :shared-inbox-id (format nil "~A/inbox" system-id)
       :pool-size 1
       :consumption-policy :sequential)
      :supervision-policy
      (sbcl-agent::make-actor-supervision-policy
       :strategy :root
       :max-restarts 0
       :restart-window-seconds 0
       :on-failure :quarantine
       :escalation-target nil)
      :execution-policy
      (sbcl-agent::make-actor-execution-policy
       :model :coordinator-thread
       :thread-name "actor-system-root"
       :mailbox-mode :serial-per-actor
       :max-concurrency 1)
      :metadata '(:actor-class :system-supervisor
                  :auto-supervision-escalation-p t))
     (make-default-actor-definition :context-chat
                                    :scope session-id
                                    :display-name "Context Chat"
                                    :parent-actor-id system-id
                                    :capabilities '(:conversation :projection)
                                    :llm-profile :default
                                    :supervision-strategy :one-for-one
                                    :on-failure :restart
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/context-chat"
                                    :metadata '(:actor-class :conversation-client))
     (make-default-actor-definition :governance
                                    :scope session-id
                                    :display-name "Governance Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:approval :authorization :policy)
                                    :llm-profile :default
                                    :supervision-strategy :one-for-one
                                    :on-failure :escalate
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/governance"
                                    :metadata '(:actor-class :policy-gateway
                                                :auto-supervision-escalation-p t))
     (make-default-actor-definition :workflow
                                    :scope session-id
                                    :display-name "Workflow Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:workflow/resume
                                                    :workflow/quarantine
                                                    :workflow/rollback
                                                    :workflow/complete-validations
                                                    :workflow/steer-plan
                                                    :workflow-state)
                                    :llm-profile :default
                                    :supervision-strategy :one-for-one
                                    :on-failure :escalate
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/workflow"
                                    :metadata '(:actor-class :workflow-controller
                                                :auto-supervision-escalation-p t))
     (make-default-actor-definition :project
                                    :scope session-id
                                    :display-name "Project Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:project/control
                                                    :project/binding
                                                    :project/planning)
                                    :llm-profile :default
                                    :supervision-strategy :one-for-one
                                    :on-failure :escalate
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/project"
                                    :metadata '(:actor-class :project-controller
                                                :auto-supervision-escalation-p t))
     (make-default-actor-definition :incident
                                    :scope session-id
                                    :display-name "Incident Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:incident/remediation
                                                    :incident-state
                                                    :incident-followup)
                                    :llm-profile :default
                                    :supervision-strategy :one-for-one
                                    :on-failure :escalate
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/incident"
                                    :metadata '(:actor-class :incident-controller
                                                :auto-supervision-escalation-p t))
     (make-default-actor-definition :runtime
                                    :scope session-id
                                    :display-name "Runtime Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:runtime-eval :runtime-state)
                                    :llm-profile :default
                                    :supervision-strategy :one-for-one
                                    :on-failure :restart
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/runtime"
                                    :metadata '(:actor-class :capability-server
                                                :runtime-id "runtime-primary"))
     (make-default-actor-definition :editor
                                    :scope session-id
                                    :display-name "Editor Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:workspace-write :buffer-mutation)
                                    :supervision-strategy :one-for-one
                                    :on-failure :restart
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/editor"
                                    :metadata '(:actor-class :capability-server))
     (make-default-actor-definition :calculator
                                    :scope session-id
                                    :display-name "Calculator Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:calculator-control)
                                    :supervision-strategy :one-for-one
                                    :on-failure :restart
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/calculator"
                                    :metadata '(:actor-class :capability-server))
     (make-default-actor-definition :package-management
                                    :scope session-id
                                    :display-name "Package Management Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:package-management/install-quicklisp
                                                    :package-management/run-qlot
                                                    :package-management/edit-source-registry
                                                    :package-management/manage-local-projects)
                                    :supervision-strategy :one-for-one
                                    :on-failure :escalate
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/package-management"
                                    :metadata '(:actor-class :environment-gateway
                                                :auto-supervision-escalation-p t))
     (make-default-actor-definition :memory
                                    :scope session-id
                                    :display-name "Memory Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:memory/update :memory/delete)
                                    :supervision-strategy :one-for-one
                                    :on-failure :escalate
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/memory"
                                    :metadata '(:actor-class :state-gateway))
     (make-default-actor-definition :intent
                                    :scope session-id
                                    :display-name "Intent Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:intent/create :intent/update :intent/select)
                                    :supervision-strategy :one-for-one
                                    :on-failure :escalate
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/intent"
                                    :metadata '(:actor-class :state-gateway))
     (make-default-actor-definition :shell
                                    :scope session-id
                                    :display-name "Shell Desktop Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:shell/desktop-control
                                                    :shell/desktop-restore
                                                    :shell/desktop-select)
                                    :supervision-strategy :one-for-one
                                    :on-failure :restart
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/shell"
                                    :metadata '(:actor-class :presentation-controller))
     (make-default-actor-definition :desktop-task-admin
                                    :scope session-id
                                    :display-name "Desktop Task Admin Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:desktop-task/configure-mcp-server
                                                    :desktop-task/remove-mcp-server
                                                    :desktop-task-admin)
                                    :supervision-strategy :one-for-one
                                    :on-failure :escalate
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/desktop-task-admin"
                                    :metadata '(:actor-class :governance-gateway
                                                :auto-supervision-escalation-p t))
     (make-default-actor-definition :environment
                                    :scope (or (and environment
                                                    (sbcl-agent::environment-id environment))
                                               session-id)
                                    :display-name "Environment Actor"
                                    :parent-actor-id system-id
                                    :capabilities '(:environment-state :persistence)
                                    :supervision-strategy :one-for-one
                                    :on-failure :escalate
                                    :escalation-target system-id
                                    :execution-model :thread-pool-worker
                                    :thread-name "actor-pool/environment"
                                    :metadata '(:actor-class :environment-gateway
                                                :auto-supervision-escalation-p t)))))

(defun actor-registry-desktop-task-definitions (session)
  (declare (ignore session))
  (let ((definitions '())
        (system-id (sbcl-agent::make-actor-address-id :actor-system)))
    (dolist (manifest (sbcl-agent::list-registered-desktop-task-manifests :discoverable-only-p nil))
      (let* ((target (sbcl-agent::desktop-task-manifest-target manifest))
             (backend-ref (sbcl-agent::desktop-task-manifest-backend-ref manifest))
             (backend-kind (sbcl-agent::desktop-task-manifest-backend-kind manifest))
             (core-singleton-target-p
             (and (eq backend-kind :internal)
                    (member target '(:context-chat :governance :workflow :project :incident :runtime :editor :calculator :package-management :memory :intent :shell :desktop-task-admin :environment)
                            :test #'eq)))
             (pooled-p (eq backend-kind :mcp))
             (shared-inbox-id
               (and pooled-p
                    (format nil "actor/~(~A~)/pool/~A/inbox"
                            target
                            (or backend-ref "default"))))
             (definition
               (make-default-actor-definition
               target
               :scope (and backend-ref (princ-to-string backend-ref))
                :display-name (or (sbcl-agent::desktop-task-manifest-description manifest)
                                  (format nil "~A Actor" target))
                :parent-actor-id system-id
                :capabilities (list (sbcl-agent::desktop-task-manifest-capability manifest))
                :allocation-type (if pooled-p :pool :singleton)
                :shared-inbox-id shared-inbox-id
                :pool-size (and pooled-p 4)
                :consumption-policy (and pooled-p :competing-consumers)
                :supervision-strategy (if pooled-p :one-for-all :one-for-one)
                :on-failure (if pooled-p :replace-member :restart)
                :escalation-target system-id
                :execution-model :thread-pool-worker
                :thread-name (format nil "actor-pool/~(~A~)" target)
                :mailbox-mode :serial-per-actor
                :max-concurrency 1
                :metadata (list :actor-class :capability-server
                                :manifest-id (sbcl-agent::desktop-task-manifest-id manifest)
                                :backend-kind backend-kind
                                :backend-ref backend-ref))))
        (unless core-singleton-target-p
          (push definition definitions))))
    (nreverse definitions)))

(defun actor-registry-definitions (session)
  (nreverse
   (delete-duplicates
    (append (reverse (actor-registry-desktop-task-definitions session))
            (reverse (actor-registry-core-definitions session)))
    :test (lambda (left right)
            (string= (sbcl-agent::actor-definition-id left)
                     (sbcl-agent::actor-definition-id right))))))

(defun actor-system-registry-definitions (session)
  (actor-registry-definitions session))

(defun ensure-environment-actor-registry-for-session (session)
  (let ((environment (sbcl-agent::session-bound-environment session)))
    (when environment
      (setf (sbcl-agent::environment-agent-registry environment)
            (actor-registry-definitions session))))
  session)

(defun actor-registry-definition-by-id (session actor-id)
  (find actor-id
        (actor-registry-definitions session)
        :key #'sbcl-agent::actor-definition-id
        :test #'string=))

(defun actor-registry-definition-by-role (session role)
  (find role
        (actor-registry-definitions session)
        :key #'sbcl-agent::actor-definition-role
        :test #'eq))

(defun actor-registry-definitions-by-capability (session capability)
  (remove-if-not
   (lambda (definition)
     (member capability
             (sbcl-agent::actor-definition-capabilities definition)
             :test #'eq))
   (actor-registry-definitions session)))

(defun find-actor-definition-for-address (session actor-address)
  (let* ((environment (sbcl-agent::session-bound-environment session))
         (definitions (or (and environment
                               (sbcl-agent::environment-agent-registry environment))
                          (actor-registry-definitions session))))
    (or (find (sbcl-agent::actor-address-id actor-address)
              definitions
              :key #'sbcl-agent::actor-definition-id
              :test #'string=)
        (find (sbcl-agent::actor-address-role actor-address)
              definitions
              :key #'sbcl-agent::actor-definition-role
              :test #'eq))))

(defun canonical-actor-address-for-session (session actor-address)
  (let ((definition (find-actor-definition-for-address session actor-address)))
    (if definition
        (actor-definition-address definition)
        actor-address)))
