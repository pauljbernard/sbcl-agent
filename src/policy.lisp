(in-package #:tutor-codex)

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
(register-capability-policy :process-run
                            "Execute a local process inside the sandbox runtime."
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
