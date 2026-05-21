(in-package #:sbcl-agent)

(defparameter +platform-manifest-version+ 1)
(defparameter +platform-package-format+ "intentos.aop.v1")
(defparameter +platform-default-package-version+ "0.1.0")
(defparameter +platform-desktop-contract-id+ "desktop-shell-v1")
(defparameter +platform-surface-contract-id+ "execution-surfaces-v1")
(defparameter +platform-integrity-algorithm+ "fnv1a-64")
(defparameter +platform-default-release-channel+ "stable")
(defparameter +platform-default-support-tier+ "community")
(defparameter +platform-default-update-channel+ "manual")
(defparameter +platform-default-support-window+ "best-effort")
(defparameter +platform-default-release-status+ "active")
(defparameter +platform-default-rollback-strategy+ "reinstall-prior")
(defparameter +platform-default-failure-mode+ "revert-to-prior")
(defparameter +platform-default-publisher+ "local-developer")
(defparameter +platform-default-build-system+ "sbcl-agent")
(defparameter +platform-default-source-repository+ "local-workspace")
(defparameter +platform-trusted-publishers+
  '("local-developer" "internal-release" "trusted-partner"))
(defparameter +platform-package-registry-key+ :platform-packages)
(defparameter +platform-active-package-ids-key+ :platform-active-package-ids)
(defparameter +platform-package-history-key+ :platform-package-history)
(defparameter *platform-state-lock*
  (sb-thread:make-mutex :name "platform-state-lock"))

(defparameter +platform-sdk-command-entries+
  '((:command-id :platform/manifest
     :transport :shell
     :kind :query
     :command "(platform/manifest [:capabilities '(:capability ...)])"
     :description "Query the developer-platform manifest for selected capabilities.")
    (:command-id :platform/package
     :transport :shell
     :kind :command
     :command "(platform/package :output-path \"file.aop\" [:package-id \"id\"] [:package-version \"0.1.0\"] [:title \"name\"] [:capabilities '(:capability ...)])"
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
     :command "(platform/install-package \"file.aop\" [:allow-downgrade t])"
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
    (:command-id :review/mutation
     :transport :shell
     :kind :query
     :command "(review/mutation [\"turn-id\"])"
     :description "Inspect the governed mutation-review posture for one turn.")
    (:command-id :why-waiting
     :transport :shell
     :kind :query
     :command "(why-waiting [\"work-item-id\" | \"exec-id\"])"
     :description "Explain why governed work is blocked or awaiting intervention.")
    (:command-id :governance/queue
     :transport :shell
     :kind :query
     :command "(governance/queue)"
     :description "Project the shell governance queue built from execution-backed surfaces.")
    (:command-id :compatibility/list
     :transport :shell
     :kind :query
     :command "(compatibility/list)"
     :description "List governed compatibility executions and their lifecycle posture.")
    (:command-id :compatibility/show
     :transport :shell
     :kind :query
     :command "(compatibility/show [\"exec-id\"])"
     :description "Inspect one governed compatibility execution in detail.")
    (:command-id :compatibility/windows
     :transport :shell
     :kind :query
     :command "(compatibility/windows [:app-id \"linux.vscode\"])"
     :description "List Linux app display surfaces bridged into the shell workspace.")
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
     :command "sbcl-agent platform package --output <file.aop> [--package-id <id>] [--package-version <version>] [--title <title>] [--capability <capability>] [--environment <path>] [--working-directory <path>]"
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
     :command "sbcl-agent platform install --input <file.aop> [--allow-downgrade] [--environment <path>] [--working-directory <path>]"
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
     :required-capabilities ()
     :entrypoints (:review/mutation :workspace/show :inspector/show)
     :control-actions (:approve :quarantine :resume))
    (:workflow-id :governed-recovery
     :title "Governed Recovery"
     :description "Recover quarantined or failed governed work through rollback, resume, and validation-finalization control."
     :surface-kind :governed-work
     :required-capabilities ()
     :entrypoints (:why-waiting :governance/queue :inspector/show)
     :control-actions (:quarantine :resume :rollback :complete-validations))
    (:workflow-id :compatibility-host-process
     :title "Compatibility Host Process"
     :description "Launch, inspect, and control hosted compatibility executions as governed external runtimes."
     :surface-kind :compatibility-execution
     :required-capabilities (:proc/run)
     :entrypoints (:compatibility/list :compatibility/show :workspace/show)
     :control-actions (:stop :revoke :acknowledge-loss))
    (:workflow-id :desktop-host-shell
     :title "Desktop Host Shell"
     :description "Host the execution-surface shell model directly in a desktop client through desktop model, action, and restore contracts."
     :surface-kind :desktop
     :required-capabilities ()
     :entrypoints (:desktop/show :desktop/action :desktop/restore)
     :control-actions (:activate-panel :select-panel :open-panel :restore-panel))
    (:workflow-id :developer-platform-lifecycle
     :title "Developer Platform Lifecycle"
     :description "Package, simulate, inspect, and validate developer platform artifacts and harnesses."
     :surface-kind :platform
     :required-capabilities ()
     :entrypoints (:platform/manifest :platform/package :platform/simulate-package :platform/harness :platform/run-harness)
     :control-actions (:install-package :activate-package :deactivate-package))))

(defparameter +platform-harness-catalog+
  '((:harness-id :internal-evaluations
     :title "Internal Evaluations"
     :description "Run the built-in evaluation families that exercise governed execution, recovery, orchestration, and self-improvement behavior."
     :runner-package "SBCL-AGENT/TESTS"
     :runner-symbol "RUN-INTERNAL-EVALUATIONS-SMOKE"
     :report-shape :evaluation-report-v1)))

(defun platform-harness-runner-function (entry)
  (let* ((package-name (getf entry :runner-package))
         (symbol-name (getf entry :runner-symbol))
         (package (and package-name (find-package package-name))))
    (when package
      (multiple-value-bind (symbol present-p)
          (find-symbol symbol-name package)
        (when (and present-p (fboundp symbol))
          (symbol-function symbol))))))

(defun platform-harness-summary (entry)
  (let ((runner (platform-harness-runner-function entry)))
    (list :harness-id (getf entry :harness-id)
          :title (getf entry :title)
          :description (getf entry :description)
          :report-shape (getf entry :report-shape)
          :available-p (not (null runner))
          :blocked-reason (unless runner :runner-unavailable))))

(defun platform-harness-entries ()
  (mapcar #'platform-harness-summary +platform-harness-catalog+))

(defun platform-find-harness-entry (harness-id)
  (find harness-id +platform-harness-catalog+
        :key (lambda (entry) (getf entry :harness-id))
        :test #'eq))

(defun platform-merged-active-profile (environment package-summary)
  (let* ((current-profile (platform-active-package-profile environment))
         (current-packages (copy-list (or (getf current-profile :packages) '())))
         (current-capability-ids (copy-list (or (getf current-profile :capability-ids) '())))
         (current-policy-ids (copy-list (or (getf current-profile :policy-ids) '())))
         (current-workflow-ids (copy-list (or (getf current-profile :workflow-ids) '())))
         (current-sdk-command-ids (copy-list (or (getf current-profile :sdk-command-ids) '())))
         (current-compatibility-app-ids (copy-list (or (getf current-profile :compatibility-app-ids) '())))
         (current-compatibility-kinds (copy-list (or (getf current-profile :compatibility-kinds) '())))
         (package-contents (or (getf package-summary :contents) '())))
    (labels ((merge-strings (left right)
               (remove-duplicates (append (copy-list left) (copy-list right))
                                  :test #'string=)))
      (list :count (+ (or (getf current-profile :count) 0) 1)
            :packages (append current-packages
                              (list (list :package-id (getf package-summary :package-id)
                                          :title (getf package-summary :title)
                                          :path (getf package-summary :path)
                                          :active-p t
                                          :simulated-p t)))
            :capability-count (length (merge-strings current-capability-ids
                                                     (or (platform-json-object-entry package-contents "capability_ids")
                                                         '())))
            :policy-count (length (merge-strings current-policy-ids
                                                 (or (platform-json-object-entry package-contents "policy_ids")
                                                     '())))
            :workflow-count (length (merge-strings current-workflow-ids
                                                   (or (platform-json-object-entry package-contents "workflow_ids")
                                                       '())))
            :sdk-command-count (length (merge-strings current-sdk-command-ids
                                                      (or (platform-json-object-entry package-contents "sdk_command_ids")
                                                          '())))
            :compatibility-app-count (length (merge-strings current-compatibility-app-ids
                                                            (or (platform-json-object-entry package-contents "compatibility_app_ids")
                                                                '())))
            :compatibility-kind-count (length (merge-strings current-compatibility-kinds
                                                             (or (platform-json-object-entry package-contents "compatibility_kinds")
                                                                 '())))
            :capability-ids (merge-strings current-capability-ids
                                           (or (platform-json-object-entry package-contents "capability_ids")
                                               '()))
            :policy-ids (merge-strings current-policy-ids
                                       (or (platform-json-object-entry package-contents "policy_ids")
                                           '()))
            :workflow-ids (merge-strings current-workflow-ids
                                         (or (platform-json-object-entry package-contents "workflow_ids")
                                             '()))
            :sdk-command-ids (merge-strings current-sdk-command-ids
                                            (or (platform-json-object-entry package-contents "sdk_command_ids")
                                                '()))
            :compatibility-app-ids (merge-strings current-compatibility-app-ids
                                                  (or (platform-json-object-entry package-contents "compatibility_app_ids")
                                                      '()))
            :compatibility-kinds (merge-strings current-compatibility-kinds
                                                (or (platform-json-object-entry package-contents "compatibility_kinds")
                                                    '()))))))

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

(defun valid-platform-package-version-p (value)
  (and (stringp value)
       (> (length value) 0)
       (every (lambda (part)
                (and (> (length part) 0)
                     (every #'digit-char-p part)))
              (uiop:split-string value :separator "."))))

(defun platform-package-version-components (value)
  (unless (valid-platform-package-version-p value)
    (error "Invalid platform package version ~S" value))
  (mapcar #'parse-integer
          (uiop:split-string value :separator ".")))

(defun compare-platform-package-versions (left right)
  (let* ((left-components (platform-package-version-components left))
         (right-components (platform-package-version-components right))
         (max-length (max (length left-components)
                          (length right-components))))
    (loop for index from 0 below max-length
          for left-part = (or (nth index left-components) 0)
          for right-part = (or (nth index right-components) 0)
          do (cond
               ((< left-part right-part)
                (return -1))
               ((> left-part right-part)
                (return 1)))
          finally (return 0))))

(defun platform-package-update-posture (existing-entry package-summary)
  (if (null existing-entry)
      :new
      (let ((comparison (compare-platform-package-versions
                         (or (getf package-summary :package-version)
                             +platform-default-package-version+)
                         (or (getf existing-entry :package-version)
                             +platform-default-package-version+))))
        (cond
          ((plusp comparison) :upgrade)
          ((minusp comparison) :downgrade)
          (t :same-version)))))

(defun platform-runtime-requirements-data ()
  (list :supported-package-format +platform-package-format+
        :supported-manifest-version +platform-manifest-version+
        :required-runtime-class "execution-runtime"
        :required-runtime-api '("invoke" "inspect" "control")
        :required-desktop-contract +platform-desktop-contract-id+
        :required-surface-contract +platform-surface-contract-id+))

(defun platform-required-runtime-class (requirements)
  (platform-json-object-entry requirements "required_runtime_class"))

(defun platform-required-runtime-api (requirements)
  (platform-json-object-entry requirements "required_runtime_api"))

(defun platform-manifest-runtime-class (manifest)
  (platform-json-object-entry manifest "runtime_class"))

(defun platform-manifest-runtime-api (manifest)
  (platform-json-object-entry manifest "runtime_api"))

(defun platform-support-data ()
  (list :release-channel +platform-default-release-channel+
        :support-tier +platform-default-support-tier+
        :update-channel +platform-default-update-channel+
        :support-window +platform-default-support-window+))

(defun platform-lifecycle-data (&key release-status replacement-package-id)
  (list :release-status (or release-status +platform-default-release-status+)
        :replacement-package-id replacement-package-id))

(defun platform-recovery-data (&key rollback-strategy failure-mode
                                    backup-required-p recovery-runbook)
  (list :rollback-strategy (or rollback-strategy +platform-default-rollback-strategy+)
        :failure-mode (or failure-mode +platform-default-failure-mode+)
        :backup-required-p (if (null backup-required-p) t backup-required-p)
        :recovery-runbook recovery-runbook))

(defun platform-provenance-data (&key publisher build-system source-repository build-kind
                                      ((:attested-p attested-p) t attested-p-supplied-p))
  (list :publisher (or publisher +platform-default-publisher+)
        :build-system (or build-system +platform-default-build-system+)
        :source-repository (or source-repository +platform-default-source-repository+)
        :build-kind (or build-kind "developer-package")
        :attested-p (if attested-p-supplied-p attested-p t)))

(defun platform-json-object-alist-p (value)
  (and (listp value)
       (every #'consp value)
       (every (lambda (entry) (stringp (car entry))) value)))

(defun platform-descriptor-without-integrity (descriptor)
  (cond
    ((json-plist-p descriptor)
     (loop for (key value) on descriptor by #'cddr
           unless (eq key :integrity)
             append (list key value)))
    ((platform-json-object-alist-p descriptor)
     (remove "integrity" descriptor :key #'car :test #'string=))
    (t
     descriptor)))

(defun platform-json-key->keyword (key)
  (intern (string-upcase (substitute #\- #\_ key)) "KEYWORD"))

(defun platform-object-entry (object key)
  (cond
    ((null object) nil)
    ((json-plist-p object)
     (getf object (platform-json-key->keyword key)))
    (t
     (platform-json-object-entry object key))))

(defun platform-normalize-integrity-payload (value)
  (cond
    ((or (null value) (stringp value) (numberp value) (eq value t) (eq value :null))
     value)
    ((keywordp value)
     (platform-keyword-string value))
    ((platform-json-object-alist-p value)
     (loop for entry in value
           append (list (platform-json-key->keyword (car entry))
                        (platform-normalize-integrity-payload (cdr entry)))))
    ((json-plist-p value)
     (loop for (key entry) on value by #'cddr
           append (list key (platform-normalize-integrity-payload entry))))
    ((listp value)
     (mapcar #'platform-normalize-integrity-payload value))
    ((vectorp value)
     (map 'vector #'platform-normalize-integrity-payload value))
    (t
     value)))

(defun platform-fnv1a-64 (string)
  (let ((hash #xCBF29CE484222325)
        (prime #x100000001B3)
        (mask #xFFFFFFFFFFFFFFFF))
    (loop for character across string
          do (setf hash (logand mask (logxor hash (char-code character))))
             (setf hash (logand mask (* hash prime))))
    hash))

(defun platform-compute-integrity-digest (descriptor)
  (let* ((payload (if (json-plist-p descriptor)
                      (platform-descriptor-without-integrity descriptor)
                      (platform-descriptor-without-integrity descriptor)))
         (normalized (platform-normalize-integrity-payload payload))
         (json (emit-json (platform-json-safe-value normalized))))
    (format nil "~16,'0X" (platform-fnv1a-64 json))))

(defun platform-integrity-data (descriptor)
  (list :algorithm +platform-integrity-algorithm+
        :digest (platform-compute-integrity-digest descriptor)))

(defun platform-integrity-issues (descriptor)
  (let* ((integrity (platform-json-object-entry descriptor "integrity"))
         (algorithm (platform-json-object-entry integrity "algorithm"))
         (digest (platform-json-object-entry integrity "digest"))
         (expected-digest (platform-compute-integrity-digest descriptor))
         (issues '()))
    (unless integrity
      (return-from platform-integrity-issues
        (list "integrity is required")))
    (unless (string= (or algorithm "") +platform-integrity-algorithm+)
      (push "integrity algorithm does not match the supported package integrity algorithm" issues))
    (unless (and (stringp digest)
                 (> (length digest) 0))
      (push "integrity digest is required" issues))
    (when (and (stringp digest)
               (> (length digest) 0)
               (not (string= digest expected-digest)))
      (push "integrity digest does not match package contents" issues))
    (nreverse issues)))

(defun platform-package-requirements-issues (descriptor)
  (let* ((requirements (platform-json-object-entry descriptor "requires"))
         (supported-package-format (platform-json-object-entry requirements "supported_package_format"))
         (supported-manifest-version (platform-json-object-entry requirements "supported_manifest_version"))
         (required-runtime-class (platform-required-runtime-class requirements))
         (required-runtime-api (platform-required-runtime-api requirements))
         (required-desktop-contract (platform-json-object-entry requirements "required_desktop_contract"))
         (required-surface-contract (platform-json-object-entry requirements "required_surface_contract"))
         (issues '()))
    (unless requirements
      (return-from platform-package-requirements-issues
        (list "requires is required")))
    (unless (string= (or supported-package-format "") +platform-package-format+)
      (push "requires supported_package_format does not match the supported IntentOS package format" issues))
    (unless (eql supported-manifest-version +platform-manifest-version+)
      (push "requires supported_manifest_version does not match the supported platform manifest version" issues))
    (unless (string= (or required-runtime-class "") "execution-runtime")
      (push "requires required_runtime_class must be execution-runtime" issues))
    (unless (and (listp required-runtime-api)
                 (equal required-runtime-api '("invoke" "inspect" "control")))
      (push "requires required_runtime_api must expose invoke, inspect, and control" issues))
    (unless (string= (or required-desktop-contract "") +platform-desktop-contract-id+)
      (push "requires required_desktop_contract does not match the supported desktop host contract" issues))
    (unless (string= (or required-surface-contract "") +platform-surface-contract-id+)
      (push "requires required_surface_contract does not match the supported execution-surface contract" issues))
    (nreverse issues)))

(defun platform-support-issues (descriptor)
  (let* ((support (platform-json-object-entry descriptor "support"))
         (release-channel (platform-json-object-entry support "release_channel"))
         (support-tier (platform-json-object-entry support "support_tier"))
         (update-channel (platform-json-object-entry support "update_channel"))
         (support-window (platform-json-object-entry support "support_window"))
         (issues '()))
    (unless support
      (return-from platform-support-issues
        (list "support is required")))
    (unless (member release-channel '("stable" "preview" "experimental") :test #'string=)
      (push "support release_channel must be stable, preview, or experimental" issues))
    (unless (member support-tier '("community" "commercial" "internal") :test #'string=)
      (push "support support_tier must be community, commercial, or internal" issues))
    (unless (member update-channel '("manual" "managed" "pinned") :test #'string=)
      (push "support update_channel must be manual, managed, or pinned" issues))
    (unless (member support-window '("best-effort" "scheduled" "long-term") :test #'string=)
      (push "support support_window must be best-effort, scheduled, or long-term" issues))
    (nreverse issues)))

(defun platform-provenance-issues (descriptor)
  (let* ((provenance (platform-json-object-entry descriptor "provenance"))
         (publisher (platform-json-object-entry provenance "publisher"))
         (build-system (platform-json-object-entry provenance "build_system"))
         (source-repository (platform-json-object-entry provenance "source_repository"))
         (build-kind (platform-json-object-entry provenance "build_kind"))
         (attested-p (platform-json-object-entry provenance "attested_p"))
         (issues '()))
    (unless provenance
      (return-from platform-provenance-issues
        (list "provenance is required")))
    (unless (and (stringp publisher) (> (length publisher) 0))
      (push "provenance publisher is required" issues))
    (unless (and (stringp build-system) (> (length build-system) 0))
      (push "provenance build_system is required" issues))
    (unless (and (stringp source-repository) (> (length source-repository) 0))
      (push "provenance source_repository is required" issues))
    (unless (member build-kind '("developer-package" "release-package" "internal-package") :test #'string=)
      (push "provenance build_kind must be developer-package, release-package, or internal-package" issues))
    (unless (member attested-p '(t nil))
      (push "provenance attested_p must be a boolean" issues))
    (nreverse issues)))

(defun platform-lifecycle-issues (descriptor)
  (let* ((lifecycle (platform-json-object-entry descriptor "lifecycle"))
         (release-status (platform-json-object-entry lifecycle "release_status"))
         (replacement-package-id (platform-json-object-entry lifecycle "replacement_package_id"))
         (issues '()))
    (unless lifecycle
      (return-from platform-lifecycle-issues
        (list "lifecycle is required")))
    (unless (member release-status '("active" "deprecated" "sunset") :test #'string=)
      (push "lifecycle release_status must be active, deprecated, or sunset" issues))
    (when (and replacement-package-id
               (not (and (stringp replacement-package-id)
                         (> (length replacement-package-id) 0))))
      (push "lifecycle replacement_package_id must be a non-empty string when provided" issues))
    (nreverse issues)))

(defun platform-lifecycle-override-required-p (descriptor)
  (not (null
        (member (platform-json-object-entry (platform-json-object-entry descriptor "lifecycle")
                                            "release_status")
                '("deprecated" "sunset")
                :test #'string=))))

(defun platform-recovery-issues (descriptor)
  (let* ((recovery (platform-json-object-entry descriptor "recovery"))
         (rollback-strategy (platform-json-object-entry recovery "rollback_strategy"))
         (failure-mode (platform-json-object-entry recovery "failure_mode"))
         (backup-required-p (platform-json-object-entry recovery "backup_required_p"))
         (recovery-runbook (platform-json-object-entry recovery "recovery_runbook"))
         (issues '()))
    (unless recovery
      (return-from platform-recovery-issues
        (list "recovery is required")))
    (unless (member rollback-strategy '("reinstall-prior" "deactivate-only" "manual-recovery")
                    :test #'string=)
      (push "recovery rollback_strategy must be reinstall-prior, deactivate-only, or manual-recovery" issues))
    (unless (member failure-mode '("revert-to-prior" "quarantine" "manual-intervention")
                    :test #'string=)
      (push "recovery failure_mode must be revert-to-prior, quarantine, or manual-intervention" issues))
    (unless (member backup-required-p '(t nil))
      (push "recovery backup_required_p must be a boolean" issues))
    (when (or (string= (or rollback-strategy "") "manual-recovery")
              (string= (or failure-mode "") "manual-intervention"))
      (unless (and (stringp recovery-runbook)
                   (> (length recovery-runbook) 0))
        (push "recovery recovery_runbook is required for manual recovery posture" issues)))
    (nreverse issues)))

(defun platform-recovery-override-required-p (descriptor)
  (let* ((recovery (platform-json-object-entry descriptor "recovery"))
         (rollback-strategy (platform-json-object-entry recovery "rollback_strategy"))
         (failure-mode (platform-json-object-entry recovery "failure_mode")))
    (or (string= (or rollback-strategy "") "manual-recovery")
        (string= (or failure-mode "") "manual-intervention"))))

(defun platform-provenance-trust-issues (descriptor)
  (let* ((provenance (platform-object-entry descriptor "provenance"))
         (publisher (platform-object-entry provenance "publisher"))
         (attested-p (platform-object-entry provenance "attested_p"))
         (issues '()))
    (unless (member publisher +platform-trusted-publishers+ :test #'string=)
      (push "package publisher is not in the trusted publisher set" issues))
    (unless attested-p
      (push "package provenance is unattested" issues))
    (nreverse issues)))

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

(defun platform-compatibility-app-entry (app-summary)
  (list :app-id (getf app-summary :id)
        :title (getf app-summary :title)
        :executable (getf app-summary :executable)
        :default-arguments (copy-list (or (getf app-summary :default-arguments) '()))
        :launch-tool-id (getf app-summary :launch-tool-id)
        :policy-id (getf app-summary :policy-id)
        :filesystem-scope-kind (getf app-summary :filesystem-scope-kind)
        :network-policy (getf app-summary :network-policy)
        :workspace-write-p (getf app-summary :workspace-write-p)
        :display-surface-kind (getf app-summary :display-surface-kind)
        :source-package-id (getf app-summary :source-package-id)))

(defun platform-compatibility-app-entries (capability-entries &key environment session)
  (let ((selected-tool-ids (platform-capability-ids capability-entries)))
    (remove-if-not
     (lambda (entry)
       (member (getf entry :launch-tool-id) selected-tool-ids :test #'eq))
     (mapcar #'platform-compatibility-app-entry
             (list-compatibility-apps :session session
                                      :environment environment)))))

(defun platform-workflow-supported-p (workflow-entry capability-ids)
  (let ((required-capabilities (getf workflow-entry :required-capabilities)))
    (or (null required-capabilities)
        (every (lambda (capability-id)
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
        :compatibility-app-ids (mapcar (lambda (entry) (getf entry :app-id))
                                       (getf manifest :compatibility-apps))
        :compatibility-kinds (mapcar (lambda (entry) (getf entry :kind))
                                     (getf manifest :compatibility-kinds))))

(defun call-with-platform-state (environment thunk)
  (declare (ignore environment))
  (sb-thread:with-mutex (*platform-state-lock*)
    (funcall thunk)))

(defun %platform-registry-entries (environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +platform-package-registry-key+)
      '()))

(defun %platform-package-history-entries (environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +platform-package-history-key+)
      '()))

(defun %platform-active-package-ids (environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +platform-active-package-ids-key+)
      '()))

(defun replace-platform-registry-entries (environment entries)
  (set-environment-metadata-value (ensure-environment environment)
                                  +platform-package-registry-key+
                                  entries))

(defun replace-platform-package-history-entries (environment entries)
  (set-environment-metadata-value (ensure-environment environment)
                                  +platform-package-history-key+
                                  entries))

(defun replace-platform-active-package-ids (environment ids)
  (set-environment-metadata-value (ensure-environment environment)
                                  +platform-active-package-ids-key+
                                  ids))

(defun platform-registry-entries (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (call-with-platform-state
     active-environment
     (lambda ()
       (copy-list (%platform-registry-entries active-environment))))))

(defun platform-package-history-entries (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (call-with-platform-state
     active-environment
     (lambda ()
       (copy-list (%platform-package-history-entries active-environment))))))

(defun platform-active-package-ids (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (call-with-platform-state
     active-environment
     (lambda ()
       (copy-list (%platform-active-package-ids active-environment))))))

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
        :package-version (getf entry :package-version)
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

(defun record-platform-package-history (environment action package-summary
                                          &key session update-posture downgrade-p
                                            deprecated-p manual-recovery-p
                                            untrusted-p active-p downgrade-override-p
                                            deprecated-override-p
                                            manual-recovery-override-p
                                            untrusted-override-p)
  (let* ((active-environment (ensure-environment environment))
         (entry (list :timestamp (get-universal-time)
                      :action action
                      :package-id (getf package-summary :package-id)
                      :package-version (getf package-summary :package-version)
                      :path (getf package-summary :path)
                      :session-id (and session (agent-session-id session))
                      :update-posture update-posture
                      :downgrade-p downgrade-p
                      :deprecated-p deprecated-p
                      :manual-recovery-p manual-recovery-p
                      :untrusted-p untrusted-p
                      :downgrade-override-p downgrade-override-p
                      :deprecated-override-p deprecated-override-p
                      :manual-recovery-override-p manual-recovery-override-p
                      :untrusted-override-p untrusted-override-p
                      :active-p active-p)))
    (call-with-platform-state
     active-environment
     (lambda ()
       (replace-platform-package-history-entries
        active-environment
        (append (%platform-package-history-entries active-environment)
                (list entry)))))
    entry))

(defun platform-history-override-count (history)
  (count-if (lambda (entry)
              (or (getf entry :downgrade-override-p)
                  (getf entry :deprecated-override-p)
                  (getf entry :manual-recovery-override-p)
                  (getf entry :untrusted-override-p)))
            history))

(defun platform-entry-latest-history (package-id history)
  (car (last (remove-if-not (lambda (entry)
                              (string= (getf entry :package-id) package-id))
                            history))))

(defun platform-audit-package-summary (entry history &optional environment)
  (let* ((package-id (getf entry :package-id))
         (latest-history (platform-entry-latest-history package-id history))
         (support (getf entry :support))
         (lifecycle (getf entry :lifecycle))
         (recovery (getf entry :recovery))
         (provenance (getf entry :provenance))
         (release-status (platform-object-entry lifecycle "release_status"))
         (update-channel (platform-object-entry support "update_channel"))
         (publisher (platform-object-entry provenance "publisher"))
         (history-count (count package-id history
                               :key (lambda (history-entry)
                                      (getf history-entry :package-id))
                               :test #'string=)))
    (list :package-id package-id
          :package-version (getf entry :package-version)
          :title (getf entry :title)
          :active-p (platform-entry-active-p entry environment)
          :publisher publisher
          :provenance-trusted-p (getf entry :provenance-trusted-p)
          :release-status release-status
          :lifecycle-override-required-p (getf entry :lifecycle-override-required-p)
          :manual-recovery-p (getf entry :recovery-override-required-p)
          :update-channel update-channel
          :support-tier (platform-object-entry support "support_tier")
          :support-window (platform-object-entry support "support_window")
          :rollback-strategy (platform-object-entry recovery "rollback_strategy")
          :failure-mode (platform-object-entry recovery "failure_mode")
          :history-count history-count
          :latest-action (and latest-history (getf latest-history :action))
          :latest-action-at (and latest-history (getf latest-history :timestamp))
          :override-count (count-if (lambda (history-entry)
                                      (and (string= (getf history-entry :package-id) package-id)
                                           (or (getf history-entry :downgrade-override-p)
                                               (getf history-entry :deprecated-override-p)
                                               (getf history-entry :manual-recovery-override-p)
                                               (getf history-entry :untrusted-override-p))))
                                    history)
          :attention-required-p (or (not (getf entry :provenance-trusted-p))
                                    (getf entry :lifecycle-override-required-p)
                                    (getf entry :recovery-override-required-p)
                                    (string= (or update-channel "") "manual")))))

(defun platform-resolve-environment (&key environment session)
  (or environment
      (and session
           (or (session-bound-environment session)
               (let ((default-environment (make-default-environment :session session
                                                                    :storage-root (agent-session-cwd session))))
                 (bind-session-to-environment session default-environment)
                 default-environment)))
      (ensure-environment)))

(defun platform-find-registry-entry (package-id environment)
  (find package-id
        (platform-registry-entries environment)
        :key (lambda (entry) (getf entry :package-id))
        :test #'string=))

(defun platform-update-registry-entry (environment package-id updater)
  (let ((active-environment (ensure-environment environment)))
    (call-with-platform-state
     active-environment
     (lambda ()
       (let* ((registry (%platform-registry-entries active-environment))
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
         (replace-platform-registry-entries active-environment updated-registry)
         updated-registry)))))

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

(defun platform-json->compatibility-app-definition (entry &key source-package-id)
  (let* ((launch-tool-id (platform-capability-designator
                          (platform-json-object-entry entry "launch_tool_id")))
         (backend-profile-id
           (or (let ((raw-backend-profile-id
                       (or (platform-json-object-entry entry "backend_profile_id")
                           (platform-json-object-entry entry "backend-profile-id"))))
                 (and raw-backend-profile-id
                      (platform-capability-designator raw-backend-profile-id)))
               (let ((tool (and launch-tool-id
                                (find-tool launch-tool-id))))
                 (and tool
                      (tool-definition-backend-profile-id tool))))))
    (make-compatibility-app-definition
     :id (platform-json-object-entry entry "app_id")
     :title (platform-json-object-entry entry "title")
     :executable (platform-json-object-entry entry "executable")
     :default-arguments (copy-list (or (platform-json-object-entry entry "default_arguments") '()))
     :launch-tool-id launch-tool-id
     :backend-profile-id backend-profile-id
     :policy-id (platform-capability-designator (platform-json-object-entry entry "policy_id"))
     :filesystem-scope-kind (platform-capability-designator (platform-json-object-entry entry "filesystem_scope_kind"))
     :network-policy (platform-capability-designator (platform-json-object-entry entry "network_policy"))
     :workspace-write-p (platform-json-object-entry entry "workspace_write_p")
     :display-surface-kind (platform-capability-designator (platform-json-object-entry entry "display_surface_kind"))
     :source-package-id source-package-id)))

(defun platform-active-compatibility-app-definitions (&key environment session)
  (declare (ignore session))
  (let* ((active-environment (platform-resolve-environment :environment environment))
         (active-entries (remove-if-not (lambda (entry)
                                          (platform-entry-active-p entry active-environment))
                                        (platform-registry-entries active-environment))))
    (loop for entry in active-entries
          append (mapcar (lambda (app-entry)
                           (platform-json->compatibility-app-definition app-entry
                                                                        :source-package-id (getf entry :package-id)))
                         (platform-entry-manifest-array entry "compatibility_apps")))))

(setf *compatibility-app-provider-function* #'platform-active-compatibility-app-definitions)

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
         (compatibility-app-ids (remove-duplicates
                                 (mapcan (lambda (entry)
                                           (copy-list (platform-entry-contents-array entry "compatibility_app_ids")))
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
          :compatibility-app-count (length compatibility-app-ids)
          :compatibility-kind-count (length compatibility-kinds)
          :capability-ids capability-ids
          :policy-ids policy-ids
          :workflow-ids workflow-ids
          :sdk-command-ids sdk-command-ids
          :compatibility-app-ids compatibility-app-ids
          :compatibility-kinds compatibility-kinds)))

(defun parse-platform-package-file (path)
  (let* ((resolved-path (platform-path-designator path)))
    (unless (probe-file resolved-path)
      (error "Platform package file does not exist: ~A" resolved-path))
    (parse-json (uiop:read-file-string resolved-path))))

(defun platform-json-object-entry (object key)
  (and (listp object)
       (or (json-object-value object key)
           (when (stringp key)
             (let ((alternate
                     (if (find #\_ key)
                         (substitute #\- #\_ key)
                         (substitute #\_ #\- key))))
               (unless (string= alternate key)
                 (json-object-value object alternate)))))))

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

(defun platform-json-compatibility-app-entry-valid-p (entry capability-ids policy-ids)
  (let ((app-id (platform-json-object-entry entry "app_id"))
        (title (platform-json-object-entry entry "title"))
        (executable (platform-json-object-entry entry "executable"))
        (default-arguments (platform-json-object-entry entry "default_arguments"))
        (launch-tool-id (platform-json-object-entry entry "launch_tool_id"))
        (policy-id (platform-json-object-entry entry "policy_id"))
        (filesystem-scope-kind (platform-json-object-entry entry "filesystem_scope_kind"))
        (network-policy (platform-json-object-entry entry "network_policy"))
        (workspace-write-p (platform-json-object-entry entry "workspace_write_p"))
        (display-surface-kind (platform-json-object-entry entry "display_surface_kind")))
    (and (stringp app-id)
         (stringp title)
         (stringp executable)
         (platform-json-string-list-p default-arguments)
         (stringp launch-tool-id)
         (member launch-tool-id capability-ids :test #'string=)
         (stringp policy-id)
         (member policy-id policy-ids :test #'string=)
         (member filesystem-scope-kind '("session-workspace" "none" "user-home") :test #'string=)
         (member network-policy '("none" "client") :test #'string=)
         (member workspace-write-p '(t nil))
         (member display-surface-kind '("headless" "desktop-window") :test #'string=))))

(defun platform-package-validation-issues (descriptor)
  (let* ((package-format (platform-json-object-entry descriptor "package_format"))
         (package-id (platform-json-object-entry descriptor "package_id"))
         (package-version (or (platform-json-object-entry descriptor "package_version")
                              +platform-default-package-version+))
         (title (platform-json-object-entry descriptor "title"))
         (contents (platform-json-object-entry descriptor "contents"))
         (manifest (platform-json-object-entry descriptor "manifest"))
         (manifest-version (platform-json-object-entry manifest "manifest_version"))
         (runtime-class (platform-manifest-runtime-class manifest))
         (runtime-api (platform-manifest-runtime-api manifest))
         (capabilities (platform-json-object-entry manifest "capabilities"))
         (policies (platform-json-object-entry manifest "policies"))
         (workflows (platform-json-object-entry manifest "workflows"))
         (sdk-commands (platform-json-object-entry manifest "sdk_commands"))
         (compatibility-apps (platform-json-object-entry manifest "compatibility_apps"))
         (compatibility-kinds (platform-json-object-entry manifest "compatibility_kinds"))
         (capability-ids (mapcar (lambda (entry) (platform-json-object-entry entry "capability_id"))
                                 (or capabilities '())))
         (policy-ids (mapcar (lambda (entry) (platform-json-object-entry entry "id"))
                             (or policies '())))
         (workflow-ids (mapcar (lambda (entry) (platform-json-object-entry entry "workflow_id"))
                               (or workflows '())))
         (sdk-command-ids (mapcar (lambda (entry) (platform-json-object-entry entry "command_id"))
                                  (or sdk-commands '())))
         (compatibility-app-ids (mapcar (lambda (entry) (platform-json-object-entry entry "app_id"))
                                        (or compatibility-apps '())))
         (compatibility-capability-ids (mapcar (lambda (entry) (platform-json-object-entry entry "capability_id"))
                                               (or compatibility-kinds '())))
         (issues '()))
    (unless (string= (or package-format "") +platform-package-format+)
      (push "package_format does not match the supported IntentOS package format" issues))
    (unless (stringp package-id)
      (push "package_id is required" issues))
    (unless (valid-platform-package-version-p package-version)
      (push "package_version must be a dotted numeric version string" issues))
    (unless (stringp title)
      (push "title is required" issues))
    (unless manifest
      (push "manifest is required" issues))
    (unless (eql manifest-version +platform-manifest-version+)
      (push "manifest_version does not match the supported platform manifest version" issues))
    (unless (string= (or runtime-class "") "execution-runtime")
      (push "manifest runtime_class must be execution-runtime" issues))
    (unless (and (listp runtime-api)
                 (equal runtime-api '("invoke" "inspect" "control")))
      (push "manifest runtime_api must expose invoke, inspect, and control" issues))
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
    (unless (listp compatibility-apps)
      (push "manifest compatibility_apps must be an array" issues))
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
    (unless (platform-json-object-list-p compatibility-apps)
      (push "manifest compatibility_apps must contain object entries" issues))
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
    (unless (every (lambda (entry)
                     (platform-json-compatibility-app-entry-valid-p entry capability-ids policy-ids))
                   (or compatibility-apps '()))
      (push "manifest compatibility_apps contain invalid tool, policy, or resource contract references" issues))
    (when (platform-json-duplicate-values (remove nil capability-ids :test #'equal))
      (push "manifest capability ids must be unique" issues))
    (when (platform-json-duplicate-values (remove nil policy-ids :test #'equal))
      (push "manifest policy ids must be unique" issues))
    (when (platform-json-duplicate-values (remove nil workflow-ids :test #'equal))
      (push "manifest workflow ids must be unique" issues))
    (when (platform-json-duplicate-values (remove nil sdk-command-ids :test #'equal))
      (push "manifest sdk command ids must be unique" issues))
    (when (platform-json-duplicate-values (remove nil compatibility-app-ids :test #'equal))
      (push "manifest compatibility app ids must be unique" issues))
    (unless (every (lambda (capability-id)
                     (member capability-id capability-ids :test #'string=))
                   compatibility-capability-ids)
      (push "manifest compatibility_kinds must refer to declared capability ids" issues))
    (setf issues (append (nreverse (platform-integrity-issues descriptor))
                         (nreverse (platform-provenance-issues descriptor))
                         (nreverse (platform-support-issues descriptor))
                         (nreverse (platform-recovery-issues descriptor))
                         (nreverse (platform-package-requirements-issues descriptor))
                         issues))
    (when contents
      (let ((content-capability-ids (platform-json-object-entry contents "capability_ids"))
            (content-policy-ids (platform-json-object-entry contents "policy_ids"))
            (content-workflow-ids (platform-json-object-entry contents "workflow_ids"))
            (content-sdk-command-ids (platform-json-object-entry contents "sdk_command_ids"))
            (content-compatibility-app-ids (platform-json-object-entry contents "compatibility_app_ids"))
            (content-compatibility-kinds (platform-json-object-entry contents "compatibility_kinds")))
        (unless (platform-json-string-list-p content-capability-ids)
          (push "contents capability_ids must be an array of strings" issues))
        (unless (platform-json-string-list-p content-policy-ids)
          (push "contents policy_ids must be an array of strings" issues))
        (unless (platform-json-string-list-p content-workflow-ids)
          (push "contents workflow_ids must be an array of strings" issues))
        (unless (platform-json-string-list-p content-sdk-command-ids)
          (push "contents sdk_command_ids must be an array of strings" issues))
        (unless (platform-json-string-list-p content-compatibility-app-ids)
          (push "contents compatibility_app_ids must be an array of strings" issues))
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
        (unless (= (platform-json-array-count content-compatibility-app-ids)
                   (platform-json-array-count compatibility-apps))
          (push "contents compatibility_app_ids count does not match manifest compatibility apps" issues))
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
        (unless (equal content-compatibility-app-ids compatibility-app-ids)
          (push "contents compatibility_app_ids do not match manifest compatibility apps" issues))
        (unless (equal content-compatibility-kinds
                       (mapcar (lambda (entry) (platform-json-object-entry entry "kind"))
                               (or compatibility-kinds '())))
          (push "contents compatibility_kinds do not match manifest compatibility kinds" issues))))
    (nreverse issues)))

(defun platform-package-summary (descriptor path &key imported-at)
  (let* ((manifest (platform-json-object-entry descriptor "manifest"))
         (requirements (platform-json-object-entry descriptor "requires"))
         (support (platform-json-object-entry descriptor "support"))
         (lifecycle (platform-json-object-entry descriptor "lifecycle"))
         (provenance (platform-json-object-entry descriptor "provenance"))
         (integrity (platform-json-object-entry descriptor "integrity"))
         (contents (platform-json-object-entry descriptor "contents"))
         (capabilities (platform-json-object-entry manifest "capabilities"))
         (workflows (platform-json-object-entry manifest "workflows"))
         (sdk-commands (platform-json-object-entry manifest "sdk_commands"))
         (compatibility-apps (platform-json-object-entry manifest "compatibility_apps"))
         (compatibility-kinds (platform-json-object-entry manifest "compatibility_kinds"))
         (requirement-issues (platform-package-requirements-issues descriptor))
         (support-issues (platform-support-issues descriptor))
         (lifecycle-issues (platform-lifecycle-issues descriptor))
         (recovery-issues (platform-recovery-issues descriptor))
         (provenance-issues (platform-provenance-issues descriptor))
         (provenance-trust-issues (platform-provenance-trust-issues descriptor))
         (integrity-issues (platform-integrity-issues descriptor)))
    (list :package-id (platform-json-object-entry descriptor "package_id")
          :title (platform-json-object-entry descriptor "title")
          :path (platform-path-designator path)
          :package-format (platform-json-object-entry descriptor "package_format")
          :package-version (or (platform-json-object-entry descriptor "package_version")
                               +platform-default-package-version+)
          :requirements requirements
          :support support
          :support-valid-p (null support-issues)
          :support-issues support-issues
          :lifecycle lifecycle
          :lifecycle-valid-p (null lifecycle-issues)
          :lifecycle-issues lifecycle-issues
          :lifecycle-override-required-p (platform-lifecycle-override-required-p descriptor)
          :recovery (platform-json-object-entry descriptor "recovery")
          :recovery-valid-p (null recovery-issues)
          :recovery-issues recovery-issues
          :recovery-override-required-p (platform-recovery-override-required-p descriptor)
          :provenance provenance
          :provenance-valid-p (null provenance-issues)
          :provenance-issues provenance-issues
          :provenance-trusted-p (null provenance-trust-issues)
          :provenance-trust-issues provenance-trust-issues
          :integrity integrity
          :integrity-valid-p (null integrity-issues)
          :integrity-issues integrity-issues
          :contract-compatible-p (null requirement-issues)
          :contract-issues requirement-issues
          :manifest-version (platform-json-object-entry manifest "manifest_version")
          :imported-at imported-at
          :capability-count (platform-json-array-count capabilities)
          :workflow-count (platform-json-array-count workflows)
          :sdk-command-count (platform-json-array-count sdk-commands)
          :compatibility-app-count (platform-json-array-count compatibility-apps)
          :compatibility-kind-count (platform-json-array-count compatibility-kinds)
          :contents contents)))

(defun query-platform-package-service (path &key environment session)
  (let* ((descriptor (parse-platform-package-file path))
         (issues (platform-package-validation-issues descriptor))
         (summary (platform-package-summary descriptor path))
         (active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (existing-entry (platform-find-registry-entry (getf summary :package-id)
                                                       active-environment)))
    (make-service-query-response :platform
                                 :package
                                 (append summary
                                         (list :path (platform-path-designator path)
                                               :valid-p (null issues)
                                               :validation-issues issues
                                               :update-posture (platform-package-update-posture existing-entry
                                                                                                 summary)
                                               :descriptor descriptor))
                                   :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-package-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-platform-simulate-package-service (path &key environment session)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (descriptor (parse-platform-package-file path))
         (issues (platform-package-validation-issues descriptor))
         (summary (platform-package-summary descriptor path))
         (existing-entry (and active-environment
                              (platform-find-registry-entry (getf summary :package-id)
                                                            active-environment))))
    (make-service-query-response :platform
                                 :simulate-package
                                 (append summary
                                         (let ((update-posture (platform-package-update-posture existing-entry
                                                                                                summary)))
                                           (list :update-posture update-posture
                                                 :downgrade-p (eq update-posture :downgrade)
                                                 :would-require-override-p (eq update-posture :downgrade)
                                                 :deprecated-p (getf summary :lifecycle-override-required-p)
                                                 :would-require-lifecycle-override-p (getf summary :lifecycle-override-required-p)
                                                 :manual-recovery-p (getf summary :recovery-override-required-p)
                                                 :would-require-recovery-override-p (getf summary :recovery-override-required-p)
                                                 :untrusted-p (not (getf summary :provenance-trusted-p))
                                                 :would-require-trust-override-p (not (getf summary :provenance-trusted-p))))
                                         (list :path (platform-path-designator path)
                                               :valid-p (null issues)
                                               :validation-issues issues
                                               :would-import-p (null issues)
                                               :would-replace-existing-p (not (null existing-entry))
                                               :simulated-profile (and (null issues)
                                                                       active-environment
                                                                       (platform-merged-active-profile active-environment
                                                                                                       summary))))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-package-simulation-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun make-platform-control-actor-address (session)
  (make-standard-actor-address :platform
                               :scope (agent-session-id session)))

(defun make-platform-control-request (session action capability
                                      &key payload metadata environment)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :platform
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :platform-control-v1)
                     (when environment
                       (list :environment-id (environment-id environment)))
                     metadata)))

(defun actorize-platform-command-response (response
                                           &key actor-execution-job-id
                                             governance-authority
                                             policy-id
                                             approval-required-p
                                             approval-granted-p)
  (if (listp response)
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (when actor-execution-job-id
          (setf (getf metadata :actor-execution-job-id) actor-execution-job-id))
        (when governance-authority
          (setf (getf metadata :governance-authority) governance-authority))
        (when policy-id
          (setf (getf metadata :policy-id) policy-id))
        (setf (getf metadata :approval-required-p) (and approval-required-p t)
              (getf metadata :approval-granted-p) (and approval-granted-p t)
              (getf response :metadata) metadata)
        (when (keyword-plist-p data)
          (let ((updated-data (copy-list data)))
            (when actor-execution-job-id
              (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id))
            (when governance-authority
              (setf (getf updated-data :governance-authority) governance-authority))
            (when policy-id
              (setf (getf updated-data :policy-id) policy-id))
            (setf (getf updated-data :approval-required-p) (and approval-required-p t)
                  (getf updated-data :approval-granted-p) (and approval-granted-p t)
                  (getf response :data) updated-data)))
        response)
      response))

(defun platform-command-policy-id (capability)
  (let ((normalized (capability-name-string capability)))
    (cond
      ((string= normalized "platform/package") :platform-package)
      ((string= normalized "platform/import-package") :platform-import-package)
      ((string= normalized "platform/activate-package") :platform-activate-package)
      ((string= normalized "platform/deactivate-package") :platform-deactivate-package)
      ((string= normalized "platform/install-package") :platform-install-package)
      ((string= normalized "platform/run-harness") :platform-run-harness)
      (t nil))))

(defun platform-command-approval-required-p (policy-id)
  (let ((policy (and policy-id
                     (ignore-errors (ensure-capability-policy policy-id)))))
    (and policy
         (not (eq (capability-policy-default-grant-mode policy) :implicit)))))

(defun call-with-platform-governed-actor (session request thunk capability action
                                          &key environment metadata policy-id approval-required-p)
  (let* ((actor-address (make-platform-control-actor-address session))
         (resolved-policy-id (or policy-id (platform-command-policy-id capability)))
         (resolved-approval-required-p
           (if (null approval-required-p)
               (platform-command-approval-required-p resolved-policy-id)
               approval-required-p))
         (actor-context
           (make-actor-execution-context
            :actor-id (actor-address-id actor-address)
            :capability capability
            :authority :governed-runtime
            :policy-id resolved-policy-id
            :target :platform
            :operation action
            :request-id (desktop-task-request-id request)
            :approval-required-p resolved-approval-required-p
            :metadata (append (when environment
                                (list :environment-id (environment-id environment)))
                              metadata)))
         (approval-granted-p (and resolved-approval-required-p
                                  resolved-policy-id
                                  (ignore-errors (policy-approved-p session resolved-policy-id)))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (when (fboundp 'update-current-actor-execution-context)
         (update-current-actor-execution-context actor-context :replace-p t))
       (when (and resolved-approval-required-p resolved-policy-id)
         (ensure-policy-approved session resolved-policy-id))
       (actorize-platform-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)
        :governance-authority :actor-runtime
        :policy-id resolved-policy-id
        :approval-required-p resolved-approval-required-p
        :approval-granted-p approval-granted-p))
     :context actor-context)))

(defun command-platform-validate-package-service (path &key environment session)
  (let* ((descriptor (parse-platform-package-file path))
         (issues (platform-package-validation-issues descriptor))
         (summary (platform-package-summary descriptor path))
         (active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (existing-entry (platform-find-registry-entry (getf summary :package-id)
                                                       active-environment)))
    (make-service-command-response :platform
                                   :validate-package
                                   (append summary
                                           (list :path (platform-path-designator path)
                                                 :valid-p (null issues)
                                                 :validation-issues issues
                                                 :update-posture (platform-package-update-posture existing-entry
                                                                                                   summary)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :platform-package-validation-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun perform-platform-import-package-service (path &key environment session allow-downgrade-p allow-untrusted-p allow-deprecated-p allow-manual-recovery-p)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (descriptor (parse-platform-package-file path))
         (issues (platform-package-validation-issues descriptor)))
    (when issues
      (error "Platform package is invalid: ~{~A~^; ~}" issues))
    (let* ((imported-at (get-universal-time))
           (summary (platform-package-summary descriptor path :imported-at imported-at))
           (existing-entry (platform-find-registry-entry (getf summary :package-id)
                                                         active-environment))
           (update-posture (platform-package-update-posture existing-entry summary))
           (downgrade-p (eq update-posture :downgrade))
           (deprecated-p (getf summary :lifecycle-override-required-p))
           (manual-recovery-p (getf summary :recovery-override-required-p))
           (untrusted-p (not (getf summary :provenance-trusted-p))))
      (when (and downgrade-p (not allow-downgrade-p))
        (error "Refusing to downgrade platform package ~A from ~A to ~A without explicit override"
               (getf summary :package-id)
               (or (getf existing-entry :package-version) +platform-default-package-version+)
               (getf summary :package-version)))
      (when (and deprecated-p (not allow-deprecated-p))
        (error "Refusing to import deprecated platform package ~A without explicit lifecycle override"
               (getf summary :package-id)))
      (when (and manual-recovery-p (not allow-manual-recovery-p))
        (error "Refusing to import manual-recovery platform package ~A without explicit recovery override"
               (getf summary :package-id)))
      (when (and untrusted-p (not allow-untrusted-p))
        (error "Refusing to import untrusted platform package ~A without explicit trust override"
               (getf summary :package-id)))
      (let* ((summary (append summary
                              (list :active-p (and existing-entry
                                                   (platform-entry-active-p existing-entry
                                                                            active-environment))
                                    :activated-at (and existing-entry
                                                       (getf existing-entry :activated-at))
                                    :deactivated-at (and existing-entry
                                                         (getf existing-entry :deactivated-at))
                                    :update-posture update-posture
                                    :downgrade-p downgrade-p
                                    :deprecated-p deprecated-p
                                    :manual-recovery-p manual-recovery-p
                                    :untrusted-p untrusted-p)))
             (registry (remove (getf summary :package-id)
                               (platform-registry-entries active-environment)
                               :key (lambda (entry) (getf entry :package-id))
                               :test #'string=))
             (updated-registry (append registry (list summary))))
        (call-with-platform-state
         active-environment
         (lambda ()
           (replace-platform-registry-entries active-environment updated-registry)
           (replace-platform-package-history-entries
            active-environment
            (append (%platform-package-history-entries active-environment)
                    (list (list :timestamp (get-universal-time)
                                :action :import
                                :package-id (getf summary :package-id)
                                :package-version (getf summary :package-version)
                                :path (getf summary :path)
                                :session-id (and session (agent-session-id session))
                                :update-posture update-posture
                                :downgrade-p downgrade-p
                                :deprecated-p deprecated-p
                                :manual-recovery-p manual-recovery-p
                                :untrusted-p untrusted-p
                                :downgrade-override-p (and downgrade-p allow-downgrade-p)
                                :deprecated-override-p (and deprecated-p allow-deprecated-p)
                                :manual-recovery-override-p (and manual-recovery-p allow-manual-recovery-p)
                                :untrusted-override-p (and untrusted-p allow-untrusted-p)
                                :active-p (getf summary :active-p)))))))
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
                                                                        :command-model :platform-package-import-v2
                                                                        :session session
                                                                        :environment active-environment
                                                                        :policy-id :platform-import-package))))))

(defun command-platform-import-package-service (path &key environment session allow-downgrade-p allow-untrusted-p allow-deprecated-p allow-manual-recovery-p)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (request (make-platform-control-request session
                                                 :import-package
                                                 :platform/import-package
                                                 :payload (list :path (platform-path-designator path)
                                                                :allow-downgrade allow-downgrade-p
                                                                :allow-untrusted allow-untrusted-p
                                                                :allow-deprecated allow-deprecated-p
                                                                :allow-manual-recovery allow-manual-recovery-p)
                                                 :environment active-environment
                                                 :metadata (list :path (platform-path-designator path)))))
    (call-with-platform-governed-actor
     session
     request
     (lambda ()
       (perform-platform-import-package-service path
                                                :environment active-environment
                                                :session session
                                                :allow-downgrade-p allow-downgrade-p
                                                :allow-untrusted-p allow-untrusted-p
                                                :allow-deprecated-p allow-deprecated-p
                                                :allow-manual-recovery-p allow-manual-recovery-p))
     :platform/import-package
     :import-package
     :environment active-environment
     :metadata (list :path (platform-path-designator path))
     :policy-id :platform-import-package)))

(defun query-platform-package-registry-service (&key environment session)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
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

(defun query-platform-package-history-service (&key environment session package-id limit)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (history (platform-package-history-entries active-environment))
         (filtered (if package-id
                       (remove-if-not (lambda (entry)
                                        (string= (getf entry :package-id) package-id))
                                      history)
                       history))
         (effective-limit (cond
                            ((null limit) 50)
                            ((and (integerp limit) (plusp limit)) limit)
                            (t (error "platform history limit must be a positive integer"))))
         (tail (let ((count (length filtered)))
                 (if (> count effective-limit)
                     (nthcdr (- count effective-limit) filtered)
                     filtered))))
    (make-service-query-response :platform
                                 :package-history
                                 (list :count (length filtered)
                                       :limit effective-limit
                                       :package-id package-id
                                       :entries tail)
                                  :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-package-history-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-platform-audit-service (&key environment session)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (registry (platform-registry-entries active-environment))
         (history (platform-package-history-entries active-environment))
         (active-packages (remove-if-not (lambda (entry)
                                           (platform-entry-active-p entry active-environment))
                                         registry))
         (audit-packages (mapcar (lambda (entry)
                                   (platform-audit-package-summary entry history active-environment))
                                 registry)))
    (make-service-query-response :platform
                                 :audit
                                 (list :count (length registry)
                                       :active-count (length active-packages)
                                       :history-count (length history)
                                       :override-count (platform-history-override-count history)
                                       :untrusted-count (count-if (lambda (entry)
                                                                    (not (getf entry :provenance-trusted-p)))
                                                                  registry)
                                       :deprecated-count (count-if (lambda (entry)
                                                                     (getf entry :lifecycle-override-required-p))
                                                                   registry)
                                       :manual-recovery-count (count-if (lambda (entry)
                                                                          (getf entry :recovery-override-required-p))
                                                                        registry)
                                       :manual-update-count (count-if (lambda (entry)
                                                                        (string= (or (platform-object-entry (getf entry :support)
                                                                                                           "update_channel")
                                                                                     "")
                                                                                 "manual"))
                                                                     registry)
                                       :attention-count (count-if (lambda (entry)
                                                                    (getf entry :attention-required-p))
                                                                  audit-packages)
                                       :packages audit-packages)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-audit-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-platform-imported-package-service (package-id &key environment session)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
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
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
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

(defun query-platform-harness-service (&key environment session)
  (let ((active-environment (platform-resolve-environment :environment environment
                                                          :session session)))
    (make-service-query-response :platform
                                 :harness
                                 (list :count (length +platform-harness-catalog+)
                                       :available-count (count-if (lambda (entry)
                                                                    (getf entry :available-p))
                                                                  (platform-harness-entries))
                                       :harnesses (platform-harness-entries))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-harness-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun perform-platform-run-harness-service (&key harness-id environment session)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (resolved-id (or harness-id :internal-evaluations))
         (entry (or (platform-find-harness-entry resolved-id)
                    (error "Unknown platform harness ~S" resolved-id)))
         (runner (platform-harness-runner-function entry)))
    (unless runner
      (error "Platform harness ~S is unavailable in this runtime" resolved-id))
    (let ((report (funcall runner)))
      (make-service-command-response :platform
                                     :run-harness
                                     (list :harness (platform-harness-summary entry)
                                           :report report)
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :platform-harness-run-v2
                                                                      :session session
                                                                      :environment active-environment
                                                                      :policy-id :platform-run-harness)))))

(defun command-platform-run-harness-service (&key harness-id environment session)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (resolved-id (or harness-id :internal-evaluations))
         (request (make-platform-control-request session
                                                 :run-harness
                                                 :platform/run-harness
                                                 :payload (list :harness-id resolved-id)
                                                 :environment active-environment
                                                 :metadata (list :harness-id resolved-id))))
    (call-with-platform-governed-actor
     session
     request
     (lambda ()
       (perform-platform-run-harness-service
        :harness-id resolved-id
        :environment active-environment
        :session session))
     :platform/run-harness
     :run-harness
     :environment active-environment
     :metadata (list :harness-id resolved-id)
     :policy-id :platform-run-harness)))

(defun query-platform-profile-service (&key environment session)
  (let ((active-environment (platform-resolve-environment :environment environment
                                                          :session session)))
    (make-service-query-response :platform
                                 :profile
                                 (platform-active-package-profile active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-profile-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun perform-platform-activate-package-service (package-id &key environment session)
  (let ((active-environment (platform-resolve-environment :environment environment
                                                          :session session)))
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
      (call-with-platform-state
       active-environment
       (lambda ()
         (replace-platform-active-package-ids active-environment updated-active-ids)
         (replace-platform-package-history-entries
          active-environment
          (append (%platform-package-history-entries active-environment)
                  (list (list :timestamp (get-universal-time)
                              :action :activate
                              :package-id (getf entry :package-id)
                              :package-version (getf entry :package-version)
                              :path (getf entry :path)
                              :session-id (and session (agent-session-id session))
                              :active-p t))))))
      (make-service-command-response :platform
                                     :activate-package
                                     (list :package (platform-registry-summary entry active-environment)
                                           :active-count (length updated-active-ids)
                                           :registry-count (length updated-registry))
                                     :metadata (make-service-metadata :authority :environment
                                                                     :command-model :platform-package-activation-v2
                                                                     :session session
                                                                     :environment active-environment
                                                                     :policy-id :platform-activate-package)))))

(defun command-platform-activate-package-service (package-id &key environment session)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (request (make-platform-control-request session
                                                 :activate-package
                                                 :platform/activate-package
                                                 :payload (list :package-id package-id)
                                                 :environment active-environment
                                                 :metadata (list :package-id package-id))))
    (call-with-platform-governed-actor
     session
     request
     (lambda ()
       (perform-platform-activate-package-service package-id
                                                  :environment active-environment
                                                  :session session))
     :platform/activate-package
     :activate-package
     :environment active-environment
     :metadata (list :package-id package-id)
     :policy-id :platform-activate-package)))

(defun perform-platform-install-package-service (path &key environment session allow-downgrade-p allow-untrusted-p allow-deprecated-p allow-manual-recovery-p)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (import-response (perform-platform-import-package-service path
                                                                  :allow-downgrade-p allow-downgrade-p
                                                                  :allow-deprecated-p allow-deprecated-p
                                                                  :allow-manual-recovery-p allow-manual-recovery-p
                                                                  :allow-untrusted-p allow-untrusted-p
                                                                  :environment active-environment
                                                                  :session session))
         (package-id (getf (getf (service-response-data import-response) :package) :package-id))
         (activate-response (perform-platform-activate-package-service package-id
                                                                      :environment active-environment
                                                                      :session session))
         (activate-result (service-response-data activate-response))
         (installed-package (getf activate-result :package)))
    (record-platform-package-history active-environment
                                     :install
                                     installed-package
                                     :session session
                                     :update-posture (getf installed-package :update-posture)
                                     :downgrade-p (getf installed-package :downgrade-p)
                                     :deprecated-p (getf installed-package :deprecated-p)
                                     :manual-recovery-p (getf installed-package :manual-recovery-p)
                                     :untrusted-p (getf installed-package :untrusted-p)
                                     :downgrade-override-p (and (getf installed-package :downgrade-p)
                                                                allow-downgrade-p)
                                     :deprecated-override-p (and (getf installed-package :deprecated-p)
                                                                 allow-deprecated-p)
                                     :manual-recovery-override-p (and (getf installed-package :manual-recovery-p)
                                                                      allow-manual-recovery-p)
                                     :untrusted-override-p (and (getf installed-package :untrusted-p)
                                                                allow-untrusted-p)
                                     :active-p t)
    (make-service-command-response :platform
                                   :install-package
                                   (list :path (platform-path-designator path)
                                         :package installed-package
                                         :active-count (getf activate-result :active-count)
                                         :registry-count (getf activate-result :registry-count)
                                         :profile (platform-active-package-profile active-environment))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :platform-package-install-v2
                                                                    :session session
                                                                    :environment active-environment
                                                                    :policy-id :platform-install-package))))

(defun command-platform-install-package-service (path &key environment session allow-downgrade-p allow-untrusted-p allow-deprecated-p allow-manual-recovery-p)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (request (make-platform-control-request session
                                                 :install-package
                                                 :platform/install-package
                                                 :payload (list :path (platform-path-designator path)
                                                                :allow-downgrade allow-downgrade-p
                                                                :allow-untrusted allow-untrusted-p
                                                                :allow-deprecated allow-deprecated-p
                                                                :allow-manual-recovery allow-manual-recovery-p)
                                                 :environment active-environment
                                                 :metadata (list :path (platform-path-designator path)))))
    (call-with-platform-governed-actor
     session
     request
     (lambda ()
       (perform-platform-install-package-service path
                                                 :environment active-environment
                                                 :session session
                                                 :allow-downgrade-p allow-downgrade-p
                                                 :allow-untrusted-p allow-untrusted-p
                                                 :allow-deprecated-p allow-deprecated-p
                                                 :allow-manual-recovery-p allow-manual-recovery-p))
     :platform/install-package
     :install-package
     :environment active-environment
     :metadata (list :path (platform-path-designator path))
     :policy-id :platform-install-package)))

(defun perform-platform-deactivate-package-service (package-id &key environment session)
  (let ((active-environment (platform-resolve-environment :environment environment
                                                          :session session)))
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
      (call-with-platform-state
       active-environment
       (lambda ()
         (replace-platform-active-package-ids active-environment updated-active-ids)
         (replace-platform-package-history-entries
          active-environment
          (append (%platform-package-history-entries active-environment)
                  (list (list :timestamp (get-universal-time)
                              :action :deactivate
                              :package-id (getf entry :package-id)
                              :package-version (getf entry :package-version)
                              :path (getf entry :path)
                              :session-id (and session (agent-session-id session))
                              :active-p nil))))))
      (make-service-command-response :platform
                                     :deactivate-package
                                     (list :package (platform-registry-summary entry active-environment)
                                           :active-count (length updated-active-ids)
                                           :registry-count (length updated-registry))
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :platform-package-activation-v2
                                                                      :session session
                                                                      :environment active-environment
                                                                      :policy-id :platform-deactivate-package)))))

(defun command-platform-deactivate-package-service (package-id &key environment session)
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (request (make-platform-control-request session
                                                 :deactivate-package
                                                 :platform/deactivate-package
                                                 :payload (list :package-id package-id)
                                                 :environment active-environment
                                                 :metadata (list :package-id package-id))))
    (call-with-platform-governed-actor
     session
     request
     (lambda ()
       (perform-platform-deactivate-package-service package-id
                                                    :environment active-environment
                                                    :session session))
     :platform/deactivate-package
     :deactivate-package
     :environment active-environment
     :metadata (list :package-id package-id)
     :policy-id :platform-deactivate-package)))

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

(defun platform-merge-policy-entries (policy-entries extra-policy-ids)
  (let ((all-policy-ids (copy-list (platform-policy-ids policy-entries))))
    (dolist (policy-id extra-policy-ids)
      (pushnew policy-id all-policy-ids :test #'eq))
    (mapcar #'capability-policy-summary
            (sort (mapcar #'ensure-capability-policy all-policy-ids)
                  #'string<
                  :key (lambda (policy) (symbol-name (capability-policy-id policy)))))))

(defun platform-manifest-data (&key capability-ids environment session)
  (let* ((capability-entries (platform-capability-entries :capability-ids capability-ids))
         (compatibility-app-entries (platform-compatibility-app-entries capability-entries
                                                                        :environment environment
                                                                        :session session))
         (policy-entries (platform-merge-policy-entries
                          (platform-policy-entries capability-entries)
                          (mapcar (lambda (entry) (getf entry :policy-id))
                                  compatibility-app-entries)))
         (workflow-entries (platform-workflow-entries capability-entries))
         (compatibility-entries (platform-compatibility-entries capability-entries))
         (sdk-command-entries (platform-sdk-command-entries))
         (active-environment (if session
                                 (service-active-environment :session session
                                                             :environment environment)
                                 (or environment
                                     (and (boundp '*current-environment*)
                                          *current-environment*)))))
    (list :manifest-version +platform-manifest-version+
          :runtime-class :execution-runtime
          :runtime-api '(:invoke :inspect :control)
          :package-format +platform-package-format+
          :sdk-command-count (length sdk-command-entries)
          :workflow-count (length workflow-entries)
          :compatibility-app-count (length compatibility-app-entries)
          :compatibility-kind-count (length compatibility-entries)
          :capability-count (length capability-entries)
          :policy-count (length policy-entries)
          :sdk-commands sdk-command-entries
          :capabilities capability-entries
          :policies policy-entries
          :workflows workflow-entries
          :compatibility-apps compatibility-app-entries
          :compatibility-kinds compatibility-entries
          :environment (when active-environment
                         (list :environment-id (environment-id active-environment)
                               :storage-root (environment-storage-root active-environment)
                               :active-runtime-id (environment-active-runtime-id active-environment))))))

(defparameter +platform-json-array-keys+
  '(:capability-ids
    :policy-ids
    :workflow-ids
    :sdk-command-ids
    :compatibility-app-ids
    :compatibility-kinds
    :capabilities
    :policies
    :workflows
    :sdk-commands
    :compatibility-apps
    :required-capabilities
    :entrypoints
    :control-actions
    :default-arguments))

(defun platform-json-array-key-p (key)
  (member key +platform-json-array-keys+ :test #'eq))

(defun platform-json-safe-value (value &optional context-key)
  (cond
    ((or (null value) (eq value t) (stringp value) (numberp value))
     (if (and (null value) (platform-json-array-key-p context-key))
         #()
         value))
    ((keywordp value)
     (platform-keyword-string value))
    ((and (symbolp value) (not (listp value)))
     (string-downcase (symbol-name value)))
    ((and (listp value)
          (platform-json-array-key-p context-key))
     (map 'vector (lambda (entry)
                    (platform-json-safe-value entry))
          value))
    ((json-plist-p value)
     (loop for (key entry) on value by #'cddr
           append (list key (platform-json-safe-value entry key))))
    ((and (listp value)
          (every #'keywordp value))
     (map 'vector #'platform-json-safe-value value))
    ((listp value)
     (mapcar #'platform-json-safe-value value))
    ((vectorp value)
     (map 'vector #'platform-json-safe-value value))
    (t
     (princ-to-string value))))

(defun query-platform-manifest-service (&key capability-ids environment session)
  (let ((active-environment (if session
                                (service-active-environment :session session
                                                            :environment environment)
                                environment)))
    (make-service-query-response :platform
                                 :manifest
                                 (platform-manifest-data :capability-ids capability-ids
                                                         :environment active-environment
                                                         :session session)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :platform-manifest-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun perform-platform-package-service (output-path &key package-id package-version title capability-ids environment session publisher build-system source-repository build-kind
                                                    release-status replacement-package-id rollback-strategy
                                                    failure-mode backup-required-p recovery-runbook
                                                    ((:attested-p attested-p) t attested-p-supplied-p))
  (unless output-path
    (error "platform package requires an output path"))
  (let* ((active-environment (if session
                                 (service-active-environment :session session
                                                             :environment environment)
                                 environment))
         (manifest (platform-manifest-data :capability-ids capability-ids
                                           :environment active-environment
                                           :session session))
         (resolved-package-id (or package-id
                                  (format nil "intentos-package-~D" (get-universal-time))))
         (resolved-package-version (or package-version
                                       +platform-default-package-version+))
         (resolved-title (or title "IntentOS Capability Package"))
         (provenance (apply #'platform-provenance-data
                            (append (list :publisher publisher
                                          :build-system build-system
                                          :source-repository source-repository
                                          :build-kind build-kind)
                                    (when attested-p-supplied-p
                                      (list :attested-p attested-p)))))
         (package-descriptor (list :package-format +platform-package-format+
                                   :package-id resolved-package-id
                                   :package-version resolved-package-version
                                   :requires (platform-runtime-requirements-data)
                                   :support (platform-support-data)
                                   :lifecycle (platform-lifecycle-data :release-status release-status
                                                                      :replacement-package-id replacement-package-id)
                                   :recovery (platform-recovery-data :rollback-strategy rollback-strategy
                                                                    :failure-mode failure-mode
                                                                    :backup-required-p backup-required-p
                                                                    :recovery-runbook recovery-runbook)
                                   :provenance provenance
                                   :title resolved-title
                                   :created-at (get-universal-time)
                                   :contents (platform-package-contents-summary manifest)
                                   :manifest manifest))
         (package-descriptor (append package-descriptor
                                     (list :integrity (platform-integrity-data package-descriptor))))
         (validation-issues (platform-package-validation-issues
                             (parse-json (emit-json (platform-json-safe-value package-descriptor))))))
    (unless (valid-platform-package-version-p resolved-package-version)
      (error "Invalid platform package version ~S" resolved-package-version))
    (when validation-issues
      (error "Cannot export invalid platform package: ~{~A~^; ~}" validation-issues))
    (uiop:ensure-all-directories-exist (list output-path))
    (with-open-file (stream output-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string (emit-json (platform-json-safe-value package-descriptor)) stream))
    (make-service-command-response :platform
                                   :package
                                   (let ((requirements (platform-runtime-requirements-data))
                                         (support (platform-support-data))
                                         (integrity (getf package-descriptor :integrity)))
                                     (list :package-id resolved-package-id
                                           :package-version resolved-package-version
                                           :requirements requirements
                                           :support support
                                         :support-valid-p t
                                         :support-issues '()
                                         :lifecycle (platform-lifecycle-data :release-status release-status
                                                                             :replacement-package-id replacement-package-id)
                                         :lifecycle-valid-p t
                                         :lifecycle-issues '()
                                         :lifecycle-override-required-p (member (or release-status
                                                                                   +platform-default-release-status+)
                                                                               '("deprecated" "sunset")
                                                                               :test #'string=)
                                          :recovery (platform-recovery-data :rollback-strategy rollback-strategy
                                                                            :failure-mode failure-mode
                                                                            :backup-required-p backup-required-p
                                                                            :recovery-runbook recovery-runbook)
                                          :recovery-valid-p t
                                          :recovery-issues '()
                                          :recovery-override-required-p (or (string= (or rollback-strategy
                                                                                         +platform-default-rollback-strategy+)
                                                                                     "manual-recovery")
                                                                            (string= (or failure-mode
                                                                                         +platform-default-failure-mode+)
                                                                                     "manual-intervention"))
                                          :provenance provenance
                                           :provenance-valid-p t
                                           :provenance-issues '()
                                           :provenance-trusted-p (null (platform-provenance-trust-issues package-descriptor))
                                           :provenance-trust-issues (platform-provenance-trust-issues package-descriptor)
                                           :integrity integrity
                                           :integrity-valid-p t
                                           :integrity-issues '()
                                           :contract-compatible-p t
                                           :contract-issues '()
                                           :title resolved-title
                                           :output-path output-path
                                           :capability-count (getf manifest :capability-count)
                                           :workflow-count (getf manifest :workflow-count)
                                           :sdk-command-count (getf manifest :sdk-command-count)
                                           :compatibility-kind-count (getf manifest :compatibility-kind-count)
                                           :contents (platform-package-contents-summary manifest)
                                           :manifest manifest))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :platform-package-v2
                                                                    :session session
                                                                    :environment active-environment
                                                                    :policy-id :platform-package))))

(defun command-platform-package-service (output-path &key package-id package-version title capability-ids environment session publisher build-system source-repository build-kind
                                                    release-status replacement-package-id rollback-strategy
                                                    failure-mode backup-required-p recovery-runbook
                                                    ((:attested-p attested-p) t attested-p-supplied-p))
  (unless session
    (return-from command-platform-package-service
      (perform-platform-package-service output-path
                                        :package-id package-id
                                        :package-version package-version
                                        :title title
                                        :capability-ids capability-ids
                                        :environment environment
                                        :session session
                                        :publisher publisher
                                        :build-system build-system
                                        :source-repository source-repository
                                        :build-kind build-kind
                                        :release-status release-status
                                        :replacement-package-id replacement-package-id
                                        :rollback-strategy rollback-strategy
                                        :failure-mode failure-mode
                                        :backup-required-p backup-required-p
                                        :recovery-runbook recovery-runbook
                                        :attested-p attested-p)))
  (let* ((active-environment (platform-resolve-environment :environment environment
                                                           :session session))
         (request (make-platform-control-request session
                                                 :package
                                                 :platform/package
                                                 :payload (append (list :output-path (platform-path-designator output-path)
                                                                        :package-id package-id
                                                                        :package-version package-version
                                                                        :title title
                                                                        :publisher publisher
                                                                        :build-system build-system
                                                                        :source-repository source-repository
                                                                        :build-kind build-kind
                                                                        :release-status release-status
                                                                        :replacement-package-id replacement-package-id
                                                                        :rollback-strategy rollback-strategy
                                                                        :failure-mode failure-mode
                                                                        :recovery-runbook recovery-runbook
                                                                        :capability-ids capability-ids)
                                                                  (when backup-required-p
                                                                    (list :backup-required-p backup-required-p))
                                                                  (when attested-p-supplied-p
                                                                    (list :attested-p attested-p)))
                                                 :environment active-environment
                                                 :metadata (list :output-path (platform-path-designator output-path)))))
    (call-with-platform-governed-actor
     session
     request
     (lambda ()
       (perform-platform-package-service output-path
                                         :package-id package-id
                                         :package-version package-version
                                         :title title
                                         :capability-ids capability-ids
                                         :environment active-environment
                                         :session session
                                         :publisher publisher
                                         :build-system build-system
                                         :source-repository source-repository
                                         :build-kind build-kind
                                         :release-status release-status
                                         :replacement-package-id replacement-package-id
                                         :rollback-strategy rollback-strategy
                                         :failure-mode failure-mode
                                         :backup-required-p backup-required-p
                                         :recovery-runbook recovery-runbook
                                         :attested-p attested-p))
     :platform/package
     :package
     :environment active-environment
     :metadata (list :output-path (platform-path-designator output-path))
     :policy-id :platform-package)))
