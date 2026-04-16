(in-package #:tutor-codex/tests)

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

(defun runtime-smoke-test ()
  (let ((config (tutor-codex::load-config))
        (provider (tutor-codex::make-provider (tutor-codex::load-config))))
    (assert-true (typep config 'tutor-codex::config)
                 "load-config should return a tutor-codex config struct")
    (assert-true (string= (tutor-codex::provider-name provider) "mock")
                 "default provider should be mock")
    (let ((response (tutor-codex::send-prompt provider "ping")))
      (assert-true (typep response 'tutor-codex::assistant-response)
                   "provider should return an assistant-response struct")
      (assert-true (search "SBCL scaffold"
                           (tutor-codex::assistant-response-message response))
                   "mock provider should return the scaffold smoke-test marker"))))

(defun json-roundtrip-test ()
  (let* ((json (tutor-codex::emit-json (list :message "hello"
                                             :actions (list (list :type "tool"))
                                             :metadata (list :provider "mock"))))
         (parsed (tutor-codex::parse-json json)))
    (assert-equal "hello"
                  (tutor-codex::json-object-value parsed "message")
                  "json emitter/parser should roundtrip message field")
    (assert-equal "tool"
                  (tutor-codex::json-object-value (first (tutor-codex::json-object-value parsed "actions")) "type")
                  "json emitter/parser should roundtrip nested action field")))

(defun provider-decode-test ()
  (let* ((content-object '(("message" . "decoded")
                           ("actions" . (( ("type" . "tool")
                                             ("payload" . (("tool_id" . ":FS/READ")
                                                            ("arguments" . (":path" "src/main.lisp")))))))
                           ("metadata" . (("provider" . "mock")))))
         (response (tutor-codex::decode-assistant-response-object content-object)))
    (assert-equal "decoded"
                  (tutor-codex::assistant-response-message response)
                  "provider decoder should preserve message")
    (assert-equal :TOOL
                  (tutor-codex::assistant-action-type (first (tutor-codex::assistant-response-actions response)))
                  "provider decoder should normalize action type")
    (assert-equal :FS/READ
                  (getf (tutor-codex::assistant-action-payload (first (tutor-codex::assistant-response-actions response))) :TOOL-ID)
                  "provider decoder should normalize tool id keyword")
    (assert-equal :PATH
                  (first (getf (tutor-codex::assistant-action-payload (first (tutor-codex::assistant-response-actions response))) :ARGUMENTS))
                  "provider decoder should normalize argument keywords")))

(defun openai-provider-selection-test ()
  (let ((config (tutor-codex::make-config :provider "openai-compatible"
                                          :model "gpt-5"
                                          :api-base "https://api.openai.com/v1"
                                          :api-key "test-key"
                                          :api-key-present-p t
                                          :working-directory "/tmp/")))
    (assert-equal "openai-compatible"
                  (tutor-codex::provider-name (tutor-codex::make-provider config))
                  "make-provider should construct the openai-compatible provider")))

(defun command-normalization-test ()
  (let ((ask-command (tutor-codex::normalize-form-command '(ask "inspect src/main.lisp")))
        (execute-actions-command (tutor-codex::normalize-form-command '(execute-actions)))
        (describe-session-command (tutor-codex::normalize-form-command '(describe-session)))
        (eval-command (tutor-codex::normalize-form-command '(+ 100 203)))
        (approve-command (tutor-codex::normalize-form-command '(approve :process-run)))
        (patch-command (tutor-codex::normalize-form-command '(patch '((:write "x" "y"))))))
    (assert-equal :ask (tutor-codex::command-kind ask-command)
                  "ask form should normalize to :ask")
    (assert-equal :execute-actions (tutor-codex::command-kind execute-actions-command)
                  "execute-actions form should normalize to :execute-actions")
    (assert-equal :describe-session (tutor-codex::command-kind describe-session-command)
                  "describe-session form should normalize to :describe-session")
    (assert-equal :eval (tutor-codex::command-kind eval-command)
                  "plain Lisp forms should normalize to :eval")
    (assert-equal :approve (tutor-codex::command-kind approve-command)
                  "approve form should normalize to :approve")
    (assert-equal :patch (tutor-codex::command-kind patch-command)
                  "patch form should normalize to :patch")
    (assert-equal '("inspect src/main.lisp")
                  (tutor-codex::command-arguments ask-command)
                  "ask command should preserve string argument")))

(defun shell-eval-test ()
  (assert-equal 303
                (tutor-codex::eval-user-form '(+ 100 203))
                "direct user forms should evaluate in the Lisp shell"))

(defun ask-dispatch-test ()
  (let ((provider (tutor-codex::make-provider (tutor-codex::load-config)))
        (session (tutor-codex::make-default-session))
        (command (tutor-codex::normalize-form-command '(ask "ping"))))
    (multiple-value-bind (result kind updated-session)
        (tutor-codex::execute-command command provider session)
      (let ((response (getf result :response)))
        (assert-equal :ask kind "ask command should dispatch as :ask")
        (assert-true (typep response 'tutor-codex::assistant-response)
                     "ask command should return an assistant response")
        (assert-true (search "Mock response: ping" (tutor-codex::assistant-response-message response))
                     "ask command should be handled by the provider")
        (assert-equal 0 (getf result :staged-action-count)
                      "ask without actions should stage zero actions")
        (assert-equal 4 (length (tutor-codex::agent-session-events updated-session))
                      "ask dispatch should record command, transcript, and response events")))))

(defun assistant-action-proposal-test ()
  (let* ((provider (tutor-codex::make-provider (tutor-codex::load-config)))
         (session (tutor-codex::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (response (tutor-codex::send-prompt provider "please read src/main.lisp" session)))
    (assert-equal 1 (length (tutor-codex::assistant-response-actions response))
                  "mock provider should propose one read action")
    (assert-equal :TOOL
                  (tutor-codex::assistant-action-type (first (tutor-codex::assistant-response-actions response)))
                  "proposed action should be a tool action")))

(defun assistant-action-staging-test ()
  (let* ((provider (tutor-codex::make-provider (tutor-codex::load-config)))
         (session (tutor-codex::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (command (tutor-codex::normalize-form-command '(ask "please read src/main.lisp"))))
    (multiple-value-bind (result kind updated-session)
        (tutor-codex::execute-command command provider session)
      (declare (ignore kind))
      (assert-equal 1 (getf result :staged-action-count)
                    "ask flow should stage one proposed action")
      (assert-equal 1 (length (tutor-codex::agent-session-pending-actions updated-session))
                    "session should retain one staged action")
      (assert-true (= 0 (length (or (getf result :action-results) '())))
                   "ask flow should not execute actions immediately"))))

(defun assistant-action-execution-test ()
  (let* ((provider (tutor-codex::make-provider (tutor-codex::load-config)))
         (session (tutor-codex::make-default-session :cwd "/Volumes/data/development/sbcl-agent/")))
    (tutor-codex::execute-command
     (tutor-codex::normalize-form-command '(ask "please read src/main.lisp"))
     provider
     session)
    (multiple-value-bind (result kind updated-session)
        (tutor-codex::execute-command
         (tutor-codex::normalize-form-command '(execute-actions))
         provider
         session)
      (assert-equal :execute-actions kind "execute-actions should dispatch correctly")
      (assert-equal 1 (length result)
                    "execute-actions should execute one staged action")
      (assert-true (search "(defun print-help ()"
                           (getf (getf (first result) :result) :content))
                   "executed assistant action should read src/main.lisp")
      (assert-equal 0 (length (tutor-codex::agent-session-pending-actions updated-session))
                    "pending actions should be cleared after execution"))))

(defun session-plan-test ()
  (let* ((provider (tutor-codex::make-provider (tutor-codex::load-config)))
         (session (tutor-codex::make-default-session))
         (command (tutor-codex::normalize-form-command '(plan "Build tool registry"))))
    (multiple-value-bind (result kind updated-session)
        (tutor-codex::execute-command command provider session)
      (assert-equal :plan kind "plan command should dispatch as :plan")
      (assert-true (search "Current plan: Build tool registry" result)
                   "plan command should return the current plan message")
      (assert-equal "Build tool registry"
                    (tutor-codex::agent-session-plan updated-session)
                    "plan command should update session plan state"))))

(defun session-save-load-test ()
  (let* ((path #P"/tmp/tutor-codex-session-test.sexp")
         (session (tutor-codex::make-default-session)))
    (tutor-codex::update-session-plan session "Persist session")
    (tutor-codex::append-transcript-entry session :user "hello")
    (tutor-codex::save-session session path)
    (let ((loaded (tutor-codex::load-session path)))
      (assert-equal "Persist session"
                    (tutor-codex::agent-session-plan loaded)
                    "loaded session should preserve plan")
      (assert-equal 1
                    (length (tutor-codex::agent-session-transcript loaded))
                    "loaded session should preserve transcript entries"))))

(defun session-shell-commands-test ()
  (let* ((provider (tutor-codex::make-provider (tutor-codex::load-config)))
         (path "/tmp/tutor-codex-shell-session.sexp")
         (session (tutor-codex::make-default-session)))
    (tutor-codex::update-session-plan session "Shell persistence")
    (multiple-value-bind (describe-result describe-kind described-session)
        (tutor-codex::execute-command
         (tutor-codex::normalize-form-command '(describe-session))
         provider
         session)
      (declare (ignore described-session))
      (assert-equal :describe-session describe-kind
                    "describe-session should dispatch correctly")
      (assert-equal "Shell persistence"
                    (getf describe-result :plan)
                    "describe-session should report the current plan"))
    (multiple-value-bind (save-result save-kind saved-session)
        (tutor-codex::execute-command
         (tutor-codex::normalize-form-command `(session/save ,path))
         provider
         session)
      (declare (ignore saved-session))
      (assert-equal :session-save save-kind
                    "session/save should dispatch correctly")
      (assert-equal path (getf save-result :saved)
                    "session/save should report the saved path"))
    (let ((fresh-session (tutor-codex::reset-session session)))
      (assert-true (null (tutor-codex::agent-session-plan fresh-session))
                   "reset-session should clear the plan"))
    (multiple-value-bind (load-result load-kind loaded-session)
        (tutor-codex::execute-command
         (tutor-codex::normalize-form-command `(session/load ,path))
         provider
         (tutor-codex::make-default-session))
      (assert-equal :session-load load-kind
                    "session/load should dispatch correctly")
      (assert-equal path (getf load-result :loaded)
                    "session/load should report the loaded path")
      (assert-equal "Shell persistence"
                    (tutor-codex::agent-session-plan loaded-session)
                    "session/load should restore the saved plan"))))

(defun list-tools-test ()
  (let ((tools (tutor-codex::list-tools)))
    (assert-true (find :fs/read tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :fs/read")
    (assert-true (find :proc/run tools :key (lambda (entry) (getf entry :id)))
                 "tool registry should include :proc/run")
    (assert-equal :process-run
                  (getf (tutor-codex::describe-tool :proc/run) :policy)
                  "process tool should advertise process-run policy")))

(defun fs-read-tool-test ()
  (let* ((provider (tutor-codex::make-provider (tutor-codex::load-config)))
         (session (tutor-codex::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (command (tutor-codex::normalize-form-command '(tool :fs/read :path "src/main.lisp"))))
    (multiple-value-bind (result kind updated-session)
        (tutor-codex::execute-command command provider session)
      (declare (ignore updated-session))
      (assert-equal :tool kind "tool command should dispatch as :tool")
      (assert-equal :fs/read (getf result :tool) "fs/read should identify itself")
      (assert-true (search "(defun print-help ()" (getf result :content))
                   "fs/read should return file contents"))))

(defun proc-run-approval-test ()
  (let* ((provider (tutor-codex::make-provider (tutor-codex::load-config)))
         (session (tutor-codex::make-default-session))
         (command (tutor-codex::normalize-form-command '(tool :proc/run :argv ("/bin/echo" "hello")))))
    (assert-signals-error
     (lambda () (tutor-codex::execute-command command provider session))
     "Approval required"
     "process tool should require approval before execution")))

(defun approve-and-run-tool-test ()
  (let* ((provider (tutor-codex::make-provider (tutor-codex::load-config)))
         (session (tutor-codex::make-default-session)))
    (tutor-codex::execute-command
     (tutor-codex::normalize-form-command '(approve :process-run)) provider session)
    (multiple-value-bind (result kind updated-session)
        (tutor-codex::execute-command
         (tutor-codex::normalize-form-command '(tool :proc/run :argv ("/bin/echo" "hello")))
         provider
         session)
      (declare (ignore updated-session))
      (assert-equal :tool kind "process tool should dispatch as :tool after approval")
      (assert-equal 0 (getf result :exit-code) "process tool should return exit code 0")
      (assert-true (search "hello" (getf result :stdout))
                   "process tool should capture stdout after approval"))))

(defun patch-approval-and-apply-test ()
  (let* ((provider (tutor-codex::make-provider (tutor-codex::load-config)))
         (session (tutor-codex::make-default-session :cwd "/tmp/"))
         (path "/tmp/tutor-codex-patch-test.txt")
         (patch-command '(patch ((:write "tutor-codex-patch-test.txt" "patched")))))
    (assert-signals-error
     (lambda ()
       (tutor-codex::execute-command (tutor-codex::normalize-form-command patch-command)
                                     provider
                                     session))
     "Approval required"
     "patch application should require workspace-write approval")
    (tutor-codex::execute-command
     (tutor-codex::normalize-form-command '(approve :workspace-write)) provider session)
    (multiple-value-bind (result kind updated-session)
        (tutor-codex::execute-command (tutor-codex::normalize-form-command patch-command)
                                      provider
                                      session)
      (declare (ignore updated-session))
      (assert-equal :patch kind "patch command should dispatch as :patch after approval")
      (assert-equal :write (getf (first (getf result :patch)) :operation)
                    "patch should apply write operation")
      (with-open-file (stream path :direction :input)
        (let ((line (read-line stream nil nil)))
          (assert-equal "patched" line "patch should write file contents"))))))

(defun run-all-tests ()
  (format t "Running tutor-codex test suite...~%")
  (runtime-smoke-test)
  (format t "PASS runtime-smoke-test~%")
  (json-roundtrip-test)
  (format t "PASS json-roundtrip-test~%")
  (provider-decode-test)
  (format t "PASS provider-decode-test~%")
  (openai-provider-selection-test)
  (format t "PASS openai-provider-selection-test~%")
  (command-normalization-test)
  (format t "PASS command-normalization-test~%")
  (shell-eval-test)
  (format t "PASS shell-eval-test~%")
  (ask-dispatch-test)
  (format t "PASS ask-dispatch-test~%")
  (assistant-action-proposal-test)
  (format t "PASS assistant-action-proposal-test~%")
  (assistant-action-staging-test)
  (format t "PASS assistant-action-staging-test~%")
  (assistant-action-execution-test)
  (format t "PASS assistant-action-execution-test~%")
  (session-plan-test)
  (format t "PASS session-plan-test~%")
  (session-save-load-test)
  (format t "PASS session-save-load-test~%")
  (session-shell-commands-test)
  (format t "PASS session-shell-commands-test~%")
  (list-tools-test)
  (format t "PASS list-tools-test~%")
  (fs-read-tool-test)
  (format t "PASS fs-read-tool-test~%")
  (proc-run-approval-test)
  (format t "PASS proc-run-approval-test~%")
  (approve-and-run-tool-test)
  (format t "PASS approve-and-run-tool-test~%")
  (patch-approval-and-apply-test)
  (format t "PASS patch-approval-and-apply-test~%")
  (format t "All tests passed.~%")
  t)
