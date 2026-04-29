(defparameter *script-path*
  (or *load-truename* *compile-file-truename* (truename *default-pathname-defaults*)))

(defparameter *project-dir*
  (make-pathname :directory (butlast (pathname-directory *script-path*))
                 :name nil
                 :type nil
                 :defaults *script-path*))

(require :asdf)

(load (merge-pathnames #P"sbcl-agent.asd" *project-dir*))
(asdf:load-system "sbcl-agent/tests")

(let ((arguments (remove "--" (uiop:command-line-arguments) :test #'string=)))
  (unless arguments
    (format *error-output* "Usage: run-test-category <category> [<category> ...]~%")
    (sb-ext:exit :code 1))
  (uiop:symbol-call :sbcl-agent/tests
                    :run-and-write-test-report-for-categories
                    arguments)
  (sb-ext:exit :code 0))
