(in-package #:sbcl-agent)

(defun print-help ()
  (format t "sbcl-agent ~A~%" "0.1.0")
  (format t "Usage: sbcl-agent <command> [args]~%~%")
  (format t "Commands:~%")
  (format t "  chat [options]     Start the Lisp-native interactive shell.~%")
  (format t "                     Options: -i, --provider NAME, --model NAME, --api-base URL, --cwd PATH~%")
  (format t "                     Providers: mock, openai-compatible, anthropic, gemini/google, lm-studio, meta-compatible~%")
  (format t "  exec <cmd...>      Run a shell command from the current directory.~%")
  (format t "  provider <subcmd>  Query or mutate provider profiles and routing as JSON service envelopes.~%")
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

(defstruct provider-options
  subcommand
  environment-path
  working-directory
  profile-name
  prompt
  mode
  provider
  model
  fast-model
  api-base
  intents)

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

(defun parse-provider-intents (value)
  (when value
    (remove nil
            (mapcar (lambda (entry)
                      (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) entry)))
                        (unless (string= trimmed "")
                          (parse-rgp-keyword trimmed))))
                    (uiop:split-string value :separator ",")))))

(defun parse-provider-arguments (arguments)
  (let ((subcommand (first arguments))
        (remaining (rest arguments))
        (environment-path nil)
        (working-directory nil)
        (profile-name nil)
        (prompt nil)
        (mode nil)
        (provider nil)
        (model nil)
        (fast-model nil)
        (api-base nil)
        (intents nil))
    (unless subcommand
      (error "provider requires a subcommand"))
    (loop while remaining
          for argument = (pop remaining)
          do (cond
               ((string= argument "--environment")
                (setf environment-path (require-option-value argument remaining))
                (pop remaining))
               ((or (string= argument "--cwd")
                    (string= argument "--working-directory"))
                (setf working-directory (require-option-value argument remaining))
                (pop remaining))
               ((or (string= argument "--profile")
                    (string= argument "--profile-name"))
                (setf profile-name (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--prompt")
                (setf prompt (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--mode")
                (setf mode (parse-rgp-keyword (require-option-value argument remaining)))
                (pop remaining))
               ((string= argument "--provider")
                (setf provider (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--model")
                (setf model (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--fast-model")
                (setf fast-model (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--api-base")
                (setf api-base (require-option-value argument remaining))
                (pop remaining))
               ((string= argument "--intents")
                (setf intents (parse-provider-intents (require-option-value argument remaining)))
                (pop remaining))
               (t
                (error "Unknown provider option ~A" argument))))
    (make-provider-options :subcommand subcommand
                           :environment-path environment-path
                           :working-directory working-directory
                           :profile-name profile-name
                           :prompt prompt
                           :mode mode
                           :provider provider
                           :model model
                           :fast-model fast-model
                           :api-base api-base
                           :intents intents)))

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

(defun write-service-result (response)
  (format t "~A~%" (emit-json (json-safe-value response)))
  (finish-output))

(defun persist-rgp-environment (environment options)
  (let ((environment-path (rgp-options-environment-path options)))
    (when environment-path
      (save-environment environment environment-path)))
  environment)

(defun load-or-create-provider-environment (options &optional config)
  (let* ((environment-path (provider-options-environment-path options))
         (active-config (or config (load-config)))
         (working-directory (or (provider-options-working-directory options)
                                (config-working-directory active-config))))
    (when environment-path
      (ensure-rgp-path-parent environment-path))
    (let ((environment (if (and environment-path (probe-file environment-path))
                           (load-environment environment-path)
                           (make-default-environment :storage-root working-directory))))
      (setf *current-environment* environment)
      (or (environment-session environment)
          (bind-session-to-environment (make-default-session :cwd working-directory)
                                       environment))
      (ensure-environment-provider-profile :environment environment
                                           :config active-config
                                           :profile-name "default")
      environment)))

(defun persist-provider-environment (environment options)
  (let ((environment-path (provider-options-environment-path options)))
    (when environment-path
      (save-environment environment environment-path)))
  environment)

(defun rgp-command-bind (options)
  (let* ((environment (load-or-create-rgp-environment options))
         (session (environment-session environment))
         (response (command-rgp-bind-service session
                                             :tenant-id (rgp-options-tenant-id options)
                                             :request-id (rgp-options-request-id options)
                                             :agent-session-id (rgp-options-agent-session-id options)
                                             :integration-id (rgp-options-integration-id options)
                                             :projection-id (rgp-options-projection-id options)
                                             :environment environment)))
    (persist-rgp-environment environment options)
    (write-rgp-result
     (list :status "bound"
           :environment_path (rgp-options-environment-path options)
           :binding (getf (service-response-data response) :binding)
           :governed_runtime (getf (service-response-data response) :governed-runtime)))
    0))

(defun rgp-command-show (options)
  (let* ((environment (load-or-create-rgp-environment options))
         (session (environment-session environment)))
    (write-rgp-result
     (service-response-data (query-rgp-show-service session environment)))
    0))

(defun rgp-command-export (options)
  (let ((environment (load-or-create-rgp-environment options))
        (session nil)
        (output-path (rgp-options-output-path options)))
    (unless output-path
      (error "rgp export requires --output"))
    (ensure-rgp-path-parent output-path)
    (setf session (environment-session environment))
    (write-rgp-result
     (service-response-data (command-rgp-export-service session output-path environment)))
    0))

(defun rgp-command-artifacts (options)
  (let* ((environment (load-or-create-rgp-environment options))
         (session (environment-session environment)))
    (write-rgp-result
     (service-response-data (query-rgp-artifacts-service session environment)))
    0))

(defun rgp-command-approvals (options)
  (let* ((environment (load-or-create-rgp-environment options))
         (session (environment-session environment)))
    (write-rgp-result
     (service-response-data (query-rgp-approvals-service session environment)))
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
    (let ((response (command-rgp-approve-service session
                                                 work-item-id
                                                 policy
                                                 :reason (rgp-options-reason options)
                                                 :environment environment)))
      (persist-rgp-environment environment options)
      (write-rgp-result
       (list :status "approved"
             :environment_path (rgp-options-environment-path options)
             :work_item (getf (service-response-data response) :work-item)
             :approval (getf (service-response-data response) :approval))))
    0))

(defun rgp-command-resume (options)
  (let* ((environment (load-or-create-rgp-environment options))
         (session (environment-session environment))
         (work-item-id (rgp-options-work-item-id options)))
    (unless work-item-id
      (error "rgp resume requires --work-item-id"))
    (let ((response (command-rgp-resume-service session
                                                work-item-id
                                                :note (rgp-options-note options)
                                                :environment environment)))
      (persist-rgp-environment environment options)
      (write-rgp-result
       (list :status "resumed"
             :environment_path (rgp-options-environment-path options)
             :work_item (getf (service-response-data response) :work-item)
             :approval (getf (service-response-data response) :approval))))
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

(defun provider-command-show (environment)
  (write-service-result
   (query-environment-provider-service environment))
  0)

(defun provider-command-route (environment)
  (write-service-result
   (query-environment-provider-route-service environment))
  0)

(defun provider-command-preview (options environment)
  (unless (provider-options-prompt options)
    (error "provider preview requires --prompt"))
  (let ((response (query-environment-provider-preview-service
                   (provider-options-prompt options)
                   :environment environment
                   :session (environment-session environment))))
    (write-service-result response))
  0)

(defun provider-command-routing (options environment)
  (let ((response (command-environment-provider-routing-service
                   (provider-options-mode options)
                   environment)))
    (persist-provider-environment environment options)
    (write-service-result response))
  0)

(defun provider-command-configure (options environment)
  (unless (provider-options-profile-name options)
    (error "provider configure requires --profile"))
  (unless (provider-options-provider options)
    (error "provider configure requires --provider"))
  (unless (provider-options-model options)
    (error "provider configure requires --model"))
  (let ((response (command-environment-provider-configure-service
                   (provider-options-profile-name options)
                   (list :provider (provider-options-provider options)
                         :model (provider-options-model options)
                         :fast-model (provider-options-fast-model options)
                         :api-base (provider-options-api-base options)
                         :intents (provider-options-intents options))
                   environment)))
    (persist-provider-environment environment options)
    (write-service-result response))
  0)

(defun provider-command-use (options environment)
  (unless (provider-options-profile-name options)
    (error "provider use requires --profile"))
  (let ((response (command-environment-provider-use-service
                   (provider-options-profile-name options)
                   environment)))
    (persist-provider-environment environment options)
    (write-service-result response))
  0)

(defun provider-command (config arguments)
  (let* ((options (parse-provider-arguments arguments))
         (subcommand (string-downcase (provider-options-subcommand options)))
         (environment (load-or-create-provider-environment options config)))
    (cond
      ((string= subcommand "show")
       (provider-command-show environment))
      ((string= subcommand "route")
       (provider-command-route environment))
      ((string= subcommand "preview")
       (provider-command-preview options environment))
      ((string= subcommand "routing")
       (provider-command-routing options environment))
      ((string= subcommand "configure")
       (provider-command-configure options environment))
      ((string= subcommand "use")
       (provider-command-use options environment))
      (t
       (error "Unknown provider subcommand ~A" subcommand)))))

(defun session-for-chat-config (config)
  (configure-retrieval-ranking-mode (config-retrieval-ranking-mode config))
  (let ((environment (or *current-environment*
                         (setf *current-environment*
                               (make-default-environment
                                :storage-root (config-working-directory config)
                                :session (or *current-session*
                                             (setf *current-session*
                                                   (make-default-session :cwd (config-working-directory config)))))))))
    (ensure-environment-provider-profile :environment environment
                                         :config config
                                         :profile-name "default")
    (set-environment-metadata-value environment :active-provider-profile "default")
    (or (environment-session environment)
        (bind-session-to-environment
         (make-default-session :cwd (config-working-directory config))
         environment))))

(defun doctor-command (config)
  (configure-retrieval-ranking-mode (config-retrieval-ranking-mode config))
  (let* ((environment (ensure-environment))
         (session (ensure-session))
         (environment-summary (service-response-data
                               (query-environment-summary-service environment)))
         (session-summary (service-response-data
                           (query-session-summary-service session)))
         (artifact-summary (getf environment-summary :artifact-summary))
         (replay-groups (service-response-data
                         (query-replay-groups-service session)))
         (image-reconciliations (service-response-data
                                 (query-image-reconciliations-service session))))
    (format t "Runtime: SBCL~%")
    (format t "Environment id: ~A~%" (environment-id environment))
    (format t "Provider: ~A~%" (config-provider config))
    (format t "Model: ~A~%" (config-model config))
    (format t "Fast model: ~A~%" (config-fast-model config))
    (let ((provider-profile (getf environment-summary :provider-profile)))
      (format t "Active provider profile: ~A~%"
              (or (getf provider-profile :active-profile-name) "<none>"))
      (format t "Provider profiles configured: ~D~%"
              (or (getf provider-profile :profile-count) 0)))
    (format t "Retrieval ranking mode: ~A~%" (config-retrieval-ranking-mode config))
    (format t "Working directory: ~A~%" (config-working-directory config))
    (format t "Shell package: ~A~%" (package-name *shell-package*))
    (format t "Session id: ~A~%" (agent-session-id session))
    (format t "Active runtime id: ~A~%" (environment-active-runtime-id environment))
    (format t "Environment events: ~D~%" (getf environment-summary :event-count))
    (format t "Session plan: ~A~%" (or (getf session-summary :plan) "<none>"))
    (format t "Pending assistant actions: ~D~%" (or (getf session-summary :pending-action-count) 0))
    (format t "Queued tasks: ~D~%" (count :queued (agent-session-tasks session) :key #'task-status))
    (format t "Work items: ~D~%" (getf environment-summary :work-item-count))
    (format t "Artifacts: ~D~%" (getf environment-summary :artifact-count))
    (format t "Artifact evidence: ~S~%" artifact-summary)
    (format t "Workflow records: ~D~%" (getf (getf environment-summary :workflow-state) :workflow-record-count))
    (let ((wait-summary (getf session-summary :wait-summary))
          (operator-status (getf environment-summary :operator-status))
          (incident-summary (getf environment-summary :incident-summary))
          (active-worker-count (or (getf session-summary :active-worker-count) 0)))
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
      (format t "Image reconciliations: ~D~%" (length image-reconciliations))
      (format t "Active workers: ~D~%" active-worker-count))
    (format t "Approved policies: ~S~%" (getf session-summary :approved-policies))
    (format t "Capability grants: ~S~%" (getf session-summary :capability-grants))
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
      ((string= command "provider")
       (provider-command config (rest arguments)))
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
