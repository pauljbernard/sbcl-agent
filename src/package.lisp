(defpackage #:sbcl-agent
  (:use #:cl)
  (:import-from #:uiop
                #:command-line-arguments
                #:getcwd
                #:getenv)
  (:export #:main))

(defpackage #:sbcl-agent-user
  (:use #:cl))

(in-package #:sbcl-agent)
