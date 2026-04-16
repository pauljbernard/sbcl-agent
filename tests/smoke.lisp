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
        (assert-equal 5 (length (sbcl-agent::agent-session-events updated-session))
                      "ask dispatch should record command, transcript, pending-action reset, and response events")))))

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
      (assert-equal 1
                    (length (getf summary :recent-transcript))
                    "provider session summary should keep recent transcript entries")
      (assert-true (< (length (getf (first (getf summary :recent-transcript)) :content)) 260)
                   "provider session summary should truncate oversized transcript content"))))

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
    (sbcl-agent::save-session session path)
    (let ((loaded (sbcl-agent::load-session path)))
      (assert-equal "Persist session"
                    (sbcl-agent::agent-session-plan loaded)
                    "loaded session should preserve plan")
      (assert-equal 1
                    (length (sbcl-agent::agent-session-transcript loaded))
                    "loaded session should preserve transcript entries"))))

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
      (declare (ignore updated-session))
      (assert-equal :patch kind "patch command should dispatch as :patch after approval")
      (assert-equal :write (getf (first (getf result :patch)) :operation)
                    "patch should apply write operation")
      (with-open-file (stream path :direction :input)
        (let ((line (read-line stream nil nil)))
          (assert-equal "patched" line "patch should write file contents"))))))

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
  (json-roundtrip-test)
  (format t "PASS json-roundtrip-test~%")
  (provider-decode-test)
  (format t "PASS provider-decode-test~%")
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
  (streaming-provider-test)
  (format t "PASS streaming-provider-test~%")
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
  (session-plan-test)
  (format t "PASS session-plan-test~%")
  (capability-policy-model-test)
  (format t "PASS capability-policy-model-test~%")
  (capability-grant-session-test)
  (format t "PASS capability-grant-session-test~%")
  (session-save-load-test)
  (format t "PASS session-save-load-test~%")
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
  (patch-path-escape-test)
  (format t "PASS patch-path-escape-test~%")
  (format t "All tests passed.~%")
  t)
