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
(load (merge-pathnames #P"tests/smoke.lisp" *project-dir*))
(load (merge-pathnames #P"tests/performance.lisp" *project-dir*))
(uiop:symbol-call :sbcl-agent/tests :run-performance-benchmarks)
(sb-ext:exit :code 0)
