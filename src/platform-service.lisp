(in-package #:sbcl-agent)

(defparameter +platform-manifest-version+ 1)
(defparameter +platform-package-format+ "intentos.aop.v1")
(defparameter +platform-package-registry-key+ :platform-packages)
(defparameter +platform-active-package-ids-key+ :platform-active-package-ids)

(defparameter +platform-sdk-command-entries+
  '((:command-id :platform/manifest
     :transport :shell
     :kind :query
     :command "(platform/manifest [:capabilities '(:capability ...)])"
     :description "Query the developer-platform manifest for selected capabilities.")
    (:command-id :platform/package
     :transport :shell
     :kind :command
     :command "(platform/package :output-path \"file.aop\" [:package-id \"id\"] [:title \"name\"] [:capabilities '(:capability ...)])"
     :description "Export an IntentOS developer package descriptor.")
    (:command-id :platform/activate-package
     :transport :shell
     :kind :command
     :command "(platform/activate-package \"package-id\")"
     :description "Activate one imported IntentOS developer package in the bound environment.")
    (:command-id :platform/deactivate-package
     :transport :shell
     :kind :command
     :command "(platform/deactivate-package \"package-id\")"
     :description "Deactivate one imported IntentOS developer package in the bound environment.")
    (:command-id :platform/active-packages
     :transport :shell
     :kind :query
     :command "(platform/active-packages)"
     :description "List active imported IntentOS developer packages in the bound environment.")
    (:command-id :platform/profile
     :transport :shell
     :kind :query
     :command "(platform/profile)"
     :description "Show the applied active-package developer platform profile for the bound environment.")
    (:command-id :platform/install-package
     :transport :shell
     :kind :command
     :command "(platform/install-package \"file.aop\")"
     :description "Validate, import, and activate one IntentOS developer package in the bound environment.")
    (:command-id :platform/simulate-package
     :transport :shell
     :kind :query
     :command "(platform/simulate-package \"file.aop\")"
     :description "Preview the profile and registry effects of importing and activating one IntentOS developer package without mutating the environment.")
    (:command-id :platform/harness
     :transport :shell
     :kind :query
     :command "(platform/harness)"
     :description "List the available developer platform harnesses and their availability.")
    (:command-id :platform/run-harness
     :transport :shell
     :kind :command
     :command "(platform/run-harness [:harness-id :internal-evaluations])"
     :description "Run one available developer platform harness and return its report.")
    (:command-id :desktop/show
     :transport :shell
     :kind :query
     :command "(desktop/show)"
     :description "Project the hostable desktop shell model.")
    (:command-id :desktop/action
     :transport :shell
     :kind :command
     :command "(desktop/action [:action-id \"...\"] | :action-kind ... :panel-id ...)"
     :description "Dispatch a structured hosted-desktop action.")
    (:command-id :desktop/restore
     :transport :shell
     :kind :command
     :command "(desktop/restore [:panel-id ...] [:panel-state '(... )])"
     :description "Restore hosted desktop panel state.")
    (:command-id :workspace/show
     :transport :shell
     :kind :query
     :command "(workspace/show)"
     :description "Project the shell workspace model built from execution surfaces.")
    (:command-id :inspector/show
     :transport :shell
     :kind :query
     :command "(inspector/show [\"exec-id\"])"
     :description "Inspect the current focused execution-backed object.")
    (:command-id :open
     :transport :shell
     :kind :command
     :command "(open [:execution-id \"exec-id\"] [:surface-index N] [:governance-index N] [:object-kind :kind :object-index N])"
     :description "Open one workspace/governance/object-browser item through the unified shell focus path.")
    (:command-id :platform-cli/manifest
     :transport :cli
     :kind :query
     :command "sbcl-agent platform manifest [--capability <capability>] [--environment <path>] [--working-directory <path>]"
     :description "Query the developer-platform manifest from the command line.")
    (:command-id :platform-cli/package
     :transport :cli
     :kind :command
     :command "sbcl-agent platform package --output <file.aop> [--package-id <id>] [--title <title>] [--capability <capability>] [--environment <path>] [--working-directory <path>]"
     :description "Export an IntentOS developer package descriptor from the command line.")
    (:command-id :platform-cli/activate
     :transport :cli
     :kind :command
     :command "sbcl-agent platform activate --package-id <id> [--environment <path>] [--working-directory <path>]"
     :description "Activate one imported IntentOS developer package from the command line.")
    (:command-id :platform-cli/deactivate
     :transport :cli
     :kind :command
     :command "sbcl-agent platform deactivate --package-id <id> [--environment <path>] [--working-directory <path>]"
     :description "Deactivate one imported IntentOS developer package from the command line.")
    (:command-id :platform-cli/active
     :transport :cli
     :kind :query
     :command "sbcl-agent platform active [--environment <path>] [--working-directory <path>]"
     :description "List active imported IntentOS developer packages from the command line.")
    (:command-id :platform-cli/profile
     :transport :cli
     :kind :query
     :command "sbcl-agent platform profile [--environment <path>] [--working-directory <path>]"
     :description "Show the applied active-package developer platform profile from the command line.")
    (:command-id :platform-cli/install
     :transport :cli
     :kind :command
     :command "sbcl-agent platform install --input <file.aop> [--environment <path>] [--working-directory <path>]"
     :description "Validate, import, and activate one IntentOS developer package from the command line.")
    (:command-id :platform-cli/simulate
     :transport :cli
     :kind :query
     :command "sbcl-agent platform simulate --input <file.aop> [--environment <path>] [--working-directory <path>]"
     :description "Preview the profile and registry effects of importing and activating one IntentOS developer package from the command line.")
    (:command-id :platform-cli/harness
     :transport :cli
     :kind :query
     :command "sbcl-agent platform harness [--environment <path>] [--working-directory <path>]"
     :description "List the available developer platform harnesses from the command line.")
    (:command-id :platform-cli/run-harness
     :transport :cli
     :kind :command
     :command "sbcl-agent platform run-harness [--harness-id <id>] [--environment <path>] [--working-directory <path>]"
     :description "Run one available developer platform harness from the command line.")))

(defparameter +platform-workflow-catalog+
  '((:workflow-id :governed-mutation-review
     :title "Governed Mutation Review"
     :description "Drive approval-gated mutation through governed work, mutation review, and operator inspection."
     :surface-kind :review
     :required-capabilities nil
     :entrypoints (:review/mutation :workspace/show :inspector/show)
     :control-actions (:approve :quarantine :resume))
    (:workflow-id :governed-recovery
     :title "Governed Recovery"
     :description "Recover quarantined or failed governed work through rollback, resume, and validation-finalization control."
     :surface-kind :governed-work
     :required-capabilities nil
     :entrypoints (:why-waiting :governance/queue :inspector/show)
     :control-actions (:quarantine :resume :rollback :complete-validations))
    (:workflow-id :compatibility-host-process
     :title "Compatibility Host Process"
     :description "Launch, inspect, and control hosted compatibility executions as governed external runtimes."
     :surface-kind :compatibility-execution
     :required-capabilities (:proc/run :proc/spawn)
     :entrypoints (:compatibility/list :compatibility/show :workspace/show)
     :control-actions (:stop :revoke :acknowledge-loss))
    (:workflow-id :desktop-host-shell
     :title "Desktop Host Shell"
     :description "Host the execution-surface shell model directly in a desktop client through desktop model, action, and restore contracts."
     :surface-kind :desktop
     :required-capabilities nil
     :entrypoints (:desktop/show :desktop/action :desktop/restore)
     :control-actions (:activate-panel :select-panel :open-panel :restore-panel))
    (:workflow-id :developer-platform-lifecycle
     :title "Developer Platform Lifecycle"
     :description "Package, simulate, inspect, and validate developer platform artifacts and harnesses."
     :surface-kind :platform
     :required-capabilities nil
     :entrypoints (:platform/manifest :platform/package :platform/simulate-package :platform/harness :platform/run-harness)
     :control-actions (:install-package :activate-package :deactivate-package))))

(defparameter +platform-harness-catalog+
  '((:harness-id :internal-evaluations
     :title "Internal Evaluations"
     :description "Run the built-in evaluation families that exercise governed execution, recovery, orchestration, and self-improvement behavior."
     :runner-package "SBCL-AGENT/TESTS"
     :runner-symbol "RUN-INTERNAL-EVALUATIONS"
     :report-shape :evaluation-report-v1)))

(defun normalize-platform-capability-ids (value)
  (cond
    ((null value) nil)
    ((and (consp value)
          (eq (first value) 'quote)
          (= (length value) 2))
     (normalize-platform-capability-ids (second value)))
    ((listp value) value)
    (t (list value))))

(defun platform-keyword-string (value)
  (string-downcase (substitute #\- #\_ (symbol-name value))))

(defun platform-path-designator (value)
  (cond
    ((stringp value) value)
    ((pathnamep value) (namestring value))
    (t (error "Invalid platform package path ~S" value))))

(defun platform-capability-designator (value)
  (typecase value
    (keyword value)
    (string (intern (string-upcase value) "KEYWORD"))
    (t (error "Invalid platform capability designator ~S" value))))

(defun platform-capability-entry (tool-summary)
  (let* ((capability-id (getf tool-summary :id))
         (policy-spec (getf tool-summary :policy-spec)))
    (list :capability-id capability-id
          :capability-name (platform-keyword-string capability-id)
          :type :tool-capability
          :documentation (getf tool-summary :documentation)
          :policy-id (getf tool-summary :policy)
          :policy policy-spec
          :risk-level (getf policy-spec :risk-level)
          :default-grant-mode (getf policy-spec :default-grant-mode)
          :compatibility-kind (getf tool-summary :compatibility-kind)
          :isolation-profile (getf tool-summary :isolation-profile))))

(defun platform-capability-ids (capability-entries)
  (mapcar (lambda (entry) (getf entry :capability-id)) capability-entries))

(defun platform-policy-ids (policy-entries)
  (mapcar (lambda (entry) (getf entry :id)) policy-entries))

(defun platform-compatibility-entries (capability-entries)
  (let ((compatibility-entries '()))
    (dolist (entry capability-entries (nreverse compatibility-entries))
      (let ((kind (getf entry :compatibility-kind)))
        (when kind
          (pushnew (list :kind kind
                         :capability-id (getf entry :capability-id)
                         :isolation-profile (getf entry :isolation-profile))
                   compatibility-entries
                   :test (lambda (left right)
                           (and (eq (getf left :kind) (getf right :kind))
                                (eq (getf left :capability-id) (getf right :capability-id))))))))))

(defun platform-workflow-supported-p (workflow-entry capability-ids)
  (let ((required-capabilities (getf workflow-entry :required-capabilities)))
    (or (null required-capabilities)
        (some (lambda (capability-id)
                (member capability-id capability-ids :test #'eq))
              required-capabilities))))

(defun platform-workflow-entries (capability-entries)
  (let ((capability-ids (platform-capability-ids capability-entries)))
    (remove-if-not (lambda (entry)
                     (platform-workflow-supported-p entry capability-ids))
                   +platform-workflow-catalog+)))

(defun platform-sdk-command-entries ()
  +platform-sdk-command-entries+)

(defun platform-package-contents-summary (manifest)
  (list :capability-ids (mapcar (lambda (entry) (getf entry :capability-id))
                                (getf manifest :capabilities))
        :policy-ids (mapcar (lambda (entry) (getf entry :id))
                            (getf manifest :policies))
        :workflow-ids (mapcar (lambda (entry) (getf entry :workflow-id))
                              (getf manifest :workflows))
        :sdk-command-ids (mapcar (lambda (entry) (getf entry :command-id))
                                 (getf manifest :sdk-commands))
        :compatibility-kinds (mapcar (lambda (entry) (getf entry :kind))
                                     (getf manifest :compatibility-kinds))))

(defun platform-registry-entries (&optional environment)
  (copy-list (or (environment-metadata-value (ensure-environment environment)
                                             +platform-package-registry-key+)
                 '())))

(defun platform-active-package-ids (&optional environment)
  (copy-list (or (environment-metadata-value (ensure-environment environment)
                                             +platform-active-package-ids-key+)
                 '())))

(defun platform-entry-active-p (entry &optional environment)
  (or (getf entry :active-p)
      (member (getf entry :package-id)
              (platform-active-package-ids environment)
              :test #'string=)))

(defun platform-registry-entry-summary (entry)
  (list :package-id (getf entry :package-id)
        :title (getf entry :title)
        :path (getf entry :path)
        :package-format (getf entry :package-format)
        :manifest-version (getf entry :manifest-version)
        :imported-at (getf entry :imported-at)
        :active-p (getf entry :active-p)
        :activated-at (getf entry :activated-at)
        :deactivated-at (getf entry :deactivated-at)
        :capability-count (getf entry :capability-count)
        :workflow-count (getf entry :workflow-count)
        :sdk-command-count (getf entry :sdk-command-count)
        :compatibility-kind-count (getf entry :compatibility-kind-count)
        :contents (getf entry :contents)))

(defun platform-registry-summary (entry &optional environment)
  (let ((summary (platform-registry-entry-summary entry)))
    (setf (getf summary :active-p) (platform-entry-active-p entry environment))
    summary))

(defun platform-find-registry-entry (package-id environment)
  (find package-id
        (platform-registry-entries environment)
        :key (lambda (entry) (getf entry :package-id))
        :test #'string=))

(defun platform-update-registry-entry (environment package-id updater)
  (let* ((registry (platform-registry-entries environment))
         (updated nil)
         (updated-registry
           (mapcar (lambda (entry)
                     (if (string= (getf entry :package-id) package-id)
                         (progn
                           (setf updated t)
                           (funcall updater (copy-list entry)))
                         entry))
                   registry)))
    (unless updated
      (error "Unknown imported platform package ~A" package-id))
    (set-environment-metadata-value environment
                                    +platform-package-registry-key+
                                    updated-registry)
    updated-registry))

(defun platform-entry-manifest (entry)
  (getf (platform-json-object-entry (parse-platform-package-file (getf entry :path))
                                    "manifest")
        :missing))

(defun platform-entry-manifest-object (entry)
  (platform-json-object-entry (parse-platform-package-file (getf entry :path))
                              "manifest"))

(defun platform-entry-manifest-array (entry key)
  (or (platform-json-object-entry (platform-entry-manifest-object entry) key)
      '()))

(defun platform-entry-contents-array (entry key)
  (or (platform-json-object-entry (getf entry :contents) key)
      '()))

(defun platform-active-package-profile (environment)
  (let* ((active-entries (remove-if-not (lambda (entry)
                                          (platform-entry-active-p entry environment))
                                        (platform-registry-entries environment)))
         (capability-ids (remove-duplicates
                          (mapcan (lambda (entry)
                                    (copy-list (platform-entry-contents-array entry "capability_ids")))
                                  active-entries)
                          :test #'string=))
         (policy-ids (remove-duplicates
                      (mapcan (lambda (entry)
                                (copy-list (platform-entry-contents-array entry "policy_ids")))
                              active-entries)
                      :test #'string=))
         (workflow-ids (remove-duplicates
                        (mapcan (lambda (entry)
                                  (copy-list (platform-entry-contents-array entry "workflow_ids")))
                                active-entries)
                        :test #'string=))
         (sdk-command-ids (remove-duplicates
                           (mapcan (lambda (entry)
                                     (copy-list (platform-entry-contents-array entry "sdk_command_ids")))
                                   active-entries)
                           :test #'string=))
         (compatibility-kinds (remove-duplicates
                               (mapcan (lambda (entry)
                                         (copy-list (platform-entry-contents-array entry "compatibility_kinds")))
                                       active-entries)
                               :test #'string=)))
    (list :count (length active-entries)
          :packages (mapcar (lambda (entry)
                              (platform-registry-summary entry environment))
                            active-entries)
          :capability-count (length capability-ids)
          :policy-count (length policy-ids)
          :workflow-count (length workflow-ids)
          :sdk-command-count (length sdk-command-ids)
          :compatibility-kind-count (length compatibility-kinds)
          :capability-ids capability-ids
          :policy-ids policy-ids
          :workflow-ids workflow-ids
          :sdk-command-ids sdk-command-ids
          :compatibility-kinds compatibility-kinds)))

(defun parse-platform-package-file (path)
  (let* ((resolved-path (platform-path-designator path)))
    (unless (probe-file resolved-path)
      (error "Platform package file does not exist: ~A" resolved-path))
    (parse-json (uiop:read-file-string resolved-path))))

(defun platform-json-object-entry (object key)
  (and (listp object)
       (json-object-value object key)))

(defun platform-json-array-count (value)
  (if (listp value) (length value) 0))

(defun platform-json-string-list-p (value)
  (and (listp value)
       (every #'stringp value)))

(defun platform-json-object-list-p (value)
  (and (listp value)
       (every #'listp value)))

(defun platform-json-duplicate-values (values)
  (let ((seen '())
        (duplicates '()))
    (dolist (value values (nreverse duplicates))
      (if (member value seen :test #'equal)
          (pushnew value duplicates :test #'equal)
          (push value seen)))))

(defun platform-json-workflow-entry-valid-p (entry sdk-command-ids capability-ids)
  (let ((workflow-id (platform-json-object-entry entry "workflow_id"))
        (entrypoints (platform-json-object-entry entry "entrypoints"))
        (required-capabilities (platform-json-object-entry entry "required_capabilities"))
        (control-actions (platform-json-object-entry entry "control_actions")))
    (and (stringp workflow-id)
         (platform-json-string-list-p entrypoints)
         (platform-json-string-list-p required-capabilities)
         (platform-json-string-list-p control-actions)
         (every (lambda (entrypoint)
                  (member entrypoint sdk-command-ids :test #'string=))
                entrypoints)
         (every (lambda (capability-id)
                  (member capability-id capability-ids :test #'string=))
                required-capabilities))))

(defun platform-json-sdk-command-entry-valid-p (entry)
  (let ((command-id (platform-json-object-entry entry "command_id"))
        (transport (platform-json-object-entry entry "transport"))
        (kind (platform-json-object-entry entry "kind"))
        (command (platform-json-object-entry entry "command"))
        (description (platform-json-object-entry entry "description")))
    (and (stringp command-id)
         (stringp transport)
         (stringp kind)
         (stringp command)
         (stringp description))))

(defun platform-json-capability-entry-valid-p (entry policy-ids)
  (let ((capability-id (platform-json-object-entry entry "capability_id"))
        (capability-name (platform-json-object-entry entry "capability_name"))
        (policy-id (platform-json-object-entry entry "policy_id")))
    (and (stringp capability-id)
         (stringp capability-name)
         (stringp policy-id)
         (member policy-id policy-ids :test #'string=))))

(defun platform-json-policy-entry-valid-p (entry)
  (let ((policy-id (platform-json-object-entry entry "id"))
        (description (platform-json-object-entry entry "description"))
        (risk-level (platform-json-object-entry entry "risk_level"))
        (default-grant-mode (platform-json-object-entry entry "default_grant_mode")))
    (and (stringp policy-id)
         (stringp description)
         (stringp risk-level)
         (stringp default-grant-mode))))

(defun platform-json-compatibility-entry-valid-p (entry capability-ids)
  (let ((kind (platform-json-object-entry entry "kind"))
        (capability-id (platform-json-object-entry entry "capability_id")))
    (and (stringp kind)
         (stringp capability-id)
         (member capability-id capability-ids :test #'string=))))

(defun platform-package-validation-issues (descriptor)
  (let* ((package-format (platform-json-object-entry descriptor "package_format"))
         (package-id (platform-json-object-entry descriptor "package_id"))
         (title (platform-json-object-entry descriptor "title"))
         (contents (platform-json-object-entry descriptor "contents"))
         (manifest (platform-json-object-entry descriptor "manifest"))
         (manifest-version (platform-json-object-entry manifest "manifest_version"))
         (kernel-class (platform-json-object-entry manifest "kernel_class"))
         (kernel-api (platform-json-object-entry manifest "kernel_api"))
         (capabilities (platform-json-object-entry manifest "capabilities"))
         (policies (platform-json-object-entry manifest "policies"))
         (workflows (platform-json-object-entry manifest "workflows"))
         (sdk-commands (platform-json-object-entry manifest "sdk_commands"))
         (compatibility-kinds (platform-json-object-entry manifest "compatibility_kinds"))
         (capability-ids (mapcar (lambda (entry) (platform-json-object-entry entry "capability_id"))
                                 (or capabilities '())))
         (policy-ids (mapcar (lambda (entry) (platform-json-object-entry entry "id"))
                             (or policies '())))
         (workflow-ids (mapcar (lambda (entry) (platform-json-object-entry entry "workflow_id"))
                               (or workflows '())))
         (sdk-command-ids (mapcar (lambda (entry) (platform-json-object-entry entry "command_id"))
                                  (or sdk-commands '())))
         (compatibility-capability-ids (mapcar (lambda (entry) (platform-json-object-entry entry "capability_id"))
                                               (or compatibility-kinds '())))
         (issues '()))
    (unless (string= (or package-format "") +platform-package-format+)
      (push "package_format does not match the supported IntentOS package format" issues))
    (unless (stringp package-id)
      (push "package_id is required" issues))
    (unless (stringp title)
      (push "title is required" issues))
    (unless manifest
      (push "manifest is required" issues))
    (unless (eql manifest-version +platform-manifest-version+)
      (push "manifest_version does not match the supported platform manifest version" issues))
    (unless (string= (or kernel-class "") "execution-kernel")
      (push "manifest kernel_class must be execution-kernel" issues))
    (unless (and (listp kernel-api)
                 (equal kernel-api '("invoke" "inspect" "control")))
      (push "manifest kernel_api must expose invoke, inspect, and control" issues))
    (unless (listp capabilities)
      (push "manifest capabilities must be an array" issues))
    (unless (listp policies)
      (push "manifest policies must be an array" issues))
    (unless (listp workflows)
      (push "manifest workflows must be an array" issues))
    (unless (listp sdk-commands)
      (push "manifest sdk_commands must be an array" issues))
    (unless (listp compatibility-kinds)
      (push "manifest compatibility_kinds must be an array" issues))
    (unless (platform-json-object-list-p capabilities)
      (push "manifest capabilities must contain object entries" issues))
    (unless (platform-json-object-list-p policies)
      (push "manifest policies must contain object entries" issues))
    (unless (platform-json-object-list-p workflows)
      (push "manifest workflows must contain object entries" issues))
    (unless (platform-json-object-list-p sdk-commands)
      (push "manifest sdk_commands must contain object entries" issues))
    (unless (platform-json-object-list-p compatibility-kinds)
      (push "manifest compatibility_kinds must contain object entries" issues))
    (unless (every #'platform-json-policy-entry-valid-p (or policies '()))
      (push "manifest policies contain invalid entries" issues))
    (unless (every (lambda (entry)
                     (platform-json-capability-entry-valid-p entry policy-ids))
                   (or capabilities '()))
      (push "manifest capabilities contain invalid entries or unknown policy references" issues))
    (unless (every #'platform-json-sdk-command-entry-valid-p (or sdk-commands '()))
      (push "manifest sdk_commands contain invalid entries" issues))
    (unless (every (lambda (entry)
                     (platform-json-workflow-entry-valid-p entry sdk-command-ids capability-ids))
                   (or workflows '()))
      (push "manifest workflows contain invalid entrypoints or capability references" issues))
    (unless (every (lambda (entry)
                     (platform-json-compatibility-entry-valid-p entry capability-ids))
                   (or compatibility-kinds '()))
      (push "manifest compatibility_kinds contain invalid capability references" issues))
    (when (platform-json-duplicate-values (remove nil capability-ids :test #'equal))
      (push "manifest capability ids must be unique" issues))
    (when (platform-json-duplicate-values (remove nil policy-ids :test #'equal))
      (push "manifest policy ids must be unique" issues))
    (when (platform-json-duplicate-values (remove nil workflow-ids :test #'equal))
      (push "manifest workflow ids must be unique" issues))
    (when (platform-json-duplicate-values (remove nil sdk-command-ids :test #'equal))
      (push "manifest sdk command ids must be unique" issues))
    (unless (every (lambda (capability-id)
                     (member capability-id capability-ids :test #'string=))
                   compatibility-capability-ids)
      (push "manifest compatibility_kinds must refer to declared capability ids" issues))
    (when contents
      (let ((content-capability-ids (platform-json-object-entry contents "capability_ids"))
            (content-policy-ids (platform-json-object-entry contents "policy_ids"))
            (content-workflow-ids (platform-json-object-entry contents "workflow_ids"))
            (content-sdk-command-ids (platform-json-object-entry contents "sdk_command_ids"))
            (content-compatibility-kinds (platform-json-object-entry contents "compatibility_kinds")))
        (unless (platform-json-string-list-p content-capability-ids)
          (push "contents capability_ids must be an array of strings" issues))
        (unless (platform-json-string-list-p content-policy-ids)
          (push "contents policy_ids must be an array of strings" issues))
        (unless (platform-json-string-list-p content-workflow-ids)
          (push "contents workflow_ids must be an array of strings" issues))
        (unless (platform-json-string-list-p content-sdk-command-ids)
          (push "contents sdk_command_ids must be an array of strings" issues))
        (unless (platform-json-string-list-p content-compatibility-kinds)
          (push "contents compatibility_kinds must be an array of strings" issues))
        (unless (= (platform-json-array-count content-capability-ids)
                   (platform-json-array-count capabilities))
          (push "contents capability_ids count does not match manifest capabilities" issues))
        (unless (= (platform-json-array-count content-policy-ids)
                   (platform-json-array-count policies))
          (push "contents policy_ids count does not match manifest policies" issues))
        (unless (= (platform-json-array-count content-workflow-ids)
                   (platform-json-array-count workflows))
          (push "contents workflow_ids count does not match manifest workflows" issues))
        (unless (= (platform-json-array-count content-sdk-command-ids)
                   (platform-json-array-count sdk-commands))
          (push "contents sdk_command_ids count does not match manifest sdk commands" issues))
        (unless (= (platform-json-array-count content-compatibility-kinds)
                   (platform-json-array-count compatibility-kinds))
          (push "contents compatibility_kinds count does not match manifest compatibility kinds" issues))
        (unless (equal content-capability-ids capability-ids)
          (push "contents capability_ids do not match manifest capabilities" issues))
        (unless (equal content-policy-ids policy-ids)
          (push "contents policy_ids do not match manifest policies" issues))
        (unless (equal content-workflow-ids workflow-ids)
          (push "contents workflow_ids do not match manifest workflows" issues))
        (unless (equal content-sdk-command-ids sdk-command-ids)
          (push "contents sdk_command_ids do not match manifest sdk commands" issues))
        (unless (equal content-compatibility-kinds
                       (mapcar (lambda (entry) (platform-json-object-entry entry "kind"))
                               (or compatibility-kinds '())))
          (push "contents compatibility_kinds do not match manifest compatibility kinds" issues))))
    (nreverse issues)))

(defun platform-package-summary (descriptor path &key imported-at)
  (let* ((manifest (platform-json-object-entry descriptor "manifest"))
         (contents (platform-json-object-entry descriptor "contents"))
         (capabilities (platform-json-object-entry manifest "capabilities"))
         (workflows (platform-json-object-entry manifest "workflows"))
         (sdk-commands (platform-json-object-entry manifest "sdk_commands"))
         (compatibility-kinds (platform-json-object-entry manifest "compatibility_kinds")))
    (list :package-id (platform-json-object-entry descriptor "package_id")
          :title (platform-json-object-entry descriptor "title")
          :path (platform-path-designator path)
          :package-format (platform-json-object-entry descriptor "package_format")
          :manifest-version (platform-json-object-entry manifest "manifest_version")
          :imported-at imported-at
          :capability-count (platform-json-array-count capabilities)
          :workflow-count (platform-json-array-count workflows)
          :sdk-command-count (platform-json-array-count sdk-commands)
          :compatibility-kind-count (platform-json-array-count compatibility-kinds)
          :contents contents)))

(defun query-platform-package-service (path &key environment session)
  (let* ((descriptor (parse-platform-package-file path))
         (issues (platform-package-validation-issues descriptor))
         (summary (platform-package-summary descriptor path))
         (active-environment (or environment
                                 (and session (session-bound-environment session)))))
    (make-service-query-response :platform
                                 :package
                                 (append summary
                                         (list :path (platform-path-designator path)
                                               :valid-p (null issues)
                                               :validation-issues issues
                                               :descriptor descriptor))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-package-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-platform-validate-package-service (path &key environment session)
  (let* ((descriptor (parse-platform-package-file path))
         (issues (platform-package-validation-issues descriptor))
         (summary (platform-package-summary descriptor path))
         (active-environment (or environment
                                 (and session (session-bound-environment session)))))
    (make-service-command-response :platform
                                   :validate-package
                                   (append summary
                                           (list :path (platform-path-designator path)
                                                 :valid-p (null issues)
                                                 :validation-issues issues))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :platform-package-validation-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun command-platform-import-package-service (path &key environment session)
  (let* ((active-environment (or environment
                                 (and session (session-bound-environment session))))
         (descriptor (parse-platform-package-file path))
         (issues (platform-package-validation-issues descriptor)))
    (unless active-environment
      (error "platform import requires a bound environment"))
    (when issues
      (error "Platform package is invalid: ~{~A~^; ~}" issues))
    (let* ((imported-at (get-universal-time))
           (summary (platform-package-summary descriptor path :imported-at imported-at))
           (existing-entry (platform-find-registry-entry (getf summary :package-id)
                                                         active-environment))
           (summary (append summary
                            (list :active-p (and existing-entry
                                                 (platform-entry-active-p existing-entry
                                                                          active-environment))
                                  :activated-at (and existing-entry
                                                     (getf existing-entry :activated-at))
                                  :deactivated-at (and existing-entry
                                                       (getf existing-entry :deactivated-at)))))
           (registry (remove (getf summary :package-id)
                             (platform-registry-entries active-environment)
                             :key (lambda (entry) (getf entry :package-id))
                             :test #'string=))
           (updated-registry (append registry (list summary))))
      (set-environment-metadata-value active-environment
                                      +platform-package-registry-key+
                                      updated-registry)
      (make-service-command-response :platform
                                     :import-package
                                     (list :path (platform-path-designator path)
                                           :package summary
                                           :registry-count (length updated-registry)
                                           :registry (mapcar (lambda (entry)
                                                               (platform-registry-summary entry
                                                                                          active-environment))
                                                             updated-registry))
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :platform-package-import-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun query-platform-package-registry-service (&key environment session)
  (let* ((active-environment (or environment
                                 (and session (session-bound-environment session))))
         (registry (platform-registry-entries active-environment)))
    (make-service-query-response :platform
                                 :package-registry
                                 (list :count (length registry)
                                       :active-count (length (remove-if-not (lambda (entry)
                                                                              (platform-entry-active-p entry
                                                                                                       active-environment))
                                                                            registry))
                                       :packages (mapcar (lambda (entry)
                                                           (platform-registry-summary entry
                                                                                      active-environment))
                                                         registry))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-package-registry-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-platform-imported-package-service (package-id &key environment session)
  (let* ((active-environment (or environment
                                 (and session (session-bound-environment session))))
         (entry (find package-id
                      (platform-registry-entries active-environment)
                      :key (lambda (registry-entry) (getf registry-entry :package-id))
                      :test #'string=)))
    (unless entry
      (error "Unknown imported platform package ~A" package-id))
    (make-service-query-response :platform
                                 :imported-package
                                 (platform-registry-summary entry active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-imported-package-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-platform-active-packages-service (&key environment session)
  (let* ((active-environment (or environment
                                 (and session (session-bound-environment session))))
         (registry (platform-registry-entries active-environment))
         (active-packages (remove-if-not (lambda (entry)
                                           (platform-entry-active-p entry active-environment))
                                         registry)))
    (make-service-query-response :platform
                                 :active-packages
                                 (list :count (length active-packages)
                                       :packages (mapcar (lambda (entry)
                                                           (platform-registry-summary entry
                                                                                      active-environment))
                                                         active-packages))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-active-packages-v1
                                                                 :session session
                                                                 :environment active-environment))))

(defun query-platform-profile-service (&key environment session)
  (let ((active-environment (or environment
                                (and session (session-bound-environment session)))))
    (make-service-query-response :platform
                                 :profile
                                 (platform-active-package-profile active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-profile-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-platform-activate-package-service (package-id &key environment session)
  (let ((active-environment (or environment
                                (and session (session-bound-environment session)))))
    (unless active-environment
      (error "platform activate requires a bound environment"))
    (let* ((activated-at (get-universal-time))
           (updated-registry
             (platform-update-registry-entry
              active-environment
              package-id
              (lambda (entry)
                (setf (getf entry :active-p) t
                      (getf entry :activated-at) activated-at
                      (getf entry :deactivated-at) nil)
                entry)))
           (updated-active-ids (adjoin package-id
                                       (platform-active-package-ids active-environment)
                                       :test #'string=))
           (entry (platform-find-registry-entry package-id active-environment)))
      (set-environment-metadata-value active-environment
                                      +platform-active-package-ids-key+
                                      updated-active-ids)
      (make-service-command-response :platform
                                     :activate-package
                                     (list :package (platform-registry-summary entry active-environment)
                                           :active-count (length updated-active-ids)
                                           :registry-count (length updated-registry))
                                     :metadata (make-service-metadata :authority :environment
                                                                     :command-model :platform-package-activation-v1
                                                                     :session session
                                                                     :environment active-environment)))))

(defun command-platform-install-package-service (path &key environment session)
  (let* ((active-environment (or environment
                                 (and session (session-bound-environment session))))
         (import-response (command-platform-import-package-service path
                                                                  :environment active-environment
                                                                  :session session))
         (package-id (getf (getf (service-response-data import-response) :package) :package-id))
         (activate-response (command-platform-activate-package-service package-id
                                                                      :environment active-environment
                                                                      :session session))
         (activate-result (service-response-data activate-response)))
    (make-service-command-response :platform
                                   :install-package
                                   (list :path (platform-path-designator path)
                                         :package (getf activate-result :package)
                                         :active-count (getf activate-result :active-count)
                                         :registry-count (getf activate-result :registry-count)
                                         :profile (platform-active-package-profile active-environment))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :platform-package-install-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun command-platform-deactivate-package-service (package-id &key environment session)
  (let ((active-environment (or environment
                                (and session (session-bound-environment session)))))
    (unless active-environment
      (error "platform deactivate requires a bound environment"))
    (let* ((deactivated-at (get-universal-time))
           (updated-registry
             (platform-update-registry-entry
              active-environment
              package-id
              (lambda (entry)
                (setf (getf entry :active-p) nil
                      (getf entry :deactivated-at) deactivated-at)
                entry)))
           (updated-active-ids (remove package-id
                                       (platform-active-package-ids active-environment)
                                       :test #'string=))
           (entry (platform-find-registry-entry package-id active-environment)))
      (set-environment-metadata-value active-environment
                                      +platform-active-package-ids-key+
                                      updated-active-ids)
      (make-service-command-response :platform
                                     :deactivate-package
                                     (list :package (platform-registry-summary entry active-environment)
                                           :active-count (length updated-active-ids)
                                           :registry-count (length updated-registry))
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :platform-package-activation-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun platform-capability-entries (&key capability-ids)
  (let* ((normalized-capability-ids (normalize-platform-capability-ids capability-ids))
         (selected-ids (and normalized-capability-ids
                            (mapcar #'platform-capability-designator normalized-capability-ids)))
         (entries (mapcar #'platform-capability-entry (list-tools))))
    (if selected-ids
        (progn
          (dolist (capability-id selected-ids)
            (unless (find capability-id entries :key (lambda (entry) (getf entry :capability-id)) :test #'eq)
              (error "Unknown platform capability ~S" capability-id)))
          (remove-if-not (lambda (entry)
                           (member (getf entry :capability-id) selected-ids :test #'eq))
                         entries))
        entries)))

(defun platform-policy-entries (capability-entries)
  (let ((policy-ids '()))
    (dolist (entry capability-entries)
      (pushnew (getf entry :policy-id) policy-ids :test #'eq))
    (mapcar #'capability-policy-summary
            (sort (mapcar #'ensure-capability-policy policy-ids)
                  #'string<
                  :key (lambda (policy) (symbol-name (capability-policy-id policy)))))))

(defun platform-manifest-data (&key capability-ids environment session)
  (let* ((capability-entries (platform-capability-entries :capability-ids capability-ids))
         (policy-entries (platform-policy-entries capability-entries))
         (workflow-entries (platform-workflow-entries capability-entries))
         (compatibility-entries (platform-compatibility-entries capability-entries))
         (sdk-command-entries (platform-sdk-command-entries))
         (active-environment (or environment
                                 (and session (session-bound-environment session))
                                 (and (boundp '*current-environment*) *current-environment*))))
    (list :manifest-version +platform-manifest-version+
          :kernel-class :execution-kernel
          :kernel-api '(:invoke :inspect :control)
          :package-format +platform-package-format+
          :sdk-command-count (length sdk-command-entries)
          :workflow-count (length workflow-entries)
          :compatibility-kind-count (length compatibility-entries)
          :capability-count (length capability-entries)
          :policy-count (length policy-entries)
          :sdk-commands sdk-command-entries
          :capabilities capability-entries
          :policies policy-entries
          :workflows workflow-entries
          :compatibility-kinds compatibility-entries
          :environment (when active-environment
                         (list :environment-id (environment-id active-environment)
                               :storage-root (environment-storage-root active-environment)
                               :active-runtime-id (environment-active-runtime-id active-environment))))))

(defun platform-json-safe-value (value)
  (cond
    ((or (null value) (eq value t) (stringp value) (numberp value))
     value)
    ((keywordp value)
     (platform-keyword-string value))
    ((symbolp value)
     (string-downcase (symbol-name value)))
    ((json-plist-p value)
     (loop for (key entry) on value by #'cddr
           append (list key (platform-json-safe-value entry))))
    ((listp value)
     (mapcar #'platform-json-safe-value value))
    (t
     (princ-to-string value))))

(defun query-platform-manifest-service (&key capability-ids environment session)
  (let ((active-environment (or environment
                                (and session (session-bound-environment session)))))
    (make-service-query-response :platform
                                 :manifest
                                 (platform-manifest-data :capability-ids capability-ids
                                                         :environment active-environment
                                                         :session session)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-manifest-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-platform-package-service (output-path &key package-id title capability-ids environment session)
  (unless output-path
    (error "platform package requires an output path"))
  (let* ((active-environment (or environment
                                 (and session (session-bound-environment session))))
         (manifest (platform-manifest-data :capability-ids capability-ids
                                           :environment active-environment
                                           :session session))
         (resolved-package-id (or package-id
                                  (format nil "intentos-package-~D" (get-universal-time))))
         (resolved-title (or title "IntentOS Capability Package"))
         (package-descriptor (list :package-format +platform-package-format+
                                   :package-id resolved-package-id
                                   :title resolved-title
                                   :created-at (get-universal-time)
                                   :contents (platform-package-contents-summary manifest)
                                   :manifest manifest)))
    (uiop:ensure-all-directories-exist (list output-path))
    (with-open-file (stream output-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string (emit-json (platform-json-safe-value package-descriptor)) stream))
    (make-service-command-response :platform
                                   :package
                                   (list :package-id resolved-package-id
                                         :title resolved-title
                                         :output-path output-path
                                         :capability-count (getf manifest :capability-count)
                                         :workflow-count (getf manifest :workflow-count)
                                         :sdk-command-count (getf manifest :sdk-command-count)
                                         :compatibility-kind-count (getf manifest :compatibility-kind-count)
                                         :contents (platform-package-contents-summary manifest)
                                         :manifest manifest)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :platform-package-v1
                                                                    :session session
                                                                    :environment active-environment))))
