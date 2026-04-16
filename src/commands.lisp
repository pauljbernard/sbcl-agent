(in-package #:tutor-codex)

(defstruct command
  kind
  form
  arguments)

(defun command-operator-symbol (form)
  (and (consp form)
       (symbolp (first form))
       (string-downcase (symbol-name (first form)))))

(defun normalize-form-command (form)
  (let ((operator (command-operator-symbol form)))
    (cond
      ((or (null operator)
           (not (member operator '("ask" "plan" "tool" "help" "approve" "patch" "execute-actions"
                                   "session/save" "session/load" "session/reset" "describe-session")
                        :test #'string=)))
       (make-command :kind :eval :form form :arguments (list form)))
      ((string= operator "ask")
       (make-command :kind :ask :form form :arguments (rest form)))
      ((string= operator "plan")
       (make-command :kind :plan :form form :arguments (rest form)))
      ((string= operator "tool")
       (make-command :kind :tool :form form :arguments (rest form)))
      ((string= operator "help")
       (make-command :kind :help :form form :arguments (rest form)))
      ((string= operator "approve")
       (make-command :kind :approve :form form :arguments (rest form)))
      ((string= operator "patch")
       (make-command :kind :patch :form form :arguments (rest form)))
      ((string= operator "execute-actions")
       (make-command :kind :execute-actions :form form :arguments (rest form)))
      ((string= operator "session/save")
       (make-command :kind :session-save :form form :arguments (rest form)))
      ((string= operator "session/load")
       (make-command :kind :session-load :form form :arguments (rest form)))
      ((string= operator "session/reset")
       (make-command :kind :session-reset :form form :arguments (rest form)))
      ((string= operator "describe-session")
       (make-command :kind :describe-session :form form :arguments (rest form)))
      (t
       (make-command :kind :eval :form form :arguments (list form))))))

(defun command-summary (command)
  (list :kind (command-kind command)
        :form (command-form command)
        :arguments (command-arguments command)))
