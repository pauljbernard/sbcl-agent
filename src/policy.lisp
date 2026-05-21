(in-package #:sbcl-agent.system.policy)

(defstruct capability-policy
  id
  description
  risk-level
  default-grant-mode)

(defstruct capability-grant
  policy-id
  granted-at
  scope
  metadata)

(defparameter *capability-policies* (make-hash-table :test #'eq))

(defun register-capability-policy (id description &key (risk-level :medium) (default-grant-mode :session))
  (setf (gethash id *capability-policies*)
        (make-capability-policy :id id
                                :description description
                                :risk-level risk-level
                                :default-grant-mode default-grant-mode))
  id)

(defun find-capability-policy (id)
  (gethash id *capability-policies*))

(defun ensure-capability-policy (policy-designator)
  (typecase policy-designator
    (capability-policy policy-designator)
    (keyword
     (or (find-capability-policy policy-designator)
         (error "Unknown capability policy ~S" policy-designator)))
    (t
     (error "Invalid capability policy designator ~S" policy-designator))))

(defun capability-policy-summary (policy)
  (list :id (capability-policy-id policy)
        :description (capability-policy-description policy)
        :risk-level (capability-policy-risk-level policy)
        :default-grant-mode (capability-policy-default-grant-mode policy)))

(defun list-capability-policies ()
  (sort (loop for policy being the hash-values of *capability-policies*
              collect (capability-policy-summary policy))
        #'string<
        :key (lambda (entry)
               (symbol-name (getf entry :id)))))

(register-capability-policy :safe-read
                            "Read-only operations that stay within the current session workspace."
                            :risk-level :low
                            :default-grant-mode :implicit)
(register-capability-policy :desktop-control
                            "Inspect or steer Surface desktop state through governed desktop tools."
                            :risk-level :low
                            :default-grant-mode :implicit)
(register-capability-policy :calculator-control
                            "Use the Surface calculator as transient local computational state without mutating workspace, runtime, or governance records."
                            :risk-level :low
                            :default-grant-mode :implicit)
(register-capability-policy :runtime-read
                            "Inspect read-only runtime state in the current image."
                            :risk-level :low
                            :default-grant-mode :implicit)
(register-capability-policy :runtime-package-switch
                            "Change the active Common Lisp package for the current runtime session."
                            :risk-level :medium)
(register-capability-policy :runtime-reload
                            "Load source files from the workspace into the current live image."
                            :risk-level :high)
(register-capability-policy :runtime-eval-safe
                            "Evaluate read-only or low-risk runtime expressions in the current image."
                            :risk-level :medium
                            :default-grant-mode :implicit)
(register-capability-policy :runtime-eval-mutate
                            "Evaluate runtime expressions that intentionally mutate the current image."
                            :risk-level :high)
(register-capability-policy :process-run
                            "Execute a local process inside the sandbox runtime."
                            :risk-level :high)
(register-capability-policy :linux-app-launch
                            "Launch a governed Linux compatibility app through the compatibility kernel."
                            :risk-level :high)
(register-capability-policy :linux-ide-launch
                            "Launch a governed Linux IDE app with workspace access and a desktop display surface."
                            :risk-level :high)
(register-capability-policy :git-read
                            "Read repository state through sandboxed git commands."
                            :risk-level :medium)
(register-capability-policy :git-write
                            "Mutate repository state through sandboxed git commands."
                            :risk-level :high)
(register-capability-policy :workspace-write
                            "Modify workspace files through patch application."
                            :risk-level :high)
(register-capability-policy :project-governance-write
                            "Mutate governed project artifacts such as constitutions, requirements, journeys, architecture decisions, and quality gates."
                            :risk-level :high)
(register-capability-policy :platform-package
                            "Export a governed developer platform package descriptor."
                            :risk-level :high)
(register-capability-policy :platform-import-package
                            "Import a governed developer platform package into the active environment registry."
                            :risk-level :high)
(register-capability-policy :platform-activate-package
                            "Activate an imported developer platform package in the active environment."
                            :risk-level :high)
(register-capability-policy :platform-deactivate-package
                            "Deactivate an imported developer platform package in the active environment."
                            :risk-level :high)
(register-capability-policy :platform-install-package
                            "Install a governed developer platform package by importing and activating it in the active environment."
                            :risk-level :high)
(register-capability-policy :platform-run-harness
                            "Run a governed developer platform harness that may exercise platform workflows and evaluations."
                            :risk-level :high)
(register-capability-policy :alignment-reconciliation-execute
                            "Materialize a reconciliation decision into governed corrective work that may change runtime, intent, or both."
                            :risk-level :high)
