(in-package #:sbcl-agent)

(defun print-help ()
  (format t "sbcl-agent ~A~%" "0.1.0")
  (format t "Usage: sbcl-agent <command> [args]~%~%")
  (format t "Commands:~%")
  (format t "  chat [options]     Start the Lisp-native interactive shell.~%")
  (format t "                     Options: -i, --provider NAME, --model NAME, --api-base URL, --cwd PATH~%")
  (format t "  exec <cmd...>      Run a shell command from the current directory.~%")
  (format t "  doctor             Print runtime and configuration diagnostics.~%")
  (format t "  help               Show this message.~%"))

(defstruct chat-options
  (default-stream-p nil :type boolean)
  (provider nil :type (or null string))
  (model nil :type (or null string))
  (api-base nil :type (or null string))
  (working-directory nil :type (or null string)))

(defun normalize-arguments (arguments)
  (if (and arguments (string= (first arguments) "--"))
      (rest arguments)
      arguments))

(defun require-option-value (name remaining-arguments)
  (let ((value (first remaining-arguments)))
    (unless value
      (error "Missing value for ~A" name))
    value))

(defun parse-chat-arguments (arguments)
  (let ((default-stream-p nil)
        (provider nil)
        (model nil)
        (api-base nil)
        (working-directory nil))
    (loop while arguments
          for argument = (pop arguments)
          do (cond
               ((or (string= argument "-i")
                    (string= argument "--interactive-stream"))
                (setf default-stream-p t))
               ((string= argument "--provider")
                (setf provider (require-option-value argument arguments))
                (pop arguments))
               ((string= argument "--model")
                (setf model (require-option-value argument arguments))
                (pop arguments))
               ((string= argument "--api-base")
                (setf api-base (require-option-value argument arguments))
                (pop arguments))
               ((or (string= argument "--cwd")
                    (string= argument "--working-directory"))
                (setf working-directory (require-option-value argument arguments))
                (pop arguments))
               (t
                (error "Unknown chat option ~A" argument))))
    (make-chat-options :default-stream-p default-stream-p
                       :provider provider
                       :model model
                       :api-base api-base
                       :working-directory working-directory)))

(defun session-for-chat-config (config)
  (or *current-session*
      (setf *current-session*
            (make-default-session :cwd (config-working-directory config)))))

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
    (format t "Work items: ~D~%" (length (agent-session-work-items session)))
    (format t "Workflow records: ~D~%" (length (agent-session-workflow-records session)))
    (let ((wait-summary (session-wait-summary session))
          (operator-status (session-operator-status session))
          (replay-groups (session-validator-replay-groups session))
          (image-reconciliations (session-image-reconciliation-summary session)))
      (format t "Blocked work items: ~D~%" (getf wait-summary :blocked-count))
      (format t "Blocked summary: ~S~%" (getf wait-summary :by-reason))
      (format t "Operator status: ready=~D blocked=~D quarantined=~D image-only=~D durable=~D~%"
              (getf operator-status :ready-count)
              (getf operator-status :blocked-count)
              (getf operator-status :quarantined-count)
              (getf operator-status :image-only-count)
              (getf operator-status :durable-count))
      (format t "Validator replay groups: ~D~%" (length replay-groups))
      (format t "Image reconciliations: ~D~%" (length image-reconciliations)))
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
       (let* ((chat-options (parse-chat-arguments (rest arguments)))
              (chat-config (config-with-overrides config
                                                 :provider (chat-options-provider chat-options)
                                                 :model (chat-options-model chat-options)
                                                 :api-base (chat-options-api-base chat-options)
                                                 :working-directory (chat-options-working-directory chat-options))))
         (start-shell (make-provider chat-config)
                      (session-for-chat-config chat-config)
                      :default-stream-p (chat-options-default-stream-p chat-options))))
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
