(in-package #:sbcl-agent)

(defstruct tool-definition
  id
  documentation
  policy
  isolation-profile
  compatibility-kind
  function)

(defparameter *tool-registry* (make-hash-table :test #'equal))

(defun ensure-tool-policy (policy-designator)
  (ensure-capability-policy policy-designator))

(defun register-tool (id documentation policy function &key (isolation-profile :in-process) compatibility-kind)
  (setf (gethash id *tool-registry*)
        (make-tool-definition :id id
                              :documentation documentation
                              :policy (ensure-tool-policy policy)
                              :isolation-profile isolation-profile
                              :compatibility-kind compatibility-kind
                              :function function))
  id)

(defun find-tool (id)
  (gethash id *tool-registry*))

(defun list-tools ()
  (sort
   (loop for definition being the hash-values of *tool-registry*
         collect (list :id (tool-definition-id definition)
                       :documentation (tool-definition-documentation definition)
                       :policy (capability-policy-id (tool-definition-policy definition))
                       :policy-spec (capability-policy-summary (tool-definition-policy definition))
                       :compatibility-kind (tool-definition-compatibility-kind definition)
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
          :policy (capability-policy-id (tool-definition-policy definition))
          :policy-spec (capability-policy-summary (tool-definition-policy definition))
          :compatibility-kind (tool-definition-compatibility-kind definition)
          :isolation-profile (tool-definition-isolation-profile definition))))

(defun tool-compatibility-target (id session args)
  (let ((definition (find-tool id)))
    (when (and definition
               (tool-definition-compatibility-kind definition))
      (let* ((profile-id (tool-definition-isolation-profile definition))
             (profile (ensure-sandbox-profile profile-id)))
        (list :kind (tool-definition-compatibility-kind definition)
              :tool-id id
              :backend :sbcl-sandbox-worker
              :sandbox-profile profile-id
              :cwd (agent-session-cwd session)
              :filesystem-scope (agent-session-cwd session)
              :network-enabled-p (sandbox-profile-network-enabled-p profile)
              :workspace-write-p (sandbox-profile-workspace-write-p profile)
              :argv (copy-tree (getf args :argv)))))))

(defun invoke-sandboxed-tool (id session args)
  (case id
    (:proc/run
     (sandbox-execute-process session (getf args :argv)))
    (:proc/spawn
     (sandbox-execute-process-spawn session (getf args :argv)))
    (:git/status
     (sandbox-execute-git session :status))
    (:git/diff
     (sandbox-execute-git session :diff :cached (getf args :cached)))
    (:git/add
     (sandbox-execute-git session :add :paths (getf args :paths)))
    (:git/commit
     (sandbox-execute-git session :commit :message (getf args :message)))
    (:git/branch
     (sandbox-execute-git session :branch :name (getf args :name) :checkout (getf args :checkout)))
    (t
     (error "Sandbox execution is not implemented for tool ~S" id))))

(defun invoke-tool (id session &rest args &key &allow-other-keys)
  (let ((definition (find-tool id)))
    (unless definition
      (error "Unknown tool ~S" id))
    (let ((policy (tool-definition-policy definition))
          (isolation-profile (tool-definition-isolation-profile definition)))
      (ensure-capability-granted session policy)
      (if (eq isolation-profile :in-process)
          (apply (tool-definition-function definition) session args)
          (invoke-sandboxed-tool id session args)))))
