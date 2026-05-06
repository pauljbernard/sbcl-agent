(in-package #:sbcl-agent/tests)
;; Shared assertions, fixture helpers, and test providers now live in
;; tests/support.lisp and tests/provider-support.lisp so this file focuses on
;; smoke/integration behavior definitions.

(defun runtime-smoke-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-runtime-XXXXXX"))
         (ignore (ensure-directories-exist root))
         (config (sbcl-agent::load-config :working-directory (namestring root)))
         (provider (sbcl-agent::make-provider config)))
    (declare (ignore ignore))
    (assert-true (typep config 'sbcl-agent::config)
                 "load-config should return a sbcl-agent config struct")
    (assert-true (string= (sbcl-agent::provider-name provider) "mock")
                 "default provider should be mock when no provider or API key is configured")
    (let ((response (sbcl-agent::send-prompt provider "ping")))
      (assert-true (typep response 'sbcl-agent::assistant-response)
                   "provider should return an assistant-response struct")
      (assert-true (search "SBCL scaffold"
                           (sbcl-agent::assistant-response-message response))
                   "mock provider should return the scaffold smoke-test marker"))))

(defun direct-sandbox-tool-wrapper-test ()
  (let ((session (sbcl-agent::make-default-session :cwd "/tmp/")))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::tool-git-status session))
     "sandbox isolation layer"
     "tool-git-status should reject direct execution")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::tool-git-diff session :cached t))
     "sandbox isolation layer"
     "tool-git-diff should reject direct execution")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::tool-git-add session :paths '("README.md")))
     "sandbox isolation layer"
     "tool-git-add should reject direct execution")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::tool-git-commit session :message "msg"))
     "sandbox isolation layer"
     "tool-git-commit should reject direct execution")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::tool-git-branch session :name "branch" :checkout t))
     "sandbox isolation layer"
     "tool-git-branch should reject direct execution")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::tool-proc-run session :argv '("pwd")))
     "sandbox isolation layer"
     "tool-proc-run should reject direct execution")))

(defun repl-alias-test ()
  (let ((provider (make-test-provider)))
    (let ((*standard-input* (make-string-input-stream "")))
      (assert-equal 0
                    (sbcl-agent::start-chat-repl provider)
                    "start-chat-repl should delegate to the shell and exit cleanly on EOF"))))

(defun main-command-helper-test ()
  (assert-equal '("chat")
                (sbcl-agent::normalize-arguments '("--" "chat"))
                "normalize-arguments should drop leading --")
  (assert-equal '("chat")
                (sbcl-agent::normalize-arguments '("chat"))
                "normalize-arguments should preserve normal arguments")
  (assert-equal "mock"
                (sbcl-agent::resolve-provider-name nil nil)
                "resolve-provider-name should default to mock")
  (assert-equal "explicit"
                (sbcl-agent::resolve-provider-name "explicit" nil)
                "resolve-provider-name should prefer explicit provider")
  (assert-equal "openai-compatible"
                (sbcl-agent::resolve-provider-name nil "secret")
                "resolve-provider-name should infer openai-compatible when an API key exists")
  (assert-equal "value"
                (sbcl-agent::require-option-value "--provider" '("value"))
                "require-option-value should return the next argument")
  (assert-signals-error
   (lambda ()
     (sbcl-agent::require-option-value "--provider" '()))
   "Missing value"
   "require-option-value should reject missing values")
  (let ((options (sbcl-agent::parse-chat-arguments
                  '("-i" "--provider" "mock" "--model" "gpt-5" "--api-base" "http://api" "--cwd" "/tmp"))))
    (assert-true (sbcl-agent::chat-options-default-stream-p options)
                 "parse-chat-arguments should enable default streaming")
    (assert-equal "mock" (sbcl-agent::chat-options-provider options)
                  "parse-chat-arguments should capture provider")
    (assert-equal "gpt-5" (sbcl-agent::chat-options-model options)
                  "parse-chat-arguments should capture model")
    (assert-equal "http://api" (sbcl-agent::chat-options-api-base options)
                  "parse-chat-arguments should capture api base")
    (assert-equal "/tmp" (sbcl-agent::chat-options-working-directory options)
                  "parse-chat-arguments should capture cwd"))
  (let ((options (sbcl-agent::parse-chat-arguments '("--working-directory" "/tmp"))))
    (assert-equal "/tmp" (sbcl-agent::chat-options-working-directory options)
                  "parse-chat-arguments should accept --working-directory"))
  (assert-signals-error
   (lambda ()
     (sbcl-agent::parse-chat-arguments '("--unknown")))
   "Unknown chat option"
   "parse-chat-arguments should reject unknown options")
  (let ((options (sbcl-agent::parse-provider-arguments
                  '("configure" "--environment" "/tmp/provider.json" "--profile" "local-fast"
                    "--provider" "lm-studio" "--model" "qwen-coder"
                    "--fast-model" "qwen-coder-mini" "--api-base" "http://localhost:1234/v1"
                    "--intents" "quick-turn,local-development,code-execution"
                    "--working-directory" "/tmp"))))
    (assert-equal "configure" (sbcl-agent::provider-options-subcommand options)
                  "parse-provider-arguments should capture the provider subcommand")
    (assert-equal "/tmp/provider.json" (sbcl-agent::provider-options-environment-path options)
                  "parse-provider-arguments should capture the environment path")
    (assert-equal "local-fast" (sbcl-agent::provider-options-profile-name options)
                  "parse-provider-arguments should capture the profile name")
    (assert-equal "lm-studio" (sbcl-agent::provider-options-provider options)
                  "parse-provider-arguments should capture the provider")
    (assert-equal "qwen-coder" (sbcl-agent::provider-options-model options)
                  "parse-provider-arguments should capture the model")
    (assert-equal "qwen-coder-mini" (sbcl-agent::provider-options-fast-model options)
                  "parse-provider-arguments should capture the fast model")
    (assert-equal "http://localhost:1234/v1" (sbcl-agent::provider-options-api-base options)
                  "parse-provider-arguments should capture the api base")
    (assert-true (equal '(:QUICK-TURN :LOCAL-DEVELOPMENT :CODE-EXECUTION)
                        (sbcl-agent::provider-options-intents options))
                  "parse-provider-arguments should parse comma-delimited intents")
    (assert-equal "/tmp" (sbcl-agent::provider-options-working-directory options)
                  "parse-provider-arguments should capture the working directory"))
  (let ((options (sbcl-agent::parse-provider-arguments '("preview" "--prompt" "Use the local model"))))
    (assert-equal "Use the local model" (sbcl-agent::provider-options-prompt options)
                  "parse-provider-arguments should capture provider preview prompts"))
  (let ((options (sbcl-agent::parse-provider-arguments '("routing" "--mode" "manual"))))
    (assert-equal :manual (sbcl-agent::provider-options-mode options)
                  "parse-provider-arguments should parse provider routing mode"))
  (let ((options (sbcl-agent::parse-rgp-arguments
                  '("workspace" "--environment" "/tmp/rgp-cli.sexp" "--working-directory" "/tmp"))))
    (assert-equal "workspace" (sbcl-agent::rgp-options-subcommand options)
                  "parse-rgp-arguments should capture the rgp workspace subcommand")
    (assert-equal "/tmp/rgp-cli.sexp" (sbcl-agent::rgp-options-environment-path options)
                  "parse-rgp-arguments should capture the rgp environment path")
    (assert-equal "/tmp" (sbcl-agent::rgp-options-working-directory options)
                  "parse-rgp-arguments should capture the rgp working directory"))
  (let ((options (sbcl-agent::parse-platform-arguments
                  '("package" "--input" "/tmp/source.aop" "--output" "/tmp/devkit.aop" "--package-id" "demo-kit"
                    "--title" "Demo Kit" "--capability" "proc/run" "--capability" "git/status"))))
    (assert-equal "package" (sbcl-agent::platform-options-subcommand options)
                  "parse-platform-arguments should capture the platform subcommand")
    (assert-equal "/tmp/source.aop" (sbcl-agent::platform-options-input-path options)
                  "parse-platform-arguments should capture the input path")
    (assert-equal "/tmp/devkit.aop" (sbcl-agent::platform-options-output-path options)
                  "parse-platform-arguments should capture the output path")
    (assert-equal "demo-kit" (sbcl-agent::platform-options-package-id options)
                  "parse-platform-arguments should capture the package id")
    (assert-equal "Demo Kit" (sbcl-agent::platform-options-title options)
                  "parse-platform-arguments should capture the package title")
    (assert-true (equal '(:PROC/RUN :GIT/STATUS)
                        (sbcl-agent::platform-options-capabilities options))
                 "parse-platform-arguments should collect repeated capability flags"))
  (assert-signals-error
   (lambda ()
     (sbcl-agent::parse-provider-arguments '()))
   "provider requires a subcommand"
   "parse-provider-arguments should reject missing subcommands")
  (assert-signals-error
   (lambda ()
     (sbcl-agent::parse-provider-arguments '("show" "--unknown")))
   "Unknown provider option"
   "parse-provider-arguments should reject unknown options")
  (let* ((config (sbcl-agent::make-config :provider "mock"
                                          :model "gpt-5"
                                          :working-directory "/tmp/"))
         (created-session nil))
    (let ((sbcl-agent::*current-session* nil)
          (sbcl-agent::*current-environment* nil))
      (setf created-session (sbcl-agent::session-for-chat-config config))
      (assert-equal "/tmp/" (sbcl-agent::agent-session-cwd created-session)
                    "session-for-chat-config should create a session rooted at the config working directory")
      (assert-true (typep sbcl-agent::*current-environment* 'sbcl-agent::environment)
                   "session-for-chat-config should also establish a current environment")
      (assert-equal "default"
                    (sbcl-agent::environment-active-provider-profile-name sbcl-agent::*current-environment*)
                    "session-for-chat-config should seed the default provider profile")))
  (let* ((config (sbcl-agent::make-config :provider "mock"
                                          :model "gpt-5"
                                          :working-directory "/tmp/"))
         (existing (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (let ((sbcl-agent::*current-session* existing)
          (sbcl-agent::*current-environment* (sbcl-agent::make-default-environment :session existing)))
      (assert-true (eq existing (sbcl-agent::session-for-chat-config config))
                   "session-for-chat-config should reuse the current session")))
  (multiple-value-bind (status stdout stderr)
      (with-captured-output
        (lambda ()
          (sbcl-agent::dispatch-command
           (sbcl-agent::make-config :provider "mock"
                                    :model "gpt-5"
                                    :working-directory "/tmp/")
           '("help"))))
    (declare (ignore stderr))
    (assert-equal 0 status "dispatch-command help should return success")
    (assert-true (search "Usage: sbcl-agent" stdout)
                 "dispatch-command help should print usage"))
  (multiple-value-bind (status stdout stderr)
      (with-captured-output
        (lambda ()
          (sbcl-agent::dispatch-command
           (sbcl-agent::make-config :provider "mock"
                                    :model "gpt-5"
                                    :working-directory "/tmp/")
           '("unknown"))))
    (declare (ignore stdout))
    (assert-equal 1 status "dispatch-command unknown should return failure")
    (assert-true (search "Unknown command" stderr)
                 "dispatch-command unknown should print an error"))
  (assert-signals-error
   (lambda ()
     (sbcl-agent::exec-command '()))
   "exec requires at least one shell argument"
   "exec-command should reject empty argument lists")
  (assert-equal 0
                (sbcl-agent::exec-command '("true"))
                "exec-command should return process exit code")
  (multiple-value-bind (status stdout stderr)
      (with-captured-output
        (lambda ()
          (sbcl-agent::doctor-command
           (sbcl-agent::make-config :provider "mock"
                                    :model "gpt-5"
                                    :working-directory "/tmp/"))))
    (declare (ignore stderr))
    (assert-equal 0 status "doctor-command should return success")
    (assert-true (search "Runtime: SBCL" stdout)
                 "doctor-command should print runtime information")
    (assert-true (search "Environment id:" stdout)
                 "doctor-command should print environment information")
    (assert-true (search "Active provider profile:" stdout)
                 "doctor-command should print provider profile information"))
  (let ((config (sbcl-agent::make-config :provider "mock"
                                         :model "gpt-5"
                                         :working-directory "/tmp/"))
        (original-doctor (symbol-function 'sbcl-agent::doctor-command))
        (original-provider (symbol-function 'sbcl-agent::provider-command))
        (original-platform (symbol-function 'sbcl-agent::platform-command))
        (original-rgp (symbol-function 'sbcl-agent::rgp-command))
        (original-exec (symbol-function 'sbcl-agent::exec-command))
        (original-start-shell (symbol-function 'sbcl-agent::start-shell))
        (original-load-config (symbol-function 'sbcl-agent::load-config))
        (original-dispatch (symbol-function 'sbcl-agent::dispatch-command))
        (original-cli (symbol-function 'uiop:command-line-arguments)))
    (unwind-protect
         (progn
           (setf (symbol-function 'sbcl-agent::doctor-command)
                 (lambda (cfg)
                   (declare (ignore cfg))
                   17))
           (setf (symbol-function 'sbcl-agent::provider-command)
                 (lambda (cfg arguments)
                   (declare (ignore cfg))
                   (assert-equal '("show") arguments
                                 "dispatch-command should route provider arguments through")
                   19))
           (setf (symbol-function 'sbcl-agent::platform-command)
                 (lambda (cfg arguments)
                   (declare (ignore cfg))
                   (assert-equal '("show" "--input" "/tmp/demo.aop") arguments
                                 "dispatch-command should route platform arguments through")
                   21))
           (setf (symbol-function 'sbcl-agent::rgp-command)
                 (lambda (cfg arguments)
                   (declare (ignore cfg))
                   (assert-equal '("workspace" "--environment" "/tmp/rgp-cli.sexp") arguments
                                 "dispatch-command should route rgp arguments through")
                   29))
           (setf (symbol-function 'sbcl-agent::exec-command)
                 (lambda (arguments)
                   (assert-equal '("echo" "hi") arguments
                                 "dispatch-command should pass exec arguments through")
                   23))
           (setf (symbol-function 'sbcl-agent::start-shell)
                 (lambda (provider session &key default-stream-p)
                   (declare (ignore provider session))
                   (if default-stream-p 31 30)))
           (setf (symbol-function 'sbcl-agent::load-config)
                 (lambda (&key &allow-other-keys)
                   config))
           (setf (symbol-function 'sbcl-agent::dispatch-command)
                 (lambda (cfg arguments)
                   (declare (ignore cfg))
                   (if (equal arguments '("exec" "true"))
                       41
                       (funcall original-dispatch config arguments))))
           (setf (symbol-function 'uiop:command-line-arguments)
                 (lambda () '("--" "exec" "true")))
           (assert-equal 17
                         (sbcl-agent::dispatch-command config '("doctor"))
                         "dispatch-command should route to doctor-command")
           (assert-equal 19
                         (sbcl-agent::dispatch-command config '("provider" "show"))
                         "dispatch-command should route to provider-command")
           (assert-equal 21
                         (sbcl-agent::dispatch-command config '("platform" "show" "--input" "/tmp/demo.aop"))
                         "dispatch-command should route to platform-command")
           (assert-equal 29
                         (sbcl-agent::dispatch-command config '("rgp" "workspace" "--environment" "/tmp/rgp-cli.sexp"))
                         "dispatch-command should route to rgp-command")
           (assert-equal 23
                         (sbcl-agent::dispatch-command config '("exec" "echo" "hi"))
                         "dispatch-command should route to exec-command")
           (let ((sbcl-agent::*current-session* nil))
             (assert-equal 31
                           (sbcl-agent::dispatch-command config '("chat" "-i"))
                           "dispatch-command should route chat through start-shell with default streaming enabled"))
           (assert-equal 41
                         (sbcl-agent::main)
                         "main should return the status from dispatch-command"))
      (setf (symbol-function 'sbcl-agent::doctor-command) original-doctor)
      (setf (symbol-function 'sbcl-agent::provider-command) original-provider)
      (setf (symbol-function 'sbcl-agent::platform-command) original-platform)
      (setf (symbol-function 'sbcl-agent::rgp-command) original-rgp)
      (setf (symbol-function 'sbcl-agent::exec-command) original-exec)
      (setf (symbol-function 'sbcl-agent::start-shell) original-start-shell)
      (setf (symbol-function 'sbcl-agent::load-config) original-load-config)
      (setf (symbol-function 'sbcl-agent::dispatch-command) original-dispatch)
      (setf (symbol-function 'uiop:command-line-arguments) original-cli))))

(defun provider-cli-command-test ()
  (let ((sbcl-agent::*current-environment* nil)
        (sbcl-agent::*current-session* nil))
    (let* ((environment-path "/tmp/provider-cli-environment.sexp")
           (config (sbcl-agent::make-config :provider "mock"
                                            :model "gpt-5"
                                            :working-directory "/tmp/provider-cli/")))
      (when (probe-file environment-path)
        (delete-file environment-path))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::provider-command
               config
               '("configure"
                 "--environment" "/tmp/provider-cli-environment.sexp"
                 "--profile" "local-fast"
                 "--provider" "lm-studio"
                 "--model" "qwen-coder"
                 "--fast-model" "qwen-coder-mini"
                 "--api-base" "http://localhost:1234/v1"
                 "--intents" "quick-turn,local-development,code-execution"))))
        (declare (ignore stderr))
        (assert-equal 0 status "provider configure CLI command should return success")
        (assert-true (search "\"operation\":\"provider-configure\"" stdout)
                     "provider configure CLI command should emit the service operation")
        (assert-true (search "\"active_profile_name\":\"default\"" stdout)
                     "provider configure CLI command should emit the provider summary envelope"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::provider-command
               config
               '("routing"
                 "--environment" "/tmp/provider-cli-environment.sexp"
                 "--mode" "manual"))))
        (declare (ignore stderr))
        (assert-equal 0 status "provider routing CLI command should return success")
        (assert-true (search "\"operation\":\"provider-routing\"" stdout)
                     "provider routing CLI command should emit the routing operation")
        (assert-true (search "\"mode\":\"manual\"" stdout)
                     "provider routing CLI command should expose the updated routing mode"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::provider-command
               config
               '("show"
                 "--environment" "/tmp/provider-cli-environment.sexp"))))
        (declare (ignore stderr))
        (assert-equal 0 status "provider show CLI command should return success")
        (assert-true (search "\"operation\":\"provider\"" stdout)
                     "provider show CLI command should emit the provider operation")
        (assert-true (search "\"profile_count\":2" stdout)
                     "provider show CLI command should expose the configured profiles"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::provider-command
               config
               '("route"
                 "--environment" "/tmp/provider-cli-environment.sexp"))))
        (declare (ignore stderr))
        (assert-equal 0 status "provider route CLI command should return success")
        (assert-true (search "\"operation\":\"provider-route\"" stdout)
                     "provider route CLI command should emit the provider-route operation"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::provider-command
               config
               '("routing"
                 "--environment" "/tmp/provider-cli-environment.sexp"
                 "--mode" "auto"))))
        (declare (ignore stdout stderr))
        (assert-equal 0 status "provider routing CLI command should allow switching back to auto"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::provider-command
               config
               '("preview"
                 "--environment" "/tmp/provider-cli-environment.sexp"
                 "--prompt" "Use the local model and implement the fix"))))
        (declare (ignore stderr))
        (assert-equal 0 status "provider preview CLI command should return success")
        (assert-true (search "\"operation\":\"provider-preview\"" stdout)
                     "provider preview CLI command should emit the provider-preview operation")
        (assert-true (search "\"selected_profile_name\":\"local-fast\"" stdout)
                     "provider preview CLI command should expose the previewed selected profile")))))

(defun platform-cli-command-test ()
  (let ((sbcl-agent::*current-environment* nil)
        (sbcl-agent::*current-session* nil))
    (let* ((output-path "/tmp/platform-cli-package.aop")
           (environment-path "/tmp/platform-cli-import.sexp")
           (config (sbcl-agent::make-config :provider "mock"
                                            :model "gpt-5"
                                            :working-directory "/tmp/platform-cli/")))
      (when (probe-file output-path)
        (delete-file output-path))
      (when (probe-file environment-path)
        (delete-file environment-path))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::platform-command
               config
               '("manifest" "--capability" "proc/run"))))
        (declare (ignore stderr))
        (assert-equal 0 status "platform manifest CLI command should return success")
        (assert-true (search "\"operation\":\"manifest\"" stdout)
                     "platform manifest CLI command should emit the manifest operation")
        (assert-true (search "\"capability_count\":1" stdout)
                     "platform manifest CLI command should respect the capability filter")
        (assert-true (search "\"workflow_count\"" stdout)
                     "platform manifest CLI command should emit workflow inventory")
        (assert-true (search "\"sdk_command_count\"" stdout)
                     "platform manifest CLI command should emit sdk command inventory"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::platform-command
               config
               `("package" "--output" ,output-path "--package-id" "demo-kit"
                 "--package-version" "1.2.0" "--title" "Demo Kit"
                 "--capability" "proc/run"))))
        (declare (ignore stderr))
        (assert-equal 0 status "platform package CLI command should return success")
        (assert-true (search "\"operation\":\"package\"" stdout)
                     "platform package CLI command should emit the package operation")
        (assert-true (search "\"package_version\":\"1.2.0\"" stdout)
                     "platform package CLI command should emit the requested package version")
        (assert-true (search "\"required_desktop_contract\":\"desktop-shell-v1\"" stdout)
                     "platform package CLI command should emit runtime contract requirements")
        (assert-true (search "\"support_valid_p\":true" stdout)
                     "platform package CLI command should emit support posture")
        (assert-true (search "\"lifecycle_valid_p\":true" stdout)
                     "platform package CLI command should emit lifecycle posture")
        (assert-true (search "\"recovery_valid_p\":true" stdout)
                     "platform package CLI command should emit recovery posture")
        (assert-true (search "\"provenance_valid_p\":true" stdout)
                     "platform package CLI command should emit provenance posture")
        (assert-true (search "\"provenance_trusted_p\":true" stdout)
                     "platform package CLI command should emit provenance trust posture")
        (assert-true (search "\"integrity_valid_p\":true" stdout)
                     "platform package CLI command should emit integrity posture")
        (assert-true (probe-file output-path)
                     "platform package CLI command should write the .aop descriptor")
        (let ((contents (uiop:read-file-string output-path)))
          (assert-true (search "\"package_id\":\"demo-kit\"" contents)
                       "platform package CLI command should persist the requested package id")
          (assert-true (search "\"package_version\":\"1.2.0\"" contents)
                       "platform package CLI command should persist the requested package version")
          (assert-true (search "\"package_format\":\"intentos.aop.v1\"" contents)
                       "platform package CLI command should persist the package format")
          (assert-true (search "\"required_surface_contract\":\"execution-surfaces-v1\"" contents)
                       "platform package CLI command should persist execution-surface contract requirements")
          (assert-true (search "\"release_channel\":\"stable\"" contents)
                       "platform package CLI command should persist support metadata")
          (assert-true (search "\"release_status\":\"active\"" contents)
                       "platform package CLI command should persist lifecycle metadata")
          (assert-true (search "\"rollback_strategy\":\"reinstall-prior\"" contents)
                       "platform package CLI command should persist recovery metadata")
          (assert-true (search "\"publisher\":\"local-developer\"" contents)
                       "platform package CLI command should persist provenance metadata")
          (assert-true (search "\"attested_p\":true" contents)
                       "platform package CLI command should persist provenance attestation")
          (assert-true (search "\"algorithm\":\"fnv1a-64\"" contents)
                       "platform package CLI command should persist package integrity metadata")
          (assert-true (search "\"contents\"" contents)
                       "platform package CLI command should persist the top-level contents summary")
          (assert-true (search "\"workflow_ids\"" contents)
                       "platform package CLI command should persist workflow inventory")))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::platform-command
               config
               `("show" "--input" ,output-path))))
        (declare (ignore stderr))
        (assert-equal 0 status "platform show CLI command should return success")
        (assert-true (search "\"operation\":\"package\"" stdout)
                     "platform show CLI command should emit the package operation")
        (assert-true (search "\"package_version\":\"1.2.0\"" stdout)
                     "platform show CLI command should preserve the package version")
        (assert-true (search "\"contract_compatible_p\":true" stdout)
                     "platform show CLI command should report contract compatibility")
        (assert-true (search "\"support_valid_p\":true" stdout)
                     "platform show CLI command should report support compatibility")
        (assert-true (search "\"lifecycle_valid_p\":true" stdout)
                     "platform show CLI command should report lifecycle compatibility")
        (assert-true (search "\"recovery_valid_p\":true" stdout)
                     "platform show CLI command should report recovery compatibility")
        (assert-true (search "\"provenance_valid_p\":true" stdout)
                     "platform show CLI command should report provenance compatibility")
        (assert-true (search "\"provenance_trusted_p\":true" stdout)
                     "platform show CLI command should report provenance trust")
        (assert-true (search "\"integrity_valid_p\":true" stdout)
                     "platform show CLI command should report package integrity")
        (assert-true (search "\"valid_p\":true" stdout)
                     "platform show CLI command should report a valid package"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::platform-command
               config
               `("validate" "--input" ,output-path))))
        (declare (ignore stderr))
        (assert-equal 0 status "platform validate CLI command should return success")
        (assert-true (search "\"operation\":\"validate-package\"" stdout)
                     "platform validate CLI command should emit the validation operation")
        (assert-true (search "\"contract_compatible_p\":true" stdout)
                     "platform validate CLI command should report contract compatibility")
        (assert-true (search "\"support_valid_p\":true" stdout)
                     "platform validate CLI command should report support compatibility")
        (assert-true (search "\"lifecycle_valid_p\":true" stdout)
                     "platform validate CLI command should report lifecycle compatibility")
        (assert-true (search "\"recovery_valid_p\":true" stdout)
                     "platform validate CLI command should report recovery compatibility")
        (assert-true (search "\"provenance_valid_p\":true" stdout)
                     "platform validate CLI command should report provenance compatibility")
        (assert-true (search "\"provenance_trusted_p\":true" stdout)
                     "platform validate CLI command should report provenance trust")
        (assert-true (search "\"integrity_valid_p\":true" stdout)
                     "platform validate CLI command should report package integrity")
        (assert-true (search "\"update_posture\":\"new\"" stdout)
                     "platform validate CLI command should mark the first package version as new")
        (assert-true (search "\"valid_p\":true" stdout)
                     "platform validate CLI command should report a valid package"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::platform-command
               config
               `("import" "--environment" ,environment-path "--input" ,output-path))))
        (declare (ignore stderr))
        (assert-equal 0 status "platform import CLI command should return success")
        (assert-true (search "\"operation\":\"import-package\"" stdout)
                     "platform import CLI command should emit the import operation")
        (assert-true (search "\"registry_count\":1" stdout)
                     "platform import CLI command should register the imported package"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::platform-command
               config
               `("list" "--environment" ,environment-path))))
        (declare (ignore stderr))
        (assert-equal 0 status "platform list CLI command should return success")
        (assert-true (search "\"operation\":\"package-registry\"" stdout)
                     "platform list CLI command should emit the registry operation")
        (assert-true (search "\"count\":1" stdout)
                     "platform list CLI command should report imported package count"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::platform-command
               config
               `("history" "--environment" ,environment-path "--package-id" "demo-kit" "--limit" "10"))))
        (declare (ignore stderr))
        (assert-equal 0 status "platform history CLI command should return success")
        (assert-true (search "\"operation\":\"package-history\"" stdout)
                     "platform history CLI command should emit the package-history operation")
        (assert-true (search "\"count\":1" stdout)
                     "platform history CLI command should report imported package history count"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::platform-command
               config
               `("audit" "--environment" ,environment-path))))
        (declare (ignore stderr))
        (assert-equal 0 status "platform audit CLI command should return success")
        (assert-true (search "\"operation\":\"audit\"" stdout)
                     "platform audit CLI command should emit the audit operation")
        (assert-true (search "\"override_count\":0" stdout)
                     "platform audit CLI command should report no override usage before explicit overrides"))
      (multiple-value-bind (status stdout stderr)
          (with-captured-output
            (lambda ()
              (sbcl-agent::platform-command
               config
               `("show-imported" "--environment" ,environment-path "--package-id" "demo-kit"))))
        (declare (ignore stderr))
      (assert-equal 0 status "platform show-imported CLI command should return success")
      (assert-true (search "\"operation\":\"imported-package\"" stdout)
                     "platform show-imported CLI command should emit the imported package operation")
      (assert-true (search "\"package_id\":\"demo-kit\"" stdout)
                     "platform show-imported CLI command should return the imported package")))
    (multiple-value-bind (stdout stderr status)
        (run-main-command
         '("platform" "activate"
           "--environment" "/tmp/platform-cli-import.sexp"
           "--package-id" "demo-kit"))
      (declare (ignore stderr))
      (assert-equal 0 status "platform activate CLI command should return success")
      (assert-true (search "\"operation\":\"activate-package\"" stdout)
                   "platform activate CLI command should emit the activation operation")
      (assert-true (search "\"active_p\":true" stdout)
                   "platform activate CLI command should mark the imported package active"))
    (multiple-value-bind (stdout stderr status)
        (run-main-command
         '("platform" "active"
           "--environment" "/tmp/platform-cli-import.sexp"))
      (declare (ignore stderr))
      (assert-equal 0 status "platform active CLI command should return success")
      (assert-true (search "\"operation\":\"active-packages\"" stdout)
                   "platform active CLI command should emit the active-packages operation")
      (assert-true (search "\"count\":1" stdout)
                   "platform active CLI command should report active imported package count"))
    (multiple-value-bind (stdout stderr status)
        (run-main-command
         '("platform" "profile"
           "--environment" "/tmp/platform-cli-import.sexp"))
      (declare (ignore stderr))
      (assert-equal 0 status "platform profile CLI command should return success")
      (assert-true (search "\"operation\":\"profile\"" stdout)
                   "platform profile CLI command should emit the profile operation")
      (assert-true (search "\"capability_count\":1" stdout)
                   "platform profile CLI command should expose the applied active-package capability set"))
    (multiple-value-bind (stdout stderr status)
        (run-main-command
         '("platform" "deactivate"
           "--environment" "/tmp/platform-cli-import.sexp"
           "--package-id" "demo-kit"))
      (declare (ignore stderr))
      (assert-equal 0 status "platform deactivate CLI command should return success")
      (assert-true (search "\"operation\":\"deactivate-package\"" stdout)
                   "platform deactivate CLI command should emit the deactivation operation")
      (assert-true (search "\"active_p\":false" stdout)
                   "platform deactivate CLI command should mark the imported package inactive"))
    (let ((install-environment-path "/tmp/platform-cli-install.env"))
      (when (probe-file install-environment-path)
        (delete-file install-environment-path))
      (multiple-value-bind (stdout stderr status)
          (run-main-command
           `("platform" "install"
             "--environment" ,install-environment-path
             "--input" "/tmp/platform-cli-package.aop"))
        (declare (ignore stderr))
        (assert-equal 0 status "platform install CLI command should return success")
        (assert-true (search "\"operation\":\"install-package\"" stdout)
                     "platform install CLI command should emit the install operation")
        (assert-true (search "\"active_p\":true" stdout)
                     "platform install CLI command should activate the imported package"))
      (multiple-value-bind (stdout stderr status)
          (run-main-command
           `("platform" "simulate"
             "--environment" ,install-environment-path
             "--input" "/tmp/platform-cli-package.aop"))
        (declare (ignore stderr))
        (assert-equal 0 status "platform simulate CLI command should return success")
        (assert-true (search "\"operation\":\"simulate-package\"" stdout)
                     "platform simulate CLI command should emit the simulate operation")
        (assert-true (search "\"update_posture\":\"same-version\"" stdout)
                     "platform simulate CLI command should recognize same-version replacement posture")
        (assert-true (search "\"simulated_profile\"" stdout)
                     "platform simulate CLI command should expose the simulated profile"))
      (let ((downgrade-path "/tmp/platform-cli-downgrade.aop"))
        (multiple-value-bind (stdout stderr status)
            (run-main-command
             `("platform" "package"
               "--output" ,downgrade-path
               "--package-id" "demo-kit"
               "--package-version" "1.1.0"
               "--title" "Demo Kit"
               "--capability" "proc/run"))
          (declare (ignore stdout stderr))
          (assert-equal 0 status "platform package CLI command should export the downgrade descriptor"))
        (multiple-value-bind (stdout stderr status)
            (run-main-command
             `("platform" "simulate"
               "--environment" ,install-environment-path
               "--input" ,downgrade-path))
          (declare (ignore stderr))
          (assert-equal 0 status "platform simulate CLI command should allow downgrade simulation")
          (assert-true (search "\"update_posture\":\"downgrade\"" stdout)
                       "platform simulate CLI command should report downgrade posture")
          (assert-true (search "\"would_require_override_p\":true" stdout)
                       "platform simulate CLI command should require explicit downgrade override"))
        (assert-signals-error
         (lambda ()
           (run-main-command
            `("platform" "import"
              "--environment" ,install-environment-path
              "--input" ,downgrade-path)))
         "Refusing to downgrade platform package"
         "platform import CLI command should explain refused downgrade imports")
        (multiple-value-bind (stdout stderr status)
            (run-main-command
             `("platform" "import"
               "--environment" ,install-environment-path
               "--input" ,downgrade-path
               "--allow-downgrade"))
          (declare (ignore stderr))
          (assert-equal 0 status "platform import CLI command should allow explicit downgrade override")
          (assert-true (search "\"update_posture\":\"downgrade\"" stdout)
                       "platform import CLI command should preserve downgrade posture when override is granted")))
      (let ((deprecated-path "/tmp/platform-cli-deprecated.aop"))
        (multiple-value-bind (stdout stderr status)
            (run-main-command
             `("platform" "package"
               "--output" ,deprecated-path
               "--package-id" "legacy-kit"
               "--package-version" "2.0.0"
               "--title" "Legacy Kit"
               "--release-status" "deprecated"
               "--replacement-package-id" "modern-kit"
               "--capability" "proc/run"))
          (declare (ignore stdout stderr))
          (assert-equal 0 status "platform package CLI command should export the deprecated descriptor"))
        (multiple-value-bind (stdout stderr status)
            (run-main-command
             `("platform" "simulate"
               "--environment" ,install-environment-path
               "--input" ,deprecated-path))
          (declare (ignore stderr))
          (assert-equal 0 status "platform simulate CLI command should allow deprecated package simulation")
          (assert-true (search "\"would_require_lifecycle_override_p\":true" stdout)
                       "platform simulate CLI command should require explicit lifecycle override for deprecated packages"))
        (assert-signals-error
         (lambda ()
           (run-main-command
            `("platform" "import"
              "--environment" ,install-environment-path
              "--input" ,deprecated-path)))
         "Refusing to import deprecated platform package"
         "platform import CLI command should explain refused deprecated imports")
        (multiple-value-bind (stdout stderr status)
            (run-main-command
             `("platform" "import"
               "--environment" ,install-environment-path
               "--input" ,deprecated-path
               "--allow-deprecated"))
          (declare (ignore stderr))
          (assert-equal 0 status "platform import CLI command should allow explicit lifecycle override")
          (assert-true (search "\"deprecated_p\":true" stdout)
                       "platform import CLI command should preserve deprecated posture when override is granted")))
      (let ((manual-recovery-path "/tmp/platform-cli-manual-recovery.aop"))
        (multiple-value-bind (stdout stderr status)
            (run-main-command
             `("platform" "package"
               "--output" ,manual-recovery-path
               "--package-id" "ops-kit"
               "--package-version" "3.0.0"
               "--title" "Ops Kit"
               "--rollback-strategy" "manual-recovery"
               "--failure-mode" "manual-intervention"
               "--recovery-runbook" "ops://runbooks/ops-kit"
               "--capability" "proc/run"))
          (declare (ignore stdout stderr))
          (assert-equal 0 status "platform package CLI command should export the manual-recovery descriptor"))
        (multiple-value-bind (stdout stderr status)
            (run-main-command
             `("platform" "simulate"
               "--environment" ,install-environment-path
               "--input" ,manual-recovery-path))
          (declare (ignore stderr))
          (assert-equal 0 status "platform simulate CLI command should allow manual-recovery package simulation")
          (assert-true (search "\"would_require_recovery_override_p\":true" stdout)
                       "platform simulate CLI command should require explicit recovery override for manual-recovery packages"))
        (assert-signals-error
         (lambda ()
           (run-main-command
            `("platform" "import"
              "--environment" ,install-environment-path
              "--input" ,manual-recovery-path)))
         "Refusing to import manual-recovery platform package"
         "platform import CLI command should explain refused manual-recovery imports")
        (multiple-value-bind (stdout stderr status)
            (run-main-command
             `("platform" "import"
               "--environment" ,install-environment-path
               "--input" ,manual-recovery-path
               "--allow-manual-recovery"))
          (declare (ignore stderr))
          (assert-equal 0 status "platform import CLI command should allow explicit recovery override")
          (assert-true (search "\"manual_recovery_p\":true" stdout)
                       "platform import CLI command should preserve manual-recovery posture when override is granted")))
      (multiple-value-bind (stdout stderr status)
          (run-main-command
           `("platform" "audit" "--environment" ,install-environment-path))
        (declare (ignore stderr))
        (assert-equal 0 status "platform audit CLI command should return success after override-granted imports")
        (assert-true (search "\"operation\":\"audit\"" stdout)
                     "platform audit CLI command should emit the audit operation after override-granted imports")
        (assert-true (search "\"override_count\":3" stdout)
                     "platform audit CLI command should count explicit override-granted imports")
        (assert-true (search "\"untrusted_count\":0" stdout)
                     "platform audit CLI command should reflect that the install-environment audit does not include the separately imported untrusted package")
        (assert-true (search "\"deprecated_count\":1" stdout)
                     "platform audit CLI command should count deprecated imported packages")
        (assert-true (search "\"manual_recovery_count\":1" stdout)
                     "platform audit CLI command should count manual-recovery imported packages"))
      (multiple-value-bind (stdout stderr status)
          (run-main-command
           '("platform" "harness"))
        (declare (ignore stderr))
        (assert-equal 0 status "platform harness CLI command should return success")
        (assert-true (search "\"operation\":\"harness\"" stdout)
                     "platform harness CLI command should emit the harness operation")
        (assert-true (search "\"internal-evaluations\"" stdout)
                     "platform harness CLI command should list the internal evaluations harness"))
      (multiple-value-bind (stdout stderr status)
          (run-main-command
           '("platform" "run-harness" "--harness-id" "internal-evaluations"))
        (declare (ignore stderr))
        (assert-equal 0 status "platform run-harness CLI command should return success")
        (assert-true (search "\"operation\":\"run-harness\"" stdout)
                     "platform run-harness CLI command should emit the harness run operation")
        (assert-true (search "\"implemented_family_count\"" stdout)
                     "platform run-harness CLI command should return the evaluation report")))))

(defun openai-helper-coverage-test ()
  (let* ((provider (make-instance 'sbcl-agent::openai-compatible-provider
                                  :model "gpt-5"
                                  :fast-model "gpt-4.1-mini"
                                  :api-base "https://api.example.com/v1"
                                  :api-key "secret"))
         (request (sbcl-agent::make-provider-request
                   :prompt "Need a quick answer"
                   :session-summary '(:recent-transcript ((:role :assistant :content "Earlier"))))))
    (assert-equal "openai-compatible"
                  (sbcl-agent::provider-name provider)
                  "openai provider name should match")
    (assert-true (find :streaming (sbcl-agent::provider-capabilities provider))
                 "openai provider capabilities should include streaming")
    (assert-true (search "Return only valid JSON" (sbcl-agent::build-openai-system-prompt))
                 "system prompt should mention JSON response shape")
    (let ((stream-prompt (sbcl-agent::build-openai-stream-system-prompt)))
      (assert-true (search sbcl-agent::+stream-actions-marker+ stream-prompt)
                   "stream prompt should include start marker")
      (assert-true (search sbcl-agent::+stream-actions-end-marker+ stream-prompt)
                   "stream prompt should include end marker"))
    (assert-true (search "User prompt: Need a quick answer"
                         (sbcl-agent::build-openai-user-prompt request))
                 "user prompt should embed provider prompt")
    (assert-true (sbcl-agent::deep-request-p "Need a detailed architecture review")
                 "deep-request-p should detect detailed requests")
    (assert-true (not (sbcl-agent::deep-request-p "short ping"))
                 "deep-request-p should reject shallow prompts")
    (assert-equal "gpt-4.1-mini"
                  (sbcl-agent::openai-request-model provider request)
                  "openai-request-model should choose fast model for shallow prompts")
    (assert-equal "gpt-5"
                  (sbcl-agent::openai-request-model
                   provider
                   (sbcl-agent::make-provider-request :prompt "Need a deep architecture review"))
                  "openai-request-model should choose primary model for deep prompts")
    (assert-true (search "\"stream\":false"
                         (sbcl-agent::build-openai-request-body provider request))
                 "request body should include stream false by default")
    (assert-true (search "\"stream\":true"
                         (sbcl-agent::build-openai-request-body provider request :stream t :stream-protocol t))
                 "request body should include stream true when requested")
    (assert-equal "hello"
                  (sbcl-agent::extract-openai-message-content
                   '(("choices" . ((("message" . (("content" . "hello"))))))))
                  "extract-openai-message-content should read content")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::extract-openai-message-content
        '(("error" . (("message" . "boom"))))))
     "OpenAI API error"
     "extract-openai-message-content should raise API errors")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::extract-openai-message-content '(("choices" . ()))))
     "Could not find assistant content"
     "extract-openai-message-content should fail when content is missing")
    (assert-equal "delta"
                  (sbcl-agent::extract-openai-stream-delta
                   '(("choices" . ((("delta" . (("content" . "delta"))))))))
                  "extract-openai-stream-delta should read delta content")
    (assert-true (sbcl-agent::openai-stream-done-p "data: [DONE]")
                 "openai-stream-done-p should detect completion marker")
    (assert-true (sbcl-agent::openai-stream-data-line-p "data: {}")
                 "openai-stream-data-line-p should detect stream data lines")
    (assert-true (not (sbcl-agent::openai-stream-data-line-p "event: ping"))
                 "openai-stream-data-line-p should reject non-data lines")
    (assert-equal "part"
                  (getf (sbcl-agent::assistant-response-metadata
                         (sbcl-agent::decode-openai-content-response
                          "{\"message\":\"done\",\"actions\":[],\"metadata\":{\"step\":\"part\"}}"
                          "gpt-test"))
                        :STEP)
                  "decode-openai-content-response should preserve metadata")
    (assert-true (sbcl-agent::decoded-action-payload-present-p
                  (sbcl-agent::make-assistant-action :type :eval :payload "(* 2 3)"))
                 "decoded-action-payload-present-p should accept string eval payloads")
    (assert-true (not (sbcl-agent::decoded-action-payload-present-p
                       (sbcl-agent::make-assistant-action :type :eval :payload '(:note "missing form"))))
                 "decoded-action-payload-present-p should reject eval payloads without code")
    (let* ((good (sbcl-agent::make-assistant-action :type :tool :payload '(:tool-id :fs/read)))
           (bad (sbcl-agent::make-assistant-action :type :eval :payload '(:note "missing"))))
      (assert-equal 1
                    (length (sbcl-agent::sanitized-response-actions
                             (sbcl-agent::make-assistant-response :message "x" :actions (list good bad))))
                    "sanitized-response-actions should drop invalid eval actions")))
  (let ((events '()))
    (let ((sbcl-agent::*provider-timing-listener*
            (lambda (phase payload)
              (push (list phase payload) events))))
      (sbcl-agent::emit-provider-timing :phase :count 1))
    (assert-equal :phase (first (first events))
                  "emit-provider-timing should notify listener"))
  (multiple-value-bind (emit rest found)
      (sbcl-agent::parse-stream-visible-fragment
       (concatenate 'string "hello\n" sbcl-agent::+stream-actions-marker+ "{\"actions\":[]}"))
    (assert-true found
                 "parse-stream-visible-fragment should detect the marker")
    (assert-true (search "hello" emit)
                 "parse-stream-visible-fragment should emit visible text")
    (assert-true (search "{\"actions\":[]}" rest)
                 "parse-stream-visible-fragment should return post-marker content"))
  (multiple-value-bind (emit rest found)
      (sbcl-agent::parse-stream-visible-fragment "hello<<<SBCL-ACT")
    (assert-true (not found)
                 "parse-stream-visible-fragment should retain partial markers")
    (assert-equal "hello" emit
                  "parse-stream-visible-fragment should emit the safe prefix")
    (assert-equal "<<<SBCL-ACT" rest
                  "parse-stream-visible-fragment should retain marker overlap"))
  (let ((response (sbcl-agent::finalize-stream-response
                   "visible text
"
                   "{\"actions\":[{\"type\":\"tool\",\"payload\":{\"tool_id\":\":FS/READ\",\"arguments\":[\":path\",\"src/main.lisp\"]}}],\"metadata\":{\"step\":\"done\"}}<<<END-SBCL-ACTIONS>>>"
                   "gpt-test")))
    (assert-equal "visible text"
                  (sbcl-agent::assistant-response-message response)
                  "finalize-stream-response should trim visible text")
    (assert-equal "done"
                  (getf (sbcl-agent::assistant-response-metadata response) :STEP)
                  "finalize-stream-response should preserve metadata")
    (assert-equal 1
                  (length (sbcl-agent::assistant-response-actions response))
                  "finalize-stream-response should decode actions")))

(defun json-helper-coverage-test ()
  (assert-true (sbcl-agent::json-whitespace-char-p #\Space)
               "json-whitespace-char-p should recognize space")
  (assert-true (not (sbcl-agent::json-whitespace-char-p #\A))
               "json-whitespace-char-p should reject non-whitespace")
  (assert-equal 2
                (sbcl-agent::json-skip-whitespace "  \nabc" 0)
                "json-skip-whitespace should skip leading whitespace")
  (multiple-value-bind (value index)
      (sbcl-agent::json-parse-string "\"line\\ntext\"" 0)
    (assert-equal "line
text" value
                  "json-parse-string should decode escapes")
    (assert-equal 12 index
                  "json-parse-string should return the closing index"))
  (assert-signals-error
   (lambda ()
     (sbcl-agent::json-parse-string "\"\\u\"" 0))
   "Unsupported JSON escape"
   "json-parse-string should reject unsupported escapes")
  (assert-signals-error
   (lambda ()
     (sbcl-agent::json-parse-string "\"unterminated" 0))
   "Unterminated JSON string"
   "json-parse-string should reject unterminated strings")
  (multiple-value-bind (value index)
      (sbcl-agent::json-parse-number "-12.5e1" 0)
    (assert-equal -125.0 value
                  "json-parse-number should parse exponents")
    (assert-equal 7 index
                  "json-parse-number should advance the index"))
  (multiple-value-bind (value index)
      (sbcl-agent::json-parse-literal "true" 0 "true" t)
    (assert-true value "json-parse-literal should parse true")
    (assert-equal 4 index "json-parse-literal should advance"))
  (assert-signals-error
   (lambda ()
     (sbcl-agent::json-parse-literal "nope" 0 "true" t))
   "Expected JSON literal"
   "json-parse-literal should reject wrong literal")
  (assert-signals-error
   (lambda ()
     (sbcl-agent::json-parse-array "[1 2]" 0))
   "Expected ',' or ']'"
   "json-parse-array should reject missing comma")
  (assert-signals-error
   (lambda ()
     (sbcl-agent::json-parse-object "{\"a\" 1}" 0))
   "Expected ':'"
   "json-parse-object should reject missing colon")
  (assert-signals-error
   (lambda ()
     (sbcl-agent::parse-json ""))
   "Unexpected end of JSON input"
   "parse-json should reject empty input")
  (assert-equal "a_b"
                (sbcl-agent::keyword->json-key :a-b)
                "keyword->json-key should downcase and replace dashes")
  (assert-true (sbcl-agent::json-plist-p '(:a 1 :b nil))
               "json-plist-p should accept plists")
  (assert-true (not (sbcl-agent::json-plist-p '(:a 1 :b)))
               "json-plist-p should reject odd plists")
  (assert-true (not (sbcl-agent::json-plist-p '(a 1)))
               "json-plist-p should reject non-keyword keys")
  (assert-equal "{\"value\":null,\"ok\":true,\"no\":false,\"items\":[1,\"x\"]}"
                (sbcl-agent::emit-json '(:value :null :ok t :no nil :items (1 "x")))
                "emit-json should serialize mixed values")
  (assert-signals-error
   (lambda ()
     (sbcl-agent::emit-json #\A))
   "Unsupported JSON value"
   "emit-json should reject unsupported values")
  (assert-equal nil
                (sbcl-agent::json-object-value '(("a" . 1)) "missing")
                "json-object-value should return nil for missing keys"))

(defun sandbox-helper-coverage-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-sandbox-XXXXXX"))
         (ignore (ensure-directories-exist root))
         (child (merge-pathnames #P"child/" root))
         (file (merge-pathnames #P"child/test.txt" root))
         (session (sbcl-agent::make-default-session :cwd (namestring root))))
    (declare (ignore ignore))
    (ensure-directories-exist child)
    (with-open-file (stream file :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "sandbox" stream))
    (assert-true (sbcl-agent::find-sandbox-profile :in-process)
                 "find-sandbox-profile should find registered profiles")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::ensure-sandbox-profile :missing))
     "Unknown sandbox profile"
     "ensure-sandbox-profile should reject unknown ids")
    (assert-true (search "/tmp/" (namestring (sbcl-agent::canonicalize-directory-path root)))
                 "canonicalize-directory-path should normalize directories")
    (assert-true (search "child/" (namestring (sbcl-agent::canonicalize-file-parent-directory file)))
                 "canonicalize-file-parent-directory should return parent directory")
    (assert-true (sbcl-agent::path-within-root-p child root)
                 "path-within-root-p should accept descendants")
    (assert-true (not (sbcl-agent::path-within-root-p #P"/etc/" root))
                 "path-within-root-p should reject escapes")
    (assert-true (probe-file (sbcl-agent::ensure-path-within-session session "child/test.txt" :must-exist t))
                 "ensure-path-within-session should return existing files")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::ensure-path-within-session session "newdir/new.txt" :must-exist nil))
     "Path escapes"
     "ensure-path-within-session currently rejects unresolved nested paths")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::ensure-path-within-session session "missing.txt" :must-exist t))
     "Path does not exist"
     "ensure-path-within-session should reject missing files when required")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::ensure-path-within-session session "../escape.txt" :must-exist nil))
     "Path escapes"
     "ensure-path-within-session should reject path escapes")
    (assert-true (search "bin/sandbox-runner" (namestring (sbcl-agent::sandbox-runner-path)))
                 "sandbox-runner-path should resolve to the script")
    (assert-equal '(:ok 1)
                  (sbcl-agent::parse-sandbox-result "(:ok 1)")
                  "parse-sandbox-result should read the worker payload")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::sandbox-execute-process session '()))
     "requires non-empty :argv"
     "sandbox-execute-process should reject empty argv")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::sandbox-execute-git session :add :paths '()))
     "requires non-empty :paths"
     "sandbox-execute-git add should reject empty paths")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::sandbox-execute-git session :commit :message ""))
     "requires non-empty :message"
     "sandbox-execute-git commit should reject empty messages")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::sandbox-execute-git session :branch :name ""))
     "requires non-empty :name"
     "sandbox-execute-git branch should reject empty names")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::sandbox-execute-git session :unknown))
     "Unsupported git sandbox action"
     "sandbox-execute-git should reject unknown actions")
    (assert-true (listp (sbcl-agent::sandbox-worker-environment))
                 "sandbox-worker-environment should return a list")
    (let ((proc-result (sbcl-agent::sandbox-worker-proc-run "/" '("/bin/echo" "hello"))))
      (assert-equal :proc/run (getf proc-result :tool)
                    "sandbox-worker-proc-run should identify the tool")
      (assert-true (search "hello" (getf proc-result :stdout))
                   "sandbox-worker-proc-run should capture stdout")))
  (let ((repo (make-test-git-repo)))
    (let ((status (sbcl-agent::sandbox-worker-git-status repo)))
      (assert-equal :git/status (getf status :tool)
                    "sandbox-worker-git-status should identify the tool"))
    (let ((diff (sbcl-agent::sandbox-worker-git-diff repo '())))
      (assert-equal :git/diff (getf diff :tool)
                    "sandbox-worker-git-diff should identify the tool"))
    (let ((add (sbcl-agent::sandbox-worker-git-add repo '("README.md"))))
      (assert-equal :git/add (getf add :tool)
                    "sandbox-worker-git-add should identify the tool"))
    (let ((commit (sbcl-agent::sandbox-worker-git-commit repo '("message"))))
      (assert-equal :git/commit (getf commit :tool)
                    "sandbox-worker-git-commit should identify the tool"))
    (let ((branch (sbcl-agent::sandbox-worker-git-branch repo '("branch-two"))))
      (assert-equal :git/branch (getf branch :tool)
                    "sandbox-worker-git-branch should identify the tool")
      (assert-true (not (getf branch :checkout))
                   "sandbox-worker-git-branch should report checkout false when omitted"))))

(defun module-reload-coverage-test ()
  (let ((root (uiop:ensure-directory-pathname "/Volumes/data/development/sbcl-agent/")))
    (dolist (path '("src/package.lisp"
                    "src/policy.lisp"
                    "src/tools-process.lisp"
                    "src/tools-git.lisp"
                    "src/tools-fs.lisp"
                    "src/tools-docs.lisp"
                    "src/tools-session.lisp"))
      (load (merge-pathnames path root))))
  (assert-true (find-package :sbcl-agent)
               "reloading package.lisp should preserve the sbcl-agent package")
  (assert-true (eq 'sbcl-agent:main
                   (find-symbol "MAIN" :sbcl-agent))
               "reloading package.lisp should preserve the exported MAIN symbol")
  (assert-true (eq :git/status
                   (sbcl-agent::tool-definition-id
                    (sbcl-agent::find-tool :git/status)))
               "reloading tools-git.lisp should keep git tools registered")
  (assert-true (eq :proc/run
                   (sbcl-agent::tool-definition-id
                    (sbcl-agent::find-tool :proc/run)))
               "reloading tools-process.lisp should keep process tools registered")
  (assert-true (eq :fs/read
                   (sbcl-agent::tool-definition-id
                    (sbcl-agent::find-tool :fs/read)))
               "reloading tools-fs.lisp should keep fs tools registered")
  (assert-true (eq :docs/read
                   (sbcl-agent::tool-definition-id
                    (sbcl-agent::find-tool :docs/read)))
               "reloading tools-docs.lisp should keep docs tools registered")
  (assert-true (eq :session/events
                   (sbcl-agent::tool-definition-id
                    (sbcl-agent::find-tool :session/events)))
               "reloading tools-session.lisp should keep session tools registered")
  (assert-true (eq :workspace-write
                   (sbcl-agent::capability-policy-id
                    (sbcl-agent::find-capability-policy :workspace-write)))
               "reloading policy.lisp should keep policies registered"))

(defun tool-helper-coverage-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-tools-XXXXXX"))
         (docs-dir (merge-pathnames #P"docs/" root))
         (nested-dir (merge-pathnames #P"nested/" root))
         (readme (merge-pathnames #P"README.txt" root))
         (architecture (merge-pathnames #P"docs/architecture.md" root))
         (notes (merge-pathnames #P"nested/notes.txt" root))
         (session (sbcl-agent::make-default-session :cwd (namestring root))))
    (ensure-directories-exist docs-dir)
    (ensure-directories-exist nested-dir)
    (with-open-file (stream readme :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "root readme" stream))
    (with-open-file (stream architecture :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "architecture details" stream))
    (with-open-file (stream notes :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "notes" stream))
    (assert-true (search (namestring root)
                         (namestring (sbcl-agent::session-root-pathname session)))
                 "session-root-pathname should point at the session cwd")
    (assert-equal (namestring notes)
                  (namestring (sbcl-agent::resolve-session-path session "nested/notes.txt"))
                  "resolve-session-path should resolve relative paths")
    (assert-equal #P"/tmp/example.txt"
                  (sbcl-agent::resolve-session-path session "/tmp/example.txt")
                  "resolve-session-path should preserve absolute paths")
    (assert-equal "root readme"
                  (sbcl-agent::read-file-contents readme)
                  "read-file-contents should return file contents")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::tool-fs-read session))
     "requires :path"
     "tool-fs-read should require a path")
    (let ((listing (sbcl-agent::tool-fs-list session :path ".")))
      (assert-equal :fs/list (getf listing :tool)
                    "tool-fs-list should identify itself")
      (assert-true (listp (getf listing :entries))
                   "tool-fs-list should return an entry list"))
    (assert-true (search "/docs/"
                         (namestring (sbcl-agent::docs-root-pathname session)))
                 "docs-root-pathname should resolve the docs directory")
    (assert-true (search "architecture.md"
                         (namestring (sbcl-agent::resolve-doc-path session nil :must-exist t)))
                 "resolve-doc-path should default to architecture.md")
    (let ((listing (sbcl-agent::tool-docs-list session)))
      (assert-equal :docs/list (getf listing :tool)
                    "tool-docs-list should identify itself")
      (assert-true (listp (getf listing :entries))
                   "tool-docs-list should return a docs entry list")))
  (let ((session (sbcl-agent::make-default-session :cwd "/tmp/")))
    (assert-equal 10
                  (sbcl-agent::normalize-tail-count nil)
                  "normalize-tail-count should default nil to ten")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::normalize-tail-count 0))
     "positive integer"
     "normalize-tail-count should reject non-positive values")
    (assert-equal :session/events
                  (getf (sbcl-agent::tool-session-events session) :tool)
                  "tool-session-events should accept a default tail")
    (assert-equal :session/replay-groups
                  (getf (sbcl-agent::tool-session-replay-groups session) :tool)
                  "tool-session-replay-groups should identify itself")
    (assert-equal :session/image-reconciliations
                  (getf (sbcl-agent::tool-session-image-reconciliations session) :tool)
                  "tool-session-image-reconciliations should identify itself")))

(defun policy-helper-coverage-test ()
  (let* ((policy-id :coverage-test-policy)
         (registered (sbcl-agent::register-capability-policy policy-id "Coverage policy"))
         (policy (sbcl-agent::find-capability-policy policy-id))
         (grant (sbcl-agent::make-capability-grant :policy-id policy-id
                                                   :granted-at 123
                                                   :scope :session
                                                   :metadata '(:why :test))))
    (declare (ignore grant))
    (assert-equal policy-id registered
                  "register-capability-policy should return the policy id")
    (assert-equal :session
                  (sbcl-agent::capability-policy-default-grant-mode policy)
                  "register-capability-policy should default grant mode to :session")
    (assert-equal :medium
                  (sbcl-agent::capability-policy-risk-level policy)
                  "register-capability-policy should default risk level to :medium")
    (assert-true (eq policy (sbcl-agent::ensure-capability-policy policy))
                 "ensure-capability-policy should accept policy structs")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::ensure-capability-policy :missing-policy))
     "Unknown capability policy"
     "ensure-capability-policy should reject missing keywords")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::ensure-capability-policy "bad"))
     "Invalid capability policy designator"
     "ensure-capability-policy should reject invalid designators")
    (let ((policies (sbcl-agent::list-capability-policies)))
      (assert-true (find policy-id policies :key (lambda (entry) (getf entry :id)))
                   "list-capability-policies should include custom policies"))))

(defun with-fake-curl (thunk)
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-fake-curl-XXXXXX"))
         (script (merge-pathnames #P"curl" root))
         (old-path (uiop:getenv "PATH"))
         (script-body
           "#!/bin/sh
stream=0
for arg in \"$@\"; do
  if [ \"$arg\" = \"-N\" ]; then
    stream=1
  fi
done
if [ \"${FAKE_CURL_FAIL:-0}\" = \"1\" ]; then
  echo \"fake curl failure\" 1>&2
  exit 7
fi
if [ \"$stream\" = \"1\" ]; then
  printf '%s\n' 'data: {\"choices\":[{\"delta\":{\"content\":\"Visible text\n<<<SBCL-ACTIONS>>>\"}}]}'
  printf '%s\n' 'data: {\"choices\":[{\"delta\":{\"content\":\"{\\\"actions\\\":[{\\\"type\\\":\\\"tool\\\",\\\"payload\\\":{\\\"tool_id\\\":\\\":FS/READ\\\",\\\"arguments\\\":[\\\":path\\\",\\\"src/main.lisp\\\"]}}],\\\"metadata\\\":{\\\"origin\\\":\\\"fake-stream\\\"}}<<<END-SBCL-ACTIONS>>>\"}}]}'
  printf '%s\n' 'data: [DONE]'
else
  printf '%s' '{\"choices\":[{\"message\":{\"content\":\"{\\\"message\\\":\\\"fake-response\\\",\\\"actions\\\":[],\\\"metadata\\\":{\\\"origin\\\":\\\"fake-send\\\"}}\"}}]}'
fi
"))
    (ensure-directories-exist root)
    (with-open-file (stream script :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string script-body stream))
    (multiple-value-bind (code stdout stderr)
        (run-command "chmod" (list "+x" (namestring script)))
      (declare (ignore stdout stderr))
      (assert-equal 0 code "fake curl chmod should succeed"))
    (unwind-protect
         (progn
           (setf (uiop:getenv "PATH")
                 (format nil "~A:~A" (namestring root) (or old-path "")))
           (funcall thunk))
      (setf (uiop:getenv "PATH") (or old-path "")))))

(defun openai-provider-io-coverage-test ()
  (let ((fallback-provider (make-instance 'sbcl-agent::openai-compatible-provider
                                          :model "gpt-5"
                                          :fast-model nil
                                          :api-base "https://api.example.com/v1"
                                          :api-key "secret")))
    (assert-equal "x"
                  (sbcl-agent::extract-openai-stream-delta
                   (sbcl-agent::parse-openai-stream-json-line
                    "data: {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}"))
                  "parse-openai-stream-json-line should decode stream chunks")
    (assert-equal 0
                  (sbcl-agent::longest-marker-overlap "plain text" sbcl-agent::+stream-actions-marker+)
                  "longest-marker-overlap should return zero when there is no overlap")
    (assert-equal "gpt-5"
                  (sbcl-agent::openai-request-model
                   fallback-provider
                   (sbcl-agent::make-provider-request :prompt "short ping"))
                  "openai-request-model should fall back to primary model when no fast model is configured")))
  (assert-signals-error
   (lambda ()
     (sbcl-agent::send-request
      (make-instance 'sbcl-agent::openai-compatible-provider
                     :provider-id "openai-compatible"
                     :model "gpt-5"
                     :fast-model "gpt-4.1-mini"
                     :api-base "https://api.example.com/v1"
                     :api-key nil)
      (sbcl-agent::make-provider-request :prompt "x" :session-summary '())))
   "API key is required for provider openai-compatible"
   "send-request should reject missing API keys")
  (assert-signals-error
   (lambda ()
     (sbcl-agent::stream-request
      (make-instance 'sbcl-agent::openai-compatible-provider
                     :provider-id "openai-compatible"
                     :model "gpt-5"
                     :fast-model "gpt-4.1-mini"
                     :api-base "https://api.example.com/v1"
                     :api-key nil)
      (sbcl-agent::make-provider-request :prompt "x" :session-summary '())
      (lambda (event) (declare (ignore event)))))
   "API key is required for provider openai-compatible"
   "stream-request should reject missing API keys")
  (with-fake-curl
    (lambda ()
      (let* ((provider (make-instance 'sbcl-agent::openai-compatible-provider
                                      :model "gpt-5"
                                      :fast-model "gpt-4.1-mini"
                                      :api-base "https://api.example.com/v1"
                                      :api-key "secret"))
             (request (sbcl-agent::make-provider-request
                       :prompt "Need a fake network round trip"
                       :session-summary '(:recent-transcript ()))))
        (assert-true (search "\"choices\"" (sbcl-agent::curl-json-request "https://api.example.com/v1/chat/completions"
                                                                          "secret"
                                                                          "{}"))
                     "curl-json-request should capture stdout from the fake curl binary")
        (let ((response (sbcl-agent::send-request provider request)))
          (assert-equal "fake-response"
                        (sbcl-agent::assistant-response-message response)
                        "send-request should decode fake curl responses")
          (assert-equal "fake-send"
                        (getf (sbcl-agent::assistant-response-metadata response) :ORIGIN)
                        "send-request should preserve fake metadata"))
        (let ((events '())
              (timings '()))
          (let ((sbcl-agent::*provider-timing-listener*
                  (lambda (phase payload)
                    (push (list phase payload) timings))))
            (let ((response (sbcl-agent::stream-request
                             provider
                             request
                             (lambda (event)
                               (push event events)))))
              (assert-true (search "Visible text"
                                   (sbcl-agent::assistant-response-message response))
                           "stream-request should decode visible text from fake stream")
              (assert-true (find :MESSAGE-DELTA events
                                 :key #'sbcl-agent::provider-event-type)
                           "stream-request should emit message delta events")
              (assert-true (find :MESSAGE-COMPLETE events
                                 :key #'sbcl-agent::provider-event-type)
                           "stream-request should emit message completion events")
              (assert-true (find :request-built timings :key #'first)
                           "stream-request should emit request-built timing")
              (assert-true (find :response-finalized timings :key #'first)
                           "stream-request should emit response-finalized timing"))))
        (setf (uiop:getenv "FAKE_CURL_FAIL") "1")
        (unwind-protect
             (progn
               (assert-signals-error
                (lambda ()
                  (sbcl-agent::curl-json-request "https://api.example.com/v1/chat/completions"
                                                 "secret"
                                                 "{}"))
                "OpenAI request failed"
                "curl-json-request should surface fake curl failures")
               (assert-signals-error
                (lambda ()
                  (sbcl-agent::stream-openai-json-request
                   "https://api.example.com/v1/chat/completions"
                   "secret"
                   "{}"
                   (lambda (line) (declare (ignore line)))))
                "OpenAI streaming request failed"
                "stream-openai-json-request should surface fake curl failures"))
          (setf (uiop:getenv "FAKE_CURL_FAIL") "")))))

(defun provider-protocol-helper-coverage-test ()
  (assert-equal :run-started
                (sbcl-agent::legacy-provider-event-type->canonical-type :message-start)
                "legacy-provider-event-type->canonical-type should normalize message-start")
  (assert-equal :custom
                (sbcl-agent::legacy-provider-event-type->canonical-type :custom)
                "legacy-provider-event-type->canonical-type should preserve unknown types")
  (let ((delta-event (sbcl-agent::make-provider-event :type :message-delta))
        (complete-event (sbcl-agent::make-provider-event :type :message-complete))
        (action-event (sbcl-agent::make-provider-event :type :action-proposal))
        (canonical-event (sbcl-agent::make-provider-event :canonical-type :text-delta)))
    (assert-equal :text-delta
                  (sbcl-agent::provider-event-effective-type delta-event)
                  "provider-event-effective-type should fall back to legacy normalization")
    (assert-true (sbcl-agent::provider-text-delta-event-p delta-event)
                 "provider-text-delta-event-p should detect deltas")
    (assert-true (sbcl-agent::provider-text-delta-event-p canonical-event)
                 "provider-text-delta-event-p should honor canonical types")
    (assert-true (sbcl-agent::provider-text-complete-event-p complete-event)
                 "provider-text-complete-event-p should detect completion events")
    (assert-true (sbcl-agent::provider-action-intent-event-p action-event)
                 "provider-action-intent-event-p should detect tool intents"))
  (assert-equal '(:A 1)
                (sbcl-agent::provider-summary-content '(:a 1))
                "provider-summary-content should preserve non-string values")
  (assert-equal :FS/READ
                (sbcl-agent::normalize-json-derived-value ":fs/read")
                "normalize-json-derived-value should convert keyword-like strings")
  (assert-equal '(:TOOL-ID :FS/READ :ARGUMENTS (:PATH "src/main.lisp"))
                (sbcl-agent::normalize-json-derived-value
                 '(("tool_id" . ":fs/read")
                   ("arguments" . (":path" "src/main.lisp"))))
                "normalize-json-derived-value should convert JSON objects recursively")
  (assert-equal '(:FS/READ "plain")
                (sbcl-agent::normalize-json-derived-value '(":fs/read" "plain"))
                "normalize-json-derived-value should map plain lists recursively")
  (let ((action (sbcl-agent::decode-assistant-action
                 '(("type" . "eval")
                   ("payload" . "(+ 7 8)")))))
    (assert-equal :EVAL
                  (sbcl-agent::assistant-action-type action)
                  "decode-assistant-action should normalize action type strings")
    (assert-equal "(+ 7 8)"
                  (sbcl-agent::assistant-action-payload action)
                  "decode-assistant-action should preserve scalar payloads"))
  (assert-true (sbcl-agent::valid-assistant-action-p
                (sbcl-agent::make-assistant-action :type :patch :payload '((:write "x" "y"))))
               "valid-assistant-action-p should accept patch actions")
  (assert-true (not (sbcl-agent::valid-assistant-action-p
                     (sbcl-agent::make-assistant-action :type :note :payload '(:message "x"))))
               "valid-assistant-action-p should reject unsupported action types")
  (assert-equal '(+ 9 1)
                (sbcl-agent::parse-eval-action-form '(:expression "(+ 9 1)"))
                "parse-eval-action-form should accept :expression payloads")
  (assert-equal '(:raw 1)
                (sbcl-agent::parse-eval-action-form '(:raw 1))
                "parse-eval-action-form should return payloads that do not embed source")
  (assert-equal 42
                (sbcl-agent::parse-eval-action-form 42)
                "parse-eval-action-form should preserve non-list payloads")
  (let* ((root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-provider-protocol-~D-~D/"
                        (get-universal-time)
                        (random 1000000))))
         (session (sbcl-agent::make-default-session :cwd (namestring root))))
    (ensure-directories-exist root)
    (sbcl-agent::approve-policy session :workspace-write)
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-assistant-action
        (sbcl-agent::make-assistant-action :type :tool :payload '(:tool-id "fs/read"))
        session))
     "requires keyword tool id"
     "execute-assistant-action should reject non-keyword tool ids")
    (let* ((patch-result (sbcl-agent::execute-assistant-action
                          (sbcl-agent::make-assistant-action
                           :type :patch
                           :payload '((:write "artifact.txt" "patched content")))
                          session))
           (patched (merge-pathnames #P"artifact.txt" root)))
      (assert-equal :patch (first patch-result)
                    "execute-assistant-action should apply patch actions")
      (assert-equal "patched content"
                    (sbcl-agent::read-file-contents patched)
                    "execute-assistant-action should write patched content"))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-assistant-action
        (sbcl-agent::make-assistant-action :type :unknown :payload nil)
        session))
     "Unsupported assistant action type"
     "execute-assistant-action should reject unknown action types")
    (let* ((results (sbcl-agent::execute-assistant-actions
                     (sbcl-agent::make-assistant-response
                      :message "eval"
                      :actions (list (sbcl-agent::make-assistant-action
                                      :type :eval
                                      :payload "(+ 1 2)")))
                     session)))
      (assert-equal 1
                    (length results)
                    "execute-assistant-actions should execute response actions")
      (assert-equal 3
                    (getf (getf (first results) :result) :result)
                    "execute-assistant-actions should return evaluation results")))
  (let* ((request (sbcl-agent::make-provider-request :prompt "stream me" :session-summary '()))
         (events '())
         (response (sbcl-agent::stream-request
                    (make-instance 'mixed-action-provider)
                    request
                    (lambda (event)
                      (push event events)))))
    (assert-true (typep response 'sbcl-agent::assistant-response)
                 "default provider stream-request should return the response object")
    (assert-equal 4
                  (length events)
                  "default provider stream-request should emit start, delta, action, and complete events"))
  (assert-signals-error
   (lambda ()
     (sbcl-agent::make-provider
      (sbcl-agent::make-config :provider "unknown"
                               :model "gpt-5"
                               :working-directory "/tmp/")))
   "Unsupported provider"
   "make-provider should reject unknown provider names"))

(defun sandbox-main-coverage-test ()
  (assert-signals-error
   (lambda ()
     (sbcl-agent::sandbox-worker-proc-run "/" '()))
   "requires argv"
   "sandbox-worker-proc-run should reject empty argv")
  (let ((repo (make-test-git-repo)))
    (let ((branch (sbcl-agent::sandbox-worker-git-branch repo '("branch-checkout" "--checkout"))))
      (assert-equal :git/branch (getf branch :tool)
                    "sandbox-worker-git-branch should identify checkout operations")
      (assert-true (getf branch :checkout)
                   "sandbox-worker-git-branch should report checkout true when requested"))))
  (assert-signals-error
   (lambda ()
     (with-fake-command-line-arguments
         nil
       (lambda ()
         (sbcl-agent::sandbox-worker-main))))
   "requires a command"
   "sandbox-worker-main should reject missing commands")
  (multiple-value-bind (ignored stdout stderr)
      (run-sandbox-main-with-arguments '("proc-run" "/" "/bin/echo" "sandbox-main"))
    (declare (ignore ignored stderr))
    (assert-true (search ":PROC/RUN" stdout)
                 "sandbox-worker-main should dispatch proc-run commands"))
  (multiple-value-bind (ignored stdout stderr)
      (run-sandbox-main-with-arguments (list "git-status" (make-test-git-repo)))
    (declare (ignore ignored stderr))
    (assert-true (search ":GIT/STATUS" stdout)
                 "sandbox-worker-main should dispatch git-status commands"))
  (assert-signals-error
   (lambda ()
     (with-fake-command-line-arguments
         '("unknown" "/tmp")
       (lambda ()
         (sbcl-agent::sandbox-worker-main))))
   "Unknown sandbox command"
   "sandbox-worker-main should reject unknown commands")

(defun turn-orchestrator-helper-coverage-test ()
  (let* ((eval-action (sbcl-agent::make-assistant-action :type :eval :payload "(* 2 3)"))
         (tool-action (sbcl-agent::make-assistant-action :type :tool :payload '(:tool_id :fs/read)))
         (unknown-tool-action (sbcl-agent::make-assistant-action :type :tool :payload '(:tool-id :unknown/tool)))
         (patch-action (sbcl-agent::make-assistant-action :type :patch :payload '((:write "x" "y"))))
         (other-action (sbcl-agent::make-assistant-action :type :note :payload '(:message "hi"))))
    (assert-equal :safe-read
                  (getf (sbcl-agent::policy-decision-summary :safe-read) :policy-id)
                  "policy-decision-summary should default decision to :allowed")
    (assert-equal :allowed
                  (getf (sbcl-agent::say-provider-operation-policy-decision) :decision)
                  "say-provider-operation-policy-decision should mark provider runs allowed")
    (assert-equal :runtime-eval-safe
                  (getf (sbcl-agent::assistant-action-policy-decision eval-action :allowed) :policy-id)
                  "assistant-action-policy-decision should map eval actions")
    (assert-equal :safe-read
                  (getf (sbcl-agent::assistant-action-policy-decision tool-action :staged) :policy-id)
                  "assistant-action-policy-decision should accept :tool_id payloads")
    (assert-equal nil
                  (getf (sbcl-agent::assistant-action-policy-decision unknown-tool-action :staged) :policy-id)
                  "assistant-action-policy-decision should fall back when a tool is unknown")
    (assert-equal :workspace-write
                  (getf (sbcl-agent::assistant-action-policy-decision patch-action :approval-required) :policy-id)
                  "assistant-action-policy-decision should map patch actions")
    (assert-equal nil
                  (getf (sbcl-agent::assistant-action-policy-decision other-action :staged) :policy-id)
                  "assistant-action-policy-decision should handle unknown action types")
    (assert-equal :staged
                  (sbcl-agent::staged-assistant-action-disposition tool-action)
                  "staged-assistant-action-disposition should stage non-patch actions")
    (assert-equal :staged
                  (sbcl-agent::staged-assistant-action-status tool-action)
                  "staged-assistant-action-status should mark non-patch actions staged")
    (assert-equal "assistant-action"
                  (sbcl-agent::action-operation-name other-action)
                  "action-operation-name should fall back for unknown action types"))
  (let* ((failed-op (sbcl-agent::make-operation :status :failed))
         (completed-op (sbcl-agent::make-operation :status :completed)))
    (assert-equal :failed
                  (sbcl-agent::turn-status-from-action-operations (list failed-op completed-op))
                  "turn-status-from-action-operations should surface failures"))
  (let ((progress '()))
    (let ((sbcl-agent::*task-progress-callback*
            (lambda (phase payload)
              (push (list phase payload) progress))))
      (sbcl-agent::emit-say-progress :phase '(:ok t)))
    (assert-equal :phase (first (first progress))
                  "emit-say-progress should notify the task progress callback")))

(defun shell-helper-coverage-test ()
  (let ((help-text (with-output-to-string (stream)
                     (let ((*standard-output* stream))
                       (sbcl-agent::print-shell-help)))))
    (assert-true (search "(say \"prompt\")" help-text)
                 "print-shell-help should mention SAY")
    (assert-true (search "(provider/show)" help-text)
                 "print-shell-help should mention provider commands")
    (assert-true (search "(provider/routing [:mode])" help-text)
                 "print-shell-help should mention provider routing controls")
    (assert-true (search "(integration/rgp-bind :request-id \"req\" :agent-session-id \"sess\")" help-text)
                 "print-shell-help should mention the RGP binding command"))
  (let* ((session (sbcl-agent::make-default-session))
         (prompt-text (with-output-to-string (stream)
                        (let ((*query-io* stream))
                          (sbcl-agent::shell-prompt session)))))
    (assert-true (search (sbcl-agent::agent-session-id session) prompt-text)
                 "shell-prompt should include the session id"))
  (let* ((input (make-string-input-stream "(help)"))
         (output (make-string-output-stream))
         (*query-io* (make-two-way-stream input output)))
    (assert-equal "HELP"
                  (symbol-name (first (sbcl-agent::read-shell-form (sbcl-agent::make-default-session))))
                  "read-shell-form should read one form from query io"))
  (let ((session (make-test-session)))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-tool-command nil session))
     "TOOL requires a tool id"
     "execute-tool-command should reject missing tool ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-tool-command '("bad") session))
     "TOOL id must be a keyword"
     "execute-tool-command should reject non-keyword tool ids")
    (assert-equal :fs/read
                  (getf (sbcl-agent::execute-tool-command '(:fs/read :path "src/main.lisp") session) :tool)
                  "execute-tool-command should invoke tools directly")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-approve-command '("bad") session))
     "APPROVE requires a keyword policy"
     "execute-approve-command should reject non-keyword policies")
    (sbcl-agent::approve-policy session :workspace-write)
    (assert-equal :write
                  (getf (first (getf (sbcl-agent::execute-patch-command '(((:write "tmp/shell-helper.txt" "ok"))) session) :patch)) :operation)
                  "execute-patch-command should apply approved patches")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-assistant-action-command '("bad") session))
     "assistant-action object"
     "execute-assistant-action-command should reject invalid arguments")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-pending-actions-command session))
     "No pending assistant actions"
     "execute-pending-actions-command should reject missing staged actions")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-session-save-command '(42) session))
     "SESSION/SAVE requires a string path"
     "execute-session-save-command should require a string path")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-thread-new-command '(:title 7) session))
     "THREAD/NEW :TITLE must be a string"
     "execute-thread-new-command should validate titles")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-thread-use-command '(7) session))
     "THREAD/USE requires a string thread id"
     "execute-thread-use-command should validate thread ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-thread-show-command '(7) session))
     "THREAD/SHOW requires a string thread id"
     "execute-thread-show-command should validate thread ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-turn-status-command '(7) session))
     "TURN/STATUS requires a string turn id"
     "execute-turn-status-command should validate turn ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::resume-turn-command-target session "missing"))
     "Unknown turn"
     "resume-turn-command-target should reject unknown turns")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::resume-turn-command-target session nil))
     "No turns recorded"
     "resume-turn-command-target should reject empty sessions")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-describe-task-command '(7) session))
     "DESCRIBE-TASK requires a string task id"
     "execute-describe-task-command should validate task ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-monitor-task-command '(7) session))
     "MONITOR-TASK requires a string task id"
     "execute-monitor-task-command should validate task ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-cancel-task-command '(7) session))
     "CANCEL-TASK requires a string task id"
     "execute-cancel-task-command should validate task ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-stop-worker-command '(7) session))
     "STOP-WORKER requires a string worker id"
     "execute-stop-worker-command should validate worker ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-describe-worker-command '(7) session))
     "DESCRIBE-WORKER requires a string worker id"
     "execute-describe-worker-command should validate worker ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-describe-work-item-command '(7) session))
     "DESCRIBE-WORK-ITEM requires a string work-item id"
     "execute-describe-work-item-command should validate work-item ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-describe-work-item-plan-command '(7) session))
     "DESCRIBE-WORK-ITEM-PLAN requires a string work-item id"
     "execute-describe-work-item-plan-command should validate work-item ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-describe-workflow-record-command '(7) session))
     "DESCRIBE-WORKFLOW-RECORD requires a string workflow record id"
     "execute-describe-workflow-record-command should validate workflow ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-request-work-item-approval-command '("x" "bad") session))
     "requires a keyword policy"
     "execute-request-work-item-approval-command should validate policy ids")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-quarantine-work-item-command '("x" 7) session))
     "requires a string reason"
     "execute-quarantine-work-item-command should validate reasons")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-steer-work-item-plan-command '("x" :phase "bad" :next-step :run-cold-validation) session))
     "STEER-WORK-ITEM-PLAN requires a keyword :phase"
     "execute-steer-work-item-plan-command should validate phases")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-steer-work-item-plan-command '("x" :phase :validate :next-step "bad") session))
     "STEER-WORK-ITEM-PLAN requires a keyword :next-step"
     "execute-steer-work-item-plan-command should validate next-step values")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-why-waiting-command '(7) session))
     "WHY-WAITING requires a string work-item id"
     "execute-why-waiting-command should validate work-item ids"))
  (let ((eval-action (sbcl-agent::make-assistant-action :type :eval :payload "(+ 1 2)"))
        (tool-action (sbcl-agent::make-assistant-action :type :tool :payload '(:tool-id :fs/read))))
    (multiple-value-bind (immediate staged)
        (sbcl-agent::split-assistant-actions (list tool-action eval-action))
      (assert-equal 1 (length immediate)
                    "split-assistant-actions should collect eval actions")
      (assert-equal 1 (length staged)
                    "split-assistant-actions should stage non-eval actions")))
  (assert-equal :fallback
                (sbcl-agent::plist-value '(:a 1) :missing :fallback)
                "plist-value should return defaults")
  (assert-true (not (sbcl-agent::option-present-p '(:a 1) :b))
               "option-present-p should return nil for missing keys")
  (assert-equal '(:b 2)
                (sbcl-agent::remove-plist-key '(:a 1 :b 2) :a)
                "remove-plist-key should drop keys")
  (let ((task-form (sbcl-agent::ask-task-form "ping" '(:stream t :enqueue t))))
    (assert-equal "ASK"
                  (symbol-name (first task-form))
                  "ask-task-form should preserve the ASK operator")
    (assert-equal '("ping" :stream t)
                  (rest task-form)
                  "ask-task-form should remove :enqueue"))
  (assert-equal '(tool :fs/read)
                (sbcl-agent::unwrap-task-form '(quote (tool :fs/read)))
                "unwrap-task-form should unwrap quoted forms")
  (assert-equal '(tool :fs/read)
                (sbcl-agent::unwrap-task-form '(tool :fs/read))
                "unwrap-task-form should preserve bare forms")
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result '(:x 1) :tool)))))
    (assert-true (search "tool>" result)
                 "print-shell-result should render tool results"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result nil :help)))))
    (assert-equal "" result
                  "print-shell-result should print nothing for help"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     '(:id "turn-1"
                       :status :completed
                       :messages ((:role :user :content "prompt")
                                  (:role :assistant :content "first reply")
                                  (:role :assistant :content "follow-up reply"))
                       :operations ((:name "provider-1") (:name "provider-2"))
                       :incidents ((:id "incident-1"))
                       :artifacts ((:title "artifact.txt"))
                       :detail-summary (:runtime-operation-count 1
                                        :runtime-artifact-count 1
                                        :incident-count 1
                                        :work-item-id "work-1"
                                        :work-item-status :committed
                                        :workflow-record-status :committed)
                       :assistant-message (:role :assistant :content "follow-up reply")
                       :recovery (:resumable-p t
                                  :resumable-operation-count 1
                                  :work-item-id "work-1"
                                  :work-item-resume-payload (:resume-command :turn/resume))
                       :awaiting-approval (:awaiting-approval-p nil :blocked-operation-count 0))
                     :turn-status)))))
    (assert-true (search "turn> turn-1 status=COMPLETED messages=3 operations=2 artifacts=1 incidents=1" result)
                 "print-shell-result should render compact turn-status summaries")
    (assert-true (search "turn-summary> runtime-ops=1 runtime-artifacts=1 incidents=1 weakly-grounded=0 deferred-weakly-grounded=0 work-item=work-1 work-status=COMMITTED workflow=COMMITTED" result)
                 "print-shell-result should render turn runtime/workflow summaries")
    (assert-true (search "recovery> resumable=1 interrupted=0 work-item=work-1" result)
                 "print-shell-result should render turn recovery summaries")
    (assert-true (search "assistant> follow-up reply" result)
                 "print-shell-result should render the current assistant message for turn-status"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     '(:id "thread-1"
                       :title "Feature work"
                       :messages ((:role :user :content "prompt"))
                       :turns ((:id "turn-1"))
                       :incidents ((:id "incident-1"))
                       :artifacts ((:title "runtime-eval"))
                       :detail-summary (:runtime-artifact-count 1
                                        :incident-count 1
                                        :work-item-artifact-count 1))
                     :thread-show)))))
    (assert-true (search "thread> thread-1 title=Feature work messages=1 turns=1 artifacts=1 incidents=1" result)
                 "print-shell-result should render compact thread-show summaries")
    (assert-true (search "thread-summary> runtime-artifacts=1 work-item-artifacts=1 incidents=1" result)
                 "print-shell-result should render thread runtime/work-item summaries"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     '((:id "incident-1"
                        :kind :runtime-eval-failure
                        :status :open
                        :turn-id "turn-1"
                        :operation-id "op-1"))
                     :incident-list)))))
    (assert-true (search "incidents> count=1" result)
                 "print-shell-result should render incident list summaries")
    (assert-true (search "incident> incident-1 kind=RUNTIME-EVAL-FAILURE status=OPEN turn=turn-1 operation=op-1" result)
                 "print-shell-result should render compact incident rows"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     '(:workspace-id "workspace-1"
                       :environment-id "env-1"
                       :plan "Focus governed work"
                       :execution-surfaces (:count 2)
                       :display-surfaces (:count 1 :top-surface (:app-id "linux.echo" :window-state :visible :execution-id "exec-display"))
                       :current-focus (:focus-kind :display
                                       :label "linux.echo"
                                       :status :running
                                       :execution-id "exec-display"
                                       :app-id "linux.echo")
                       :recommended-action (:label "Show current display"
                                            :action-kind :show-panel
                                            :command "(display/show :app-id \"linux.echo\")"
                                            :action-id "display:show-panel:linux.echo")
                       :current-display-surface (:app-id "linux.echo" :window-state :visible :execution-id "exec-display")
                       :current-display-posture (:status :running
                                                 :display-surface-kind :desktop-window
                                                 :controllable-p t
                                                 :relaunch-ready-p t
                                                 :supported-actions (:show :next :previous :relaunch)
                                                 :source-package-id "shell-display-kit")
                       :display-actions (:show-command "(display/show :app-id \"linux.echo\")"
                                         :show (:action-id "display:show:linux.echo")
                                         :next-command "(display/step :next)"
                                         :next (:action-id "display:step-panel:next:linux.echo")
                                         :previous-command "(display/step :previous)"
                                         :previous (:action-id "display:step-panel:previous:linux.echo"))
                       :display-action-ids (:show "display:show:linux.echo"
                                            :next "display:step-panel:next:linux.echo"
                                            :previous "display:step-panel:previous:linux.echo")
                       :display-entry-actions (:open (:command "(open :display-app-id \"linux.echo\")"
                                                     :action-id "display:open-panel:linux.echo")
                                               :show (:command "(display/show :app-id \"linux.echo\")"
                                                     :action-id "display:show-panel:linux.echo")
                                               :next (:command "(display/step :next)"
                                                     :action-id "display:step-panel:next:linux.echo")
                                               :previous (:command "(display/step :previous)"
                                                         :action-id "display:step-panel:previous:linux.echo"))
                       :display-entry-action-ids (:open "display:open-panel:linux.echo"
                                                  :show "display:show-panel:linux.echo"
                                                  :next "display:step-panel:next:linux.echo"
                                                  :previous "display:step-panel:previous:linux.echo")
                       :governance-queue (:count 1 :top-item (:queue-kind :approval :execution-id "exec-approval"))
                       :object-browser (:group-count 2)
                       :top-surface (:surface-kind "governed-work" :status :awaiting-approval :execution-id "exec-work"))
                     :workspace-show)))))
    (assert-true (search "workspace-open> (open :surface-index 0)" result)
                 "print-shell-result should render the default workspace open handoff")
    (assert-true (search "workspace-current-focus> kind=DISPLAY label=linux.echo status=RUNNING exec=exec-display app=linux.echo" result)
                 "print-shell-result should render the compact current workspace focus")
    (assert-true (search "workspace-next-action> label=Show current display kind=SHOW-PANEL" result)
                 "print-shell-result should render the recommended next workspace action header")
    (assert-true (search "command=(display/show :app-id \"linux.echo\")" result)
                 "print-shell-result should render the recommended next workspace action command")
    (assert-true (search "action-id=display:show-panel:linux.echo" result)
                 "print-shell-result should render the recommended next workspace action id")
    (assert-true (search "workspace-current-display> app=linux.echo state=VISIBLE exec=exec-display" result)
                 "print-shell-result should render current display posture in workspace summaries")
    (assert-true (search "workspace-display-state> status=RUNNING kind=DESKTOP-WINDOW controllable=T relaunch=T" result)
                 "print-shell-result should render current display lifecycle/control posture in workspace summaries")
    (assert-true (search "source=shell-display-kit" result)
                 "print-shell-result should render the source package for current display posture in workspace summaries")
    (assert-true (search "actions=" result)
                 "print-shell-result should render a supported action set for current display posture in workspace summaries")
    (assert-true (search "SHOW" result)
                 "print-shell-result should include SHOW in the supported action set for current display posture")
    (assert-true (search "NEXT" result)
                 "print-shell-result should include NEXT in the supported action set for current display posture")
    (assert-true (search "PREVIOUS" result)
                 "print-shell-result should include PREVIOUS in the supported action set for current display posture")
    (assert-true (search "RELAUNCH" result)
                 "print-shell-result should include RELAUNCH in the supported action set for current display posture")
    (assert-true (search "workspace-display-actions>" result)
                 "print-shell-result should render display lane actions in workspace summaries")
    (assert-true (search "(display/show :app-id \"linux.echo\")" result)
                 "print-shell-result should render the show action in workspace display lane actions")
    (assert-true (search "(display/step :next)" result)
                 "print-shell-result should render the next action in workspace display lane actions")
    (assert-true (search "(display/step :previous)" result)
                 "print-shell-result should render the previous action in workspace display lane actions")
    (assert-true (search "workspace-display-action-ids>" result)
                 "print-shell-result should render stable action ids for current display actions in workspace summaries")
    (assert-true (search "display:show:linux.echo" result)
                 "print-shell-result should render the show action id in workspace display lane actions")
    (assert-true (search "display:step-panel:next:linux.echo" result)
                 "print-shell-result should render the next action id in workspace display lane actions")
    (assert-true (search "display:step-panel:previous:linux.echo" result)
                 "print-shell-result should render the previous action id in workspace display lane actions")
    (assert-true (search "workspace-display-entry-actions>" result)
                 "print-shell-result should render structured display entry actions in workspace summaries")
    (assert-true (search "(open :display-app-id \"linux.echo\")" result)
                 "print-shell-result should render the open action in workspace display entry actions")
    (assert-true (search "workspace-display-entry-action-ids>" result)
                 "print-shell-result should render stable action ids for display entry actions in workspace summaries")
    (assert-true (search "display:open-panel:linux.echo" result)
                 "print-shell-result should render the open action id in workspace display entry actions")
    (assert-true (search "workspace-governance-open> (open :governance-index 0)" result)
                 "print-shell-result should render the default governance open handoff from workspace"))
  (let (result)
    (setf result
          (with-output-to-string (stream)
            (let ((*standard-output* stream))
              (sbcl-agent::print-shell-result
               '(:workspace-id "workspace-1"
                 :environment-id "env-1"
                 :plan "Desktop focus"
                 :surface-count 2
                 :display-count 1
                 :governance-count 1
                 :object-group-count 2
                 :focus-object-id "exec-display"
                 :entry-points ((:entry-kind :display :label "Active display"))
                 :active-panel :display
                 :active-panel-summary (:panel-id :display
                                        :label "Display"
                                        :focus-object-id "exec-display"
                                        :execution-id "exec-display"
                                        :app-id "linux.echo"
                                        :status :running)
                 :recommended-action (:label "Show selected display"
                                      :action-kind :show-panel
                                      :command "(display/show :app-id \"linux.echo\")"
                                      :action-id "display:show-panel:linux.echo")
                 :panels (:display (:selected-index 0
                                   :selected-execution-id "exec-display"
                                   :selected-app-id "linux.echo"
                                   :selected-window-state :visible
                                   :selected-status :running
                                   :selected-display-surface-kind :desktop-window
                                   :selected-controllable-p t
                                   :selected-relaunch-ready-p t
                                   :selected-supported-actions (:show :next :previous :relaunch)
                                   :actions (:show-command "(display/show :app-id \"linux.echo\")"
                                             :next-command "(display/step :next)"
                                             :previous-command "(display/step :previous)"
                                             :relaunch-command "(display/control :action :relaunch :app-id \"linux.echo\")"))
                          :workspace (:selected-index 0
                                      :selected-execution-id "exec-work"
                                      :focus-object-id "exec-work"
                                      :actions (:open-command "(open :surface-index 0)"
                                                :activate (:action-id "workspace:activate-panel:0")
                                                :open (:action-id "workspace:open-panel:0")
                                                :restore (:action-id "workspace:restore-panel:0")))
                          :governance (:selected-index 0
                                       :selected-title "Approval request"
                                       :focus-object-id "exec-approval"
                                       :actions (:open-command "(open :governance-index 0)"))
                          :object-browser (:selected-kind :execution
                                          :selected-index 0
                                          :selected-title "linux.echo"
                                          :focus-object-id "exec-display"
                                          :actions (:open-command "(open :object-kind :execution :object-index 0)"))
                          :inspector (:object-kind :display
                                      :focus-object-id "exec-display"
                                      :actions (:open-command "(inspector/show)"))))
               :desktop-show))))
    (assert-true (search "desktop-active-summary> panel=DISPLAY label=Display focus=exec-display exec=exec-display app=linux.echo status=RUNNING" result)
                 "print-shell-result should render the compact active desktop panel summary")
    (assert-true (search "desktop-next-action> label=Show selected display kind=SHOW-PANEL" result)
                 "print-shell-result should render the recommended next desktop action header")
    (assert-true (search "command=(display/show :app-id \"linux.echo\")" result)
                 "print-shell-result should render the recommended next desktop action command")
    (assert-true (search "action-id=display:show-panel:linux.echo" result)
                 "print-shell-result should render the recommended next desktop action id"))
  (let (result)
    (setf result
          (with-output-to-string (stream)
            (let ((*standard-output* stream))
              (sbcl-agent::print-shell-result
               '(:workspace-id "workspace-1"
                 :environment-id "env-1"
                 :plan "Inspector focus"
                 :surface-count 2
                 :display-count 0
                 :governance-count 1
                 :object-group-count 2
                 :focus-object-id "exec-work"
                 :entry-points ((:entry-kind :workspace :label "Top surface"))
                 :active-panel :inspector
                 :active-panel-summary (:panel-id :inspector
                                        :label "Inspector"
                                        :focus-object-id "exec-work"
                                        :execution-id "exec-work"
                                        :status :awaiting-approval
                                        :object-kind :work-item
                                        :resolved-via :execution-handle
                                        :history-count 3)
                 :recommended-action (:label "Open focused execution"
                                      :action-kind :open-panel
                                      :command "(open :execution-id \"exec-work\")"
                                      :action-id "inspector:open-panel:exec-work"))
               :desktop-show))))
    (assert-true (search "desktop-inspector-summary> object=WORK-ITEM resolved=EXECUTION-HANDLE history=3" result)
                 "print-shell-result should render the compact active inspector posture")
    (assert-true (search "desktop-next-action> label=Open focused execution kind=OPEN-PANEL" result)
                 "print-shell-result should render the inspector-focused recommended desktop action header")
    (assert-true (search "command=(open :execution-id \"exec-work\")" result)
                 "print-shell-result should render the inspector-focused recommended desktop action command")
    (assert-true (search "action-id=inspector:open-panel:exec-work" result)
                 "print-shell-result should render the inspector-focused recommended desktop action id"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     '(:count 1
                       :top-item (:queue-kind :approval
                                  :status :awaiting-approval
                                  :execution-id "exec-approval"
                                  :surface (:surface-kind "governed-work")))
                     :governance-queue)))))
    (assert-true (search "governance-open> (open :governance-index 0)" result)
                 "print-shell-result should render the default governance open handoff"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     '(:group-count 1
                       :focus-object-id "exec-work"
                       :top-group (:object-kind :work-item :count 1))
                     :object-browser)))))
    (assert-true (search "object-browser-open> (open :object-kind :WORK-ITEM :object-index 0)" result)
                 "print-shell-result should render the default object-browser open handoff"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     '(:id "env-1"
                       :active-runtime-id "runtime-1"
                       :thread-count 2
                       :artifact-count 3
                       :incident-count 1
                       :event-count 9
                       :operator-status (:blocked-count 1
                                         :quarantined-count 1
                                         :incident-count 1
                                         :open-incident-count 1))
                     :environment-show)))))
    (assert-true (search "environment> env-1 runtime=runtime-1 threads=2 artifacts=3 incidents=1 events=9" result)
                 "print-shell-result should render environment summaries")
    (assert-true (search "environment-operator> blocked=1 quarantined=1 incidents=1 open=1" result)
                 "print-shell-result should render environment operator summaries"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     (list :environment-id "env-1"
                           :event-count 2
                           :events (list (sbcl-agent::make-event :id "event-1"
                                                                 :timestamp 1
                                                                 :kind :incident-created
                                                                 :family :incident
                                                                 :entity-id "incident-1"
                                                                 :thread-id "thread-1"
                                                                 :turn-id "turn-1"
                                                                 :visibility :operator
                                                                 :metadata '(:environment-id "env-1")
                                                                 :payload '(:environment-id "env-1"))))
                     :environment-events)))))
    (assert-true (search "environment-events> env=env-1 count=2 shown=1" result)
                 "print-shell-result should render environment event summaries")
    (assert-true (search "environment-event> INCIDENT-CREATED family=INCIDENT entity=incident-1 env=env-1" result)
                 "print-shell-result should render compact environment event rows"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     '(:id "session-1"
                       :package "SBCL-AGENT-USER"
                       :thread-state (:thread-count 2)
                       :turn-count 3
                       :work-item-count 2
                       :incident-count 1
                       :operator-status (:blocked-count 1
                                         :quarantined-count 1
                                         :incident-count 1
                                         :open-incident-count 1
                                         :durable-count 0)
                       :incident-summary (:count 1
                                          :open-count 1
                                          :recent ((:id "incident-1")))
                       :execution-surfaces (:count 1
                                            :top-surface (:surface-kind "conversation"
                                                          :status :completed
                                                          :execution-id "exec-turn"))
                       :blocked-work-surfaces (:count 1
                                                :top-surface (:surface-kind "governed-work"
                                                              :status :awaiting-approval
                                                              :execution-id "exec-blocked"))
                       :approval-surfaces (:count 1
                                           :top-surface (:surface-kind "governed-work"
                                                         :status :awaiting-approval
                                                         :execution-id "exec-approval")))
                     :describe-session)))))
    (assert-true (search "session> session-1 package=SBCL-AGENT-USER threads=2 turns=3 work-items=2 incidents=1" result)
                 "print-shell-result should render session summaries")
    (assert-true (search "session-operator> blocked=1 quarantined=1 incidents=1 open=1 durable=0" result)
                 "print-shell-result should render session operator summaries")
    (assert-true (search "session-incidents> total=1 open=1 recent=1" result)
                 "print-shell-result should render compact session incident summaries")
    (assert-true (search "session-open> (open :execution-id \"exec-turn\")" result)
                 "print-shell-result should render the default session open handoff")
    (assert-true (search "session-blocked-open> (open :execution-id \"exec-blocked\")" result)
                 "print-shell-result should render the default blocked session handoff")
    (assert-true (search "session-approval-open> (open :execution-id \"exec-approval\")" result)
                 "print-shell-result should render the default approval session handoff"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     '(:environment (:id "env-1")
                       :active-thread (:id "thread-1")
                       :active-runtime (:runtime-id "runtime-1")
                       :blocked-work (:count 1)
                       :incidents (:open-count 1)
                       :operator-posture (:blocked-count 1)
                       :execution-surfaces (:count 1
                                            :top-surface (:surface-kind "conversation"
                                                          :status :completed
                                                          :execution-id "exec-env"))
                       :blocked-work-surfaces (:count 1
                                                :top-surface (:surface-kind "governed-work"
                                                              :status :awaiting-approval
                                                              :execution-id "exec-blocked"))
                       :approval-surfaces (:count 1
                                           :top-surface (:surface-kind "governed-work"
                                                         :status :awaiting-approval
                                                         :execution-id "exec-approval")))
                     :environment-status)))))
    (assert-true (search "environment-open> (open :execution-id \"exec-env\")" result)
                 "print-shell-result should render the default environment open handoff")
    (assert-true (search "blocked-open> (open :execution-id \"exec-blocked\")" result)
                 "print-shell-result should render the default blocked-work open handoff")
    (assert-true (search "approval-open> (open :execution-id \"exec-approval\")" result)
                 "print-shell-result should render the default approval open handoff"))
  (let ((result (with-output-to-string (stream)
                  (let ((*standard-output* stream))
                    (sbcl-agent::print-shell-result
                     `(:turn-id "turn-1"
                       :resumed-operation-count 1
                       :action-result-count 1
                       :followup (:response ,(sbcl-agent::make-assistant-response
                                              :message "Follow-up complete"
                                              :actions '()
                                              :metadata '())))
                     :turn-resume)))))
    (assert-true (search "turn-resume> turn=turn-1 resumed=1 results=1" result)
                 "print-shell-result should render compact turn-resume summaries")
    (assert-true (search "followup> Follow-up complete" result)
                 "print-shell-result should render follow-up assistant text for resumed turns")))

(defun shell-stream-rendering-coverage-test ()
  (multiple-value-bind (ignored stdout stderr)
      (with-captured-output
        (lambda ()
          (sbcl-agent::render-provider-timing :phase '(:count 1))
          (sbcl-agent::render-stream-event
           (sbcl-agent::make-provider-event :canonical-type :run-started))
          (sbcl-agent::render-stream-event
           (sbcl-agent::make-provider-event :canonical-type :text-delta
                                            :payload "hello"))
          (sbcl-agent::render-stream-event
           (sbcl-agent::make-provider-event :canonical-type :text-complete))
          (sbcl-agent::render-stream-event
           (sbcl-agent::make-provider-event :canonical-type :other
                                            :payload '(:x 1)))))
    (declare (ignore ignored stderr))
    (assert-true (search "assistant-timing>" stdout)
                 "render-provider-timing should print timing information")
    (assert-true (search "assistant-stream> hello" stdout)
                 "render-stream-event should print streamed text")
    (assert-true (search "assistant-stream-event>" stdout)
                 "render-stream-event should print fallback events"))
  (let* ((session (sbcl-agent::make-default-session))
         (event (sbcl-agent::make-provider-event :family :provider
                                                 :type :message-delta
                                                 :canonical-type :text-delta
                                                 :legacy-type :message-delta
                                                 :run-id "run-1"
                                                 :operation-id "op-1"
                                                 :thread-id "thread-1"
                                                 :turn-id "turn-1"
                                                 :visibility :user
                                                 :metadata '(:provider-source :mock)
                                                 :payload "delta"))
         (progress '())
         (stream-events '())
         (events nil))
    (let ((sbcl-agent::*task-progress-callback*
            (lambda (phase payload)
              (push (list phase payload) progress)))
          (sbcl-agent::*stream-event-listener*
            (lambda (payload)
              (push payload stream-events))))
      (setf events (sbcl-agent::handle-provider-stream-event session event '())))
    (assert-equal 1
                  (length events)
                  "handle-provider-stream-event should append the new event")
    (let ((recorded (first (sbcl-agent::agent-session-events session))))
      (assert-equal "run-1"
                    (getf (sbcl-agent::event-metadata recorded) :run-id)
                    "handle-provider-stream-event should preserve provider run correlation metadata")
      (assert-equal "op-1"
                    (getf (sbcl-agent::event-metadata recorded) :operation-id)
                    "handle-provider-stream-event should preserve provider operation correlation metadata")
      (assert-equal "thread-1"
                    (sbcl-agent::event-thread-id recorded)
                    "handle-provider-stream-event should project provider thread identity onto session events")
      (assert-equal "turn-1"
                    (sbcl-agent::event-turn-id recorded)
                    "handle-provider-stream-event should project provider turn identity onto session events"))
    (assert-equal 1
                  (length stream-events)
                  "handle-provider-stream-event should notify the stream listener")
    (assert-equal :provider-stream
                  (first (first progress))
                  "handle-provider-stream-event should notify task progress listeners"))
  (assert-signals-error
   (lambda ()
     (sbcl-agent::parse-ask-arguments '(42)))
   "ASK requires a single string prompt"
   "parse-ask-arguments should reject non-string prompts")
  (assert-signals-error
   (lambda ()
     (sbcl-agent::parse-ask-arguments '("ok" :stream)))
   "property list"
   "parse-ask-arguments should reject odd keyword option lists"))

(defun turn-orchestrator-run-coverage-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (thread (sbcl-agent::current-thread session))
         (progress '()))
    (let ((sbcl-agent::*task-progress-callback*
            (lambda (phase payload)
              (push (list phase payload) progress))))
      (let ((result (sbcl-agent::run-say-turn-sync
                     (make-instance 'mixed-action-provider)
                     session
                     thread
                     "sync prompt")))
        (assert-equal nil
                      (getf result :streamed-p)
                      "run-say-turn-sync should report non-streaming turns")
        (assert-equal 1
                      (getf result :immediate-action-count)
                      "run-say-turn-sync should record immediate actions")
        (assert-equal 1
                      (getf result :staged-action-count)
                      "run-say-turn-sync should record staged actions")
        (assert-equal :completed
                      (sbcl-agent::turn-status
                       (first (last (sbcl-agent::agent-session-turns session))))
                      "run-say-turn-sync should complete the turn after staging follow-up actions")
        (assert-equal 1
                      (length (sbcl-agent::agent-session-pending-actions session))
                      "run-say-turn-sync should stage non-immediate actions")))
    (assert-true (find :say-response progress :key #'first)
                 "run-say-turn-sync should emit say-response progress"))
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (thread (sbcl-agent::current-thread session))
         (result (sbcl-agent::run-say-turn-streaming
                  (make-instance 'mixed-action-provider)
                  session
                  thread
                  "stream prompt")))
    (assert-true (getf result :streamed-p)
                 "run-say-turn-streaming should report streamed turns")
    (assert-equal 4
                  (getf result :stream-event-count)
                  "run-say-turn-streaming should capture provider stream events")
    (assert-equal 4
                  (length (getf result :stream-events))
                  "run-say-turn-streaming should return the captured stream events")
    (assert-equal 1
                  (length (sbcl-agent::agent-session-pending-actions session))
                  "run-say-turn-streaming should stage tool actions")
    (assert-true (find :provider-stream
                       (sbcl-agent::agent-session-events session)
                       :key #'sbcl-agent::event-kind)
                 "run-say-turn-streaming should log provider stream events"))
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (result (sbcl-agent::run-say-turn
                  (make-instance 'mixed-action-provider)
                  session
                  "wrapped prompt"
                  :stream-p nil)))
    (assert-equal nil
                  (getf result :streamed-p)
                  "run-say-turn should dispatch the sync path when stream-p is false")))

(defun conversation-helper-coverage-test ()
  (let* ((session (sbcl-agent::make-default-session))
         (existing (sbcl-agent::make-session-thread :title "Existing")))
    (setf (sbcl-agent::agent-session-threads session) (list existing)
          (sbcl-agent::agent-session-current-thread-id session) nil)
    (assert-true (eq existing (sbcl-agent::ensure-default-thread session))
                 "ensure-default-thread should reuse an existing thread when the current thread id is missing")
    (assert-equal (sbcl-agent::thread-id existing)
                  (sbcl-agent::agent-session-current-thread-id session)
                  "ensure-default-thread should restore the current thread id"))
  (let* ((session (sbcl-agent::make-default-session))
         (thread (sbcl-agent::create-thread session)))
    (assert-true (search "Thread " (sbcl-agent::thread-title thread))
                 "create-thread should synthesize a default title when none is provided")
    (assert-signals-error
     (lambda ()
       (sbcl-agent::use-thread session "missing-thread"))
     "Unknown thread"
     "use-thread should reject missing thread ids"))
  (let* ((awaiting (sbcl-agent::make-operation :status :awaiting-approval))
         (failed (sbcl-agent::make-operation :status :failed)))
    (assert-equal :failed
                  (sbcl-agent::turn-status-from-operations '() :current-error-state :boom)
                  "turn-status-from-operations should prefer explicit error state")
    (assert-equal :awaiting-approval
                  (sbcl-agent::turn-status-from-operations (list awaiting))
                  "turn-status-from-operations should detect approval waits")
    (assert-equal :failed
                  (sbcl-agent::turn-status-from-operations (list failed))
                  "turn-status-from-operations should detect failed operations")))

(defun sandbox-branch-coverage-test ()
  (let ((repo (make-test-git-repo)))
    (let ((diff (sbcl-agent::sandbox-execute-git
                 (sbcl-agent::make-default-session :cwd (namestring repo))
                 :diff
                 :cached t)))
      (assert-true (getf diff :cached)
                   "sandbox-execute-git should preserve the cached diff flag"))))
  (let ((session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::sandbox-worker-command "not-a-command" session '()))
     "Sandbox worker failed"
     "sandbox-worker-command should surface worker failures"))

(defun json-roundtrip-test ()
  (let* ((json (sbcl-agent::emit-json (list :message "hello"
                                             :actions (list (list :type "tool"))
                                             :metadata (list :provider "mock"))))
         (parsed (sbcl-agent::parse-json json)))
    (assert-equal "hello"
                  (sbcl-agent::json-object-value parsed "message")
                  "json emitter/parser should roundtrip message field")
    (assert-equal "tool"
                  (sbcl-agent::json-object-value (first (sbcl-agent::json-object-value parsed "actions")) "type")
                  "json emitter/parser should roundtrip nested action field")))

(defun provider-decode-test ()
  (let* ((content-object '(("message" . "decoded")
                           ("actions" . ((("type" . "tool")
                                           ("payload" . (("tool_id" . ":FS/READ")
                                                          ("arguments" . (":path" "src/main.lisp")))))))
                           ("metadata" . (("provider" . "mock")))))
         (response (sbcl-agent::decode-assistant-response-object content-object)))
    (assert-equal "decoded"
                  (sbcl-agent::assistant-response-message response)
                  "provider decoder should preserve message")
    (assert-equal :TOOL
                  (sbcl-agent::assistant-action-type (first (sbcl-agent::assistant-response-actions response)))
                  "provider decoder should normalize action type")
    (assert-equal :FS/READ
                  (getf (sbcl-agent::assistant-action-payload (first (sbcl-agent::assistant-response-actions response))) :TOOL-ID)
                  "provider decoder should normalize tool id keyword")
    (assert-equal :PATH
                  (first (getf (sbcl-agent::assistant-action-payload (first (sbcl-agent::assistant-response-actions response))) :ARGUMENTS))
                  "provider decoder should normalize argument keywords")))

(defun mock-provider-helper-coverage-test ()
  (assert-equal 1
                (length (sbcl-agent::mock-actions-for-prompt "please read src/main.lisp"))
                "mock-actions-for-prompt should create a read action")
  (assert-equal 1
                (length (sbcl-agent::mock-actions-for-prompt "can you list src"))
                "mock-actions-for-prompt should create a list action")
  (assert-equal 1
                (length (sbcl-agent::mock-actions-for-prompt "please create governed project artifacts"))
                "mock-actions-for-prompt should create one governed project creation action")
  (assert-equal 8
                (length (sbcl-agent::mock-actions-for-prompt "please augment governed project artifacts"))
                "mock-actions-for-prompt should create the governed project augmentation action set")
  (assert-equal 2
                (length (sbcl-agent::mock-actions-for-prompt "please revise governed project foundations"))
                "mock-actions-for-prompt should create the governed project foundation revision action set")
  (assert-equal 1
                (length (sbcl-agent::mock-actions-for-prompt "please revise governed architecture posture"))
                "mock-actions-for-prompt should create the governed project architecture revision action set")
  (assert-equal 1
                (length (sbcl-agent::mock-actions-for-prompt "please revise governed testing posture"))
                "mock-actions-for-prompt should create the governed project testing posture revision action set")
  (assert-equal 1
                (length (sbcl-agent::mock-actions-for-prompt "please revise governed release readiness"))
                "mock-actions-for-prompt should create the governed release readiness revision action set")
  (assert-equal 1
                (length (sbcl-agent::mock-actions-for-prompt "please revise governed readiness obligations"))
                "mock-actions-for-prompt should create the governed readiness obligations revision action set")
  (assert-equal nil
                (sbcl-agent::mock-actions-for-prompt "no tool request here")
                "mock-actions-for-prompt should return nil for plain prompts")
  (let ((response (sbcl-agent::build-mock-response "plain prompt" '(:id "s"))))
    (assert-true (search "SBCL scaffold" (sbcl-agent::assistant-response-message response))
                 "build-mock-response should return the scaffold message when no actions are needed")
    (assert-equal :mock
                  (getf (sbcl-agent::assistant-response-metadata response) :provider)
                  "build-mock-response should mark metadata with the provider id"))
  (assert-equal '("abc" "def" "ghi")
                (sbcl-agent::split-stream-message "abcdefghi")
                "split-stream-message should divide messages into chunks")
  (let* ((provider (make-instance 'sbcl-agent::mock-provider :model "gpt-5"))
         (request (sbcl-agent::make-provider-request
                   :prompt "please read src/main.lisp"
                   :session-summary '(:recent-transcript ()))))
    (let ((response (sbcl-agent::send-request provider request)))
      (assert-equal 1
                    (length (sbcl-agent::assistant-response-actions response))
                    "mock provider send-request should return proposed actions"))
    (let ((project-response
            (sbcl-agent::send-request
             provider
             (sbcl-agent::make-provider-request
              :prompt "please create governed project artifacts"
              :session-summary '(:recent-transcript ())))))
      (assert-equal :PROJECT/CREATE
                    (getf (sbcl-agent::assistant-action-payload
                           (first (sbcl-agent::assistant-response-actions project-response)))
                          :tool-id)
                    "mock provider should expose the governed project creation tool action"))
    (let ((events '()))
      (sbcl-agent::stream-request provider
                                  request
                                  (lambda (event)
                                    (push event events)))
      (assert-true (find :ACTION-PROPOSAL events :key #'sbcl-agent::provider-event-type)
                   "mock provider stream-request should emit action proposals")
      (assert-true (> (count :MESSAGE-DELTA events :key #'sbcl-agent::provider-event-type) 1)
                   "mock provider stream-request should emit multiple message deltas"))))

(defun mock-project-authoring-conversation-approval-test ()
  (let* ((provider (make-instance 'sbcl-agent::mock-provider :model "gpt-5"))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (command (sbcl-agent::normalize-form-command '(say "please create governed project artifacts"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (assert-equal :say kind "mock project-authoring say should dispatch as :say")
      (assert-equal :awaiting-approval
                    (getf (getf result :turn) :status)
                    "mock project-authoring say should leave the turn awaiting approval")
      (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions updated-session))
                    "mock project-authoring say should stage one pending governed action")
      (assert-equal 1 (length (sbcl-agent::agent-session-work-items updated-session))
                    "mock project-authoring say should create one governed work item")
      (let ((tool-op (find "assistant-tool"
                           (sbcl-agent::agent-session-operations updated-session)
                           :key #'sbcl-agent::operation-name
                           :test #'string=)))
        (assert-true tool-op "mock project-authoring say should record the governed tool action")
        (assert-equal :awaiting-approval (sbcl-agent::operation-status tool-op)
                      "mock project-authoring tool action should await approval")
        (assert-equal :approval-required
                      (getf (sbcl-agent::operation-policy-decision tool-op) :decision)
                      "mock project-authoring tool action should require approval")
        (assert-equal :project-governance-write
                      (getf (sbcl-agent::operation-policy-decision tool-op) :policy-id)
                      "mock project-authoring tool action should record project-governance-write")))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :project-governance-write))
     provider
     session)
    (multiple-value-bind (resume-result resume-kind resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (assert-equal :turn-resume resume-kind "mock project-authoring resume should dispatch as :turn-resume")
      (assert-equal 1 (getf resume-result :resumed-operation-count)
                    "mock project-authoring resume should execute the approved governed action")
      (assert-equal 1 (length (sbcl-agent::agent-session-projects resumed-session))
                    "mock project-authoring resume should create one governed project")
      (let ((project (first (sbcl-agent::agent-session-projects resumed-session))))
        (assert-equal "Agent Governed Project"
                      (sbcl-agent::project-record-title project)
                      "mock project-authoring resume should persist the created project title")
        (assert-equal "req-agent-governance"
                      (sbcl-agent::project-requirement-id
                       (first (sbcl-agent::project-record-requirements project)))
                      "mock project-authoring resume should persist the seeded governed requirement")))
    (multiple-value-bind (augment-result augment-kind augment-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(say "please augment governed project artifacts"))
         provider
         session)
      (assert-equal :say augment-kind "mock project augmentation should dispatch as :say")
      (assert-equal :awaiting-approval
                    (getf (getf augment-result :turn) :status)
                    "mock project augmentation should also await approval")
      (assert-equal 8 (length (sbcl-agent::agent-session-pending-actions augment-session))
                    "mock project augmentation should stage the full governed augmentation action set"))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :project-governance-write))
     provider
     session)
    (multiple-value-bind (augment-resume-result augment-resume-kind augment-resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (assert-equal :turn-resume augment-resume-kind
                    "mock project augmentation resume should dispatch as :turn-resume")
      (assert-equal 8 (getf augment-resume-result :resumed-operation-count)
                    "mock project augmentation resume should execute all staged governed actions")
      (let ((project (first (sbcl-agent::agent-session-projects augment-resumed-session))))
        (assert-true (search "evidence-first"
                             (princ-to-string (sbcl-agent::project-record-style-guide project))
                             :test #'char-equal)
                     "mock project augmentation resume should persist the revised style guide")))
    (multiple-value-bind (revise-result revise-kind revise-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(say "please revise governed project foundations"))
         provider
         session)
      (assert-equal :say revise-kind "mock project foundation revision should dispatch as :say")
      (assert-equal :awaiting-approval
                    (getf (getf revise-result :turn) :status)
                    "mock project foundation revision should await approval")
      (assert-equal 2 (length (sbcl-agent::agent-session-pending-actions revise-session))
                    "mock project foundation revision should stage two governed actions"))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :project-governance-write))
     provider
     session)
    (multiple-value-bind (revise-resume-result revise-resume-kind revise-resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (assert-equal :turn-resume revise-resume-kind
                    "mock project foundation revision resume should dispatch as :turn-resume")
      (assert-equal 2 (getf revise-resume-result :resumed-operation-count)
                    "mock project foundation revision resume should execute both staged actions")
      (let* ((project (first (sbcl-agent::agent-session-projects revise-resumed-session)))
             (requirements (sbcl-agent::project-record-requirements project)))
        (assert-true (search "conversation revision discipline"
                             (princ-to-string (sbcl-agent::project-record-constitution project))
                             :test #'char-equal)
                     "mock project foundation revision resume should replace the constitution")
        (assert-true (find "req-governed-closure"
                           requirements
                           :key #'sbcl-agent::project-requirement-id
                           :test #'string=)
                     "mock project foundation revision resume should append the revised governed requirement")))
    (multiple-value-bind (architecture-result architecture-kind architecture-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(say "please revise governed architecture posture"))
         provider
         session)
      (assert-equal :say architecture-kind "mock project architecture revision should dispatch as :say")
      (assert-equal :awaiting-approval
                    (getf (getf architecture-result :turn) :status)
                    "mock project architecture revision should await approval")
      (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions architecture-session))
                    "mock project architecture revision should stage one governed action"))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :project-governance-write))
     provider
     session)
    (multiple-value-bind (architecture-resume-result architecture-resume-kind architecture-resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (assert-equal :turn-resume architecture-resume-kind
                    "mock project architecture revision resume should dispatch as :turn-resume")
      (assert-equal 1 (getf architecture-resume-result :resumed-operation-count)
                    "mock project architecture revision resume should execute the staged action")
      (let* ((project (first (sbcl-agent::agent-session-projects architecture-resumed-session)))
             (architecture-decisions (sbcl-agent::project-record-architecture-decisions project)))
        (assert-true (find "adr-governed-closure"
                           architecture-decisions
                           :key #'sbcl-agent::project-architecture-decision-id
                           :test #'string=)
                     "mock project architecture revision resume should append the revised architecture decision")))
    (multiple-value-bind (testing-result testing-kind testing-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(say "please revise governed testing posture"))
         provider
         session)
      (assert-equal :say testing-kind "mock project testing posture revision should dispatch as :say")
      (assert-equal :awaiting-approval
                    (getf (getf testing-result :turn) :status)
                    "mock project testing posture revision should await approval")
      (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions testing-session))
                    "mock project testing posture revision should stage one governed action"))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :project-governance-write))
     provider
     session)
    (multiple-value-bind (testing-resume-result testing-resume-kind testing-resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (assert-equal :turn-resume testing-resume-kind
                    "mock project testing posture revision resume should dispatch as :turn-resume")
      (assert-equal 1 (getf testing-resume-result :resumed-operation-count)
                    "mock project testing posture revision resume should execute the staged action")
      (let* ((project (first (sbcl-agent::agent-session-projects testing-resumed-session)))
             (testing-strategy (getf (sbcl-agent::project-record-metadata project) :testing-strategy))
             (threshold-policy (and (listp testing-strategy)
                                    (getf testing-strategy :threshold-policy))))
        (assert-equal '("coverage" "performance" "governed-approval")
                      (getf testing-strategy :required-evidence)
                      "mock project testing posture revision resume should replace required evidence")
        (assert-equal 2
                      (length (getf testing-strategy :suite-expectations))
                      "mock project testing posture revision resume should persist suite expectations")
        (assert-equal 1
                      (getf threshold-policy :max-failed-tests)
                      "mock project testing posture revision resume should persist threshold policy")))
    (multiple-value-bind (release-result release-kind release-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(say "please revise governed release readiness"))
         provider
         session)
      (assert-equal :say release-kind "mock release readiness revision should dispatch as :say")
      (assert-equal :awaiting-approval
                    (getf (getf release-result :turn) :status)
                    "mock release readiness revision should await approval")
      (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions release-session))
                    "mock release readiness revision should stage one governed action"))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :project-governance-write))
     provider
     session)
    (multiple-value-bind (release-resume-result release-resume-kind release-resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (assert-equal :turn-resume release-resume-kind
                    "mock release readiness revision resume should dispatch as :turn-resume")
      (assert-equal 1 (getf release-resume-result :resumed-operation-count)
                    "mock release readiness revision resume should execute the staged action")
      (let* ((project (first (sbcl-agent::agent-session-projects release-resumed-session)))
             (release-readiness (getf (sbcl-agent::project-record-metadata project) :release-readiness)))
        (assert-equal "candidate"
                      (getf release-readiness :stage)
                      "mock release readiness revision resume should persist the readiness stage")
        (assert-equal "pending"
                      (getf release-readiness :signoff-status)
                      "mock release readiness revision resume should persist signoff status")
        (assert-equal '("platform" "ops")
                      (getf release-readiness :required-approvers)
                      "mock release readiness revision resume should persist required approvers")))
    (multiple-value-bind (obligation-result obligation-kind obligation-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(say "please revise governed readiness obligations"))
         provider
         session)
      (assert-equal :say obligation-kind "mock readiness obligations revision should dispatch as :say")
      (assert-equal :awaiting-approval
                    (getf (getf obligation-result :turn) :status)
                    "mock readiness obligations revision should await approval")
      (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions obligation-session))
                    "mock readiness obligations revision should stage one governed action"))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :project-governance-write))
     provider
     session)
    (multiple-value-bind (obligation-resume-result obligation-resume-kind obligation-resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (assert-equal :turn-resume obligation-resume-kind
                    "mock readiness obligations revision resume should dispatch as :turn-resume")
      (assert-equal 1 (getf obligation-resume-result :resumed-operation-count)
                    "mock readiness obligations revision resume should execute the staged action")
      (let* ((project (first (sbcl-agent::agent-session-projects obligation-resumed-session)))
             (readiness-obligations (getf (sbcl-agent::project-record-metadata project) :readiness-obligations)))
        (assert-equal 2
                      (length readiness-obligations)
                      "mock readiness obligations revision resume should persist readiness obligations")
        (assert-equal "Complete operator release signoff"
                      (getf (first readiness-obligations) :title)
                      "mock readiness obligations revision resume should persist obligation titles")))))

(defun openai-provider-selection-test ()
  (let ((config (sbcl-agent::make-config :provider "openai-compatible"
                                          :model "gpt-5"
                                          :api-base "https://api.openai.com/v1"
                                          :api-key "test-key"
                                          :api-key-present-p t
                                          :working-directory "/tmp/")))
    (assert-equal "openai-compatible"
                  (sbcl-agent::provider-name (sbcl-agent::make-provider config))
                  "make-provider should construct the openai-compatible provider")))

(defun multi-vendor-provider-selection-test ()
  (let ((anthropic (sbcl-agent::make-provider
                    (sbcl-agent::make-config :provider "anthropic"
                                             :model "claude-sonnet-4-20250514"
                                             :api-base "https://api.anthropic.com"
                                             :api-key "anthropic-key"
                                             :api-key-present-p t
                                             :working-directory "/tmp/"))))
    (assert-equal "anthropic"
                  (sbcl-agent::provider-name anthropic)
                  "make-provider should construct the anthropic provider"))
  (let ((gemini (sbcl-agent::make-provider
                 (sbcl-agent::make-config :provider "gemini"
                                          :model "gemini-2.5-pro"
                                          :api-base "https://generativelanguage.googleapis.com/v1beta/openai"
                                          :api-key "gemini-key"
                                          :api-key-present-p t
                                          :working-directory "/tmp/"))))
    (assert-equal "gemini"
                  (sbcl-agent::provider-name gemini)
                  "make-provider should construct the Gemini-compatible provider"))
  (let ((lm-studio (sbcl-agent::make-provider
                    (sbcl-agent::make-config :provider "lm-studio"
                                             :model "local-model"
                                             :api-base "http://localhost:1234/v1"
                                             :api-key "lm-studio"
                                             :api-key-present-p t
                                             :working-directory "/tmp/"))))
    (assert-equal "lm-studio"
                  (sbcl-agent::provider-name lm-studio)
                  "make-provider should construct the LM Studio-compatible provider")))

(defun config-key-file-fallback-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-config-XXXXXX"))
         (ignore (ensure-directories-exist root))
         (key-path (merge-pathnames #P"openai-api-key.key" root)))
    (declare (ignore ignore))
    (with-open-file (stream key-path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-line "file-key" stream))
    (let ((config (sbcl-agent::load-config :working-directory (namestring root))))
      (assert-equal "file-key"
                    (sbcl-agent::config-api-key config)
                    "load-config should fall back to openai-api-key.key when OPENAI_API_KEY is unset")
      (assert-true (sbcl-agent::config-api-key-present-p config)
                   "load-config should mark the API key as present when read from key file"))))

(defun config-auto-provider-selection-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-provider-XXXXXX"))
         (ignore (ensure-directories-exist root))
         (key-path (merge-pathnames #P"openai-api-key.key" root)))
    (declare (ignore ignore))
    (with-open-file (stream key-path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-line "file-key" stream))
    (let ((config (sbcl-agent::load-config :working-directory (namestring root))))
      (assert-equal "openai-compatible"
                    (sbcl-agent::config-provider config)
                    "load-config should auto-select the openai-compatible provider when an API key is present")
      (assert-true (typep (sbcl-agent::make-provider config) 'sbcl-agent::openai-compatible-provider)
                   "make-provider should construct the OpenAI-compatible provider after auto-selection"))))

(defun config-legacy-key-filename-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-legacy-provider-XXXXXX"))
         (ignore (ensure-directories-exist root))
         (key-path (merge-pathnames #P"openai-api-kay.key" root)))
    (declare (ignore ignore))
    (with-open-file (stream key-path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-line "legacy-file-key" stream))
    (let ((config (sbcl-agent::load-config :working-directory (namestring root))))
      (assert-equal "legacy-file-key"
                    (sbcl-agent::config-api-key config)
                    "load-config should honor the legacy misspelled key filename when present")
      (assert-equal "openai-compatible"
                    (sbcl-agent::config-provider config)
                    "legacy key filename should still activate the OpenAI-compatible provider"))))

(defun config-anthropic-key-file-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-anthropic-provider-XXXXXX"))
         (ignore (ensure-directories-exist root))
         (key-path (merge-pathnames #P"anthropic-api-key.key" root)))
    (declare (ignore ignore))
    (with-open-file (stream key-path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-line "anthropic-file-key" stream))
    (let ((config (sbcl-agent::load-config :working-directory (namestring root))))
      (assert-equal "anthropic-file-key"
                    (sbcl-agent::config-api-key config)
                    "load-config should honor anthropic-api-key.key when present")
      (assert-equal "anthropic"
                    (sbcl-agent::config-provider config)
                    "anthropic key filename should activate the anthropic provider")
      (assert-equal "https://api.anthropic.com"
                    (sbcl-agent::config-api-base config)
                    "anthropic key filename should apply the Anthropic default API base")
      (assert-true (typep (sbcl-agent::make-provider config) 'sbcl-agent::anthropic-provider)
                   "make-provider should construct the Anthropic provider from anthropic-api-key.key"))))

(defun config-with-overrides-test ()
  (let* ((base (sbcl-agent::make-config :provider "mock"
                                        :model "gpt-5"
                                        :fast-model "gpt-4.1-mini"
                                        :api-base nil
                                        :api-key nil
                                        :api-key-present-p nil
                                        :retrieval-ranking-mode :auto
                                        :working-directory "/tmp/base/"))
         (updated (sbcl-agent::config-with-overrides base
                                                     :provider "openai-compatible"
                                                     :model "gpt-5.1"
                                                     :api-base "https://example.test/v1"
                                                     :retrieval-ranking-mode :off
                                                     :working-directory "/tmp/override")))
    (assert-equal "openai-compatible"
                  (sbcl-agent::config-provider updated)
                  "config-with-overrides should replace the provider when requested")
    (assert-equal "gpt-5.1"
                  (sbcl-agent::config-model updated)
                  "config-with-overrides should replace the model when requested")
    (assert-equal "gpt-4.1-mini"
                  (sbcl-agent::config-fast-model updated)
                  "config-with-overrides should preserve the fast model")
    (assert-equal "https://example.test/v1"
                  (sbcl-agent::config-api-base updated)
                  "config-with-overrides should replace the api base when requested")
    (assert-equal :off
                  (sbcl-agent::config-retrieval-ranking-mode updated)
                  "config-with-overrides should replace retrieval ranking mode when requested")
    (assert-true (search "/tmp/override/" (sbcl-agent::config-working-directory updated))
                 "config-with-overrides should normalize the working directory")))

(defun config-helper-coverage-test ()
  (assert-equal nil
                (sbcl-agent::normalize-config-string (format nil "   ~C~C  " #\Newline #\Tab))
                "normalize-config-string should collapse blank strings to nil")
  (let* ((root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-config-extra-~D-~D/"
                        (get-universal-time)
                        (random 1000000))))
         (ignore (ensure-directories-exist root)))
    (declare (ignore ignore))
    (assert-equal nil
                  (sbcl-agent::load-api-key-from-file (namestring root))
                  "load-api-key-from-file should return nil when no key file exists"))
  (let* ((base (sbcl-agent::make-config :provider "mock"
                                        :model "gpt-5"
                                        :fast-model "gpt-4.1-mini"
                                        :api-base nil
                                        :api-key nil
                                        :api-key-present-p nil
                                        :retrieval-ranking-mode :auto
                                        :working-directory nil))
         (updated (sbcl-agent::config-with-overrides base)))
    (assert-true (stringp (sbcl-agent::config-working-directory updated))
                 "config-with-overrides should fall back to the current directory when no working directory exists")
    (assert-equal "mock"
                  (sbcl-agent::config-provider updated)
                  "config-with-overrides should preserve the existing provider by default"))
  (assert-equal :auto
                (sbcl-agent::parse-retrieval-ranking-mode "bogus")
                "invalid retrieval ranking config values should fall back to :auto")
  (assert-equal :off
                (sbcl-agent::parse-retrieval-ranking-mode "off")
                "parse-retrieval-ranking-mode should accept off")
  (assert-equal :on
                (sbcl-agent::parse-retrieval-ranking-mode "enabled")
                "parse-retrieval-ranking-mode should accept enabled"))

(defun provider-defaults-coverage-test ()
  (assert-equal "https://generativelanguage.googleapis.com/v1beta/openai"
                (sbcl-agent::provider-default-api-base "gemini")
                "provider-default-api-base should know the Gemini OpenAI-compatible endpoint")
  (assert-equal "http://localhost:1234/v1"
                (sbcl-agent::provider-default-api-base "lm-studio")
                "provider-default-api-base should know the LM Studio endpoint")
  (assert-equal "https://api.anthropic.com"
                (sbcl-agent::provider-default-api-base "anthropic")
                "provider-default-api-base should know the Anthropic endpoint")
  (assert-true (equal '("anthropic-api-key.key")
                      (sbcl-agent::provider-key-file-names "anthropic"))
               "provider-key-file-names should return the Anthropic key file name")
  (assert-true (equal '("gemini-api-key.key" "google-api-key.key")
                      (sbcl-agent::provider-key-file-names "gemini"))
               "provider-key-file-names should return the Gemini key file names"))

(defun test-program-reporting-coverage-test ()
  (let* ((results (list (list :name "alpha-test"
                              :category :core-cli
                              :status :passed
                              :duration-seconds 0.01)
                        (list :name "beta-test"
                              :category :extended-suite
                              :status :failed
                              :duration-seconds 0.02
                              :error "synthetic failure")))
         (report (generate-test-program-report results))
         (json-path (write-test-report-json report))
         (markdown-path (write-test-report-markdown report))
         (json-body (uiop:read-file-string json-path))
         (markdown-body (uiop:read-file-string markdown-path)))
    (assert-true (probe-file json-path)
                 "test program reporting should write a JSON report")
    (assert-true (probe-file markdown-path)
                 "test program reporting should write a markdown report")
    (assert-true (search "\"suite_id\":\"sbcl-agent\"" json-body)
                 "test program reporting JSON should encode suite identity")
    (assert-true (search "\"failed\":1" json-body)
                 "test program reporting JSON should encode failing totals")
    (assert-true (search "# sbcl-agent Test Program Report" markdown-body)
                 "test program reporting markdown should include a title")
    (assert-true (search "`core-cli`: total=1 passed=1 failed=0" markdown-body)
                 "test program reporting markdown should include category summaries")
    (assert-true (search "`beta-test` (`extended-suite`): synthetic failure" markdown-body)
                 "test program reporting markdown should include failure summaries")))

(defun test-program-category-runner-coverage-test ()
  (assert-equal :retrieval-and-memory
                (extended-suite-test-category "retrieval-dossier-service-contract-test")
                "extended suite classifier should prioritize retrieval families before broad service-contract matching")
  (assert-equal :service-contracts
                (extended-suite-test-category "platform-service-contract-test")
                "extended suite classifier should identify service-contract families")
  (assert-equal :workflow-and-governance
                (extended-suite-test-category "work-item-checkpoint-test")
                "extended suite classifier should identify workflow/governance families")
  (let* ((results (run-test-program-category :categories '("interaction-boundary")))
         (summary (summarize-test-results results))
         (report (generate-test-program-report results))
         (markdown-path (write-test-report-markdown report))
         (markdown-body (uiop:read-file-string markdown-path)))
    (assert-true results
                 "focused category runner should execute at least one filtered test")
    (assert-equal 0 (or (getf summary :failed) 0)
                  "focused category runner should preserve passing status for the filtered slice")
    (assert-true (search "`interaction-boundary`:" markdown-body)
                 "focused category report should include the requested category")
    (assert-true (null (search "`core-cli`:" markdown-body))
                  "focused category report should omit unrelated categories")))

(defun test-program-harness-inventory-coverage-test ()
  (let* ((harnesses (available-test-harnesses))
         (service-contracts (find :service-contracts harnesses
                                  :key (lambda (entry) (getf entry :id))
                                  :test #'eq))
         (evidence-index (generate-test-evidence-index))
         (markdown-path (write-test-evidence-index-markdown evidence-index))
         (markdown-body (uiop:read-file-string markdown-path)))
    (assert-true service-contracts
                 "test harness inventory should expose a named service-contracts runner")
    (assert-true (equal '(:service-contracts)
                        (getf service-contracts :categories))
                 "focused service-contract harness should declare its category slice")
    (assert-true (search "`service-contracts`: Service Contracts via `./bin/run-test-service-contracts`"
                         markdown-body)
                 "test evidence index should list the named service-contract runner")
    (assert-true (search "`full-suite`: Full Lisp Suite via `./bin/run-tests`"
                         markdown-body)
                 "test evidence index should preserve the full-suite harness")
    (assert-true (search "## Artifacts" markdown-body)
                 "test evidence index should include an artifact section")))

(defun openai-request-model-selection-test ()
  (let* ((provider (make-instance 'sbcl-agent::openai-compatible-provider
                                  :model "gpt-5"
                                  :fast-model "gpt-4.1-mini"
                                  :api-base "https://api.openai.com/v1"
                                  :api-key "test-key"))
         (simple-request (sbcl-agent::make-provider-request :prompt "create a program which will tell me the current date and time of day" :session-summary '(:recent-transcript ())))
         (deep-request (sbcl-agent::make-provider-request :prompt "provide a deep architecture analysis" :session-summary '(:recent-transcript ()))))
    (assert-equal "gpt-4.1-mini"
                  (sbcl-agent::openai-request-model provider simple-request)
                  "ordinary asks should route through the fast model")
    (assert-equal "gpt-5"
                  (sbcl-agent::openai-request-model provider deep-request)
                  "deep asks should stay on the configured primary model")))

(defun invalid-eval-action-dropped-test ()
  (let* ((response (sbcl-agent::decode-assistant-response-object
                    '(("message" . "hi")
                      ("actions" . ((("type" . "eval")
                                         ("payload" . (("note" . "missing code"))))))
                      ("metadata" . ()))))
         (actions (sbcl-agent::assistant-response-actions response)))
    (assert-equal 0
                  (length actions)
                  "malformed eval actions should be dropped during decode")))

(defun chat-argument-parsing-test ()
  (let ((options (sbcl-agent::parse-chat-arguments '("-i"
                                                     "--provider" "openai-compatible"
                                                     "--model" "gpt-5.1"
                                                     "--api-base" "https://example.test/v1"
                                                     "--cwd" "/tmp/chat-root"))))
    (assert-true (sbcl-agent::chat-options-default-stream-p options)
                 "parse-chat-arguments should enable interactive streaming for -i")
    (assert-equal "openai-compatible"
                  (sbcl-agent::chat-options-provider options)
                  "parse-chat-arguments should capture provider overrides")
    (assert-equal "gpt-5.1"
                  (sbcl-agent::chat-options-model options)
                  "parse-chat-arguments should capture model overrides")
    (assert-equal "https://example.test/v1"
                  (sbcl-agent::chat-options-api-base options)
                  "parse-chat-arguments should capture api base overrides")
    (assert-equal "/tmp/chat-root"
                  (sbcl-agent::chat-options-working-directory options)
                  "parse-chat-arguments should capture working directory overrides")))

(defun command-normalization-test ()
  (let ((ask-command (sbcl-agent::normalize-form-command '(ask "inspect src/main.lisp")))
        (say-command (sbcl-agent::normalize-form-command '(say "inspect src/main.lisp")))
        (provider-show-command (sbcl-agent::normalize-form-command '(provider/show)))
        (provider-list-command (sbcl-agent::normalize-form-command '(provider/list)))
        (provider-use-command (sbcl-agent::normalize-form-command '(provider/use "anthropic-review")))
        (provider-routing-command (sbcl-agent::normalize-form-command '(provider/routing :manual)))
        (provider-route-command (sbcl-agent::normalize-form-command '(provider/route)))
        (provider-configure-command (sbcl-agent::normalize-form-command
                                     '(provider/configure "anthropic-review"
                                       :provider "anthropic"
                                       :model "claude-3-7-sonnet")))
        (execution-show-command (sbcl-agent::normalize-form-command '(execution/show "exec-1")))
        (execution-control-command (sbcl-agent::normalize-form-command '(execution/control "exec-1" :action :quarantine :reason "Review")))
        (compatibility-list-command (sbcl-agent::normalize-form-command '(compatibility/list :kind :host-process)))
        (compatibility-show-command (sbcl-agent::normalize-form-command '(compatibility/show "exec-1")))
        (compatibility-apps-command (sbcl-agent::normalize-form-command '(compatibility/apps)))
        (compatibility-app-show-command (sbcl-agent::normalize-form-command '(compatibility/app-show "linux.vscode")))
        (compatibility-launch-command (sbcl-agent::normalize-form-command '(compatibility/launch "linux.echo" :arguments '("hello"))))
        (compatibility-relaunch-command (sbcl-agent::normalize-form-command '(compatibility/relaunch "exec-1")))
        (compatibility-windows-command (sbcl-agent::normalize-form-command '(compatibility/windows :app-id "linux.vscode")))
        (workspace-show-command (sbcl-agent::normalize-form-command '(workspace/show)))
        (desktop-show-command (sbcl-agent::normalize-form-command '(desktop/show)))
        (desktop-panel-command (sbcl-agent::normalize-form-command '(desktop/panel :governance)))
        (desktop-select-command (sbcl-agent::normalize-form-command '(desktop/select :panel :workspace :index 0)))
        (desktop-restore-command (sbcl-agent::normalize-form-command '(desktop/restore :panel-id :workspace)))
        (desktop-action-command (sbcl-agent::normalize-form-command '(desktop/action :action-kind :activate-panel :panel-id :governance)))
        (surface-list-command (sbcl-agent::normalize-form-command '(surface/list)))
        (surface-select-command (sbcl-agent::normalize-form-command '(surface/select :index 0)))
        (surface-step-command (sbcl-agent::normalize-form-command '(surface/step :next)))
        (display-list-command (sbcl-agent::normalize-form-command '(display/list)))
        (display-show-command (sbcl-agent::normalize-form-command '(display/show "exec-1")))
        (display-select-command (sbcl-agent::normalize-form-command '(display/select :index 0)))
        (display-step-command (sbcl-agent::normalize-form-command '(display/step :next)))
        (display-control-command (sbcl-agent::normalize-form-command '(display/control :action :relaunch :execution-id "exec-1")))
        (display-control-app-command (sbcl-agent::normalize-form-command '(display/control :action :relaunch :app-id "linux.echo")))
        (desktop-select-display-app-command (sbcl-agent::normalize-form-command '(desktop/select :panel :display :app-id "linux.echo")))
        (open-command (sbcl-agent::normalize-form-command '(open :surface-index 0)))
        (open-display-command (sbcl-agent::normalize-form-command '(open :display-index 0)))
        (open-display-app-command (sbcl-agent::normalize-form-command '(open :display-app-id "linux.echo")))
        (focus-show-command (sbcl-agent::normalize-form-command '(focus/show)))
        (focus-set-command (sbcl-agent::normalize-form-command '(focus/set "exec-1")))
        (governance-queue-command (sbcl-agent::normalize-form-command '(governance/queue)))
        (governance-select-command (sbcl-agent::normalize-form-command '(governance/select :index 0)))
        (object-browser-command (sbcl-agent::normalize-form-command '(object-browser :work-item)))
        (object-browser-select-command (sbcl-agent::normalize-form-command '(object-browser/select :kind :work-item :index 0)))
        (inspector-show-command (sbcl-agent::normalize-form-command '(inspector/show "exec-1")))
        (thread-new-command (sbcl-agent::normalize-form-command '(thread/new :title "Conversation")))
        (thread-list-command (sbcl-agent::normalize-form-command '(thread/list)))
        (thread-use-command (sbcl-agent::normalize-form-command '(thread/use "thread-1")))
        (thread-show-command (sbcl-agent::normalize-form-command '(thread/show "thread-1")))
        (turn-status-command (sbcl-agent::normalize-form-command '(turn/status "turn-1")))
        (turn-resume-command (sbcl-agent::normalize-form-command '(turn/resume "turn-1")))
        (incident-list-command (sbcl-agent::normalize-form-command '(incident/list)))
        (incident-show-command (sbcl-agent::normalize-form-command '(incident/show "incident-1")))
        (environment-status-command (sbcl-agent::normalize-form-command '(environment/status)))
        (review-mutation-command (sbcl-agent::normalize-form-command '(review/mutation "turn-1")))
        (runtime-current-package-command (sbcl-agent::normalize-form-command '(runtime/current-package)))
        (runtime-list-loaded-systems-command (sbcl-agent::normalize-form-command '(runtime/list-loaded-systems)))
        (runtime-describe-symbol-command (sbcl-agent::normalize-form-command '(runtime/describe-symbol "CAR" :package "COMMON-LISP")))
        (runtime-find-definition-command (sbcl-agent::normalize-form-command '(runtime/find-definition "CAR" :package "COMMON-LISP")))
        (runtime-callers-command (sbcl-agent::normalize-form-command '(runtime/callers "CAR" :package "COMMON-LISP")))
        (runtime-methods-command (sbcl-agent::normalize-form-command '(runtime/methods "PRINT-OBJECT")))
        (runtime-source-image-divergence-command (sbcl-agent::normalize-form-command '(runtime/source-image-divergence "CAR" :package "COMMON-LISP")))
        (runtime-set-package-command (sbcl-agent::normalize-form-command '(runtime/set-package "COMMON-LISP")))
        (runtime-eval-command (sbcl-agent::normalize-form-command '(runtime/eval "(+ 1 2)")))
        (runtime-history-command (sbcl-agent::normalize-form-command '(runtime/history :tail 5)))
        (runtime-reload-file-command (sbcl-agent::normalize-form-command '(runtime/reload-file "src/main.lisp")))
        (environment-show-command (sbcl-agent::normalize-form-command '(environment/show)))
        (environment-events-command (sbcl-agent::normalize-form-command '(environment/events :tail 5)))
        (environment-save-command (sbcl-agent::normalize-form-command '(environment/save "/tmp/environment.sexp")))
        (environment-load-command (sbcl-agent::normalize-form-command '(environment/load "/tmp/environment.sexp")))
        (execute-actions-command (sbcl-agent::normalize-form-command '(execute-actions)))
        (describe-session-command (sbcl-agent::normalize-form-command '(describe-session)))
        (enqueue-task-command (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp"))))
        (run-next-task-command (sbcl-agent::normalize-form-command '(run-next-task)))
        (list-replay-groups-command (sbcl-agent::normalize-form-command '(list-replay-groups)))
        (list-image-reconciliations-command (sbcl-agent::normalize-form-command '(list-image-reconciliations)))
        (replay-validator-command (sbcl-agent::normalize-form-command '(replay-validator-task "work" "validator" :status :passed)))
        (replay-validator-set-command (sbcl-agent::normalize-form-command '(replay-validator-set "work" "replay" :status :partial :statuses '(:live :partial :cold :passed))))
        (reconcile-image-only-command (sbcl-agent::normalize-form-command '(reconcile-image-only-source "work" "summary")))
        (integration-rgp-bind-command (sbcl-agent::normalize-form-command '(integration/rgp-bind :request-id "req" :agent-session-id "agent-session")))
        (integration-rgp-show-command (sbcl-agent::normalize-form-command '(integration/rgp-show)))
        (integration-rgp-workspace-command (sbcl-agent::normalize-form-command '(integration/rgp-workspace)))
        (integration-rgp-export-command (sbcl-agent::normalize-form-command '(integration/rgp-export "/tmp/rgp-snapshot.json")))
        (integration-rgp-artifacts-command (sbcl-agent::normalize-form-command '(integration/rgp-artifacts)))
        (integration-rgp-approvals-command (sbcl-agent::normalize-form-command '(integration/rgp-approvals)))
        (integration-rgp-approve-command (sbcl-agent::normalize-form-command '(integration/rgp-approve "work" :process-run :reason "Need approval")))
        (integration-rgp-resume-command (sbcl-agent::normalize-form-command '(integration/rgp-resume "work" :note "Continue")))
        (eval-command (sbcl-agent::normalize-form-command '(+ 100 203)))
        (approve-command (sbcl-agent::normalize-form-command '(approve :process-run)))
        (patch-command (sbcl-agent::normalize-form-command '(patch '((:write "x" "y"))))))
    (assert-equal :ask (sbcl-agent::command-kind ask-command)
                  "ask form should normalize to :ask")
    (assert-equal :say (sbcl-agent::command-kind say-command)
                  "say form should normalize to :say")
    (assert-equal :provider-show (sbcl-agent::command-kind provider-show-command)
                  "provider/show form should normalize to :provider-show")
    (assert-equal :provider-list (sbcl-agent::command-kind provider-list-command)
                  "provider/list form should normalize to :provider-list")
    (assert-equal :provider-use (sbcl-agent::command-kind provider-use-command)
                  "provider/use form should normalize to :provider-use")
    (assert-equal :provider-routing (sbcl-agent::command-kind provider-routing-command)
                  "provider/routing form should normalize to :provider-routing")
    (assert-equal :provider-route (sbcl-agent::command-kind provider-route-command)
                  "provider/route form should normalize to :provider-route")
    (assert-equal :provider-configure (sbcl-agent::command-kind provider-configure-command)
                  "provider/configure form should normalize to :provider-configure")
    (assert-equal :execution-show (sbcl-agent::command-kind execution-show-command)
                  "execution/show form should normalize to :execution-show")
    (assert-equal :execution-control (sbcl-agent::command-kind execution-control-command)
                  "execution/control form should normalize to :execution-control")
    (assert-equal :compatibility-list (sbcl-agent::command-kind compatibility-list-command)
                  "compatibility/list form should normalize to :compatibility-list")
    (assert-equal :compatibility-show (sbcl-agent::command-kind compatibility-show-command)
                  "compatibility/show form should normalize to :compatibility-show")
    (assert-equal :compatibility-apps (sbcl-agent::command-kind compatibility-apps-command)
                  "compatibility/apps form should normalize to :compatibility-apps")
    (assert-equal :compatibility-app-show (sbcl-agent::command-kind compatibility-app-show-command)
                  "compatibility/app-show form should normalize to :compatibility-app-show")
    (assert-equal :compatibility-launch (sbcl-agent::command-kind compatibility-launch-command)
                  "compatibility/launch form should normalize to :compatibility-launch")
    (assert-equal :compatibility-relaunch (sbcl-agent::command-kind compatibility-relaunch-command)
                  "compatibility/relaunch form should normalize to :compatibility-relaunch")
    (assert-equal :compatibility-windows (sbcl-agent::command-kind compatibility-windows-command)
                  "compatibility/windows form should normalize to :compatibility-windows")
    (assert-equal :workspace-show (sbcl-agent::command-kind workspace-show-command)
                  "workspace/show form should normalize to :workspace-show")
    (assert-equal :desktop-show (sbcl-agent::command-kind desktop-show-command)
                  "desktop/show form should normalize to :desktop-show")
    (assert-equal :desktop-panel (sbcl-agent::command-kind desktop-panel-command)
                  "desktop/panel form should normalize to :desktop-panel")
    (assert-equal :desktop-select (sbcl-agent::command-kind desktop-select-command)
                  "desktop/select form should normalize to :desktop-select")
    (assert-equal :desktop-restore (sbcl-agent::command-kind desktop-restore-command)
                  "desktop/restore form should normalize to :desktop-restore")
    (assert-equal :desktop-action (sbcl-agent::command-kind desktop-action-command)
                  "desktop/action form should normalize to :desktop-action")
    (assert-equal :surface-list (sbcl-agent::command-kind surface-list-command)
                  "surface/list form should normalize to :surface-list")
    (assert-equal :surface-select (sbcl-agent::command-kind surface-select-command)
                  "surface/select form should normalize to :surface-select")
    (assert-equal :surface-step (sbcl-agent::command-kind surface-step-command)
                  "surface/step form should normalize to :surface-step")
    (assert-equal :display-list (sbcl-agent::command-kind display-list-command)
                  "display/list form should normalize to :display-list")
    (assert-equal :display-show (sbcl-agent::command-kind display-show-command)
                  "display/show form should normalize to :display-show")
    (assert-equal :display-select (sbcl-agent::command-kind display-select-command)
                  "display/select form should normalize to :display-select")
    (assert-equal :display-step (sbcl-agent::command-kind display-step-command)
                  "display/step form should normalize to :display-step")
    (assert-equal :display-control (sbcl-agent::command-kind display-control-command)
                  "display/control form should normalize to :display-control")
    (assert-equal :display-control (sbcl-agent::command-kind display-control-app-command)
                  "display/control with :app-id should normalize to :display-control")
    (assert-equal :desktop-select (sbcl-agent::command-kind desktop-select-display-app-command)
                  "desktop/select with :app-id should normalize to :desktop-select")
    (assert-equal :open (sbcl-agent::command-kind open-command)
                  "open form should normalize to :open")
    (assert-equal :open (sbcl-agent::command-kind open-display-command)
                  "open with :display-index should normalize to :open")
    (assert-equal :open (sbcl-agent::command-kind open-display-app-command)
                  "open with :display-app-id should normalize to :open")
    (assert-equal :focus-show (sbcl-agent::command-kind focus-show-command)
                  "focus/show form should normalize to :focus-show")
    (assert-equal :focus-set (sbcl-agent::command-kind focus-set-command)
                  "focus/set form should normalize to :focus-set")
    (assert-equal :governance-queue (sbcl-agent::command-kind governance-queue-command)
                  "governance/queue form should normalize to :governance-queue")
    (assert-equal :governance-select (sbcl-agent::command-kind governance-select-command)
                  "governance/select form should normalize to :governance-select")
    (assert-equal :object-browser (sbcl-agent::command-kind object-browser-command)
                  "object-browser form should normalize to :object-browser")
    (assert-equal :object-browser-select (sbcl-agent::command-kind object-browser-select-command)
                  "object-browser/select form should normalize to :object-browser-select")
    (assert-equal :inspector-show (sbcl-agent::command-kind inspector-show-command)
                  "inspector/show form should normalize to :inspector-show")
    (assert-equal :thread-new (sbcl-agent::command-kind thread-new-command)
                  "thread/new form should normalize to :thread-new")
    (assert-equal :thread-list (sbcl-agent::command-kind thread-list-command)
                  "thread/list form should normalize to :thread-list")
    (assert-equal :thread-use (sbcl-agent::command-kind thread-use-command)
                  "thread/use form should normalize to :thread-use")
    (assert-equal :thread-show (sbcl-agent::command-kind thread-show-command)
                  "thread/show form should normalize to :thread-show")
    (assert-equal :turn-status (sbcl-agent::command-kind turn-status-command)
                  "turn/status form should normalize to :turn-status")
    (assert-equal :turn-resume (sbcl-agent::command-kind turn-resume-command)
                  "turn/resume form should normalize to :turn-resume")
    (assert-equal :incident-list (sbcl-agent::command-kind incident-list-command)
                  "incident/list form should normalize to :incident-list")
    (assert-equal :incident-show (sbcl-agent::command-kind incident-show-command)
                  "incident/show form should normalize to :incident-show")
    (assert-equal :environment-status (sbcl-agent::command-kind environment-status-command)
                  "environment/status form should normalize to :environment-status")
    (assert-equal :review-mutation (sbcl-agent::command-kind review-mutation-command)
                  "review/mutation form should normalize to :review-mutation")
    (assert-equal :runtime-current-package (sbcl-agent::command-kind runtime-current-package-command)
                  "runtime/current-package form should normalize to :runtime-current-package")
    (assert-equal :runtime-list-loaded-systems (sbcl-agent::command-kind runtime-list-loaded-systems-command)
                  "runtime/list-loaded-systems form should normalize to :runtime-list-loaded-systems")
    (assert-equal :runtime-describe-symbol (sbcl-agent::command-kind runtime-describe-symbol-command)
                  "runtime/describe-symbol form should normalize to :runtime-describe-symbol")
    (assert-equal :runtime-find-definition (sbcl-agent::command-kind runtime-find-definition-command)
                  "runtime/find-definition form should normalize to :runtime-find-definition")
    (assert-equal :runtime-callers (sbcl-agent::command-kind runtime-callers-command)
                  "runtime/callers form should normalize to :runtime-callers")
    (assert-equal :runtime-methods (sbcl-agent::command-kind runtime-methods-command)
                  "runtime/methods form should normalize to :runtime-methods")
    (assert-equal :runtime-source-image-divergence (sbcl-agent::command-kind runtime-source-image-divergence-command)
                  "runtime/source-image-divergence form should normalize to :runtime-source-image-divergence")
    (assert-equal :runtime-set-package (sbcl-agent::command-kind runtime-set-package-command)
                  "runtime/set-package form should normalize to :runtime-set-package")
    (assert-equal :runtime-eval (sbcl-agent::command-kind runtime-eval-command)
                  "runtime/eval form should normalize to :runtime-eval")
    (assert-equal :runtime-history (sbcl-agent::command-kind runtime-history-command)
                  "runtime/history form should normalize to :runtime-history")
    (assert-equal :runtime-reload-file (sbcl-agent::command-kind runtime-reload-file-command)
                  "runtime/reload-file form should normalize to :runtime-reload-file")
    (assert-equal :environment-show (sbcl-agent::command-kind environment-show-command)
                  "environment/show form should normalize to :environment-show")
    (assert-equal :environment-events (sbcl-agent::command-kind environment-events-command)
                  "environment/events form should normalize to :environment-events")
    (assert-equal :environment-save (sbcl-agent::command-kind environment-save-command)
                  "environment/save form should normalize to :environment-save")
    (assert-equal :environment-load (sbcl-agent::command-kind environment-load-command)
                  "environment/load form should normalize to :environment-load")
    (assert-equal :execute-actions (sbcl-agent::command-kind execute-actions-command)
                  "execute-actions form should normalize to :execute-actions")
    (assert-equal :describe-session (sbcl-agent::command-kind describe-session-command)
                  "describe-session form should normalize to :describe-session")
    (assert-equal :enqueue-task (sbcl-agent::command-kind enqueue-task-command)
                  "enqueue-task form should normalize to :enqueue-task")
    (assert-equal :run-next-task (sbcl-agent::command-kind run-next-task-command)
                  "run-next-task form should normalize to :run-next-task")
    (assert-equal :list-replay-groups (sbcl-agent::command-kind list-replay-groups-command)
                  "list-replay-groups form should normalize to :list-replay-groups")
    (assert-equal :list-image-reconciliations (sbcl-agent::command-kind list-image-reconciliations-command)
                  "list-image-reconciliations form should normalize to :list-image-reconciliations")
    (assert-equal :replay-validator-task (sbcl-agent::command-kind replay-validator-command)
                  "replay-validator-task form should normalize to :replay-validator-task")
    (assert-equal :replay-validator-set (sbcl-agent::command-kind replay-validator-set-command)
                  "replay-validator-set form should normalize to :replay-validator-set")
    (assert-equal :reconcile-image-only-source (sbcl-agent::command-kind reconcile-image-only-command)
                  "reconcile-image-only-source form should normalize to :reconcile-image-only-source")
    (assert-equal :integration-rgp-bind (sbcl-agent::command-kind integration-rgp-bind-command)
                  "integration/rgp-bind form should normalize to :integration-rgp-bind")
    (assert-equal :integration-rgp-show (sbcl-agent::command-kind integration-rgp-show-command)
                  "integration/rgp-show form should normalize to :integration-rgp-show")
    (assert-equal :integration-rgp-workspace (sbcl-agent::command-kind integration-rgp-workspace-command)
                  "integration/rgp-workspace form should normalize to :integration-rgp-workspace")
    (assert-equal :integration-rgp-export (sbcl-agent::command-kind integration-rgp-export-command)
                  "integration/rgp-export form should normalize to :integration-rgp-export")
    (assert-equal :integration-rgp-artifacts (sbcl-agent::command-kind integration-rgp-artifacts-command)
                  "integration/rgp-artifacts form should normalize to :integration-rgp-artifacts")
    (assert-equal :integration-rgp-approvals (sbcl-agent::command-kind integration-rgp-approvals-command)
                  "integration/rgp-approvals form should normalize to :integration-rgp-approvals")
    (assert-equal :integration-rgp-approve (sbcl-agent::command-kind integration-rgp-approve-command)
                  "integration/rgp-approve form should normalize to :integration-rgp-approve")
    (assert-equal :integration-rgp-resume (sbcl-agent::command-kind integration-rgp-resume-command)
                  "integration/rgp-resume form should normalize to :integration-rgp-resume")
    (assert-equal :eval (sbcl-agent::command-kind eval-command)
                  "plain Lisp forms should normalize to :eval")
    (assert-equal :approve (sbcl-agent::command-kind approve-command)
                  "approve form should normalize to :approve")
    (assert-equal :patch (sbcl-agent::command-kind patch-command)
                  "patch form should normalize to :patch")))

(defun provider-profile-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/provider-profiles/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-profiles/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::ensure-environment-provider-profile
     :environment environment
     :config (sbcl-agent::make-config :provider "mock"
                                      :model "gpt-5"
                                      :working-directory "/tmp/provider-profiles/")
     :profile-name "default")
    (multiple-value-bind (configure-result configure-kind configure-session configure-provider)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command
          '(provider/configure "anthropic-review"
            :provider "anthropic"
            :model "claude-3-7-sonnet"
            :fast-model "claude-3-5-haiku"
            :api-base "https://api.anthropic.com"
            :intents '(:architecture-review :deep-reasoning)
            :latency-tier :balanced
            :review-bias :deep
            :execution-bias :balanced
            :locality :network))
         provider
         session)
      (assert-equal :provider-configure configure-kind
                    "provider/configure should dispatch correctly")
      (assert-true (eq configure-session session)
                   "provider/configure should preserve the session")
      (assert-equal "mock" (sbcl-agent::provider-name configure-provider)
                    "provider/configure should not switch the runtime provider")
      (assert-equal 2 (getf configure-result :profile-count)
                    "provider/configure should add a provider profile"))
    (multiple-value-bind (use-result use-kind use-session switched-provider)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(provider/use "anthropic-review"))
         provider
         session)
      (assert-equal :provider-use use-kind
                    "provider/use should dispatch correctly")
      (assert-true (eq use-session session)
                   "provider/use should preserve the session")
      (assert-equal "anthropic" (sbcl-agent::provider-name switched-provider)
                    "provider/use should switch the runtime provider")
      (assert-equal "anthropic-review" (getf use-result :active-profile-name)
                    "provider/use should activate the requested profile")
      (assert-equal "claude-3-7-sonnet" (getf (getf use-result :active-profile) :model)
                    "provider/use should expose the active model")
      (assert-true (member :architecture-review
                           (getf (getf use-result :active-profile) :intents))
                   "provider/use should expose provider profile intent metadata"))
    (multiple-value-bind (list-result list-kind listed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(provider/list))
         provider
         session)
      (declare (ignore listed-session))
      (assert-equal :provider-list list-kind
                    "provider/list should dispatch correctly")
      (assert-equal 2 (getf list-result :profile-count)
                    "provider/list should report all configured profiles"))
    (multiple-value-bind (routing-result routing-kind routing-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(provider/routing :manual))
         provider
         session)
      (declare (ignore routing-session))
      (assert-equal :provider-routing routing-kind
                    "provider/routing should dispatch correctly")
      (assert-equal :manual (getf routing-result :routing-mode)
                    "provider/routing should update the environment routing mode"))
    (let* ((route (sbcl-agent::select-environment-provider-profile
                   "Need a deep architecture review"
                   :environment environment))
           (route-summary (sbcl-agent::record-environment-provider-route route environment)))
      (declare (ignore route-summary)))
    (multiple-value-bind (route-result route-kind route-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(provider/route))
         provider
         session)
      (declare (ignore route-session))
      (assert-equal :provider-route route-kind
                    "provider/route should dispatch correctly")
      (assert-equal :manual (getf route-result :routing-mode)
                    "provider/route should report the current routing mode")
      (assert-equal "anthropic-review"
                    (getf (getf route-result :last-route) :selected-profile-name)
                    "provider/route should expose the last routing decision"))
    (assert-equal "anthropic-review"
                  (getf (getf (sbcl-agent::environment-status environment) :provider-profile)
                        :active-profile-name)
                  "environment/status should surface the active provider profile")))

(defun provider-auto-routing-selection-test ()
  (let* ((environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-routing/"))
         (base (sbcl-agent::make-config :provider "mock"
                                        :model "gpt-5"
                                        :working-directory "/tmp/provider-routing/")))
    (sbcl-agent::ensure-environment-provider-profile
     :environment environment
     :config base
     :profile-name "default")
    (sbcl-agent::command-environment-provider-configure-service
     "anthropic-review"
     '(:provider "anthropic"
       :model "claude-3-7-sonnet"
       :fast-model "claude-3-5-haiku"
       :api-base "https://api.anthropic.com"
       :intents (:architecture-review :deep-reasoning)
       :review-bias :deep
       :latency-tier :balanced
       :locality :network)
     environment)
    (sbcl-agent::command-environment-provider-configure-service
     "local-fast"
     '(:provider "lm-studio"
       :model "qwen-coder"
       :fast-model "qwen-coder-mini"
       :api-base "http://localhost:1234/v1"
       :intents (:quick-turn :local-development :code-execution)
       :latency-tier :fast
       :execution-bias :high
       :locality :local)
     environment)
    (let ((deep-route (sbcl-agent::select-environment-provider-profile
                       "Need a deep architecture review of this subsystem"
                       :environment environment))
          (quick-route (sbcl-agent::select-environment-provider-profile
                        "Give me a quick brief answer"
                        :environment environment))
          (local-route (sbcl-agent::select-environment-provider-profile
                        "Use the local lm studio model for this"
                        :environment environment))
          (explicit-route (sbcl-agent::select-environment-provider-profile
                           "Need a detailed review"
                           :environment environment
                           :options '(:provider-profile "default"))))
      (assert-equal :deep-request (getf deep-route :reason)
                    "provider routing should classify deep review prompts")
      (assert-equal "anthropic-review"
                    (getf (getf deep-route :selected-profile) :name)
                    "provider routing should prefer the Anthropic profile for deep review prompts")
      (assert-true (consp (getf deep-route :candidate-rankings))
                   "provider routing should expose candidate rankings")
      (assert-equal :quick-request (getf quick-route :reason)
                    "provider routing should classify quick prompts")
      (assert-equal "local-fast"
                    (getf (getf quick-route :selected-profile) :name)
                    "provider routing should prefer the local profile for quick prompts")
      (assert-true (>= (getf (first (getf quick-route :candidate-rankings)) :score) 1)
                   "provider routing candidate rankings should include scores")
      (assert-equal :local-request (getf local-route :reason)
                    "provider routing should classify local prompts")
      (assert-equal "local-fast"
                    (getf (getf local-route :selected-profile) :name)
                    "provider routing should prefer the local profile for explicit local prompts")
      (let ((execution-route (sbcl-agent::select-environment-provider-profile
                              "Implement this patch and fix the code"
                              :environment environment)))
        (assert-equal :code-execution-request (getf execution-route :reason)
                      "provider routing should classify code execution prompts")
        (assert-equal "local-fast"
                      (getf (getf execution-route :selected-profile) :name)
                      "provider routing should prefer execution-biased profiles for code execution prompts"))
      (assert-equal :requested-profile (getf explicit-route :reason)
                    "provider routing should honor explicit provider profile overrides")
      (assert-equal "default"
                    (getf (getf explicit-route :selected-profile) :name)
                    "provider routing should keep the explicitly requested profile"))))

(defun provider-governance-routing-selection-test ()
  (let* ((environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-governance-routing/"))
         (base (sbcl-agent::make-config :provider "mock"
                                        :model "gpt-5"
                                        :working-directory "/tmp/provider-governance-routing/")))
    (sbcl-agent::ensure-environment-provider-profile
     :environment environment
     :config base
     :profile-name "default")
    (sbcl-agent::command-environment-provider-configure-service
     "deep-review"
     '(:provider "anthropic"
       :model "claude-3-7-sonnet"
       :intents (:incident-review :validation-review :governance-review)
       :review-bias :deep
       :latency-tier :balanced
       :locality :network)
     environment)
    (sbcl-agent::command-environment-provider-configure-service
     "local-exec"
     '(:provider "lm-studio"
       :model "qwen-coder"
       :intents (:code-execution :local-development)
       :execution-bias :high
       :latency-tier :fast
       :locality :local)
     environment)
    (setf (sbcl-agent::environment-summaries environment)
          '(:operator-status (:blocked-count 1
                              :quarantined-count 0
                              :incident-count 1
                              :open-incident-count 1
                              :blocked-work-items ((:why :pending-validation))
                              :quarantined-work-items ())
            :incident-summary (:count 1 :open-count 1 :recent ((:id "incident-1")))))
    (let ((incident-route (sbcl-agent::select-environment-provider-profile
                           "Implement the fix now"
                           :environment environment)))
      (assert-equal :validation-governance-request (getf incident-route :reason)
                    "governance-heavy environments should bias code execution prompts toward review profiles")
      (assert-equal "deep-review"
                    (getf (getf incident-route :selected-profile) :name)
                    "governance-heavy environments should prefer governance-review profiles over execution-fast profiles")
      (assert-equal "deep-review"
                    (getf (first (getf incident-route :candidate-rankings)) :profile-name)
                    "governance routing should rank the governance-review profile first"))))

(defun rgp-integration-snapshot-test ()
  (let* ((provider (make-test-provider))
         (snapshot-path "/tmp/sbcl-agent-rgp-snapshot.json")
         (session (sbcl-agent::make-default-session :cwd "/tmp/sbcl-agent-rgp/"))
         (thread (sbcl-agent::current-thread session))
         (turn (let ((user-message (sbcl-agent::create-message session thread :user "Summarize the integration"))
                     (assistant-message nil)
                     (turn nil))
                 (setf turn (sbcl-agent::start-turn session thread user-message :metadata '(:source :test)))
                 (setf assistant-message (sbcl-agent::create-message session thread :assistant "Integration state captured."
                                                                    :turn-id (sbcl-agent::turn-id turn)))
                 (sbcl-agent::complete-turn session thread turn assistant-message)
                 turn))
         (work-item (sbcl-agent::create-work-item session "Governed runtime checkpoint" :transaction-scope :test)))
    (declare (ignore turn))
    (sbcl-agent::bind-session-to-environment session)
    (sbcl-agent::create-environment-artifact session
                                             :report
                                             "/tmp/sbcl-agent-rgp/report.json"
                                             :title "Runtime report"
                                             :summary "Projected runtime state"
                                             :metadata '(:lineage-source :rgp-test))
    (sbcl-agent::request-work-item-approval session work-item :process-run :reason "Need external approval")
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command
      '(integration/rgp-bind :tenant-id "tenant-1"
                             :request-id "req-1"
                             :agent-session-id "agent-session-1"
                             :integration-id "integration-1"
                             :projection-id "projection-1"))
     provider
     session)
    (let* ((binding (sbcl-agent::rgp-binding-summary))
           (snapshot (sbcl-agent::environment-rgp-snapshot))
           (approvals (sbcl-agent::environment-rgp-approval-summaries))
           (artifacts (sbcl-agent::environment-rgp-artifact-summaries))
           (export-result (sbcl-agent::export-environment-rgp-snapshot snapshot-path))
           (json (uiop:read-file-string snapshot-path)))
      (assert-equal "req-1" (getf binding :request-id)
                    "rgp binding should persist the request id on the environment")
      (assert-equal "agent-session-1" (getf binding :agent-session-id)
                    "rgp binding should persist the governed agent-session id")
      (assert-equal "sbcl_agent" (getf (getf snapshot :governed-runtime) :runtime-subtype)
                    "governed runtime snapshot should identify the sbcl-agent runtime subtype")
      (assert-equal 1 (length approvals)
                    "approval summaries should include the blocked governed runtime work-item")
      (assert-true (getf (first artifacts) :lineage)
                   "artifact summaries should expose lineage fields")
      (assert-equal snapshot-path (getf export-result :path)
                    "RGP export should report the JSON snapshot path")
      (assert-true (search "\"request_id\":\"req-1\"" json)
                   "RGP export should serialize binding identifiers to JSON")
      (assert-true (search "\"runtime_subtype\":\"sbcl_agent\"" json)
                   "RGP export should serialize the governed runtime subtype"))))

(defun rgp-integration-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/sbcl-agent-rgp-shell/"))
         (work-item (sbcl-agent::create-work-item session "Governed shell approval" :transaction-scope :test)))
    (sbcl-agent::bind-session-to-environment session)
    (multiple-value-bind (bind-result bind-kind bound-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command
          '(integration/rgp-bind :request-id "req-shell" :agent-session-id "agent-shell"))
         provider
         session)
      (declare (ignore bound-session))
      (assert-equal :integration-rgp-bind bind-kind
                    "integration/rgp-bind should dispatch correctly")
      (assert-equal "req-shell" (getf (getf bind-result :binding) :request-id)
                    "integration/rgp-bind should return the binding summary"))
    (multiple-value-bind (approval-result approval-kind approval-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command
          `(integration/rgp-approve ,(sbcl-agent::work-item-id work-item) :process-run :reason "Approve runtime checkpoint"))
         provider
         session)
      (declare (ignore approval-session))
      (assert-equal :integration-rgp-approve approval-kind
                    "integration/rgp-approve should dispatch correctly")
      (assert-equal :approval-required
                    (getf (getf approval-result :approval) :why)
                    "integration/rgp-approve should expose approval wait state"))
    (multiple-value-bind (approval-list approval-list-kind approval-list-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(integration/rgp-approvals))
         provider
         session)
      (declare (ignore approval-list-session))
      (assert-equal :integration-rgp-approvals approval-list-kind
                    "integration/rgp-approvals should dispatch correctly")
      (assert-equal 1 (length approval-list)
                    "integration/rgp-approvals should list blocked governed runtime work-items")
      (assert-equal "governed-work"
                    (getf (getf (first approval-list) :execution-surface) :surface-kind)
                    "integration/rgp-approvals should expose execution surfaces for approvals"))
    (multiple-value-bind (resume-result resume-kind resume-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command
          `(integration/rgp-resume ,(sbcl-agent::work-item-id work-item) :note "Resume runtime"))
         provider
         session)
      (declare (ignore resume-session))
      (assert-equal :integration-rgp-resume resume-kind
                    "integration/rgp-resume should dispatch correctly")
      (assert-equal :pending-validation
                    (getf (getf resume-result :approval) :why)
                    "integration/rgp-resume should move the work-item past approval into validation"))))

(defun shell-eval-test ()
  (assert-equal 303
                (sbcl-agent::eval-user-form '(+ 100 203))
                "direct user forms should evaluate in the Lisp shell"))

(defun ask-dispatch-test ()
  (let ((provider (make-test-provider))
        (session (sbcl-agent::make-default-session))
        (command (sbcl-agent::normalize-form-command '(ask "ping"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (let ((response (getf result :response)))
        (assert-equal :ask kind "ask command should dispatch as :ask")
        (assert-true (typep response 'sbcl-agent::assistant-response)
                     "ask command should return an assistant response")
        (assert-true (search "Mock response: ping" (sbcl-agent::assistant-response-message response))
                     "ask command should be handled by the provider")
        (assert-equal 0 (getf result :staged-action-count)
                      "ask without actions should stage zero actions")
        (assert-equal 0 (getf result :immediate-action-count)
                      "ask without eval actions should auto-execute nothing")
        (assert-true (stringp (getf (getf result :thread) :id))
                     "ask should now return the active thread summary through the shared turn runtime")
        (assert-true (stringp (getf (getf result :turn) :id))
                     "ask should now return a persisted turn summary")
        (assert-equal :completed (getf (getf result :turn) :status)
                      "ask should finalize the turn as completed")
        (assert-equal 2 (length (sbcl-agent::agent-session-messages updated-session))
                      "ask should persist user and assistant messages through the shared turn runtime")
        (assert-equal 1 (length (sbcl-agent::agent-session-turns updated-session))
                      "ask should persist one completed turn")
        (assert-equal 1 (length (sbcl-agent::agent-session-operations updated-session))
                      "ask should persist one provider operation when no assistant actions exist")
        (assert-true (>= (length (sbcl-agent::agent-session-events updated-session)) 10)
                     "ask should record turn and operation lifecycle events through the shared runtime")))))

(defun say-dispatch-test ()
  (let ((provider (make-test-provider))
        (session (sbcl-agent::make-default-session))
        (command (sbcl-agent::normalize-form-command '(say "ping"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (let ((response (getf result :response)))
        (assert-equal :say kind "say command should dispatch as :say")
        (assert-true (typep response 'sbcl-agent::assistant-response)
                     "say command should return an assistant response")
        (assert-true (search "Mock response: ping" (sbcl-agent::assistant-response-message response))
                     "say command should be handled by the provider")
        (assert-equal 0 (getf result :staged-action-count)
                      "say without actions should stage zero actions")
        (assert-equal 0 (getf result :immediate-action-count)
                      "say without eval actions should auto-execute nothing")
        (assert-true (stringp (getf (getf result :thread) :id))
                     "say should return the active thread summary")
        (assert-true (stringp (getf (getf result :turn) :id))
                     "say should return a persisted turn summary")
        (assert-equal :completed (getf (getf result :turn) :status)
                      "say should finalize the turn as completed")
        (assert-equal 2 (length (sbcl-agent::agent-session-messages updated-session))
                      "say should persist user and assistant messages")
        (assert-equal 1 (length (sbcl-agent::agent-session-turns updated-session))
                      "say should persist one completed turn")
        (assert-equal 1 (length (sbcl-agent::agent-session-operations updated-session))
                      "say should persist one provider operation when no assistant actions exist")
	        (assert-equal :safe-read
	                      (getf (getf (sbcl-agent::operation-record-summary
	                                   (first (sbcl-agent::agent-session-operations updated-session)))
	                                  :policy-decision)
	                            :policy-id)
	                      "say provider operation should record a safe-read policy decision")
	        (assert-equal 16 (length (sbcl-agent::agent-session-events updated-session))
	                      "say should record turn, retrieval, cognition, reasoning, planning, durable-memory, and operation lifecycle events")
            (assert-true (find :retrieval-dossier
                               (sbcl-agent::agent-session-events updated-session)
                               :key #'sbcl-agent::event-kind)
                         "say should record the pre-prompt retrieval dossier event")
            (assert-true (find :cognition-bundle
                               (sbcl-agent::agent-session-events updated-session)
                               :key #'sbcl-agent::event-kind)
                         "say should record the pre-prompt cognition bundle event")
            (assert-true (find :reasoning-brief
                               (sbcl-agent::agent-session-events updated-session)
                               :key #'sbcl-agent::event-kind)
                         "say should record the pre-prompt reasoning brief event")
            (assert-true (find :planning-brief
                               (sbcl-agent::agent-session-events updated-session)
                               :key #'sbcl-agent::event-kind)
                         "say should record the pre-prompt planning brief event")
            (assert-true (find :memory-entry-recorded
                               (sbcl-agent::agent-session-events updated-session)
                               :key #'sbcl-agent::event-kind)
                         "say should record the durable memory entry event")))))

(defun say-mixed-action-operations-test ()
  (let ((provider (make-instance 'mixed-action-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
        (command (sbcl-agent::normalize-form-command '(say "execute and inspect"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (declare (ignore result))
      (assert-equal :say kind "mixed-action say should dispatch as :say")
      (assert-equal 3 (length (sbcl-agent::agent-session-operations updated-session))
                    "mixed-action say should persist provider, immediate, and staged action operations")
      (let* ((operations (sbcl-agent::agent-session-operations updated-session))
             (eval-op (find "assistant-eval" operations :key #'sbcl-agent::operation-name :test #'string=))
             (tool-op (find "assistant-tool" operations :key #'sbcl-agent::operation-name :test #'string=)))
        (assert-true eval-op "mixed-action say should record an eval action operation")
        (assert-true tool-op "mixed-action say should record a tool action operation")
        (assert-equal :completed (sbcl-agent::operation-status eval-op)
                      "immediate eval action operation should complete")
        (assert-equal :staged (sbcl-agent::operation-status tool-op)
                      "tool action operation should be marked staged")
        (assert-equal :allowed
                      (getf (sbcl-agent::operation-policy-decision eval-op) :decision)
                      "immediate eval action should be marked allowed")
        (assert-equal :runtime-eval-safe
                      (getf (sbcl-agent::operation-policy-decision eval-op) :policy-id)
                      "immediate eval action should record runtime-eval-safe policy")
        (assert-equal :staged
                      (getf (sbcl-agent::operation-policy-decision tool-op) :decision)
                      "staged tool action should record staged decision")
        (assert-equal :safe-read
                      (getf (sbcl-agent::operation-policy-decision tool-op) :policy-id)
                      "staged fs/read action should record its tool policy")))))

(defun say-patch-action-approval-test ()
  (let ((provider (make-instance 'patch-action-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
        (command (sbcl-agent::normalize-form-command '(say "prepare patch"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (assert-equal :say kind "patch-action say should dispatch as :say")
      (assert-equal :awaiting-approval
                    (getf (getf result :turn) :status)
                    "patch-action say should leave the turn awaiting approval")
      (assert-equal 2 (length (sbcl-agent::agent-session-operations updated-session))
                    "patch-action say should persist provider and patch action operations")
      (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions updated-session))
                    "patch-action say should leave the patch action staged for later")
      (assert-equal 1 (length (sbcl-agent::agent-session-work-items updated-session))
                    "patch-action say should create a work-item for the mutating turn")
      (let ((work-item (first (sbcl-agent::agent-session-work-items updated-session))))
        (assert-equal 1 (length (sbcl-agent::work-item-checkpoints work-item))
                      "patch-action say should checkpoint the bound work-item")
        (assert-equal :approval
                      (sbcl-agent::workflow-record-waiting-on
                       (sbcl-agent::work-item-workflow-record updated-session work-item))
                      "patch-action say should mark the bound workflow record as awaiting approval"))
      (let ((patch-op (find "assistant-patch"
                            (sbcl-agent::agent-session-operations updated-session)
                            :key #'sbcl-agent::operation-name
                            :test #'string=)))
        (assert-true patch-op "patch-action say should record a patch action operation")
        (assert-equal :awaiting-approval (sbcl-agent::operation-status patch-op)
                      "patch action operation should wait for approval")
        (assert-true (stringp (getf (sbcl-agent::operation-metadata patch-op) :work-item-id))
                     "patch action operation should retain its bound work-item id")
        (assert-equal :approval-required
                      (getf (sbcl-agent::operation-policy-decision patch-op) :decision)
                      "patch action should record approval-required policy decision")
        (assert-equal :workspace-write
                      (getf (sbcl-agent::operation-policy-decision patch-op) :policy-id)
                      "patch action should record workspace-write policy")))))

(defun say-patch-action-deferred-by-incident-test ()
  (let ((provider (make-instance 'patch-action-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
        (command (sbcl-agent::normalize-form-command '(say "prepare patch while incidents remain open"))))
    (sbcl-agent::create-incident session
                                 :test
                                 "Open incident"
                                 "An active incident should make governed mutation proposals conservative.")
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (assert-equal :say kind "deferred patch say should dispatch as :say")
      (assert-equal :completed
                    (getf (getf result :turn) :status)
                    "deferred governed mutations should not leave the turn awaiting approval")
      (assert-equal 1 (getf result :deferred-action-count)
                    "active incidents should defer governed patch proposals")
      (assert-equal 0 (getf result :staged-action-count)
                    "deferred governed patch proposals should not be staged")
      (assert-equal 0 (length (sbcl-agent::agent-session-pending-actions updated-session))
                    "deferred governed patch proposals should not enter pending actions")
      (assert-equal 0 (length (sbcl-agent::agent-session-work-items updated-session))
                    "deferred governed patch proposals should not create governed work-items")
      (let ((patch-op (find "assistant-patch"
                            (sbcl-agent::agent-session-operations updated-session)
                            :key #'sbcl-agent::operation-name
                            :test #'string=))
            (deferred-event (find :governed-mutations-deferred
                                  (sbcl-agent::agent-session-events updated-session)
                                  :key #'sbcl-agent::event-kind)))
        (assert-true patch-op "deferred patch flow should still record an assistant patch operation")
        (assert-equal :blocked
                      (sbcl-agent::operation-status patch-op)
                      "deferred patch action should be recorded as blocked")
        (assert-equal :deferred
                      (getf (sbcl-agent::operation-policy-decision patch-op) :decision)
                      "deferred patch action should record deferred policy disposition")
        (assert-true deferred-event
                     "deferred governed patch proposals should emit a deferral event")))))

(defun say-weakly-grounded-patch-deferred-test ()
  (let ((provider (make-instance 'weak-grounding-patch-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
        (command (sbcl-agent::normalize-form-command '(say "What happened earlier with that prior incident?"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (assert-equal :say kind "weak-grounding patch say should dispatch as :say")
      (assert-equal :completed
                    (getf (getf result :turn) :status)
                    "weakly grounded mutation proposals should not leave the turn awaiting approval")
      (assert-equal 1 (getf result :deferred-action-count)
                    "weakly grounded governed mutations should be deferred")
      (assert-equal 0 (getf result :staged-action-count)
                    "weakly grounded governed mutations should not be staged")
      (assert-equal 0 (length (sbcl-agent::agent-session-pending-actions updated-session))
                    "weakly grounded governed mutations should not enter pending actions")
      (let ((patch-op (find "assistant-patch"
                            (sbcl-agent::agent-session-operations updated-session)
                            :key #'sbcl-agent::operation-name
                            :test #'string=))
            (weak-grounding-event (find :weakly-grounded-mutations-deferred
                                        (sbcl-agent::agent-session-events updated-session)
                                        :key #'sbcl-agent::event-kind))
            (turn-status (sbcl-agent::turn-detail updated-session))
            (mutation-review (sbcl-agent::mutation-review updated-session))
            (turn-status-patch-op nil))
        (setf turn-status-patch-op (find "assistant-patch"
                                         (getf turn-status :operations)
                                         :key (lambda (operation) (getf operation :name))
                                         :test #'string=))
        (assert-true patch-op "weakly grounded patch flow should still record an assistant patch operation")
        (assert-equal :blocked
                      (sbcl-agent::operation-status patch-op)
                      "weakly grounded patch action should be recorded as blocked")
        (assert-equal :deferred
                      (getf (sbcl-agent::operation-policy-decision patch-op) :decision)
                      "weakly grounded patch action should record deferred policy disposition")
        (assert-true (getf (getf (sbcl-agent::operation-metadata patch-op) :action-assessment) :weakly-grounded-p)
                     "weakly grounded patch action should preserve its assessment metadata")
        (assert-true turn-status-patch-op
                     "turn/status should expose the assistant patch operation")
        (assert-true (getf (getf turn-status-patch-op :action-assessment)
                           :weakly-grounded-p)
                     "turn/status should project compact action assessment details")
        (assert-equal 1
                      (getf (getf turn-status :detail-summary) :weakly-grounded-operation-count)
                      "turn/status should summarize weakly grounded operation counts")
        (assert-equal 1
                      (getf (getf turn-status :detail-summary)
                            :deferred-weakly-grounded-operation-count)
                      "turn/status should summarize deferred weakly grounded operation counts")
        (assert-equal 1
                      (getf (getf (getf mutation-review :governance) :action-assessment-summary)
                            :weakly-grounded-operation-count)
                      "mutation review should expose weakly grounded action counts")
        (assert-equal 1
                      (getf (getf (getf mutation-review :governance) :action-assessment-summary)
                            :deferred-weakly-grounded-operation-count)
                      "mutation review should expose deferred weakly grounded action counts")
        (assert-true weak-grounding-event
                     "weakly grounded mutation proposals should emit a dedicated deferral event")))))

(defun strategy-governed-mutation-deferred-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (response (sbcl-agent::make-assistant-response
                    :message "Propose a patch."
                    :actions (list (sbcl-agent::make-assistant-action
                                    :type :patch
                                    :payload '((:write "tmp/strategy-deferred.txt" "hello"))))))
         (retrieval-dossier '(:intent (:category :code-change
                                       :domains (:workspace :workflow)
                                       :mutation-likely-p t)
                             :ranking (:top-candidates ((:label :workspace)))))
         (reasoning-brief '(:reasoning-mode :environment-grounded
                            :facts ()
                            :uncertainties ((:kind :missing-context :statement "Need stronger evidence."))
                            :blockers ()
                            :validation-obligations ()
                            :evidence-actions ((:kind :collect-missing-context))))
         (cognition-bundle (sbcl-agent::make-cognition-bundle
                            :retrieval-dossier retrieval-dossier
                            :prior-outcome-brief '(:mode :historical-analogy
                                                  :similar-successes ()
                                                  :similar-failures ()
                                                  :avoidance-guidance ()
                                                  :reuse-recommendation :no-strong-prior-analogy)
                            :reasoning-brief reasoning-brief
                            :planning-brief '(:planning-mode :environment-grounded
                                              :ordered-steps ((:phase :collect-evidence)
                                                              (:phase :plan)
                                                              (:phase :mutate)))
                            :execution-strategy '(:mode :inspection-first
                                                  :next-step :collect-evidence)
                            :validation-strategy '(:mode :opportunistic
                                                   :next-step :no-additional-validation-required)
                            :action-agenda '(:step-count 2
                                             :primary-step (:kind :collect-evidence
                                                            :priority :high
                                                            :statement "Collect additional evidence first.")
                                             :steps ((:kind :collect-evidence
                                                      :priority :high
                                                      :statement "Collect additional evidence first.")
                                                     (:kind :plan-mutation
                                                      :priority :medium
                                                      :statement "Then plan the mutation.")))
                            :outcome-brief '(:outcome-mode :expectation-vs-observation
                                             :recommended-next-step :collect-evidence)))
         (action-report (sbcl-agent::process-response-actions response
                                                              session
                                                              :reasoning-brief reasoning-brief
                                                              :retrieval-dossier retrieval-dossier
                                                              :cognition-bundle cognition-bundle))
         (strategy-event (find :strategy-governed-mutations-deferred
                               (sbcl-agent::agent-session-events session)
                               :key #'sbcl-agent::event-kind)))
    (assert-equal 0
                  (length (getf action-report :staged-actions))
                  "execution strategy should prevent staging governed mutations while evidence collection is still required")
    (assert-equal 1
                  (length (getf action-report :deferred-actions))
                  "execution strategy should defer governed mutations until evidence collection is complete")
    (assert-true strategy-event
                 "strategy-based deferral should emit a dedicated event")
    (assert-equal :collect-evidence
                  (getf (getf (sbcl-agent::event-payload strategy-event) :execution-strategy) :next-step)
                  "strategy deferral event should preserve the governing execution next step")
    (assert-equal :collect-evidence
                  (getf (getf (getf (sbcl-agent::event-payload strategy-event) :action-agenda)
                              :primary-step)
                        :kind)
                  "strategy deferral event should preserve the governing action agenda")))

(defun say-mutating-eval-approval-test ()
  (let ((provider (make-instance 'mutating-eval-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
        (command (sbcl-agent::normalize-form-command '(say "mutate runtime state"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (assert-equal :say kind "mutating eval say should dispatch as :say")
      (assert-equal :awaiting-approval
                    (getf (getf result :turn) :status)
                    "mutating eval say should await approval")
      (assert-equal 1 (length (sbcl-agent::agent-session-work-items updated-session))
                    "mutating eval say should create a governed work-item")
      (let ((eval-op (find "assistant-eval"
                           (sbcl-agent::agent-session-operations updated-session)
                           :key #'sbcl-agent::operation-name
                           :test #'string=)))
        (assert-true eval-op "mutating eval say should record an eval action operation")
        (assert-equal :awaiting-approval (sbcl-agent::operation-status eval-op)
                      "mutating eval should wait for approval")
        (assert-equal :runtime-eval-mutate
                      (getf (sbcl-agent::operation-policy-decision eval-op) :policy-id)
                      "mutating eval should record runtime-eval-mutate policy")))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (let ((work-item (first (sbcl-agent::agent-session-work-items session))))
      (assert-equal :awaiting-cold-validation
                    (sbcl-agent::work-item-status work-item)
                    "mutating eval resume should stop at awaiting cold validation")
      (assert-equal :passed
                    (sbcl-agent::validation-result-status
                     (sbcl-agent::work-item-live-validation-result work-item))
                    "mutating eval resume should record live validation evidence")
      (assert-true (member :cold (sbcl-agent::work-item-pending-validations work-item))
                   "mutating eval resume should leave cold validation pending"))))

(defun say-git-write-tool-approval-test ()
  (let* ((repo (make-test-git-repo))
         (provider (make-instance 'git-write-action-provider))
         (session (sbcl-agent::make-default-session :cwd (namestring repo)))
         (command (sbcl-agent::normalize-form-command '(say "stage repository change"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (assert-equal :say kind "git-write tool say should dispatch as :say")
      (assert-equal :awaiting-approval
                    (getf (getf result :turn) :status)
                    "git-write tool say should await approval")
      (assert-equal 1 (length (sbcl-agent::agent-session-work-items updated-session))
                    "git-write tool say should create a governed work-item")
      (let ((tool-op (find "assistant-tool"
                           (sbcl-agent::agent-session-operations updated-session)
                           :key #'sbcl-agent::operation-name
                           :test #'string=)))
        (assert-true tool-op "git-write tool say should record a tool action operation")
        (assert-equal :awaiting-approval (sbcl-agent::operation-status tool-op)
                      "git-write tool should wait for approval")
        (assert-equal :git-write
                      (getf (sbcl-agent::operation-policy-decision tool-op) :policy-id)
                      "git-write tool should record git-write policy")))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :git-write))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (let ((work-item (first (sbcl-agent::agent-session-work-items session))))
      (assert-equal :committed
                    (sbcl-agent::work-item-status work-item)
                    "git-write tool resume should commit the governed work-item")
      (assert-equal :committed
                    (sbcl-agent::workflow-record-status
                     (sbcl-agent::work-item-workflow-record session work-item))
                    "git-write tool resume should close the governed workflow record"))))

(defun streaming-provider-test ()
  (let* ((provider (make-test-provider))
         (events '())
         (response (sbcl-agent::stream-prompt provider
                                               "please read src/main.lisp"
                                               (lambda (event)
                                                 (setf events (append events (list event)))))))
    (assert-true (> (length events) 3)
                 "streaming provider should emit multiple events")
    (assert-equal :MESSAGE-START
                  (sbcl-agent::provider-event-type (first events))
                  "stream should begin with a message-start event")
    (assert-equal :RUN-STARTED
                  (sbcl-agent::provider-event-effective-type (first events))
                  "stream should normalize the first event to a run-started canonical type")
    (assert-true (search "Mock response: please read src/main.lisp"
                         (sbcl-agent::assistant-response-message response))
                 "streaming response should preserve the mock prefix")
    (let ((assembled (sbcl-agent::stream-response->assistant-response events)))
      (assert-equal (sbcl-agent::assistant-response-message response)
                    (sbcl-agent::assistant-response-message assembled)
                    "streamed fragments should assemble into the final response")
      (assert-equal 1
                    (length (sbcl-agent::assistant-response-actions assembled))
                    "stream assembly should preserve proposed actions"))))

(defun provider-event-normalization-test ()
  (let ((event (sbcl-agent::make-provider-event :type :action-proposal
                                                :legacy-type :action-proposal
                                                :canonical-type :tool-intent
                                                :family :provider
                                                :visibility :user
                                                :payload '(:demo t))))
    (assert-equal :TOOL-INTENT
                  (sbcl-agent::provider-event-effective-type event)
                  "provider events should expose the canonical tool-intent type")
    (assert-true (sbcl-agent::provider-action-intent-event-p event)
                 "provider action intent predicate should recognize canonical tool-intent events")))

(defun event-envelope-correlation-fields-test ()
  (let* ((event (sbcl-agent::make-event-now
                 :workflow-record-created
                 '(:ok t)
                 :entity-id "wf-1"
                 :thread-id "thread-1"
                 :turn-id "turn-1"
                 :environment-id "env-1"
                 :session-id "session-1"
                 :work-item-id "work-1"
                 :artifact-id "artifact-1"
                 :incident-id "incident-1"))
         (summary (sbcl-agent::event-envelope-summary event)))
    (assert-equal :workflow
                  (sbcl-agent::event-family event)
                  "event family normalization should classify workflow-record-created as workflow")
    (assert-equal "env-1"
                  (getf (sbcl-agent::event-metadata event) :environment-id)
                  "event envelope should preserve environment-id correlation metadata")
    (assert-equal "session-1"
                  (getf (sbcl-agent::event-metadata event) :session-id)
                  "event envelope should preserve session-id correlation metadata")
    (assert-equal "work-1"
                  (getf (sbcl-agent::event-metadata event) :work-item-id)
                  "event envelope should preserve work-item correlation metadata")
    (assert-true (find :environment-id (getf summary :metadata-keys) :test #'eq)
                 "event envelope summary should expose metadata keys for correlation fields")))

(defun event-family-normalization-coverage-test ()
  (let ((incident-event (sbcl-agent::make-event-now :incident-created '(:ok t)))
        (artifact-event (sbcl-agent::make-event-now :artifact-created '(:ok t)))
        (followup-event (sbcl-agent::make-event-now :turn-followup-started '(:ok t))))
    (assert-equal :incident
                  (sbcl-agent::event-family incident-event)
                  "incident-created should normalize to incident family")
    (assert-equal :conversation
                  (sbcl-agent::event-family artifact-event)
                  "artifact-created should normalize to conversation family")
    (assert-equal :conversation
                  (sbcl-agent::event-family followup-event)
                  "turn follow-up events should normalize to conversation family")))

(defun openai-stream-line-parser-test ()
  (let* ((line (concatenate 'string "data: " "{\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"))
         (chunk (sbcl-agent::parse-openai-stream-json-line line)))
    (assert-true (sbcl-agent::openai-stream-data-line-p line)
                 "openai stream parser should recognize data lines")
    (assert-equal "Hello"
                  (sbcl-agent::extract-openai-stream-delta chunk)
                  "openai stream parser should extract delta content from a chunk")
    (assert-true (sbcl-agent::openai-stream-done-p "data: [DONE]")
                 "openai stream parser should recognize the terminal DONE line")))

(defun openai-stream-response-decode-test ()
  (let* ((content "{\"message\":\"hi\",\"actions\":[],\"metadata\":{\"provider\":\"openai-compatible\"}}")
         (response (sbcl-agent::decode-openai-content-response content "gpt-5")))
    (assert-equal "hi"
                  (sbcl-agent::assistant-response-message response)
                  "openai stream decoder should preserve the assistant message")
    (assert-equal "openai-compatible"
                  (getf (sbcl-agent::assistant-response-metadata response) :PROVIDER)
                  "openai stream decoder should preserve provider metadata from the JSON payload")
    (assert-equal "gpt-5"
                  (getf (sbcl-agent::assistant-response-metadata response) :MODEL)
                  "openai stream decoder should tag the model metadata")))

(defun streaming-ask-dispatch-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (command (sbcl-agent::normalize-form-command '(ask "please read src/main.lisp" :stream t))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (declare (ignore kind))
      (assert-true (getf result :streamed-p)
                   "streaming ask should mark the result as streamed")
      (assert-true (> (getf result :stream-event-count) 3)
                   "streaming ask should record multiple stream events")
      (assert-equal 1 (getf result :staged-action-count)
                    "streaming ask should still stage assistant actions")
      (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions updated-session))
                    "streaming ask should retain staged actions in session state")
      (let* ((provider-event (find :provider-stream
                                   (sbcl-agent::agent-session-events updated-session)
                                   :key #'sbcl-agent::event-kind))
             (provider-operation (find :provider-run
                                       (sbcl-agent::agent-session-operations updated-session)
                                       :key #'sbcl-agent::operation-kind)))
        (assert-true provider-event
                     "streaming ask should log provider stream events")
        (assert-true provider-operation
                     "streaming ask should create a provider-run operation")
        (assert-equal (sbcl-agent::operation-id provider-operation)
                      (getf (sbcl-agent::event-metadata provider-event) :operation-id)
                      "streaming ask provider stream events should correlate to the provider-run operation")
        (assert-equal (getf (getf result :thread) :id)
                      (sbcl-agent::event-thread-id provider-event)
                      "streaming ask provider stream events should carry thread identity")
        (assert-equal (getf (getf result :turn) :id)
                      (sbcl-agent::event-turn-id provider-event)
                      "streaming ask provider stream events should carry turn identity")))))

(defun default-streaming-ask-dispatch-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (command (sbcl-agent::normalize-form-command '(ask "please read src/main.lisp"))))
    (let ((sbcl-agent::*default-ask-streaming* t))
      (multiple-value-bind (result kind updated-session)
          (sbcl-agent::execute-command command provider session)
        (declare (ignore kind))
        (assert-true (getf result :streamed-p)
                     "default shell streaming should stream ask requests without an explicit :stream option")
        (assert-true (> (getf result :stream-event-count) 3)
                     "default shell streaming should still record provider stream events")
        (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions updated-session))
                      "default shell streaming should still stage assistant actions")))))

(defun chat-interactive-flag-test ()
  (multiple-value-bind (exit-code stdout stderr)
      (run-command-with-input "./bin/sbcl-agent"
                              '("chat" "-i" "--provider" "mock" "--model" "gpt-5")
                              (concatenate 'string "(ask \"ping\")" (string #\Newline))
                              :directory (uiop:ensure-directory-pathname (current-workspace-root)))
    (declare (ignore stderr))
    (assert-equal 0 exit-code
                  "chat -i should exit cleanly after stdin closes")
    (assert-true (search "Interactive streaming is enabled by default" stdout)
                 "chat -i should announce the default interactive streaming mode")
    (assert-true (search "assistant-stream>" stdout)
                 "chat -i should render streamed assistant output")
    (assert-true (search "Mock response: ping" stdout)
                 "chat -i should stream the assistant response content")))

(defun ask-enqueue-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (command (sbcl-agent::normalize-form-command '(ask "please read src/main.lisp" :enqueue t))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (assert-equal :ask kind "queued ask should still dispatch through the ask command")
      (assert-true (getf result :enqueued-p)
                   "queued ask should report that it was enqueued")
      (assert-equal 1 (length (sbcl-agent::agent-session-tasks updated-session))
                    "queued ask should create one task in the session")
      (assert-equal :ask
                    (sbcl-agent::task-kind (first (sbcl-agent::agent-session-tasks updated-session)))
                    "queued ask should create an ask task"))))

(defun queued-ask-worker-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(ask "please read src/main.lisp" :enqueue t))
     provider
     session)
    (multiple-value-bind (worker-result worker-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(start-worker))
         provider
         session)
      (assert-equal :start-worker worker-kind "start-worker should dispatch correctly for queued ask")
      (wait-for (lambda ()
                  (eq :completed
                      (sbcl-agent::task-status
                       (first (sbcl-agent::agent-session-tasks updated-session)))))
                :timeout-seconds 10.0)
      (let* ((task (first (sbcl-agent::agent-session-tasks updated-session)))
             (result (sbcl-agent::task-result task))
             (response (getf result :response)))
        (assert-true (typep response 'sbcl-agent::assistant-response)
                     "queued ask worker should produce an assistant response")
        (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions updated-session))
                      "queued ask worker should still stage assistant actions")
        (assert-true (> (length (sbcl-agent::task-progress-events task)) 2)
                     "queued ask worker should record task progress events")
        (assert-true (find :provider-stream
                           (sbcl-agent::task-progress-events task)
                           :key #'sbcl-agent::event-kind)
                     "queued ask worker should capture streamed provider progress in the task")
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(stop-worker ,(getf worker-result :id)))
         provider
         updated-session)))))


(defun describe-task-progress-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (enqueue-result enqueue-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(ask "please read src/main.lisp" :enqueue t))
         provider
         session)
      (declare (ignore enqueue-kind))
      (sbcl-agent::execute-command
       (sbcl-agent::normalize-form-command '(run-next-task))
       provider
       updated-session)
      (multiple-value-bind (describe-result describe-kind final-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(describe-task ,(getf (getf enqueue-result :queued-task) :id)))
           provider
           updated-session)
        (declare (ignore final-session))
        (assert-equal :describe-task describe-kind "describe-task should dispatch correctly after queued ask")
        (assert-true (> (getf describe-result :progress-event-count) 2)
                     "describe-task should report recorded task progress events")
        (assert-equal "task"
                      (getf (getf describe-result :execution-surface) :surface-kind)
                      "describe-task should expose a task execution surface")
        (assert-true (typep (getf describe-result :latest-progress-event) 'sbcl-agent::event)
                     "describe-task should expose the latest task progress event")))))


(defun monitor-task-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (enqueue-result enqueue-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(ask "please read src/main.lisp" :enqueue t))
         provider
         session)
      (declare (ignore enqueue-kind))
      (sbcl-agent::execute-command
       (sbcl-agent::normalize-form-command '(run-next-task))
       provider
       updated-session)
      (multiple-value-bind (monitor-result monitor-kind final-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(monitor-task ,(getf (getf enqueue-result :queued-task) :id)))
           provider
           updated-session)
        (declare (ignore final-session))
        (assert-equal :monitor-task monitor-kind "monitor-task should dispatch correctly")
        (assert-true (> (length (getf monitor-result :recent-progress-events)) 0)
                     "monitor-task should report recent task progress events")
        (assert-equal "task"
                      (getf (getf monitor-result :execution-surface) :surface-kind)
                      "monitor-task should expose a task execution surface")
        (assert-equal :completed (getf monitor-result :status)
                      "monitor-task should report the completed task status")))))

(defun task-monitoring-prefers-environment-agent-state-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/task-monitoring-environment/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/task-monitoring-environment/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (multiple-value-bind (enqueue-result enqueue-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(ask "please read src/main.lisp" :enqueue t))
         provider
         session)
      (declare (ignore enqueue-kind))
      (sbcl-agent::execute-command
       (sbcl-agent::normalize-form-command '(run-next-task))
       provider
       updated-session)
      (sbcl-agent::refresh-environment-agent-domain environment updated-session)
      (setf (sbcl-agent::agent-session-tasks updated-session) '()
            (sbcl-agent::agent-session-tasks-tail updated-session) nil)
      (let ((task-id (getf (getf enqueue-result :queued-task) :id)))
        (assert-true (sbcl-agent::find-task updated-session task-id)
                     "find-task should prefer environment-backed agent state when bound")
        (let ((monitor-result (sbcl-agent::execute-monitor-task-command (list task-id) updated-session)))
          (assert-equal :completed (getf monitor-result :status)
                        "monitor-task should read task status from environment-backed agent state")
          (assert-true (> (length (getf monitor-result :recent-progress-events)) 0)
                       "monitor-task should retain progress events from environment-backed agent state"))))))

(defun task-queue-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (enqueue-result enqueue-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
         provider
         session)
      (assert-equal :enqueue-task enqueue-kind "enqueue-task should dispatch correctly")
      (assert-equal :queued (getf enqueue-result :status) "new task should start queued")
      (assert-equal "task"
                    (getf (getf enqueue-result :execution-surface) :surface-kind)
                    "enqueue-task should expose a task execution surface")
      (assert-equal 1 (length (sbcl-agent::agent-session-tasks updated-session))
                    "session should retain one queued task"))
    (multiple-value-bind (tasks kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(list-tasks))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :list-tasks kind "list-tasks should dispatch correctly")
      (assert-equal 1 (length tasks) "list-tasks should return one task summary")
      (assert-equal "task"
                    (getf (getf (first tasks) :execution-surface) :surface-kind)
                    "list-tasks should expose task execution surfaces"))))

(defun enqueue-task-updates-environment-agent-state-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/enqueue-task-environment-sync/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/enqueue-task-environment-sync/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     provider
     session)
    (let ((agent-summary (sbcl-agent::environment-agent-state-summaries
                          (sbcl-agent::environment-agent-state environment))))
      (assert-equal 1
                    (getf agent-summary :task-count)
                    "enqueue-task should update environment agent task counts immediately"))))

(defun task-run-next-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     provider
     session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(run-next-task))
         provider
         session)
      (assert-equal :run-next-task kind "run-next-task should dispatch correctly")
      (assert-equal :completed (getf result :status) "run-next-task should complete the queued task")
      (assert-equal "task"
                    (getf (getf result :execution-surface) :surface-kind)
                    "run-next-task should preserve the task execution surface")
      (assert-true (search "print-help"
                           (getf (getf result :result) :content))
                   "queued tool task should return fs/read content")
      (assert-true (find :task-completed
                         (sbcl-agent::agent-session-events updated-session)
                         :key #'sbcl-agent::event-kind)
                   "task completion should be logged"))))

(defun task-cancel-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (enqueue-result enqueue-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
         provider
         session)
      (declare (ignore enqueue-kind updated-session))
      (multiple-value-bind (cancel-result cancel-kind final-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(cancel-task ,(getf enqueue-result :id)))
           provider
           session)
        (declare (ignore final-session))
        (assert-equal :cancel-task cancel-kind "cancel-task should dispatch correctly")
        (assert-equal :cancelled (getf cancel-result :status) "cancel-task should finalize the task as cancelled")))))

(defun worker-flow-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     provider
     session)
    (multiple-value-bind (worker-result worker-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(start-worker))
         provider
         session)
      (assert-equal :start-worker worker-kind "start-worker should dispatch correctly")
      (assert-true (stringp (getf worker-result :id)) "start-worker should return a worker id")
      (wait-for (lambda ()
                  (eq :completed
                      (sbcl-agent::task-status
                       (first (sbcl-agent::agent-session-tasks updated-session))))))
      (let ((worker-id (getf worker-result :id)))
        (multiple-value-bind (stop-result stop-kind final-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(stop-worker ,worker-id))
             provider
             updated-session)
          (declare (ignore final-session))
          (assert-equal :stop-worker stop-kind "stop-worker should dispatch correctly")
          (assert-true (not (getf stop-result :running-p)) "stop-worker should mark the worker as stopped")
          (assert-equal "worker"
                        (getf (getf stop-result :execution-surface) :surface-kind)
                        "stop-worker should expose a worker execution surface"))))))

(defun worker-mutations-update-environment-agent-state-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/worker-environment-sync/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/worker-environment-sync/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (multiple-value-bind (start-result start-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(start-worker))
         provider
         session)
      (assert-equal :start-worker start-kind "start-worker should dispatch correctly for environment sync")
      (let ((agent-summary (sbcl-agent::environment-agent-state-summaries
                            (sbcl-agent::environment-agent-state environment))))
        (assert-equal 1
                      (getf agent-summary :worker-count)
                      "start-worker should update environment agent worker count immediately")
        (assert-equal 1
                      (getf agent-summary :active-worker-count)
                      "start-worker should update environment active worker count immediately"))
      (sbcl-agent::execute-command
       (sbcl-agent::normalize-form-command `(stop-worker ,(getf start-result :id)))
       provider
       updated-session)
      (let ((agent-summary (sbcl-agent::environment-agent-state-summaries
                            (sbcl-agent::environment-agent-state environment))))
        (assert-equal 0
                      (getf agent-summary :active-worker-count)
                      "stop-worker should update environment active worker count immediately")))))


(defun worker-introspection-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (start-result start-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(start-worker))
         provider
         session)
      (assert-equal :start-worker start-kind "start-worker should dispatch correctly for introspection")
      (multiple-value-bind (workers workers-kind introspected-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(list-workers))
           provider
           updated-session)
        (assert-equal :list-workers workers-kind "list-workers should dispatch correctly")
        (assert-equal 1 (length workers) "list-workers should return one worker summary")
        (assert-equal "worker"
                      (getf (getf (first workers) :execution-surface) :surface-kind)
                      "list-workers should expose worker execution surfaces")
        (multiple-value-bind (worker-result worker-kind final-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(describe-worker ,(getf start-result :id)))
             provider
             introspected-session)
          (declare (ignore final-session))
          (assert-equal :describe-worker worker-kind "describe-worker should dispatch correctly")
          (assert-equal (getf start-result :id) (getf worker-result :id)
                        "describe-worker should return the matching worker id")
          (assert-equal "worker"
                        (getf (getf worker-result :execution-surface) :surface-kind)
                        "describe-worker should expose a worker execution surface"))
      (sbcl-agent::execute-command
       (sbcl-agent::normalize-form-command `(stop-worker ,(getf start-result :id)))
       provider
       introspected-session)))))

(defun worker-monitoring-prefers-environment-agent-state-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/worker-monitoring-environment/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/worker-monitoring-environment/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (multiple-value-bind (start-result start-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(start-worker))
         provider
         session)
      (assert-equal :start-worker start-kind "start-worker should dispatch correctly for environment-backed monitoring")
      (sbcl-agent::refresh-environment-agent-domain environment updated-session)
      (setf (sbcl-agent::agent-session-workers updated-session) '()
            (sbcl-agent::agent-session-workers-tail updated-session) nil)
      (let ((workers (sbcl-agent::list-worker-summaries updated-session))
            (worker-id (getf start-result :id)))
        (assert-equal 1 (length workers)
                      "list-worker-summaries should prefer environment-backed agent state when bound")
        (assert-equal worker-id
                      (getf (sbcl-agent::worker-summary (sbcl-agent::find-worker updated-session worker-id)) :id)
                      "find-worker should prefer environment-backed agent state when bound")
        (setf (sbcl-agent::worker-state-running-p
               (sbcl-agent::find-worker updated-session worker-id))
              nil)))))

(defun work-item-creation-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (declare (ignore provider))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     (make-test-provider)
     session)
    (assert-equal 1 (length (sbcl-agent::agent-session-work-items session))
                  "enqueue-task should create one transitional work-item")
    (let ((work-item (first (sbcl-agent::agent-session-work-items session)))
          (task (first (sbcl-agent::agent-session-tasks session))))
      (assert-equal (sbcl-agent::task-work-item-id task)
                    (sbcl-agent::work-item-id work-item)
                    "queued task should link to its work-item")
      (assert-equal :planned (sbcl-agent::work-item-status work-item)
                    "new work-item should reflect planned transitional task state"))))

(defun work-item-persistence-test ()
  (let* ((path #P"/tmp/sbcl-agent-work-item-session.sexp")
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     (make-test-provider)
     session)
    (sbcl-agent::save-session session path)
    (let ((loaded (sbcl-agent::load-session path)))
      (assert-equal 1 (length (sbcl-agent::agent-session-work-items loaded))
                    "saved session should preserve transitional work-items")
      (assert-equal :planned
                    (sbcl-agent::work-item-status (first (sbcl-agent::agent-session-work-items loaded)))
                    "loaded work-item should preserve status"))))

(defun work-item-checkpoint-test ()
  (let ((session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     (make-test-provider)
     session)
    (let ((work-item (first (sbcl-agent::agent-session-work-items session))))
      (assert-equal 1 (length (sbcl-agent::work-item-checkpoints work-item))
                    "new transitional work-item should capture one checkpoint")
      (assert-equal :checkpointed
                    (sbcl-agent::mutation-transaction-state (first (sbcl-agent::work-item-transactions work-item)))
                    "new work-item transaction should advance to checkpointed before execution"))))

(defun work-item-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (enqueue-result enqueue-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
         provider
         session)
      (declare (ignore enqueue-kind))
      (multiple-value-bind (list-result list-kind listed-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(list-work-items))
           provider
           updated-session)
        (declare (ignore listed-session))
        (assert-equal :list-work-items list-kind "list-work-items should dispatch correctly")
        (assert-equal 1 (length list-result) "list-work-items should return one work-item summary")
        (assert-true (stringp (getf (getf (first list-result) :primary-execution-handle)
                                    :execution-id))
                     "list-work-items should expose the enqueue execution as the primary handle"))
      (multiple-value-bind (detail-result detail-kind detailed-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(describe-work-item ,(getf enqueue-result :work-item-id)))
           provider
           updated-session)
        (declare (ignore detailed-session))
        (assert-equal :describe-work-item detail-kind "describe-work-item should dispatch correctly")
        (assert-equal 1 (length (getf detail-result :transactions))
                      "describe-work-item should expose transaction detail")
        (assert-equal 1 (length (getf detail-result :checkpoints))
                      "describe-work-item should expose checkpoint detail")
        (assert-true (stringp (getf (getf detail-result :primary-execution-handle)
                                    :execution-id))
                     "work-item detail should expose the enqueue execution as the primary handle"))
      (let* ((work-item-id (getf enqueue-result :work-item-id))
             (approval-response (sbcl-agent::command-request-work-item-approval-service updated-session
                                                                                        work-item-id
                                                                                        :workspace-write
                                                                                        :reason "Execution-native detail"))
             (execution-id (getf (getf approval-response :metadata) :execution-id)))
        (multiple-value-bind (execution-detail execution-kind execution-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(describe-work-item ,execution-id))
             provider
             updated-session)
          (declare (ignore execution-session))
          (assert-equal :describe-work-item execution-kind
                        "describe-work-item should accept execution ids")
          (assert-equal work-item-id
                        (getf execution-detail :id)
                        "describe-work-item should resolve execution ids to work-items")
          (assert-equal execution-id
                        (getf (getf execution-detail :primary-execution-handle) :execution-id)
                        "work-item detail should expose the canonical governing execution handle")
          (assert-equal "governed-work"
                        (getf (getf execution-detail :execution-surface) :surface-kind)
                        "work-item detail should expose the governed execution surface"))))))

(defun work-item-plan-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (enqueue-result enqueue-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
         provider
         session)
      (declare (ignore enqueue-kind))
      (let ((work-item-id (getf enqueue-result :work-item-id)))
        (multiple-value-bind (plan-result plan-kind plan-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(describe-work-item-plan ,work-item-id))
             provider
             updated-session)
          (declare (ignore plan-session))
          (assert-equal :describe-work-item-plan plan-kind
                        "describe-work-item-plan should dispatch correctly")
          (assert-equal work-item-id
                        (getf plan-result :id)
                        "describe-work-item-plan should return the requested work-item")
          (assert-true (listp (getf plan-result :plan-steering))
                       "describe-work-item-plan should expose plan steering")
          (assert-true (stringp (getf (getf plan-result :primary-execution-handle)
                                      :execution-id))
                       "work-item plan should expose the enqueue execution as the primary handle"))
        (multiple-value-bind (steer-result steer-kind steer-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command
              `(steer-work-item-plan ,work-item-id :phase :validate :next-step :run-cold-validation :note "Validation first"))
             provider
             updated-session)
          (declare (ignore steer-session))
          (assert-equal :steer-work-item-plan steer-kind
                        "steer-work-item-plan should dispatch correctly")
          (assert-equal :operator-steered
                        (getf (getf steer-result :next-action) :type)
                        "steer-work-item-plan should produce an operator-directed next action")
          (assert-equal :validate
                        (getf (getf steer-result :plan-steering) :operator-directed-phase)
                        "steer-work-item-plan should preserve the operator-directed phase")
          (assert-equal :run-cold-validation
                        (getf (getf steer-result :plan-steering) :operator-directed-next-step)
                        "steer-work-item-plan should preserve the operator-directed next step")
          (assert-true (> (getf (getf steer-result :plan-steering) :operator-steering-count) 0)
                       "steer-work-item-plan should record operator steering history"))
        (multiple-value-bind (followup-result followup-kind followup-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(describe-work-item-plan ,work-item-id))
             provider
             updated-session)
          (declare (ignore followup-session))
          (assert-equal :describe-work-item-plan followup-kind
                        "describe-work-item-plan should remain available after steering")
          (assert-equal :validate
                        (getf (getf followup-result :plan-steering) :operator-directed-phase)
                        "describe-work-item-plan should expose the persisted operator-directed phase"))
        (let* ((approval-response (sbcl-agent::command-request-work-item-approval-service updated-session
                                                                                          work-item-id
                                                                                          :workspace-write
                                                                                          :reason "Execution-native plan"))
               (execution-id (getf (getf approval-response :metadata) :execution-id)))
          (multiple-value-bind (execution-plan execution-kind execution-session)
              (sbcl-agent::execute-command
               (sbcl-agent::normalize-form-command `(describe-work-item-plan ,execution-id))
               provider
               updated-session)
          (declare (ignore execution-session))
          (assert-equal :describe-work-item-plan execution-kind
                        "describe-work-item-plan should accept execution ids")
          (assert-equal work-item-id
                        (getf execution-plan :id)
                        "describe-work-item-plan should resolve execution ids to work-items")
          (assert-equal execution-id
                        (getf (getf execution-plan :primary-execution-handle) :execution-id)
                        "work-item plan should expose the canonical governing execution handle")))))))

(defun work-item-validation-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(run-next-task))
     provider
     session)
    (let ((work-item (first (sbcl-agent::agent-session-work-items session))))
      (assert-equal :passed
                    (sbcl-agent::validation-result-status (sbcl-agent::work-item-live-validation-result work-item))
                    "committed work-item should record a passing live validation result")
      (assert-equal :passed
                    (sbcl-agent::validation-result-status (sbcl-agent::work-item-cold-validation-result work-item))
                    "committed work-item should record a passing cold validation result")
      (assert-equal :durable
                    (sbcl-agent::reconciliation-record-status (sbcl-agent::work-item-reconciliation-result work-item))
                    "committed work-item should reconcile to durable status"))))

(defun work-item-failure-validation-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "missing-file.lisp")))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(run-next-task))
     provider
     session)
    (let* ((work-item (first (sbcl-agent::agent-session-work-items session)))
           (transaction (first (sbcl-agent::work-item-transactions work-item))))
      (assert-equal :failed
                    (sbcl-agent::work-item-status work-item)
                    "failing task should mark work-item failed")
      (assert-equal :failed
                    (sbcl-agent::validation-result-status (sbcl-agent::work-item-live-validation-result work-item))
                    "failing work-item should record a failing live validation result")
      (assert-equal :failed
                    (sbcl-agent::validation-result-status (sbcl-agent::work-item-cold-validation-result work-item))
                    "failing work-item should record a failing cold validation result")
      (assert-equal :failed
                    (sbcl-agent::reconciliation-record-status (sbcl-agent::work-item-reconciliation-result work-item))
                    "failing work-item should reconcile to failed status")
      (assert-equal :required
                    (sbcl-agent::mutation-transaction-rollback-status transaction)
                    "failing transaction should require rollback")
      (assert-true (getf (sbcl-agent::mutation-transaction-rollback-detail transaction) :reason)
                   "failing transaction should record rollback detail"))))

(defun work-item-provenance-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(run-next-task))
     provider
     session)
    (let* ((work-item (first (sbcl-agent::agent-session-work-items session)))
           (provenance (sbcl-agent::work-item-provenance work-item))
           (transaction (first (sbcl-agent::work-item-transactions work-item))))
      (assert-true (> (length (sbcl-agent::provenance-record-executed-mutations provenance)) 1)
                   "committed work-item should record executed mutations in provenance")
      (assert-true (> (length (sbcl-agent::mutation-transaction-source-mutations transaction)) 0)
                   "committed transaction should record source mutation evidence")
      (assert-true (> (length (sbcl-agent::mutation-transaction-image-mutations transaction)) 0)
                   "committed transaction should record image mutation evidence")
      (assert-equal :clean
                    (sbcl-agent::provenance-record-taint-status provenance)
                    "committed work-item provenance should record clean taint status"))))

(defun work-item-provenance-shell-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (enqueue-result enqueue-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
         provider
         session)
      (declare (ignore enqueue-kind))
      (sbcl-agent::execute-command
       (sbcl-agent::normalize-form-command '(run-next-task))
       provider
       updated-session)
      (multiple-value-bind (detail-result detail-kind detailed-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(describe-work-item ,(getf enqueue-result :work-item-id)))
           provider
           updated-session)
        (declare (ignore detailed-session))
        (assert-equal :describe-work-item detail-kind "describe-work-item should still dispatch correctly with provenance")
        (assert-true (getf detail-result :provenance-detail)
                     "describe-work-item should expose provenance detail")))))

(defun work-item-taint-reconciliation-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Synthetic taint check" :transaction-scope :test)))
    (sbcl-agent::append-work-item-image-mutation work-item
                                                 (list :kind :synthetic-runtime-patch
                                                       :symbol 'sbcl-agent::demo-symbol))
    (setf (sbcl-agent::work-item-status work-item) :committed)
    (sbcl-agent::update-work-item-validation-results
     session
     work-item
     :passed
     (list :validator :live-test)
     :failed
     (list :validator :cold-test))
    (let ((reconciliation (sbcl-agent::work-item-reconciliation-result work-item)))
      (assert-equal :tainted-live-only
                    (sbcl-agent::reconciliation-record-status reconciliation)
                    "live-only outcomes should remain explicitly tainted when image mutations are not reproduced")
      (assert-equal :not-reproduced
                    (sbcl-agent::reconciliation-record-reproducibility-status reconciliation)
                    "live-only outcomes should report a failed reproducibility status")
      (assert-equal :tainted
                    (sbcl-agent::reconciliation-record-taint-status reconciliation)
                    "live-only outcomes should report a tainted reconciliation status")
      (assert-true (member :image-state-not-reproduced
                           (sbcl-agent::reconciliation-record-taint-reasons reconciliation))
                   "tainted live-only outcomes should explain that the image state was not reproduced")
      (assert-true (member :validation-diverged
                           (sbcl-agent::reconciliation-record-taint-reasons reconciliation))
                   "tainted live-only outcomes should record validation divergence")
      (assert-true (sbcl-agent::validation-result-tainted-p
                    (sbcl-agent::work-item-live-validation-result work-item))
                   "live validation should carry taint when run against tainted image state"))))

(defun validation-and-reconciliation-event-correlation-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Validation event correlation" :transaction-scope :test)))
    (sbcl-agent::update-work-item-validation-results
     session
     work-item
     :passed
     (list :validator :live)
     :failed
     (list :validator :cold))
    (let ((validation-event (find :validation-completed
                                  (sbcl-agent::agent-session-events session)
                                  :key #'sbcl-agent::event-kind))
          (reconciliation-event (find :reconciliation-created
                                      (sbcl-agent::agent-session-events session)
                                      :key #'sbcl-agent::event-kind)))
      (assert-true validation-event
                   "validation completion should emit a workflow event")
      (assert-true reconciliation-event
                   "reconciliation creation should emit a workflow event")
      (assert-equal :workflow
                    (sbcl-agent::event-family validation-event)
                    "validation completion events should be classified as workflow events")
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (getf (sbcl-agent::event-metadata validation-event) :work-item-id)
                    "validation completion events should carry work-item correlation metadata")
      (assert-equal (sbcl-agent::work-item-workflow-record-ref work-item)
                    (getf (sbcl-agent::event-metadata reconciliation-event) :workflow-record-id)
                    "reconciliation events should carry workflow-record correlation metadata"))))

(defun work-item-taint-shell-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Synthetic shell taint check" :transaction-scope :test)))
    (sbcl-agent::append-work-item-image-mutation work-item
                                                 (list :kind :synthetic-runtime-patch
                                                       :symbol 'sbcl-agent::shell-symbol))
    (setf (sbcl-agent::work-item-status work-item) :committed)
    (sbcl-agent::update-work-item-validation-results
     session
     work-item
     :passed
     (list :validator :live-test)
     :failed
     (list :validator :cold-test))
    (multiple-value-bind (detail-result detail-kind detailed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(describe-work-item ,(sbcl-agent::work-item-id work-item)))
         provider
         session)
      (declare (ignore detailed-session))
      (assert-equal :describe-work-item detail-kind "describe-work-item should dispatch correctly for tainted synthetic work-items")
      (assert-equal :tainted-live-only
                    (getf (getf detail-result :reconciliation-result) :status)
                    "describe-work-item should expose tainted live-only reconciliation state")
      (assert-equal :not-reproduced
                    (getf (getf detail-result :reconciliation-result) :reproducibility-status)
                    "describe-work-item should expose reproducibility state")
      (assert-true (member :image-state-not-reproduced
                           (getf detail-result :taint-reasons))
                   "describe-work-item should expose taint reasons on the work-item summary")
      (assert-true (member :validation-diverged
                           (getf (getf detail-result :reconciliation-result) :taint-reasons))
                   "describe-work-item should expose reconciliation taint reasons"))))

(defun workflow-record-creation-test ()
  (let ((session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     (make-test-provider)
     session)
    (assert-equal 1 (length (sbcl-agent::agent-session-workflow-records session))
                  "enqueue-task should create one workflow record alongside the work-item")
    (let* ((work-item (first (sbcl-agent::agent-session-work-items session)))
           (record (first (sbcl-agent::agent-session-workflow-records session))))
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (sbcl-agent::workflow-record-work-item-id record)
                    "workflow record should link back to its work-item")
      (assert-equal (sbcl-agent::workflow-record-id record)
                    (sbcl-agent::work-item-workflow-record-ref work-item)
                    "work-item should link to its workflow record")
      (assert-true (> (length (sbcl-agent::workflow-record-entries record)) 0)
                   "workflow record should capture an initial inspection entry"))))

(defun workflow-record-persistence-test ()
  (let* ((path #P"/tmp/sbcl-agent-workflow-session.sexp")
         (provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(run-next-task))
     provider
     session)
    (sbcl-agent::save-session session path)
    (let ((loaded (sbcl-agent::load-session path)))
      (assert-equal 1 (length (sbcl-agent::agent-session-workflow-records loaded))
                    "saved session should preserve workflow records")
      (assert-true (> (length (sbcl-agent::workflow-record-entries (first (sbcl-agent::agent-session-workflow-records loaded)))) 2)
                   "loaded workflow record should preserve appended entries")
      (assert-equal :committed
                    (sbcl-agent::workflow-record-status (first (sbcl-agent::agent-session-workflow-records loaded)))
                    "loaded workflow record should preserve closure status"))))

(defun workflow-record-shell-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (enqueue-result enqueue-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
         provider
         session)
      (declare (ignore enqueue-result enqueue-kind))
      (sbcl-agent::execute-command
       (sbcl-agent::normalize-form-command '(run-next-task))
       provider
       updated-session)
      (multiple-value-bind (list-result list-kind listed-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(list-workflow-records))
           provider
           updated-session)
        (declare (ignore listed-session))
        (assert-equal :list-workflow-records list-kind "list-workflow-records should dispatch correctly")
        (assert-equal 1 (length list-result) "list-workflow-records should return one workflow record")
        (assert-true (stringp (getf (getf (first list-result) :primary-execution-handle)
                                    :execution-id))
                     "workflow list should expose the enqueue execution as the primary handle"))
      (let* ((record (first (sbcl-agent::agent-session-workflow-records updated-session)))
             (record-id (sbcl-agent::workflow-record-id record)))
        (multiple-value-bind (detail-result detail-kind detailed-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(describe-workflow-record ,record-id))
             provider
             updated-session)
          (declare (ignore detailed-session))
          (assert-equal :describe-workflow-record detail-kind
                        "describe-workflow-record should dispatch correctly")
          (assert-equal record-id
                        (getf detail-result :id)
                        "describe-workflow-record should return the requested workflow record")
          (assert-true (> (length (getf detail-result :entries)) 2)
                       "describe-workflow-record should expose appended workflow entries")
          (assert-equal :committed
                        (getf detail-result :status)
                        "describe-workflow-record should expose committed closure state")
          (assert-true (stringp (getf (getf detail-result :primary-execution-handle)
                                      :execution-id))
                       "workflow detail should expose the enqueue execution as the primary handle")))
      (let* ((work-item (sbcl-agent::create-work-item updated-session
                                                      "Workflow execution shell check"
                                                      :transaction-scope :test))
             (approval-response (sbcl-agent::command-request-work-item-approval-service updated-session
                                                                                        (sbcl-agent::work-item-id work-item)
                                                                                        :workspace-write
                                                                                        :reason "Workflow execution detail"))
             (execution-id (getf (getf approval-response :metadata) :execution-id))
             (record (sbcl-agent::work-item-workflow-record updated-session work-item))
             (record-id (sbcl-agent::workflow-record-id record)))
        (multiple-value-bind (execution-detail execution-kind execution-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(describe-workflow-record ,execution-id))
             provider
             updated-session)
          (declare (ignore execution-session))
          (assert-equal :describe-workflow-record execution-kind
                        "describe-workflow-record should accept execution ids")
          (assert-equal record-id
                        (getf execution-detail :id)
                        "describe-workflow-record should resolve execution ids through work-items")
          (assert-equal execution-id
                        (getf (getf execution-detail :primary-execution-handle) :execution-id)
                        "workflow detail should expose the canonical governing execution handle")
          (assert-equal "governed-work"
                        (getf (getf execution-detail :execution-surface) :surface-kind)
                        "workflow detail should expose the governed execution surface"))))))

(defun workflow-record-approval-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Approval check" :transaction-scope :test))
         (record (first (sbcl-agent::agent-session-workflow-records session))))
    (sbcl-agent::request-work-item-approval session work-item :process-run :reason "Need process execution")
    (assert-equal :awaiting-approval
                  (sbcl-agent::workflow-record-status record)
                  "request-work-item-approval should put the workflow record into awaiting-approval state")
    (assert-equal :approval
                  (sbcl-agent::workflow-record-waiting-on record)
                  "approval requests should mark workflow waiting-on approval")
    (assert-true (find :process-run
                       (sbcl-agent::workflow-record-approval-requirements record)
                       :key (lambda (entry) (getf entry :policy)))
                 "approval requirements should record the requested policy")
    (assert-true (> (length (sbcl-agent::provenance-record-approval-checkpoints (sbcl-agent::work-item-provenance work-item))) 0)
                 "approval requests should be preserved in provenance checkpoints")))

(defun execution-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Execution shell command check" :transaction-scope :test))
         (approval-response (sbcl-agent::command-request-work-item-approval-service session
                                                                                    (sbcl-agent::work-item-id work-item)
                                                                                    :workspace-write
                                                                                    :reason "Execution shell coverage"))
         (execution-id (getf (getf approval-response :metadata) :execution-id)))
    (multiple-value-bind (show-result show-kind shown-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(execution/show ,execution-id))
         provider
         session)
      (declare (ignore shown-session))
      (assert-equal :execution-show show-kind
                    "execution/show should dispatch correctly")
      (assert-equal execution-id
                    (getf (getf show-result :execution) :execution-id)
                    "execution/show should return the requested execution handle")
      (assert-equal :work-item
                    (getf show-result :object-kind)
                    "execution/show should project the governed work-item object kind"))
    (multiple-value-bind (control-result control-kind controlled-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(execution/control ,execution-id :action :approve))
         provider
         session)
      (declare (ignore controlled-session))
      (assert-equal :execution-control control-kind
                    "execution/control should dispatch correctly")
      (assert-true (member :workspace-write
                           (getf (getf control-result :result) :approved-policies))
                   "execution/control should allow policy approval through execution identity"))))

(defun compatibility-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/compatibility-shell-commands/")))
    (ensure-directories-exist "/tmp/compatibility-shell-commands/")
    (sbcl-agent::approve-policy session :process-run)
    (let* ((command-response
             (sbcl-agent::command-invoke-tool-service session :proc/run '(:argv ("/bin/echo" "compat-shell"))))
           (execution-id (getf (sbcl-agent::service-response-metadata command-response) :execution-id)))
      (multiple-value-bind (result kind updated-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(compatibility/list :kind :host-process))
           provider
           session)
        (declare (ignore updated-session))
        (assert-equal :compatibility-list kind
                      "compatibility/list should dispatch correctly")
        (assert-true (> (getf result :count) 0)
                     "compatibility/list should return hosted compatibility executions")
        (let ((matching-entry (find execution-id
                                   (getf result :entries)
                                   :key (lambda (entry) (getf entry :execution-id))
                                   :test #'string=)))
          (assert-true matching-entry
                       "compatibility/list should include the created compatibility execution")
          (assert-equal :host-process
                        (getf matching-entry :kind)
                        "compatibility/list should expose compatibility execution kind")
          (assert-equal :completed
                        (getf matching-entry :status)
                        "compatibility/list should expose completed lifecycle state for synchronous compatibility execution")
          (assert-equal :host-process-sync
                        (getf matching-entry :backend-adapter-id)
                        "compatibility/list should expose the backend adapter id for attached compatibility execution")
          (assert-equal :attached-host-process
                        (getf (getf matching-entry :backend-profile) :runtime-class)
                        "compatibility/list should expose attached host-process runtime posture for synchronous compatibility execution")
          (assert-equal :sbcl-sandbox-worker
                        (getf matching-entry :backend)
                        "compatibility/list should expose compatibility backend")
          (assert-equal '()
                        (getf (getf matching-entry :control-posture) :supported-actions)
                        "compatibility/list should expose an empty compatibility action set for synchronous host-process execution"))))
    (let* ((spawn-response
             (sbcl-agent::command-invoke-tool-service session :proc/spawn '(:argv ("/bin/sleep" "5"))))
           (spawn-execution-id (getf (sbcl-agent::service-response-metadata spawn-response) :execution-id)))
      (multiple-value-bind (result kind updated-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(compatibility/list :kind :host-process))
           provider
           session)
        (declare (ignore updated-session))
        (assert-equal :compatibility-list kind
                      "compatibility/list should keep dispatching correctly after spawned execution")
        (let ((matching-entry (find spawn-execution-id
                                   (getf result :entries)
                                   :key (lambda (entry) (getf entry :execution-id))
                                   :test #'string=)))
          (assert-true matching-entry
                       "compatibility/list should include the spawned compatibility execution")
          (assert-equal :running
                        (getf matching-entry :status)
                        "compatibility/list should expose running lifecycle state for spawned compatibility execution")
          (assert-equal :host-process-detached
                        (getf matching-entry :backend-adapter-id)
                        "compatibility/list should expose the backend adapter id for detached compatibility execution")
          (assert-equal :detached-host-process
                        (getf (getf matching-entry :backend-profile) :runtime-class)
                        "compatibility/list should expose detached host-process runtime posture for spawned compatibility execution")
          (assert-true (member :stop
                               (getf (getf matching-entry :control-posture) :supported-actions))
                       "compatibility/list should expose stop support for spawned compatibility execution")))
      (multiple-value-bind (detail detail-kind detail-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(compatibility/show ,spawn-execution-id))
           provider
           session)
        (declare (ignore detail-session))
        (assert-equal :compatibility-show detail-kind
                      "compatibility/show should dispatch correctly")
        (assert-equal :running
                      (getf (getf detail :lifecycle) :status)
                      "compatibility/show should expose running lifecycle state for spawned compatibility execution")
        (assert-true (integerp (getf (getf detail :lifecycle) :registered-at))
                     "compatibility/show should expose registration time for spawned compatibility execution"))
      (sbcl-agent::command-kernel-control-service session spawn-execution-id :stop))))

(defun linux-app-compatibility-kernel-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/linux-app-compatibility-kernel/")))
    (ensure-directories-exist "/tmp/linux-app-compatibility-kernel/")
    (sbcl-agent::approve-policy session :process-run)
    (sbcl-agent::approve-policy session :linux-app-launch)
    (let* ((echo-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Launch a Linux echo app."
                                                        "linux.echo"
                                                        :payload (list :arguments '("hello-linux"))))
           (echo-execution-id (getf (sbcl-agent::service-response-metadata echo-response) :execution-id))
           (sleep-response
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Launch a Linux sleep app."
                                                        "linux.sleep"
                                                        :payload (list :arguments '("5"))))
           (sleep-execution-id (getf (sbcl-agent::service-response-metadata sleep-response) :execution-id)))
      (multiple-value-bind (list-result list-kind list-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(compatibility/list :kind :linux-app))
           (make-test-provider)
           session)
        (declare (ignore list-session))
        (assert-equal :compatibility-list list-kind
                      "compatibility/list should dispatch correctly for linux-app compatibility executions")
        (let ((echo-entry (find echo-execution-id
                                (getf list-result :entries)
                                :key (lambda (entry) (getf entry :execution-id))
                                :test #'string=))
              (sleep-entry (find sleep-execution-id
                                 (getf list-result :entries)
                                 :key (lambda (entry) (getf entry :execution-id))
                                 :test #'string=)))
          (assert-true echo-entry
                       "compatibility/list should include the attached linux app execution")
          (assert-true sleep-entry
                       "compatibility/list should include the detached linux app execution")
          (assert-equal "linux.echo"
                        (getf echo-entry :app-id)
                        "compatibility/list should preserve the linux app manifest id for attached executions")
          (assert-equal "linux.sleep"
                        (getf sleep-entry :app-id)
                        "compatibility/list should preserve the linux app manifest id for detached executions")
          (assert-equal :running
                        (getf sleep-entry :status)
                        "compatibility/list should surface running lifecycle state for detached linux app executions")))
      (sbcl-agent::command-kernel-control-service session sleep-execution-id :stop))))

(defun compatibility-app-registry-shell-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/compatibility-app-registry-shell/")))
    (ensure-directories-exist "/tmp/compatibility-app-registry-shell/")
    (sbcl-agent::approve-policy session :process-run)
    (sbcl-agent::approve-policy session :linux-app-launch)
    (multiple-value-bind (apps-result apps-kind apps-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(compatibility/apps))
         provider
         session)
      (declare (ignore apps-session))
      (assert-equal :compatibility-apps apps-kind
                    "compatibility/apps should dispatch correctly")
      (assert-true (> (getf apps-result :count) 0)
                   "compatibility/apps should expose registered Linux app manifests"))
    (multiple-value-bind (show-result show-kind show-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(compatibility/app-show "linux.vscode"))
         provider
         session)
      (declare (ignore show-session))
      (assert-equal :compatibility-app-show show-kind
                    "compatibility/app-show should dispatch correctly")
      (assert-equal "linux.vscode"
                    (getf (first (getf show-result :entries)) :id)
                    "compatibility/app-show should expose the selected Linux app manifest")
      (assert-equal :linux-ide-launch
                    (getf (first (getf show-result :entries)) :policy-id)
                    "compatibility/app-show should expose the per-manifest policy contract")
      (assert-equal :desktop-app-bridge
                    (getf (first (getf show-result :entries)) :backend-profile-id)
                    "compatibility/app-show should expose the manifest runtime backend profile")
      (assert-equal :desktop-window
                    (getf (getf (first (getf show-result :entries)) :backend-profile) :display-bridge-kind)
                    "compatibility/app-show should expose the manifest display bridge contract through the backend profile")
      (assert-equal :desktop-session
                    (getf (getf (first (getf show-result :entries)) :backend-profile) :control-plane-kind)
                    "compatibility/app-show should expose the desktop-session control plane through the backend profile")
      (assert-equal :desktop-bridge
                    (getf (getf (first (getf show-result :entries)) :backend-profile) :runtime-class)
                    "compatibility/app-show should expose desktop-bridge runtime posture through the backend profile")
      (assert-equal :desktop-window
                    (getf (first (getf show-result :entries)) :display-surface-kind)
                    "compatibility/app-show should expose the per-manifest display contract"))
    (multiple-value-bind (managed-result managed-kind managed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(compatibility/app-show "linux.intent-demo"))
         provider
         session)
      (declare (ignore managed-session))
      (assert-equal :compatibility-app-show managed-kind
                    "compatibility/app-show should expose managed desktop surface manifests")
      (assert-equal "linux.intent-demo"
                    (getf (first (getf managed-result :entries)) :id)
                    "compatibility/app-show should expose the managed desktop surface manifest id")
      (assert-equal :managed-desktop-surface
                    (getf (first (getf managed-result :entries)) :backend-profile-id)
                    "compatibility/app-show should expose the managed desktop surface backend profile")
      (assert-equal :managed-desktop-surface
                    (getf (getf (first (getf managed-result :entries)) :backend-profile) :runtime-class)
                    "compatibility/app-show should expose managed runtime posture for non-host-process display apps")
      (assert-equal :governed-desktop-surface
                    (getf (getf (first (getf managed-result :entries)) :backend-profile) :substrate-kind)
                    "compatibility/app-show should expose the governed desktop substrate for managed display apps"))
    (multiple-value-bind (launch-result launch-kind launch-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(compatibility/launch "linux.echo" :arguments '("hello-shell")))
         provider
         session)
      (declare (ignore launch-session))
      (assert-equal :compatibility-launch launch-kind
                    "compatibility/launch should dispatch correctly")
      (assert-equal "linux.echo"
                    (getf (getf launch-result :compatibility-target) :app-id)
                    "compatibility/launch should preserve the launched Linux app manifest id")
      (assert-equal :linux-app-launch
                    (getf (getf launch-result :compatibility-target) :policy-id)
                    "compatibility/launch should preserve the launched Linux app policy contract")
      (assert-equal :host-process-sync
                    (getf (getf launch-result :compatibility-target) :backend-profile-id)
                    "compatibility/launch should preserve the launched Linux app backend profile contract")
      (assert-equal :sandbox-proc-runner
                    (getf (getf launch-result :compatibility-target) :backend-implementation)
                    "compatibility/launch should report the actual backend implementation used for launched Linux apps")
      (assert-equal :none
                    (getf (getf launch-result :compatibility-target) :filesystem-scope-kind)
                    "compatibility/launch should preserve the launched Linux app filesystem contract"))
    (multiple-value-bind (managed-launch-result managed-launch-kind managed-launch-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(compatibility/launch "linux.intent-demo"))
         provider
         session)
      (declare (ignore managed-launch-session))
      (assert-equal :compatibility-launch managed-launch-kind
                    "compatibility/launch should dispatch correctly for managed desktop surface apps")
      (assert-equal :managed-desktop-surface
                    (getf (getf managed-launch-result :compatibility-target) :backend-profile-id)
                    "compatibility/launch should preserve the managed desktop surface backend profile")
      (assert-equal :managed-desktop-surface
                    (getf (getf managed-launch-result :compatibility-target) :backend-implementation)
                    "compatibility/launch should report the managed desktop surface implementation")
      (assert-equal :desktop-window
                    (getf (getf managed-launch-result :compatibility-target) :display-surface-kind)
                    "compatibility/launch should preserve the managed display contract")
      (multiple-value-bind (display-list-result display-list-kind display-list-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(display/list))
           provider
           session)
        (declare (ignore display-list-session))
        (assert-equal :display-list display-list-kind
                      "display/list should keep dispatching after managed desktop surface launch")
        (let ((matching-display
                (find (getf (getf managed-launch-result :execution) :execution-id)
                      (getf display-list-result :items)
                      :key (lambda (entry) (getf entry :execution-id))
                      :test #'string=)))
          (assert-true matching-display
                       "display/list should expose managed desktop surface executions")
          (assert-equal :desktop-window
                        (getf matching-display :display-surface-kind)
                        "display/list should preserve the managed desktop surface contract"))))
    (let* ((initial-launch
             (sbcl-agent::command-kernel-invoke-service session
                                                        "Launch Linux app for shell relaunch coverage."
                                                        "linux.echo"
                                                        :payload (list :arguments '("relaunch-shell"))))
           (initial-execution-id (getf (sbcl-agent::service-response-metadata initial-launch) :execution-id)))
      (multiple-value-bind (relaunch-result relaunch-kind relaunch-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(compatibility/relaunch ,initial-execution-id))
           provider
           session)
        (declare (ignore relaunch-session))
        (assert-equal :compatibility-relaunch relaunch-kind
                      "compatibility/relaunch should dispatch correctly")
        (assert-equal :accepted
                      (getf (getf (getf relaunch-result :result) :compatibility-result) :status)
                      "compatibility/relaunch should accept relaunch for terminal linux apps")
        (assert-true (string/= initial-execution-id
                               (getf (getf relaunch-result :execution) :execution-id))
                     "compatibility/relaunch should return a new execution handle")))
    (multiple-value-bind (show-result show-kind show-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(compatibility/app-show "linux.echo"))
         provider
         session)
      (declare (ignore show-session))
      (assert-equal :compatibility-app-show show-kind
                    "compatibility/app-show should keep dispatching after app launch")
      (assert-true (> (getf (first (getf show-result :entries)) :execution-count) 0)
                   "compatibility/app-show should expose execution counts after Linux app launch"))
    (let ((display-package-path "/tmp/compatibility-display-shell.aop"))
      (sbcl-agent::command-platform-package-service display-package-path
                                                   :package-id "display-shell-kit"
                                                   :package-version "1.0.0"
                                                   :title "Display Shell Kit"
                                                   :capability-ids '(:proc/run)
                                                   :session session)
      (rewrite-platform-package-app-display-surface-kind display-package-path
                                                         "linux.echo"
                                                         :desktop-window
                                                         :backend-profile-id :desktop-app-bridge)
      (sbcl-agent::command-platform-import-package-service display-package-path
                                                           :session session)
      (sbcl-agent::command-platform-activate-package-service "display-shell-kit"
                                                             :session session)
      (multiple-value-bind (display-launch-result display-launch-kind display-launch-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(compatibility/launch "linux.echo" :arguments '("display-shell")))
           provider
           session)
        (declare (ignore display-launch-session))
        (assert-equal :compatibility-launch display-launch-kind
                      "compatibility/launch should keep dispatching for package-provided display apps")
        (multiple-value-bind (display-list-result display-list-kind display-list-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command '(display/list))
             provider
             session)
          (declare (ignore display-list-session))
          (let ((matching-display
                  (find (getf (getf display-launch-result :execution) :execution-id)
                        (getf display-list-result :items)
                        :key (lambda (entry) (getf entry :execution-id))
                        :test #'string=)))
            (assert-equal :display-list display-list-kind
                          "display/list should dispatch correctly")
            (assert-true (> (getf display-list-result :count) 0)
                         "display/list should expose display-bearing Linux app surfaces")
            (assert-true matching-display
                         "display/list should include the launched display-bearing Linux app")
            (assert-equal :desktop-window
                          (getf matching-display :display-surface-kind)
                          "display/list should preserve the launched display-bearing Linux app surface contract")))
        (multiple-value-bind (display-select-result display-select-kind display-select-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command
              `(display/select :execution-id ,(getf (getf display-launch-result :execution) :execution-id)))
             provider
             session)
          (declare (ignore display-select-session))
          (assert-equal :display-select display-select-kind
                        "display/select should dispatch correctly")
          (assert-equal (getf (getf display-launch-result :execution) :execution-id)
                        (getf (getf display-select-result :display-surface) :execution-id)
                        "display/select should focus the requested display-bearing Linux app"))
        (multiple-value-bind (display-show-result display-show-kind display-show-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command
              `(display/show :app-id "linux.echo"))
             provider
             session)
          (declare (ignore display-show-session))
          (assert-equal :display-show display-show-kind
                        "display/show should dispatch correctly")
          (assert-equal "linux.echo"
                        (getf (getf display-show-result :display-surface) :app-id)
                        "display/show should expose the requested display-bearing Linux app by app id")
          (assert-equal :display
                        (getf display-show-result :panel-id)
                        "display/show should report display panel posture"))
        (multiple-value-bind (display-select-result display-select-kind display-select-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command '(display/select :app-id "linux.echo"))
             provider
             session)
          (declare (ignore display-select-session))
          (assert-equal :display-select display-select-kind
                        "display/select by app id should dispatch correctly")
          (assert-equal "linux.echo"
                        (getf (getf display-select-result :display-surface) :app-id)
                        "display/select by app id should focus the requested Linux app"))
        (multiple-value-bind (display-step-result display-step-kind display-step-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command '(display/step :next))
             provider
             session)
          (declare (ignore display-step-session))
          (assert-equal :display-step display-step-kind
                        "display/step should dispatch correctly")
          (assert-equal :display
                        (getf display-step-result :panel-id)
                        "display/step should preserve display panel focus"))
        (multiple-value-bind (open-display-result open-display-kind open-display-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command '(open :display-index 0))
             provider
             session)
          (declare (ignore open-display-session))
          (assert-equal :open open-display-kind
                        "open with :display-index should dispatch correctly")
          (assert-equal :display
                        (getf open-display-result :open-via)
                        "open with :display-index should enter through the display lane"))
        (multiple-value-bind (open-display-app-result open-display-app-kind open-display-app-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command '(open :display-app-id "linux.echo"))
             provider
             session)
          (declare (ignore open-display-app-session))
          (assert-equal :open open-display-app-kind
                        "open with :display-app-id should dispatch correctly")
          (assert-equal :display
                        (getf open-display-app-result :open-via)
                        "open with :display-app-id should enter through the display lane"))
        (let* ((desktop-result
                 (first
                  (multiple-value-list
                   (sbcl-agent::execute-command
                    (sbcl-agent::normalize-form-command '(desktop/show))
                    provider
                    session))))
               (display-entry (find :display
                                    (getf desktop-result :entry-points)
                                    :key (lambda (entry) (getf entry :entry-kind))
                                    :test #'eq))
               (display-actions (getf (getf (getf desktop-result :panels) :display) :actions))
               (display-show-action (getf display-actions :show))
               (display-next-action (getf display-actions :next))
               (display-relaunch-action (getf display-actions :relaunch)))
          (assert-true (listp (getf display-entry :actions))
                       "desktop/show should expose structured actions on the top display entry point")
          (assert-equal :show-panel
                        (getf (getf (getf display-entry :actions) :show) :action-kind)
                        "desktop/show should expose a structured show action on the top display entry point")
          (assert-equal :step-panel
                        (getf (getf (getf display-entry :actions) :next) :action-kind)
                        "desktop/show should expose a structured next action on the top display entry point")
          (assert-equal (getf (getf desktop-result :top-display-surface) :app-id)
                        (getf (getf (getf (getf display-entry :actions) :show) :params) :app-id)
                        "desktop/show should preserve app-id in the top display entry show action")
          (assert-equal (getf (getf desktop-result :top-display-surface) :app-id)
                        (getf (getf (getf (getf display-entry :actions) :open) :params) :app-id)
                        "desktop/show should preserve app-id in the top display entry open action")
          (assert-equal :previous
                        (getf (getf (getf (getf display-entry :actions) :previous) :params) :direction)
                        "desktop/show should preserve previous direction on the top display entry")
          (assert-equal :desktop-window
                        (getf (getf (getf desktop-result :panels) :display) :selected-display-surface-kind)
                        "desktop/show should preserve display surface kind in panel state")
          (assert-true (getf (getf (getf desktop-result :panels) :display) :selected-relaunch-ready-p)
                       "desktop/show should preserve relaunch readiness in display panel state")
          (assert-true display-show-action
                       "desktop/show should expose a structured display show action when Linux app windows exist")
          (assert-true display-next-action
                       "desktop/show should expose a structured display next action when Linux app windows exist")
          (assert-true display-relaunch-action
                       "desktop/show should expose a structured display relaunch action when the selected Linux app can relaunch")
          (multiple-value-bind (desktop-show-action-result desktop-show-action-kind desktop-show-action-session)
              (sbcl-agent::execute-command
               (sbcl-agent::normalize-form-command
                `(desktop/action ,@display-show-action))
               provider
               session)
            (declare (ignore desktop-show-action-session))
            (assert-equal :desktop-action desktop-show-action-kind
                          "desktop/action should dispatch correctly for display show")
          (assert-equal :display
                        (getf (getf desktop-show-action-result :result) :panel-id)
                        "desktop/action display show should preserve display panel posture"))
          (multiple-value-bind (desktop-next-action-result desktop-next-action-kind desktop-next-action-session)
              (sbcl-agent::execute-command
               (sbcl-agent::normalize-form-command
                `(desktop/action ,@display-next-action))
               provider
               session)
            (declare (ignore desktop-next-action-session))
            (assert-equal :desktop-action desktop-next-action-kind
                          "desktop/action should dispatch correctly for display next")
            (assert-equal :display
                          (getf (getf desktop-next-action-result :result) :panel-id)
                          "desktop/action display next should preserve display panel posture")
            (assert-equal :next
                          (getf (getf desktop-next-action-result :result) :direction)
                          "desktop/action display next should preserve step direction"))
          (multiple-value-bind (entry-next-action-result entry-next-action-kind entry-next-action-session)
              (sbcl-agent::execute-command
               (sbcl-agent::normalize-form-command
                `(desktop/action ,@(getf (getf display-entry :actions) :next)))
               provider
               session)
            (declare (ignore entry-next-action-session))
            (assert-equal :desktop-action entry-next-action-kind
                          "desktop/action should dispatch correctly for top display entry next")
            (assert-equal :next
                          (getf (getf entry-next-action-result :result) :direction)
                          "desktop/action top display entry next should preserve step direction"))
          (multiple-value-bind (desktop-relaunch-action-result desktop-relaunch-action-kind desktop-relaunch-action-session)
              (sbcl-agent::execute-command
               (sbcl-agent::normalize-form-command
                `(desktop/action ,@display-relaunch-action))
               provider
               session)
            (declare (ignore desktop-relaunch-action-session))
            (assert-equal :desktop-action desktop-relaunch-action-kind
                          "desktop/action should dispatch correctly for display relaunch")
            (assert-equal :display
                          (getf (getf desktop-relaunch-action-result :result) :panel-id)
                          "desktop/action display relaunch should preserve display panel posture")
            (multiple-value-bind (desktop-select-app-result desktop-select-app-kind desktop-select-app-session)
                (sbcl-agent::execute-command
                 (sbcl-agent::normalize-form-command '(desktop/select :panel :display :app-id "linux.echo"))
                 provider
                 session)
              (declare (ignore desktop-select-app-session))
              (assert-equal :desktop-select desktop-select-app-kind
                            "desktop/select by app id should dispatch correctly for display panel")
              (assert-equal "linux.echo"
                            (getf (getf (getf (getf desktop-select-app-result :desktop-model) :panels) :display)
                                  :selected-app-id)
                            "desktop/select by app id should preserve selected display app identity in the desktop model"))))
        (multiple-value-bind (display-control-result display-control-kind display-control-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command
              '(display/control :action :relaunch :app-id "linux.echo"))
             provider
             session)
          (declare (ignore display-control-session))
          (assert-equal :display-control display-control-kind
                        "display/control should dispatch correctly for relaunch by app id")
          (assert-equal :relaunch
                        (getf (getf display-control-result :result) :action)
                        "display/control should preserve the requested relaunch action by app id"))
        (multiple-value-bind (windows-result windows-kind windows-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command '(compatibility/windows :app-id "linux.echo"))
             provider
             session)
          (declare (ignore windows-session))
          (assert-equal :compatibility-windows windows-kind
                        "compatibility/windows should dispatch correctly")
          (let ((window-entry (find (getf (getf display-launch-result :execution) :execution-id)
                                    (getf windows-result :entries)
                                    :key (lambda (entry) (getf entry :execution-id))
                                    :test #'string=)))
            (assert-true window-entry
                         "compatibility/windows should expose launched display-bearing Linux apps")
            (assert-equal :desktop-window
                          (getf window-entry :display-surface-kind)
                          "compatibility/windows should preserve the display bridge kind"))))
      (sbcl-agent::command-platform-deactivate-package-service "display-shell-kit"
                                                               :session session))))

(defun workflow-record-quarantine-resume-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Quarantine check" :transaction-scope :test))
         (record (first (sbcl-agent::agent-session-workflow-records session))))
    (sbcl-agent::quarantine-work-item session work-item "Needs operator review")
    (assert-equal :quarantined
                  (sbcl-agent::workflow-record-status record)
                  "quarantine-work-item should mark the workflow record quarantined")
    (assert-equal :operator-review
                  (sbcl-agent::workflow-record-waiting-on record)
                  "quarantine should block on operator review")
    (assert-equal "Needs operator review"
                  (sbcl-agent::workflow-record-quarantine-reason record)
                  "quarantine should preserve the operator-facing reason")
    (assert-equal :quarantined
                  (sbcl-agent::work-item-status work-item)
                  "quarantine should update the work-item status")
    (sbcl-agent::resume-work-item session work-item :note "Operator approved resume")
    (assert-equal :resumed
                  (sbcl-agent::workflow-record-status record)
                  "resume-work-item should mark the workflow record resumed")
    (assert-equal 1
                  (sbcl-agent::workflow-record-resume-count record)
                  "resume-work-item should increment the resume count")
    (assert-true (> (length (sbcl-agent::workflow-record-operator-interventions record)) 1)
                 "quarantine and resume should both record operator interventions"))
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Execution-native quarantine" :transaction-scope :test))
         (approval-response (sbcl-agent::command-request-work-item-approval-service session
                                                                                    (sbcl-agent::work-item-id work-item)
                                                                                    :workspace-write
                                                                                    :reason "Execution-native quarantine"))
         (execution-id (getf (getf approval-response :metadata) :execution-id))
         (record (sbcl-agent::work-item-workflow-record session work-item)))
    (multiple-value-bind (quarantine-result quarantine-kind quarantine-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command
          `(quarantine-work-item ,execution-id "Operator hold"))
         provider
         session)
      (declare (ignore quarantine-session))
      (assert-equal :quarantine-work-item quarantine-kind
                    "quarantine-work-item should accept execution ids")
      (assert-equal :quarantined
                    (getf quarantine-result :status)
                    "quarantine-work-item should quarantine the underlying work-item"))
    (multiple-value-bind (resume-result resume-kind resume-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command
          `(resume-work-item ,execution-id :note "Resume via execution"))
         provider
         session)
      (declare (ignore resume-session))
      (assert-equal :resume-work-item resume-kind
                    "resume-work-item should accept execution ids")
      (assert-equal :resumed
                    (getf resume-result :status)
                    "resume-work-item should resume the underlying workflow record")
      (assert-equal 1
                    (sbcl-agent::workflow-record-resume-count record)
                    "execution-native resume should update workflow record state"))))

(defun workflow-milestone-event-correlation-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Workflow milestone events" :transaction-scope :test))
         (record (first (sbcl-agent::agent-session-workflow-records session))))
    (sbcl-agent::quarantine-work-item session work-item "Needs operator review")
    (sbcl-agent::resume-work-item session work-item :note "Resume requested")
    (sbcl-agent::close-workflow-record session record '(:done t) :status :committed)
    (let ((quarantine-event (find :workflow-record-quarantined
                                  (sbcl-agent::agent-session-events session)
                                  :key #'sbcl-agent::event-kind))
          (resume-event (find :workflow-record-resumed
                              (sbcl-agent::agent-session-events session)
                              :key #'sbcl-agent::event-kind))
          (close-event (find :workflow-record-closed
                             (sbcl-agent::agent-session-events session)
                             :key #'sbcl-agent::event-kind)))
      (assert-true quarantine-event
                   "quarantine-work-item should emit a workflow-record-quarantined event")
      (assert-true resume-event
                   "resume-work-item should emit a workflow-record-resumed event")
      (assert-true close-event
                   "close-workflow-record should emit a workflow-record-closed event")
      (assert-equal :workflow
                    (sbcl-agent::event-family quarantine-event)
                    "workflow milestone events should remain in the workflow family")
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (getf (sbcl-agent::event-metadata quarantine-event) :work-item-id)
                    "workflow milestone events should carry work-item correlation metadata")
      (assert-equal (sbcl-agent::workflow-record-id record)
                    (getf (sbcl-agent::event-metadata close-event) :workflow-record-id)
                    "workflow closure events should carry workflow-record correlation metadata"))))

(defun workflow-record-operator-shell-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Operator shell check" :transaction-scope :test)))
    (multiple-value-bind (approval-result approval-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(request-work-item-approval ,(sbcl-agent::work-item-id work-item) :process-run :reason "Need process execution"))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :request-work-item-approval approval-kind "request-work-item-approval should dispatch correctly")
      (assert-equal :awaiting-approval
                    (getf (getf approval-result :workflow-record) :status)
                    "work-item detail should expose awaiting approval state"))
    (multiple-value-bind (quarantine-result quarantine-kind quarantined-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(quarantine-work-item ,(sbcl-agent::work-item-id work-item) "Needs operator review"))
         provider
         session)
      (declare (ignore quarantined-session))
      (assert-equal :quarantine-work-item quarantine-kind "quarantine-work-item should dispatch correctly")
      (assert-equal :quarantined
                    (getf quarantine-result :status)
                    "quarantine-work-item should return a quarantined work-item detail"))
    (multiple-value-bind (resume-result resume-kind resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(resume-work-item ,(sbcl-agent::work-item-id work-item) :note "Resume now"))
         provider
         session)
      (declare (ignore resumed-session))
      (assert-equal :resume-work-item resume-kind "resume-work-item should dispatch correctly")
      (assert-equal :resumed
                    (getf resume-result :status)
                    "resume-work-item should return a resumed work-item detail"))
    (let ((record (first (sbcl-agent::agent-session-workflow-records session))))
      (multiple-value-bind (detail-result detail-kind detail-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(describe-workflow-record ,(sbcl-agent::workflow-record-id record)))
           provider
           session)
        (declare (ignore detail-session))
        (assert-equal :describe-workflow-record detail-kind "describe-workflow-record should still dispatch correctly after operator controls")
        (assert-equal 3
                      (length (getf detail-result :operator-interventions))
                      "workflow detail should expose approval, quarantine, and resume interventions")
        (assert-equal 1
                      (getf detail-result :resume-count)
                      "workflow detail should expose resume count")))))

(defun work-item-wait-report-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Wait report check" :transaction-scope :test)))
    (let ((report (sbcl-agent::work-item-wait-report session work-item)))
      (assert-equal :pending-validation
                    (getf report :why)
                    "new work-items should report pending validation work")
      (assert-equal '(:live :cold)
                    (getf report :pending-validations)
                    "new work-items should expose both pending validations"))
    (sbcl-agent::request-work-item-approval session work-item :process-run :reason "Need process execution")
    (let ((report (sbcl-agent::work-item-wait-report session work-item)))
      (assert-equal :approval-required
                    (getf report :why)
                    "approval-gated work should explain the approval dependency")
      (assert-equal :approval
                    (getf report :waiting-on)
                    "approval-gated work should report approval waiting state")
      (assert-true (equal :await-approval
                          (getf (getf report :next-action) :type))
                   "approval-gated work should expose a resumable next action"))
    (let* ((runtime-session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
           (provider (make-test-provider)))
      (sbcl-agent::execute-command
       (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
       provider
       runtime-session)
      (multiple-value-bind (result kind updated-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command
            '(runtime/eval "(progn (defparameter sbcl-agent-user::*wait-report-cold* nil) (setf sbcl-agent-user::*wait-report-cold* :ok) sbcl-agent-user::*wait-report-cold*)" :mutating t))
           provider
           runtime-session)
        (declare (ignore kind updated-session))
        (let* ((cold-work-item (sbcl-agent::find-work-item runtime-session (getf result :work-item-id)))
               (report (sbcl-agent::work-item-wait-report runtime-session cold-work-item)))
          (assert-equal :cold-validation-required
                        (getf report :why)
                        "awaiting-cold-validation work should report a dedicated cold-validation wait reason")
          (assert-true (equal :complete-pending-validations
                              (getf (getf report :next-action) :type))
                       "awaiting-cold-validation work should expose a cold-validation next action"))))))

(defun why-waiting-shell-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Why waiting shell check" :transaction-scope :test)))
    (sbcl-agent::request-work-item-approval session work-item :process-run :reason "Need process execution")
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(why-waiting ,(sbcl-agent::work-item-id work-item)))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :why-waiting kind "why-waiting should dispatch correctly")
      (assert-equal :approval-required
                    (getf result :why)
                    "why-waiting should explain approval blockers")
      (assert-equal :approval
                    (getf result :waiting-on)
                    "why-waiting should return the workflow wait reason")
      (assert-true (equal :await-approval
                          (getf (getf result :next-action) :type))
                   "why-waiting should expose a deterministic next action")
      (assert-equal "governed-work"
                    (getf (getf result :execution-surface) :surface-kind)
                    "why-waiting should expose the governed work execution surface"))
    (let* ((approval-response (sbcl-agent::command-request-work-item-approval-service session
                                                                                       (sbcl-agent::work-item-id work-item)
                                                                                       :workspace-write
                                                                                       :reason "Execution-native why-waiting"))
           (execution-id (getf (getf approval-response :metadata) :execution-id)))
      (multiple-value-bind (execution-result execution-kind execution-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(why-waiting ,execution-id))
           provider
           session)
        (declare (ignore execution-session))
        (assert-equal :why-waiting execution-kind
                      "why-waiting should accept execution ids")
        (assert-equal :approval-required
                      (getf execution-result :why)
                      "why-waiting should resolve execution ids to the underlying wait report")
        (assert-equal :approval
                      (getf execution-result :waiting-on)
                      "why-waiting should preserve the underlying workflow wait reason")
        (assert-equal "governed-work"
                      (getf (getf execution-result :execution-surface) :surface-kind)
                      "why-waiting should preserve execution-surface posture when resolving execution ids")))))

(defun workflow-record-resume-payload-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Resume payload check" :transaction-scope :test))
         (record (first (sbcl-agent::agent-session-workflow-records session))))
    (sbcl-agent::request-work-item-approval session work-item :process-run :reason "Need process execution")
    (assert-equal "RESUME-WORK-ITEM"
                  (symbol-name (first (getf (sbcl-agent::workflow-record-resume-payload record) :resume-command)))
                  "workflow resume payload should preserve a resumable command form")
    (assert-equal "RESUME-WORK-ITEM"
                  (symbol-name (first (getf (sbcl-agent::work-item-resume-payload work-item) :resume-command)))
                  "work-item resume payload should stay aligned with the workflow record")))

(defun session-wait-summary-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-a (sbcl-agent::create-work-item session "Approval blocked" :transaction-scope :test))
         (work-b (sbcl-agent::create-work-item session "Validation pending" :transaction-scope :test))
         (provider (make-test-provider)))
    (sbcl-agent::request-work-item-approval session work-a :process-run :reason "Need process execution")
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command
          '(runtime/eval "(progn (defparameter sbcl-agent-user::*wait-summary-cold* nil) (setf sbcl-agent-user::*wait-summary-cold* :ok) sbcl-agent-user::*wait-summary-cold*)" :mutating t))
         provider
         session)
      (declare (ignore kind updated-session))
      (setf work-b (sbcl-agent::find-work-item session (getf result :work-item-id))))
    (let* ((summary (sbcl-agent::session-wait-summary session))
           (reasons (getf summary :by-reason))
           (session-summary (sbcl-agent::session-summary session)))
      (assert-equal 3
                    (getf summary :blocked-count)
                    "session-wait-summary should count blocked work items")
      (assert-true (find :approval-required reasons :key (lambda (entry) (getf entry :why)))
                   "session-wait-summary should include approval blockers")
      (assert-true (find :cold-validation-required reasons :key (lambda (entry) (getf entry :why)))
                   "session-wait-summary should include cold-validation blockers")
      (assert-true (find :pending-validation reasons :key (lambda (entry) (getf entry :why)))
                   "session-wait-summary should include pending validation blockers")
      (assert-equal 3
                    (getf (getf session-summary :wait-summary) :blocked-count)
                    "session-summary should expose wait-summary data"))))

(defun session-wait-summary-prefers-environment-workflow-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/session-wait-summary-environment/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/session-wait-summary-environment/"
                       :session session))
         (work-item (sbcl-agent::create-work-item session "Environment wait authority" :transaction-scope :test)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::request-work-item-approval session work-item :process-run :reason "Need process execution")
    (let ((environment-summary (sbcl-agent::session-wait-summary session)))
      (setf (sbcl-agent::agent-session-work-items session) '()
            (sbcl-agent::agent-session-work-items-tail session) nil)
      (let ((summary (sbcl-agent::session-wait-summary session)))
        (assert-equal (getf environment-summary :blocked-count)
                      (getf summary :blocked-count)
                      "session-wait-summary should prefer environment-backed workflow state when bound")))))


(defun checkpoint-linked-resume-payload-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Checkpoint link check" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let ((payload (sbcl-agent::work-item-resume-payload work-item)))
      (assert-true (stringp (getf payload :checkpoint-id))
                   "checkpoint-linked resume payload should include checkpoint id")
      (assert-equal (sbcl-agent::latest-work-item-checkpoint-id work-item)
                    (getf payload :checkpoint-id)
                    "resume payload should point at the latest checkpoint"))))

(defun validator-action-plan-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Validator action check" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let ((actions (sbcl-agent::work-item-validator-actions work-item)))
      (assert-equal 2 (length actions)
                    "validator action plan should include live and cold validators for fresh work")
      (assert-true (every (lambda (entry) (stringp (getf entry :checkpoint-id))) actions)
                   "validator action plan should carry checkpoint ids"))))


(defun transaction-replay-id-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Replay id check" :transaction-scope :test))
         (transaction (first (sbcl-agent::work-item-transactions work-item))))
    (assert-true (stringp (sbcl-agent::mutation-transaction-replay-id transaction))
                 "transactions should carry replay ids")
    (assert-true (search "TXN-" (string-upcase (sbcl-agent::mutation-transaction-replay-id transaction)))
                 "transaction replay ids should use the txn prefix")))

(defun validator-task-records-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Validator record check" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let ((records (sbcl-agent::work-item-validator-tasks work-item)))
      (assert-equal 2 (length records)
                    "validator task records should be created for pending validators")
      (assert-true (every (lambda (record)
                            (and (stringp (sbcl-agent::validator-task-record-id record))
                                 (stringp (sbcl-agent::validator-task-record-replay-id record))))
                          records)
                   "validator task records should carry ids and replay ids"))))

(defun list-replay-groups-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "List replay groups" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let* ((records (sbcl-agent::work-item-validator-tasks work-item))
           (group-id (sbcl-agent::validator-task-record-replay-id (first records))))
      (setf (sbcl-agent::validator-task-record-replay-id (second records)) group-id)
      (multiple-value-bind (result kind updated-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(list-replay-groups))
           provider
           session)
        (declare (ignore updated-session))
        (assert-equal :list-replay-groups kind "list-replay-groups should dispatch correctly")
        (assert-equal 1 (length result)
                      "list-replay-groups should return one aggregated replay group")))))

(defun replay-groups-prefer-environment-workflow-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/list-replay-groups-environment/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/list-replay-groups-environment/"
                       :session session))
         (work-item (sbcl-agent::create-work-item session "Environment replay groups" :transaction-scope :test)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let* ((records (sbcl-agent::work-item-validator-tasks work-item))
           (group-id (sbcl-agent::validator-task-record-replay-id (first records))))
      (setf (sbcl-agent::validator-task-record-replay-id (second records)) group-id)
      (sbcl-agent::sync-environment-from-session environment session)
      (setf (sbcl-agent::agent-session-work-items session) '()
            (sbcl-agent::agent-session-work-items-tail session) nil)
      (let ((result (sbcl-agent::session-validator-replay-groups session)))
        (assert-equal 1 (length result)
                      "replay group summaries should prefer environment-backed workflow state when bound")))))

(defun list-image-reconciliations-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "List reconciliations" :transaction-scope :test)))
    (sbcl-agent::mark-work-item-image-only session work-item :reason "Experimental live patch")
    (sbcl-agent::reconcile-image-only-work-item-to-source session work-item "Attached source patch")
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(list-image-reconciliations))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :list-image-reconciliations kind "list-image-reconciliations should dispatch correctly")
      (assert-equal 1 (length result)
                    "list-image-reconciliations should return one reconciliation record"))))

(defun image-reconciliations-prefer-environment-workflow-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/list-reconciliations-environment/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/list-reconciliations-environment/"
                       :session session))
         (work-item (sbcl-agent::create-work-item session "Environment reconciliations" :transaction-scope :test)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::mark-work-item-image-only session work-item :reason "Experimental live patch")
    (sbcl-agent::reconcile-image-only-work-item-to-source session work-item "Attached source patch")
    (sbcl-agent::sync-environment-from-session environment session)
    (setf (sbcl-agent::agent-session-work-items session) '()
          (sbcl-agent::agent-session-work-items-tail session) nil)
    (let ((result (sbcl-agent::session-image-reconciliation-summary session)))
      (assert-equal 1 (length result)
                    "image reconciliation summaries should prefer environment-backed workflow state when bound"))))

(defun replay-validator-set-mixed-status-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Replay mixed status" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let* ((live (first (sbcl-agent::work-item-validator-tasks work-item)))
           (cold (second (sbcl-agent::work-item-validator-tasks work-item))))
      (setf (sbcl-agent::validator-task-record-replay-id cold)
            (sbcl-agent::validator-task-record-replay-id live))
      (sbcl-agent::execute-validator-replay-set session
                                                work-item
                                                (sbcl-agent::validator-task-record-replay-id live)
                                                :status :passed
                                                :statuses '(:live :partial :cold :failed))
      (assert-equal :partial
                    (sbcl-agent::validation-result-status (sbcl-agent::work-item-live-validation-result work-item))
                    "mixed replay should allow live validation to be partial")
      (assert-equal :failed
                    (sbcl-agent::validation-result-status (sbcl-agent::work-item-cold-validation-result work-item))
                    "mixed replay should allow cold validation to fail"))))

(defun session-replay-group-summary-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Replay group summary" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let* ((records (sbcl-agent::work-item-validator-tasks work-item))
           (group-id (sbcl-agent::validator-task-record-replay-id (first records))))
      (setf (sbcl-agent::validator-task-record-replay-id (second records)) group-id)
      (let ((groups (sbcl-agent::session-validator-replay-groups session)))
        (assert-equal 1 (length groups)
                      "session replay group summary should aggregate shared replay ids")
        (assert-equal 2 (getf (first groups) :task-count)
                      "session replay group summary should count grouped validator tasks")))))

(defun session-image-reconciliation-summary-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Reconciliation summary" :transaction-scope :test)))
    (sbcl-agent::mark-work-item-image-only session work-item :reason "Experimental live patch")
    (sbcl-agent::reconcile-image-only-work-item-to-source session work-item "Attached source patch")
    (let ((items (sbcl-agent::session-image-reconciliation-summary session)))
      (assert-equal 1 (length items)
                    "session image reconciliation summary should expose reconciled image-only work")
      (assert-equal :attached-to-source
                    (getf (first items) :status)
                    "session image reconciliation summary should preserve reconciliation status"))))

(defun doctor-command-replay-and-reconciliation-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (config (sbcl-agent::load-config))
         (stdout (make-string-output-stream))
         (work-item (sbcl-agent::create-work-item session "Doctor replay summary" :transaction-scope :test)))
    (setf sbcl-agent::*current-session* session)
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (sbcl-agent::mark-work-item-image-only session work-item :reason "Experimental live patch")
    (sbcl-agent::reconcile-image-only-work-item-to-source session work-item "Attached source patch")
    (let ((*standard-output* stdout))
      (assert-equal 0 (sbcl-agent::doctor-command config)
                    "doctor command should succeed with replay and reconciliation data"))
    (let ((output (get-output-stream-string stdout)))
      (assert-true (search "Validator replay groups:" output)
                   "doctor should print validator replay group count")
      (assert-true (search "Image reconciliations:" output)
                   "doctor should print image reconciliation count"))))

(defun replay-validator-set-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Replay validator set shell" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let* ((replay-id (sbcl-agent::validator-task-record-replay-id (first (sbcl-agent::work-item-validator-tasks work-item)))))
      (multiple-value-bind (result kind updated-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(replay-validator-set ,(sbcl-agent::work-item-id work-item) ,replay-id :status :partial))
           provider
           session)
        (declare (ignore updated-session))
        (assert-equal :replay-validator-set kind "replay-validator-set should dispatch correctly")
        (assert-equal :partial
                      (getf (getf result :live-validation-result) :status)
                      "replay-validator-set should propagate partial status")
        (assert-true (member :cold (getf result :pending-validations))
                     "replaying one validator set should leave cold validation pending when replay ids are per validator")))))

(defun validator-failure-status-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Validator failure" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let ((validator-id (sbcl-agent::validator-task-record-id (first (sbcl-agent::work-item-validator-tasks work-item)))))
      (sbcl-agent::execute-validator-task-record session work-item validator-id :status :failed)
      (assert-equal :failed
                    (sbcl-agent::validation-result-status (sbcl-agent::work-item-live-validation-result work-item))
                    "validator replay should preserve failed status")
      (assert-equal :failed
                    (sbcl-agent::validator-task-record-status (first (sbcl-agent::work-item-validator-tasks work-item)))
                    "validator task record should preserve failed status"))))

(defun image-reconciliation-record-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Image reconciliation record" :transaction-scope :test)))
    (sbcl-agent::mark-work-item-image-only session work-item :reason "Experimental live patch")
    (sbcl-agent::reconcile-image-only-work-item-to-source session work-item "Attached source patch")
    (let ((record (sbcl-agent::work-item-image-reconciliation work-item)))
      (assert-true record "reconciling image-only work should create an image reconciliation record")
      (assert-equal :attached-to-source
                    (sbcl-agent::image-reconciliation-record-status record)
                    "image reconciliation record should preserve attached-to-source status"))))

(defun replay-validator-task-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Replay validator shell" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let ((validator-id (sbcl-agent::validator-task-record-id (first (sbcl-agent::work-item-validator-tasks work-item)))))
      (multiple-value-bind (result kind updated-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(replay-validator-task ,(sbcl-agent::work-item-id work-item) ,validator-id :status :passed))
           provider
           session)
        (declare (ignore updated-session))
      (assert-equal :replay-validator-task kind "replay-validator-task should dispatch correctly")
      (assert-equal 1
                    (length (getf result :pending-validations))
                    "replaying one validator should leave one pending validator")
      (assert-equal :passed
                    (getf (getf result :live-validation-result) :status)
                    "replaying the first validator should record a passed live validation")
      (assert-true (find :validation
                         (sbcl-agent::agent-session-artifacts session)
                         :key #'sbcl-agent::artifact-kind)
                   "replaying a validator should create a validation artifact")))))

(defun reconcile-image-only-source-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Image-only reconcile shell" :transaction-scope :test)))
    (sbcl-agent::mark-work-item-image-only session work-item :reason "Experimental live patch")
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(reconcile-image-only-source ,(sbcl-agent::work-item-id work-item) "Captured source patch"))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :reconcile-image-only-source kind "reconcile-image-only-source should dispatch correctly")
      (assert-equal :committed
                    (getf result :status)
                    "reconciling image-only work should return a committed work-item detail")
      (assert-equal :committed-to-source-and-image
                    (getf result :closure-decision)
                    "reconciling image-only work should produce a durable closure decision")
      (assert-true (find :reconciliation
                         (sbcl-agent::agent-session-artifacts session)
                         :key #'sbcl-agent::artifact-kind)
                   "reconciling image-only work should create a reconciliation artifact"))))

(defun image-only-outcome-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Image only check" :transaction-scope :test)))
    (sbcl-agent::mark-work-item-image-only session work-item :reason "Experimental live patch")
    (assert-equal :image-only
                  (sbcl-agent::work-item-status work-item)
                  "image-only outcome should set the work-item status")
    (assert-equal :committed-to-image-only
                  (sbcl-agent::work-item-closure-decision work-item)
                  "image-only outcome should preserve the closure decision")
    (let ((status (sbcl-agent::session-operator-status session)))
      (assert-equal 1 (getf status :image-only-count)
                    "operator status should count image-only work items"))))

(defun operator-status-summary-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (ready (sbcl-agent::create-work-item session "Ready item" :transaction-scope :test))
         (blocked (sbcl-agent::create-work-item session "Blocked item" :transaction-scope :test))
         (quarantined (sbcl-agent::create-work-item session "Quarantined item" :transaction-scope :test)))
    (sbcl-agent::update-work-item-validation-results session ready :passed '(:live) :passed '(:cold))
    (sbcl-agent::request-work-item-approval session blocked :process-run :reason "Need process execution")
    (sbcl-agent::quarantine-work-item session quarantined "Needs review")
    (setf (sbcl-agent::work-item-closure-decision ready) :committed-to-source-and-image)
    (let ((status (sbcl-agent::session-operator-status session)))
      (assert-equal 0 (getf status :ready-count)
                    "durable source-and-image work should not remain in the generic ready bucket")
      (assert-equal 1 (getf status :durable-count)
                    "operator status should count durable source-and-image work items")
      (assert-equal 1 (getf status :blocked-count)
                    "operator status should count blocked work items")
      (assert-equal 1 (getf status :quarantined-count)
                    "operator status should count quarantined work items")
      (assert-equal 0 (getf status :incident-count)
                    "operator status should report incident count when none are recorded"))))

(defun operator-status-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::request-work-item-approval session
                                            (sbcl-agent::create-work-item session "Operator tool blocked" :transaction-scope :test)
                                            :process-run
                                            :reason "Need process execution")
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :session/operator-status))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :tool kind "operator status tool should dispatch as :tool")
      (assert-equal :session/operator-status (getf result :tool)
                    "operator status tool should identify itself")
      (assert-equal 1
                    (getf (getf result :status) :blocked-count)
                    "operator status tool should expose blocked count")
      (assert-equal 0
                    (getf (getf result :status) :image-only-count)
                    "operator status tool should expose image-only count"))))

(defun doctor-command-wait-summary-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (config (sbcl-agent::load-config))
         (stdout (make-string-output-stream)))
    (setf sbcl-agent::*current-session* session)
    (sbcl-agent::request-work-item-approval session
                                            (sbcl-agent::create-work-item session "Doctor blocked" :transaction-scope :test)
                                            :process-run
                                            :reason "Need process execution")
    (let ((*standard-output* stdout))
      (assert-equal 0
                    (sbcl-agent::doctor-command config)
                    "doctor command should succeed"))
    (let ((output (get-output-stream-string stdout)))
      (assert-true (search "Blocked work items: 1" output)
                   "doctor command should print blocked work-item count")
      (assert-true (search ":APPROVAL-REQUIRED" output)
                   "doctor command should print blocked work-item reasons")
      (assert-true (search "Blocked surfaces: 1" output)
                   "doctor command should print blocked surface count")
      (assert-true (search "Blocked open: (open :" output)
                   "doctor command should print the blocked-work open handoff")
      (assert-true (search "Approval surfaces: 1" output)
                   "doctor command should print approval surface count")
      (assert-true (search "Approval open: (open :" output)
                   "doctor command should print the approval open handoff")
      (assert-true (search "Task surfaces: 0" output)
                   "doctor command should print task surface count")
      (assert-true (search "Worker surfaces: 0" output)
                   "doctor command should print worker surface count")
      (assert-true (search "Operator status: ready=0 blocked=1 quarantined=0 image-only=0 durable=0 incidents=0 open-incidents=0" output)
                   "doctor command should print operator status counts"))))

(defun doctor-command-task-worker-surface-summary-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (config (sbcl-agent::load-config))
         (stdout (make-string-output-stream)))
    (setf sbcl-agent::*current-session* session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(start-worker))
     provider
     session)
    (let ((*standard-output* stdout))
      (assert-equal 0
                    (sbcl-agent::doctor-command config)
                    "doctor command should succeed with task and worker surfaces"))
    (let ((output (get-output-stream-string stdout)))
      (assert-true (search "Task surfaces: 1" output)
                   "doctor command should print task surface count when a task exists")
      (assert-true (search "Task top surface: kind=task" output)
                   "doctor command should print the top task surface posture")
      (assert-true (search "Task open: (open :" output)
                   "doctor command should print the task open handoff")
      (assert-true (search "Worker surfaces: 1" output)
                   "doctor command should print worker surface count when a worker exists")
      (assert-true (search "Worker top surface: kind=worker" output)
                   "doctor command should print the top worker surface posture")
      (assert-true (search "Worker open: (open :" output)
                   "doctor command should print the worker open handoff"))))

(defun task-persistence-test ()
  (let* ((provider (make-test-provider))
         (path "/tmp/sbcl-agent-task-session.sexp")
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(start-worker))
     provider
     session)
    (sbcl-agent::save-session session path)
    (let ((loaded (sbcl-agent::load-session path)))
      (assert-equal 1 (length (sbcl-agent::agent-session-tasks loaded))
                    "loaded session should preserve queued task state")
      (assert-true (every (lambda (worker) (null (sbcl-agent::worker-state-thread worker)))
                         (sbcl-agent::agent-session-workers loaded))
                   "loaded session should sanitize worker thread objects")
      (assert-true (every (lambda (worker) (not (sbcl-agent::worker-state-running-p worker)))
                         (sbcl-agent::agent-session-workers loaded))
                   "loaded session should mark persisted workers as not running"))))
(defun assistant-action-proposal-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (response (sbcl-agent::send-prompt provider "please read src/main.lisp" session)))
    (assert-equal 1 (length (sbcl-agent::assistant-response-actions response))
                  "mock provider should propose one read action")
    (assert-equal :TOOL
                  (sbcl-agent::assistant-action-type (first (sbcl-agent::assistant-response-actions response)))
                  "proposed action should be a tool action")))

(defun assistant-action-staging-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (command (sbcl-agent::normalize-form-command '(ask "please read src/main.lisp"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (declare (ignore kind))
      (assert-equal 1 (getf result :staged-action-count)
                    "ask flow should stage one proposed action")
      (assert-equal 0 (getf result :immediate-action-count)
                    "tool-only ask flow should not auto-execute any actions")
      (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions updated-session))
                    "session should retain one staged action")
      (assert-true (= 0 (length (or (getf result :action-results) '())))
                   "tool and patch actions should not execute immediately"))))

(defun assistant-mixed-action-ask-test ()
  (let* ((provider (make-instance 'mixed-action-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (command (sbcl-agent::normalize-form-command '(ask "execute and inspect"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (assert-equal :ask kind "mixed-action ask should dispatch as :ask")
      (assert-equal 1 (getf result :immediate-action-count)
                    "ask should auto-execute eval actions")
      (assert-equal 1 (getf result :staged-action-count)
                    "ask should still stage tool actions")
      (assert-equal 1 (length (getf result :action-results))
                    "ask should return immediate eval results")
      (assert-equal 303
                    (getf (getf (first (getf result :action-results)) :result) :result)
                    "immediate eval action should execute in the current image")
      (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions updated-session))
                    "only non-eval actions should remain staged")
      (assert-equal 3 (length (sbcl-agent::agent-session-operations updated-session))
                    "ask should now persist provider, immediate, and staged action operations")
      (assert-equal :tool
                    (sbcl-agent::assistant-action-type (first (sbcl-agent::agent-session-pending-actions updated-session)))
                    "the staged remainder should be the tool action"))))

(defun assistant-action-execution-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(ask "please read src/main.lisp"))
     provider
     session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(execute-actions))
         provider
         session)
      (assert-equal :execute-actions kind "execute-actions should dispatch correctly")
      (assert-equal 1 (length result)
                    "execute-actions should execute one staged action")
      (assert-true (search "(defun print-help ()"
                           (getf (getf (first result) :result) :content))
                   "executed assistant action should read src/main.lisp")
      (assert-equal 0 (length (sbcl-agent::agent-session-pending-actions updated-session))
                    "pending actions should be cleared after execution"))))

(defun assistant-eval-action-execution-test ()
  (let* ((session (sbcl-agent::make-default-session))
         (action (sbcl-agent::make-assistant-action :type :eval
                                                    :payload '(:form "(+ 100 203)")))
         (code-action (sbcl-agent::make-assistant-action :type :eval
                                                         :payload '(:code "(+ 100 203)"))))
    (assert-equal 303
                  (getf (sbcl-agent::execute-assistant-action action session) :result)
                  "assistant eval actions should execute Common Lisp forms in the current image")
    (assert-equal 303
                  (getf (sbcl-agent::execute-assistant-action code-action session) :result)
                  "assistant eval actions should also accept payloads under :code")))

(defun direct-conversation-runtime-eval-routing-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session))
         (result (sbcl-agent::service-response-data
                  (sbcl-agent::command-conversation-execution-service session
                                                                      provider
                                                                      "(+ 5 6)"
                                                                      '()
                                                                      :source :say
                                                                      :operator-mode :conversation)))
         (turn-id (getf (getf result :turn) :id))
         (turn-detail (sbcl-agent::turn-detail session turn-id))
         (operations (getf turn-detail :operations))
         (eval-operation (find "conversation-runtime-eval"
                               operations
                               :key (lambda (entry) (getf entry :name))
                               :test #'string=)))
    (assert-true (getf result :direct-runtime-eval-p)
                 "bare Lisp forms in conversation should route directly to runtime eval")
    (assert-equal :direct-form
                  (getf result :direct-runtime-eval-reason)
                  "direct runtime eval routing should record the direct-form reason")
    (assert-true (search "Result: 11."
                         (getf (getf result :assistant-message) :content))
                 "direct runtime eval should answer from the runtime result")
    (assert-true eval-operation
                 "direct runtime eval should create a dedicated runtime operation in the turn")
    (assert-equal :completed
                  (getf eval-operation :status)
                  "direct runtime eval operation should complete")
    (assert-equal 11
                  (getf (getf eval-operation :output) :result)
                  "direct runtime eval output should expose the computed runtime result")
    (assert-true (find :assistant
                       (sbcl-agent::agent-session-transcript session)
                       :key (lambda (entry) (getf entry :role)))
                 "direct runtime eval should still append an assistant transcript entry")))

(defun conversation-runtime-eval-confirmation-routing-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session))
         (thread (sbcl-agent::current-thread session))
         (user-message (sbcl-agent::create-message session thread :user "(+ 5 6)"))
         (turn (sbcl-agent::start-turn session thread user-message))
         (assistant-message (sbcl-agent::create-message session
                                                        thread
                                                        :assistant
                                                        "The result of the expression (+ 5 6) is 11. Would you like me to evaluate this expression directly for you?"
                                                        :turn-id (sbcl-agent::turn-id turn)))
         (_completed-turn (sbcl-agent::complete-turn session
                                                     thread
                                                     turn
                                                     assistant-message
                                                     :status :completed))
         (result (sbcl-agent::service-response-data
                  (sbcl-agent::command-conversation-execution-service session
                                                                      provider
                                                                      "yes"
                                                                      '()
                                                                      :source :say
                                                                      :operator-mode :conversation)))
         (turn-id (getf (getf result :turn) :id))
         (turn-detail (sbcl-agent::turn-detail session turn-id))
         (eval-operation (find "conversation-runtime-eval"
                               (getf turn-detail :operations)
                               :key (lambda (entry) (getf entry :name))
                               :test #'string=)))
    (declare (ignore _completed-turn))
    (assert-true (getf result :direct-runtime-eval-p)
                 "explicit confirmation should route the conversation into runtime eval")
    (assert-equal :confirmed-prior-form
                  (getf result :direct-runtime-eval-reason)
                  "explicit confirmation should reuse the pending prior form")
    (assert-true (search "Evaluated the previously requested form"
                         (getf (getf result :assistant-message) :content))
                 "confirmation routing should explain that the prior form was evaluated")
    (assert-true eval-operation
                 "confirmation routing should still create a runtime eval operation")
    (assert-equal 11
                  (getf (getf eval-operation :output) :result)
                  "confirmation routing should evaluate the prior Lisp form in the runtime")))

(defun pasted-assistant-action-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session))
         (action (sbcl-agent::make-assistant-action :type :eval
                                                    :payload '(:form "(+ 100 203)")))
         (command (sbcl-agent::normalize-form-command action)))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (assert-equal :assistant-action kind
                    "pasted assistant-action objects should normalize into a dedicated shell command")
      (assert-equal 303 (getf result :result)
                    "pasted assistant-action command should execute the assistant action payload")
      (assert-true (find :assistant-action
                         (sbcl-agent::agent-session-transcript updated-session)
                         :key (lambda (entry) (getf entry :role)))
                   "executed assistant actions should be recorded in the transcript"))))

(defun journal-date-time-followup-execution-test ()
  (let* ((provider (make-instance 'journal-date-time-provider))
         (session (sbcl-agent::make-default-session))
         (first-command (sbcl-agent::normalize-form-command '(ask "create code that tells me the current data and time"))))
    (multiple-value-bind (first-result first-kind updated-session)
        (sbcl-agent::execute-command first-command provider session)
      (assert-equal :ask first-kind
                    "initial journal ask should dispatch as :ask")
      (assert-true (search "get-decoded-time"
                           (sbcl-agent::assistant-response-message (getf first-result :response))
                           :test #'char-equal)
                   "initial journal ask should return the suggested date/time code")
      (assert-equal 0 (getf first-result :immediate-action-count)
                    "initial journal ask should not auto-execute anything")
      (let ((second-command (sbcl-agent::normalize-form-command '(ask "now go execute that"))))
        (multiple-value-bind (second-result second-kind final-session)
            (sbcl-agent::execute-command second-command provider updated-session)
          (declare (ignore final-session))
          (assert-equal :ask second-kind
                        "follow-up journal ask should dispatch as :ask")
          (assert-equal 1 (getf second-result :immediate-action-count)
                        "follow-up journal ask should auto-execute the remembered eval action")
          (assert-equal 0 (getf second-result :staged-action-count)
                        "follow-up journal ask should not leave staged actions behind")
          (assert-equal 1 (length (getf second-result :action-results))
                        "follow-up journal ask should report the eval result")
          (let ((rendered (getf (getf (first (getf second-result :action-results)) :result) :result)))
            (assert-true (stringp rendered)
                         "executed journal code should return a date/time string")
            (assert-true (search "-" rendered)
                         "rendered date/time string should contain a date separator")
            (assert-true (search ":" rendered)
                         "rendered date/time string should contain a time separator")))))))


(defun session-plan-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session))
         (command (sbcl-agent::normalize-form-command '(plan "Build tool registry"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (assert-equal :plan kind "plan command should dispatch as :plan")
      (assert-true (search "Current plan: Build tool registry" result)
                   "plan command should return the current plan message")
      (assert-equal "Build tool registry"
                    (sbcl-agent::agent-session-plan updated-session)
                    "plan command should update session plan state"))))

(defun capability-policy-model-test ()
  (let ((policies (sbcl-agent::list-capability-policies)))
    (assert-true (find :process-run policies :key (lambda (entry) (getf entry :id)))
                 "capability policy registry should include :process-run")
    (assert-equal :implicit
                  (getf (sbcl-agent::capability-policy-summary
                         (sbcl-agent::ensure-capability-policy :safe-read))
                        :default-grant-mode)
                  "safe-read should be implicitly granted")
    (assert-equal :high
                  (getf (sbcl-agent::capability-policy-summary
                         (sbcl-agent::ensure-capability-policy :git-write))
                        :risk-level)
                  "git-write should be modeled as high risk")))

(defun capability-grant-session-test ()
  (let ((session (sbcl-agent::make-default-session)))
    (assert-true (sbcl-agent::ensure-policy-approved session :safe-read)
                 "safe-read should be implicitly approved")
    (assert-signals-error
     (lambda () (sbcl-agent::ensure-policy-approved session :process-run))
     "Approval required"
     "process-run should still require an explicit capability grant")
    (sbcl-agent::approve-policy session :process-run)
    (assert-true (sbcl-agent::policy-approved-p session :process-run)
                 "process-run should be approved after granting the capability")
    (assert-equal :process-run
                  (getf (first (sbcl-agent::session-capability-grants-summary session)) :policy-id)
                  "session grant summaries should retain the granted policy id")))

(defun session-save-load-test ()
  (let* ((path #P"/tmp/sbcl-agent-session-test.sexp")
         (session (sbcl-agent::make-default-session)))
    (sbcl-agent::update-session-plan session "Persist session")
    (sbcl-agent::append-transcript-entry session :user "hello")
    (sbcl-agent::create-thread session :title "Saved thread")
    (let* ((thread (sbcl-agent::current-thread session))
           (user-message (sbcl-agent::create-message session thread :user "saved prompt"))
           (turn (sbcl-agent::start-turn session thread user-message))
           (assistant-message (sbcl-agent::create-message session thread :assistant "saved response")))
      (sbcl-agent::complete-turn session thread turn assistant-message))
    (sbcl-agent::save-session session path)
    (let ((loaded (sbcl-agent::load-session path)))
      (assert-equal "Persist session"
                    (sbcl-agent::agent-session-plan loaded)
                    "loaded session should preserve plan")
      (assert-true (>= (length (sbcl-agent::agent-session-threads loaded)) 2)
                   "loaded session should preserve created threads")
      (assert-equal 2
                    (length (sbcl-agent::agent-session-messages loaded))
                    "loaded session should preserve persisted messages")
      (assert-equal 1
                    (length (sbcl-agent::agent-session-turns loaded))
                    "loaded session should preserve persisted turns")
      (assert-equal 0
                    (length (sbcl-agent::agent-session-operations loaded))
                    "manually created saved conversation should preserve operation collection when absent")
      (assert-equal 1
                    (length (sbcl-agent::agent-session-transcript loaded))
                    "loaded session should preserve transcript entries"))))

(defun serializable-session-copy-trims-transcript-test ()
  (let ((session (sbcl-agent::make-default-session)))
    (sbcl-agent::append-transcript-entry session :user "trim session transcript")
    (let ((serializable (sbcl-agent::serializable-session-copy session)))
      (assert-equal nil
                    (sbcl-agent::agent-session-transcript serializable)
                    "serializable-session-copy should not duplicate transcript state when events are persisted"))))

(defun project-record-persistence-test ()
  (let* ((path (format nil "/tmp/sbcl-agent-project-record-~D-~D.sexp"
                       (get-universal-time)
                       (random 1000000)))
         (session (sbcl-agent::make-default-session))
         (project (sbcl-agent::create-project-record
                   session
                   :title "IntentOS Shell"
                   :summary "Desktop shell modernization program."
                   :constitution '(:mission "Build a governed environment-first desktop shell."
                                   :principles ("governance-first" "operator-visible"))
                   :requirements
                   (list (sbcl-agent::make-project-requirement
                          :id "req-runtime-stability"
                          :title "Runtime Stability"
                          :summary "The shell must survive reloads and preserve session continuity."
                          :scope :platform
                          :kind :non-functional
                          :priority :high
                          :status :accepted
                          :verification-kind :test-suite))
                   :feature-specifications
                   (list (sbcl-agent::make-project-feature-spec
                          :id "spec-console"
                          :title "Console Surface"
                          :summary "Expose environment and host observability in-browser."
                          :status :in-progress
                          :acceptance-criteria '("show host logs" "show diagnostic inventory")
                          :linked-requirement-ids '("req-runtime-stability")
                          :linked-journey-ids '("journey-runtime-investigation")))
                   :user-journeys
                   (list (sbcl-agent::make-project-user-journey
                          :id "journey-runtime-investigation"
                          :title "Investigate a runtime fault"
                          :summary "Operator follows console, diagnostics, and testing evidence."
                          :actors '("operator" "agent")
                          :entrypoints '("incident" "console")
                          :steps '("inspect logs" "review diagnostics" "run targeted tests")
                          :outcomes '("incident scoped" "repair plan created")
                          :edge-cases '("stale environment image")))
                   :non-functional-requirements
                   (list (sbcl-agent::make-project-requirement
                          :id "nfr-governance-audit"
                          :title "Governance Auditability"
                          :summary "Every material change must remain linked to work and evidence."
                          :scope :system
                          :kind :non-functional
                          :priority :high
                          :status :accepted
                          :verification-kind :replay))
                   :architecture-decisions
                   (list (sbcl-agent::make-project-architecture-decision
                          :id "adr-environment-first"
                          :title "Environment-first runtime model"
                          :status :accepted
                          :summary "The environment is the system of record, not the transient shell."
                          :drivers '("shared introspection" "governed recovery")
                          :consequences '("strong environment state" "desktop shell becomes projection")
                          :stack-choices '("sbcl" "electron")
                          :linked-requirement-ids '("req-runtime-stability" "nfr-governance-audit")))
                   :linked-work-item-ids '("work-item-runtime-stability")
                   :linked-incident-ids '("incident-runtime-recovery")
                   :linked-testing-harness-ids '(:full-suite :coverage)
                   :source-roots '("/Volumes/data/development/sbcl-agent/"
                                   "/Volumes/data/development/sbcl-agent-ux/"))))
    (sbcl-agent::save-session session path)
    (let* ((loaded (sbcl-agent::load-session path))
           (loaded-project (sbcl-agent::current-project-record loaded)))
      (assert-true loaded-project
                   "loading a session should preserve project records")
      (assert-equal (sbcl-agent::project-record-id project)
                    (sbcl-agent::project-record-id loaded-project)
                    "loading a session should preserve the selected project id")
      (assert-equal "IntentOS Shell"
                    (sbcl-agent::project-record-title loaded-project)
                    "loading a session should preserve project titles")
      (assert-equal 1
                    (length (sbcl-agent::project-record-requirements loaded-project))
                    "loading a session should preserve project requirements")
      (assert-equal 1
                    (length (sbcl-agent::project-record-user-journeys loaded-project))
                    "loading a session should preserve project journeys")
      (assert-equal 1
                    (length (sbcl-agent::project-record-architecture-decisions loaded-project))
                    "loading a session should preserve project architecture decisions")
      (assert-equal '("work-item-runtime-stability")
                    (sbcl-agent::project-record-linked-work-item-ids loaded-project)
                    "loading a session should preserve linked work-item ids")
      (assert-equal '("incident-runtime-recovery")
                    (sbcl-agent::project-record-linked-incident-ids loaded-project)
                    "loading a session should preserve linked incident ids")
      (assert-equal '(:full-suite :coverage)
                    (sbcl-agent::project-record-linked-testing-harness-ids loaded-project)
                    "loading a session should preserve linked testing harness ids"))))

(defun environment-creation-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-root/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-root/"
                       :session session))
         (summary (sbcl-agent::environment-summary environment)))
    (assert-true (typep environment 'sbcl-agent::environment)
                 "make-default-environment should create an environment")
    (assert-equal "/tmp/environment-root/"
                  (sbcl-agent::environment-storage-root environment)
                  "environment should preserve the requested storage root")
    (assert-equal (sbcl-agent::agent-session-id session)
                  (getf summary :session-id)
                  "environment summary should expose the compatibility session")
    (assert-equal (sbcl-agent::agent-session-current-thread-id session)
                  (getf summary :active-thread-id)
                  "environment summary should reflect the active thread")))

(defun environment-persistence-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-test.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-root/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-root/"
                       :session session)))
    (sbcl-agent::update-session-plan session "Persist environment")
    (sbcl-agent::append-transcript-entry session :user "hello environment")
    (sbcl-agent::append-session-event session
                                      :environment-persistence-test
                                      '(:checkpoint :before-save)
                                      :family :runtime
                                      :entity-id "persist-1")
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment))
           (loaded-event (find :environment-persistence-test
                               (sbcl-agent::environment-event-log loaded-environment)
                               :key #'sbcl-agent::event-kind)))
      (assert-equal (sbcl-agent::environment-id environment)
                    (sbcl-agent::environment-id loaded-environment)
                    "load-environment should preserve the environment id")
      (assert-equal "Persist environment"
                    (sbcl-agent::agent-session-plan loaded-session)
                    "load-environment should preserve the compatibility session")
      (assert-equal 1
                    (length (sbcl-agent::agent-session-transcript loaded-session))
                    "load-environment should preserve transcript state")
      (assert-true loaded-event
                   "load-environment should preserve projected environment events")
      (assert-equal (sbcl-agent::environment-id loaded-environment)
                    (getf (sbcl-agent::event-metadata loaded-event) :environment-id)
                    "persisted environment event should retain its environment id metadata")
      (assert-equal "persist-1"
                    (sbcl-agent::event-entity-id loaded-event)
                    "persisted environment event should retain its entity id"))))

(defun environment-serializes-compatibility-payload-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-compatibility-payload/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-compatibility-payload/"
                       :session session))
         (serializable (sbcl-agent::serializable-environment-copy environment))
         (payload (sbcl-agent::environment-compatibility-session serializable)))
  (assert-true (typep payload 'sbcl-agent::environment-compatibility-payload)
               "serializable-environment-copy should store an explicit compatibility payload instead of a full agent-session")
  (assert-equal (sbcl-agent::agent-session-id session)
                (sbcl-agent::environment-compatibility-payload-session-id payload)
                "compatibility payload should preserve only the compatibility session identity")))

(defun compatibility-payload-reconstructs-legacy-session-header-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/compatibility-header/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/compatibility-header/"
                       :session session)))
    (sbcl-agent::create-thread session :title "Compatibility header thread")
    (sbcl-agent::sync-environment-from-session environment session)
    (let* ((payload (sbcl-agent::make-environment-compatibility-payload-from-session session))
           (rehydrated (sbcl-agent::compatibility-payload->session payload environment)))
      (assert-equal (sbcl-agent::agent-session-id session)
                    (sbcl-agent::agent-session-id rehydrated)
                    "compatibility payload reconstruction should preserve session identity")
      (assert-equal "/tmp/compatibility-header/"
                    (sbcl-agent::agent-session-cwd rehydrated)
                    "compatibility payload reconstruction should derive cwd from the environment")
      (assert-equal "SBCL-AGENT-USER"
                    (sbcl-agent::agent-session-package rehydrated)
                    "compatibility payload reconstruction should derive package from the environment runtime summary")
      (assert-equal (sbcl-agent::environment-active-thread-id environment)
                    (sbcl-agent::agent-session-current-thread-id rehydrated)
                    "compatibility payload reconstruction should derive the active thread from the environment"))))

(defun serializable-environment-copy-preserves-existing-compatibility-payload-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-preserve-compatibility-payload/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-preserve-compatibility-payload/"
                       :session session))
         (payload (sbcl-agent::make-environment-compatibility-payload-from-session session)))
    (setf (sbcl-agent::environment-compatibility-session environment) payload)
    (let ((serializable (sbcl-agent::serializable-environment-copy environment))
          (copied-payload (sbcl-agent::environment-compatibility-session
                           (sbcl-agent::serializable-environment-copy environment))))
      (declare (ignore serializable))
      (assert-true (typep copied-payload 'sbcl-agent::environment-compatibility-payload)
                   "serializable-environment-copy should preserve an existing compatibility payload")
      (assert-equal (sbcl-agent::environment-compatibility-payload-session-id payload)
                    (sbcl-agent::environment-compatibility-payload-session-id copied-payload)
                    "serializable-environment-copy should preserve the compatibility payload session id"))))

(defun load-environment-normalizes-legacy-compatibility-session-test ()
  (let* ((path "/tmp/sbcl-agent-legacy-compatibility-session.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/legacy-compatibility-session/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/legacy-compatibility-session/"
                       :session session)))
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (let ((*print-circle* t)
            (*print-pretty* t))
        (write environment :stream stream)))
    (let* ((loaded (sbcl-agent::load-environment path))
           (loaded-compatibility (sbcl-agent::environment-compatibility-session loaded))
           (rehydrated (sbcl-agent::environment-session loaded)))
      (assert-true (typep loaded-compatibility 'sbcl-agent::environment-compatibility-payload)
                   "load-environment should normalize legacy embedded compatibility sessions down to payloads")
      (assert-equal (sbcl-agent::agent-session-id session)
                    (sbcl-agent::environment-compatibility-payload-session-id loaded-compatibility)
                    "load-environment should preserve the legacy compatibility session identity")
      (assert-equal (sbcl-agent::agent-session-id session)
                    (sbcl-agent::agent-session-id rehydrated)
                    "environment-session should still reconstruct the compatibility session after legacy normalization"))))

(defun environment-serializable-copy-trims-derived-indexes-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-trimmed-indexes/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-trimmed-indexes/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-work-item session "Trim derived indexes" :transaction-scope :test)
    (let ((artifact (sbcl-agent::create-environment-artifact
                     session
                     :validation
                     nil
                     :title "Derived index artifact"
                     :summary "Ensure derived indexes are reconstructed from domain state.")))
      (declare (ignore artifact))
      (let ((serializable (sbcl-agent::serializable-environment-copy environment)))
        (assert-equal nil
                      (sbcl-agent::environment-thread-set serializable)
                      "serializable environment copy should omit duplicated top-level thread-set")
        (assert-equal nil
                      (sbcl-agent::environment-artifact-index serializable)
                      "serializable environment copy should omit duplicated top-level artifact-index")
        (assert-equal nil
                      (sbcl-agent::environment-work-item-graph serializable)
                      "serializable environment copy should omit duplicated top-level work-item graph")
        (assert-equal nil
                      (sbcl-agent::environment-runtime-set serializable)
                      "serializable environment copy should omit duplicated top-level runtime set")))))

(defun load-environment-rehydrates-derived-indexes-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-derived-indexes.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-derived-indexes/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-derived-indexes/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-work-item session "Rehydrate derived indexes" :transaction-scope :test)
    (sbcl-agent::create-environment-artifact
     session
     :validation
     nil
     :title "Reloaded derived index artifact"
     :summary "Environment load should rebuild top-level indexes from domain state.")
    (sbcl-agent::save-environment environment path)
    (let ((loaded-environment (sbcl-agent::load-environment path)))
      (assert-true (plusp (length (sbcl-agent::environment-thread-set loaded-environment)))
                   "load-environment should rebuild the top-level thread set from conversation state")
      (assert-true (plusp (length (sbcl-agent::environment-artifact-index loaded-environment)))
                   "load-environment should rebuild the top-level artifact index from conversation state")
      (assert-true (plusp (length (sbcl-agent::environment-work-item-graph loaded-environment)))
                   "load-environment should rebuild the top-level work-item graph from workflow state")
      (assert-equal 1
                    (length (sbcl-agent::environment-runtime-set loaded-environment))
                    "load-environment should rebuild the top-level runtime set from runtime state"))))

(defun load-environment-rehydrates-session-events-and-transcript-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-session-events.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-session-events/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-session-events/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::append-transcript-entry session :user "rehydrate me")
    (sbcl-agent::append-session-event session
                                      :session-event-rehydration-test
                                      '(:status :ok)
                                      :family :runtime
                                      :entity-id "rehydrate-event-1")
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment)))
      (assert-equal 1
                    (length (sbcl-agent::agent-session-transcript loaded-session))
                    "load-environment should rebuild transcript entries from the environment event log")
      (assert-true (find :session-event-rehydration-test
                         (sbcl-agent::agent-session-events loaded-session)
                         :key #'sbcl-agent::event-kind)
                   "load-environment should rebuild session events from the environment event log")
      (assert-equal "rehydrate me"
                    (getf (first (sbcl-agent::agent-session-transcript loaded-session)) :content)
                    "rehydrated transcript entries should preserve content"))))

(defun load-environment-rehydrates-pending-actions-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-pending-actions.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-pending-actions/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-pending-actions/"
                       :session session))
         (action (sbcl-agent::make-assistant-action
                  :type :eval
                  :payload '(:code "(+ 1 2)" :language :lisp))))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::stage-pending-actions session (list action))
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment))
           (loaded-actions (sbcl-agent::agent-session-pending-actions loaded-session))
           (loaded-action (first loaded-actions)))
      (assert-equal 1
                    (length loaded-actions)
                    "load-environment should rebuild pending actions from environment-owned state")
      (assert-equal :eval
                    (sbcl-agent::assistant-action-type loaded-action)
                    "rehydrated pending actions should preserve action type")
      (assert-equal '(:code "(+ 1 2)" :language :lisp)
                    (sbcl-agent::assistant-action-payload loaded-action)
                    "rehydrated pending actions should preserve action payload"))))

(defun load-environment-rehydrates-incidents-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-incidents.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-incidents/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-incidents/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-incident session
                                 :runtime-condition
                                 "Environment-owned incident"
                                 "Incident should survive via environment agent state."
                                 :metadata '(:source :test))
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment))
           (loaded-incidents (sbcl-agent::agent-session-incidents loaded-session))
           (loaded-incident (first loaded-incidents))
           (summary (sbcl-agent::environment-summary loaded-environment)))
      (assert-equal 1
                    (length loaded-incidents)
                    "load-environment should rebuild incidents from environment-owned state")
      (assert-equal "Environment-owned incident"
                    (sbcl-agent::incident-title loaded-incident)
                    "rehydrated incidents should preserve title")
      (assert-equal 1
                    (getf summary :incident-count)
                    "environment-summary should derive incident count from environment-owned agent state"))))

(defun load-environment-rehydrates-tasks-and-workers-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-tasks-workers.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-tasks-workers/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-tasks-workers/"
                       :session session))
         (command (sbcl-agent::normalize-form-command '(ask "rehydrate worker task"))))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::enqueue-task session command :priority 3)
    (let ((worker (sbcl-agent::make-worker-state :id "worker-rehydrated"
                                                 :thread nil
                                                 :running-p nil
                                                 :session-id (sbcl-agent::agent-session-id session))))
      (setf (sbcl-agent::agent-session-workers session) (list worker)
            (sbcl-agent::agent-session-workers-tail session) (last (sbcl-agent::agent-session-workers session)))
      (sbcl-agent::refresh-environment-agent-domain environment session))
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment))
           (loaded-tasks (sbcl-agent::agent-session-tasks loaded-session))
           (loaded-workers (sbcl-agent::agent-session-workers loaded-session))
           (agent-summary (getf (sbcl-agent::environment-summary loaded-environment) :agent-state)))
      (assert-equal 1
                    (length loaded-tasks)
                    "load-environment should rebuild tasks from environment-owned agent state")
      (assert-equal :ask
                    (sbcl-agent::task-kind (first loaded-tasks))
                    "rehydrated tasks should preserve task kind")
      (assert-equal 1
                    (length loaded-workers)
                    "load-environment should rebuild workers from environment-owned agent state")
      (assert-equal "worker-rehydrated"
                    (sbcl-agent::worker-state-id (first loaded-workers))
                    "rehydrated workers should preserve worker identity")
      (assert-equal 1
                    (getf agent-summary :task-count)
                    "environment agent summary should report task count from environment-owned state")
      (assert-equal 1
                    (getf agent-summary :worker-count)
                    "environment agent summary should report worker count from environment-owned state"))))

(defun load-environment-rehydrates-capability-grants-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-capability-grants.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-capability-grants/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-capability-grants/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::approve-policy session :runtime-eval-mutate)
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment))
           (grants (sbcl-agent::agent-session-capability-grants loaded-session))
           (grant-summary (first (sbcl-agent::session-capability-grants-summary loaded-session))))
      (assert-equal 1
                    (length grants)
                    "load-environment should rebuild capability grants from environment policy-state")
      (assert-equal :runtime-eval-mutate
                    (sbcl-agent::capability-grant-policy-id (first grants))
                    "rehydrated capability grants should preserve policy identity")
      (assert-equal :runtime-eval-mutate
                    (getf grant-summary :policy-id)
                    "rehydrated capability grant summaries should preserve policy identity"))))

(defun load-environment-rehydrates-plan-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-plan.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-plan/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-plan/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::update-session-plan session "Environment-owned plan")
    (sbcl-agent::refresh-environment-agent-domain environment session)
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment))
           (summary (sbcl-agent::environment-summary loaded-environment)))
      (assert-equal "Environment-owned plan"
                    (sbcl-agent::agent-session-plan loaded-session)
                    "load-environment should rebuild the session plan from environment agent-state")
      (assert-equal "Environment-owned plan"
                    (getf summary :plan)
                    "environment-summary should expose the environment-owned plan"))))

(defun load-environment-derives-compatibility-header-from-environment-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-compatibility-header.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-compatibility-header/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-compatibility-header/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::approve-policy session :runtime-package-switch)
    (sbcl-agent::tool-runtime-set-package session :package "COMMON-LISP")
    (let ((thread (sbcl-agent::create-thread session :title "Header thread")))
      (sbcl-agent::use-thread session (sbcl-agent::thread-id thread)))
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment)))
      (assert-equal "/tmp/environment-compatibility-header/"
                    (sbcl-agent::agent-session-cwd loaded-session)
                    "load-environment should derive session cwd from the environment")
      (assert-equal "COMMON-LISP"
                    (sbcl-agent::agent-session-package loaded-session)
                    "load-environment should derive session package from the environment runtime state")
      (assert-equal (sbcl-agent::environment-active-thread-id loaded-environment)
                    (sbcl-agent::agent-session-current-thread-id loaded-session)
                    "load-environment should derive current thread identity from the environment"))))

(defun environment-workflow-rehydration-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-workflow-rehydration.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-workflow-rehydration/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-workflow-rehydration/"
                       :session session))
         (work-item (sbcl-agent::create-work-item session "Environment-native workflow rehydration"
                                                  :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment))
           (loaded-work-item (first (sbcl-agent::agent-session-work-items loaded-session)))
           (loaded-record (first (sbcl-agent::agent-session-workflow-records loaded-session))))
      (assert-equal 1
                    (length (sbcl-agent::agent-session-work-items loaded-session))
                    "environment load should rehydrate work-items from environment workflow state")
      (assert-equal 1
                    (length (sbcl-agent::agent-session-workflow-records loaded-session))
                    "environment load should rehydrate workflow records from environment workflow state")
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (sbcl-agent::work-item-id loaded-work-item)
                    "rehydrated environment work-items should preserve work-item identity")
      (assert-equal (sbcl-agent::work-item-workflow-record-ref loaded-work-item)
                    (sbcl-agent::workflow-record-id loaded-record)
                    "rehydrated environment workflow should preserve work-item to workflow-record linkage")
      (assert-true (> (length (sbcl-agent::work-item-checkpoints loaded-work-item)) 0)
                   "rehydrated environment work-items should preserve checkpoint state"))))

(defun environment-workflow-write-through-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-workflow-write-through/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-workflow-write-through/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((work-item (sbcl-agent::create-work-item session "Environment workflow write-through"
                                                    :transaction-scope :test))
           (workflow-state (sbcl-agent::environment-workflow-state environment))
           (environment-work-item (find (sbcl-agent::work-item-id work-item)
                                        (sbcl-agent::environment-workflow-state-work-items workflow-state)
                                        :key #'sbcl-agent::work-item-id
                                        :test #'string=))
           (environment-record (find (sbcl-agent::work-item-workflow-record-ref work-item)
                                     (sbcl-agent::environment-workflow-state-workflow-records workflow-state)
                                     :key #'sbcl-agent::workflow-record-id
                                     :test #'string=)))
      (assert-true environment-work-item
                   "bound environment should receive new work-items through explicit workflow write-through")
      (assert-true environment-record
                   "bound environment should receive new workflow records through explicit workflow write-through")
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (sbcl-agent::work-item-id environment-work-item)
                    "environment workflow write-through should preserve work-item identity")
      (assert-equal (sbcl-agent::work-item-workflow-record-ref work-item)
                    (sbcl-agent::workflow-record-id environment-record)
                    "environment workflow write-through should preserve workflow linkage"))))

(defun environment-workflow-event-write-through-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-workflow-event-write-through/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-workflow-event-write-through/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((initial-event-count (length (sbcl-agent::environment-event-log environment)))
           (work-item (sbcl-agent::create-work-item session "Environment workflow event write-through"
                                                    :transaction-scope :test))
           (events (sbcl-agent::environment-event-log environment))
           (work-item-event (find (sbcl-agent::work-item-id work-item)
                                  events
                                  :key #'sbcl-agent::event-entity-id
                                  :test #'string=))
           (workflow-event (find (sbcl-agent::work-item-workflow-record-ref work-item)
                                 events
                                 :key #'sbcl-agent::event-entity-id
                                 :test #'string=)))
      (assert-true (> (length events) initial-event-count)
                   "bound environment should append workflow events immediately when workflow state changes")
      (assert-true work-item-event
                   "bound environment should project work-item-created into the environment event log")
      (assert-true workflow-event
                   "bound environment should project workflow-record-created into the environment event log")
      (assert-equal :workflow
                    (sbcl-agent::event-family work-item-event)
                    "work-item-created environment event should use workflow family")
      (assert-equal :workflow-record-created
                    (sbcl-agent::event-kind workflow-event)
                    "workflow record creation should be visible as a distinct environment event")
      (assert-equal (sbcl-agent::environment-id environment)
                    (getf (sbcl-agent::event-metadata work-item-event) :environment-id)
                    "workflow events should carry active environment metadata"))))

(defun environment-event-envelope-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-events/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-events/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::append-session-event session
                                      :test-event
                                      '(:payload :ok)
                                      :family :runtime
                                      :entity-id "entity-1"
                                      :thread-id (sbcl-agent::agent-session-current-thread-id session)
                                      :metadata '(:note "project me"))
    (sbcl-agent::sync-environment-from-session environment session)
    (let ((event (car (last (sbcl-agent::environment-event-log environment))))
          (source-event (car (last (sbcl-agent::agent-session-events session)))))
      (assert-true event
                   "sync-environment-from-session should project events into the environment log")
      (assert-equal :test-event
                    (sbcl-agent::event-kind event)
                    "projected environment event should preserve the event kind")
      (assert-equal (sbcl-agent::agent-session-id session)
                    (getf (sbcl-agent::event-metadata source-event) :session-id)
                    "session-originated events should include session-id correlation metadata")
      (assert-equal (sbcl-agent::environment-id environment)
                    (getf (sbcl-agent::event-metadata source-event) :environment-id)
                    "session-originated events should include environment-id correlation metadata when bound")
      (assert-equal :runtime
                    (sbcl-agent::event-family event)
                    "projected environment event should preserve event family")
      (assert-equal (sbcl-agent::environment-id environment)
                    (getf (sbcl-agent::event-metadata event) :environment-id)
                    "projected environment event should include its environment id")
      (assert-equal (sbcl-agent::event-id source-event)
                    (getf (sbcl-agent::event-metadata event) :source-event-id)
                    "projected environment event should retain the source event id")
      (assert-equal (sbcl-agent::environment-id environment)
                    (getf (sbcl-agent::event-payload event) :environment-id)
                    "projected environment event payload should include the environment id")
      (assert-equal '(:payload :ok)
                    (getf (sbcl-agent::event-payload event) :event-summary)
                    "projected non-transcript environment events should store compact payload summaries"))))

(defun environment-transcript-event-preserves-full-payload-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-transcript-events/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-transcript-events/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::append-transcript-entry session :user "preserve transcript payload")
    (let ((event (car (last (sbcl-agent::environment-event-log environment)))))
      (assert-equal :transcript
                    (sbcl-agent::event-kind event)
                    "transcript append should project a transcript environment event")
      (assert-equal "preserve transcript payload"
                    (getf (getf (sbcl-agent::event-payload event) :event) :content)
                    "projected transcript environment events should preserve full payload for reload reconstruction"))))

(defun incident-environment-event-projection-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (environment (sbcl-agent::make-default-environment
                       :storage-root (current-workspace-root)
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-command
        (sbcl-agent::normalize-form-command '(runtime/eval "(error \"environment incident projection\")"))
        provider
        session))
     "environment incident projection"
     "test setup should create a runtime incident")
    (let ((incident-event (find :incident-created
                                (sbcl-agent::environment-event-log environment)
                                :key #'sbcl-agent::event-kind)))
      (assert-true incident-event
                   "environment event log should include projected incident-created events")
      (assert-equal :incident
                    (sbcl-agent::event-family incident-event)
                    "projected incident event should keep incident family")
      (assert-true (getf (sbcl-agent::event-metadata incident-event) :incident-id)
                   "projected incident event should retain incident correlation metadata")
      (assert-equal (sbcl-agent::environment-id environment)
                    (getf (sbcl-agent::event-metadata incident-event) :environment-id)
                    "projected incident event should include the active environment id"))))

(defun environment-domain-summary-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-domains/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-domains/"
                       :session session))
         (summary (sbcl-agent::environment-summary environment)))
    (assert-true (listp (getf summary :runtime-state))
                 "environment summary should expose runtime-state summary data")
    (assert-true (listp (getf summary :conversation-state))
                 "environment summary should expose conversation-state summary data")
    (assert-true (listp (getf summary :workflow-state))
                 "environment summary should expose workflow-state summary data")
    (assert-true (listp (getf summary :agent-state))
                 "environment summary should expose agent-state summary data")
    (assert-equal 1
                  (getf (getf summary :runtime-state) :runtime-count)
                  "runtime-state summary should report one primary runtime")
    (assert-equal (length (sbcl-agent::agent-session-threads session))
                  (getf (getf summary :conversation-state) :thread-count)
                  "conversation-state summary should mirror thread count")
    (assert-equal (length (sbcl-agent::agent-session-work-items session))
                  (getf (getf summary :workflow-state) :work-item-count)
                  "workflow-state summary should mirror work-item count")
    (assert-equal 0
                  (getf (getf summary :agent-state) :agent-count)
                  "agent-state summary should start empty")))

(defun environment-runtime-domain-summary-helper-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-runtime-domain-helper/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-runtime-domain-helper/"
                       :session session))
         (runtime-summary (sbcl-agent::environment-runtime-domain-summary environment)))
    (assert-true (listp runtime-summary)
                 "environment runtime domain helper should return a runtime summary plist")
    (assert-equal "SBCL-AGENT-USER"
                  (getf runtime-summary :package)
                  "environment runtime domain helper should expose the active package")
    (assert-equal 1
                  (getf runtime-summary :runtime-count)
                  "environment runtime domain helper should report one active runtime")))

(defun environment-conversation-domain-summary-helper-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-conversation-domain-helper/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-conversation-domain-helper/"
                       :session session)))
    (sbcl-agent::create-thread session :title "Conversation domain helper")
    (sbcl-agent::sync-environment-from-session environment session)
    (let ((conversation-summary (sbcl-agent::environment-conversation-domain-summary environment)))
      (assert-true (listp conversation-summary)
                   "environment conversation domain helper should return a conversation summary plist")
      (assert-equal 2
                    (getf conversation-summary :thread-count)
                    "environment conversation domain helper should reflect synchronized thread count")
      (assert-equal (sbcl-agent::agent-session-current-thread-id session)
                    (getf conversation-summary :active-thread-id)
                    "environment conversation domain helper should expose the active thread id"))))

(defun environment-workflow-domain-summary-helper-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-workflow-domain-helper/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-workflow-domain-helper/"
                       :session session)))
    (sbcl-agent::create-work-item session "Workflow domain helper" :transaction-scope :test)
    (sbcl-agent::sync-environment-from-session environment session)
    (let ((workflow-summary (sbcl-agent::environment-workflow-domain-summary environment)))
      (assert-true (listp workflow-summary)
                   "environment workflow domain helper should return a workflow summary plist")
      (assert-equal 1
                    (getf workflow-summary :work-item-count)
                    "environment workflow domain helper should reflect synchronized work-item count")
      (assert-equal 1
                    (getf workflow-summary :workflow-record-count)
                    "environment workflow domain helper should reflect synchronized workflow-record count"))))

(defun environment-artifact-domain-helper-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-artifact-domain-helper/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-artifact-domain-helper/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-environment-artifact
     session
     :validation
     nil
     :title "Artifact domain helper"
     :summary "Environment artifact helper should expose environment-native artifact evidence.")
    (let ((artifact-summary (sbcl-agent::environment-artifact-summary environment)))
      (assert-true (listp artifact-summary)
                   "environment artifact helper should return an artifact summary plist")
      (assert-true (> (sbcl-agent::environment-artifact-count environment) 0)
                   "environment artifact helper should count synchronized artifacts")
      (assert-true (> (getf artifact-summary :validation-count) 0)
                   "environment artifact helper should expose validation evidence from the environment artifact index"))))

(defun environment-summary-prefers-domain-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-domain-preference/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-domain-preference/"
                       :session session)))
    (sbcl-agent::create-work-item session "Environment-owned workflow state" :transaction-scope :test)
    (sbcl-agent::sync-environment-from-session environment session)
    (setf (sbcl-agent::environment-compatibility-session environment) nil)
    (let ((summary (sbcl-agent::environment-summary environment)))
      (assert-equal 1
                    (getf summary :thread-count)
                    "environment-summary should still report thread count from environment-owned conversation state")
      (assert-equal 1
                    (getf summary :work-item-count)
                    "environment-summary should still report work-item count from environment-owned workflow state")
      (assert-equal nil
                    (getf summary :session-id)
                    "environment-summary should tolerate a detached compatibility session"))))

(defun environment-summary-does-not-resync-on-read-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-summary-no-read-resync/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-summary-no-read-resync/"
                       :session session)))
    (setf (sbcl-agent::agent-session-package session) "COMMON-LISP")
    (let ((summary (sbcl-agent::environment-summary environment)))
      (assert-equal "SBCL-AGENT-USER"
                    (getf (getf summary :runtime-state) :package)
                    "environment-summary should report persisted environment runtime state, not silently resync from the compatibility session"))))

(defun environment-summary-alignment-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-summary-alignment/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-summary-alignment/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-intent-record
     session
     :description "Keep the active environment continuously aligned."
     :scope '(:symbols ("SBCL-AGENT::RUN-CONVERSATION-TURN"))
     :constraints '((:invariant "runtime-is-authoritative"))
     :expected-behaviors '("Observe runtime changes"))
    (let* ((summary (sbcl-agent::environment-summary environment))
           (alignment-state (getf summary :alignment-state))
           (reconciliation-decision (getf summary :reconciliation-decision))
           (status (sbcl-agent::environment-status environment)))
      (assert-true (listp alignment-state)
                   "environment-summary should expose an alignment-state payload")
      (assert-true (listp reconciliation-decision)
                   "environment-summary should expose a reconciliation-decision payload")
      (assert-true (numberp (getf alignment-state :score))
                   "environment-summary should expose an alignment score")
      (assert-true (listp (getf (sbcl-agent::environment-operator-evidence summary) :alignment))
                   "environment operator evidence should surface alignment posture")
      (assert-true (listp (getf (sbcl-agent::environment-operator-evidence summary) :reconciliation))
                   "environment operator evidence should surface reconciliation posture")
      (assert-true (listp (getf status :alignment-state))
                   "environment-status should expose alignment-state directly")
      (assert-true (listp (getf status :reconciliation-decision))
                   "environment-status should expose reconciliation-decision directly"))))

(defun environment-first-binding-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-first-binding/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-first-binding/"
                       :session session)))
    (setf sbcl-agent::*current-environment* environment
          sbcl-agent::*current-session* nil)
    (let ((resolved-session (sbcl-agent::ensure-session)))
      (assert-equal (sbcl-agent::agent-session-id session)
                    (sbcl-agent::agent-session-id resolved-session)
                    "ensure-session should resolve through the current environment when session is absent")
      (assert-equal (sbcl-agent::environment-id environment)
                    (getf (sbcl-agent::environment-summary environment) :id)
                    "environment-first session resolution should keep the current environment bound"))))

(defun environment-runtime-history-persistence-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-runtime-history.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-runtime-history/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-runtime-history/"
                       :session session)))
    (declare (ignore environment))
    (sbcl-agent::approve-policy session :runtime-package-switch)
    (sbcl-agent::approve-policy session :runtime-eval-mutate)
    (sbcl-agent::tool-runtime-set-package session :package "COMMON-LISP")
    (sbcl-agent::tool-runtime-eval session :form "(+ 20 22)")
    (sbcl-agent::tool-runtime-eval session
                                   :form "(progn (defparameter sbcl-agent-user::*runtime-history-flag* nil) (setf sbcl-agent-user::*runtime-history-flag* :ok) sbcl-agent-user::*runtime-history-flag*)"
                                   :mutating t)
    (sbcl-agent::save-environment (sbcl-agent::ensure-environment) path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (runtime-state (sbcl-agent::environment-runtime-state loaded-environment))
           (history (sbcl-agent::environment-runtime-state-eval-history runtime-state)))
      (assert-true (>= (length history) 3)
                   "load-environment should preserve runtime history entries")
      (assert-equal :package-switch
                    (getf (first history) :kind)
                    "load-environment should preserve the package switch history entry")
      (assert-equal 3
                    (length (sbcl-agent::environment-artifact-index loaded-environment))
                    "load-environment should preserve runtime artifacts created by structured operations"))))

(defun environment-desktop-preferences-persistence-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-desktop-preferences.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-desktop-preferences/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-desktop-preferences/"
                       :session session))
         (preferences
           '(:theme-preference "dark"
             :desktop-surface-view
             (:tooltip-scale-percent 112
              :conversation-text-scale-percent 155)
             :conversation-draft "persistence-check conversation draft"
             :selected-conversation-thread-by-project
             (:project-alpha "thread-1")
             :workspace-package-by-project
             (:project-alpha "SBCL-AGENT-USER")
             :workspace-draft-by-project
             (:project-alpha "(defparameter *persistence-check* t)")
             :workspace-result-by-project
             (:project-alpha (:data (:summary "workspace result")))
             :workspace-history-by-project
             (:project-alpha ((:input "(+ 1 2)" :output "3")))
             :selected-editor-buffer-id-by-project
             (:project-alpha "buffer-main")
             :editor-buffers-by-project
             (:project-alpha
              ((:buffer-id "buffer-main"
                :title "Main"
                :package-name "SBCL-AGENT-USER"
                :draft-form "(print :persistence-check)"
                :baseline-draft "(print :baseline)"
                :last-summary "ready"
                :runtime-summary (:runtime-id "runtime-1")))))))
    (sbcl-agent::command-environment-set-desktop-preferences-service preferences environment)
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (restored (sbcl-agent::environment-desktop-preferences loaded-environment))
           (desktop-surface-view (getf restored :desktop-surface-view))
           (selected-editor-buffer-ids (getf restored :selected-editor-buffer-id-by-project))
           (workspace-drafts (getf restored :workspace-draft-by-project))
           (editor-buffers (getf restored :editor-buffers-by-project))
           (project-buffers (getf editor-buffers :project-alpha))
           (main-buffer (first project-buffers)))
      (assert-equal "dark"
                    (getf restored :theme-preference)
                    "desktop preferences should preserve the persisted theme preference")
      (assert-equal 155
                    (getf desktop-surface-view :conversation-text-scale-percent)
                    "desktop preferences should preserve nested desktop surface settings")
      (assert-equal "persistence-check conversation draft"
                    (getf restored :conversation-draft)
                    "desktop preferences should preserve the conversation draft")
      (assert-equal "(defparameter *persistence-check* t)"
                    (getf workspace-drafts :project-alpha)
                    "desktop preferences should preserve workspace drafts by project")
      (assert-equal "buffer-main"
                    (getf selected-editor-buffer-ids :project-alpha)
                    "desktop preferences should preserve selected editor buffer ids by project")
      (assert-equal "(print :persistence-check)"
                    (getf main-buffer :draft-form)
                    "desktop preferences should preserve editor buffer drafts")
      (assert-equal "runtime-1"
                    (getf (getf main-buffer :runtime-summary) :runtime-id)
                    "desktop preferences should preserve nested editor buffer runtime summaries"))))

(defun environment-desktop-preferences-legacy-key-normalization-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-desktop-preferences-legacy/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-desktop-preferences-legacy/"
                       :session session)))
    (sbcl-agent::set-environment-metadata-value
     environment
     sbcl-agent::+environment-desktop-preferences-key+
     '(:THEMEPREFERENCE "dark"
       :THEME-PREFERENCE "system"
       :DESKTOPSURFACEVIEW
       (:CONVERSATIONTEXTSCALEPERCENT 150
        :TOOLTIPSCALEPERCENT 110)
       :DESKTOP-SURFACE-VIEW
       (:CONVERSATION-TEXT-SCALE-PERCENT 160
        :TOOLTIP-SCALE-PERCENT 115)
       :CONVERSATIONDRAFT "legacy draft"
       :CONVERSATION-DRAFT "canonical draft"
       :WORKSPACEDRAFTBYPROJECT
       (:PROJECT-ALPHA "(+ 40 2)")
       :WORKSPACE-DRAFT-BY-PROJECT
       (:PROJECT-ALPHA "(+ 99 1)")
       :EDITORBUFFERSBYPROJECT
       (:PROJECT-ALPHA
        ((:BUFFERID "buffer-main"
          :DRAFTFORM "(print :legacy)"
          :BASELINEDRAFT "(print :baseline)"
          :RUNTIMESUMMARY (:RUNTIMEID "runtime-legacy"))))
       :EDITOR-BUFFERS-BY-PROJECT
       (:PROJECT-ALPHA
        ((:BUFFER-ID "buffer-main"
          :DRAFT-FORM "(print :canonical)"
          :BASELINE-DRAFT "(print :baseline)"
          :RUNTIME-SUMMARY (:RUNTIME-ID "runtime-canonical"))))))
    (let* ((restored (sbcl-agent::environment-desktop-preferences environment))
           (desktop-surface-view (getf restored :desktop-surface-view))
           (editor-buffers (getf restored :editor-buffers-by-project))
           (main-buffer (first (getf editor-buffers :project-alpha))))
      (assert-equal "system"
                    (getf restored :theme-preference)
                    "desktop preferences should collapse legacy and canonical flat theme keys to one canonical value")
      (assert-equal 160
                    (getf desktop-surface-view :conversation-text-scale-percent)
                    "desktop preferences should collapse legacy and canonical nested desktop surface keys to one canonical value")
      (assert-equal "canonical draft"
                    (getf restored :conversation-draft)
                    "desktop preferences should collapse legacy and canonical conversation draft keys to one canonical value")
      (assert-equal "(+ 99 1)"
                    (getf (getf restored :workspace-draft-by-project) :project-alpha)
                    "desktop preferences should collapse legacy and canonical workspace draft keys to one canonical value")
      (assert-equal "(print :canonical)"
                    (getf main-buffer :draft-form)
                    "desktop preferences should collapse legacy and canonical editor buffer keys to one canonical value")
      (assert-equal "runtime-canonical"
                    (getf (getf main-buffer :runtime-summary) :runtime-id)
                    "desktop preferences should collapse legacy and canonical nested runtime summary keys to one canonical value"))))

(defun trace-link-persistence-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-trace-links-XXXXXX"))
         (root-path (namestring root))
         (path (merge-pathnames #P"environment.sexp" root))
         (session (sbcl-agent::make-default-session :cwd root-path))
         (environment (sbcl-agent::make-default-environment
                       :storage-root root-path
                       :session session))
         (project (sbcl-agent::create-project-record session
                                                     :title "Traceability Project"
                                                     :summary "Trace persistence regression."))
         (project-id (sbcl-agent::project-record-id project))
         (work-item (sbcl-agent::create-work-item session
                                                  "Implement a traceability regression"
                                                  :mutation-intent '(:thread-id "thread-1")))
         (incident nil))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::command-project-requirement-service session
                                                     :project-id project-id
                                                     :id "req-1"
                                                     :title "Traceability requirement"
                                                     :summary "Requirement should remain traceable.")
    (sbcl-agent::command-project-user-journey-service session
                                                      :project-id project-id
                                                      :id "journey-1"
                                                      :title "End-to-end SDLC journey"
                                                      :summary "Traceable path."
                                                      :steps '("Define" "Implement" "Validate"))
    (sbcl-agent::command-project-feature-spec-service session
                                                      :project-id project-id
                                                      :id "spec-1"
                                                      :title "Traceability feature"
                                                      :summary "Link requirements to execution."
                                                      :linked-requirement-ids '("req-1")
                                                      :linked-journey-ids '("journey-1"))
    (sbcl-agent::command-project-architecture-decision-service session
                                                               :project-id project-id
                                                               :id "adr-1"
                                                               :title "Persist trace links"
                                                               :summary "Persist trace links in the image."
                                                               :linked-requirement-ids '("req-1"))
    (sbcl-agent::command-project-bind-work-item-service session
                                                        (sbcl-agent::work-item-id work-item)
                                                        :project-id project-id)
    (setf incident (sbcl-agent::create-incident session
                                                :runtime-condition
                                                "Traceability regression incident"
                                                "Traceability incident summary."
                                                :work-item work-item))
    (sbcl-agent::command-project-bind-incident-service session
                                                       (sbcl-agent::incident-id incident)
                                                       :project-id project-id)
    (sbcl-agent::command-project-bind-testing-harness-service session :full-suite :project-id project-id)
    (sbcl-agent::command-project-source-root-service session "/tmp/traceability/" :project-id project-id)
    (sbcl-agent::save-environment (sbcl-agent::ensure-environment) path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment))
           (project-neighborhood (sbcl-agent::trace-neighborhood-summary loaded-session :project project-id))
           (work-item-neighborhood (sbcl-agent::trace-neighborhood-summary loaded-session
                                                                           :work-item
                                                                           (sbcl-agent::work-item-id work-item)))
           (incident-neighborhood (sbcl-agent::trace-neighborhood-summary loaded-session
                                                                           :incident
                                                                           (sbcl-agent::incident-id incident)))
           (trace-links (sbcl-agent::list-trace-links loaded-session)))
      (assert-true (>= (length trace-links) 8)
                   "save-environment/load-environment should preserve generated trace links")
      (assert-true (>= (getf project-neighborhood :count) 6)
                   "trace neighborhoods should preserve project-centered SDLC linkages")
      (assert-true (> (getf work-item-neighborhood :count) 0)
                   "trace neighborhoods should preserve work-item linkage")
      (assert-true (> (getf incident-neighborhood :count) 0)
                   "trace neighborhoods should preserve incident linkage"))))

(defun environment-image-registry-persistence-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-environment-images-XXXXXX"))
         (root-path (namestring root))
         (session (sbcl-agent::make-default-session :cwd root-path))
         (environment (sbcl-agent::make-default-environment
                       :storage-root root-path
                       :session session)))
    (sbcl-agent::set-environment-desktop-preferences
     environment
     '(:conversation-draft "image persistence draft"))
    (let* ((record (sbcl-agent::save-environment-as-image "alpha" :environment environment))
           (registry (sbcl-agent::load-environment-image-registry environment))
           (loaded-environment (sbcl-agent::load-environment-image "alpha" environment))
           (loaded-preferences (sbcl-agent::environment-desktop-preferences loaded-environment)))
      (assert-true (probe-file (sbcl-agent::environment-image-registry-path environment))
                   "saving an environment image should create an image registry file")
      (assert-true (probe-file (sbcl-agent::environment-image-record-path record))
                   "saving an environment image should persist the named image snapshot")
      (assert-equal (sbcl-agent::environment-image-record-id record)
                    (getf registry :current-image-id)
                    "saving an environment image should advance the registry current image id")
      (assert-equal "alpha"
                    (sbcl-agent::environment-image-name loaded-environment)
                    "loading an environment image should restore the saved image name")
      (assert-equal "image persistence draft"
                    (getf loaded-preferences :conversation-draft)
                    "loading an environment image should restore persisted desktop shell state")
      (assert-true (typep (sbcl-agent::environment-checkpoint-policy-record loaded-environment)
                          'sbcl-agent::environment-checkpoint-policy)
                   "loading an environment image should retain checkpoint policy metadata")
      (assert-true (typep (sbcl-agent::environment-runtime-manifest-record loaded-environment)
                          'sbcl-agent::environment-runtime-manifest)
                   "loading an environment image should retain runtime manifest metadata")
      (assert-true (typep (sbcl-agent::environment-recovery-manifest-record loaded-environment)
                          'sbcl-agent::environment-recovery-manifest)
                   "loading an environment image should retain recovery manifest metadata"))))

(defun environment-image-revert-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-environment-revert-XXXXXX"))
         (root-path (namestring root))
         (session (sbcl-agent::make-default-session :cwd root-path))
         (environment (sbcl-agent::make-default-environment
                       :storage-root root-path
                       :session session)))
    (sbcl-agent::set-environment-desktop-preferences
     environment
     '(:conversation-draft "saved image draft"))
    (sbcl-agent::save-environment-as-image "beta" :environment environment)
    (sbcl-agent::set-environment-desktop-preferences
     environment
     '(:conversation-draft "mutated transient draft"))
    (let* ((reverted-environment (sbcl-agent::revert-environment-to-current-image environment))
           (reverted-preferences (sbcl-agent::environment-desktop-preferences reverted-environment)))
      (assert-equal "saved image draft"
                    (getf reverted-preferences :conversation-draft)
                    "reverting to the current image should discard transient shell-state mutations")
      (assert-equal "beta"
                    (sbcl-agent::environment-image-name reverted-environment)
                    "reverting to the current image should preserve the bound image identity"))))

(defun environment-image-load-assesses-recovery-test ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-environment-recovery-XXXXXX"))
         (root-path (namestring root))
         (session (sbcl-agent::make-default-session :cwd root-path))
         (environment (sbcl-agent::make-default-environment
                       :storage-root root-path
                       :session session)))
    (sbcl-agent::set-environment-metadata-value
     environment
     :compatibility-apps
     '((:app-id "linux.vscode")))
    (sbcl-agent::save-environment-as-image "recoverable" :environment environment)
    (let* ((loaded-environment (sbcl-agent::load-environment-image "recoverable" environment))
           (summary (sbcl-agent::environment-summary loaded-environment))
           (recovery-summary (getf summary :recovery-summary)))
      (assert-equal :degraded
                    (getf recovery-summary :status)
                    "loading an environment image should mark recovery degraded when runtime obligations remain pending")
      (assert-true (getf recovery-summary :manual-recovery-required-p)
                   "loading an environment image should report when manual recovery is still required")
      (assert-equal 1
                    (getf recovery-summary :compatibility-app-restart-count)
                    "loading an environment image should report compatibility app restart obligations")
      (assert-equal :pending-manual-recovery
                    (getf (first (getf recovery-summary :runtime-replay)) :outcome)
                    "loading an environment image should persist explicit runtime replay outcomes")
      (assert-equal :degraded
                    (sbcl-agent::environment-recovery-manifest-last-recovery-status
                     (sbcl-agent::environment-recovery-manifest-record loaded-environment))
                    "loading an environment image should stamp the recovery manifest with the assessed recovery state")
      (assert-true (integerp
                    (sbcl-agent::environment-recovery-manifest-last-recovery-at
                     (sbcl-agent::environment-recovery-manifest-record loaded-environment)))
                   "loading an environment image should stamp the recovery manifest with a recovery assessment time"))))

(defun load-environment-does-not-resync-on-read-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-no-read-resync.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-load-no-read-resync/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-load-no-read-resync/"
                       :session session)))
    (sbcl-agent::save-environment environment path)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (loaded-session (sbcl-agent::environment-session loaded-environment)))
      (setf (sbcl-agent::agent-session-package loaded-session) "COMMON-LISP")
      (let ((summary (sbcl-agent::environment-summary loaded-environment)))
        (assert-equal "SBCL-AGENT-USER"
                      (getf (getf summary :runtime-state) :package)
                      "load-environment should keep the persisted environment summary stable until an explicit sync occurs")))))

(defun environment-status-uses-environment-owned-state-test ()
  (let* ((path #P"/tmp/sbcl-agent-environment-status-owned-state.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-status-owned-state/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-status-owned-state/"
                       :session session)))
    (let* ((thread (sbcl-agent::create-thread session :title "Owned state thread"))
           (user-message (sbcl-agent::create-message session thread :user "owned state"))
           (turn (sbcl-agent::start-turn session thread user-message))
           (assistant-message (sbcl-agent::create-message session thread :assistant "done")))
      (sbcl-agent::complete-turn session thread turn assistant-message :status :completed))
    (sbcl-agent::save-environment environment path)
    (setf sbcl-agent::*current-session* nil
          sbcl-agent::*current-environment* nil)
    (let* ((loaded-environment (sbcl-agent::load-environment path))
           (status (sbcl-agent::environment-status loaded-environment)))
      (assert-equal nil
                    sbcl-agent::*current-session*
                    "environment-status should not need to materialize a compatibility session to orient the operator")
      (assert-equal (sbcl-agent::environment-active-thread-id loaded-environment)
                    (getf (getf status :active-thread) :id)
                    "environment-status should derive the active thread from environment-owned conversation state")
      (assert-true (stringp (getf (getf status :active-turn) :id))
                   "environment-status should derive the active turn from environment-owned turn summaries"))))



(defun session-tail-rebuild-after-load-test ()
  (let* ((provider (make-test-provider))
         (path (format nil "/tmp/sbcl-agent-tail-rebuild-~D-~D.sexp"
                       (get-universal-time)
                       (random 1000000)))
         (session (sbcl-agent::make-default-session)))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "first tail rebuild prompt"))
     provider
     session)
    (sbcl-agent::save-session session path)
    (let ((loaded (sbcl-agent::load-session path)))
      (sbcl-agent::execute-command
       (sbcl-agent::normalize-form-command '(say "second tail rebuild prompt"))
       provider
       loaded)
      (let* ((thread (sbcl-agent::current-thread loaded))
             (messages (sbcl-agent::list-thread-messages loaded (sbcl-agent::thread-id thread)))
             (turns (sbcl-agent::list-thread-turns loaded (sbcl-agent::thread-id thread))))
        (assert-equal 4
                      (length messages)
                      "loaded sessions should accept appended messages after tail rebuild")
        (assert-equal 2
                      (length turns)
                      "loaded sessions should accept appended turns after tail rebuild")
        (assert-equal "first tail rebuild prompt"
                      (sbcl-agent::message-content (first messages))
                      "message order should be preserved after load and append")
        (assert-equal "second tail rebuild prompt"
                      (sbcl-agent::message-content (third messages))
                      "newly appended messages should stay at the end of the thread history")))))

(defun thread-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session)))
    (multiple-value-bind (list-result list-kind list-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(thread/list))
         provider
         session)
      (declare (ignore list-session))
      (assert-equal :thread-list list-kind "thread/list should dispatch correctly")
      (assert-true (>= (length list-result) 1)
                   "thread/list should synthesize a default thread"))
    (multiple-value-bind (new-result new-kind new-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(thread/new :title "Feature work"))
         provider
         session)
      (assert-equal :thread-new new-kind "thread/new should dispatch correctly")
      (assert-equal "Feature work"
                    (getf new-result :title)
                    "thread/new should use the requested title")
      (assert-equal (getf new-result :id)
                    (sbcl-agent::agent-session-current-thread-id new-session)
                    "thread/new should select the created thread"))
    (let* ((target (sbcl-agent::create-thread session :title "Switch target"))
           (target-id (sbcl-agent::thread-id target)))
      (multiple-value-bind (use-result use-kind used-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(thread/use ,target-id))
           provider
           session)
        (assert-equal :thread-use use-kind "thread/use should dispatch correctly")
        (assert-equal target-id
                      (getf use-result :id)
                      "thread/use should return the selected thread summary")
        (assert-equal target-id
                      (sbcl-agent::agent-session-current-thread-id used-session)
                      "thread/use should update the active thread id")))))

(defun thread-show-and-turn-status-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session)))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "inspect thread state"))
     provider
     session)
    (multiple-value-bind (thread-result thread-kind thread-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(thread/show))
         provider
         session)
      (declare (ignore thread-session))
      (assert-equal :thread-show thread-kind "thread/show should dispatch correctly")
      (assert-equal 2 (length (getf thread-result :messages))
                    "thread/show should expose persisted thread messages")
      (assert-equal 1 (length (getf thread-result :turns))
                    "thread/show should expose persisted thread turns")
      (assert-equal 0
                    (getf (getf thread-result :detail-summary) :runtime-artifact-count)
                    "thread/show should summarize runtime artifact counts"))
    (multiple-value-bind (turn-result turn-kind turn-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/status))
         provider
         session)
      (declare (ignore turn-session))
      (assert-equal :turn-status turn-kind "turn/status should dispatch correctly")
      (assert-equal :completed (getf turn-result :status)
                    "turn/status should expose the persisted turn status")
      (assert-equal :user (getf (getf turn-result :user-message) :role)
                    "turn/status should expose the user message")
      (assert-equal :assistant (getf (getf turn-result :assistant-message) :role)
                    "turn/status should expose the assistant message")
      (assert-equal 1 (length (getf turn-result :operations))
                    "turn/status should expose persisted operations")
      (assert-equal :completed (getf (first (getf turn-result :operations)) :status)
                    "turn/status should expose completed operation status")
      (assert-equal :safe-read
                    (getf (getf (first (getf turn-result :operations)) :policy-decision) :policy-id)
                    "turn/status should expose operation policy decisions")
      (assert-equal 0
                    (getf (getf turn-result :detail-summary) :runtime-operation-count)
                    "turn/status should summarize runtime operation counts")
      (assert-true (not (getf (getf turn-result :awaiting-approval) :awaiting-approval-p))
                   "completed turn/status should report no approval wait")
      (assert-equal 0
                    (getf (getf turn-result :awaiting-approval) :blocked-operation-count)
                    "completed turn/status should report zero blocked operations")
      (assert-true (member :primary-execution-handle turn-result)
                   "turn/status should advertise the primary execution-handle field")
      (assert-equal "conversation"
                    (getf (getf turn-result :execution-surface) :surface-kind)
                    "turn/status should expose the turn execution surface")
      (assert-true (consp (getf turn-result :execution-handles))
                   "turn/status should expose execution handles for persisted turn executions"))))

(defun turn-status-approval-summary-test ()
  (let* ((provider (make-instance 'patch-action-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare patch"))
     provider
     session)
    (multiple-value-bind (turn-result turn-kind turn-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/status))
         provider
         session)
      (declare (ignore turn-session))
      (assert-equal :turn-status turn-kind "turn/status should dispatch correctly for approval case")
      (assert-equal :awaiting-approval (getf turn-result :status)
                    "turn/status should surface awaiting-approval turn state")
      (assert-true (getf (getf turn-result :awaiting-approval) :awaiting-approval-p)
                   "turn/status should expose approval wait summary")
      (assert-equal 1
                    (getf (getf turn-result :awaiting-approval) :blocked-operation-count)
                    "turn/status should report one blocked operation")
      (assert-equal :workspace-write
                    (getf (first (getf (getf turn-result :awaiting-approval) :blocked-operations)) :policy-id)
                    "turn/status should report the waiting policy id")
      (assert-true (getf (getf turn-result :recovery) :resumable-p)
                   "turn/status should report approval-gated turns as resumable")
      (assert-equal 1
                    (getf (getf turn-result :recovery) :resumable-operation-count)
                    "turn/status should report one resumable blocked operation")
      (assert-equal "conversation"
                    (getf (getf turn-result :execution-surface) :surface-kind)
                    "approval-gated turn/status should expose the turn execution surface")
      (assert-true (consp (getf turn-result :execution-handles))
                   "approval-gated turn/status should preserve execution-handle listings"))))

(defun turn-resume-approval-flow-test ()
  (let* ((provider (make-instance 'patch-action-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare patch"))
     provider
     session)
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-command
        (sbcl-agent::normalize-form-command '(turn/resume))
        provider
        session))
     "Approval required"
     "turn/resume should require approval before executing awaiting patch actions")
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :workspace-write))
     provider
     session)
    (multiple-value-bind (resume-result resume-kind resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (assert-equal :turn-resume resume-kind "turn/resume should dispatch correctly")
      (assert-equal 1 (getf resume-result :resumed-operation-count)
                    "turn/resume should resume one blocked action operation")
      (assert-equal 1 (getf resume-result :action-result-count)
                    "turn/resume should execute one pending action")
      (assert-equal 0 (length (sbcl-agent::agent-session-pending-actions resumed-session))
                    "turn/resume should clear pending actions after execution")
      (let ((work-item (first (sbcl-agent::agent-session-work-items resumed-session))))
        (assert-equal :committed
                      (sbcl-agent::work-item-status work-item)
                      "turn/resume should advance the bound work-item to committed")
        (assert-equal :committed
                      (sbcl-agent::workflow-record-status
                       (sbcl-agent::work-item-workflow-record resumed-session work-item))
                      "turn/resume should close the bound workflow record as committed")
        (assert-equal :passed
                      (sbcl-agent::validation-result-status
                       (sbcl-agent::work-item-live-validation-result work-item))
                      "turn/resume should attach live validation evidence to the work-item")
        (assert-equal :passed
                      (sbcl-agent::validation-result-status
                       (sbcl-agent::work-item-cold-validation-result work-item))
                      "turn/resume should attach cold validation evidence to the work-item")))
    (multiple-value-bind (turn-result turn-kind turn-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/status))
         provider
         session)
      (declare (ignore turn-session))
      (assert-equal :turn-status turn-kind "turn/status should dispatch correctly after resume")
      (assert-equal :completed (getf turn-result :status)
                    "turn/resume should move the turn to completed")
      (assert-true (not (getf (getf turn-result :awaiting-approval) :awaiting-approval-p))
                   "turn/resume should clear approval wait summary")
      (assert-equal 1 (length (getf turn-result :artifacts))
                    "turn/resume should attach one artifact for the resumed patch write")
      (assert-equal "generated.txt"
                    (getf (first (getf turn-result :artifacts)) :title)
                    "turn/resume should expose the created file artifact")
      (assert-equal :committed
                    (getf (getf turn-result :detail-summary) :work-item-status)
                    "turn/status should summarize the bound work-item status after resume")
      (assert-true (stringp (getf (first (getf turn-result :artifacts)) :work-item-id))
                   "turn/resume should attach the resumed artifact to the originating work-item")
      (let ((patch-op (find "assistant-patch"
                            (getf turn-result :operations)
                            :key (lambda (entry) (getf entry :name))
                            :test #'string=)))
        (assert-true patch-op "turn/status should still expose the patch operation after resume")
        (assert-equal :completed (getf patch-op :status)
                      "turn/resume should mark the patch operation completed")))
    (multiple-value-bind (thread-result thread-kind thread-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(thread/show))
         provider
         session)
      (declare (ignore thread-session))
      (assert-equal :thread-show thread-kind "thread/show should dispatch after turn resume")
      (assert-equal 1 (length (getf thread-result :artifacts))
                    "thread/show should expose persisted thread artifacts after resume")
      (assert-equal 1
                    (getf (getf thread-result :detail-summary) :work-item-artifact-count)
                    "thread/show should summarize work-item artifact counts after resume"))))

(defun turn-resume-isolates-pending-actions-by-turn-test ()
  (let* ((provider (make-instance 'patch-action-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare first patch"))
     provider
     session)
    (let* ((thread (sbcl-agent::current-thread session))
           (first-turn (first (sbcl-agent::list-thread-turns session (sbcl-agent::thread-id thread)))))
      (sbcl-agent::execute-command
       (sbcl-agent::normalize-form-command '(say "prepare second patch"))
       provider
       session)
      (let* ((turns (sbcl-agent::list-thread-turns session (sbcl-agent::thread-id thread)))
             (second-turn (first (last turns))))
        (assert-true (not (string= (sbcl-agent::turn-id first-turn)
                                   (sbcl-agent::turn-id second-turn)))
                     "test setup should create two distinct awaiting-approval turns")
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(approve :workspace-write))
         provider
         session)
        (multiple-value-bind (resume-result resume-kind resumed-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(turn/resume ,(sbcl-agent::turn-id first-turn)))
             provider
             session)
          (declare (ignore resumed-session))
          (assert-equal :turn-resume resume-kind
                        "turn/resume should dispatch correctly for an explicit turn id")
          (assert-equal 1 (getf resume-result :resumed-operation-count)
                        "turn/resume should complete only one blocked operation for the target turn")
          (assert-equal 1 (getf resume-result :action-result-count)
                        "turn/resume should execute only the target turn action"))
        (let* ((updated-first-turn (sbcl-agent::find-turn session (sbcl-agent::turn-id first-turn)))
               (updated-second-turn (sbcl-agent::find-turn session (sbcl-agent::turn-id second-turn)))
               (first-ops (sbcl-agent::list-turn-operations session (sbcl-agent::turn-id updated-first-turn)))
               (second-ops (sbcl-agent::list-turn-operations session (sbcl-agent::turn-id updated-second-turn)))
               (first-patch-op (find "assistant-patch"
                                     first-ops
                                     :key #'sbcl-agent::operation-name
                                     :test #'string=))
               (second-patch-op (find "assistant-patch"
                                      second-ops
                                      :key #'sbcl-agent::operation-name
                                      :test #'string=)))
          (assert-equal :completed (sbcl-agent::turn-status updated-first-turn)
                        "turn/resume should complete the selected turn")
          (assert-equal :awaiting-approval (sbcl-agent::turn-status updated-second-turn)
                        "turn/resume should leave the non-selected turn blocked")
          (assert-true first-patch-op
                       "selected turn should include the staged patch operation")
          (assert-true second-patch-op
                       "non-selected turn should include the staged patch operation")
          (assert-equal :completed (sbcl-agent::operation-status first-patch-op)
                        "turn/resume should complete the selected turn operation")
          (assert-equal :awaiting-approval (sbcl-agent::operation-status second-patch-op)
                        "turn/resume should not consume the other turn's operation")
          (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions session))
                        "turn/resume should leave unrelated staged actions pending"))))))

(defun turn-resume-provider-followup-test ()
  (let* ((provider (make-instance 'followup-patch-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare patch and continue"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :workspace-write))
     provider
     session)
    (multiple-value-bind (resume-result resume-kind resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (declare (ignore resumed-session))
      (assert-equal :turn-resume resume-kind
                    "turn/resume should dispatch correctly for follow-up capable providers")
      (assert-true (getf (getf resume-result :followup) :followup-p)
                   "turn/resume should include structured follow-up results when the provider supports continuation")
      (assert-true (search "Patch applied successfully"
                           (sbcl-agent::assistant-response-message
                            (getf (getf resume-result :followup) :response)))
                   "turn/resume should resume the provider with completed operation context"))
    (let* ((turn (sbcl-agent::most-recent-thread-turn session))
           (detail (sbcl-agent::turn-detail session (sbcl-agent::turn-id turn))))
      (assert-equal :completed (getf detail :status)
                    "follow-up continuation should leave the turn completed")
      (assert-equal 3 (length (getf detail :messages))
                    "follow-up continuation should expose the full turn-local message history")
      (assert-equal :assistant
                    (getf (third (getf detail :messages)) :role)
                    "follow-up continuation should include the final assistant follow-up message in turn-local history")
      (assert-true (search "Patch applied successfully"
                           (getf (getf detail :assistant-message) :content))
                   "follow-up continuation should replace the turn's assistant message with the follow-up summary")
      (assert-equal :completed
                    (getf (getf detail :metadata) :followup-state)
                    "follow-up continuation should leave explicit follow-up state metadata on the turn")
      (assert-equal 3 (length (getf detail :operations))
                    "follow-up continuation should add a second provider operation to the turn"))
    (assert-true (find :turn-followup-started
                       (sbcl-agent::agent-session-events session)
                       :key #'sbcl-agent::event-kind)
                 "follow-up continuation should emit an explicit follow-up started event")
    (assert-true (find :turn-followup-completed
                       (sbcl-agent::agent-session-events session)
                       :key #'sbcl-agent::event-kind)
                 "follow-up continuation should emit an explicit follow-up completed event")))

(defun turn-resume-validation-first-followup-test ()
  (let* ((provider (make-instance 'followup-validation-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "mutate runtime then follow up"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (multiple-value-bind (resume-result resume-kind resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (declare (ignore resumed-session))
      (assert-equal :turn-resume resume-kind
                    "turn/resume should dispatch correctly for validation-first follow-up providers")
      (assert-true (getf (getf resume-result :followup) :followup-p)
                   "turn/resume should still produce structured follow-up results")
      (assert-true (listp (getf (getf resume-result :followup) :action-agenda-summary))
                   "turn/resume follow-up should expose an action agenda summary")
      (assert-equal 1
                    (getf (getf resume-result :followup) :deferred-action-count)
                    "post-mutation follow-up should defer fresh governed mutations while validation remains the next step")
      (assert-equal 0
                    (getf (getf resume-result :followup) :staged-action-count)
                    "post-mutation validation-first follow-up should not stage fresh governed mutations"))
    (let* ((turn (sbcl-agent::most-recent-thread-turn session))
           (detail (sbcl-agent::turn-detail session (sbcl-agent::turn-id turn)))
           (followup-patch-op (find "assistant-patch"
                                    (getf detail :operations)
                                    :key (lambda (entry) (getf entry :name))
                                    :test #'string=))
           (strategy-event (find :strategy-governed-mutations-deferred
                                 (sbcl-agent::agent-session-events session)
                                 :key #'sbcl-agent::event-kind)))
      (assert-equal :completed (getf detail :status)
                    "validation-first follow-up should leave the turn completed")
      (assert-true followup-patch-op
                   "validation-first follow-up should still record the deferred follow-up patch operation")
      (assert-equal :blocked (getf followup-patch-op :status)
                    "validation-first follow-up should record the follow-up patch as blocked")
      (assert-true strategy-event
                   "validation-first follow-up should emit a strategy deferral event")
      (assert-true (getf (sbcl-agent::event-payload strategy-event) :post-mutation-p)
                   "strategy deferral event should identify post-mutation follow-up enforcement")
      (assert-equal :validate
                    (getf (getf (sbcl-agent::event-payload strategy-event) :outcome-brief)
                          :recommended-next-step)
                    "strategy deferral event should preserve the validating next step"))))

(defun session-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (path "/tmp/sbcl-agent-shell-session.sexp")
         (session (sbcl-agent::make-default-session)))
    (sbcl-agent::update-session-plan session "Shell persistence")
    (sbcl-agent::approve-policy session :runtime-package-switch)
    (sbcl-agent::command-runtime-set-package-service session "CL-USER")
    (multiple-value-bind (describe-result describe-kind described-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(describe-session))
         provider
         session)
      (declare (ignore described-session))
      (assert-equal :describe-session describe-kind "describe-session should dispatch correctly")
      (assert-equal "Shell persistence"
                    (getf describe-result :plan)
                    "describe-session should report the current plan")
      (assert-true (> (getf (getf describe-result :execution-surfaces) :count) 0)
                   "describe-session should expose execution-backed surfaces")
      (assert-true (integerp (getf (getf describe-result :blocked-work-surfaces) :count))
                   "describe-session should expose compact blocked-work surfaces")
      (assert-true (integerp (getf (getf describe-result :approval-surfaces) :count))
                   "describe-session should expose compact approval surfaces"))
    (multiple-value-bind (save-result save-kind saved-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(session/save ,path))
         provider
         session)
      (declare (ignore saved-session))
      (assert-equal :session-save save-kind "session/save should dispatch correctly")
      (assert-equal path (getf save-result :saved)
                    "session/save should report the saved path"))
    (let ((fresh-session (sbcl-agent::reset-session session)))
      (assert-true (null (sbcl-agent::agent-session-plan fresh-session))
                   "reset-session should clear the plan"))
    (multiple-value-bind (load-result load-kind loaded-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(session/load ,path))
         provider
         (sbcl-agent::make-default-session))
      (assert-equal :session-load load-kind "session/load should dispatch correctly")
      (assert-equal path (getf load-result :loaded)
                    "session/load should report the loaded path")
      (assert-true (listp (getf load-result :workspace))
                   "session/load should now expose workspace shell posture")
      (assert-equal "Shell persistence"
                    (sbcl-agent::agent-session-plan loaded-session)
                    "session/load should restore the saved plan"))))

(defun shell-workspace-commands-test ()
  (let* ((provider (make-test-provider))
         (session (make-test-session :cwd "/tmp/shell-workspace-commands/"))
         (work-item (sbcl-agent::create-work-item session "Shell workspace governed work")))
    (sbcl-agent::approve-policy session :process-run)
    (sbcl-agent::command-request-work-item-approval-service session
                                                            (sbcl-agent::work-item-id work-item)
                                                            :process-run
                                                            :reason "Need operator review")
    (sbcl-agent::command-task-enqueue-service
     session
     '(tool :fs/list :path ".")
     (sbcl-agent::normalize-form-command '(tool :fs/list :path "."))
     0)
    (sbcl-agent::command-worker-start-service session provider)
    (multiple-value-bind (workspace-result workspace-kind workspace-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(workspace/show))
         provider
         session)
      (declare (ignore workspace-session))
      (assert-equal :workspace-show workspace-kind
                    "workspace/show should dispatch correctly")
      (assert-true (> (getf (getf workspace-result :execution-surfaces) :count) 0)
                   "workspace/show should expose execution surfaces")
      (assert-true (> (getf (getf workspace-result :governance-queue) :count) 0)
                   "workspace/show should expose governance queue items")
      (assert-true (> (getf (getf workspace-result :object-browser) :group-count) 0)
                   "workspace/show should expose object-browser groups")
      (assert-true (stringp (getf workspace-result :inspector-focus-object-id))
                   "workspace/show should expose an inspector focus object id")
      (assert-true (listp (getf workspace-result :current-focus))
                   "workspace/show should expose a compact current focus summary")
      (assert-true (listp (getf workspace-result :recommended-action))
                   "workspace/show should expose a recommended next action")
      (multiple-value-bind (desktop-result desktop-kind desktop-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(desktop/show))
           provider
           session)
        (declare (ignore desktop-session))
        (assert-equal :desktop-show desktop-kind
                      "desktop/show should dispatch correctly")
        (assert-true (> (getf desktop-result :surface-count) 0)
                     "desktop/show should expose surface count")
        (assert-true (> (getf desktop-result :governance-count) 0)
                     "desktop/show should expose governance count")
        (assert-true (> (length (getf desktop-result :entry-points)) 0)
                     "desktop/show should expose desktop entry points")
        (assert-equal :inspector
                      (getf desktop-result :active-panel)
                      "desktop/show should expose the active panel")
        (assert-true (listp (getf desktop-result :active-panel-summary))
                     "desktop/show should expose a compact active panel summary")
        (assert-equal :inspector
                      (getf (getf desktop-result :active-panel-summary) :panel-id)
                      "desktop/show should align the active panel summary with the active panel")
        (assert-true (listp (getf desktop-result :recommended-action))
                     "desktop/show should expose a recommended next desktop action")
        (assert-equal :open-panel
                      (getf (getf desktop-result :recommended-action) :action-kind)
                      "desktop/show should recommend opening the focused execution when inspector is active")
        (assert-true (listp (getf desktop-result :panels))
                     "desktop/show should expose panel state")
        (assert-equal (getf (getf (getf desktop-result :panels) :workspace) :selected-index)
                      (getf (getf desktop-result :surface-list) :focus-index)
                      "desktop/show should align workspace panel selection with surface focus")
        (assert-true (stringp (getf (getf (getf (getf desktop-result :panels) :workspace) :actions)
                                          :open-command))
                     "desktop/show should expose workspace panel open commands")
        (assert-true (stringp (getf (getf (getf (getf desktop-result :panels) :governance) :actions)
                                          :select-command))
                     "desktop/show should expose governance panel select commands")
        (assert-equal :activate-panel
                      (getf (getf (getf (getf (getf desktop-result :panels) :workspace) :actions)
                                  :activate)
                            :action-kind)
                      "desktop/show should expose structured workspace panel activate actions")
        (assert-true (stringp (getf (getf (getf (getf (getf desktop-result :panels) :workspace) :actions)
                                                :activate)
                                      :action-id))
                     "desktop/show should expose stable workspace panel action ids")
        (assert-true (stringp (getf (getf (getf (getf (getf desktop-result :panels) :workspace) :actions)
                                                :restore)
                                      :action-id))
                     "desktop/show should expose stable workspace panel restore action ids")
        (assert-true (stringp (getf (first (getf desktop-result :entry-points)) :command))
                     "desktop/show should expose string shell commands for entry points"))
      (multiple-value-bind (desktop-panel-result desktop-panel-kind desktop-panel-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(desktop/panel :governance))
           provider
           session)
        (declare (ignore desktop-panel-session))
        (assert-equal :desktop-panel desktop-panel-kind
                      "desktop/panel should dispatch correctly")
        (assert-equal :governance
                      (getf desktop-panel-result :active-panel)
                      "desktop/panel should persist the requested active panel")
        (assert-equal :governance
                      (getf (getf desktop-panel-result :desktop-model) :active-panel)
                      "desktop/panel should return a desktop model with the requested active panel"))
      (multiple-value-bind (desktop-select-result desktop-select-kind desktop-select-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(desktop/select :panel :workspace :index 0))
           provider
           session)
        (declare (ignore desktop-select-session))
        (assert-equal :desktop-select desktop-select-kind
                      "desktop/select workspace should dispatch correctly")
        (assert-equal :workspace
                      (getf desktop-select-result :panel-id)
                      "desktop/select workspace should report the selected panel")
        (assert-equal :workspace
                      (getf (getf desktop-select-result :desktop-model) :active-panel)
                      "desktop/select workspace should make workspace the active panel")
        (assert-equal (getf (getf desktop-select-result :selection) :selected-index)
                      (getf (getf (getf (getf desktop-select-result :desktop-model) :panels)
                                  :workspace)
                            :selected-index)
                      "desktop/select workspace should restore selected index in the desktop model")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf (getf desktop-select-result :desktop-model) :focus-object-id)
                      "desktop/select workspace should preserve the selected focus object"))
      (let* ((desktop-model (sbcl-agent::service-response-data
                             (sbcl-agent::query-shell-desktop-model-service session)))
             (workspace-panel-state (getf (getf desktop-model :panels) :workspace)))
        (multiple-value-bind (desktop-restore-result desktop-restore-kind desktop-restore-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command
              `(desktop/restore :panel-state ',workspace-panel-state))
             provider
             session)
          (declare (ignore desktop-restore-session))
          (assert-equal :desktop-restore desktop-restore-kind
                        "desktop/restore should dispatch correctly")
          (assert-equal :workspace
                        (getf (getf desktop-restore-result :desktop-model) :active-panel)
                        "desktop/restore should restore the requested panel")
          (assert-equal (getf workspace-panel-state :selected-index)
                        (getf (getf (getf (getf desktop-restore-result :desktop-model) :panels)
                                    :workspace)
                              :selected-index)
                        "desktop/restore should restore workspace selection posture")))
      (let* ((desktop-model (sbcl-agent::service-response-data
                             (sbcl-agent::query-shell-desktop-model-service session)))
             (workspace-restore-action
               (getf (getf (getf (getf desktop-model :panels)
                                 :workspace)
                           :actions)
                     :restore)))
        (multiple-value-bind (desktop-action-result desktop-action-kind desktop-action-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command
              `(desktop/action ,@workspace-restore-action))
             provider
             session)
          (declare (ignore desktop-action-session))
          (assert-equal :desktop-action desktop-action-kind
                        "desktop/action restore should dispatch correctly")
          (assert-equal :workspace
                        (getf (getf desktop-action-result :result) :panel-id)
                        "desktop/action restore should preserve restore panel identity")
          (assert-equal :workspace
                        (getf (getf desktop-action-result :desktop-model) :active-panel)
                        "desktop/action restore should restore the requested panel")))
      (let* ((desktop-model (sbcl-agent::service-response-data
                             (sbcl-agent::query-shell-desktop-model-service session)))
             (desktop-governance-action (getf (getf (getf (getf desktop-model :panels)
                                                          :governance)
                                                    :actions)
                                              :activate)))
        (multiple-value-bind (desktop-action-result desktop-action-kind desktop-action-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command
              `(desktop/action ,@desktop-governance-action))
             provider
             session)
          (declare (ignore desktop-action-session))
          (assert-equal :desktop-action desktop-action-kind
                        "desktop/action activate should dispatch correctly")
          (assert-equal :governance
                        (getf (getf desktop-action-result :desktop-model) :active-panel)
                        "desktop/action activate should update the active panel")))
      (let* ((desktop-model (sbcl-agent::service-response-data
                             (sbcl-agent::query-shell-desktop-model-service session)))
             (desktop-governance-action-id
               (getf (getf (getf (getf (getf desktop-model :panels)
                                       :governance)
                                 :actions)
                           :activate)
                     :action-id)))
        (multiple-value-bind (desktop-action-result desktop-action-kind desktop-action-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command
              `(desktop/action :action-id ,desktop-governance-action-id))
             provider
             session)
          (declare (ignore desktop-action-session))
          (assert-equal :desktop-action desktop-action-kind
                        "desktop/action by action-id should dispatch correctly")
          (assert-equal desktop-governance-action-id
                        (getf (getf desktop-action-result :action) :action-id)
                        "desktop/action should resolve and report the requested action id")
          (assert-equal :governance
                        (getf (getf desktop-action-result :desktop-model) :active-panel)
                        "desktop/action by action-id should activate the selected panel")))
      (multiple-value-bind (desktop-select-governance-result desktop-select-governance-kind desktop-select-governance-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(desktop/select :panel :governance :index 0))
           provider
           session)
        (declare (ignore desktop-select-governance-session))
        (assert-equal :desktop-select desktop-select-governance-kind
                      "desktop/select governance should dispatch correctly")
        (assert-equal :governance
                      (getf desktop-select-governance-result :panel-id)
                      "desktop/select governance should report the selected panel")
        (assert-equal :governance
                      (getf (getf desktop-select-governance-result :desktop-model) :active-panel)
                      "desktop/select governance should make governance the active panel")
        (assert-true (stringp (getf (getf (getf (getf desktop-select-governance-result :desktop-model) :panels)
                                                :governance)
                                      :selected-title))
                     "desktop/select governance should preserve selected governance title in the desktop model"))
      (let* ((desktop-model (sbcl-agent::service-response-data
                             (sbcl-agent::query-shell-desktop-model-service session)))
             (desktop-governance-open-action (getf (getf (getf (getf desktop-model :panels)
                                                               :governance)
                                                         :actions)
                                                   :open)))
        (multiple-value-bind (desktop-action-result desktop-action-kind desktop-action-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command
              `(desktop/action ,@desktop-governance-open-action))
             provider
             session)
          (declare (ignore desktop-action-session))
          (assert-equal :desktop-action desktop-action-kind
                        "desktop/action open should dispatch correctly")
          (assert-equal :governance
                        (getf (getf desktop-action-result :result) :open-via)
                        "desktop/action open should preserve the governance open path")))
      (multiple-value-bind (desktop-select-object-result desktop-select-object-kind desktop-select-object-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(desktop/select :panel :object-browser :kind :work-item :index 0))
           provider
           session)
        (declare (ignore desktop-select-object-session))
        (assert-equal :desktop-select desktop-select-object-kind
                      "desktop/select object-browser should dispatch correctly")
        (assert-equal :object-browser
                      (getf desktop-select-object-result :panel-id)
                      "desktop/select object-browser should report the selected panel")
        (assert-equal :object-browser
                      (getf (getf desktop-select-object-result :desktop-model) :active-panel)
                      "desktop/select object-browser should make object-browser the active panel")
        (assert-equal :work-item
                      (getf (getf (getf (getf desktop-select-object-result :desktop-model) :panels)
                                  :object-browser)
                            :selected-kind)
                      "desktop/select object-browser should preserve selected kind in the desktop model"))
      (let ((manual-focus-id (sbcl-agent::agent-session-shell-focus-object-id session)))
        (assert-true (stringp manual-focus-id)
                     "desktop/select inspector requires an existing focused object")
        (multiple-value-bind (desktop-select-inspector-result desktop-select-inspector-kind desktop-select-inspector-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command '(desktop/select :panel :inspector))
             provider
             session)
          (declare (ignore desktop-select-inspector-session))
          (assert-equal :desktop-select desktop-select-inspector-kind
                        "desktop/select inspector should dispatch correctly")
          (assert-equal :inspector
                        (getf desktop-select-inspector-result :panel-id)
                        "desktop/select inspector should report the selected panel")
          (assert-equal :inspector
                        (getf (getf desktop-select-inspector-result :desktop-model) :active-panel)
                        "desktop/select inspector should make inspector the active panel")
          (assert-equal manual-focus-id
                        (getf (getf desktop-select-inspector-result :desktop-model) :focus-object-id)
                        "desktop/select inspector should preserve the existing focus object")))
      (multiple-value-bind (surface-list-result surface-list-kind surface-list-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(surface/list))
           provider
           session)
        (declare (ignore surface-list-session))
        (assert-equal :surface-list surface-list-kind
                      "surface/list should dispatch correctly")
        (assert-true (> (getf surface-list-result :count) 0)
                     "surface/list should expose execution surfaces")
        (assert-true (integerp (getf surface-list-result :focus-index))
                     "surface/list should expose a focused surface index"))
      (multiple-value-bind (surface-select-result surface-select-kind surface-select-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(surface/select :index 0))
           provider
           session)
        (declare (ignore surface-select-session))
        (assert-equal :surface-select surface-select-kind
                      "surface/select should dispatch correctly")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf surface-select-result :focus-object-id)
                      "surface/select should persist the selected surface focus"))
      (let* ((surface-focus-before-step (sbcl-agent::agent-session-shell-focus-object-id session))
             (surface-count (getf (getf workspace-result :execution-surfaces) :count)))
        (multiple-value-bind (surface-step-result surface-step-kind surface-step-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command '(surface/step :next))
             provider
             session)
          (declare (ignore surface-step-session))
          (assert-equal :surface-step surface-step-kind
                        "surface/step should dispatch correctly")
          (assert-equal :next (getf surface-step-result :direction)
                        "surface/step should preserve the requested direction")
          (assert-true (stringp (getf surface-step-result :focus-object-id))
                       "surface/step should expose a focused surface object id")
          (when (> surface-count 1)
            (assert-true (not (string= surface-focus-before-step
                                       (getf surface-step-result :focus-object-id)))
                         "surface/step should move focus when multiple surfaces exist"))))
      (multiple-value-bind (open-result open-kind open-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(open :surface-index 0))
           provider
           session)
        (declare (ignore open-session))
        (assert-equal :open open-kind
                      "open should dispatch correctly")
        (assert-equal :surface (getf open-result :open-via)
                      "open should report the surface entry path")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf open-result :focus-object-id)
                      "open should persist the focused object id")
        (assert-true (member (getf (getf open-result :inspection) :object-kind)
                             '(:work-item :workflow-record :incident :runtime :turn :execution :compatibility-execution))
                     "open should land on an inspectable kernel object"))
      (multiple-value-bind (queue-result queue-kind queue-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(governance/queue))
           provider
           session)
        (declare (ignore queue-session))
        (assert-equal :governance-queue queue-kind
                      "governance/queue should dispatch correctly")
        (assert-true (> (getf queue-result :count) 0)
                     "governance/queue should report at least one item")
        (assert-true (member (getf (getf queue-result :top-item) :queue-kind)
                             '(:approval :blocked-work :incident))
                     "governance/queue should classify the top item"))
      (multiple-value-bind (governance-select-result governance-select-kind governance-select-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(governance/select :index 0))
           provider
           session)
        (declare (ignore governance-select-session))
        (assert-equal :governance-select governance-select-kind
                      "governance/select should dispatch correctly")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf governance-select-result :focus-object-id)
                      "governance/select should persist the selected focus object")
        (assert-true (stringp (getf (getf governance-select-result :selected-item) :title))
                     "governance/select should return the selected item title"))
      (multiple-value-bind (open-governance-result open-governance-kind open-governance-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(open :governance-index 0))
           provider
           session)
        (declare (ignore open-governance-session))
        (assert-equal :open open-governance-kind
                      "open governance should dispatch correctly")
        (assert-equal :governance (getf open-governance-result :open-via)
                      "open governance should report the governance entry path")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf open-governance-result :focus-object-id)
                      "open governance should persist the selected focus"))
      (multiple-value-bind (browser-result browser-kind browser-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(object-browser))
           provider
           session)
        (declare (ignore browser-session))
        (assert-equal :object-browser browser-kind
                      "object-browser should dispatch correctly")
        (assert-true (> (getf browser-result :group-count) 0)
                     "object-browser should expose grouped objects")
        (assert-true (stringp (getf browser-result :focus-object-id))
                     "object-browser should expose a focus object id"))
      (multiple-value-bind (object-select-result object-select-kind object-select-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(object-browser/select :kind :work-item :index 0))
           provider
           session)
        (declare (ignore object-select-session))
        (assert-equal :object-browser-select object-select-kind
                      "object-browser/select should dispatch correctly")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf object-select-result :focus-object-id)
                      "object-browser/select should persist the selected focus object")
        (assert-true (stringp (getf object-select-result :selected-title))
                     "object-browser/select should return the selected object title")))
      (multiple-value-bind (open-object-result open-object-kind open-object-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(open :object-kind :work-item :object-index 0))
           provider
           session)
        (declare (ignore open-object-session))
        (assert-equal :open open-object-kind
                      "open object-browser should dispatch correctly")
        (assert-equal :object-browser (getf open-object-result :open-via)
                      "open object-browser should report the object-browser entry path")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf open-object-result :focus-object-id)
                      "open object-browser should persist the selected focus"))
    (let ((manual-focus-id (sbcl-agent::agent-session-shell-focus-object-id session)))
      (assert-true (stringp manual-focus-id)
                   "shell workspace test requires a persisted shell focus before focus/set")
      (multiple-value-bind (focus-set-result focus-set-kind focus-set-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command
            `(focus/set ,manual-focus-id))
           provider
           session)
        (declare (ignore focus-set-session))
        (assert-equal :focus-set focus-set-kind
                      "focus/set should dispatch correctly")
        (assert-equal manual-focus-id
                      (getf focus-set-result :focus-object-id)
                      "focus/set should preserve the requested focus object"))
      (multiple-value-bind (focus-show-result focus-show-kind focus-show-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(focus/show))
           provider
           session)
        (declare (ignore focus-show-session))
        (assert-equal :focus-show focus-show-kind
                      "focus/show should dispatch correctly")
        (assert-equal manual-focus-id
                      (getf focus-show-result :focus-object-id)
                      "focus/show should return the persisted shell focus"))
      (multiple-value-bind (inspector-result inspector-kind inspector-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(inspector/show))
           provider
           session)
        (declare (ignore inspector-session))
        (assert-equal :inspector-show inspector-kind
                      "inspector/show should dispatch correctly")
        (assert-equal (sbcl-agent::agent-session-shell-focus-object-id session)
                      (getf inspector-result :focus-object-id)
                      "inspector/show should honor the persisted shell focus")
        (assert-true (member (getf inspector-result :object-kind)
                             '(:work-item :workflow-record :incident :runtime :turn :execution :compatibility-execution))
                     "inspector/show should resolve the focused object through the kernel")
        (assert-true (listp (getf inspector-result :summary))
                     "inspector/show should expose a compact inspector summary")
        (assert-true (listp (getf inspector-result :recommended-action))
                     "inspector/show should expose a recommended next action")))))

(defun platform-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (session (make-test-session :cwd "/tmp/platform-shell-commands/"))
         (output-path "/tmp/platform-shell-package.aop"))
    (when (probe-file output-path)
      (delete-file output-path))
    (multiple-value-bind (manifest-result manifest-kind manifest-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/manifest :capabilities '(:proc/run)))
         provider
         session)
      (declare (ignore manifest-session))
      (assert-equal :platform-manifest manifest-kind
                    "platform/manifest should dispatch correctly")
      (assert-equal 1 (getf manifest-result :capability-count)
                    "platform/manifest should filter the manifest to the requested capability")
      (assert-equal :proc/run
                    (getf (first (getf manifest-result :capabilities)) :capability-id)
                    "platform/manifest should report the requested capability")
      (assert-true (> (getf manifest-result :workflow-count) 0)
                   "platform/manifest should expose governed workflow inventory")
      (assert-true (find :platform-cli/package
                         (getf manifest-result :sdk-commands)
                         :key (lambda (entry) (getf entry :command-id))
                         :test #'eq)
                   "platform/manifest should expose platform sdk entrypoints"))
    (multiple-value-bind (package-result package-kind package-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command
          `(platform/package :output-path ,output-path :package-id "demo-kit" :package-version "1.2.0" :title "Demo Kit"
                             :capabilities '(:proc/run :git/status)))
         provider
         session)
      (declare (ignore package-session))
      (assert-equal :platform-package package-kind
                    "platform/package should dispatch correctly")
      (assert-equal "demo-kit" (getf package-result :package-id)
                    "platform/package should preserve the package id")
      (assert-equal "1.2.0" (getf package-result :package-version)
                    "platform/package should preserve the package version")
      (assert-equal t (getf package-result :contract-compatible-p)
                    "platform/package should expose contract-compatibility state")
      (assert-equal t (getf package-result :support-valid-p)
                    "platform/package should expose support-valid state")
      (assert-equal t (getf package-result :lifecycle-valid-p)
                    "platform/package should expose lifecycle-valid state")
      (assert-equal nil (getf package-result :lifecycle-override-required-p)
                    "platform/package should not require lifecycle override for active packages")
      (assert-equal t (getf package-result :recovery-valid-p)
                    "platform/package should expose recovery-valid state")
      (assert-equal nil (getf package-result :recovery-override-required-p)
                    "platform/package should not require recovery override for default packages")
      (assert-equal t (getf package-result :provenance-valid-p)
                    "platform/package should expose provenance-valid state")
      (assert-equal t (getf package-result :provenance-trusted-p)
                    "platform/package should expose provenance-trusted state")
      (assert-equal t (getf package-result :integrity-valid-p)
                    "platform/package should expose integrity-valid state")
      (assert-true (probe-file output-path)
                   "platform/package should write the .aop descriptor")
      (let ((contents (uiop:read-file-string output-path)))
        (assert-true (search "\"title\":\"Demo Kit\"" contents)
                     "platform/package should persist the package title")
        (assert-true (search "\"package_version\":\"1.2.0\"" contents)
                     "platform/package should persist the package version")
        (assert-true (search "\"required_desktop_contract\":\"desktop-shell-v1\"" contents)
                     "platform/package should persist desktop host contract requirements")
        (assert-true (search "\"release_channel\":\"stable\"" contents)
                     "platform/package should persist support metadata")
        (assert-true (search "\"release_status\":\"active\"" contents)
                     "platform/package should persist active lifecycle posture")
        (assert-true (search "\"rollback_strategy\":\"reinstall-prior\"" contents)
                     "platform/package should persist default recovery posture")
        (assert-true (search "\"publisher\":\"local-developer\"" contents)
                     "platform/package should persist provenance metadata")
        (assert-true (search "\"attested_p\":true" contents)
                     "platform/package should persist provenance attestation")
        (assert-true (search "\"algorithm\":\"fnv1a-64\"" contents)
                     "platform/package should persist package integrity metadata")
        (assert-true (search "\"capability_count\":2" contents)
                     "platform/package should persist the selected capability set")
        (assert-true (search "\"workflow_count\"" contents)
                     "platform/package should persist workflow inventory")
        (assert-true (search "\"sdk_command_ids\"" contents)
                     "platform/package should persist sdk command inventory")))
    (multiple-value-bind (show-result show-kind show-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(platform/show-package ,output-path))
         provider
         session)
      (declare (ignore show-session))
      (assert-equal :platform-show-package show-kind
                    "platform/show-package should dispatch correctly")
      (assert-equal t (getf show-result :valid-p)
                    "platform/show-package should report a valid package")
      (assert-equal "1.2.0" (getf show-result :package-version)
                    "platform/show-package should preserve the package version")
      (assert-equal t (getf show-result :contract-compatible-p)
                    "platform/show-package should report contract compatibility")
      (assert-equal t (getf show-result :support-valid-p)
                    "platform/show-package should report support compatibility")
      (assert-equal t (getf show-result :lifecycle-valid-p)
                    "platform/show-package should report lifecycle compatibility")
      (assert-equal t (getf show-result :recovery-valid-p)
                    "platform/show-package should report recovery compatibility")
      (assert-equal t (getf show-result :provenance-valid-p)
                    "platform/show-package should report provenance compatibility")
      (assert-equal t (getf show-result :provenance-trusted-p)
                    "platform/show-package should report provenance trust")
      (assert-equal t (getf show-result :integrity-valid-p)
                    "platform/show-package should report package integrity")
      (assert-equal "demo-kit" (getf show-result :package-id)
                    "platform/show-package should preserve the package id"))
    (multiple-value-bind (validate-result validate-kind validate-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(platform/validate-package ,output-path))
         provider
         session)
      (declare (ignore validate-session))
      (assert-equal :platform-validate-package validate-kind
                    "platform/validate-package should dispatch correctly")
      (assert-equal :new (getf validate-result :update-posture)
                    "platform/validate-package should mark brand-new descriptors as new")
      (assert-equal t (getf validate-result :contract-compatible-p)
                    "platform/validate-package should report contract compatibility")
      (assert-equal t (getf validate-result :support-valid-p)
                    "platform/validate-package should report support compatibility")
      (assert-equal t (getf validate-result :lifecycle-valid-p)
                    "platform/validate-package should report lifecycle compatibility")
      (assert-equal t (getf validate-result :recovery-valid-p)
                    "platform/validate-package should report recovery compatibility")
      (assert-equal t (getf validate-result :provenance-valid-p)
                    "platform/validate-package should report provenance compatibility")
      (assert-equal t (getf validate-result :provenance-trusted-p)
                    "platform/validate-package should report provenance trust")
      (assert-equal t (getf validate-result :integrity-valid-p)
                    "platform/validate-package should report package integrity")
      (assert-equal t (getf validate-result :valid-p)
                    "platform/validate-package should report a valid package"))
    (multiple-value-bind (import-result import-kind import-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(platform/import-package ,output-path))
         provider
         session)
      (declare (ignore import-session))
      (assert-equal :platform-import-package import-kind
                    "platform/import-package should dispatch correctly")
      (assert-equal 1 (getf import-result :registry-count)
                    "platform/import-package should register the imported package")
      (assert-equal "demo-kit"
                    (getf (getf import-result :package) :package-id)
                    "platform/import-package should return the imported package summary")
      (assert-equal "1.2.0"
                    (getf (getf import-result :package) :package-version)
                    "platform/import-package should preserve the imported package version"))
    (multiple-value-bind (list-result list-kind list-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/list-packages))
         provider
         session)
      (declare (ignore list-session))
      (assert-equal :platform-list-packages list-kind
                    "platform/list-packages should dispatch correctly")
      (assert-equal 1 (getf list-result :count)
                    "platform/list-packages should expose imported package count"))
    (multiple-value-bind (imported-result imported-kind imported-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/show-imported-package "demo-kit"))
         provider
         session)
      (declare (ignore imported-session))
      (assert-equal :platform-show-imported-package imported-kind
                    "platform/show-imported-package should dispatch correctly")
      (assert-equal "demo-kit" (getf imported-result :package-id)
                    "platform/show-imported-package should return the imported package by id")
      (assert-equal "1.2.0" (getf imported-result :package-version)
                    "platform/show-imported-package should preserve the imported package version"))
    (multiple-value-bind (history-result history-kind history-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/history))
         provider
         session)
      (declare (ignore history-session))
      (assert-equal :platform-history history-kind
                    "platform/history should dispatch correctly")
      (assert-equal 1 (getf history-result :count)
                    "platform/history should expose the initial import event"))
    (multiple-value-bind (audit-result audit-kind audit-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/audit))
         provider
         session)
      (declare (ignore audit-session))
      (assert-equal :platform-audit audit-kind
                    "platform/audit should dispatch correctly")
      (assert-equal 1 (getf audit-result :count)
                    "platform/audit should report imported package count")
      (assert-equal 0 (getf audit-result :override-count)
                    "platform/audit should report no override usage before explicit overrides"))
    (multiple-value-bind (activate-result activate-kind activate-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/activate-package "demo-kit"))
         provider
         session)
      (declare (ignore activate-session))
      (assert-equal :platform-activate-package activate-kind
                    "platform/activate-package should dispatch correctly")
      (assert-equal t (getf (getf activate-result :package) :active-p)
                    "platform/activate-package should mark the package active"))
    (multiple-value-bind (active-result active-kind active-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/active-packages))
         provider
         session)
      (declare (ignore active-session))
      (assert-equal :platform-active-packages active-kind
                    "platform/active-packages should dispatch correctly")
      (assert-equal 1 (getf active-result :count)
                    "platform/active-packages should expose active package count"))
    (multiple-value-bind (profile-result profile-kind profile-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/profile))
         provider
         session)
      (declare (ignore profile-session))
      (assert-equal :platform-profile profile-kind
                    "platform/profile should dispatch correctly")
      (assert-equal 2 (getf profile-result :capability-count)
                    "platform/profile should expose the applied active-package capability set"))
    (multiple-value-bind (deactivate-result deactivate-kind deactivate-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/deactivate-package "demo-kit"))
         provider
         session)
      (declare (ignore deactivate-session))
      (assert-equal :platform-deactivate-package deactivate-kind
                    "platform/deactivate-package should dispatch correctly")
      (assert-equal nil (getf (getf deactivate-result :package) :active-p)
                    "platform/deactivate-package should clear the active package flag"))
    (multiple-value-bind (history-result history-kind history-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/history :package-id "demo-kit" :limit 10))
         provider
         session)
      (declare (ignore history-session))
      (assert-equal :platform-history history-kind
                    "platform/history should dispatch filtered history queries correctly")
      (assert-equal 3 (getf history-result :count)
                    "platform/history should expose import, activate, and deactivate events for one package"))
    (multiple-value-bind (install-result install-kind install-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(platform/install-package ,output-path))
         provider
         (make-test-session :cwd "/tmp/platform-install-shell-commands/"))
      (declare (ignore install-session))
      (assert-equal :platform-install-package install-kind
                    "platform/install-package should dispatch correctly")
      (assert-equal t (getf (getf install-result :package) :active-p)
                    "platform/install-package should activate the imported package in one step"))
    (multiple-value-bind (simulate-result simulate-kind simulate-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(platform/simulate-package ,output-path))
         provider
         session)
      (declare (ignore simulate-session))
      (assert-equal :platform-simulate-package simulate-kind
                    "platform/simulate-package should dispatch correctly")
      (assert-equal t (getf simulate-result :valid-p)
                    "platform/simulate-package should report a valid package")
      (assert-equal :same-version (getf simulate-result :update-posture)
                    "platform/simulate-package should recognize same-version replacement posture")
      (assert-true (listp (getf simulate-result :simulated-profile))
                   "platform/simulate-package should expose a simulated profile preview"))
    (let ((downgrade-path "/tmp/platform-downgrade-shell-commands.aop"))
      (multiple-value-bind (downgrade-package-result downgrade-package-kind downgrade-package-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command
            `(platform/package :output-path ,downgrade-path :package-id "demo-kit" :package-version "1.1.0"
                               :title "Demo Kit" :capabilities '(:proc/run)))
           provider
           session)
        (declare (ignore downgrade-package-result downgrade-package-session))
        (assert-equal :platform-package downgrade-package-kind
                      "platform/package should export downgrade descriptors when explicitly requested"))
      (multiple-value-bind (downgrade-simulate-result downgrade-simulate-kind downgrade-simulate-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/simulate-package ,downgrade-path))
           provider
           session)
        (declare (ignore downgrade-simulate-session))
        (assert-equal :platform-simulate-package downgrade-simulate-kind
                      "platform/simulate-package should dispatch downgrade simulations correctly")
        (assert-equal :downgrade (getf downgrade-simulate-result :update-posture)
                      "platform/simulate-package should report downgrade posture")
        (assert-equal t (getf downgrade-simulate-result :would-require-override-p)
                      "platform/simulate-package should require explicit override for downgrades"))
      (assert-signals-error
       (lambda ()
         (sbcl-agent::execute-command
          (sbcl-agent::normalize-form-command `(platform/import-package ,downgrade-path))
          provider
          session))
       "Refusing to downgrade platform package"
       "platform/import-package should refuse downgrades without explicit override")
      (multiple-value-bind (downgrade-import-result downgrade-import-kind downgrade-import-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/import-package ,downgrade-path :allow-downgrade t))
           provider
           session)
        (declare (ignore downgrade-import-session))
        (assert-equal :platform-import-package downgrade-import-kind
                      "platform/import-package should dispatch explicit downgrade overrides")
        (assert-equal :downgrade (getf (getf downgrade-import-result :package) :update-posture)
                      "platform/import-package should preserve downgrade posture when override is granted")))
    (multiple-value-bind (harness-result harness-kind harness-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/harness))
         provider
         session)
      (declare (ignore harness-session))
      (assert-equal :platform-harness harness-kind
                    "platform/harness should dispatch correctly")
      (assert-true (find :internal-evaluations
                         (getf harness-result :harnesses)
                         :key (lambda (entry) (getf entry :harness-id))
                         :test #'eq)
                   "platform/harness should expose the internal evaluations harness"))
    (multiple-value-bind (run-harness-result run-harness-kind run-harness-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/run-harness :harness-id :internal-evaluations))
         provider
         session)
      (declare (ignore run-harness-session))
      (assert-equal :platform-run-harness run-harness-kind
                    "platform/run-harness should dispatch correctly")
      (assert-equal :internal-evaluations
                    (getf (getf run-harness-result :harness) :harness-id)
                    "platform/run-harness should preserve the requested harness id")
      (assert-true (>= (getf (getf run-harness-result :report) :implemented-family-count) 4)
                   "platform/run-harness should return the evaluation report"))
    (let ((untrusted-path "/tmp/platform-untrusted-shell-commands.aop"))
      (multiple-value-bind (untrusted-package-result untrusted-package-kind untrusted-package-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command
            `(platform/package :output-path ,untrusted-path :package-id "untrusted-kit" :package-version "1.0.0"
                               :title "Untrusted Kit" :publisher "unknown-publisher" :attested-p nil
                               :capabilities '(:proc/run)))
           provider
           session)
        (declare (ignore untrusted-package-result untrusted-package-session))
        (assert-equal :platform-package untrusted-package-kind
                      "platform/package should export untrusted descriptors when explicitly requested"))
      (multiple-value-bind (untrusted-validate-result untrusted-validate-kind untrusted-validate-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/validate-package ,untrusted-path))
           provider
           session)
        (declare (ignore untrusted-validate-session))
        (assert-equal :platform-validate-package untrusted-validate-kind
                      "platform/validate-package should dispatch untrusted package validation")
        (assert-equal t (getf untrusted-validate-result :valid-p)
                      "platform/validate-package should accept structurally valid untrusted packages")
        (assert-equal nil (getf untrusted-validate-result :provenance-trusted-p)
                      "platform/validate-package should mark untrusted provenance"))
      (multiple-value-bind (untrusted-simulate-result untrusted-simulate-kind untrusted-simulate-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/simulate-package ,untrusted-path))
           provider
           session)
        (declare (ignore untrusted-simulate-session))
        (assert-equal :platform-simulate-package untrusted-simulate-kind
                      "platform/simulate-package should dispatch untrusted package simulation")
        (assert-equal t (getf untrusted-simulate-result :would-require-trust-override-p)
                      "platform/simulate-package should require trust override for untrusted packages"))
      (assert-signals-error
       (lambda ()
         (sbcl-agent::execute-command
          (sbcl-agent::normalize-form-command `(platform/import-package ,untrusted-path))
          provider
          session))
       "Refusing to import untrusted platform package"
       "platform/import-package should refuse untrusted packages without explicit override")
      (multiple-value-bind (untrusted-import-result untrusted-import-kind untrusted-import-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/import-package ,untrusted-path :allow-untrusted t))
           provider
           session)
        (declare (ignore untrusted-import-session))
        (assert-equal :platform-import-package untrusted-import-kind
                      "platform/import-package should dispatch explicit trust overrides")
        (assert-equal nil (getf (getf untrusted-import-result :package) :provenance-trusted-p)
                      "platform/import-package should preserve untrusted provenance after override")))
    (let ((deprecated-path "/tmp/platform-deprecated-shell-commands.aop"))
      (multiple-value-bind (deprecated-package-result deprecated-package-kind deprecated-package-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command
            `(platform/package :output-path ,deprecated-path :package-id "legacy-kit" :package-version "2.0.0"
                               :title "Legacy Kit" :release-status "deprecated"
                               :replacement-package-id "modern-kit" :capabilities '(:proc/run)))
           provider
           session)
        (declare (ignore deprecated-package-result deprecated-package-session))
        (assert-equal :platform-package deprecated-package-kind
                      "platform/package should export deprecated descriptors when explicitly requested"))
      (multiple-value-bind (deprecated-validate-result deprecated-validate-kind deprecated-validate-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/validate-package ,deprecated-path))
           provider
           session)
        (declare (ignore deprecated-validate-session))
        (assert-equal :platform-validate-package deprecated-validate-kind
                      "platform/validate-package should dispatch deprecated package validation")
        (assert-equal t (getf deprecated-validate-result :valid-p)
                      "platform/validate-package should accept structurally valid deprecated packages")
        (assert-equal t (getf deprecated-validate-result :lifecycle-override-required-p)
                      "platform/validate-package should mark deprecated packages as requiring lifecycle override"))
      (multiple-value-bind (deprecated-simulate-result deprecated-simulate-kind deprecated-simulate-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/simulate-package ,deprecated-path))
           provider
           session)
        (declare (ignore deprecated-simulate-session))
        (assert-equal :platform-simulate-package deprecated-simulate-kind
                      "platform/simulate-package should dispatch deprecated package simulation")
        (assert-equal t (getf deprecated-simulate-result :would-require-lifecycle-override-p)
                      "platform/simulate-package should require lifecycle override for deprecated packages"))
      (assert-signals-error
       (lambda ()
         (sbcl-agent::execute-command
          (sbcl-agent::normalize-form-command `(platform/import-package ,deprecated-path))
          provider
          session))
       "Refusing to import deprecated platform package"
       "platform/import-package should refuse deprecated packages without explicit lifecycle override")
      (multiple-value-bind (deprecated-import-result deprecated-import-kind deprecated-import-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/import-package ,deprecated-path :allow-deprecated t))
           provider
           session)
        (declare (ignore deprecated-import-session))
        (assert-equal :platform-import-package deprecated-import-kind
                      "platform/import-package should dispatch explicit lifecycle overrides")
        (assert-equal t (getf (getf deprecated-import-result :package) :deprecated-p)
                      "platform/import-package should preserve deprecated posture after override")))
    (let ((manual-recovery-path "/tmp/platform-manual-recovery-shell-commands.aop"))
      (multiple-value-bind (manual-recovery-package-result manual-recovery-package-kind manual-recovery-package-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command
            `(platform/package :output-path ,manual-recovery-path :package-id "ops-kit" :package-version "3.0.0"
                               :title "Ops Kit" :rollback-strategy "manual-recovery"
                               :failure-mode "manual-intervention"
                               :recovery-runbook "ops://runbooks/ops-kit" :capabilities '(:proc/run)))
           provider
           session)
        (declare (ignore manual-recovery-package-result manual-recovery-package-session))
        (assert-equal :platform-package manual-recovery-package-kind
                      "platform/package should export manual-recovery descriptors when explicitly requested"))
      (multiple-value-bind (manual-recovery-validate-result manual-recovery-validate-kind manual-recovery-validate-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/validate-package ,manual-recovery-path))
           provider
           session)
        (declare (ignore manual-recovery-validate-session))
        (assert-equal :platform-validate-package manual-recovery-validate-kind
                      "platform/validate-package should dispatch manual-recovery package validation")
        (assert-equal t (getf manual-recovery-validate-result :valid-p)
                      "platform/validate-package should accept structurally valid manual-recovery packages")
        (assert-equal t (getf manual-recovery-validate-result :recovery-override-required-p)
                      "platform/validate-package should mark manual-recovery packages as requiring explicit recovery override"))
      (multiple-value-bind (manual-recovery-simulate-result manual-recovery-simulate-kind manual-recovery-simulate-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/simulate-package ,manual-recovery-path))
           provider
           session)
        (declare (ignore manual-recovery-simulate-session))
        (assert-equal :platform-simulate-package manual-recovery-simulate-kind
                      "platform/simulate-package should dispatch manual-recovery package simulation")
        (assert-equal t (getf manual-recovery-simulate-result :would-require-recovery-override-p)
                      "platform/simulate-package should require explicit recovery override for manual-recovery packages"))
      (assert-signals-error
       (lambda ()
         (sbcl-agent::execute-command
          (sbcl-agent::normalize-form-command `(platform/import-package ,manual-recovery-path))
          provider
          session))
       "Refusing to import manual-recovery platform package"
       "platform/import-package should refuse manual-recovery packages without explicit override")
      (multiple-value-bind (manual-recovery-import-result manual-recovery-import-kind manual-recovery-import-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(platform/import-package ,manual-recovery-path :allow-manual-recovery t))
           provider
           session)
        (declare (ignore manual-recovery-import-session))
        (assert-equal :platform-import-package manual-recovery-import-kind
                      "platform/import-package should dispatch explicit recovery overrides")
        (assert-equal t (getf (getf manual-recovery-import-result :package) :manual-recovery-p)
                      "platform/import-package should preserve manual-recovery posture after override")))
    (multiple-value-bind (audit-result audit-kind audit-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(platform/audit))
         provider
         session)
      (declare (ignore audit-session))
      (assert-equal :platform-audit audit-kind
                    "platform/audit should dispatch correctly after override-granted imports")
      (assert-true (>= (getf audit-result :override-count) 3)
                   "platform/audit should count override-granted imports across lifecycle, trust, and recovery posture")
      (assert-equal 1 (getf audit-result :untrusted-count)
                    "platform/audit should count untrusted imported packages")
      (assert-equal 1 (getf audit-result :deprecated-count)
                    "platform/audit should count deprecated imported packages")
      (assert-equal 1 (getf audit-result :manual-recovery-count)
                    "platform/audit should count manual-recovery imported packages"))))

(defun session-summary-prefers-environment-summary-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/describe-session-environment/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/describe-session-environment/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::approve-policy session :runtime-eval-mutate)
    (sbcl-agent::update-session-plan session "Environment-governed plan")
    (sbcl-agent::stage-pending-actions
     session
     (list (sbcl-agent::make-assistant-action :type :eval
                                              :payload '(:code "(+ 1 1)" :language :lisp))))
    (sbcl-agent::sync-environment-from-session environment session)
    (setf (sbcl-agent::agent-session-plan session) nil
          (sbcl-agent::agent-session-capability-grants session) '()
          (sbcl-agent::agent-session-capability-grants-tail session) nil
          (sbcl-agent::agent-session-pending-actions session) '())
    (let ((summary (sbcl-agent::session-summary session)))
      (assert-equal "Environment-governed plan"
                    (getf summary :plan)
                    "session-summary should prefer the environment-owned plan")
      (assert-equal 1
                    (getf summary :pending-action-count)
                    "session-summary should prefer environment-owned pending action counts")
      (assert-true (listp (getf summary :alignment-state))
                   "session-summary should carry environment-backed alignment state")
      (assert-true (listp (getf summary :reconciliation-decision))
                   "session-summary should carry environment-backed reconciliation direction")
      (assert-true (find :runtime-eval-mutate
                         (getf summary :approved-policies)
                         :test #'eq)
                   "session-summary should prefer environment-owned approved policy state"))))

(defun session-summary-prefers-environment-event-summary-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/session-summary-environment-events/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/session-summary-environment-events/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::append-transcript-entry session :user "event authority")
    (let ((environment-event-summary (getf (sbcl-agent::environment-summary environment) :event-summary)))
      (setf (sbcl-agent::agent-session-events session) '()
            (sbcl-agent::agent-session-events-tail session) nil)
      (let ((summary (sbcl-agent::session-summary session)))
      (assert-equal (getf environment-event-summary :event-count)
                      (getf (getf summary :event-summary) :event-count)
                      "session-summary should prefer environment-backed event counts")
        (assert-true (find :transcript
                           (getf (getf summary :event-summary) :recent-kinds)
                           :test #'eq)
                     "session-summary should preserve environment-backed recent event kinds")
        (assert-true (listp (getf summary :operator-evidence))
                     "session-summary should expose consolidated operator evidence when bound to an environment")))))

(defun environment-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (path "/tmp/sbcl-agent-shell-environment.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/shell-environment-root/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/shell-environment-root/"
                       :session session)))
    (declare (ignore environment))
    (sbcl-agent::update-session-plan session "Environment persistence")
    (multiple-value-bind (show-result show-kind shown-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(environment/show))
         provider
         session)
      (declare (ignore shown-session))
      (assert-equal :environment-show show-kind "environment/show should dispatch correctly")
      (assert-equal (sbcl-agent::agent-session-id session)
                    (getf show-result :session-id)
                    "environment/show should expose the compatibility session id")
      (assert-equal 0
                    (getf show-result :incident-count)
                    "environment/show should report incident counts")
      (assert-true (listp (getf show-result :runtime-state))
                   "environment/show should expose runtime-state summary data"))
    (sbcl-agent::append-session-event session :environment-test '(:ok t) :family :runtime)
    (multiple-value-bind (events-result events-kind events-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(environment/events :tail 1))
         provider
         session)
      (declare (ignore events-session))
      (assert-equal :environment-events events-kind
                    "environment/events should dispatch correctly")
      (assert-equal 1
                    (length (getf events-result :events))
                    "environment/events should honor the requested tail size")
      (assert-equal (sbcl-agent::environment-id (sbcl-agent::ensure-environment))
                    (getf (sbcl-agent::event-metadata (first (getf events-result :events))) :environment-id)
                    "environment/events should return projected environment events"))
    (multiple-value-bind (save-result save-kind saved-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(environment/save ,path))
         provider
         session)
      (declare (ignore saved-session))
      (assert-equal :environment-save save-kind "environment/save should dispatch correctly")
      (assert-equal path (getf save-result :saved)
                    "environment/save should report the saved path"))
    (let ((fresh-session (sbcl-agent::make-default-session :cwd "/tmp/fresh-environment-root/")))
      (sbcl-agent::make-default-environment
       :storage-root "/tmp/fresh-environment-root/"
       :session fresh-session))
    (multiple-value-bind (load-result load-kind loaded-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(environment/load ,path))
         provider
         (sbcl-agent::make-default-session))
      (assert-equal :environment-load load-kind "environment/load should dispatch correctly")
      (assert-equal path (getf load-result :loaded)
                    "environment/load should report the loaded path")
      (assert-equal "Environment persistence"
                    (sbcl-agent::agent-session-plan loaded-session)
                    "environment/load should restore the compatibility session plan")
      (assert-equal (sbcl-agent::agent-session-id loaded-session)
                    (getf (getf load-result :summary) :session-id)
                    "environment/load should summarize the loaded compatibility session")
      (multiple-value-bind (reloaded-events reloaded-kind reloaded-events-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(environment/events :tail 5))
           provider
           loaded-session)
        (declare (ignore reloaded-events-session))
        (assert-equal :environment-events reloaded-kind
                      "environment/events should remain available after environment/load")
        (assert-true (find :environment-test
                           (getf reloaded-events :events)
                           :key #'sbcl-agent::event-kind)
                     "environment/events should surface persisted projected events after load")
        (let ((event (find :environment-test
                           (getf reloaded-events :events)
                           :key #'sbcl-agent::event-kind)))
          (assert-equal (getf reloaded-events :environment-id)
                        (getf (sbcl-agent::event-metadata event) :environment-id)
                        "post-load environment/events should preserve environment-id metadata"))))))

(defun environment-load-shell-orientation-test ()
  (let* ((provider (make-test-provider))
         (path "/tmp/sbcl-agent-shell-environment-orientation.sexp")
         (session (sbcl-agent::make-default-session :cwd "/tmp/environment-load-orientation/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-load-orientation/"
                       :session session)))
    (declare (ignore environment))
    (sbcl-agent::create-work-item session "Orientation blocker" :transaction-scope :test)
    (sbcl-agent::save-environment (sbcl-agent::ensure-environment) path)
    (setf sbcl-agent::*current-session* nil
          sbcl-agent::*current-environment* nil)
    (multiple-value-bind (load-result load-kind loaded-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(environment/load ,path))
         provider
         (sbcl-agent::make-default-session))
      (assert-equal :environment-load load-kind
                    "environment/load should dispatch for orientation test")
      (assert-equal path (getf load-result :loaded)
                    "environment/load should report the loaded path")
      (multiple-value-bind (status-result status-kind status-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(environment/status))
           provider
           loaded-session)
        (declare (ignore status-session))
        (assert-equal :environment-status status-kind
                      "environment/status should remain available immediately after environment/load")
        (assert-equal (getf (getf load-result :summary) :id)
                      (getf (getf status-result :environment) :id)
                      "post-load environment/status should orient around the loaded environment")
        (assert-equal (sbcl-agent::agent-session-current-thread-id loaded-session)
                      (getf (getf status-result :active-thread) :id)
                      "post-load environment/status should orient around the loaded thread")))))

(defun shell-environment-orientation-render-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/shell-environment-orientation/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/shell-environment-orientation/"
                       :session session))
         (work-item (sbcl-agent::create-work-item session "Shell orientation blocker" :transaction-scope :test)))
    (sbcl-agent::request-work-item-approval session work-item :process-run :reason "Need approval")
    (sbcl-agent::bind-session-to-environment session environment)
    (multiple-value-bind (_ stdout stderr)
        (with-captured-output
          (lambda ()
            (sbcl-agent::print-shell-environment-orientation environment)
            (sbcl-agent::print-shell-workspace-startup-summary session environment)))
      (declare (ignore _ stderr))
      (assert-true (search "Environment:" stdout)
                   "shell environment orientation should print environment identity first")
      (assert-true (search "Orientation:" stdout)
                   "shell environment orientation should print active thread/runtime context")
      (assert-true (search "Operator posture:" stdout)
                   "shell environment orientation should print operator posture counts")
      (assert-true (search "Workspace:" stdout)
                   "shell workspace startup summary should print workspace counts")
      (assert-true (search "Workspace governance top:" stdout)
                   "shell workspace startup summary should print governance focus")
      (assert-true (search "Workspace governance open: (open :governance-index 0)" stdout)
                   "shell workspace startup summary should print the default governance open handoff"))))

(defun environment-load-rendering-test ()
  (let* ((summary (list :id "environment-load-test"
                        :session-id "session-load-test"
                        :operator-status (list :blocked-count 1
                                               :quarantined-count 0
                                               :incident-count 2
                                               :open-incident-count 1)))
         (workspace (list :inspector-focus-object-id "exec-123"))
         (result (list :loaded "/tmp/environment-load.sexp"
                       :summary summary
                       :workspace workspace)))
    (multiple-value-bind (_ stdout stderr)
        (with-captured-output
          (lambda ()
            (sbcl-agent::print-shell-result result :environment-load)))
      (declare (ignore _ stderr))
      (assert-true (search "environment-load>" stdout)
                   "environment-load rendering should print the loaded environment summary")
      (assert-true (search "environment-load-operator>" stdout)
                   "environment-load rendering should print operator posture for the loaded environment")
      (assert-true (search "environment-load-workspace-focus> exec-123" stdout)
                   "environment-load rendering should print workspace focus posture after load"))))

(defun environment-status-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (blocked (sbcl-agent::create-work-item session "Blocked status item" :transaction-scope :test)))
    (sbcl-agent::request-work-item-approval session blocked :process-run :reason "Need process approval")
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(environment/status))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :environment-status kind
                    "environment/status should dispatch correctly")
      (assert-equal (sbcl-agent::environment-id (sbcl-agent::ensure-environment))
                    (getf (getf result :environment) :id)
                    "environment/status should expose the active environment identity")
      (assert-equal (sbcl-agent::agent-session-current-thread-id session)
                    (getf (getf result :active-thread) :id)
                    "environment/status should expose the active thread")
      (assert-equal (sbcl-agent::agent-session-package session)
                    (getf (getf result :active-runtime) :package)
                    "environment/status should expose the active runtime package")
      (assert-equal 1
                    (getf (getf result :blocked-work) :count)
                    "environment/status should expose blocked work-item count")
      (assert-equal 1
                    (getf (getf result :operator-posture) :outstanding-approval-count)
                    "environment/status should summarize outstanding approvals")
      (assert-true (listp (getf result :operator-evidence))
                   "environment/status should expose consolidated operator evidence")
      (assert-true (member :execution-surfaces result)
                   "environment/status should expose the execution surface field")
      (assert-true (listp (getf result :execution-surfaces))
                   "environment/status should expose execution surfaces as a plist payload")
      (assert-equal 1
                    (getf (getf result :blocked-work-surfaces) :count)
                    "environment/status should expose one blocked-work surface in the approval case")
      (assert-equal 1
                    (getf (getf result :approval-surfaces) :count)
                    "environment/status should expose one approval surface in the approval case")
      (assert-equal (getf (getf result :operator-posture) :blocked-count)
                    (getf (getf (getf result :operator-evidence) :posture) :blocked-count)
                    "environment/status operator evidence should align with rendered posture"))))

(defun environment-status-incident-summary-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-command
        (sbcl-agent::normalize-form-command '(runtime/eval "(error \"environment status incident\")"))
        provider
        session))
     "environment status incident"
     "test setup should create an incident for environment/status")
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(environment/status))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :environment-status kind
                    "environment/status should still dispatch after runtime incidents")
      (assert-equal 1
                    (getf (getf result :incidents) :open-count)
                    "environment/status should summarize open incidents")
      (assert-equal 1
                    (getf (getf result :operator-posture) :open-incident-count)
                    "environment/status should carry operator incident posture")
      (assert-equal 0
                    (getf (getf result :approval-surfaces) :count)
                    "environment/status should not invent approval surfaces for incident-only posture"))))

(defun environment-status-blocked-work-summary-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (approval-item (sbcl-agent::create-work-item session "Approval item" :transaction-scope :test))
         (review-item (sbcl-agent::create-work-item session "Review item" :transaction-scope :test))
         (cold-item (sbcl-agent::create-work-item session "Cold item" :transaction-scope :test)))
    (sbcl-agent::request-work-item-approval session approval-item :process-run :reason "Need operator approval")
    (sbcl-agent::quarantine-work-item session review-item "Review required")
    (setf (sbcl-agent::work-item-status cold-item) :awaiting-cold-validation
          (sbcl-agent::work-item-pending-validations cold-item) '(:cold))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(environment/status))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :environment-status kind
                    "environment/status should dispatch for blocked summary analysis")
      (assert-equal 3
                    (getf (getf result :blocked-work) :count)
                    "environment/status should count all blocked work items")
      (assert-equal 1
                    (getf (getf result :blocked-work) :approval-count)
                    "environment/status should count approval blockers")
      (assert-equal 1
                    (getf (getf result :blocked-work) :operator-review-count)
                    "environment/status should count operator review blockers")
      (assert-equal 1
                    (getf (getf result :blocked-work) :cold-validation-count)
                    "environment/status should count cold validation blockers")
      (assert-equal 3
                    (getf (getf result :blocked-work-surfaces) :count)
                    "environment/status should expose all blocked governed-work/workflow surfaces")
      (assert-equal 1
                    (getf (getf result :approval-surfaces) :count)
                    "environment/status should keep the approval subset surface queue separate"))))

(defun runtime-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session)))
    (multiple-value-bind (package-result package-kind package-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/current-package))
         provider
         session)
      (declare (ignore package-session))
      (assert-equal :runtime-current-package package-kind
                    "runtime/current-package should report its command kind")
      (assert-equal :runtime/current-package (getf package-result :tool)
                    "runtime/current-package should dispatch through the runtime tool surface")
      (assert-equal "SBCL-AGENT-USER" (getf package-result :package)
                    "runtime/current-package should report the current session package"))
    (multiple-value-bind (systems-result systems-kind systems-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/list-loaded-systems))
         provider
         session)
      (declare (ignore systems-session))
      (assert-equal :runtime-list-loaded-systems systems-kind
                    "runtime/list-loaded-systems should report its command kind")
      (assert-equal :runtime/list-loaded-systems (getf systems-result :tool)
                    "runtime/list-loaded-systems should dispatch through the runtime tool surface")
      (assert-true (find "sbcl-agent" (getf systems-result :systems) :test #'string=)
                   "runtime/list-loaded-systems should include the current system"))
    (multiple-value-bind (symbol-result symbol-kind symbol-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/describe-symbol "CAR" :package "COMMON-LISP"))
         provider
         session)
      (declare (ignore symbol-session))
      (assert-equal :runtime-describe-symbol symbol-kind
                    "runtime/describe-symbol should report its command kind")
      (assert-equal :runtime/describe-symbol (getf symbol-result :tool)
                    "runtime/describe-symbol should dispatch through the runtime tool surface")
      (assert-equal "CAR" (getf symbol-result :symbol)
                    "runtime/describe-symbol should describe the requested symbol")
      (assert-true (getf symbol-result :fboundp)
                   "runtime/describe-symbol should report function bindings"))
    (multiple-value-bind (definition-result definition-kind definition-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/find-definition "runtime-shell-commands-test"))
         provider
         session)
      (declare (ignore definition-session))
      (assert-equal :runtime-find-definition definition-kind
                    "runtime/find-definition should report its command kind")
      (assert-equal :runtime/find-definition (getf definition-result :tool)
                    "runtime/find-definition should dispatch through the runtime tool surface")
      (assert-true (>= (getf definition-result :definition-count) 1)
                   "runtime/find-definition should find source definitions inside the workspace"))
    (multiple-value-bind (method-result method-kind method-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/methods "PRINT-OBJECT" :package "COMMON-LISP"))
         provider
         session)
      (declare (ignore method-session))
      (assert-equal :runtime-methods method-kind
                    "runtime/methods should report its command kind")
      (assert-equal :runtime/methods (getf method-result :tool)
                    "runtime/methods should dispatch through the runtime tool surface")
      (assert-true (> (getf method-result :method-count) 0)
                   "runtime/methods should report generic function methods"))
    (multiple-value-bind (eval-result eval-kind eval-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/eval "(package-name *package*)"))
         provider
         session)
      (declare (ignore eval-session))
      (assert-equal :runtime-eval eval-kind
                    "runtime/eval should report its command kind")
      (assert-equal :runtime/eval (getf eval-result :tool)
                    "runtime/eval should dispatch through the runtime tool surface")
      (assert-equal "SBCL-AGENT-USER" (getf eval-result :result)
                    "runtime/eval should execute inside the current session package"))
    (multiple-value-bind (multi-form-result multi-form-kind multi-form-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command
          '(runtime/eval ";; Editor
;; Sustain source and form editing here without collapsing into scratch workspace posture.

(in-package :cl-user)
(* 3 (+ 4 4))"))
         provider
         session)
      (declare (ignore multi-form-session))
      (assert-equal :runtime-eval multi-form-kind
                    "multi-form runtime/eval should report its command kind")
      (assert-equal 24 (getf multi-form-result :result)
                    "multi-form runtime/eval should return the final form value, not an earlier package-switch result")
      (assert-equal "COMMON-LISP-USER" (getf multi-form-result :package)
                    "multi-form runtime/eval should report the final active package after in-package"))
    (multiple-value-bind (history-result history-kind history-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/history :tail 5))
         provider
         session)
      (declare (ignore history-session))
      (assert-equal :runtime-history history-kind
                    "runtime/history should report its command kind")
      (assert-equal :runtime/history (getf history-result :tool)
                    "runtime/history should dispatch through the runtime tool surface")
      (assert-true (>= (length (getf history-result :entries)) 1)
                   "runtime/history should return recent runtime entries"))))

(defun runtime-callers-test ()
  (let* ((provider (make-test-provider))
         (root (make-temporary-directory "/tmp/sbcl-agent-runtime-nav-XXXXXX"))
         (source (merge-pathnames "nav-target.lisp" (pathname (format nil "~A/" root))))
         (session (sbcl-agent::make-default-session :cwd (format nil "~A/" root))))
    (with-open-file (stream source :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-line "(in-package #:sbcl-agent-user)" stream)
      (write-line "(defun nav-target () :ok)" stream)
      (write-line "(defun nav-caller () (nav-target))" stream))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/callers "nav-target"))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :runtime-callers kind
                    "runtime/callers should dispatch correctly")
      (assert-equal :runtime/callers (getf result :tool)
                    "runtime/callers should dispatch through the runtime tool surface")
      (assert-true (>= (getf result :caller-count) 2)
                   "runtime/callers should report source references for the requested symbol"))))

(defun runtime-find-definition-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/find-definition "runtime-find-definition-test"))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :runtime-find-definition kind
                    "runtime/find-definition should dispatch correctly")
      (assert-true (> (getf result :definition-count) 0)
                   "runtime/find-definition should find definitions in the workspace")
      (assert-true (find "tests/smoke.lisp"
                         (getf result :definitions)
                         :key (lambda (entry) (getf entry :path))
                         :test #'search)
                   "runtime/find-definition should report definition locations"))))

(defun runtime-methods-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/methods "PRINT-OBJECT" :package "COMMON-LISP"))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :runtime-methods kind
                    "runtime/methods should dispatch correctly")
      (assert-equal :generic-function
                    (getf (getf result :runtime-presence) :function-kind)
                    "runtime/methods should identify generic functions")
      (assert-true (> (getf result :method-count) 0)
                   "runtime/methods should report generic function methods"))))

(defun runtime-source-image-divergence-test ()
  (let* ((provider (make-test-provider))
         (root (make-temporary-directory "/tmp/sbcl-agent-runtime-divergence-XXXXXX"))
         (source (merge-pathnames "divergence-target.lisp" (pathname (format nil "~A/" root))))
         (session (sbcl-agent::make-default-session :cwd (format nil "~A/" root))))
    (with-open-file (stream source :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-line "(in-package #:sbcl-agent-user)" stream)
      (write-line "(defun divergence-source-only () :source)" stream))
    (multiple-value-bind (source-result source-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/source-image-divergence "divergence-source-only"))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :runtime-source-image-divergence source-kind
                    "runtime/source-image-divergence should dispatch correctly")
      (assert-equal :source-only (getf source-result :divergence)
                    "runtime/source-image-divergence should report source-only symbols"))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command
      '(runtime/eval "(progn (defun divergence-runtime-only () :runtime) #'divergence-runtime-only)" :mutating t))
     provider
     session)
    (multiple-value-bind (runtime-result runtime-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/source-image-divergence "divergence-runtime-only"))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :runtime-source-image-divergence runtime-kind
                    "runtime/source-image-divergence should remain available after runtime mutation")
      (assert-equal :runtime-only (getf runtime-result :divergence)
                    "runtime/source-image-divergence should report runtime-only symbols"))))

(defun runtime-package-switch-approval-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session)))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-command
        (sbcl-agent::normalize-form-command '(runtime/set-package "COMMON-LISP"))
        provider
        session))
     "Approval required for :RUNTIME-PACKAGE-SWITCH"
     "runtime/set-package should require explicit approval")
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-package-switch))
     provider
     session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/set-package "COMMON-LISP"))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :runtime-set-package kind
                    "runtime/set-package should report its command kind")
      (assert-equal "COMMON-LISP" (getf result :package)
                    "runtime/set-package should switch the active session package")
      (assert-equal 1 (length (sbcl-agent::agent-session-artifacts session))
                    "runtime/set-package should create a runtime artifact")
      (assert-equal "COMMON-LISP" (sbcl-agent::agent-session-package session)
                    "runtime/set-package should mutate the active session package"))))

(defun runtime-mutating-eval-approval-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session)))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-command
        (sbcl-agent::normalize-form-command
         '(runtime/eval "(progn (setf sbcl-agent-user::*structured-runtime-flag* :set) sbcl-agent-user::*structured-runtime-flag*)" :mutating t))
        provider
        session))
     "Approval required for :RUNTIME-EVAL-MUTATE"
     "mutating runtime/eval should require explicit approval")
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command
          '(runtime/eval "(progn (defparameter sbcl-agent-user::*structured-runtime-flag* nil) (setf sbcl-agent-user::*structured-runtime-flag* :set) sbcl-agent-user::*structured-runtime-flag*)" :mutating t))
         provider
         session)
      (declare (ignore updated-session))
      (let ((work-item (sbcl-agent::find-work-item session (getf result :work-item-id))))
        (assert-equal :runtime-eval kind
                      "mutating runtime/eval should report its command kind")
        (assert-equal :runtime-eval-mutate (getf result :policy-id)
                      "mutating runtime/eval should record runtime-eval-mutate policy")
        (assert-equal :set (getf result :result)
                      "mutating runtime/eval should return the evaluated result")
        (assert-equal 1 (length (sbcl-agent::agent-session-artifacts session))
                      "mutating runtime/eval should create a runtime artifact")
        (assert-true (stringp (getf result :work-item-id))
                     "mutating runtime/eval should return the created work-item id")
        (assert-true work-item
                     "mutating runtime/eval should create a persisted work-item")
        (assert-equal :awaiting-cold-validation (sbcl-agent::work-item-status work-item)
                      "mutating runtime/eval should stop at awaiting-cold-validation until colder evidence exists")
        (assert-true (member :cold (sbcl-agent::work-item-pending-validations work-item))
                     "mutating runtime/eval should leave cold validation pending")
        (assert-equal :awaiting-cold-validation
                      (sbcl-agent::workflow-record-status
                       (sbcl-agent::work-item-workflow-record session work-item))
                      "mutating runtime/eval should leave the workflow record awaiting cold validation")
        (assert-equal 1 (length (sbcl-agent::work-item-checkpoints work-item))
                      "mutating runtime/eval should capture a work-item checkpoint")
        (assert-true (>= (length (sbcl-agent::work-item-runtime-observations work-item)) 2)
                     "mutating runtime/eval should append runtime observations to the work-item")))))

(defun runtime-reload-file-approval-and-workflow-test ()
  (let* ((provider (make-test-provider))
         (root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-runtime-reload-~D-~D/"
                        (get-universal-time)
                        (random 1000000))))
         (ignore (ensure-directories-exist root))
         (path (merge-pathnames #P"reload-target.lisp" root))
         (session (sbcl-agent::make-default-session :cwd (namestring root))))
    (declare (ignore ignore))
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-line "(in-package #:sbcl-agent-user)" stream)
      (write-line "(defun reloaded-runtime-target () :reloaded-ok)" stream))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-command
        (sbcl-agent::normalize-form-command '(runtime/reload-file "reload-target.lisp"))
        provider
        session))
     "Approval required for :RUNTIME-RELOAD"
     "runtime/reload-file should require explicit approval")
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-reload))
     provider
     session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(runtime/reload-file "reload-target.lisp"))
         provider
         session)
      (declare (ignore updated-session))
      (let ((work-item (sbcl-agent::find-work-item session (getf result :work-item-id))))
        (assert-equal :runtime-reload-file kind
                      "runtime/reload-file should report its command kind")
        (assert-equal :runtime/reload-file (getf result :tool)
                      "runtime/reload-file should dispatch through the runtime tool surface")
        (assert-true (fboundp 'sbcl-agent-user::reloaded-runtime-target)
                     "runtime/reload-file should load definitions into the live image")
        (assert-equal :reloaded-ok
                      (funcall (symbol-function 'sbcl-agent-user::reloaded-runtime-target))
                      "runtime/reload-file should make the loaded definition callable")
        (assert-true (stringp (getf result :work-item-id))
                     "runtime/reload-file should return a workflow work-item id")
        (assert-true work-item
                     "runtime/reload-file should create a persisted work-item")
        (assert-equal :awaiting-cold-validation (sbcl-agent::work-item-status work-item)
                      "runtime/reload-file should stop at awaiting-cold-validation until colder evidence exists")
        (assert-equal :awaiting-cold-validation (sbcl-agent::work-item-closure-decision work-item)
                      "runtime/reload-file should not claim durable closure before cold validation runs")
        (assert-true (member :cold (sbcl-agent::work-item-pending-validations work-item))
                     "runtime/reload-file should leave cold validation pending")
        (assert-equal 1 (length (sbcl-agent::work-item-checkpoints work-item))
                      "runtime/reload-file should capture a checkpoint")
        (assert-true (>= (length (sbcl-agent::work-item-runtime-observations work-item)) 2)
                     "runtime/reload-file should append runtime observations")
        (assert-true (find :runtime-reload
                           (sbcl-agent::agent-session-artifacts session)
                           :key #'sbcl-agent::artifact-kind)
                     "runtime/reload-file should create a runtime reload artifact")))))

(defun runtime-eval-incident-recording-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session)))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-command
        (sbcl-agent::normalize-form-command '(runtime/eval "(error \"incident from direct runtime eval\")"))
        provider
        session))
     "incident from direct runtime eval"
     "failing runtime/eval should still surface the original error")
    (multiple-value-bind (list-result list-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(incident/list))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :incident-list list-kind
                    "incident/list should dispatch through the shell command surface")
      (assert-equal 1 (length list-result)
                    "failing direct runtime/eval should create one incident")
      (let* ((incident-summary (first list-result))
             (incident-id (getf incident-summary :id)))
        (assert-true (stringp incident-id)
                     "incident/list should expose incident ids")
        (assert-true (member :primary-execution-handle incident-summary :test #'eq)
                     "incident/list should expose a primary execution handle field")
        (multiple-value-bind (incident-result incident-kind incident-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(incident/show ,incident-id))
             provider
             session)
          (declare (ignore incident-session))
          (assert-equal :incident-show incident-kind
                        "incident/show should dispatch through the shell command surface")
          (assert-equal :runtime-eval-failure (getf incident-result :kind)
                        "failing runtime/eval should record a runtime-eval-failure incident")
          (assert-true (search "incident from direct runtime eval"
                               (getf incident-result :condition))
                       "incident/show should expose the runtime condition text")
          (assert-true (member :primary-execution-handle incident-result :test #'eq)
                       "incident/show should expose a primary execution handle field")
          (assert-equal "incident"
                        (getf (getf incident-result :execution-surface) :surface-kind)
                        "incident/show should expose the incident execution surface")
          (assert-true (listp (getf incident-result :thread))
                       "incident/show should expose linked thread context")
          (assert-equal (sbcl-agent::agent-session-current-thread-id session)
                        (getf (getf incident-result :thread) :id)
                        "incident/show should link the incident back to the active thread")
          (assert-true (listp (getf incident-result :recovery))
                       "incident/show should expose compact turn recovery context when a turn is linked")
          (assert-equal 0
                        (or (getf (getf incident-result :recovery) :resumable-operation-count) 0)
                        "direct runtime incidents should not invent resumable operations")
          (assert-equal nil
                        (getf incident-result :operation)
                        "direct runtime incidents should not invent operation links"))))))

(defun turn-resume-runtime-incident-quarantine-test ()
  (let ((provider (make-instance 'failing-mutating-eval-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "trigger a failing governed runtime mutation"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (multiple-value-bind (resume-result resume-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :turn-resume resume-kind
                    "turn/resume should still return a structured result when a governed action fails")
      (assert-equal 1 (getf resume-result :resumed-operation-count)
                    "turn/resume should report the resumed failing operation"))
    (multiple-value-bind (turn-result turn-kind turn-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/status))
         provider
         session)
      (declare (ignore turn-session))
      (assert-equal :turn-status turn-kind
                    "turn/status should remain available after a runtime incident")
      (assert-equal :failed (getf turn-result :status)
                    "a failing resumed runtime mutation should fail the turn")
      (assert-equal 1 (length (getf turn-result :incidents))
                    "the failed turn should expose one linked incident")
      (assert-equal 1
                    (getf (getf turn-result :detail-summary) :incident-count)
                    "turn/detail summary should count linked incidents")
      (let* ((incident (first (getf turn-result :incidents)))
             (incident-id (getf incident :id))
             (work-item-id (getf incident :work-item-id))
             (work-item (sbcl-agent::find-work-item session work-item-id)))
        (assert-equal :runtime-eval-failure (getf incident :kind)
                      "failed resumed runtime eval should record a runtime-eval-failure incident")
        (assert-true (stringp incident-id)
                     "incident ids should be durable on failed turns")
        (assert-true (search "runtime incident boom" (getf incident :condition))
                     "incident detail should preserve the original runtime condition")
        (assert-true work-item
                     "the failed governed turn should still reference its work-item")
        (assert-equal :quarantined (sbcl-agent::work-item-status work-item)
                      "failed governed runtime mutations should quarantine the bound work-item")
        (multiple-value-bind (incident-result incident-kind incident-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(incident/show ,incident-id))
             provider
             session)
          (declare (ignore incident-session))
          (assert-equal :incident-show incident-kind
                        "incident/show should remain available for governed incident analysis")
          (assert-equal (getf incident :turn-id)
                        (getf (getf incident-result :turn) :id)
                        "incident/show should link governed incidents back to the failed turn")
          (assert-equal (getf incident :operation-id)
                        (getf (getf incident-result :operation) :id)
                        "incident/show should link governed incidents back to the failed operation")
          (assert-equal work-item-id
                        (getf (getf incident-result :work-item) :id)
                        "incident/show should link governed incidents back to the bound work-item")
          (assert-true (listp (getf incident-result :wait))
                       "incident/show should expose the bound work-item wait report")
          (assert-equal :operator-review-required
                        (getf (getf incident-result :wait) :why)
                        "quarantined governed incidents should explain the operator wait reason")
          (assert-true (listp (getf incident-result :recommended-actions))
                       "incident/show should expose deterministic next actions")
          (assert-true (find :work-item-next-action
                             (mapcar (lambda (action) (getf action :type))
                                     (getf incident-result :recommended-actions)))
                       "incident/show should recommend the bound work-item next action")
          (assert-true (listp (getf incident-result :workflow-record))
                       "incident/show should expose linked workflow context for governed incidents"))))))

(defun incident-workspace-runtime-context-test ()
  (let ((provider (make-instance 'failing-mutating-eval-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "trigger a failing governed runtime mutation"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (let* ((incident-id (getf (first (sbcl-agent::list-incident-summaries session)) :id)))
      (multiple-value-bind (result kind updated-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(incident/show ,incident-id))
           provider
           session)
        (declare (ignore updated-session))
        (assert-equal :incident-show kind
                      "incident/show should dispatch for runtime context analysis")
        (assert-true (listp (getf result :runtime-context))
                     "incident/show should expose richer runtime context")
        (assert-equal "SBCL-AGENT-USER"
                      (getf (getf result :runtime-context) :package)
                      "incident runtime context should expose the active runtime package")
        (assert-true (> (getf (getf result :runtime-context) :runtime-observation-count) 0)
                     "incident runtime context should expose work-item observations")
        (assert-true (listp (getf (getf result :runtime-context) :recent-runtime-history))
                     "incident runtime context should expose recent runtime history")))))

(defun incident-recommended-recovery-test ()
  (let ((provider (make-instance 'failing-mutating-eval-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "trigger a failing governed runtime mutation"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (let* ((incident-id (getf (first (sbcl-agent::list-incident-summaries session)) :id)))
      (multiple-value-bind (result kind updated-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command `(incident/show ,incident-id))
           provider
           session)
        (declare (ignore updated-session))
        (assert-equal :incident-show kind
                      "incident/show should dispatch for recovery planning analysis")
        (assert-true (listp (getf result :recovery-plan))
                     "incident/show should expose a structured recovery plan")
        (assert-equal :operator-review-required
                      (getf (getf result :recovery-plan) :wait-reason)
                      "incident recovery plan should expose the governing wait reason")
        (assert-true (find :inspect-runtime-context
                           (mapcar (lambda (entry) (getf entry :type))
                                   (getf (getf result :recovery-plan) :actions)))
                     "incident recovery plan should recommend runtime-context inspection")
        (assert-true (find :work-item-next-action
                           (mapcar (lambda (entry) (getf entry :type))
                                   (getf result :recommended-actions)))
                     "incident recommended actions should still surface the work-item next action")))))

(defun incident-recovery-artifact-test ()
  (let ((provider (make-instance 'failing-mutating-eval-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "trigger a failing governed runtime mutation"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (assert-true (find :plan
                       (sbcl-agent::agent-session-artifacts session)
                       :key #'sbcl-agent::artifact-kind)
                 "runtime incidents with actionable recovery should create a recovery-plan artifact")
    (let ((artifact (find :plan
                          (sbcl-agent::agent-session-artifacts session)
                          :key #'sbcl-agent::artifact-kind)))
      (assert-equal :incident-recovery-plan
                    (getf (sbcl-agent::artifact-metadata artifact) :source)
                    "recovery-plan artifacts should be tagged with incident-recovery-plan source")
      (assert-true (stringp (getf (sbcl-agent::artifact-metadata artifact) :incident-id))
                   "recovery-plan artifacts should link back to the source incident"))))

(defun incident-aware-session-and-environment-summary-test ()
  (let ((provider (make-test-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-command
        (sbcl-agent::normalize-form-command '(runtime/eval "(error \"summary incident\")"))
        provider
        session))
     "summary incident"
     "test setup should create a runtime incident")
    (let* ((session-summary (sbcl-agent::session-summary session))
           (environment-summary (sbcl-agent::environment-summary)))
      (assert-equal 1
                    (getf session-summary :incident-count)
                    "session-summary should expose total incident count")
      (assert-equal 1
                    (getf (getf session-summary :incident-summary) :open-count)
                    "session-summary should expose open incident count")
      (assert-equal 1
                    (getf (getf session-summary :operator-status) :incident-count)
                    "session operator status should surface incident totals")
      (assert-equal 1
                    (getf environment-summary :incident-count)
                    "environment-summary should surface incident totals")
      (assert-equal 1
                    (getf (getf environment-summary :incident-summary) :open-count)
                    "environment-summary should expose open incident count")
      (let ((provider-summary (sbcl-agent::provider-session-summary session)))
        (assert-equal 1
                      (getf provider-summary :incident-count)
                      "provider-session-summary should carry incident totals")
        (assert-equal 1
                      (getf provider-summary :open-incident-count)
                      "provider-session-summary should carry open incident totals")))))

(defun non-thread-validation-artifact-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Non-thread validation artifact" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let ((validator-id (sbcl-agent::validator-task-record-id
                         (first (sbcl-agent::work-item-validator-tasks work-item)))))
      (sbcl-agent::execute-validator-task-record session work-item validator-id :status :passed)
      (let ((artifact (find :validation
                            (sbcl-agent::agent-session-artifacts session)
                            :key #'sbcl-agent::artifact-kind)))
        (assert-true artifact
                     "validator execution should create a validation artifact even outside a conversation turn")
        (assert-equal nil
                      (sbcl-agent::artifact-turn-id artifact)
                      "non-thread validation artifacts should not require a turn binding")
        (assert-true (stringp (sbcl-agent::artifact-thread-id artifact))
                     "non-thread validation artifacts should still anchor into the session evidence stream")))))

(defun environment-level-evidence-summary-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (environment (sbcl-agent::make-default-environment
                       :storage-root (current-workspace-root)
                       :session session))
         (work-item (sbcl-agent::create-work-item session "Environment evidence summary" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let ((validator-id (sbcl-agent::validator-task-record-id
                         (first (sbcl-agent::work-item-validator-tasks work-item)))))
      (sbcl-agent::execute-validator-task-record session work-item validator-id :status :passed))
    (sbcl-agent::mark-work-item-image-only session work-item :reason "Environment evidence image-only")
    (sbcl-agent::reconcile-image-only-work-item-to-source session work-item "Attached source evidence")
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((summary (sbcl-agent::environment-summary))
           (artifact-summary (getf summary :artifact-summary)))
      (assert-true (listp artifact-summary)
                   "environment-summary should expose artifact evidence summaries")
      (assert-true (> (getf artifact-summary :validation-count) 0)
                   "environment-summary should count validation artifacts")
      (assert-true (> (getf artifact-summary :reconciliation-count) 0)
                   "environment-summary should count reconciliation artifacts")
      (assert-true (find :validation
                         (getf artifact-summary :kind-counts)
                         :key (lambda (entry) (getf entry :kind))
                         :test #'eq)
                   "environment-summary should expose validation artifact kinds"))))

(defun environment-native-artifact-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-native-artifacts/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-native-artifacts/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let ((artifact (sbcl-agent::create-environment-artifact
                     session
                     :validation
                     nil
                     :title "Cold validation pending"
                     :summary "Validation evidence attached to the environment."
                     :metadata '(:source :environment-test))))
      (let ((summary (sbcl-agent::environment-summary environment)))
        (assert-equal nil
                      (sbcl-agent::artifact-thread-id artifact)
                      "environment-native artifacts should not require thread ownership")
        (assert-equal nil
                      (sbcl-agent::artifact-turn-id artifact)
                      "environment-native artifacts should not require turn ownership")
        (assert-equal :environment
                      (getf (sbcl-agent::artifact-metadata artifact) :ownership)
                      "environment-native artifacts should be marked with environment ownership")
        (assert-equal 1
                      (getf summary :artifact-count)
                      "environment-summary should count environment-native artifacts")
        (assert-equal 1
                      (getf (getf summary :artifact-summary) :validation-count)
                      "environment-summary should classify environment-native validation artifacts")
        (assert-equal (sbcl-agent::artifact-id artifact)
                      (getf (first (sbcl-agent::environment-artifact-index environment)) :id)
                      "environment artifact index should retain environment-native artifact references")))))

(defun environment-artifact-summary-prefers-environment-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-artifact-summary-authority/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-artifact-summary-authority/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-environment-artifact
     session
     :validation
     nil
     :title "Authoritative environment artifact"
     :summary "Environment conversation state should own artifact evidence summary.")
    (setf (sbcl-agent::agent-session-artifacts session) '()
          (sbcl-agent::agent-session-artifacts-tail session) nil)
    (let* ((summary (sbcl-agent::environment-summary environment))
           (artifact-summary (getf summary :artifact-summary)))
      (assert-equal 1
                    (getf summary :artifact-count)
                    "environment-summary should keep artifact count from environment conversation state")
      (assert-equal 1
                    (getf artifact-summary :validation-count)
                    "environment-summary should keep validation counts from environment conversation state"))))

(defun provider-artifact-summary-prefers-environment-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/provider-artifact-summary-authority/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/provider-artifact-summary-authority/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-environment-artifact
     session
     :reconciliation
     nil
     :title "Provider artifact authority"
     :summary "Provider summaries should use environment-native artifact aggregates.")
    (setf (sbcl-agent::agent-session-artifacts session) '()
          (sbcl-agent::agent-session-artifacts-tail session) nil)
    (let ((provider-session-summary (sbcl-agent::provider-session-summary session))
          (provider-workspace-summary (sbcl-agent::provider-workspace-summary session)))
      (assert-equal 1
                    (getf (getf provider-session-summary :artifact-summary) :reconciliation-count)
                    "provider-session-summary should use the environment-native artifact summary")
      (assert-equal 1
                    (getf (getf provider-workspace-summary :artifact-summary) :reconciliation-count)
                    "provider-workspace-summary should use the environment-native artifact summary"))))

(defun artifact-inspection-prefers-environment-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/environment-artifact-inspection/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/environment-artifact-inspection/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (let* ((thread (sbcl-agent::current-thread session))
           (user-message (sbcl-agent::create-message session thread :user "artifact authority"))
           (turn (sbcl-agent::start-turn session thread user-message))
           (artifact (sbcl-agent::create-artifact session
                                                  thread
                                                  turn
                                                  nil
                                                  :validation
                                                  "tmp/evidence.txt"
                                                  :title "Environment-owned artifact"
                                                  :summary "Artifact lookup should prefer environment state."))
           (artifact-id (sbcl-agent::artifact-id artifact))
           (turn-id (sbcl-agent::turn-id turn))
           (thread-id (sbcl-agent::thread-id thread)))
      (setf (sbcl-agent::agent-session-artifacts session) '()
            (sbcl-agent::agent-session-artifacts-tail session) nil)
      (let ((found (sbcl-agent::find-artifact session artifact-id))
            (thread-artifacts (sbcl-agent::list-thread-artifacts session thread-id))
            (turn-artifacts (sbcl-agent::list-turn-artifacts session turn-id))
            (artifact-summary (sbcl-agent::session-artifact-summary session)))
        (assert-equal artifact-id
                      (sbcl-agent::artifact-id found)
                      "find-artifact should prefer environment-native artifact state when bound")
        (assert-equal 1 (length thread-artifacts)
                      "list-thread-artifacts should prefer environment-native artifact state when bound")
        (assert-equal artifact-id
                      (sbcl-agent::artifact-id (first thread-artifacts))
                      "list-thread-artifacts should return the environment-owned artifact")
        (assert-equal 1 (length turn-artifacts)
                      "list-turn-artifacts should prefer environment-native artifact state when bound")
        (assert-equal artifact-id
                      (sbcl-agent::artifact-id (first turn-artifacts))
                      "list-turn-artifacts should return the environment-owned artifact")
        (assert-equal 1
                      (getf artifact-summary :validation-count)
                      "session-artifact-summary should resolve through environment-native artifact state")))))

(defun reconciliation-artifact-coverage-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (work-item (sbcl-agent::create-work-item session "Reconciliation artifact coverage" :transaction-scope :test)))
    (sbcl-agent::mark-work-item-image-only session work-item :reason "Coverage image-only")
    (sbcl-agent::reconcile-image-only-work-item-to-source session work-item "Coverage source patch")
    (let ((session-summary (sbcl-agent::session-summary session)))
      (assert-true (find :reconciliation
                         (getf (getf session-summary :artifact-summary) :kind-counts)
                         :key (lambda (entry) (getf entry :kind))
                         :test #'eq)
                   "session-summary should expose reconciliation artifacts in the artifact summary")
      (assert-true (> (getf (getf session-summary :artifact-summary) :reconciliation-count) 0)
                   "session-summary should count reconciliation artifacts"))))

(defun turn-resume-mutating-runtime-eval-turn-evidence-test ()
  (let ((provider (make-instance 'mutating-eval-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "mutate runtime state through conversation"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (multiple-value-bind (turn-result turn-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/status))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :turn-status turn-kind
                    "turn/status should dispatch after mutating runtime eval resume")
      (assert-equal :completed (getf turn-result :status)
                    "mutating runtime eval resume should complete the turn")
      (assert-equal 1 (length (getf turn-result :artifacts))
                    "mutating runtime eval resume should attach a runtime artifact to the turn")
      (assert-equal 1
                    (getf (getf turn-result :detail-summary) :runtime-operation-count)
                    "turn/status should summarize runtime operation counts for runtime eval turns")
      (assert-equal 1
                    (getf (getf turn-result :detail-summary) :runtime-artifact-count)
                    "turn/status should summarize runtime artifact counts for runtime eval turns")
      (let ((eval-op (find "assistant-eval"
                           (getf turn-result :operations)
                           :key (lambda (entry) (getf entry :name))
                           :test #'string=)))
        (assert-true eval-op
                     "turn/status should expose the resumed assistant-eval operation")
        (assert-equal :completed (getf eval-op :status)
                      "assistant-eval operation should be completed after resume")
        (assert-true (stringp (getf (getf (getf eval-op :output) :result) :work-item-id))
                     "assistant-eval output should expose the bound work-item id")
        (assert-true (consp (getf (getf eval-op :metadata) :artifact-ids))
                     "assistant-eval metadata should expose linked artifact ids")
        (let ((work-item (sbcl-agent::find-work-item session
                                                     (getf (getf (getf eval-op :output) :result) :work-item-id))))
          (assert-equal :awaiting-cold-validation
                        (sbcl-agent::work-item-status work-item)
                        "conversation-driven mutating runtime eval should remain awaiting cold validation"))))))

(defun turn-resume-runtime-reload-turn-evidence-test ()
  (let* ((provider (make-instance 'runtime-reload-action-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (path (namestring (merge-pathnames #P"tmp/conversation-reload-target.lisp"
                                           (uiop:ensure-directory-pathname (current-workspace-root))))))
    (ensure-directories-exist path)
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-line "(in-package #:sbcl-agent-user)" stream)
      (write-line "(defun conversation-reloaded-runtime-target () :conversation-reloaded)" stream))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "reload runtime source through conversation"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-reload))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (multiple-value-bind (turn-result turn-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/status))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :turn-status turn-kind
                    "turn/status should dispatch after runtime reload resume")
      (assert-equal :completed (getf turn-result :status)
                    "runtime reload resume should complete the turn")
      (assert-equal 1 (length (getf turn-result :artifacts))
                    "runtime reload resume should attach a runtime artifact to the turn")
      (assert-equal 1
                    (getf (getf turn-result :detail-summary) :runtime-operation-count)
                    "turn/status should summarize runtime operation counts for reload turns")
      (assert-equal 1
                    (getf (getf turn-result :detail-summary) :runtime-artifact-count)
                    "turn/status should summarize runtime artifact counts for reload turns")
      (assert-true (fboundp 'sbcl-agent-user::conversation-reloaded-runtime-target)
                   "runtime reload resume should load the file into the live image")
      (assert-equal :conversation-reloaded
                    (funcall (symbol-function 'sbcl-agent-user::conversation-reloaded-runtime-target))
                    "runtime reload resume should make the loaded definition callable")
      (let ((reload-op (find "assistant-tool"
                             (getf turn-result :operations)
                             :key (lambda (entry) (getf entry :name))
                             :test #'string=)))
        (assert-true reload-op
                     "turn/status should expose the resumed assistant-tool operation")
        (assert-equal :completed (getf reload-op :status)
                      "assistant-tool operation should be completed after runtime reload resume")
        (assert-equal :runtime/reload-file
                      (getf (getf (getf reload-op :output) :result) :tool)
                      "assistant-tool output should expose the runtime reload result")
        (assert-true (stringp (getf (getf (getf reload-op :output) :result) :work-item-id))
                     "assistant-tool output should expose the bound work-item id")
        (assert-true (consp (getf (getf reload-op :metadata) :artifact-ids))
                     "assistant-tool metadata should expose linked artifact ids")
        (let ((work-item (sbcl-agent::find-work-item session
                                                     (getf (getf (getf reload-op :output) :result) :work-item-id))))
          (assert-equal :awaiting-cold-validation
                        (sbcl-agent::work-item-status work-item)
                        "conversation-driven runtime reload should remain awaiting cold validation"))))))

(defun mutation-review-command-test ()
  (let* ((provider (make-instance 'patch-action-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare patch"))
     provider
     session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(review/mutation))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :review-mutation kind
                    "review/mutation should dispatch correctly")
      (assert-equal :awaiting-approval
                    (getf (getf result :turn) :status)
                    "review/mutation should expose the current turn state")
      (assert-true (> (getf (getf result :mutation) :operation-count) 0)
                   "review/mutation should summarize at least one mutation-related operation")
      (assert-equal :approval-required
                    (getf (getf (getf result :governance) :wait) :why)
                    "review/mutation should expose the governing wait reason")
      (assert-equal "conversation"
                    (getf (getf (getf result :turn) :execution-surface) :surface-kind)
                    "review/mutation should expose the governed turn execution surface")
      (assert-true (listp (getf (getf result :governance) :next-action))
                   "review/mutation should expose a deterministic next action")
      (assert-true (consp (getf (getf result :turn) :execution-handles))
                   "review/mutation should expose execution-handle listings for the governed turn")
      (assert-true (member :primary-execution-handle
                           (getf (getf result :governance) :work-item))
                   "review/mutation should advertise the execution-handle field for governed work")
      (assert-equal "governed-work"
                    (getf (getf (getf result :governance) :work-item-surface) :surface-kind)
                    "review/mutation should expose the governed work execution surface")
      (assert-equal "workflow"
                    (getf (getf (getf result :governance) :workflow-record-surface) :surface-kind)
                    "review/mutation should expose the workflow execution surface"))))

(defun mutation-review-cold-validation-test ()
  (let* ((provider (make-instance 'runtime-reload-action-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (path (namestring (merge-pathnames #P"tmp/conversation-reload-target.lisp"
                                           (uiop:ensure-directory-pathname (current-workspace-root))))))
    (ensure-directories-exist path)
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-line "(in-package #:sbcl-agent-user)" stream)
      (write-line "(defun conversation-reloaded-runtime-target () :conversation-reloaded)" stream))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "reload runtime source through conversation"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-reload))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(review/mutation))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :review-mutation kind
                    "review/mutation should remain available after runtime reload resume")
      (assert-equal :awaiting-cold-validation
                    (getf (getf (getf result :governance) :work-item) :status)
                    "review/mutation should expose awaiting cold validation work-items")
      (assert-equal :cold-validation-required
                    (getf (getf (getf result :governance) :wait) :why)
                    "review/mutation should make cold validation blockers explicit")
      (assert-equal "governed-work"
                    (getf (getf (getf result :governance) :work-item-surface) :surface-kind)
                    "review/mutation should preserve the governed work surface through cold validation")
      (assert-equal 1
                    (getf (getf result :evidence) :checkpoint-count)
                    "review/mutation should expose captured checkpoint evidence")
      (assert-equal 1
                    (length (getf (getf result :evidence) :runtime-artifacts))
                    "review/mutation should surface runtime artifacts as evidence"))))

(defun mutation-review-incident-linked-test ()
  (let ((provider (make-instance 'failing-mutating-eval-provider))
        (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "trigger a failing governed runtime mutation"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(review/mutation))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :review-mutation kind
                    "review/mutation should dispatch for failed governed mutations")
      (assert-equal 1
                    (length (getf result :incidents))
                    "review/mutation should expose linked incidents")
      (assert-equal :operator-review-required
                    (getf (getf (getf result :governance) :wait) :why)
                    "review/mutation should expose operator review blockers after incidents")
      (assert-equal "incident"
                    (getf (getf (first (getf result :incidents)) :execution-surface) :surface-kind)
                    "review/mutation should expose compact incident execution surfaces")
      (assert-true (search "runtime incident boom"
                           (getf (first (getf result :incidents)) :condition))
                   "review/mutation should preserve the linked incident condition text"))))

(defun runtime-cold-validation-finalization-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session))
         (result (progn
                   (sbcl-agent::execute-command
                    (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
                    provider
                    session)
                   (nth-value
                    0
                    (sbcl-agent::execute-command
                     (sbcl-agent::normalize-form-command
                      '(runtime/eval "(progn (defparameter sbcl-agent-user::*cold-validation-finalize* nil) (setf sbcl-agent-user::*cold-validation-finalize* :ok) sbcl-agent-user::*cold-validation-finalize*)" :mutating t))
                     provider
                     session))))
         (work-item (sbcl-agent::find-work-item session (getf result :work-item-id)))
         (cold-validator (find :cold
                               (sbcl-agent::work-item-validator-tasks work-item)
                               :key #'sbcl-agent::validator-task-record-kind)))
    (assert-true cold-validator
                 "governed runtime mutations should create a cold validator task")
    (sbcl-agent::execute-validator-task-record session
                                               work-item
                                               (sbcl-agent::validator-task-record-id cold-validator)
                                               :status :passed)
    (assert-equal :committed
                  (sbcl-agent::work-item-status work-item)
                  "passing cold validation should promote the work-item to committed")
    (assert-equal :committed-to-image
                  (sbcl-agent::work-item-closure-decision work-item)
                  "passing cold validation should restore the final closure decision")
    (assert-equal :committed
                  (sbcl-agent::workflow-record-status
                   (sbcl-agent::work-item-workflow-record session work-item))
                  "passing cold validation should close the workflow record")))

(defun turn-recovery-persists-across-session-load-test ()
  (let* ((provider (make-instance 'patch-action-provider))
         (path (format nil "/tmp/sbcl-agent-turn-recovery-~D-~D.sexp"
                       (get-universal-time)
                       (random 1000000)))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare patch"))
     provider
     session)
    (sbcl-agent::save-session session path)
    (let ((loaded (sbcl-agent::load-session path)))
      (multiple-value-bind (turn-result turn-kind turn-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(turn/status))
           provider
           loaded)
        (declare (ignore turn-session))
        (assert-equal :turn-status turn-kind
                      "turn/status should dispatch after session reload")
        (assert-true (getf (getf turn-result :recovery) :resumable-p)
                     "turn/status should preserve recovery summary after session reload")
        (assert-true (getf (getf turn-result :recovery) :work-item-resume-payload)
                     "turn/status should preserve work-item resume payload after session reload")
        (assert-equal 1
                      (getf (getf turn-result :recovery) :resumable-operation-count)
                      "turn/status should preserve blocked resumable operation counts after session reload")))))

(defun interrupted-turn-state-recovered-on-session-load-test ()
  (let* ((path (format nil "/tmp/sbcl-agent-turn-interruption-~D-~D.sexp"
                       (get-universal-time)
                       (random 1000000)))
         (session (sbcl-agent::make-default-session))
         (thread (sbcl-agent::current-thread session))
         (user-message (sbcl-agent::create-message session thread :user "start long-running work"))
         (turn (sbcl-agent::start-turn session thread user-message :metadata '(:source :test)))
         (operation (sbcl-agent::start-operation session
                                                 thread
                                                 turn
                                                 :tool-call
                                                 "long-running-op"
                                                 '(:tool-id :proc/run)
                                                 :metadata '(:synthetic-test-p t))))
    (declare (ignore operation))
    (sbcl-agent::save-session session path)
    (let ((loaded (sbcl-agent::load-session path)))
      (multiple-value-bind (turn-result turn-kind turn-session)
          (sbcl-agent::execute-command
           (sbcl-agent::normalize-form-command '(turn/status))
           (make-test-provider)
           loaded)
        (declare (ignore turn-session))
        (assert-equal :turn-status turn-kind
                      "turn/status should dispatch for interrupted recovered turns")
        (assert-equal :interrupted
                      (getf turn-result :status)
                      "loading a session with an in-flight turn should mark the turn interrupted")
        (assert-true (getf (getf turn-result :recovery) :interrupted-p)
                     "turn recovery summary should flag interrupted recovered operations")
        (assert-equal 1
                      (getf (getf turn-result :recovery) :interrupted-operation-count)
                      "turn recovery summary should count interrupted operations")
        (let ((loaded-operation (first (getf turn-result :operations))))
          (assert-equal :interrupted
                        (getf loaded-operation :status)
                        "loading a session with an in-flight operation should mark the operation interrupted")
          (assert-true (getf (getf loaded-operation :metadata) :interrupted-during-load-p)
                       "interrupted recovered operations should carry recovery metadata"))))))

(defun list-tools-test ()
  (let ((tools (sbcl-agent::list-tools)))
    (assert-true (find :fs/read tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :fs/read")
    (assert-true (find :proc/run tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :proc/run")
    (assert-true (find :git/status tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :git/status")
    (assert-true (find :session/summary tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :session/summary")
    (assert-true (find :runtime/current-package tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :runtime/current-package")
    (assert-true (find :runtime/list-loaded-systems tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :runtime/list-loaded-systems")
    (assert-true (find :runtime/describe-symbol tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :runtime/describe-symbol")
    (assert-true (find :runtime/find-definition tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :runtime/find-definition")
    (assert-true (find :runtime/callers tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :runtime/callers")
    (assert-true (find :runtime/methods tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :runtime/methods")
    (assert-true (find :runtime/source-image-divergence tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :runtime/source-image-divergence")
    (assert-true (find :runtime/set-package tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :runtime/set-package")
    (assert-true (find :runtime/eval tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :runtime/eval")
    (assert-true (find :runtime/reload-file tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :runtime/reload-file")
    (assert-true (find :docs/read tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :docs/read")
    (assert-equal :process-run
                  (getf (sbcl-agent::describe-tool :proc/run) :isolation-profile)
                  "process tool should advertise a sandbox isolation profile")
    (assert-equal :git-read
                  (getf (sbcl-agent::describe-tool :git/status) :policy)
                  "git status should advertise git-read policy")
    (assert-equal :runtime-read
                  (getf (sbcl-agent::describe-tool :runtime/current-package) :policy)
                  "runtime package inspection should advertise runtime-read policy")
    (assert-equal :runtime-read
                  (getf (sbcl-agent::describe-tool :runtime/find-definition) :policy)
                  "runtime definition lookup should advertise runtime-read policy")
    (assert-equal :runtime-package-switch
                  (getf (sbcl-agent::describe-tool :runtime/set-package) :policy)
                  "runtime package switching should advertise runtime-package-switch policy")
    (assert-equal :runtime-eval-safe
                  (getf (sbcl-agent::describe-tool :runtime/eval) :policy)
                  "runtime eval should advertise runtime-eval-safe policy")
    (assert-equal :runtime-reload
                  (getf (sbcl-agent::describe-tool :runtime/reload-file) :policy)
                  "runtime reload should advertise runtime-reload policy")
    (assert-equal :safe-read
                  (getf (sbcl-agent::describe-tool :session/summary) :policy)
                  "session summary should advertise safe-read policy")))

(defun session-summary-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::update-session-plan session "Inspect runtime state")
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :session/summary))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :tool kind "session summary tool should dispatch as :tool")
      (assert-equal :session/summary (getf result :tool) "session summary tool should identify itself")
      (assert-equal "Inspect runtime state"
                    (getf (getf result :session) :plan)
                    "session summary tool should return the current session plan")
      (assert-equal 0
                    (getf (getf result :session) :incident-count)
                    "session summary tool should expose incident counts")
      (assert-true (listp (getf (getf result :session) :event-summary))
                   "session summary tool should expose event-backed evidence summary")
      (assert-true (listp (getf (getf result :session) :operator-evidence))
                   "session summary tool should expose consolidated operator evidence"))))

(defun session-summary-uses-environment-thread-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/tmp/session-summary-environment-thread/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/session-summary-environment-thread/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::create-thread session :title "Environment-owned summary thread")
    (sbcl-agent::sync-environment-from-session environment session)
    (setf (sbcl-agent::agent-session-current-thread-id session) nil)
    (let ((summary (sbcl-agent::session-summary session)))
      (assert-equal 2
                    (getf (getf summary :thread-state) :thread-count)
                    "session-summary should use environment-backed thread counts")
      (assert-true (stringp (getf (getf summary :thread-state) :current-thread-id))
                   "session-summary should recover current thread identity from the environment facade"))))

(defun session-events-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::update-session-plan session "Inspect events")
    (sbcl-agent::append-transcript-entry session :user "hello")
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :session/events :tail 2))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :tool kind "session events tool should dispatch as :tool")
      (assert-equal :session/events (getf result :tool) "session events tool should identify itself")
      (assert-equal 2 (length (getf result :events))
                    "session events tool should honor the requested tail size")
      (assert-true (find :transcript (getf result :events) :key #'sbcl-agent::event-kind)
                   "session events tool should return recent session events"))))

(defun session-events-tool-prefers-environment-event-log-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/session-events-environment/"))
         (environment (sbcl-agent::make-default-environment
                       :storage-root "/tmp/session-events-environment/"
                       :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::append-transcript-entry session :user "hello from environment")
    (setf (sbcl-agent::agent-session-events session) '()
          (sbcl-agent::agent-session-events-tail session) nil)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :session/events :tail 2))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :tool kind "session events tool should still dispatch as :tool")
      (assert-true (getf result :environment-backed-p)
                   "session events tool should expose when it is serving environment-backed events")
      (assert-true (> (getf result :event-count) 0)
                   "session events tool should recover non-empty event history from the bound environment log when session events drift")
      (assert-true (listp (getf result :event-summary))
                   "session events tool should expose an environment-backed event summary")
      (assert-equal (getf result :event-count)
                    (getf (getf result :event-summary) :event-count)
                    "session events tool event summary should reflect the environment-backed event count")
      (assert-true (> (length (or (getf (getf result :event-summary) :recent-kinds) '())) 0)
                   "session events tool should preserve non-empty recent environment event kinds"))))

(defun docs-read-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (command (sbcl-agent::normalize-form-command '(tool :docs/read :path "architecture.md"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (declare (ignore updated-session))
      (assert-equal :tool kind "docs/read should dispatch as :tool")
      (assert-equal :docs/read (getf result :tool) "docs/read should identify itself")
      (assert-true (search "the three truths" (string-downcase (getf result :content)))
                   "docs/read should return maintained architecture content"))))

(defun docs-read-path-escape-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (command (sbcl-agent::normalize-form-command '(tool :docs/read :path "../README.md"))))
    (assert-signals-error
     (lambda () (sbcl-agent::execute-command command provider session))
     "escapes the current session workspace"
     "docs/read should reject paths outside the docs root")))

(defun fs-read-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (command (sbcl-agent::normalize-form-command '(tool :fs/read :path "src/main.lisp"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (declare (ignore updated-session))
      (assert-equal :tool kind "tool command should dispatch as :tool")
      (assert-equal :fs/read (getf result :tool) "fs/read should identify itself")
      (assert-true (search "(defun print-help ()" (getf result :content))
                   "fs/read should return file contents"))))

(defun fs-read-path-escape-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (command (sbcl-agent::normalize-form-command '(tool :fs/read :path "../README.md"))))
    (assert-signals-error
     (lambda () (sbcl-agent::execute-command command provider session))
     "escapes the current session workspace"
     "fs/read should reject paths outside the session root")))

(defun proc-run-approval-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session))
         (command (sbcl-agent::normalize-form-command '(tool :proc/run :argv ("/bin/echo" "hello")))))
    (assert-signals-error
     (lambda () (sbcl-agent::execute-command command provider session))
     "Approval required"
     "process tool should require approval before execution")))

(defun approve-and-run-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :process-run)) provider session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :proc/run :argv ("/bin/echo" "hello")))
         provider
         session)
      (assert-equal :tool kind "process tool should dispatch as :tool after approval")
      (assert-equal 0 (getf result :exit-code) "process tool should return exit code 0")
      (assert-true (search "hello" (getf result :stdout))
                   "process tool should capture stdout after approval")
      (assert-true (getf result :sandboxed)
                   "process tool should execute through the sandbox worker")
      (assert-equal :process-run (getf result :sandbox-profile)
                    "process tool should report the sandbox profile it used")
      (assert-true (find :sandbox-exec
                         (sbcl-agent::agent-session-events updated-session)
                         :key #'sbcl-agent::event-kind)
                   "sandboxed process execution should be logged in the session"))))

(defun git-read-approval-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (namestring (make-test-git-repo))))
         (command (sbcl-agent::normalize-form-command '(tool :git/status))))
    (assert-signals-error
     (lambda () (sbcl-agent::execute-command command provider session))
     "Approval required"
     "git status should require explicit git-read approval")))

(defun git-status-and-diff-test ()
  (let* ((repo (make-test-git-repo))
         (provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (namestring repo))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :git-read)) provider session)
    (multiple-value-bind (status-result status-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :git/status))
         provider
         session)
      (assert-equal :tool status-kind "git status should dispatch as :tool")
      (assert-equal :git/status (getf status-result :tool) "git status should identify itself")
      (assert-true (search "README.md" (getf status-result :stdout))
                   "git status should report the modified file")
      (assert-true (getf status-result :sandboxed)
                   "git status should execute in the sandbox")
      (assert-true (find :sandbox-exec
                         (sbcl-agent::agent-session-events updated-session)
                         :key #'sbcl-agent::event-kind)
                   "git status should be logged as sandbox execution"))
    (multiple-value-bind (diff-result diff-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :git/diff))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :tool diff-kind "git diff should dispatch as :tool")
      (assert-equal :git/diff (getf diff-result :tool) "git diff should identify itself")
      (assert-true (search "sandbox git test" (getf diff-result :stdout))
                   "git diff should show tracked file content"))))

(defun git-write-flow-test ()
  (let* ((repo (make-test-git-repo))
         (provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (namestring repo))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :git-read)) provider session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :git-write)) provider session)
    (multiple-value-bind (add-result add-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :git/add :paths ("README.md")))
         provider
         session)
      (assert-equal :tool add-kind "git add should dispatch as :tool")
      (assert-equal :git/add (getf add-result :tool) "git add should identify itself")
      (assert-equal 0 (getf add-result :exit-code) "git add should succeed")
      (assert-true (find :sandbox-exec
                         (sbcl-agent::agent-session-events updated-session)
                         :key #'sbcl-agent::event-kind)
                   "git add should be logged as sandbox execution"))
    (multiple-value-bind (commit-result commit-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :git/commit :message "Initial sandbox commit"))
         provider
         session)
      (assert-equal :tool commit-kind "git commit should dispatch as :tool")
      (assert-equal :git/commit (getf commit-result :tool) "git commit should identify itself")
      (assert-equal 0 (getf commit-result :exit-code) "git commit should succeed")
      (assert-true (search "Initial sandbox commit" (getf commit-result :stdout))
                   "git commit should report the commit message")
      (assert-true (find :sandbox-exec
                         (sbcl-agent::agent-session-events updated-session)
                         :key #'sbcl-agent::event-kind)
                   "git commit should be logged as sandbox execution"))
    (multiple-value-bind (branch-result branch-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :git/branch :name "feature/test" :checkout t))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :tool branch-kind "git branch should dispatch as :tool")
      (assert-equal :git/branch (getf branch-result :tool) "git branch should identify itself")
      (assert-equal 0 (getf branch-result :exit-code) "git branch checkout should succeed"))
    (multiple-value-bind (status-result status-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(tool :git/status))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :tool status-kind "git status should still dispatch as :tool after writes")
      (assert-true (search "## feature/test" (getf status-result :stdout))
                   "git status should report the checked out branch"))))

(defun patch-approval-and-apply-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/"))
         (path "/tmp/sbcl-agent-patch-test.txt")
         (patch-command '(patch ((:write "sbcl-agent-patch-test.txt" "patched")))))
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-command (sbcl-agent::normalize-form-command patch-command)
                                     provider
                                     session))
     "Approval required"
     "patch application should require workspace-write approval")
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :workspace-write)) provider session)
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command (sbcl-agent::normalize-form-command patch-command)
                                      provider
                                      session)
      (assert-equal 1 (length (sbcl-agent::agent-session-artifacts updated-session))
                    "direct patch command should create one artifact")
      (assert-equal :patch kind "patch command should dispatch as :patch after approval")
      (assert-equal :write (getf (first (getf result :patch)) :operation)
                    "patch should apply write operation")
      (assert-equal "sbcl-agent-patch-test.txt"
                    (getf (sbcl-agent::artifact-record-summary
                           (first (sbcl-agent::agent-session-artifacts updated-session)))
                          :title)
                    "direct patch artifact should expose the written filename")
      (with-open-file (stream path :direction :input)
        (let ((line (read-line stream nil nil)))
          (assert-equal "patched" line "patch should write file contents"))))))

(defun artifact-persistence-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/"))
         (save-path "/tmp/sbcl-agent-artifact-session.sexp")
         (patch-command '(patch ((:write "sbcl-agent-artifact-persist.txt" "persisted artifact")))))
    (when (probe-file save-path)
      (delete-file save-path))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :workspace-write))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command patch-command)
     provider
     session)
    (sbcl-agent::save-session session save-path)
    (let ((loaded (sbcl-agent::load-session save-path)))
      (assert-equal 1 (length (sbcl-agent::agent-session-artifacts loaded))
                    "saved sessions should restore artifact records")
      (assert-equal "sbcl-agent-artifact-persist.txt"
                    (getf (sbcl-agent::artifact-record-summary
                           (first (sbcl-agent::agent-session-artifacts loaded)))
                          :title)
                    "loaded artifact records should preserve title")
      (assert-equal 1
                    (length (getf (sbcl-agent::thread-detail loaded) :artifacts))
                    "thread/show data should preserve artifacts after load"))))

(defun patch-path-escape-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd (current-workspace-root)))
         (patch-command '(patch ((:write "../escape.txt" "patched")))))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :workspace-write)) provider session)
    (assert-signals-error
     (lambda ()
       (sbcl-agent::execute-command (sbcl-agent::normalize-form-command patch-command)
                                     provider
                                     session))
     "escapes the current session workspace"
     "patch application should reject writes outside the session root")))
