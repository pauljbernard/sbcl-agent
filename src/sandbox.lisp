(in-package #:tutor-codex)

(defstruct sandbox-profile
  id
  description
  network-enabled-p
  workspace-write-p)

(defparameter *sandbox-profiles*
  (list (make-sandbox-profile :id :in-process
                              :description "Execute in the main SBCL image."
                              :network-enabled-p nil
                              :workspace-write-p nil)
        (make-sandbox-profile :id :process-run
                              :description "Execute a subprocess from an isolated SBCL worker."
                              :network-enabled-p nil
                              :workspace-write-p nil)))

(defun find-sandbox-profile (id)
  (find id *sandbox-profiles* :key #'sandbox-profile-id))

(defun ensure-sandbox-profile (id)
  (or (find-sandbox-profile id)
      (error "Unknown sandbox profile ~S" id)))

(defun canonicalize-directory-path (path)
  (uiop:ensure-directory-pathname (truename path)))

(defun canonicalize-file-parent-directory (pathname)
  (canonicalize-directory-path (or (uiop:pathname-directory-pathname pathname)
                                   (error "Could not determine parent directory for ~A" pathname))))

(defun path-within-root-p (candidate root)
  (let ((candidate-namestring (namestring (canonicalize-directory-path candidate)))
        (root-namestring (namestring (canonicalize-directory-path root))))
    (and (>= (length candidate-namestring) (length root-namestring))
         (string= root-namestring candidate-namestring :end2 (length root-namestring)))))

(defun ensure-path-within-session (session path &key must-exist)
  (let* ((root (canonicalize-directory-path (agent-session-cwd session)))
         (resolved (resolve-session-path session path))
         (existing-target (probe-file resolved))
         (target (if existing-target
                     (truename existing-target)
                     resolved))
         (container (if (or (uiop:directory-pathname-p target)
                            (and existing-target
                                 (uiop:directory-pathname-p (truename existing-target))))
                        (if existing-target
                            (truename existing-target)
                            target)
                        (canonicalize-file-parent-directory target))))
    (unless (path-within-root-p container root)
      (error "Path escapes the current session workspace: ~A" path))
    (when (and must-exist (null existing-target))
      (error "Path does not exist in workspace: ~A" path))
    target))

(defun sandbox-runner-path ()
  (merge-pathnames #P"bin/sandbox-runner"
                   (uiop:ensure-directory-pathname (config-working-directory (load-config)))))

(defun parse-sandbox-result (payload)
  (with-input-from-string (stream payload)
    (read stream nil nil)))

(defun sandbox-worker-command (command session argv)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (let ((process (sb-ext:run-program "sbcl"
                                       (append (list "--script"
                                                     (namestring (sandbox-runner-path))
                                                     command
                                                     (agent-session-cwd session))
                                               argv)
                                       :search t
                                       :input nil
                                       :output stdout
                                       :error stderr
                                       :wait t)))
      (let ((exit-code (sb-ext:process-exit-code process))
            (stdout-string (get-output-stream-string stdout))
            (stderr-string (get-output-stream-string stderr)))
        (unless (zerop exit-code)
          (error "Sandbox worker failed with exit code ~D: ~A" exit-code stderr-string))
        (parse-sandbox-result stdout-string)))))

(defun sandbox-execute-process (session argv)
  (ensure-sandbox-profile :process-run)
  (unless (and (listp argv) argv)
    (error ":proc/run requires non-empty :argv"))
  (let ((result (sandbox-worker-command "proc-run" session argv)))
    (append-session-event session :sandbox-exec
                          (list :profile :process-run :argv argv :result result))
    result))

(defun sandbox-execute-git (session action &rest arguments)
  (ensure-sandbox-profile :process-run)
  (let ((argv
          (case action
            (:status '())
            (:diff (if (getf arguments :cached)
                       '("--cached")
                       '()))
            (:add (let ((paths (getf arguments :paths)))
                    (unless (and (listp paths) paths)
                      (error ":git/add requires non-empty :paths"))
                    paths))
            (:commit (let ((message (getf arguments :message)))
                       (unless (and (stringp message) (> (length message) 0))
                         (error ":git/commit requires non-empty :message"))
                       (list message)))
            (:branch (let ((name (getf arguments :name))
                           (checkout (getf arguments :checkout)))
                       (unless (and (stringp name) (> (length name) 0))
                         (error ":git/branch requires non-empty :name"))
                       (if checkout
                           (list name "--checkout")
                           (list name))))
            (t
             (error "Unsupported git sandbox action ~S" action)))))
    (let ((result (sandbox-worker-command (ecase action
                                            (:status "git-status")
                                            (:diff "git-diff")
                                            (:add "git-add")
                                            (:commit "git-commit")
                                            (:branch "git-branch"))
                                         session
                                         argv)))
      (append-session-event session :sandbox-exec
                            (list :profile :process-run
                                  :git-action action
                                  :arguments arguments
                                  :result result))
      result)))

(defun sandbox-worker-environment ()
  (let ((path (ignore-errors (getenv "PATH")))
        (home (ignore-errors (getenv "HOME"))))
    (remove nil (list (and path (format nil "PATH=~A" path))
                      (and home (format nil "HOME=~A" home))))))

(defun sandbox-worker-proc-run (cwd argv)
  (unless (and (listp argv) argv)
    (error "Sandbox worker requires argv"))
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream))
        (program (first argv))
        (arguments (rest argv)))
    (let ((process (sb-ext:run-program program
                                       arguments
                                       :search t
                                       :input nil
                                       :output stdout
                                       :error stderr
                                       :wait t
                                       :directory cwd
                                       :environment (sandbox-worker-environment))))
      (list :tool :proc/run
            :argv argv
            :stdout (get-output-stream-string stdout)
            :stderr (get-output-stream-string stderr)
            :exit-code (sb-ext:process-exit-code process)
            :sandboxed t
            :sandbox-profile :process-run))))

(defun sandbox-worker-git-command (cwd args)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (let ((process (sb-ext:run-program "git"
                                       args
                                       :search t
                                       :input nil
                                       :output stdout
                                       :error stderr
                                       :wait t
                                       :directory cwd
                                       :environment (sandbox-worker-environment))))
      (list :stdout (get-output-stream-string stdout)
            :stderr (get-output-stream-string stderr)
            :exit-code (sb-ext:process-exit-code process)
            :sandboxed t
            :sandbox-profile :process-run))))

(defun sandbox-worker-git-status (cwd)
  (let ((result (sandbox-worker-git-command cwd '("status" "--short" "--branch"))))
    (append (list :tool :git/status)
            result)))

(defun sandbox-worker-git-diff (cwd args)
  (let ((result (sandbox-worker-git-command cwd (append '("diff") args))))
    (append (list :tool :git/diff
                  :cached (member "--cached" args :test #'string=))
            result)))

(defun sandbox-worker-git-add (cwd paths)
  (let ((result (sandbox-worker-git-command cwd (append '("add" "--") paths))))
    (append (list :tool :git/add
                  :paths paths)
            result)))

(defun sandbox-worker-git-commit (cwd args)
  (let* ((message (first args))
         (result (sandbox-worker-git-command
                  cwd
                  (list "-c" "user.name=pauljbernard"
                        "-c" "user.email=pauljbernard@example.com"
                        "commit" "-m" message))))
    (append (list :tool :git/commit
                  :message message)
            result)))

(defun sandbox-worker-git-branch (cwd args)
  (let* ((name (first args))
         (checkout (member "--checkout" args :test #'string=))
         (command (if checkout
                      (list "checkout" "-b" name)
                      (list "branch" name)))
         (result (sandbox-worker-git-command cwd command)))
    (append (list :tool :git/branch
                  :name name
                  :checkout (not (null checkout)))
            result)))

(defun sandbox-worker-main ()
  (let ((arguments (uiop:command-line-arguments)))
    (unless arguments
      (error "sandbox-runner requires a command"))
    (let* ((command (first arguments))
           (cwd (second arguments))
           (argv (cddr arguments))
           (result (cond
                     ((string= command "proc-run")
                      (sandbox-worker-proc-run cwd argv))
                     ((string= command "git-status")
                      (sandbox-worker-git-status cwd))
                     ((string= command "git-diff")
                      (sandbox-worker-git-diff cwd argv))
                     ((string= command "git-add")
                      (sandbox-worker-git-add cwd argv))
                     ((string= command "git-commit")
                      (sandbox-worker-git-commit cwd argv))
                     ((string= command "git-branch")
                      (sandbox-worker-git-branch cwd argv))
                     (t
                      (error "Unknown sandbox command: ~A" command)))))
      (let ((*print-circle* t)
            (*print-pretty* t))
        (write result)
        (terpri)))))
