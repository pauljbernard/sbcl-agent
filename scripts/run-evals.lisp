(defparameter *script-path*
  (or *load-truename* *compile-file-truename* (truename *default-pathname-defaults*)))

(defparameter *project-dir*
  (make-pathname :directory (butlast (pathname-directory *script-path*))
                 :name nil
                 :type nil
                 :defaults *script-path*))

(defparameter *cache-root*
  (merge-pathnames #P"tmp/lisp-cache/" *project-dir*))

(ensure-directories-exist *cache-root*)
(ignore-errors (require :sb-posix))
(let ((setenv-symbol (and (find-package :sb-posix)
                          (find-symbol "SETENV" :sb-posix))))
  (when setenv-symbol
    (funcall setenv-symbol "XDG_CACHE_HOME" (namestring *cache-root*) 1)))

(require :asdf)

(load (merge-pathnames #P"sbcl-agent.asd" *project-dir*))
(asdf:load-system :sbcl-agent)
(load (merge-pathnames #P"tests/package.lisp" *project-dir*))
(load (merge-pathnames #P"tests/support.lisp" *project-dir*))
(load (merge-pathnames #P"tests/provider-support.lisp" *project-dir*))
(load (merge-pathnames #P"tests/evals.lisp" *project-dir*))
(uiop:symbol-call :sbcl-agent/tests :run-internal-evaluations)
(sb-ext:exit :code 0)
