(in-package #:sbcl-agent)

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
        (make-sandbox-profile :id :workspace-staging
                              :description "Stage governed workspace mutations in a disposable task workspace before promotion."
                              :network-enabled-p nil
                              :workspace-write-p t)
        (make-sandbox-profile :id :process-run
                              :description "Execute a subprocess from an isolated SBCL worker."
                              :network-enabled-p nil
                              :workspace-write-p nil)))

(defparameter *compatibility-process-registry* (make-hash-table :test #'equal))
(defparameter *desktop-bridge-session-registry* (make-hash-table :test #'equal))
(defparameter *managed-desktop-surface-registry* (make-hash-table :test #'equal))
(defstruct compatibility-backend-adapter
  id
  label
  launch-function
  status-function
  token-live-p-function
  stop-function)

(defparameter *compatibility-backend-adapters* (make-hash-table :test #'equal))

(defun register-compatibility-backend-adapter (id label
                                               &key
                                                 launch-function
                                                 status-function
                                                 token-live-p-function
                                                 stop-function)
  (setf (gethash id *compatibility-backend-adapters*)
        (make-compatibility-backend-adapter :id id
                                            :label label
                                            :launch-function launch-function
                                            :status-function status-function
                                            :token-live-p-function token-live-p-function
                                            :stop-function stop-function))
  id)

(defun find-compatibility-backend-adapter (id)
  (and id
       (gethash id *compatibility-backend-adapters*)))

(defun ensure-compatibility-backend-adapter (id)
  (or (find-compatibility-backend-adapter id)
      (error "Unknown compatibility backend adapter ~S" id)))

(defun compatibility-backend-launch (backend-profile-id session argv &key display-surface-kind)
  (let ((adapter (ensure-compatibility-backend-adapter backend-profile-id)))
    (funcall (or (compatibility-backend-adapter-launch-function adapter)
                 (error "Compatibility backend ~S does not implement launch" backend-profile-id))
             session
             argv
             :display-surface-kind display-surface-kind)))

(defun compatibility-backend-status (backend-profile-id control-token stored-status)
  (let ((adapter (find-compatibility-backend-adapter backend-profile-id)))
    (cond
      ((and adapter control-token (compatibility-backend-adapter-status-function adapter))
       (funcall (compatibility-backend-adapter-status-function adapter) control-token stored-status))
      (t
       stored-status))))

(defun compatibility-backend-token-live-p (backend-profile-id control-token)
  (let ((adapter (find-compatibility-backend-adapter backend-profile-id)))
    (and adapter
         control-token
         (compatibility-backend-adapter-token-live-p-function adapter)
         (funcall (compatibility-backend-adapter-token-live-p-function adapter) control-token))))

(defun compatibility-backend-stop (backend-profile-id control-token &key revoke-p)
  (let ((adapter (ensure-compatibility-backend-adapter backend-profile-id)))
    (funcall (or (compatibility-backend-adapter-stop-function adapter)
                 (error "Compatibility backend ~S does not implement controlled stop" backend-profile-id))
             control-token
             :revoke-p revoke-p)))

(defun make-compatibility-control-token ()
  (format nil "compat-proc-~D-~D" (get-universal-time) (random 1000000)))

(defun register-compatibility-process (process &key argv cwd)
  (let ((token (make-compatibility-control-token))
        (registered-at (get-universal-time)))
    (setf (gethash token *compatibility-process-registry*)
          (list :token token
                :process process
                :pid (sb-ext:process-pid process)
                :argv (copy-tree argv)
                :cwd cwd
                :registered-at registered-at
                :final-status nil))
    (list :token token
          :registered-at registered-at)))

(defun compatibility-process-record (token)
  (gethash token *compatibility-process-registry*))

(defun compatibility-process-token-live-p (token)
  (not (null (compatibility-process-record token))))

(defun compatibility-process-status (token)
  (let ((record (compatibility-process-record token)))
    (cond
      ((null record) :detached)
      ((getf record :final-status) (getf record :final-status))
      ((sb-ext:process-alive-p (getf record :process)) :running)
      (t
       (let ((exit-code (ignore-errors
                          (sb-ext:process-exit-code (getf record :process)))))
         (if (and (integerp exit-code) (zerop exit-code))
             :completed
             :failed))))))

(defun compatibility-process-stop (token &key revoke-p)
  (let* ((record (or (compatibility-process-record token)
                     (error "Unknown compatibility control token ~A" token)))
         (process (getf record :process))
         (signal (if revoke-p 9 15))
         (status (if revoke-p :revoked :stopped)))
    (when (and process
               (sb-ext:process-alive-p process))
      (sb-ext:process-kill process signal)
      (sb-ext:process-wait process)
      (ignore-errors (sb-ext:process-close process)))
    (setf (getf record :final-status) status)
    (setf (gethash token *compatibility-process-registry*) record)
    (list :token token
          :pid (getf record :pid)
          :status status
          :signal signal)))

(defun make-desktop-bridge-session-id ()
  (format nil "desktop-bridge-~D-~D" (get-universal-time) (random 1000000)))

(defun make-managed-desktop-surface-id ()
  (format nil "managed-surface-~D-~D" (get-universal-time) (random 1000000)))

(defun register-desktop-bridge-session (process &key argv cwd display-surface-kind)
  (let* ((process-registration (register-compatibility-process process
                                                               :argv argv
                                                               :cwd cwd))
         (control-token (getf process-registration :token))
         (bridge-session-id (make-desktop-bridge-session-id))
         (registered-at (getf process-registration :registered-at))
         (window-state (if (eq display-surface-kind :desktop-window)
                           :visible
                           :background)))
    (setf (gethash control-token *desktop-bridge-session-registry*)
          (list :bridge-session-id bridge-session-id
                :control-token control-token
                :argv (copy-tree argv)
                :cwd cwd
                :registered-at registered-at
                :display-surface-kind display-surface-kind
                :bridge-attached-p t
                :window-state window-state))
    (list :bridge-session-id bridge-session-id
          :control-token control-token
          :registered-at registered-at
          :bridge-attached-p t
          :window-state window-state)))

(defun desktop-bridge-session-record (control-token)
  (gethash control-token *desktop-bridge-session-registry*))

(defun desktop-bridge-session-live-p (control-token)
  (let ((record (desktop-bridge-session-record control-token)))
    (and record
         (getf record :bridge-attached-p)
         (compatibility-process-token-live-p control-token))))

(defun desktop-bridge-session-status (control-token)
  (let ((record (desktop-bridge-session-record control-token)))
    (cond
      ((null record) :detached)
      ((not (getf record :bridge-attached-p)) :detached)
      (t
       (compatibility-process-status control-token)))))

(defun desktop-bridge-session-stop (control-token &key revoke-p)
  (let* ((record (or (desktop-bridge-session-record control-token)
                     (error "Unknown desktop bridge control token ~A" control-token)))
         (process-result (compatibility-process-stop control-token :revoke-p revoke-p))
         (status (getf process-result :status)))
    (setf (getf record :bridge-attached-p) nil
          (getf record :window-state) :closed
          (gethash control-token *desktop-bridge-session-registry*) record)
    (append process-result
            (list :bridge-session-id (getf record :bridge-session-id)
                  :bridge-attached-p nil
                  :window-state :closed
                  :recovery-note "Desktop bridge session closed; relaunch requires a fresh bridge attachment."))))

(defun register-managed-desktop-surface (argv &key cwd display-surface-kind)
  (let* ((control-token (make-compatibility-control-token))
         (bridge-session-id (make-managed-desktop-surface-id))
         (registered-at (get-universal-time))
         (window-state (if (eq display-surface-kind :desktop-window)
                           :visible
                           :background))
         (record (list :control-token control-token
                       :bridge-session-id bridge-session-id
                       :argv (copy-tree argv)
                       :cwd cwd
                       :registered-at registered-at
                       :display-surface-kind display-surface-kind
                       :bridge-attached-p t
                       :window-state window-state
                       :status :running
                       :surface-kind :managed-desktop-surface
                       :final-status nil)))
    (setf (gethash control-token *managed-desktop-surface-registry*) record)
    (list :control-token control-token
          :bridge-session-id bridge-session-id
          :registered-at registered-at
          :bridge-attached-p t
          :window-state window-state
          :status :running)))

(defun managed-desktop-surface-record (control-token)
  (gethash control-token *managed-desktop-surface-registry*))

(defun managed-desktop-surface-live-p (control-token)
  (let ((record (managed-desktop-surface-record control-token)))
    (and record
         (getf record :bridge-attached-p)
         (member (or (getf record :final-status)
                     (getf record :status))
                 '(:running :in-progress)
                 :test #'eq))))

(defun managed-desktop-surface-status (control-token &optional stored-status)
  (declare (ignore stored-status))
  (let ((record (managed-desktop-surface-record control-token)))
    (cond
      ((null record) :detached)
      ((not (getf record :bridge-attached-p)) :detached)
      ((getf record :final-status) (getf record :final-status))
      (t (or (getf record :status) :running)))))

(defun managed-desktop-surface-stop (control-token &key revoke-p)
  (let* ((record (or (managed-desktop-surface-record control-token)
                     (error "Unknown managed desktop surface control token ~A" control-token)))
         (status (if revoke-p :revoked :stopped)))
    (setf (getf record :final-status) status
          (getf record :status) status
          (getf record :bridge-attached-p) nil
          (getf record :window-state) :closed
          (gethash control-token *managed-desktop-surface-registry*) record)
    (list :token control-token
          :status status
          :bridge-session-id (getf record :bridge-session-id)
          :bridge-attached-p nil
          :window-state :closed
          :recovery-note "Managed desktop surface closed; relaunch provisions a fresh governed surface.")))

(defun find-sandbox-profile (id)
  (find id *sandbox-profiles* :key #'sandbox-profile-id))

(defun ensure-sandbox-profile (id)
  (or (find-sandbox-profile id)
      (error "Unknown sandbox profile ~S" id)))

(defun canonicalize-directory-path (path)
  (let ((existing (probe-file path)))
    (uiop:ensure-directory-pathname (if existing
                                        (truename existing)
                                        path))))

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

(defun sandbox-execute-process-spawn (session argv)
  (ensure-sandbox-profile :process-run)
  (unless (and (listp argv) argv)
    (error ":proc/spawn requires non-empty :argv"))
  (let* ((process (sb-ext:run-program (first argv)
                                      (rest argv)
                                      :search t
                                      :input nil
                                      :output nil
                                      :error nil
                                      :wait nil
                                      :directory (agent-session-cwd session)
                                      :environment (sandbox-worker-environment)))
         (registration (register-compatibility-process process
                                                       :argv argv
                                                       :cwd (agent-session-cwd session)))
         (token (getf registration :token))
         (result (list :tool :proc/spawn
                       :argv argv
                       :cwd (agent-session-cwd session)
                       :pid (sb-ext:process-pid process)
                       :control-token token
                       :registered-at (getf registration :registered-at)
                       :status :running
                       :sandboxed t
                       :sandbox-profile :process-run)))
    (append-session-event session :sandbox-exec
                          (list :profile :process-run :argv argv :result result))
    result))

(register-compatibility-backend-adapter
 :host-process-sync
 "Synchronous host-process adapter"
 :launch-function
 (lambda (session argv &key display-surface-kind)
   (declare (ignore display-surface-kind))
   (append (sandbox-execute-process session argv)
           (list :backend-implementation :sandbox-proc-runner)))
 :status-function
 (lambda (control-token stored-status)
   (declare (ignore control-token))
   stored-status)
 :token-live-p-function
 (lambda (control-token)
   (declare (ignore control-token))
   nil))

(register-compatibility-backend-adapter
 :host-process-detached
 "Detached host-process adapter"
 :launch-function
 (lambda (session argv &key display-surface-kind)
   (declare (ignore display-surface-kind))
   (append (sandbox-execute-process-spawn session argv)
           (list :backend-implementation :sandbox-detached-process)))
 :status-function
 (lambda (control-token stored-status)
   (declare (ignore stored-status))
   (compatibility-process-status control-token))
 :token-live-p-function
 #'compatibility-process-token-live-p
 :stop-function
 #'compatibility-process-stop)

(register-compatibility-backend-adapter
 :desktop-app-bridge
 "Desktop window compatibility adapter"
 :launch-function
 (lambda (session argv &key display-surface-kind)
   (let* ((process (sb-ext:run-program (first argv)
                                       (rest argv)
                                       :search t
                                       :input nil
                                       :output nil
                                       :error nil
                                       :wait nil
                                       :directory (agent-session-cwd session)
                                       :environment (sandbox-worker-environment)))
          (registration (register-desktop-bridge-session process
                                                         :argv argv
                                                         :cwd (agent-session-cwd session)
                                                         :display-surface-kind display-surface-kind))
          (result (list :tool :desktop-app-bridge
                        :argv argv
                        :cwd (agent-session-cwd session)
                        :pid (sb-ext:process-pid process)
                        :control-token (getf registration :control-token)
                        :registered-at (getf registration :registered-at)
                        :status :running
                        :sandboxed t
                        :sandbox-profile :process-run
                        :bridge-session-id (getf registration :bridge-session-id)
                        :bridge-attached-p (getf registration :bridge-attached-p)
                        :window-state (getf registration :window-state)
                        :backend-implementation :sandbox-desktop-bridge)))
     (append-session-event session :sandbox-exec
                           (list :profile :desktop-app-bridge :argv argv :result result))
     result))
 :status-function
 #'desktop-bridge-session-status
 :token-live-p-function
 #'desktop-bridge-session-live-p
 :stop-function
 #'desktop-bridge-session-stop)

(register-compatibility-backend-adapter
 :managed-desktop-surface
 "Managed desktop surface adapter"
 :launch-function
 (lambda (session argv &key display-surface-kind)
   (let* ((registration (register-managed-desktop-surface argv
                                                          :cwd (agent-session-cwd session)
                                                          :display-surface-kind display-surface-kind))
          (result (list :tool :managed-desktop-surface
                        :argv argv
                        :cwd (agent-session-cwd session)
                        :control-token (getf registration :control-token)
                        :registered-at (getf registration :registered-at)
                        :status (getf registration :status)
                        :sandboxed t
                        :sandbox-profile :process-run
                        :bridge-session-id (getf registration :bridge-session-id)
                        :bridge-attached-p (getf registration :bridge-attached-p)
                        :window-state (getf registration :window-state)
                        :backend-implementation :managed-desktop-surface)))
     (append-session-event session :sandbox-exec
                           (list :profile :managed-desktop-surface :argv argv :result result))
     result))
 :status-function
 #'managed-desktop-surface-status
 :token-live-p-function
 #'managed-desktop-surface-live-p
 :stop-function
 #'managed-desktop-surface-stop)

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
            :cwd cwd
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
