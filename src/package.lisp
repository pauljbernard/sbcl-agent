(defpackage #:tutor-codex
  (:use #:cl)
  (:import-from #:uiop
                #:command-line-arguments
                #:getcwd
                #:getenv
                #:run-program)
  (:export #:main))

(in-package #:tutor-codex)
