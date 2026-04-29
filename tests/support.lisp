(in-package #:sbcl-agent/tests)

(defun assert-true (condition message)
  (unless condition
    (error "Test failed: ~A" message)))

(defun assert-equal (expected actual message)
  (unless (equal expected actual)
    (error "Test failed: ~A~%Expected: ~S~%Actual: ~S" message expected actual)))

(defun assert-signals-error (thunk substring message)
  (handler-case
      (progn
        (funcall thunk)
        (error "Test failed: ~A~%Expected an error containing ~S" message substring))
    (error (condition)
      (assert-true (search substring (princ-to-string condition))
                   message))))

(defun wait-for (predicate &key (timeout-seconds 3.0) (sleep-seconds 0.05))
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout-seconds internal-time-units-per-second))))
    (loop until (funcall predicate)
          do (when (> (get-internal-real-time) deadline)
               (error "Timed out waiting for condition"))
             (sleep sleep-seconds))))

(defun run-command (program arguments &key directory)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (let ((process (sb-ext:run-program program
                                       arguments
                                       :search t
                                       :input nil
                                       :output stdout
                                       :error stderr
                                       :wait t
                                       :directory directory)))
      (values (sb-ext:process-exit-code process)
              (get-output-stream-string stdout)
              (get-output-stream-string stderr)))))

(defun run-command-with-input (program arguments input &key directory)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream))
        (stdin (make-string-input-stream input)))
    (let ((process (sb-ext:run-program program
                                       arguments
                                       :search t
                                       :input stdin
                                       :output stdout
                                       :error stderr
                                       :wait t
                                       :directory directory)))
      (values (sb-ext:process-exit-code process)
              (get-output-stream-string stdout)
              (get-output-stream-string stderr)))))

(defun with-captured-output (thunk)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (let ((*standard-output* stdout)
          (*error-output* stderr))
      (values (funcall thunk)
              (get-output-stream-string stdout)
              (get-output-stream-string stderr)))))

(defun current-workspace-root ()
  (namestring (uiop:ensure-directory-pathname (uiop:getcwd))))

(defun make-test-session (&key (cwd (current-workspace-root)))
  (let* ((session (sbcl-agent::make-default-session :cwd cwd))
         (environment (sbcl-agent::make-default-environment :storage-root cwd
                                                            :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    session))

(defun make-temporary-directory (template)
  (multiple-value-bind (exit-code stdout stderr)
      (run-command "mktemp" (list "-d" template))
    (assert-equal 0 exit-code
                  (format nil "mktemp should succeed for template ~A~@[ (~A)~]" template stderr))
    (let ((path (string-right-trim '(#\Newline #\Return #\Space #\Tab) stdout)))
      (assert-true (> (length path) 0)
                   (format nil "mktemp should return a path for template ~A" template))
      (uiop:ensure-directory-pathname path))))

(defun with-fake-command-line-arguments (arguments thunk)
  (let ((original (symbol-function 'uiop:command-line-arguments)))
    (unwind-protect
         (progn
           (setf (symbol-function 'uiop:command-line-arguments)
                 (lambda () arguments))
           (funcall thunk))
      (setf (symbol-function 'uiop:command-line-arguments) original))))

(defun run-sandbox-main-with-arguments (arguments)
  (with-fake-command-line-arguments
      arguments
    (lambda ()
      (with-captured-output
        (lambda ()
          (sbcl-agent::sandbox-worker-main))))))

(defun run-main-command (arguments)
  (with-fake-command-line-arguments
      arguments
    (lambda ()
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::main)))
        (values stdout stderr status)))))

(defun rewrite-platform-package-app-display-surface-kind (path app-id display-surface-kind
                                                          &key backend-profile-id)
  (labels ((set-entry-value (entry key value)
             (cond
               ((and (listp entry) (keywordp (first entry)))
                (setf (getf entry key) value)
                entry)
               ((listp entry)
                (let* ((json-key (etypecase key
                                   (keyword (string-downcase
                                             (substitute #\_ #\- (symbol-name key))))
                                   (string key)))
                       (cell (assoc json-key entry :test #'string=)))
                  (if cell
                      (setf (cdr cell) value)
                      (nconc entry (list (cons json-key value))))
                  entry))
               (t
                entry))))
    (let* ((descriptor (sbcl-agent::platform-normalize-integrity-payload
                        (sbcl-agent::parse-platform-package-file path)))
           (manifest (getf descriptor :manifest))
           (compatibility-apps (getf manifest :compatibility-apps))
           (entry (find app-id
                        compatibility-apps
                        :key (lambda (item) (getf item :app-id))
                        :test #'string=))
           (display-value display-surface-kind))
      (assert-true entry
                   (format nil "platform package should contain compatibility app ~A" app-id))
      (set-entry-value entry :display-surface-kind display-value)
      (when backend-profile-id
        (set-entry-value entry :backend-profile-id backend-profile-id))
      (setf (getf descriptor :integrity)
            (sbcl-agent::platform-integrity-data descriptor))
      (with-open-file (stream path
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write-string (sbcl-agent::emit-json
                       (sbcl-agent::platform-json-safe-value descriptor))
                      stream))
      path)))

(defun make-test-git-repo ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-git-XXXXXX"))
         (ignore (ensure-directories-exist root))
         (readme (merge-pathnames #P"README.md" root)))
    (declare (ignore ignore))
    (multiple-value-bind (init-exit init-out init-err)
        (run-command "git" (list "init") :directory root)
      (declare (ignore init-out))
      (assert-equal 0 init-exit "git init should succeed in the temp repo")
      (assert-true (or (string= "" init-err)
                       (search "hint:" init-err))
                   "git init should only emit standard hint text in the temp repo"))
    (with-open-file (stream readme :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "sandbox git baseline\n" stream))
    (multiple-value-bind (add-exit add-out add-err)
        (run-command "git"
                     (list "-c" "user.name=pauljbernard"
                           "-c" "user.email=pauljbernard@example.com"
                           "add" "README.md")
                     :directory root)
      (declare (ignore add-out add-err))
      (assert-equal 0 add-exit "git add should succeed in the temp repo setup"))
    (multiple-value-bind (commit-exit commit-out commit-err)
        (run-command "git"
                     (list "-c" "user.name=pauljbernard"
                           "-c" "user.email=pauljbernard@example.com"
                           "commit" "-m" "Baseline")
                     :directory root)
      (declare (ignore commit-out commit-err))
      (assert-equal 0 commit-exit "baseline git commit should succeed in the temp repo setup"))
    (with-open-file (stream readme :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "sandbox git test\n" stream))
    root))
