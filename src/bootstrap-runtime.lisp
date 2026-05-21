(defpackage #:sbcl-agent.bootstrap
  (:use #:cl)
  (:export #:bootstrap-common-lisp-package-management
           #:package-management-state
           #:package-management-summary
           #:install-quicklisp-system
           #:run-qlot-command
           #:add-source-registry-entry
           #:update-source-registry-entry
           #:remove-source-registry-entry
           #:add-local-project
           #:remove-local-project))

(in-package #:sbcl-agent.bootstrap)

(defvar *package-management-state* nil)

(defparameter +managed-source-registry-relative-path+ #P".sbcl-agent/source-registry.sexp")
(defparameter +local-projects-root-relative-path+ #P"quicklisp/local-projects/")

(declaim (ftype (function (&key (:project-dir t) (:working-directory t)) t)
                bootstrap-common-lisp-package-management))

(defun package-management-state ()
  *package-management-state*)

(defun normalize-string (value)
  (let ((trimmed (and value (string-trim '(#\Space #\Tab #\Newline #\Return) value))))
    (if (and trimmed (> (length trimmed) 0))
        trimmed
        nil)))

(defun normalize-directory-pathname (pathspec)
  (let ((pathname (pathname pathspec)))
    (if (or (pathname-name pathname) (pathname-type pathname))
        (make-pathname :name nil :type nil :defaults pathname)
        pathname)))

(defun pathname-equal-p (left right)
  (and left
       right
       (string= (namestring left)
                (namestring right))))

(defun unique-pathnames (pathnames)
  (let ((result '()))
    (dolist (pathname pathnames (nreverse result))
      (when (and pathname
                 (not (some (lambda (existing)
                              (pathname-equal-p existing pathname))
                            result)))
        (push pathname result)))))

(defun existing-directory-pathname (pathspec)
  (when pathspec
    (let* ((directory (normalize-directory-pathname pathspec))
           (resolved (probe-file directory)))
      (when resolved
        (normalize-directory-pathname resolved)))))

(defun existing-file-pathname (pathspec)
  (when pathspec
    (let ((resolved (probe-file pathspec)))
      (when (and resolved
                 (pathname-name resolved))
        resolved))))

(defun pathname-parent-directory (pathname)
  (let ((directory (pathname-directory (normalize-directory-pathname pathname))))
    (when (and directory
               (> (length directory) 1))
      (let ((parent (butlast directory)))
        (unless (equal parent directory)
          (make-pathname :directory parent
                         :name nil
                         :type nil
                         :defaults pathname))))))

(defun parent-directories (pathspec)
  (let ((result '())
        (current (existing-directory-pathname pathspec)))
    (loop while current
          do (push current result)
             (setf current (pathname-parent-directory current)))
    (nreverse result)))

(defun path-join (directory relative-path)
  (merge-pathnames relative-path (normalize-directory-pathname directory)))

(defun getenv-string (name)
  #+sbcl (sb-ext:posix-getenv name)
  #-sbcl (declare (ignore name))
  #-sbcl nil)

(defun asdf-symbol (name package-name)
  (or (find-symbol name package-name)
      (error "Unable to resolve ~A from ~A" name package-name)))

(defun asdf-function (name package-name)
  (symbol-function (asdf-symbol name package-name)))

(defun asdf-variable-value (name package-name)
  (symbol-value (asdf-symbol name package-name)))

(defun require-asdf ()
  (require :asdf))

(defun project-root-from-state ()
  (or (and *package-management-state*
           (getf *package-management-state* :project-dir))
      (and *package-management-state*
           (getf *package-management-state* :working-directory))
      (namestring (normalize-directory-pathname *default-pathname-defaults*))))

(defun managed-source-registry-pathname (&optional project-dir)
  (path-join (or project-dir (project-root-from-state))
             +managed-source-registry-relative-path+))

(defun local-projects-root-pathname (&optional project-dir)
  (path-join (or project-dir (project-root-from-state))
             +local-projects-root-relative-path+))

(defun source-registry-managed-entry-strings (&optional project-dir)
  (let ((path (managed-source-registry-pathname project-dir)))
    (if (probe-file path)
        (with-open-file (stream path :direction :input)
          (let ((value (read stream nil '())))
            (remove nil
                    (mapcar #'normalize-string
                            (if (listp value) value '())))))
        '())))

(defun save-source-registry-managed-entry-strings (entries &optional project-dir)
  (let* ((path (managed-source-registry-pathname project-dir))
         (normalized (sort (remove-duplicates
                            (remove nil (mapcar #'normalize-string entries))
                            :test #'string=)
                           #'string<)))
    (ensure-directories-exist path)
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (let ((*print-pretty* t))
        (write normalized :stream stream)))
    normalized))

(defun qlot-project-root (pathspec)
  (find-if (lambda (directory)
             (probe-file (path-join directory #P"qlfile")))
           (reverse (parent-directories pathspec))))

(defun executable-pathname (name)
  (handler-case
      (sb-ext:with-timeout 1
        (let* ((stdout (uiop:run-program (list "which" name)
                                         :output :string
                                         :ignore-error-status t))
               (path (normalize-string stdout)))
          (and path (pathname path))))
    (sb-ext:timeout () nil)
    (error () nil)))

(defun existing-managed-source-registry-directories (project-dir)
  (mapcar #'existing-directory-pathname
          (source-registry-managed-entry-strings project-dir)))

(defun source-registry-directory-candidates (project-dir working-directory)
  (unique-pathnames
   (remove nil
           (append
            (mapcar #'existing-directory-pathname
                    (list project-dir
                          working-directory
                          (and project-dir (path-join project-dir #P"systems/"))
                          (and working-directory (path-join working-directory #P"systems/"))
                          (and project-dir (path-join project-dir #P"vendor/"))
                          (and working-directory (path-join working-directory #P"vendor/"))
                          (and project-dir (path-join project-dir #P"quicklisp/local-projects/"))
                          (and working-directory (path-join working-directory #P"quicklisp/local-projects/"))))
            (let ((home (getenv-string "HOME")))
              (when home
                (mapcar #'existing-directory-pathname
                        (list (path-join home #P"quicklisp/local-projects/")
                              (path-join home #P".quicklisp/local-projects/")))))
            (existing-managed-source-registry-directories project-dir)))))

(defun qlot-setup-candidates (pathspec)
  (mapcar (lambda (directory)
            (existing-file-pathname (path-join directory #P".qlot/setup.lisp")))
          (parent-directories pathspec)))

(defun quicklisp-setup-candidates (project-dir working-directory)
  (let ((home (getenv-string "HOME")))
    (remove nil
            (mapcar #'existing-file-pathname
                    (append
                     (mapcan (lambda (directory)
                               (when directory
                                 (list (path-join directory #P"quicklisp/setup.lisp")
                                       (path-join directory #P".quicklisp/setup.lisp"))))
                             (list working-directory project-dir))
                     (when home
                       (list (path-join home #P"quicklisp/setup.lisp")
                             (path-join home #P".quicklisp/setup.lisp"))))))))

(defun package-manager-setup-paths (project-dir working-directory)
  (unique-pathnames
   (append (qlot-setup-candidates working-directory)
           (qlot-setup-candidates project-dir)
           (quicklisp-setup-candidates project-dir working-directory))))

(defun initialize-source-registry (directories)
  (when directories
    (let ((parameter `(:source-registry
                       ,@(mapcar (lambda (directory)
                                   `(:tree ,(namestring directory)))
                                 directories)
                       :inherit-configuration)))
      (funcall (asdf-function "INITIALIZE-SOURCE-REGISTRY" "ASDF/SOURCE-REGISTRY")
               parameter)
      parameter)))

(defun register-central-registry-directories (directories)
  (let* ((registry-symbol (asdf-symbol "*CENTRAL-REGISTRY*" "ASDF/SYSTEM-REGISTRY"))
         (registry (symbol-value registry-symbol)))
    (dolist (directory directories)
      (unless (member directory registry :test #'pathname-equal-p)
        (push directory registry)))
    (setf (symbol-value registry-symbol) registry)
    registry))

(defun maybe-load-package-manager-setup (setup-paths)
  (let ((loaded '())
        (manager :asdf))
    (dolist (setup-path setup-paths)
      (load setup-path)
      (push setup-path loaded)
      (if (search ".qlot/" (namestring setup-path) :test #'char-equal)
          (setf manager :qlot)
          (setf manager :quicklisp)))
    (values manager (nreverse loaded))))

(defun bootstrap-state-quicklisp-available-p ()
  (not (null (find-package "QL"))))

(defun source-registry-entry-summary (path)
  (let ((normalized (normalize-string path)))
    (list :entry-id normalized
          :path normalized
          :exists-p (not (null (existing-directory-pathname normalized)))
          :managed-p t)))

(defun local-project-directory-entries (root)
  (when (probe-file root)
    (directory (merge-pathnames #P"*/" (normalize-directory-pathname root)))))

(defun pathname-last-directory-name (pathname)
  (let ((directory (pathname-directory pathname)))
    (when directory
      (string-downcase (princ-to-string (car (last directory)))))))

(defun local-project-entry-summary (pathname)
  (let* ((normalized (normalize-directory-pathname pathname))
         (name (pathname-last-directory-name normalized))
         (resolved (ignore-errors (truename normalized))))
    (list :project-id (or name (namestring normalized))
          :name (or name (namestring normalized))
          :link-path (namestring normalized)
          :path (if resolved
                    (namestring (normalize-directory-pathname resolved))
                    (namestring normalized))
          :exists-p (not (null resolved))
          :managed-p t)))

(defun package-management-summary (&key project-dir working-directory)
  (let* ((state (or *package-management-state*
                    (bootstrap-common-lisp-package-management
                     :project-dir project-dir
                     :working-directory working-directory)))
         (resolved-project-dir (getf state :project-dir))
         (resolved-working-directory (getf state :working-directory))
         (managed-source-registry-path (managed-source-registry-pathname resolved-project-dir))
         (managed-source-registry-entries
           (mapcar #'source-registry-entry-summary
                   (source-registry-managed-entry-strings resolved-project-dir)))
         (local-projects-root (local-projects-root-pathname resolved-project-dir))
         (local-projects
           (mapcar #'local-project-entry-summary
                   (or (local-project-directory-entries local-projects-root) '())))
         (qlot-executable (executable-pathname "qlot"))
         (qlot-root (qlot-project-root (or resolved-working-directory resolved-project-dir))))
    (append
     (copy-list state)
     (list :qlot-available-p (or (not (null qlot-executable))
                                 (not (null qlot-root)))
           :qlot-executable-path (and qlot-executable (namestring qlot-executable))
           :qlot-project-root (and qlot-root (namestring qlot-root))
           :managed-source-registry-path (namestring managed-source-registry-path)
           :managed-source-registry-entry-count (length managed-source-registry-entries)
           :managed-source-registry-entries managed-source-registry-entries
           :local-projects-root (namestring local-projects-root)
           :local-project-count (length local-projects)
           :local-projects local-projects))))

(defun refresh-package-management-state (&key project-dir working-directory)
  (bootstrap-common-lisp-package-management
   :project-dir (or project-dir (project-root-from-state))
   :working-directory (or working-directory
                         (and *package-management-state*
                              (getf *package-management-state* :working-directory))
                         (project-root-from-state))))

(defun quicklisp-quickload-function ()
  (let ((package (find-package "QL")))
    (and package
         (multiple-value-bind (symbol present-p)
             (find-symbol "QUICKLOAD" package)
           (when (and present-p (fboundp symbol))
             (symbol-function symbol))))))

(defun install-quicklisp-system (system-name &key project-dir working-directory)
  (let* ((resolved-system-name (or (normalize-string system-name)
                                   (error "Quicklisp system name is required")))
         (summary (package-management-summary
                   :project-dir project-dir
                   :working-directory working-directory))
         (quickload (quicklisp-quickload-function)))
    (unless quickload
      (error "Quicklisp is not available in the current runtime."))
    (funcall quickload resolved-system-name)
    (setf summary (package-management-summary
                   :project-dir project-dir
                   :working-directory working-directory))
    (list :summary (format nil "Quicklisp loaded ~A." resolved-system-name)
          :system-name resolved-system-name
          :package-management summary
          :loaded-systems (and summary (getf summary :loaded-systems)))))

(defun run-command-capturing-output (argv &key working-directory)
  (let* ((process (uiop:launch-program argv
                                       :directory (or working-directory (project-root-from-state))
                                       :output :stream
                                       :error-output :stream))
         (stdout (uiop:slurp-stream-string (uiop:process-info-output process)))
         (stderr (uiop:slurp-stream-string (uiop:process-info-error-output process)))
         (exit-code (uiop:wait-process process)))
    (list :argv argv
          :stdout stdout
          :stderr stderr
          :exit-code exit-code)))

(defun run-qlot-command (arguments &key project-dir working-directory)
  (let* ((summary (package-management-summary
                   :project-dir project-dir
                   :working-directory working-directory))
         (executable (or (and (getf summary :qlot-executable-path)
                              (namestring (pathname (getf summary :qlot-executable-path))))
                         "qlot"))
         (resolved-working-directory
           (or (getf summary :qlot-project-root)
               working-directory
               project-dir
               (project-root-from-state)))
         (argv (cons executable (remove nil (mapcar #'normalize-string arguments))))
         (result (run-command-capturing-output argv
                                              :working-directory resolved-working-directory)))
    (append result
            (list :summary (format nil "Ran qlot ~{~A~^ ~}." (cdr argv))
                  :package-management (package-management-summary
                                       :project-dir project-dir
                                       :working-directory working-directory)))))

(defun add-source-registry-entry (path &key project-dir working-directory)
  (let* ((resolved-path (or (normalize-string path)
                            (error "Source registry path is required")))
         (entries (source-registry-managed-entry-strings project-dir)))
    (save-source-registry-managed-entry-strings (append entries (list resolved-path))
                                                project-dir)
    (refresh-package-management-state :project-dir project-dir :working-directory working-directory)
    (list :summary (format nil "Added source registry entry ~A." resolved-path)
          :path resolved-path
          :package-management (package-management-summary
                               :project-dir project-dir
                               :working-directory working-directory))))

(defun update-source-registry-entry (old-path new-path &key project-dir working-directory)
  (let* ((resolved-old-path (or (normalize-string old-path)
                                (error "Existing source registry path is required")))
         (resolved-new-path (or (normalize-string new-path)
                                (error "New source registry path is required")))
         (entries (source-registry-managed-entry-strings project-dir)))
    (save-source-registry-managed-entry-strings
     (cons resolved-new-path
           (remove resolved-old-path entries :test #'string=))
     project-dir)
    (refresh-package-management-state :project-dir project-dir :working-directory working-directory)
    (list :summary (format nil "Updated source registry entry ~A -> ~A." resolved-old-path resolved-new-path)
          :old-path resolved-old-path
          :new-path resolved-new-path
          :package-management (package-management-summary
                               :project-dir project-dir
                               :working-directory working-directory))))

(defun remove-source-registry-entry (path &key project-dir working-directory)
  (let ((resolved-path (or (normalize-string path)
                           (error "Source registry path is required"))))
    (save-source-registry-managed-entry-strings
     (remove resolved-path (source-registry-managed-entry-strings project-dir)
             :test #'string=)
     project-dir)
    (refresh-package-management-state :project-dir project-dir :working-directory working-directory)
    (list :summary (format nil "Removed source registry entry ~A." resolved-path)
          :path resolved-path
          :package-management (package-management-summary
                               :project-dir project-dir
                               :working-directory working-directory))))

(defun local-project-link-pathname (project-name &optional project-dir)
  (path-join (local-projects-root-pathname project-dir)
             (parse-namestring project-name)))

(defun add-local-project (path &key name project-dir working-directory)
  (let* ((resolved-path (or (normalize-string path)
                            (error "Local project path is required")))
         (resolved-name (or (normalize-string name)
                            (file-namestring
                             (directory-namestring
                              (namestring (normalize-directory-pathname resolved-path))))
                            (pathname-last-directory-name (pathname resolved-path))
                            (error "Local project name could not be determined")))
         (root (local-projects-root-pathname project-dir))
         (link-path (local-project-link-pathname resolved-name project-dir)))
    (ensure-directories-exist root)
    (when (probe-file link-path)
      (delete-file link-path))
    (uiop:run-program (list "ln" "-sfn" resolved-path (namestring link-path)))
    (refresh-package-management-state :project-dir project-dir :working-directory working-directory)
    (list :summary (format nil "Added local project ~A." resolved-name)
          :name resolved-name
          :path resolved-path
          :package-management (package-management-summary
                               :project-dir project-dir
                               :working-directory working-directory))))

(defun remove-local-project (name &key project-dir working-directory)
  (let* ((resolved-name (or (normalize-string name)
                            (error "Local project name is required")))
         (link-path (local-project-link-pathname resolved-name project-dir)))
    (when (probe-file link-path)
      (delete-file link-path))
    (refresh-package-management-state :project-dir project-dir :working-directory working-directory)
    (list :summary (format nil "Removed local project ~A." resolved-name)
          :name resolved-name
          :package-management (package-management-summary
                               :project-dir project-dir
                               :working-directory working-directory))))

(defun bootstrap-common-lisp-package-management (&key project-dir working-directory)
  (require-asdf)
  (let* ((resolved-project-dir (existing-directory-pathname (or project-dir *default-pathname-defaults*)))
         (resolved-working-directory
           (existing-directory-pathname
            (or working-directory
                resolved-project-dir
                *default-pathname-defaults*)))
         (source-registry-directories
           (source-registry-directory-candidates resolved-project-dir resolved-working-directory))
         (source-registry-parameter
           (initialize-source-registry source-registry-directories))
         (central-registry
           (register-central-registry-directories source-registry-directories))
         (setup-paths
           (package-manager-setup-paths resolved-project-dir resolved-working-directory)))
    (multiple-value-bind (package-manager loaded-setups)
        (maybe-load-package-manager-setup setup-paths)
      (setf *package-management-state*
            (list :package-manager package-manager
                  :project-dir (and resolved-project-dir (namestring resolved-project-dir))
                  :working-directory (and resolved-working-directory
                                          (namestring resolved-working-directory))
                  :loaded-setup-count (length loaded-setups)
                  :loaded-setup-paths (mapcar #'namestring loaded-setups)
                  :source-registry-directory-count (length source-registry-directories)
                  :source-registry-directories (mapcar #'namestring source-registry-directories)
                  :central-registry-count (length central-registry)
                  :central-registry (mapcar #'namestring central-registry)
                  :source-registry-parameter source-registry-parameter
                  :quicklisp-available-p (bootstrap-state-quicklisp-available-p)))
      *package-management-state*)))
