(defparameter *script-path*
  (or *load-truename* *compile-file-truename* (truename *default-pathname-defaults*)))

(defparameter *project-dir*
  (make-pathname :directory (butlast (pathname-directory *script-path*))
                 :name nil
                 :type nil
                 :defaults *script-path*))

(defparameter *coverage-dir*
  (merge-pathnames #P"tmp/coverage/" *project-dir*))

(require :asdf)
(require :sb-cover)

(load (merge-pathnames #P"sbcl-agent.asd" *project-dir*))

(declaim (optimize (sb-c:store-coverage-data 3)))

(asdf:operate 'asdf:load-op :sbcl-agent :force t)
(asdf:operate 'asdf:load-op :sbcl-agent/tests :force t)
(uiop:symbol-call :sbcl-agent/tests :run-all-tests)

(ensure-directories-exist *coverage-dir*)
(sb-cover:report *coverage-dir*
                 :if-matches (lambda (path)
                               (search "/src/" path)))

(format t "Coverage report written to ~A~%" (namestring (merge-pathnames #P"cover-index.html" *coverage-dir*)))
(sb-ext:exit :code 0)
