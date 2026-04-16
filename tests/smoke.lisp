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
  (let ((config (sbcl-agent::load-config))
        (provider (sbcl-agent::make-provider (sbcl-agent::load-config))))
    (assert-true (typep config 'sbcl-agent::config)
                 "load-config should return a sbcl-agent config struct")
    (assert-true (string= (sbcl-agent::provider-name provider) "mock")
                 "default provider should be mock")
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

(defun command-normalization-test ()
  (let ((ask-command (sbcl-agent::normalize-form-command '(ask "inspect src/main.lisp")))
        (execute-actions-command (sbcl-agent::normalize-form-command '(execute-actions)))
        (describe-session-command (sbcl-agent::normalize-form-command '(describe-session)))
        (enqueue-task-command (sbcl-agent::normalize-form-command '(enqueue-task '(tool :fs/read :path "src/main.lisp"))))
        (run-next-task-command (sbcl-agent::normalize-form-command '(run-next-task)))
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
  (let ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
        (assert-equal 4 (length (sbcl-agent::agent-session-events updated-session))
                      "ask dispatch should record command, transcript, and response events")))))

(defun streaming-provider-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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

(defun streaming-ask-dispatch-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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


(defun ask-enqueue-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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

(defun task-persistence-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (response (sbcl-agent::send-prompt provider "please read src/main.lisp" session)))
    (assert-equal 1 (length (sbcl-agent::assistant-response-actions response))
                  "mock provider should propose one read action")
    (assert-equal :TOOL
                  (sbcl-agent::assistant-action-type (first (sbcl-agent::assistant-response-actions response)))
                  "proposed action should be a tool action")))

(defun assistant-action-staging-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (command (sbcl-agent::normalize-form-command '(ask "please read src/main.lisp"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (declare (ignore kind))
      (assert-equal 1 (getf result :staged-action-count)
                    "ask flow should stage one proposed action")
      (assert-equal 1 (length (sbcl-agent::agent-session-pending-actions updated-session))
                    "session should retain one staged action")
      (assert-true (= 0 (length (or (getf result :action-results) '())))
                   "ask flow should not execute actions immediately"))))

(defun assistant-action-execution-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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

(defun session-plan-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (command (sbcl-agent::normalize-form-command '(tool :docs/read :path "architecture.md"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (declare (ignore updated-session))
      (assert-equal :tool kind "docs/read should dispatch as :tool")
      (assert-equal :docs/read (getf result :tool) "docs/read should identify itself")
      (assert-true (search "turtles all the way down" (string-downcase (getf result :content)))
                   "docs/read should return maintained architecture content"))))

(defun docs-read-path-escape-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (command (sbcl-agent::normalize-form-command '(tool :docs/read :path "../README.md"))))
    (assert-signals-error
     (lambda () (sbcl-agent::execute-command command provider session))
     "escapes the current session workspace"
     "docs/read should reject paths outside the docs root")))

(defun fs-read-tool-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
         (session (sbcl-agent::make-default-session :cwd "/Volumes/data/development/sbcl-agent/"))
         (command (sbcl-agent::normalize-form-command '(tool :fs/read :path "../README.md"))))
    (assert-signals-error
     (lambda () (sbcl-agent::execute-command command provider session))
     "escapes the current session workspace"
     "fs/read should reject paths outside the session root")))

(defun proc-run-approval-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
         (session (sbcl-agent::make-default-session))
         (command (sbcl-agent::normalize-form-command '(tool :proc/run :argv ("/bin/echo" "hello")))))
    (assert-signals-error
     (lambda () (sbcl-agent::execute-command command provider session))
     "Approval required"
     "process tool should require approval before execution")))

(defun approve-and-run-tool-test ()
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
         (session (sbcl-agent::make-default-session :cwd (namestring (make-test-git-repo))))
         (command (sbcl-agent::normalize-form-command '(tool :git/status))))
    (assert-signals-error
     (lambda () (sbcl-agent::execute-command command provider session))
     "Approval required"
     "git status should require explicit git-read approval")))

(defun git-status-and-diff-test ()
  (let* ((repo (make-test-git-repo))
         (provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
         (provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (let* ((provider (sbcl-agent::make-provider (sbcl-agent::load-config)))
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
  (command-normalization-test)
  (format t "PASS command-normalization-test~%")
  (shell-eval-test)
  (format t "PASS shell-eval-test~%")
  (ask-dispatch-test)
  (format t "PASS ask-dispatch-test~%")
  (streaming-provider-test)
  (format t "PASS streaming-provider-test~%")
  (streaming-ask-dispatch-test)
  (format t "PASS streaming-ask-dispatch-test~%")
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
  (task-persistence-test)
  (format t "PASS task-persistence-test~%")
  (assistant-action-proposal-test)
  (format t "PASS assistant-action-proposal-test~%")
  (assistant-action-staging-test)
  (format t "PASS assistant-action-staging-test~%")
  (assistant-action-execution-test)
  (format t "PASS assistant-action-execution-test~%")
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
