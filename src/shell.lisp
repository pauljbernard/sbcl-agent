(in-package #:sbcl-agent)

(defparameter *shell-package* (find-package '#:sbcl-agent-user))
(defparameter *stream-event-listener* nil)

(defun print-shell-help ()
  (format t "Lisp shell commands:~%")
  (format t "  (ask \"prompt\")                   Send a prompt to the configured provider and stage proposed actions.~%")
  (format t "  (ask \"prompt\" :stream t)         Stream assistant output while building the final response.~%")
  (format t "  (ask \"prompt\" :enqueue t)        Queue an agent request instead of executing it inline.~%")
  (format t "  (execute-actions)                  Execute the currently staged assistant actions.~%")
  (format t "  (plan \"goal\")                    Set the current session plan goal.~%")
  (format t "  (enqueue-task '(tool ...))         Queue a normalized shell form for later execution.~%")
  (format t "  (list-tasks)                       Show queued and completed task summaries.~%")
  (format t "  (describe-task \"task-id\")         Show one task summary.~%")
  (format t "  (monitor-task \"task-id\")          Show recent progress events for one task.~%")
  (format t "  (run-next-task)                    Execute the next queued task in the current image.~%")
  (format t "  (start-worker)                     Start a background worker thread for queued tasks.~%")
  (format t "  (stop-worker \"worker-id\")         Stop a background worker thread.~%")
  (format t "  (list-workers)                     Show worker summaries for the current session.~%")
  (format t "  (list-work-items)                  Show work-item summaries for the current session.~%")
  (format t "  (describe-work-item \"work-id\")   Show one work-item detail record.~%")
  (format t "  (list-workflow-records)           Show workflow records for the current session.~%")
  (format t "  (describe-workflow-record \"wf-id\") Show one workflow record with its durable log entries.~%")
  (format t "  (request-work-item-approval \"work-id\" :policy [:reason \"...\"]) Mark a work-item as waiting for approval.~%")
  (format t "  (quarantine-work-item \"work-id\" \"reason\") Quarantine a work-item for operator review.~%")
  (format t "  (resume-work-item \"work-id\" [:note \"...\"]) Resume a quarantined or waiting work-item.~%")
  (format t "  (describe-worker \"worker-id\")     Show one worker summary.~%")
  (format t "  (approve :process-run)             Grant a capability policy to the current session.~%")
  (format t "  (tool :fs/read :path \"file\")     Read a workspace file.~%")
  (format t "  (tool :fs/list :path \"dir\")      List a workspace directory.~%")
  (format t "  (tool :proc/run :argv '(...))       Run a local process after approval.~%")
  (format t "  (patch '((:write \"file\" \"...\"))) Apply a patch after workspace-write approval.~%")
  (format t "  (session/save \"path\")            Persist the current session as an s-expression.~%")
  (format t "  (session/load \"path\")            Load a persisted session into the current image.~%")
  (format t "  (session/reset)                    Replace the current session with a fresh one.~%")
  (format t "  (describe-session)                 Print a summary of the current session state.~%")
  (format t "  (help)                             Show this message.~%")
  (format t "  Any other form is evaluated in the SBCL-AGENT-USER package.~%"))

(defun shell-prompt (session)
  (format *query-io* "~A[~A]> "
          (package-name *shell-package*)
          (agent-session-id session))
  (finish-output *query-io*))

(defun read-shell-form (session)
  (shell-prompt session)
  (read *query-io* nil :eof))

(defun eval-user-form (form)
  (let ((*package* *shell-package*))
    (eval form)))

(defun execute-tool-command (arguments session)
  (unless arguments
    (error "TOOL requires a tool id"))
  (let ((tool-id (first arguments))
        (tool-args (rest arguments)))
    (unless (keywordp tool-id)
      (error "TOOL id must be a keyword, got ~S" tool-id))
    (apply #'invoke-tool tool-id session tool-args)))

(defun execute-approve-command (arguments session)
  (let ((policy (first arguments)))
    (unless (keywordp policy)
      (error "APPROVE requires a keyword policy"))
    (approve-policy session policy)
    (list :approved policy
          :approved-policies (session-approved-policies session)
          :capability-grants (session-capability-grants-summary session))))

(defun execute-patch-command (arguments session)
  (let ((operations (first arguments)))
    (apply-patch-operations session operations)))

(defun stage-response-actions (response session)
  (let ((actions (assistant-response-actions response)))
    (when actions
      (stage-pending-actions session actions))
    actions))

(defun execute-pending-actions-command (session)
  (let ((actions (agent-session-pending-actions session)))
    (unless actions
      (error "No pending assistant actions are staged in the current session"))
    (let ((results (execute-assistant-action-list actions session)))
      (clear-pending-actions session)
      results)))

(defun execute-session-save-command (arguments session)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "SESSION/SAVE requires a string path"))
    (save-session session path)
    (list :saved path :summary (session-summary session))))

(defun execute-session-load-command (arguments)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "SESSION/LOAD requires a string path"))
    (let ((session (load-session path)))
      (values (list :loaded path :summary (session-summary session)) session))))

(defun plist-value (plist indicator &optional default)
  (if (and (listp plist) (member indicator plist))
      (getf plist indicator)
      default))

(defun parse-ask-arguments (arguments)
  (let ((prompt (first arguments))
        (options (rest arguments)))
    (unless (stringp prompt)
      (error "ASK requires a single string prompt"))
    (when (oddp (length options))
      (error "ASK keyword options must be a property list"))
    (values prompt options)))

(defun render-stream-event (event)
  (case (provider-event-type event)
    (:message-start
     (format t "assistant-stream> "))
    (:message-delta
     (format t "~A" (provider-event-payload event))
     (finish-output))
    (:message-complete
     (format t "~%")
     (finish-output))
    (:action-proposal nil)
    (t
     (format t "~&assistant-stream-event> ~S~%" event))))

(defun handle-provider-stream-event (session event events)
  (append-session-event session :provider-stream event)
  (when *task-progress-callback*
    (funcall *task-progress-callback* :provider-stream event))
  (when *stream-event-listener*
    (funcall *stream-event-listener* event))
  (append events (list event)))

(defun remove-plist-key (plist key)
  (cond
    ((null plist) '())
    ((eq (first plist) key)
     (remove-plist-key (cddr plist) key))
    (t
     (list* (first plist)
            (second plist)
            (remove-plist-key (cddr plist) key)))))

(defun ask-task-form (prompt options)
  (cons 'ask (cons prompt (remove-plist-key options :enqueue))))

(defun execute-ask-command (arguments provider session)
  (multiple-value-bind (prompt options)
      (parse-ask-arguments arguments)
    (if (plist-value options :enqueue nil)
        (let* ((task-form (ask-task-form prompt options))
               (task (enqueue-task session
                                   (normalize-form-command task-form)
                                   :payload task-form)))
          (values (list :queued-task (task-summary task)
                        :enqueued-p t)
                  :ask
                  session))
        (progn
          (append-transcript-entry session :user prompt)
          (let ((stream-p (or (plist-value options :stream nil)
                              (not (null *task-progress-callback*)))))
            (when *task-progress-callback*
              (funcall *task-progress-callback* :ask-started (list :prompt prompt :stream-p stream-p)))
            (if stream-p
                (let ((events '()))
                  (let ((response (stream-prompt provider
                                                 prompt
                                                 (lambda (event)
                                                   (setf events (handle-provider-stream-event session event events)))
                                                 session)))
                    (let ((staged-actions (stage-response-actions response session)))
                      (append-transcript-entry session :assistant (assistant-response->string response))
                      (append-session-event session :assistant-response response)
                      (when *task-progress-callback*
                        (funcall *task-progress-callback*
                                 :ask-response
                                 (list :message (assistant-response-message response)
                                       :staged-action-count (length staged-actions)
                                       :stream-event-count (length events))))
                      (values (list :response response
                                    :staged-action-count (length staged-actions)
                                    :streamed-p t
                                    :stream-event-count (length events)
                                    :stream-events events)
                              :ask
                              session))))
                (let* ((response (send-prompt provider prompt session))
                       (staged-actions (stage-response-actions response session)))
                  (append-transcript-entry session :assistant (assistant-response->string response))
                  (append-session-event session :assistant-response response)
                  (when *task-progress-callback*
                    (funcall *task-progress-callback*
                             :ask-response
                             (list :message (assistant-response-message response)
                                   :staged-action-count (length staged-actions)
                                   :stream-event-count 0)))
                  (values (list :response response
                                :staged-action-count (length staged-actions)
                                :streamed-p nil
                                :stream-event-count 0)
                          :ask
                          session))))))))

(defun unwrap-task-form (form)
  (if (and (consp form)
           (eq (first form) 'quote)
           (= (length form) 2))
      (second form)
      form))

(defun execute-enqueue-task-command (arguments session)
  (let* ((raw-form (first arguments))
         (form (unwrap-task-form raw-form))
         (priority (or (getf (rest arguments) :priority) 0))
         (command (normalize-form-command form))
         (task (enqueue-task session command :priority priority :payload form)))
    (task-summary task)))

(defun execute-describe-task-command (arguments session)
  (let ((task-id (first arguments)))
    (unless (stringp task-id)
      (error "DESCRIBE-TASK requires a string task id"))
    (let ((task (find-task session task-id)))
      (unless task
        (error "Unknown task ~A" task-id))
      (task-summary task))))

(defun execute-monitor-task-command (arguments session)
  (let ((task-id (first arguments)))
    (unless (stringp task-id)
      (error "MONITOR-TASK requires a string task id"))
    (let ((task (find-task session task-id)))
      (unless task
        (error "Unknown task ~A" task-id))
      (task-monitor-view task))))

(defun execute-cancel-task-command (arguments session)
  (let ((task-id (first arguments)))
    (unless (stringp task-id)
      (error "CANCEL-TASK requires a string task id"))
    (task-summary (cancel-task session task-id))))

(defun execute-start-worker-command (provider session)
  (let ((worker (start-worker session provider)))
    (worker-summary worker)))

(defun execute-stop-worker-command (arguments session)
  (let ((worker-id (first arguments)))
    (unless (stringp worker-id)
      (error "STOP-WORKER requires a string worker id"))
    (worker-summary (stop-worker session worker-id))))

(defun execute-describe-worker-command (arguments session)
  (let ((worker-id (first arguments)))
    (unless (stringp worker-id)
      (error "DESCRIBE-WORKER requires a string worker id"))
    (let ((worker (find-worker session worker-id)))
      (unless worker
        (error "Unknown worker ~A" worker-id))
      (worker-summary worker))))

(defun enriched-work-item-detail (session work-item)
  (let ((detail (work-item-detail work-item))
        (record (work-item-workflow-record session work-item)))
    (if record
        (append detail (list :workflow-record (workflow-record-summary record)))
        detail)))

(defun execute-describe-work-item-command (arguments session)
  (let ((work-item-id (first arguments)))
    (unless (stringp work-item-id)
      (error "DESCRIBE-WORK-ITEM requires a string work-item id"))
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (enriched-work-item-detail session work-item))))

(defun execute-describe-workflow-record-command (arguments session)
  (let ((workflow-record-id (first arguments)))
    (unless (stringp workflow-record-id)
      (error "DESCRIBE-WORKFLOW-RECORD requires a string workflow record id"))
    (let ((record (find-workflow-record session workflow-record-id)))
      (unless record
        (error "Unknown workflow record ~A" workflow-record-id))
      (workflow-record-detail record))))
(defun execute-request-work-item-approval-command (arguments session)
  (let ((work-item-id (first arguments))
        (policy (second arguments))
        (reason (getf (cddr arguments) :reason)))
    (unless (stringp work-item-id)
      (error "REQUEST-WORK-ITEM-APPROVAL requires a string work-item id"))
    (unless (keywordp policy)
      (error "REQUEST-WORK-ITEM-APPROVAL requires a keyword policy"))
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (request-work-item-approval session work-item policy :reason reason)
      (enriched-work-item-detail session work-item))))

(defun execute-quarantine-work-item-command (arguments session)
  (let ((work-item-id (first arguments))
        (reason (second arguments)))
    (unless (stringp work-item-id)
      (error "QUARANTINE-WORK-ITEM requires a string work-item id"))
    (unless (stringp reason)
      (error "QUARANTINE-WORK-ITEM requires a string reason"))
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (quarantine-work-item session work-item reason :evidence (work-item-summary work-item))
      (enriched-work-item-detail session work-item))))

(defun execute-resume-work-item-command (arguments session)
  (let ((work-item-id (first arguments))
        (note (getf (rest arguments) :note)))
    (unless (stringp work-item-id)
      (error "RESUME-WORK-ITEM requires a string work-item id"))
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (resume-work-item session work-item :note note)
      (enriched-work-item-detail session work-item))))

(defun execute-why-waiting-command (arguments session)
  (let ((work-item-id (first arguments)))
    (unless (stringp work-item-id)
      (error "WHY-WAITING requires a string work-item id"))
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (work-item-wait-report session work-item))))

(defun execute-list-replay-groups-command (session)
  (session-validator-replay-groups session))

(defun execute-list-image-reconciliations-command (session)
  (session-image-reconciliation-summary session))

(defun execute-replay-validator-task-command (arguments session)
  (let ((work-item-id (first arguments))
        (validator-task-id (second arguments))
        (status (or (getf (cddr arguments) :status) :passed)))
    (unless (stringp work-item-id)
      (error "REPLAY-VALIDATOR-TASK requires a string work-item id"))
    (unless (stringp validator-task-id)
      (error "REPLAY-VALIDATOR-TASK requires a string validator task id"))
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (execute-validator-task-record session work-item validator-task-id :status status)
      (enriched-work-item-detail session work-item))))

(defun execute-replay-validator-set-command (arguments session)
  (let ((work-item-id (first arguments))
        (replay-id (second arguments))
        (status (or (getf (cddr arguments) :status) :passed))
        (statuses (getf (cddr arguments) :statuses)))
    (unless (stringp work-item-id)
      (error "REPLAY-VALIDATOR-SET requires a string work-item id"))
    (unless (stringp replay-id)
      (error "REPLAY-VALIDATOR-SET requires a string replay id"))
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (execute-validator-replay-set session work-item replay-id :status status :statuses statuses)
      (enriched-work-item-detail session work-item))))

(defun execute-reconcile-image-only-source-command (arguments session)
  (let ((work-item-id (first arguments))
        (summary (second arguments)))
    (unless (stringp work-item-id)
      (error "RECONCILE-IMAGE-ONLY-SOURCE requires a string work-item id"))
    (unless (stringp summary)
      (error "RECONCILE-IMAGE-ONLY-SOURCE requires a string summary"))
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (reconcile-image-only-work-item-to-source session work-item summary)
      (enriched-work-item-detail session work-item))))


(defun execute-command (command provider &optional session)
  (let ((active-session (ensure-session session)))
    (append-session-event active-session :command (command-summary command))
    (case (command-kind command)
      (:eval
       (let ((result (eval-user-form (command-form command))))
         (append-transcript-entry active-session :user (command-form command))
         (append-transcript-entry active-session :system result)
         (values result :eval active-session)))
      (:ask
       (execute-ask-command (command-arguments command) provider active-session))
      (:execute-actions
       (let ((result (execute-pending-actions-command active-session)))
         (values result :execute-actions active-session)))
      (:plan
       (let ((goal (first (command-arguments command))))
         (unless (stringp goal)
           (error "PLAN requires a single string goal"))
         (update-session-plan active-session goal)
         (values (format nil "Current plan: ~A" goal) :plan active-session)))
      (:enqueue-task
       (values (execute-enqueue-task-command (command-arguments command) active-session)
               :enqueue-task
               active-session))
      (:list-tasks
       (values (list-task-summaries active-session) :list-tasks active-session))
      (:describe-task
       (values (execute-describe-task-command (command-arguments command) active-session)
               :describe-task
               active-session))
      (:cancel-task
       (values (execute-cancel-task-command (command-arguments command) active-session)
               :cancel-task
               active-session))
      (:monitor-task
       (values (execute-monitor-task-command (command-arguments command) active-session)
               :monitor-task
               active-session))
      (:run-next-task
       (values (task-summary (run-next-task active-session provider))
               :run-next-task
               active-session))
      (:start-worker
       (values (execute-start-worker-command provider active-session)
               :start-worker
               active-session))
      (:stop-worker
       (values (execute-stop-worker-command (command-arguments command) active-session)
               :stop-worker
               active-session))
      (:list-workers
       (values (list-worker-summaries active-session) :list-workers active-session))
      (:list-work-items
       (values (list-work-item-summaries active-session) :list-work-items active-session))
      (:describe-work-item
       (values (execute-describe-work-item-command (command-arguments command) active-session)
               :describe-work-item
               active-session))
      (:list-workflow-records
       (values (list-workflow-record-summaries active-session) :list-workflow-records active-session))
      (:describe-workflow-record
       (values (execute-describe-workflow-record-command (command-arguments command) active-session)
               :describe-workflow-record
               active-session))
      (:request-work-item-approval
       (values (execute-request-work-item-approval-command (command-arguments command) active-session)
               :request-work-item-approval
               active-session))
      (:quarantine-work-item
       (values (execute-quarantine-work-item-command (command-arguments command) active-session)
               :quarantine-work-item
               active-session))
      (:resume-work-item
       (values (execute-resume-work-item-command (command-arguments command) active-session)
               :resume-work-item
               active-session))
      (:why-waiting
       (values (execute-why-waiting-command (command-arguments command) active-session)
               :why-waiting
               active-session))
      (:list-replay-groups
       (values (execute-list-replay-groups-command active-session)
               :list-replay-groups
               active-session))
      (:list-image-reconciliations
       (values (execute-list-image-reconciliations-command active-session)
               :list-image-reconciliations
               active-session))
      (:replay-validator-task
       (values (execute-replay-validator-task-command (command-arguments command) active-session)
               :replay-validator-task
               active-session))
      (:replay-validator-set
       (values (execute-replay-validator-set-command (command-arguments command) active-session)
               :replay-validator-set
               active-session))
      (:reconcile-image-only-source
       (values (execute-reconcile-image-only-source-command (command-arguments command) active-session)
               :reconcile-image-only-source
               active-session))
      (:describe-worker
       (values (execute-describe-worker-command (command-arguments command) active-session)
               :describe-worker
               active-session))
      (:approve
       (let ((result (execute-approve-command (command-arguments command) active-session)))
         (values result :approve active-session)))
      (:tool
       (let ((result (execute-tool-command (command-arguments command) active-session)))
         (append-transcript-entry active-session :tool result)
         (values result :tool active-session)))
      (:patch
       (let ((result (execute-patch-command (command-arguments command) active-session)))
         (append-transcript-entry active-session :patch result)
         (values result :patch active-session)))
      (:session-save
       (let ((result (execute-session-save-command (command-arguments command) active-session)))
         (values result :session-save active-session)))
      (:session-load
       (multiple-value-bind (result loaded-session)
           (execute-session-load-command (command-arguments command))
         (values result :session-load loaded-session)))
      (:session-reset
       (let ((fresh-session (reset-session active-session)))
         (values (list :reset (agent-session-id fresh-session)
                       :summary (session-summary fresh-session))
                 :session-reset
                 fresh-session)))
      (:describe-session
       (values (session-summary active-session) :describe-session active-session))
      (:help
       (print-shell-help)
       (values nil :help active-session))
      (t
       (error "Unsupported command kind ~S" (command-kind command))))))

(defun print-shell-result (result kind)
  (case kind
    (:help nil)
    (:ask
     (if (getf result :enqueued-p)
         (format t "assistant-task> ~S~%" (getf result :queued-task))
         (let ((response (getf result :response))
               (staged-count (getf result :staged-action-count)))
           (unless (getf result :streamed-p)
             (format t "assistant> ~A~%" (assistant-response->string response)))
           (when (assistant-response-actions response)
             (format t "assistant-actions> ~S~%" (assistant-response-actions response))
             (format t "assistant-actions-staged> ~D~%" staged-count)))))
    ((:enqueue-task :list-tasks :describe-task :cancel-task :monitor-task :run-next-task :start-worker :stop-worker :list-workers :describe-worker :list-work-items :describe-work-item :list-workflow-records :describe-workflow-record :request-work-item-approval :quarantine-work-item :resume-work-item :why-waiting :list-replay-groups :list-image-reconciliations :replay-validator-task :replay-validator-set :reconcile-image-only-source)
     (format t "tasks> ~S~%" result))
    (:execute-actions
     (format t "assistant-action-results> ~S~%" result))
    (:plan
     (format t "planner> ~A~%" result))
    (:approve
     (format t "approval> ~S~%" result))
    (:tool
     (format t "tool> ~S~%" result))
    (:patch
     (format t "patch> ~S~%" result))
    (:session-save
     (format t "session> ~S~%" result))
    (:session-load
     (format t "session> ~S~%" result))
    (:session-reset
     (format t "session> ~S~%" result))
    (:describe-session
     (format t "session> ~S~%" result))
    (t
     (format t "=> ~S~%" result))))

(defun start-shell (provider &optional session)
  (let ((active-session (ensure-session session)))
    (format t "Starting Lisp-native shell with provider ~A.~%" (provider-name provider))
    (format t "Session: ~A~%" (agent-session-id active-session))
    (format t "Enter (help) for commands. Press Ctrl-D to exit.~%")
    (let ((*stream-event-listener* #'render-stream-event))
      (loop
        for form = (read-shell-form active-session)
        do (if (eq form :eof)
               (progn
                 (format t "~%")
                 (return 0))
               (handler-case
                   (multiple-value-bind (result kind updated-session)
                       (execute-command (normalize-form-command form) provider active-session)
                     (setf active-session updated-session
                           *current-session* updated-session)
                     (print-shell-result result kind))
                 (error (condition)
                   (format *error-output* "error> ~A~%" condition))))))))
