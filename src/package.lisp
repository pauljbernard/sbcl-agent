(defpackage #:tutor-codex
  (:use #:cl)
  (:import-from #:uiop
                #:command-line-arguments
                #:getcwd
                #:getenv)
  (:export #:main))

(defpackage #:tutor-codex-user
  (:use #:cl))

(in-package #:tutor-codex)
