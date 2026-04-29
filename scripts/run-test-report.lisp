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
(uiop:symbol-call :sbcl-agent/tests :run-and-write-test-report)
(sb-ext:exit :code 0)
