(in-package #:tutor-codex)

(defun apply-patch-operation (session operation)
  (destructuring-bind (kind path content) operation
    (unless (eq kind :write)
      (error "Unsupported patch operation ~S" kind))
    (let ((resolved (resolve-session-path session path)))
      (with-open-file (stream resolved
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write-string content stream))
      (list :operation :write :path (namestring resolved) :bytes (length content)))))

(defun apply-patch-operations (session operations)
  (ensure-policy-approved session :workspace-write)
  (unless (listp operations)
    (error "PATCH requires a list of operations"))
  (let ((results (mapcar (lambda (operation)
                           (apply-patch-operation session operation))
                         operations)))
    (append-session-event session :patch results)
    (list :patch results)))
