(defpackage #:sbcl-agent
  (:use #:cl)
  (:import-from #:uiop
                #:command-line-arguments
                #:getcwd
                #:getenv)
  (:export #:main
           #:kernel-invoke
           #:kernel-inspect
           #:kernel-control
           #:command-kernel-invoke-service
           #:query-kernel-inspect-service
           #:command-kernel-control-service))

(defpackage #:sbcl-agent-user
  (:use #:cl))

(in-package #:sbcl-agent)
