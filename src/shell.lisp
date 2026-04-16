(in-package #:tutor-codex)

(defparameter *shell-package* (find-package '#:tutor-codex-user))

(defun print-shell-help ()
  (format t "Lisp shell commands:~%")
  (format t "  (ask \"prompt\")                   Send a prompt to the configured provider and stage proposed actions.~%")
  (format t "  (execute-actions)                  Execute the currently staged assistant actions.~%")
  (format t "  (plan \"goal\")                    Set the current session plan goal.~%")
  (format t "  (approve :process-run)             Grant a policy approval to the current session.~%")
  (format t "  (tool :fs/read :path \"file\")     Read a workspace file.~%")
  (format t "  (tool :fs/list :path \"dir\")      List a workspace directory.~%")
  (format t "  (tool :proc/run :argv '(...))       Run a local process after approval.~%")
  (format t "  (patch '((:write \"file\" \"...\"))) Apply a patch after workspace-write approval.~%")
  (format t "  (session/save \"path\")            Persist the current session as an s-expression.~%")
  (format t "  (session/load \"path\")            Load a persisted session into the current image.~%")
  (format t "  (session/reset)                    Replace the current session with a fresh one.~%")
  (format t "  (describe-session)                 Print a summary of the current session state.~%")
  (format t "  (help)                             Show this message.~%")
  (format t "  Any other form is evaluated in the TUTOR-CODEX-USER package.~%"))

(defun shell-prompt (session)
  (format *query-io* "~A[~A]> "
          (package-name *shell-package*)
          (agent-session-id session))
  (finish-output *query-io*))

(defun read-shell-form (session)
  (shell-prompt session)
  (read *query-io* nil :eof))

(defun eval-user-form (form)
  (let ((*package* *shell-package*))
    (eval form)))

(defun execute-tool-command (arguments session)
  (unless arguments
    (error "TOOL requires a tool id"))
  (let ((tool-id (first arguments))
        (tool-args (rest arguments)))
    (unless (keywordp tool-id)
      (error "TOOL id must be a keyword, got ~S" tool-id))
    (apply #'invoke-tool tool-id session tool-args)))

(defun execute-approve-command (arguments session)
  (let ((policy (first arguments)))
    (unless (keywordp policy)
      (error "APPROVE requires a keyword policy"))
    (approve-policy session policy)
    (list :approved policy :approved-policies (agent-session-approved-policies session))))

(defun execute-patch-command (arguments session)
  (let ((operations (first arguments)))
    (apply-patch-operations session operations)))

(defun stage-response-actions (response session)
  (let ((actions (assistant-response-actions response)))
    (when actions
      (stage-pending-actions session actions))
    actions))

(defun execute-pending-actions-command (session)
  (let ((actions (agent-session-pending-actions session)))
    (unless actions
      (error "No pending assistant actions are staged in the current session"))
    (let ((results (execute-assistant-action-list actions session)))
      (clear-pending-actions session)
      results)))

(defun execute-session-save-command (arguments session)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "SESSION/SAVE requires a string path"))
    (save-session session path)
    (list :saved path :summary (session-summary session))))

(defun execute-session-load-command (arguments)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "SESSION/LOAD requires a string path"))
    (let ((session (load-session path)))
      (values (list :loaded path :summary (session-summary session)) session))))

(defun execute-command (command provider &optional session)
  (let ((active-session (ensure-session session)))
    (append-session-event active-session :command (command-summary command))
    (case (command-kind command)
      (:eval
       (let ((result (eval-user-form (command-form command))))
         (append-transcript-entry active-session :user (command-form command))
         (append-transcript-entry active-session :system result)
         (values result :eval active-session)))
      (:ask
       (let ((prompt (first (command-arguments command))))
         (unless (stringp prompt)
           (error "ASK requires a single string prompt"))
         (append-transcript-entry active-session :user prompt)
         (let* ((response (send-prompt provider prompt active-session))
                (staged-actions (stage-response-actions response active-session)))
           (append-transcript-entry active-session :assistant (assistant-response->string response))
           (append-session-event active-session :assistant-response response)
           (values (list :response response
                         :staged-action-count (length staged-actions))
                   :ask
                   active-session))))
      (:execute-actions
       (let ((result (execute-pending-actions-command active-session)))
         (values result :execute-actions active-session)))
      (:plan
       (let ((goal (first (command-arguments command))))
         (unless (stringp goal)
           (error "PLAN requires a single string goal"))
         (update-session-plan active-session goal)
         (values (format nil "Current plan: ~A" goal) :plan active-session)))
      (:approve
       (let ((result (execute-approve-command (command-arguments command) active-session)))
         (values result :approve active-session)))
      (:tool
       (let ((result (execute-tool-command (command-arguments command) active-session)))
         (append-transcript-entry active-session :tool result)
         (values result :tool active-session)))
      (:patch
       (let ((result (execute-patch-command (command-arguments command) active-session)))
         (append-transcript-entry active-session :patch result)
         (values result :patch active-session)))
      (:session-save
       (let ((result (execute-session-save-command (command-arguments command) active-session)))
         (values result :session-save active-session)))
      (:session-load
       (multiple-value-bind (result loaded-session)
           (execute-session-load-command (command-arguments command))
         (values result :session-load loaded-session)))
      (:session-reset
       (let ((fresh-session (reset-session active-session)))
         (values (list :reset (agent-session-id fresh-session)
                       :summary (session-summary fresh-session))
                 :session-reset
                 fresh-session)))
      (:describe-session
       (values (session-summary active-session) :describe-session active-session))
      (:help
       (print-shell-help)
       (values nil :help active-session))
      (t
       (error "Unsupported command kind ~S" (command-kind command))))))

(defun print-shell-result (result kind)
  (case kind
    (:help nil)
    (:ask
     (let ((response (getf result :response))
           (staged-count (getf result :staged-action-count)))
       (format t "assistant> ~A~%" (assistant-response->string response))
       (when (assistant-response-actions response)
         (format t "assistant-actions> ~S~%" (assistant-response-actions response))
         (format t "assistant-actions-staged> ~D~%" staged-count))))
    (:execute-actions
     (format t "assistant-action-results> ~S~%" result))
    (:plan
     (format t "planner> ~A~%" result))
    (:approve
     (format t "approval> ~S~%" result))
    (:tool
     (format t "tool> ~S~%" result))
    (:patch
     (format t "patch> ~S~%" result))
    (:session-save
     (format t "session> ~S~%" result))
    (:session-load
     (format t "session> ~S~%" result))
    (:session-reset
     (format t "session> ~S~%" result))
    (:describe-session
     (format t "session> ~S~%" result))
    (t
     (format t "=> ~S~%" result))))

(defun start-shell (provider &optional session)
  (let ((active-session (ensure-session session)))
    (format t "Starting Lisp-native shell with provider ~A.~%" (provider-name provider))
    (format t "Session: ~A~%" (agent-session-id active-session))
    (format t "Enter (help) for commands. Press Ctrl-D to exit.~%")
    (loop
      for form = (read-shell-form active-session)
      do (cond
           ((eq form :eof)
            (format t "~%")
            (return 0))
           (t
            (handler-case
                (multiple-value-bind (result kind updated-session)
                    (execute-command (normalize-form-command form) provider active-session)
                  (setf active-session updated-session
                        *current-session* updated-session)
                  (print-shell-result result kind))
              (error (condition)
                (format *error-output* "error> ~A~%" condition))))))))
