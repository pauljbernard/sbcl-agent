(in-package #:sbcl-agent)

(defun create-patch-result-artifacts (session results &key thread turn operation)
  (let ((target-thread (or thread
                           (current-thread session))))
    (when target-thread
      (mapcar (lambda (entry)
                (let ((path (getf entry :path)))
                  (create-artifact session
                                   target-thread
                                   turn
                                   operation
                                   :file
                                   path
                                   :title (and path (file-namestring path))
                                   :summary "Patch write completed."
                                   :metadata (list :source :patch
                                                   :bytes (getf entry :bytes)
                                                   :operation (getf entry :operation)
                                                   :sandbox-profile (getf entry :sandbox-profile)))))
              results))))

(defun apply-patch-operation (session operation)
  (destructuring-bind (kind path content) operation
    (unless (eq kind :write)
      (error "Unsupported patch operation ~S" kind))
    (let ((resolved (ensure-path-within-session session path :must-exist nil)))
      (ensure-directories-exist resolved)
      (with-open-file (stream resolved
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write-string content stream))
      (list :operation :write
            :path (namestring resolved)
            :bytes (length content)
            :sandbox-profile :in-process))))

(defun apply-patch-operations (session operations &key thread turn operation)
  (ensure-policy-approved session :workspace-write)
  (unless (listp operations)
    (error "PATCH requires a list of operations"))
  (let ((results (mapcar (lambda (operation)
                           (apply-patch-operation session operation))
                         operations)))
    (create-patch-result-artifacts session results
                                   :thread thread
                                   :turn turn
                                   :operation operation)
    (append-session-event session :patch results)
    (list :patch results)))
