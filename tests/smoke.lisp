(in-package #:sbcl-agent/tests)

(defun assert-true (condition message)
  (unless condition
    (error "Test failed: ~A" message)))

(defun assert-equal (expected actual message)
  (unless (equal expected actual)
    (error "Test failed: ~A~%Expected: ~S~%Actual: ~S" message expected actual)))

(defun assert-signals-error (thunk substring message)
  (handler-case
      (progn
        (funcall thunk)
        (error "Test failed: ~A~%Expected an error containing ~S" message substring))
    (error (condition)
      (assert-true (search substring (princ-to-string condition))
                   message))))

(defun wait-for (predicate &key (timeout-seconds 3.0) (sleep-seconds 0.05))
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout-seconds internal-time-units-per-second))))
    (loop until (funcall predicate)
          do (when (> (get-internal-real-time) deadline)
               (error "Timed out waiting for condition"))
             (sleep sleep-seconds))))

(defun run-command (program arguments &key directory)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (let ((process (sb-ext:run-program program
                                       arguments
                                       :search t
                                       :input nil
                                       :output stdout
                                       :error stderr
                                       :wait t
                                       :directory directory)))
      (values (sb-ext:process-exit-code process)
              (get-output-stream-string stdout)
              (get-output-stream-string stderr)))))

(defun run-command-with-input (program arguments input &key directory)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream))
        (stdin (make-string-input-stream input)))
    (let ((process (sb-ext:run-program program
                                       arguments
                                       :search t
                                       :input stdin
                                       :output stdout
                                       :error stderr
                                       :wait t
                                       :directory directory)))
      (values (sb-ext:process-exit-code process)
              (get-output-stream-string stdout)
              (get-output-stream-string stderr)))))

(defun with-captured-output (thunk)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (let ((*standard-output* stdout)
          (*error-output* stderr))
      (values (funcall thunk)
              (get-output-stream-string stdout)
              (get-output-stream-string stderr)))))

(defun with-fake-command-line-arguments (arguments thunk)
  (let ((original (symbol-function 'uiop:command-line-arguments)))
    (unwind-protect
         (progn
           (setf (symbol-function 'uiop:command-line-arguments)
                 (lambda () arguments))
           (funcall thunk))
      (setf (symbol-function 'uiop:command-line-arguments) original))))

(defun run-sandbox-main-with-arguments (arguments)
  (with-fake-command-line-arguments
      arguments
    (lambda ()
      (with-captured-output
        (lambda ()
          (sbcl-agent::sandbox-worker-main))))))

(defun make-test-provider ()
  (sbcl-agent::make-provider
   (sbcl-agent::make-config :provider "mock"
                            :model "gpt-5"
                            :working-directory "/tmp/")))

(defclass mixed-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider mixed-action-provider))
  "mixed-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider mixed-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider mixed-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Executing eval now and staging the file read."
   :actions (list (sbcl-agent::make-assistant-action :type :eval :payload '(:form "(+ 100 203)"))
                  (sbcl-agent::make-assistant-action :type :tool :payload '(:tool-id :fs/read :arguments (:path "src/main.lisp"))))
   :metadata '(:provider :mixed-action-test)))

(defclass patch-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider patch-action-provider))
  "patch-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider patch-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider patch-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a patch that requires workspace write approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :patch
                   :payload '((:write "tmp/generated.txt" "hello from patch"))))
   :metadata '(:provider :patch-action-test)))

(defclass journal-date-time-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider journal-date-time-provider))
  "journal-date-time-test")

(defmethod sbcl-agent::provider-capabilities ((provider journal-date-time-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider journal-date-time-provider) request)
  (declare (ignore provider))
  (let* ((prompt (sbcl-agent::provider-request-prompt request))
         (summary (sbcl-agent::provider-request-session-summary request))
         (transcript (getf summary :recent-transcript))
         (assistant-turn (find :assistant transcript :from-end t :key (lambda (entry) (getf entry :role))))
         (prior-message (and assistant-turn (getf assistant-turn :content)))
         (code "(multiple-value-bind (sec min hour day month year) (get-decoded-time) (format nil \"~D-~D-~D ~D:~D:~D\" year month day hour min sec))"))
    (cond
      ((search "current data and time" prompt :test #'char-equal)
       (sbcl-agent::make-assistant-response
        :message code
        :actions '()
        :metadata '(:provider :journal-date-time-test :step :suggest)))
      ((search "now go execute that" prompt :test #'char-equal)
       (unless (and prior-message (search "get-decoded-time" prior-message :test #'char-equal))
         (error "journal-date-time-provider expected the prior assistant suggestion in recent transcript"))
       (sbcl-agent::make-assistant-response
        :message "Executing the previously suggested date/time code."
        :actions (list (sbcl-agent::make-assistant-action :type :eval :payload prior-message))
        :metadata '(:provider :journal-date-time-test :step :execute)))
      (t
       (error "journal-date-time-provider received unexpected prompt ~S" prompt)))))

(defclass mutating-eval-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider mutating-eval-provider))
  "mutating-eval-test")

(defmethod sbcl-agent::provider-capabilities ((provider mutating-eval-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider mutating-eval-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a mutating eval that requires runtime approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :eval
                   :payload '(:form "(progn (defparameter sbcl-agent-user::*governed-runtime-flag* nil) (setf sbcl-agent-user::*governed-runtime-flag* :mutated) sbcl-agent-user::*governed-runtime-flag*)"
                             :mutating t)))
   :metadata '(:provider :mutating-eval-test)))

(defclass git-write-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider git-write-action-provider))
  "git-write-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider git-write-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider git-write-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a git write action that requires approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :tool
                   :payload '(:tool-id :git/add :arguments (:paths ("README.md")))))
   :metadata '(:provider :git-write-action-test)))

(defclass followup-patch-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider followup-patch-provider))
  "followup-patch-test")

(defmethod sbcl-agent::provider-capabilities ((provider followup-patch-provider))
  '(:chat :structured-response :action-proposals :turn-followup))

(defmethod sbcl-agent::send-request ((provider followup-patch-provider) request)
  (declare (ignore provider))
  (let* ((turn-context (sbcl-agent::provider-request-turn-context request))
         (operations (getf turn-context :operations))
         (completed-patch (find "assistant-patch"
                                operations
                                :key (lambda (entry) (getf entry :name))
                                :test #'string=)))
    (if (and completed-patch
             (eq (getf completed-patch :status) :completed))
        (sbcl-agent::make-assistant-response
         :message "Patch applied successfully. Follow-up summary recorded."
         :actions '()
         :metadata '(:provider :followup-patch-test :phase :followup))
        (sbcl-agent::make-assistant-response
         :message "Prepared a patch that requires approval before follow-up."
         :actions (list (sbcl-agent::make-assistant-action
                         :type :patch
                         :payload '((:write "tmp/followup-generated.txt" "hello from followup patch"))))
         :metadata '(:provider :followup-patch-test :phase :initial)))))

(defun make-test-git-repo ()
  (let* ((root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-git-~D-~D/" (get-universal-time) (random 1000000))))
         (ignore (ensure-directories-exist root))
         (readme (merge-pathnames #P"README.md" root)))
    (declare (ignore ignore))
    (multiple-value-bind (init-exit init-out init-err)
        (run-command "git" (list "init") :directory root)
      (declare (ignore init-out))
      (assert-equal 0 init-exit "git init should succeed in the temp repo")
      (assert-true (or (string= "" init-err)
                       (search "hint:" init-err))
                   "git init should only emit standard hint text in the temp repo"))
    (with-open-file (stream readme :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "sandbox git baseline\n" stream))
    (multiple-value-bind (add-exit add-out add-err)
        (run-command "git"
                     (list "-c" "user.name=pauljbernard"
                           "-c" "user.email=pauljbernard@example.com"
                           "add" "README.md")
                     :directory root)
      (declare (ignore add-out add-err))
      (assert-equal 0 add-exit "git add should succeed in the temp repo setup"))
    (multiple-value-bind (commit-exit commit-out commit-err)
        (run-command "git"
                     (list "-c" "user.name=pauljbernard"
                           "-c" "user.email=pauljbernard@example.com"
                           "commit" "-m" "Baseline")
                     :directory root)
      (declare (ignore commit-out commit-err))
      (assert-equal 0 commit-exit "baseline git commit should succeed in the temp repo setup"))
    (with-open-file (stream readme :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string "sandbox git test\n" stream))
    root))

(defun runtime-smoke-test ()
  (let* ((root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-runtime-~D-~D/" (get-universal-time) (random 1000000))))
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
  (let* ((config (sbcl-agent::make-config :provider "mock"
                                          :model "gpt-5"
                                          :working-directory "/tmp/"))
         (created-session nil))
    (let ((sbcl-agent::*current-session* nil))
      (setf created-session (sbcl-agent::session-for-chat-config config))
      (assert-equal "/tmp/" (sbcl-agent::agent-session-cwd created-session)
                    "session-for-chat-config should create a session rooted at the config working directory")))
  (let* ((config (sbcl-agent::make-config :provider "mock"
                                          :model "gpt-5"
                                          :working-directory "/tmp/"))
         (existing (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
    (let ((sbcl-agent::*current-session* existing))
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
                 "doctor-command should print runtime information"))
  (let ((config (sbcl-agent::make-config :provider "mock"
                                         :model "gpt-5"
                                         :working-directory "/tmp/"))
        (original-doctor (symbol-function 'sbcl-agent::doctor-command))
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
      (setf (symbol-function 'sbcl-agent::exec-command) original-exec)
      (setf (symbol-function 'sbcl-agent::start-shell) original-start-shell)
      (setf (symbol-function 'sbcl-agent::load-config) original-load-config)
      (setf (symbol-function 'sbcl-agent::dispatch-command) original-dispatch)
      (setf (symbol-function 'uiop:command-line-arguments) original-cli))))

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
  (let* ((root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-sandbox-~D-~D/" (get-universal-time) (random 1000000))))
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
  (let* ((root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-tools-~D-~D/" (get-universal-time) (random 1000000))))
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
  (let* ((root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-fake-curl-~D-~D/" (get-universal-time) (random 1000000))))
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
  (let* ((provider (make-instance 'sbcl-agent::openai-compatible-provider
                                  :model "gpt-5"
                                  :fast-model "gpt-4.1-mini"
                                  :api-base "https://api.example.com/v1"
                                  :api-key "secret"))
         (request (sbcl-agent::make-provider-request
                   :prompt "Stream this"
                   :session-summary '(:recent-transcript ()))))
    (assert-equal "x"
                  (sbcl-agent::extract-openai-stream-delta
                   (sbcl-agent::parse-openai-stream-json-line
                    "data: {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}"))
                  "parse-openai-stream-json-line should decode stream chunks")
    (assert-equal 0
                  (sbcl-agent::longest-marker-overlap "plain text" sbcl-agent::+stream-actions-marker+)
                  "longest-marker-overlap should return zero when there is no overlap")
    (let ((fallback-provider (make-instance 'sbcl-agent::openai-compatible-provider
                                            :model "gpt-5"
                                            :fast-model nil
                                            :api-base "https://api.example.com/v1"
                                            :api-key "secret")))
      (assert-equal "gpt-5"
                    (sbcl-agent::openai-request-model
                     fallback-provider
                     (sbcl-agent::make-provider-request :prompt "short ping"))
                    "openai-request-model should fall back to primary model when no fast model is configured")))
  (assert-signals-error
   (lambda ()
     (sbcl-agent::send-request
      (make-instance 'sbcl-agent::openai-compatible-provider
                     :model "gpt-5"
                     :fast-model "gpt-4.1-mini"
                     :api-base "https://api.example.com/v1"
                     :api-key nil)
      (sbcl-agent::make-provider-request :prompt "x" :session-summary '())))
   "OPENAI_API_KEY is required"
   "send-request should reject missing API keys")
  (assert-signals-error
   (lambda ()
     (sbcl-agent::stream-request
      (make-instance 'sbcl-agent::openai-compatible-provider
                     :model "gpt-5"
                     :fast-model "gpt-4.1-mini"
                     :api-base "https://api.example.com/v1"
                     :api-key nil)
      (sbcl-agent::make-provider-request :prompt "x" :session-summary '())
      (lambda (event) (declare (ignore event)))))
   "OPENAI_API_KEY is required"
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
          (setf (uiop:getenv "FAKE_CURL_FAIL") ""))))))

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
                    (getf (first results) :result)
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
  (let ((session (sbcl-agent::make-default-session))
        (progress '()))
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
                 "print-shell-help should mention SAY"))
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
  (let ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
                       :artifacts ((:title "artifact.txt"))
                       :assistant-message (:role :assistant :content "follow-up reply")
                       :awaiting-approval (:awaiting-approval-p nil :blocked-operation-count 0))
                     :turn-status)))))
    (assert-true (search "turn> turn-1 status=COMPLETED messages=3 operations=2 artifacts=1" result)
                 "print-shell-result should render compact turn-status summaries")
    (assert-true (search "assistant> follow-up reply" result)
                 "print-shell-result should render the current assistant message for turn-status"))
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
                                                 :visibility :user
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
    (let ((events '()))
      (sbcl-agent::stream-request provider
                                  request
                                  (lambda (event)
                                    (push event events)))
      (assert-true (find :ACTION-PROPOSAL events :key #'sbcl-agent::provider-event-type)
                   "mock provider stream-request should emit action proposals")
      (assert-true (> (count :MESSAGE-DELTA events :key #'sbcl-agent::provider-event-type) 1)
                   "mock provider stream-request should emit multiple message deltas"))))

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

(defun config-key-file-fallback-test ()
  (let* ((root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-config-~D-~D/" (get-universal-time) (random 1000000))))
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
  (let* ((root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-provider-~D-~D/" (get-universal-time) (random 1000000))))
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
  (let* ((root (uiop:ensure-directory-pathname
                (format nil "/tmp/sbcl-agent-legacy-provider-~D-~D/" (get-universal-time) (random 1000000))))
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

(defun config-with-overrides-test ()
  (let* ((base (sbcl-agent::make-config :provider "mock"
                                        :model "gpt-5"
                                        :fast-model "gpt-4.1-mini"
                                        :api-base nil
                                        :api-key nil
                                        :api-key-present-p nil
                                        :working-directory "/tmp/base/"))
         (updated (sbcl-agent::config-with-overrides base
                                                     :provider "openai-compatible"
                                                     :model "gpt-5.1"
                                                     :api-base "https://example.test/v1"
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
                                        :working-directory nil))
         (updated (sbcl-agent::config-with-overrides base)))
    (assert-true (stringp (sbcl-agent::config-working-directory updated))
                 "config-with-overrides should fall back to the current directory when no working directory exists")
    (assert-equal "mock"
                  (sbcl-agent::config-provider updated)
                  "config-with-overrides should preserve the existing provider by default")))

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
        (thread-new-command (sbcl-agent::normalize-form-command '(thread/new :title "Conversation")))
        (thread-list-command (sbcl-agent::normalize-form-command '(thread/list)))
        (thread-use-command (sbcl-agent::normalize-form-command '(thread/use "thread-1")))
        (thread-show-command (sbcl-agent::normalize-form-command '(thread/show "thread-1")))
        (turn-status-command (sbcl-agent::normalize-form-command '(turn/status "turn-1")))
        (turn-resume-command (sbcl-agent::normalize-form-command '(turn/resume "turn-1")))
        (execute-actions-command (sbcl-agent::normalize-form-command '(execute-actions)))
        (describe-session-command (sbcl-agent::normalize-form-command '(describe-session)))
        (enqueue-task-command (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp"))))
        (run-next-task-command (sbcl-agent::normalize-form-command '(run-next-task)))
        (list-replay-groups-command (sbcl-agent::normalize-form-command '(list-replay-groups)))
        (list-image-reconciliations-command (sbcl-agent::normalize-form-command '(list-image-reconciliations)))
        (replay-validator-command (sbcl-agent::normalize-form-command '(replay-validator-task "work" "validator" :status :passed)))
        (replay-validator-set-command (sbcl-agent::normalize-form-command '(replay-validator-set "work" "replay" :status :partial :statuses '(:live :partial :cold :passed))))
        (reconcile-image-only-command (sbcl-agent::normalize-form-command '(reconcile-image-only-source "work" "summary")))
        (eval-command (sbcl-agent::normalize-form-command '(+ 100 203)))
        (approve-command (sbcl-agent::normalize-form-command '(approve :process-run)))
        (patch-command (sbcl-agent::normalize-form-command '(patch '((:write "x" "y"))))))
    (assert-equal :ask (sbcl-agent::command-kind ask-command)
                  "ask form should normalize to :ask")
    (assert-equal :say (sbcl-agent::command-kind say-command)
                  "say form should normalize to :say")
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
    (assert-equal :eval (sbcl-agent::command-kind eval-command)
                  "plain Lisp forms should normalize to :eval")
    (assert-equal :approve (sbcl-agent::command-kind approve-command)
                  "approve form should normalize to :approve")
    (assert-equal :patch (sbcl-agent::command-kind patch-command)
                  "patch form should normalize to :patch")))

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
        (assert-equal 11 (length (sbcl-agent::agent-session-events updated-session))
                      "say should record turn and operation lifecycle events")))))

(defun say-mixed-action-operations-test ()
  (let ((provider (make-instance 'mixed-action-provider))
        (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
        (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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

(defun say-mutating-eval-approval-test ()
  (let ((provider (make-instance 'mutating-eval-provider))
        (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
      (assert-equal :committed
                    (sbcl-agent::work-item-status work-item)
                    "mutating eval resume should commit the governed work-item")
      (assert-equal :passed
                    (sbcl-agent::validation-result-status
                     (sbcl-agent::work-item-live-validation-result work-item))
                    "mutating eval resume should record validation evidence"))))

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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
      (assert-true (find :provider-stream
                         (sbcl-agent::agent-session-events updated-session)
                         :key #'sbcl-agent::event-kind)
                   "streaming ask should log provider stream events"))))

(defun default-streaming-ask-dispatch-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
                              :directory #P"/Volumes/data/development/sbcl-agent/")
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
                       (first (sbcl-agent::agent-session-tasks updated-session))))))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
        (assert-true (typep (getf describe-result :latest-progress-event) 'sbcl-agent::event)
                     "describe-task should expose the latest task progress event")))))


(defun monitor-task-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
        (assert-equal :completed (getf monitor-result :status)
                      "monitor-task should report the completed task status")))))

(defun task-queue-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
    (multiple-value-bind (enqueue-result enqueue-kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp")))
         provider
         session)
      (assert-equal :enqueue-task enqueue-kind "enqueue-task should dispatch correctly")
      (assert-equal :queued (getf enqueue-result :status) "new task should start queued")
      (assert-equal 1 (length (sbcl-agent::agent-session-tasks updated-session))
                    "session should retain one queued task"))
    (multiple-value-bind (tasks kind updated-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(list-tasks))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :list-tasks kind "list-tasks should dispatch correctly")
      (assert-equal 1 (length tasks) "list-tasks should return one task summary"))))

(defun task-run-next-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
      (assert-true (search "print-help"
                           (getf (getf result :result) :content))
                   "queued tool task should return fs/read content")
      (assert-true (find :task-completed
                         (sbcl-agent::agent-session-events updated-session)
                         :key #'sbcl-agent::event-kind)
                   "task completion should be logged"))))

(defun task-cancel-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
          (assert-true (not (getf stop-result :running-p)) "stop-worker should mark the worker as stopped"))))))


(defun worker-introspection-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
        (multiple-value-bind (worker-result worker-kind final-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(describe-worker ,(getf start-result :id)))
             provider
             introspected-session)
          (declare (ignore final-session))
          (assert-equal :describe-worker worker-kind "describe-worker should dispatch correctly")
          (assert-equal (getf start-result :id) (getf worker-result :id)
                        "describe-worker should return the matching worker id"))
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command `(stop-worker ,(getf start-result :id)))
         provider
         introspected-session)))))

(defun work-item-creation-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
  (let ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
        (assert-equal 1 (length list-result) "list-work-items should return one work-item summary"))
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
                      "describe-work-item should expose checkpoint detail")))))

(defun work-item-validation-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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

(defun work-item-taint-shell-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
        (assert-equal 1 (length list-result) "list-workflow-records should return one workflow record"))
      (let ((record (first (sbcl-agent::agent-session-workflow-records updated-session))))
        (multiple-value-bind (detail-result detail-kind detailed-session)
            (sbcl-agent::execute-command
             (sbcl-agent::normalize-form-command `(describe-workflow-record ,(sbcl-agent::workflow-record-id record)))
             provider
             updated-session)
          (declare (ignore detailed-session))
          (assert-equal :describe-workflow-record detail-kind "describe-workflow-record should dispatch correctly")
          (assert-equal (sbcl-agent::workflow-record-id record)
                        (getf detail-result :id)
                        "describe-workflow-record should return the requested workflow record")
          (assert-true (> (length (getf detail-result :entries)) 2)
                       "describe-workflow-record should expose appended workflow entries")
          (assert-equal :committed
                        (getf detail-result :status)
                        "describe-workflow-record should expose committed closure state"))))))

(defun workflow-record-approval-state-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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

(defun workflow-record-quarantine-resume-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
                 "quarantine and resume should both record operator interventions")))

(defun workflow-record-operator-shell-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
                   "approval-gated work should expose a resumable next action"))))

(defun why-waiting-shell-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
                   "why-waiting should expose a deterministic next action"))))

(defun workflow-record-resume-payload-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (work-a (sbcl-agent::create-work-item session "Approval blocked" :transaction-scope :test))
         (work-b (sbcl-agent::create-work-item session "Validation pending" :transaction-scope :test)))
    (declare (ignore work-b))
    (sbcl-agent::request-work-item-approval session work-a :process-run :reason "Need process execution")
    (let* ((summary (sbcl-agent::session-wait-summary session))
           (reasons (getf summary :by-reason))
           (session-summary (sbcl-agent::session-summary session)))
      (assert-equal 2
                    (getf summary :blocked-count)
                    "session-wait-summary should count blocked work items")
      (assert-true (find :approval-required reasons :key (lambda (entry) (getf entry :why)))
                   "session-wait-summary should include approval blockers")
      (assert-true (find :pending-validation reasons :key (lambda (entry) (getf entry :why)))
                   "session-wait-summary should include pending validation blockers")
      (assert-equal 2
                    (getf (getf session-summary :wait-summary) :blocked-count)
                    "session-summary should expose wait-summary data"))))


(defun checkpoint-linked-resume-payload-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (work-item (sbcl-agent::create-work-item session "Checkpoint link check" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let ((payload (sbcl-agent::work-item-resume-payload work-item)))
      (assert-true (stringp (getf payload :checkpoint-id))
                   "checkpoint-linked resume payload should include checkpoint id")
      (assert-equal (sbcl-agent::latest-work-item-checkpoint-id work-item)
                    (getf payload :checkpoint-id)
                    "resume payload should point at the latest checkpoint"))))

(defun validator-action-plan-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (work-item (sbcl-agent::create-work-item session "Validator action check" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (let ((actions (sbcl-agent::work-item-validator-actions work-item)))
      (assert-equal 2 (length actions)
                    "validator action plan should include live and cold validators for fresh work")
      (assert-true (every (lambda (entry) (stringp (getf entry :checkpoint-id))) actions)
                   "validator action plan should carry checkpoint ids"))))


(defun transaction-replay-id-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (work-item (sbcl-agent::create-work-item session "Replay id check" :transaction-scope :test))
         (transaction (first (sbcl-agent::work-item-transactions work-item))))
    (assert-true (stringp (sbcl-agent::mutation-transaction-replay-id transaction))
                 "transactions should carry replay ids")
    (assert-true (search "TXN-" (string-upcase (sbcl-agent::mutation-transaction-replay-id transaction)))
                 "transaction replay ids should use the txn prefix")))

(defun validator-task-records-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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

(defun list-image-reconciliations-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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

(defun replay-validator-set-mixed-status-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
                      "replaying the first validator should record a passed live validation")))))

(defun reconcile-image-only-source-command-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
                    "reconciling image-only work should produce a durable closure decision"))))

(defun image-only-outcome-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
                    "operator status should count quarantined work items"))))

(defun operator-status-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
  (let* ((session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
      (assert-true (search "Operator status: ready=0 blocked=1 quarantined=0 image-only=0 durable=0" output)
                   "doctor command should print operator status counts"))))

(defun task-persistence-test ()
  (let* ((provider (make-test-provider))
         (path "/tmp/sbcl-agent-task-session.sexp")
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (response (sbcl-agent::send-prompt provider "please read src/main.lisp" session)))
    (assert-equal 1 (length (sbcl-agent::assistant-response-actions response))
                  "mock provider should propose one read action")
    (assert-equal :TOOL
                  (sbcl-agent::assistant-action-type (first (sbcl-agent::assistant-response-actions response)))
                  "proposed action should be a tool action")))

(defun assistant-action-staging-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
                    (getf (first (getf result :action-results)) :result)
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
                  (sbcl-agent::execute-assistant-action action session)
                  "assistant eval actions should execute Common Lisp forms in the current image")
    (assert-equal 303
                  (sbcl-agent::execute-assistant-action code-action session)
                  "assistant eval actions should also accept payloads under :code")))

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
      (assert-equal 303 result
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
          (let ((rendered (getf (first (getf second-result :action-results)) :result)))
            (assert-true (stringp rendered)
                         "executed journal code should return a date/time string")
            (assert-true (search "-" rendered)
                         "rendered date/time string should contain a date separator")
            (assert-true (search ":" rendered)
                         "rendered date/time string should contain a time separator")))))))

(defun session-summary-recent-transcript-test ()
  (let ((session (sbcl-agent::make-default-session)))
    (sbcl-agent::append-transcript-entry session :user "first")
    (sbcl-agent::append-transcript-entry session :assistant "second")
    (let ((summary (sbcl-agent::session-summary session)))
      (assert-equal 2
                    (length (getf summary :recent-transcript))
                    "session summary should include recent transcript entries")
      (assert-equal "second"
                    (getf (second (getf summary :recent-transcript)) :content)
                    "recent transcript should preserve the latest assistant turn"))))

(defun provider-session-summary-compact-test ()
  (let ((session (sbcl-agent::make-default-session)))
    (sbcl-agent::append-transcript-entry session :user (make-string 400 :initial-element #\x))
    (let ((summary (sbcl-agent::provider-session-summary session)))
      (assert-true (null (getf summary :wait-summary))
                   "provider session summary should omit heavyweight workflow fields")
      (assert-true (stringp (getf summary :current-thread-id))
                   "provider session summary should expose the active thread id")
      (assert-true (>= (getf summary :thread-count) 1)
                   "provider session summary should expose thread count")
      (assert-true (integerp (getf summary :message-count))
                   "provider session summary should expose persisted message count")
      (assert-true (integerp (getf summary :turn-count))
                   "provider session summary should expose persisted turn count")
      (assert-true (integerp (getf summary :operation-count))
                   "provider session summary should expose persisted operation count")
      (assert-equal 1
                    (length (getf summary :recent-transcript))
                    "provider session summary should keep recent transcript entries")
      (assert-true (< (length (getf (first (getf summary :recent-transcript)) :content)) 260)
                   "provider session summary should truncate oversized transcript content"))))

(defun provider-request-context-test ()
  (let* ((session (sbcl-agent::make-default-session))
         (thread (sbcl-agent::current-thread session))
         (user-message (sbcl-agent::create-message session thread :user "inspect provider request"))
         (turn (sbcl-agent::start-turn session thread user-message
                                       :metadata '(:source :test)))
         (assistant-message (sbcl-agent::create-message session thread :assistant "pending"))
         (ignore (sbcl-agent::complete-turn session thread turn assistant-message
                                            :status :completed))
         (request (sbcl-agent::make-provider-request-from-session
                   "inspect provider request"
                   session
                   :thread thread
                   :turn turn
                   :operator-mode :conversation
                   :stream-p t)))
    (declare (ignore ignore))
    (assert-equal :conversation
                  (sbcl-agent::provider-request-operator-mode request)
                  "provider request should retain the operator mode")
    (assert-true (sbcl-agent::provider-request-stream-p request)
                 "provider request should retain stream intent")
    (assert-equal (sbcl-agent::thread-id thread)
                  (getf (sbcl-agent::provider-request-thread-context request) :id)
                  "provider request should expose thread context separately from session summary")
    (assert-equal (sbcl-agent::turn-id turn)
                  (getf (sbcl-agent::provider-request-turn-context request) :id)
                  "provider request should expose turn context separately from session summary")
    (assert-equal (sbcl-agent::agent-session-cwd session)
                  (getf (sbcl-agent::provider-request-runtime-summary request) :cwd)
                  "provider request should expose runtime summary")
    (assert-equal (sbcl-agent::agent-session-cwd session)
                  (getf (sbcl-agent::provider-request-workspace-summary request) :cwd)
                  "provider request should expose workspace summary")
    (assert-true (listp (getf (sbcl-agent::provider-request-policy-summary request) :approved-policies))
                 "provider request should expose policy summary")
    (assert-true (listp (sbcl-agent::provider-request-session-summary request))
                 "provider request should preserve the compact session summary")))

(defun provider-rendering-context-test ()
  (let* ((request (sbcl-agent::make-provider-request
                   :prompt "describe the current state"
                   :session-summary '(:recent-transcript ((:role :assistant :content "Earlier")))
                   :thread-context '(:id "thread-1" :title "Default Thread")
                   :turn-context '(:id "turn-1" :status :running)
                   :runtime-summary '(:cwd "/tmp/project" :package "SBCL-AGENT-USER")
                   :workspace-summary '(:cwd "/tmp/project" :artifact-count 2)
                   :policy-summary '(:approved-policies (:safe-read))
                   :operator-mode :conversation
                   :stream-p t))
         (prompt (sbcl-agent::build-openai-user-prompt request))
         (mock-response (sbcl-agent::build-mock-response request)))
    (assert-true (search "Operator mode: :CONVERSATION" prompt)
                 "build-openai-user-prompt should render operator mode")
    (assert-true (search "Thread: (:ID \"thread-1\"" prompt)
                 "build-openai-user-prompt should render thread context")
    (assert-true (search "Runtime summary: (:CWD \"/tmp/project\"" prompt)
                 "build-openai-user-prompt should render runtime summary")
    (assert-equal :conversation
                  (getf (sbcl-agent::assistant-response-metadata mock-response) :operator-mode)
                  "mock provider responses should preserve operator mode metadata")
    (assert-equal "thread-1"
                  (getf (getf (sbcl-agent::assistant-response-metadata mock-response) :thread) :id)
                  "mock provider responses should preserve thread context metadata")))

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
                    "thread/show should expose persisted thread turns"))
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
      (assert-true (not (getf (getf turn-result :awaiting-approval) :awaiting-approval-p))
                   "completed turn/status should report no approval wait")
      (assert-equal 0
                    (getf (getf turn-result :awaiting-approval) :blocked-operation-count)
                    "completed turn/status should report zero blocked operations"))))

(defun turn-status-approval-summary-test ()
  (let* ((provider (make-instance 'patch-action-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
                    "turn/status should report the waiting policy id"))))

(defun turn-resume-approval-flow-test ()
  (let* ((provider (make-instance 'patch-action-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
                    "thread/show should expose persisted thread artifacts after resume"))))

(defun turn-resume-isolates-pending-actions-by-turn-test ()
  (let* ((provider (make-instance 'patch-action-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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

(defun session-shell-commands-test ()
  (let* ((provider (make-test-provider))
         (path "/tmp/sbcl-agent-shell-session.sexp")
         (session (sbcl-agent::make-default-session)))
    (sbcl-agent::update-session-plan session "Shell persistence")
    (multiple-value-bind (describe-result describe-kind described-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(describe-session))
         provider
         session)
      (declare (ignore described-session))
      (assert-equal :describe-session describe-kind "describe-session should dispatch correctly")
      (assert-equal "Shell persistence"
                    (getf describe-result :plan)
                    "describe-session should report the current plan"))
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
      (assert-equal "Shell persistence"
                    (sbcl-agent::agent-session-plan loaded-session)
                    "session/load should restore the saved plan"))))

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
    (assert-true (find :docs/read tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :docs/read")
    (assert-equal :process-run
                  (getf (sbcl-agent::describe-tool :proc/run) :isolation-profile)
                  "process tool should advertise a sandbox isolation profile")
    (assert-equal :git-read
                  (getf (sbcl-agent::describe-tool :git/status) :policy)
                  "git status should advertise git-read policy")
    (assert-equal :safe-read
                  (getf (sbcl-agent::describe-tool :session/summary) :policy)
                  "session summary should advertise safe-read policy")))

(defun session-summary-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
                    "session summary tool should return the current session plan"))))

(defun session-events-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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

(defun docs-read-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (command (sbcl-agent::normalize-form-command '(tool :docs/read :path "../README.md"))))
    (assert-signals-error
     (lambda () (sbcl-agent::execute-command command provider session))
     "escapes the current session workspace"
     "docs/read should reject paths outside the docs root")))

(defun fs-read-tool-test ()
  (let* ((provider (make-test-provider))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
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
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
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

(defun run-all-tests ()
  (format t "Running sbcl-agent test suite...~%")
  (runtime-smoke-test)
  (format t "PASS runtime-smoke-test~%")
  (direct-sandbox-tool-wrapper-test)
  (format t "PASS direct-sandbox-tool-wrapper-test~%")
  (repl-alias-test)
  (format t "PASS repl-alias-test~%")
  (main-command-helper-test)
  (format t "PASS main-command-helper-test~%")
  (openai-helper-coverage-test)
  (format t "PASS openai-helper-coverage-test~%")
  (json-helper-coverage-test)
  (format t "PASS json-helper-coverage-test~%")
  (sandbox-helper-coverage-test)
  (format t "PASS sandbox-helper-coverage-test~%")
  (tool-helper-coverage-test)
  (format t "PASS tool-helper-coverage-test~%")
  (policy-helper-coverage-test)
  (format t "PASS policy-helper-coverage-test~%")
  (openai-provider-io-coverage-test)
  (format t "PASS openai-provider-io-coverage-test~%")
  (provider-protocol-helper-coverage-test)
  (format t "PASS provider-protocol-helper-coverage-test~%")
  (sandbox-main-coverage-test)
  (format t "PASS sandbox-main-coverage-test~%")
  (turn-orchestrator-helper-coverage-test)
  (format t "PASS turn-orchestrator-helper-coverage-test~%")
  (shell-helper-coverage-test)
  (format t "PASS shell-helper-coverage-test~%")
  (shell-stream-rendering-coverage-test)
  (format t "PASS shell-stream-rendering-coverage-test~%")
  (turn-orchestrator-run-coverage-test)
  (format t "PASS turn-orchestrator-run-coverage-test~%")
  (conversation-helper-coverage-test)
  (format t "PASS conversation-helper-coverage-test~%")
  (sandbox-branch-coverage-test)
  (format t "PASS sandbox-branch-coverage-test~%")
  (json-roundtrip-test)
  (format t "PASS json-roundtrip-test~%")
  (provider-decode-test)
  (format t "PASS provider-decode-test~%")
  (mock-provider-helper-coverage-test)
  (format t "PASS mock-provider-helper-coverage-test~%")
  (openai-provider-selection-test)
  (format t "PASS openai-provider-selection-test~%")
  (config-key-file-fallback-test)
  (format t "PASS config-key-file-fallback-test~%")
  (config-auto-provider-selection-test)
  (format t "PASS config-auto-provider-selection-test~%")
  (config-legacy-key-filename-test)
  (format t "PASS config-legacy-key-filename-test~%")
  (config-with-overrides-test)
  (format t "PASS config-with-overrides-test~%")
  (config-helper-coverage-test)
  (format t "PASS config-helper-coverage-test~%")
  (openai-request-model-selection-test)
  (format t "PASS openai-request-model-selection-test~%")
  (invalid-eval-action-dropped-test)
  (format t "PASS invalid-eval-action-dropped-test~%")
  (chat-argument-parsing-test)
  (format t "PASS chat-argument-parsing-test~%")
  (command-normalization-test)
  (format t "PASS command-normalization-test~%")
  (shell-eval-test)
  (format t "PASS shell-eval-test~%")
  (ask-dispatch-test)
  (format t "PASS ask-dispatch-test~%")
  (say-dispatch-test)
  (format t "PASS say-dispatch-test~%")
  (say-mixed-action-operations-test)
  (format t "PASS say-mixed-action-operations-test~%")
  (say-patch-action-approval-test)
  (format t "PASS say-patch-action-approval-test~%")
  (say-mutating-eval-approval-test)
  (format t "PASS say-mutating-eval-approval-test~%")
  (say-git-write-tool-approval-test)
  (format t "PASS say-git-write-tool-approval-test~%")
  (streaming-provider-test)
  (format t "PASS streaming-provider-test~%")
  (provider-event-normalization-test)
  (format t "PASS provider-event-normalization-test~%")
  (openai-stream-line-parser-test)
  (format t "PASS openai-stream-line-parser-test~%")
  (openai-stream-response-decode-test)
  (format t "PASS openai-stream-response-decode-test~%")
  (streaming-ask-dispatch-test)
  (format t "PASS streaming-ask-dispatch-test~%")
  (default-streaming-ask-dispatch-test)
  (format t "PASS default-streaming-ask-dispatch-test~%")
  (chat-interactive-flag-test)
  (format t "PASS chat-interactive-flag-test~%")
  (ask-enqueue-test)
  (format t "PASS ask-enqueue-test~%")
  (queued-ask-worker-test)
  (format t "PASS queued-ask-worker-test~%")
  (describe-task-progress-test)
  (format t "PASS describe-task-progress-test~%")
  (monitor-task-test)
  (format t "PASS monitor-task-test~%")
  (task-queue-test)
  (format t "PASS task-queue-test~%")
  (task-run-next-test)
  (format t "PASS task-run-next-test~%")
  (task-cancel-test)
  (format t "PASS task-cancel-test~%")
  (worker-flow-test)
  (format t "PASS worker-flow-test~%")
  (worker-introspection-test)
  (format t "PASS worker-introspection-test~%")
  (work-item-creation-test)
  (format t "PASS work-item-creation-test~%")
  (work-item-persistence-test)
  (format t "PASS work-item-persistence-test~%")
  (work-item-checkpoint-test)
  (format t "PASS work-item-checkpoint-test~%")
  (work-item-shell-commands-test)
  (format t "PASS work-item-shell-commands-test~%")
  (work-item-validation-test)
  (format t "PASS work-item-validation-test~%")
  (work-item-failure-validation-test)
  (format t "PASS work-item-failure-validation-test~%")
  (work-item-provenance-test)
  (format t "PASS work-item-provenance-test~%")
  (work-item-provenance-shell-test)
  (format t "PASS work-item-provenance-shell-test~%")
  (work-item-taint-reconciliation-test)
  (format t "PASS work-item-taint-reconciliation-test~%")
  (work-item-taint-shell-test)
  (format t "PASS work-item-taint-shell-test~%")
  (workflow-record-creation-test)
  (format t "PASS workflow-record-creation-test~%")
  (workflow-record-persistence-test)
  (format t "PASS workflow-record-persistence-test~%")
  (workflow-record-shell-test)
  (format t "PASS workflow-record-shell-test~%")
  (workflow-record-approval-state-test)
  (format t "PASS workflow-record-approval-state-test~%")
  (workflow-record-quarantine-resume-test)
  (format t "PASS workflow-record-quarantine-resume-test~%")
  (workflow-record-operator-shell-test)
  (format t "PASS workflow-record-operator-shell-test~%")
  (work-item-wait-report-test)
  (format t "PASS work-item-wait-report-test~%")
  (why-waiting-shell-command-test)
  (format t "PASS why-waiting-shell-command-test~%")
  (workflow-record-resume-payload-test)
  (format t "PASS workflow-record-resume-payload-test~%")
  (session-wait-summary-test)
  (format t "PASS session-wait-summary-test~%")
  (checkpoint-linked-resume-payload-test)
  (format t "PASS checkpoint-linked-resume-payload-test~%")
  (transaction-replay-id-test)
  (format t "PASS transaction-replay-id-test~%")
  (validator-action-plan-test)
  (format t "PASS validator-action-plan-test~%")
  (validator-task-records-test)
  (format t "PASS validator-task-records-test~%")
  (list-replay-groups-command-test)
  (format t "PASS list-replay-groups-command-test~%")
  (list-image-reconciliations-command-test)
  (format t "PASS list-image-reconciliations-command-test~%")
  (replay-validator-set-mixed-status-test)
  (format t "PASS replay-validator-set-mixed-status-test~%")
  (replay-validator-set-command-test)
  (format t "PASS replay-validator-set-command-test~%")
  (validator-failure-status-test)
  (format t "PASS validator-failure-status-test~%")
  (replay-validator-task-command-test)
  (format t "PASS replay-validator-task-command-test~%")
  (reconcile-image-only-source-command-test)
  (format t "PASS reconcile-image-only-source-command-test~%")
  (session-replay-group-summary-test)
  (format t "PASS session-replay-group-summary-test~%")
  (image-reconciliation-record-test)
  (format t "PASS image-reconciliation-record-test~%")
  (session-image-reconciliation-summary-test)
  (format t "PASS session-image-reconciliation-summary-test~%")
  (image-only-outcome-test)
  (format t "PASS image-only-outcome-test~%")
  (operator-status-summary-test)
  (format t "PASS operator-status-summary-test~%")
  (operator-status-tool-test)
  (format t "PASS operator-status-tool-test~%")
  (doctor-command-wait-summary-test)
  (format t "PASS doctor-command-wait-summary-test~%")
  (doctor-command-replay-and-reconciliation-test)
  (format t "PASS doctor-command-replay-and-reconciliation-test~%")
  (task-persistence-test)
  (format t "PASS task-persistence-test~%")
  (assistant-action-proposal-test)
  (format t "PASS assistant-action-proposal-test~%")
  (assistant-action-staging-test)
  (format t "PASS assistant-action-staging-test~%")
  (assistant-mixed-action-ask-test)
  (format t "PASS assistant-mixed-action-ask-test~%")
  (assistant-action-execution-test)
  (format t "PASS assistant-action-execution-test~%")
  (assistant-eval-action-execution-test)
  (format t "PASS assistant-eval-action-execution-test~%")
  (pasted-assistant-action-command-test)
  (format t "PASS pasted-assistant-action-command-test~%")
  (journal-date-time-followup-execution-test)
  (format t "PASS journal-date-time-followup-execution-test~%")
  (session-summary-recent-transcript-test)
  (format t "PASS session-summary-recent-transcript-test~%")
  (provider-session-summary-compact-test)
  (format t "PASS provider-session-summary-compact-test~%")
  (provider-request-context-test)
  (format t "PASS provider-request-context-test~%")
  (provider-rendering-context-test)
  (format t "PASS provider-rendering-context-test~%")
  (session-plan-test)
  (format t "PASS session-plan-test~%")
  (capability-policy-model-test)
  (format t "PASS capability-policy-model-test~%")
  (capability-grant-session-test)
  (format t "PASS capability-grant-session-test~%")
  (session-save-load-test)
  (format t "PASS session-save-load-test~%")
  (session-tail-rebuild-after-load-test)
  (format t "PASS session-tail-rebuild-after-load-test~%")
  (thread-shell-commands-test)
  (format t "PASS thread-shell-commands-test~%")
  (thread-show-and-turn-status-test)
  (format t "PASS thread-show-and-turn-status-test~%")
  (turn-status-approval-summary-test)
  (format t "PASS turn-status-approval-summary-test~%")
  (turn-resume-approval-flow-test)
  (format t "PASS turn-resume-approval-flow-test~%")
  (turn-resume-isolates-pending-actions-by-turn-test)
  (format t "PASS turn-resume-isolates-pending-actions-by-turn-test~%")
  (turn-resume-provider-followup-test)
  (format t "PASS turn-resume-provider-followup-test~%")
  (session-shell-commands-test)
  (format t "PASS session-shell-commands-test~%")
  (list-tools-test)
  (format t "PASS list-tools-test~%")
  (session-summary-tool-test)
  (format t "PASS session-summary-tool-test~%")
  (session-events-tool-test)
  (format t "PASS session-events-tool-test~%")
  (docs-read-tool-test)
  (format t "PASS docs-read-tool-test~%")
  (docs-read-path-escape-test)
  (format t "PASS docs-read-path-escape-test~%")
  (fs-read-tool-test)
  (format t "PASS fs-read-tool-test~%")
  (fs-read-path-escape-test)
  (format t "PASS fs-read-path-escape-test~%")
  (proc-run-approval-test)
  (format t "PASS proc-run-approval-test~%")
  (approve-and-run-tool-test)
  (format t "PASS approve-and-run-tool-test~%")
  (git-read-approval-test)
  (format t "PASS git-read-approval-test~%")
  (git-status-and-diff-test)
  (format t "PASS git-status-and-diff-test~%")
  (git-write-flow-test)
  (format t "PASS git-write-flow-test~%")
  (patch-approval-and-apply-test)
  (format t "PASS patch-approval-and-apply-test~%")
  (artifact-persistence-test)
  (format t "PASS artifact-persistence-test~%")
  (patch-path-escape-test)
  (format t "PASS patch-path-escape-test~%")
  (format t "All tests passed.~%")
  t)
