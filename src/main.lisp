(in-package #:sbcl-agent)

(defun print-help ()
  (format t "sbcl-agent ~A~%" "0.1.0")
  (format t "Usage: sbcl-agent <command> [args]~%~%")
  (format t "Commands:~%")
  (format t "  chat [options]     Start the Lisp-native interactive shell.~%")
  (format t "                     Options: -i, --provider NAME, --model NAME, --api-base URL, --cwd PATH~%")
  (format t "  exec <cmd...>      Run a shell command from the current directory.~%")
  (format t "  rgp <subcommand>   Execute non-interactive governed runtime operations for RGP.~%")
  (format t "  doctor             Print runtime and configuration diagnostics.~%")
  (format t "  help               Show this message.~%"))

(defstruct chat-options
  (default-stream-p nil :type boolean)
  (provider nil :type (or null string))
  (model nil :type (or null string))
  (api-base nil :type (or null string))
  (working-directory nil :type (or null string)))

(defstruct rgp-options
  subcommand
  environment-path
  output-path
  working-directory
  request-id
  agent-session-id
  tenant-id
  integration-id
  projection-id
  work-item-id
  policy
  reason
  note)

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

(defun parse-rgp-keyword (value)
  (unless (stringp value)
    (error "Expected a string keyword designator"))
  (intern (string-upcase value) "KEYWORD"))

(defun parse-rgp-arguments (arguments)
  (let ((subcommand (first arguments))
        (remaining (rest arguments))
        (environment-path nil)
        (output-path nil)
        (working-directory nil)
        (request-id nil)
        (agent-session-id nil)
        (tenant-id nil)
        (integration-id nil)
        (projection-id nil)
        (work-item-id nil)
        (policy nil)
        (reason nil)
        (note nil))
    (unless subcommand
      (error "rgp requires a subcommand"))
    (loop while remaining
          for argument = (pop remaining)
          do (cond
               ((string= argument "--environment")
                (setf environment-path (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--output")
                (setf output-path (require-option-value argument remaining))
                (pop remaining))
               ((or (string= argument "--cwd")
                    (string= argument "--working-directory"))
                (setf working-directory (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--request-id")
                (setf request-id (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--agent-session-id")
                (setf agent-session-id (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--tenant-id")
                (setf tenant-id (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--integration-id")
                (setf integration-id (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--projection-id")
                (setf projection-id (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--work-item-id")
                (setf work-item-id (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--policy")
                (setf policy (parse-rgp-keyword (require-option-value argument remaining)))
                (pop remaining))
               ((string= argument "--reason")
                (setf reason (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--note")
                (setf note (require-option-value argument remaining))
                (pop remaining))
               (t
                (error "Unknown rgp option ~A" argument))))
    (make-rgp-options :subcommand subcommand
                      :environment-path environment-path
                      :output-path output-path
                      :working-directory working-directory
                      :request-id request-id
                      :agent-session-id agent-session-id
                      :tenant-id tenant-id
                      :integration-id integration-id
                      :projection-id projection-id
                      :work-item-id work-item-id
                      :policy policy
                      :reason reason
                      :note note)))

(defun ensure-rgp-path-parent (path)
  (when path
    (uiop:ensure-all-directories-exist (list path)))
  path)

(defun load-or-create-rgp-environment (options)
  (let* ((environment-path (rgp-options-environment-path options))
         (working-directory (or (rgp-options-working-directory options)
                                (config-working-directory (load-config)))))
    (unless environment-path
      (error "rgp requires --environment"))
    (ensure-rgp-path-parent environment-path)
    (let ((environment (if (probe-file environment-path)
                           (load-environment environment-path)
                           (make-default-environment :storage-root working-directory))))
      (setf *current-environment* environment)
      (environment-session environment)
      environment)))

(defun write-rgp-result (value)
  (format t "~A~%" (emit-json (json-safe-value value)))
  (finish-output))

(defun rgp-command-bind (options)
  (let* ((environment (load-or-create-rgp-environment options))
         (session (environment-session environment)))
    (bind-environment-to-rgp session
                             :tenant-id (rgp-options-tenant-id options)
                             :request-id (rgp-options-request-id options)
                             :agent-session-id (rgp-options-agent-session-id options)
                             :integration-id (rgp-options-integration-id options)
                             :projection-id (rgp-options-projection-id options)
                             :environment environment)
    (save-environment environment (rgp-options-environment-path options))
    (write-rgp-result
     (list :status "bound"
           :environment_path (rgp-options-environment-path options)
           :binding (rgp-binding-summary environment)
           :governed_runtime (environment-rgp-runtime-summary environment)))
    0))

(defun rgp-command-show (options)
  (let ((environment (load-or-create-rgp-environment options)))
    (write-rgp-result (environment-rgp-snapshot environment))
    0))

(defun rgp-command-export (options)
  (let ((environment (load-or-create-rgp-environment options))
        (output-path (rgp-options-output-path options)))
    (unless output-path
      (error "rgp export requires --output"))
    (ensure-rgp-path-parent output-path)
    (write-rgp-result (export-environment-rgp-snapshot output-path environment))
    0))

(defun rgp-command-artifacts (options)
  (let ((environment (load-or-create-rgp-environment options)))
    (write-rgp-result (environment-rgp-artifact-summaries environment))
    0))

(defun rgp-command-approvals (options)
  (let ((environment (load-or-create-rgp-environment options)))
    (write-rgp-result (environment-rgp-approval-summaries environment))
    0))

(defun rgp-command-approve (options)
  (let* ((environment (load-or-create-rgp-environment options))
         (session (environment-session environment))
         (work-item-id (rgp-options-work-item-id options))
         (policy (rgp-options-policy options)))
    (unless work-item-id
      (error "rgp approve requires --work-item-id"))
    (unless policy
      (error "rgp approve requires --policy"))
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (request-work-item-approval session work-item policy :reason (rgp-options-reason options))
      (save-environment environment (rgp-options-environment-path options))
      (write-rgp-result
       (list :status "approved"
             :environment_path (rgp-options-environment-path options)
             :work_item (enriched-work-item-detail session work-item)
             :approval (work-item-wait-report session work-item))))
    0))

(defun rgp-command-resume (options)
  (let* ((environment (load-or-create-rgp-environment options))
         (session (environment-session environment))
         (work-item-id (rgp-options-work-item-id options)))
    (unless work-item-id
      (error "rgp resume requires --work-item-id"))
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (resume-work-item session work-item :note (rgp-options-note options))
      (save-environment environment (rgp-options-environment-path options))
      (write-rgp-result
       (list :status "resumed"
             :environment_path (rgp-options-environment-path options)
             :work_item (enriched-work-item-detail session work-item)
             :approval (work-item-wait-report session work-item))))
    0))

(defun rgp-command (config arguments)
  (declare (ignore config))
  (let* ((options (parse-rgp-arguments arguments))
         (subcommand (string-downcase (rgp-options-subcommand options))))
    (cond
      ((string= subcommand "bind")
       (rgp-command-bind options))
      ((string= subcommand "show")
       (rgp-command-show options))
      ((string= subcommand "export")
       (rgp-command-export options))
      ((string= subcommand "artifacts")
       (rgp-command-artifacts options))
      ((string= subcommand "approvals")
       (rgp-command-approvals options))
      ((string= subcommand "approve")
       (rgp-command-approve options))
      ((string= subcommand "resume")
       (rgp-command-resume options))
      (t
       (error "Unknown rgp subcommand ~A" subcommand)))))

(defun session-for-chat-config (config)
  (let ((environment (or *current-environment*
                         (setf *current-environment*
                               (make-default-environment
                                :storage-root (config-working-directory config)
                                :session (or *current-session*
                                             (setf *current-session*
                                                   (make-default-session :cwd (config-working-directory config)))))))))
    (or (environment-session environment)
        (bind-session-to-environment
         (make-default-session :cwd (config-working-directory config))
         environment))))

(defun doctor-command (config)
  (let* ((environment (ensure-environment))
         (session (ensure-session))
         (environment-summary (environment-summary environment))
         (artifact-summary (getf environment-summary :artifact-summary)))
    (format t "Runtime: SBCL~%")
    (format t "Environment id: ~A~%" (environment-id environment))
    (format t "Provider: ~A~%" (config-provider config))
    (format t "Model: ~A~%" (config-model config))
    (format t "Working directory: ~A~%" (config-working-directory config))
    (format t "Shell package: ~A~%" (package-name *shell-package*))
    (format t "Session id: ~A~%" (agent-session-id session))
    (format t "Active runtime id: ~A~%" (environment-active-runtime-id environment))
    (format t "Environment events: ~D~%" (getf environment-summary :event-count))
    (format t "Session plan: ~A~%" (or (agent-session-plan session) "<none>"))
    (format t "Pending assistant actions: ~D~%" (length (agent-session-pending-actions session)))
    (format t "Queued tasks: ~D~%" (count :queued (agent-session-tasks session) :key #'task-status))
    (format t "Work items: ~D~%" (getf environment-summary :work-item-count))
    (format t "Artifacts: ~D~%" (getf environment-summary :artifact-count))
    (format t "Artifact evidence: ~S~%" artifact-summary)
    (format t "Workflow records: ~D~%" (getf (getf environment-summary :workflow-state) :workflow-record-count))
    (let ((wait-summary (session-wait-summary session))
          (operator-status (getf environment-summary :operator-status))
          (incident-summary (getf environment-summary :incident-summary))
          (replay-groups (session-validator-replay-groups session))
          (image-reconciliations (session-image-reconciliation-summary session)))
      (format t "Blocked work items: ~D~%" (getf wait-summary :blocked-count))
      (format t "Blocked summary: ~S~%" (getf wait-summary :by-reason))
      (format t "Operator status: ready=~D blocked=~D quarantined=~D image-only=~D durable=~D incidents=~D open-incidents=~D~%"
              (getf operator-status :ready-count)
              (getf operator-status :blocked-count)
              (getf operator-status :quarantined-count)
              (getf operator-status :image-only-count)
              (getf operator-status :durable-count)
              (getf operator-status :incident-count)
              (getf operator-status :open-incident-count))
      (format t "Incidents: total=~D open=~D~%"
              (getf incident-summary :count)
              (getf incident-summary :open-count))
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
      ((string= command "rgp")
       (rgp-command config (rest arguments)))
      ((string= command "chat")
       (let* ((chat-options (parse-chat-arguments (rest arguments)))
              (chat-config (config-with-overrides config
                                                 :provider (chat-options-provider chat-options)
                                                 :model (chat-options-model chat-options)
                                                 :api-base (chat-options-api-base chat-options)
                                                 :working-directory (chat-options-working-directory chat-options))))
         (let ((session (session-for-chat-config chat-config)))
           (ensure-environment)
           (start-shell (make-provider chat-config)
                        session
                        :default-stream-p (chat-options-default-stream-p chat-options)))))
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
