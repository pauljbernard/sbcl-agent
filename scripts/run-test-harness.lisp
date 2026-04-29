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
  (unless (= (length arguments) 1)
    (format *error-output* "Usage: run-test-harness <harness-id>~%")
    (sb-ext:exit :code 1))
  (let* ((report (uiop:symbol-call :sbcl-agent/tests
                                   :run-and-write-test-report-for-harness
                                   (first arguments)))
         (summary (getf report :summary)))
    (sb-ext:exit :code (if (plusp (or (getf summary :failed) 0)) 1 0))))
