(defparameter *script-path*
  (or *load-truename* *compile-file-truename* (truename *default-pathname-defaults*)))

(defparameter *project-dir*
  (make-pathname :directory (butlast (pathname-directory *script-path*))
                 :name nil
                 :type nil
                 :defaults *script-path*))

(require :asdf)

(load (merge-pathnames #P"sbcl-agent.asd" *project-dir*))
(asdf:load-system :sbcl-agent)
(load (merge-pathnames #P"tests/package.lisp" *project-dir*))
(load (merge-pathnames #P"tests/support.lisp" *project-dir*))
(load (merge-pathnames #P"tests/provider-support.lisp" *project-dir*))
(load (merge-pathnames #P"tests/performance.lisp" *project-dir*))

(let ((summary (uiop:symbol-call :sbcl-agent/tests :benchmark-environment-image-save-load)))
  (format t "environment-image-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
          (* 1000.0 (getf summary :save-seconds))
          (* 1000.0 (getf summary :load-seconds))
          (* 1000.0 (getf summary :total-seconds))))

(sb-ext:exit :code 0)
