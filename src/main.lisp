(in-package #:tutor-codex)

(defun print-help ()
  (format t "tutor-codex ~A~%" "0.1.0")
  (format t "Usage: tutor-codex <command> [args]~%~%")
  (format t "Commands:~%")
  (format t "  chat               Start the Lisp-native interactive shell.~%")
  (format t "  exec <cmd...>      Run a shell command from the current directory.~%")
  (format t "  doctor             Print runtime and configuration diagnostics.~%")
  (format t "  help               Show this message.~%"))

(defun normalize-arguments (arguments)
  (if (and arguments (string= (first arguments) "--"))
      (rest arguments)
      arguments))

(defun doctor-command (config)
  (let ((session (ensure-session)))
    (format t "Runtime: SBCL~%")
    (format t "Provider: ~A~%" (config-provider config))
    (format t "Model: ~A~%" (config-model config))
    (format t "Working directory: ~A~%" (config-working-directory config))
    (format t "Shell package: ~A~%" (package-name *shell-package*))
    (format t "Session id: ~A~%" (agent-session-id session))
    (format t "Session events: ~D~%" (length (agent-session-events session)))
    (format t "Session plan: ~A~%" (or (agent-session-plan session) "<none>"))
    (format t "Pending assistant actions: ~D~%" (length (agent-session-pending-actions session)))
    (format t "Queued tasks: ~D~%" (count :queued (agent-session-tasks session) :key #'task-status))
    (format t "Active workers: ~D~%" (active-worker-count session))
    (format t "Approved policies: ~S~%" (session-approved-policies session))
    (format t "Capability grants: ~S~%" (session-capability-grants-summary session))
    (format t "Sandbox profiles: ~S~%" (mapcar #'sandbox-profile-id *sandbox-profiles*))
    (format t "Git tools registered: ~:[no~;yes~]~%"
            (and (find-tool :git/status) (find-tool :git/commit)))
    (format t "API base configured: ~:[no~;yes~]~%" (not (null (config-api-base config))))
    (format t "API key present: ~:[no~;yes~]~%" (config-api-key-present-p config))
    0))

(defun exec-command (arguments)
  (unless arguments
    (error "exec requires at least one shell argument"))
  (let* ((program (first arguments))
         (process (sb-ext:run-program program
                                      (rest arguments)
                                      :search t
                                      :input *standard-input*
                                      :output *standard-output*
                                      :error *error-output*
                                      :wait t)))
    (sb-ext:process-exit-code process)))

(defun dispatch-command (config arguments)
  (let ((command (or (first arguments) "help")))
    (cond
      ((string= command "help")
       (print-help)
       0)
      ((string= command "doctor")
       (doctor-command config))
      ((string= command "chat")
       (start-shell (make-provider config) (ensure-session)))
      ((string= command "exec")
       (exec-command (rest arguments)))
      (t
       (format *error-output* "Unknown command: ~A~%~%" command)
       (print-help)
       1))))

(defun main ()
  (let* ((config (load-config))
         (arguments (normalize-arguments (command-line-arguments)))
         (status (dispatch-command config arguments)))
    (finish-output *standard-output*)
    (finish-output *error-output*)
    status))
