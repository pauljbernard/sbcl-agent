(in-package #:sbcl-agent.system.registry)

(defstruct tool-definition
  id
  documentation
  policy
  isolation-profile
  compatibility-kind
  backend-profile-id
  function)

(defstruct compatibility-app-definition
  id
  title
  executable
  default-arguments
  launch-tool-id
  backend-profile-id
  policy-id
  filesystem-scope-kind
  network-policy
  workspace-write-p
  display-surface-kind
  source-package-id)

(defstruct compatibility-backend-profile
  id
  label
  substrate-kind
  isolation-class
  control-plane-kind
  display-bridge-kind
  filesystem-model
  network-model
  persistence-model
  host-process-p)

(defun compatibility-backend-profile-runtime-class (profile)
  (cond
    ((null profile) nil)
    ((and (eq (compatibility-backend-profile-display-bridge-kind profile) :desktop-window)
          (not (compatibility-backend-profile-host-process-p profile)))
     :managed-desktop-surface)
    ((eq (compatibility-backend-profile-display-bridge-kind profile) :desktop-window)
     :desktop-bridge)
    ((eq (compatibility-backend-profile-control-plane-kind profile) :process-token)
     :detached-host-process)
    ((compatibility-backend-profile-host-process-p profile)
     :attached-host-process)
    (t
     :governed-runtime)))

(defparameter *tool-registry* (make-hash-table :test #'equal))
(defparameter *compatibility-app-registry* (make-hash-table :test #'equal))
(defparameter *compatibility-backend-registry* (make-hash-table :test #'equal))
(defparameter *compatibility-app-provider-function* nil)

(defun ensure-tool-policy (policy-designator)
  (sbcl-agent::ensure-capability-policy policy-designator))

(defun register-tool (id documentation policy function
                      &key
                        (isolation-profile :in-process)
                        compatibility-kind
                        backend-profile-id)
  (when backend-profile-id
    (ensure-compatibility-backend-profile backend-profile-id))
  (setf (gethash id *tool-registry*)
        (make-tool-definition :id id
                              :documentation documentation
                              :policy (ensure-tool-policy policy)
                              :isolation-profile isolation-profile
                              :compatibility-kind compatibility-kind
                              :backend-profile-id backend-profile-id
                              :function function))
  id)

(defun register-compatibility-backend-profile (id label
                                               &key
                                                 substrate-kind
                                                 isolation-class
                                                 control-plane-kind
                                                 display-bridge-kind
                                                 filesystem-model
                                                 network-model
                                                 persistence-model
                                                 host-process-p)
  (setf (gethash id *compatibility-backend-registry*)
        (make-compatibility-backend-profile :id id
                                            :label label
                                            :substrate-kind substrate-kind
                                            :isolation-class isolation-class
                                            :control-plane-kind control-plane-kind
                                            :display-bridge-kind display-bridge-kind
                                            :filesystem-model filesystem-model
                                            :network-model network-model
                                            :persistence-model persistence-model
                                            :host-process-p host-process-p))
  id)

(defun find-compatibility-backend-profile (id)
  (and id
       (gethash id *compatibility-backend-registry*)))

(defun compatibility-backend-profile-summary (profile)
  (when profile
    (list :id (compatibility-backend-profile-id profile)
          :label (compatibility-backend-profile-label profile)
          :runtime-class (compatibility-backend-profile-runtime-class profile)
          :substrate-kind (compatibility-backend-profile-substrate-kind profile)
          :isolation-class (compatibility-backend-profile-isolation-class profile)
          :control-plane-kind (compatibility-backend-profile-control-plane-kind profile)
          :display-bridge-kind (compatibility-backend-profile-display-bridge-kind profile)
          :filesystem-model (compatibility-backend-profile-filesystem-model profile)
          :network-model (compatibility-backend-profile-network-model profile)
          :persistence-model (compatibility-backend-profile-persistence-model profile)
          :host-process-p (not (null (compatibility-backend-profile-host-process-p profile))))))

(defun ensure-compatibility-backend-profile (id)
  (or (find-compatibility-backend-profile id)
      (error "Unknown compatibility backend profile ~S" id)))

(defun find-tool (id)
  (gethash id *tool-registry*))

(defun register-compatibility-app (id title executable
                                   &key
                                     (default-arguments '())
                                     (launch-tool-id :proc/spawn)
                                     backend-profile-id
                                     (policy-id :linux-app-launch)
                                     (filesystem-scope-kind :session-workspace)
                                     (network-policy :none)
                                     (workspace-write-p nil)
                                     (display-surface-kind :headless)
                                     source-package-id)
  (when backend-profile-id
    (ensure-compatibility-backend-profile backend-profile-id))
  (unless backend-profile-id
    (let ((launch-tool (find-tool launch-tool-id)))
      (when launch-tool
        (setf backend-profile-id
              (tool-definition-backend-profile-id launch-tool)))))
  (setf (gethash id *compatibility-app-registry*)
        (make-compatibility-app-definition :id id
                                           :title title
                                           :executable executable
                                           :default-arguments (copy-tree default-arguments)
                                           :launch-tool-id launch-tool-id
                                           :backend-profile-id backend-profile-id
                                           :policy-id (sbcl-agent::capability-policy-id
                                                       (ensure-tool-policy policy-id))
                                           :filesystem-scope-kind filesystem-scope-kind
                                           :network-policy network-policy
                                           :workspace-write-p workspace-write-p
                                           :display-surface-kind display-surface-kind
                                           :source-package-id source-package-id))
  id)

(defun compatibility-app-provider-definitions (&key session environment)
  (when *compatibility-app-provider-function*
    (funcall *compatibility-app-provider-function* :session session
                                               :environment environment)))

(defun find-compatibility-app (id &key session environment)
  (or (find id
            (compatibility-app-provider-definitions :session session
                                                    :environment environment)
            :key #'compatibility-app-definition-id
            :test #'string=)
      (gethash id *compatibility-app-registry*)))

(defun compatibility-app-summary (definition)
  (let* ((backend-profile-id (compatibility-app-definition-backend-profile-id definition))
         (backend-profile (and backend-profile-id
                               (find-compatibility-backend-profile backend-profile-id))))
    (list :id (compatibility-app-definition-id definition)
          :title (compatibility-app-definition-title definition)
          :executable (compatibility-app-definition-executable definition)
          :default-arguments (copy-tree (compatibility-app-definition-default-arguments definition))
          :launch-tool-id (compatibility-app-definition-launch-tool-id definition)
          :backend-profile-id backend-profile-id
          :backend-profile (compatibility-backend-profile-summary backend-profile)
          :policy-id (compatibility-app-definition-policy-id definition)
          :filesystem-scope-kind (compatibility-app-definition-filesystem-scope-kind definition)
          :network-policy (compatibility-app-definition-network-policy definition)
          :workspace-write-p (not (null (compatibility-app-definition-workspace-write-p definition)))
          :display-surface-kind (compatibility-app-definition-display-surface-kind definition)
          :source-package-id (compatibility-app-definition-source-package-id definition))))

(defun compatibility-app-filesystem-scope (definition session)
  (ecase (compatibility-app-definition-filesystem-scope-kind definition)
    (:session-workspace
     (sbcl-agent::agent-session-cwd session))
    (:none
     nil)
    (:user-home
     (namestring (user-homedir-pathname)))))

(defun list-compatibility-apps (&key session environment)
  (let ((definitions
          (append (copy-list (or (compatibility-app-provider-definitions :session session
                                                                         :environment environment)
                                 '()))
                  (loop for definition being the hash-values of *compatibility-app-registry*
                        collect definition))))
    (sort
     (loop with seen-ids = '()
           for definition in definitions
           for id = (compatibility-app-definition-id definition)
           unless (member id seen-ids :test #'string=)
             do (push id seen-ids)
             and collect (compatibility-app-summary definition))
     #'string<
     :key (lambda (entry)
            (getf entry :id)))))

(defun compatibility-app-command-argv (id args &key session environment)
  (let ((definition (or (find-compatibility-app id :session session :environment environment)
                        (error "Unknown compatibility app ~S" id))))
    (append (list (compatibility-app-definition-executable definition))
            (copy-tree (compatibility-app-definition-default-arguments definition))
            (copy-tree (or (getf args :arguments)
                           (getf args :argv)
                           '())))))

(defun compatibility-app-target (id session args &key environment)
  (let* ((definition (or (find-compatibility-app id :session session :environment environment)
                         (error "Unknown compatibility app ~S" id)))
         (tool (or (find-tool (compatibility-app-definition-launch-tool-id definition))
                   (error "Compatibility app ~S references unknown launch tool ~S"
                          id
                          (compatibility-app-definition-launch-tool-id definition))))
         (profile-id (tool-definition-isolation-profile tool))
         (profile (sbcl-agent::ensure-sandbox-profile profile-id))
         (backend-profile-id (or (compatibility-app-definition-backend-profile-id definition)
                                 (error "Compatibility app ~S does not declare a backend profile" id)))
         (backend-profile (ensure-compatibility-backend-profile backend-profile-id))
         (execution-mode (if (eq (compatibility-app-definition-launch-tool-id definition) :proc/spawn)
                             :detached
                             :attached))
         (filesystem-scope (compatibility-app-filesystem-scope definition session)))
    (list :kind :linux-app
          :app-id id
          :title (compatibility-app-definition-title definition)
          :policy-id (compatibility-app-definition-policy-id definition)
          :launch-tool-id (compatibility-app-definition-launch-tool-id definition)
          :backend :sbcl-sandbox-worker
          :backend-adapter-id backend-profile-id
          :backend-profile-id backend-profile-id
          :backend-profile (compatibility-backend-profile-summary backend-profile)
          :sandbox-profile profile-id
          :cwd (sbcl-agent::agent-session-cwd session)
          :filesystem-scope filesystem-scope
          :filesystem-scope-kind (compatibility-app-definition-filesystem-scope-kind definition)
          :network-enabled-p (not (eq (compatibility-app-definition-network-policy definition) :none))
          :network-policy (compatibility-app-definition-network-policy definition)
          :workspace-write-p (not (null (compatibility-app-definition-workspace-write-p definition)))
          :display-surface-kind (compatibility-app-definition-display-surface-kind definition)
          :source-package-id (compatibility-app-definition-source-package-id definition)
          :sandbox-network-enabled-p (sbcl-agent::sandbox-profile-network-enabled-p profile)
          :sandbox-workspace-write-p (sbcl-agent::sandbox-profile-workspace-write-p profile)
          :argv (compatibility-app-command-argv id args :session session :environment environment)
          :execution-mode execution-mode)))

(defun list-tools ()
  (sort
   (loop for definition being the hash-values of *tool-registry*
         collect (list :id (tool-definition-id definition)
                       :documentation (tool-definition-documentation definition)
                       :policy (sbcl-agent::capability-policy-id (tool-definition-policy definition))
                       :policy-spec (sbcl-agent::capability-policy-summary (tool-definition-policy definition))
                       :compatibility-kind (tool-definition-compatibility-kind definition)
                       :backend-profile-id (tool-definition-backend-profile-id definition)
                       :backend-profile (compatibility-backend-profile-summary
                                         (find-compatibility-backend-profile
                                          (tool-definition-backend-profile-id definition)))
                       :isolation-profile (tool-definition-isolation-profile definition)))
   #'string<
   :key (lambda (entry)
          (symbol-name (getf entry :id)))))

(defun describe-tool (id)
  (let ((definition (find-tool id)))
    (unless definition
      (error "Unknown tool ~S" id))
    (list :id (tool-definition-id definition)
          :documentation (tool-definition-documentation definition)
          :policy (sbcl-agent::capability-policy-id (tool-definition-policy definition))
          :policy-spec (sbcl-agent::capability-policy-summary (tool-definition-policy definition))
          :compatibility-kind (tool-definition-compatibility-kind definition)
          :backend-profile-id (tool-definition-backend-profile-id definition)
          :backend-profile (compatibility-backend-profile-summary
                            (find-compatibility-backend-profile
                             (tool-definition-backend-profile-id definition)))
          :isolation-profile (tool-definition-isolation-profile definition))))

(defun tool-compatibility-target (id session args)
  (let ((definition (find-tool id)))
    (when (and definition
               (tool-definition-compatibility-kind definition))
      (let* ((profile-id (tool-definition-isolation-profile definition))
             (profile (sbcl-agent::ensure-sandbox-profile profile-id))
             (backend-profile-id (tool-definition-backend-profile-id definition))
             (backend-profile (and backend-profile-id
                                   (ensure-compatibility-backend-profile
                                    backend-profile-id))))
        (list :kind (tool-definition-compatibility-kind definition)
              :tool-id id
              :backend :sbcl-sandbox-worker
              :backend-adapter-id backend-profile-id
              :backend-profile-id backend-profile-id
              :backend-profile (compatibility-backend-profile-summary backend-profile)
              :sandbox-profile profile-id
              :cwd (sbcl-agent::agent-session-cwd session)
              :filesystem-scope (sbcl-agent::agent-session-cwd session)
              :network-enabled-p (sbcl-agent::sandbox-profile-network-enabled-p profile)
              :workspace-write-p (sbcl-agent::sandbox-profile-workspace-write-p profile)
              :argv (copy-tree (getf args :argv)))))))

(defun invoke-sandboxed-tool (id session args)
  (let ((definition (or (find-tool id)
                        (error "Unknown tool ~S" id))))
    (if (and (tool-definition-compatibility-kind definition)
             (tool-definition-backend-profile-id definition))
        (let* ((backend-profile-id (tool-definition-backend-profile-id definition))
               (backend-profile (ensure-compatibility-backend-profile backend-profile-id))
               (argv (getf args :argv))
               (display-surface-kind
                 (or (compatibility-backend-profile-display-bridge-kind backend-profile)
                     :headless)))
          (sbcl-agent::compatibility-backend-launch backend-profile-id
                                                    session
                                                    argv
                                                    :display-surface-kind display-surface-kind))
        (case id
          (:git/status
     (sbcl-agent::sandbox-execute-git session :status))
          (:git/diff
           (sbcl-agent::sandbox-execute-git session :diff :cached (getf args :cached)))
          (:git/add
           (sbcl-agent::sandbox-execute-git session :add :paths (getf args :paths)))
          (:git/commit
           (sbcl-agent::sandbox-execute-git session :commit :message (getf args :message)))
          (:git/branch
           (sbcl-agent::sandbox-execute-git session :branch :name (getf args :name) :checkout (getf args :checkout)))
          (t
           (error "Sandbox execution is not implemented for tool ~S" id))))))

(defun invoke-tool (id session &rest args &key &allow-other-keys)
  (let ((definition (find-tool id)))
    (unless definition
      (error "Unknown tool ~S" id))
    (let ((policy (tool-definition-policy definition))
          (isolation-profile (tool-definition-isolation-profile definition)))
      (sbcl-agent::ensure-capability-granted session policy)
      (if (eq isolation-profile :in-process)
          (apply (tool-definition-function definition) session args)
          (invoke-sandboxed-tool id session args)))))
