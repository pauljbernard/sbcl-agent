(in-package #:sbcl-agent)

(defparameter *shell-package* (find-package '#:sbcl-agent-user))
(defparameter *stream-event-listener* nil)
(defparameter *default-ask-streaming* nil)

(defun print-shell-help ()
  (format t "Lisp shell commands:~%")
  (format t "  (ask \"prompt\")                   Send a prompt to the configured provider and stage proposed actions.~%")
  (format t "  (say \"prompt\")                   Conversation-style alias for ASK. Same execution path today.~%")
  (format t "  (ask \"prompt\" :stream t)         Stream assistant output while building the final response.~%")
  (format t "  (ask \"prompt\" :enqueue t)        Queue an agent request instead of executing it inline.~%")
  (format t "  (thread/new [:title \"name\"])      Create and select a conversation thread.~%")
  (format t "  (thread/list)                      List conversation threads in the current session.~%")
  (format t "  (thread/use \"thread-id\")          Select the active conversation thread.~%")
  (format t "  (thread/show [\"thread-id\"])       Show one thread with persisted messages and turns.~%")
  (format t "  (turn/status [\"turn-id\"])         Show one turn, or the latest turn on the active thread.~%")
  (format t "  (turn/resume [\"turn-id\"])         Resume an approval-gated turn using current pending actions.~%")
  (format t "  (incident/list)                    List recorded incidents for the current session.~%")
  (format t "  (incident/show \"incident-id\")     Show one incident with linked turn, operation, and workflow context.~%")
  (format t "  (environment/status)               Show where you are, what is blocked, and what needs attention next.~%")
  (format t "  (review/mutation [\"turn-id\"])     Show mutation, evidence, incidents, and closure state in one view.~%")
  (format t "  (integration/rgp-bind :request-id \"req\" :agent-session-id \"sess\") Bind this environment to an RGP governed runtime session.~%")
  (format t "  (integration/rgp-show)              Show the governed-runtime snapshot RGP will reconcile.~%")
  (format t "  (integration/rgp-export \"path\")   Export the governed-runtime snapshot as JSON for RGP ingest.~%")
  (format t "  (integration/rgp-artifacts)         Show artifact summaries with lineage fields for RGP import.~%")
  (format t "  (integration/rgp-approvals)         Show blocked approvals and resumable work-items for governed runtime control.~%")
  (format t "  (integration/rgp-approve \"work-id\" :policy [:reason \"...\"]) Mark a governed runtime checkpoint as awaiting approval.~%")
  (format t "  (integration/rgp-resume \"work-id\" [:note \"...\"]) Resume a governed runtime work-item after operator action.~%")
  (format t "  (runtime/current-package)           Show the active Lisp package for the current runtime session.~%")
  (format t "  (runtime/list-loaded-systems)       Show ASDF systems currently loaded in the image.~%")
  (format t "  (runtime/describe-symbol \"name\" [:package \"PKG\"]) Inspect one symbol in the live image.~%")
  (format t "  (runtime/find-definition \"name\" [:package \"PKG\"]) Find workspace definitions for a symbol and relate them to the image.~%")
  (format t "  (runtime/callers \"name\" [:package \"PKG\"]) Find source-level callers for a symbol in the workspace.~%")
  (format t "  (runtime/methods \"name\" [:package \"PKG\"]) List generic-function methods for a symbol in the image.~%")
  (format t "  (runtime/source-image-divergence \"name\" [:package \"PKG\"]) Report source/image presence and pending drift for a symbol.~%")
  (format t "  (runtime/set-package \"PKG\")       Change the active Lisp package after approval.~%")
  (format t "  (runtime/eval form|string [:mutating t]) Evaluate in the active runtime package with policy checks.~%")
  (format t "  (runtime/history [:tail N])         Show recent structured runtime operations recorded in the environment.~%")
  (format t "  (runtime/reload-file \"path\")      Load a workspace source file into the live image after approval.~%")
  (format t "  (environment/show)                  Print a summary of the current environment state.~%")
  (format t "  (environment/events [:tail N])      Show recent projected environment events.~%")
  (format t "  (environment/save \"path\")        Persist the current environment and compatibility session.~%")
  (format t "  (environment/load \"path\")        Load a persisted environment into the current image.~%")
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
    (service-response-data
     (command-approve-policy-service session policy))))

(defun execute-patch-command (arguments session)
  (let ((operations (first arguments)))
    (apply-patch-operations session operations)))

(defun split-assistant-actions (actions)
  (let ((immediate '())
        (staged '()))
    (dolist (action actions)
      (if (and (eq (assistant-action-type action) :eval)
               (not (mutating-eval-action-p action)))
          (push action immediate)
          (push action staged)))
    (values (nreverse immediate) (nreverse staged))))

(defun process-response-actions (response session)
  (multiple-value-bind (immediate staged)
      (split-assistant-actions (assistant-response-actions response))
    (let ((immediate-results (when immediate
                               (execute-assistant-action-list immediate session))))
      (if staged
          (stage-pending-actions session staged)
          (clear-pending-actions session))
      (list :immediate-actions immediate
            :immediate-results immediate-results
            :staged-actions staged))))

(defun execute-assistant-action-command (arguments session)
  (let ((action (first arguments)))
    (unless (typep action 'assistant-action)
      (error "ASSISTANT-ACTION command requires an assistant-action object"))
    (execute-assistant-action action session)))

(defun execute-pending-actions-command (session)
  (let ((actions (agent-session-pending-actions session)))
    (unless actions
      (error "No pending assistant actions are staged in the current session"))
    (let ((results (execute-assistant-action-list actions session)))
      (clear-pending-actions session)
      results)))

(defun execute-pending-actions-command-with-context (session &key thread turn operation)
  (let ((actions (agent-session-pending-actions session)))
    (unless actions
      (error "No pending assistant actions are staged in the current session"))
    (let ((results (execute-assistant-action-list actions
                                                  session
                                                  :thread thread
                                                  :turn turn
                                                  :operation operation)))
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

(defun render-provider-timing (phase payload)
  (format t "~&assistant-timing> ~S ~S~%" phase payload)
  (finish-output))

(defun render-stream-event (event)
  (case (provider-event-effective-type event)
    (:run-started
     (format t "assistant-stream> "))
    (:text-delta
     (format t "~A" (provider-event-payload event))
     (finish-output))
    (:text-complete
     (format t "~%")
     (finish-output))
    (:tool-intent nil)
    (t
     (format t "~&assistant-stream-event> ~S~%" event))))

(defun handle-provider-stream-event (session event events
                                   &key thread-id turn-id run-id operation-id)
  (let* ((resolved-thread-id (or thread-id
                                 (provider-event-thread-id event)))
         (resolved-turn-id (or turn-id
                               (provider-event-turn-id event)))
         (resolved-run-id (or run-id
                              (provider-event-run-id event)))
         (resolved-operation-id (or operation-id
                                    (provider-event-operation-id event)))
         (metadata (merge-event-metadata
                    (list :canonical-type (provider-event-effective-type event)
                          :legacy-type (provider-event-legacy-type event)
                          :provider-family (provider-event-family event))
                    (provider-event-metadata event))))
    (append-session-event session
                          :provider-stream
                          event
                          :family :provider
                          :entity-id (or (provider-event-entity-id event)
                                         resolved-run-id
                                         resolved-operation-id)
                          :thread-id resolved-thread-id
                          :turn-id resolved-turn-id
                          :visibility (provider-event-visibility event)
                          :metadata metadata
                          :run-id resolved-run-id
                          :operation-id resolved-operation-id)
    (when *task-progress-callback*
      (funcall *task-progress-callback* :provider-stream event))
    (when *stream-event-listener*
      (funcall *stream-event-listener* event))
    (append events (list event))))

(defun option-present-p (plist key)
  (and (listp plist)
       (member key plist)))

(defun print-shell-environment-orientation (&optional environment)
  (let* ((status (environment-status (ensure-environment environment)))
         (environment-info (getf status :environment))
         (active-thread (getf status :active-thread))
         (active-runtime (getf status :active-runtime))
         (blocked-work (getf status :blocked-work))
         (incidents (getf status :incidents))
         (operator-posture (getf status :operator-posture)))
    (format t "Environment: ~A~%"
            (or (getf environment-info :id) "<unknown>"))
    (format t "Orientation: thread=~A runtime=~A blocked=~D open-incidents=~D~%"
            (or (getf active-thread :id) :none)
            (or (getf active-runtime :runtime-id) :none)
            (or (getf blocked-work :count) 0)
            (or (getf incidents :open-count) 0))
    (format t "Operator posture: approvals=~D cold-validations=~D pending-validations=~D reviews=~D~%"
            (or (getf operator-posture :outstanding-approval-count) 0)
            (or (getf operator-posture :outstanding-cold-validation-count) 0)
            (or (getf operator-posture :outstanding-pending-validation-count) 0)
            (or (getf operator-posture :outstanding-operator-review-count) 0))
    (finish-output)
    status))

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
        (let ((stream-p (or (and (option-present-p options :stream)
                                 (plist-value options :stream nil))
                            *default-ask-streaming*
                            (not (null *task-progress-callback*)))))
          (values (run-conversation-turn provider
                                         session
                                         prompt
                                         :stream-p stream-p
                                         :source :ask
                                         :operator-mode :repl-bridge)
                  :ask
                  session)))))

(defun execute-say-command (arguments provider session)
  (multiple-value-bind (prompt options)
      (parse-ask-arguments arguments)
    (if (plist-value options :enqueue nil)
        (let* ((task-form (cons 'say (cons prompt (remove-plist-key options :enqueue))))
               (task (enqueue-task session
                                   (normalize-form-command task-form)
                                   :payload task-form)))
          (values (list :queued-task (task-summary task)
                        :enqueued-p t)
                  :say
                  session))
        (let ((stream-p (or (and (option-present-p options :stream)
                                 (plist-value options :stream nil))
                            *default-ask-streaming*
                            (not (null *task-progress-callback*)))))
          (values (run-say-turn provider session prompt :stream-p stream-p)
                  :say
                  session)))))

(defun execute-thread-new-command (arguments session)
  (let ((title (getf arguments :title)))
    (when (and title (not (stringp title)))
      (error "THREAD/NEW :TITLE must be a string"))
    (service-response-data
     (command-conversation-create-thread-service session :title title))))

(defun execute-thread-list-command (session)
  (service-response-data
   (query-conversation-thread-list-service session)))

(defun execute-thread-use-command (arguments session)
  (let ((thread-id (first arguments)))
    (unless (stringp thread-id)
      (error "THREAD/USE requires a string thread id"))
    (service-response-data
     (command-conversation-use-thread-service session thread-id))))

(defun execute-thread-show-command (arguments session)
  (let ((thread-id (first arguments)))
    (when (and thread-id (not (stringp thread-id)))
      (error "THREAD/SHOW requires a string thread id when provided"))
    (service-response-data
     (query-conversation-thread-detail-service session thread-id))))

(defun execute-turn-status-command (arguments session)
  (let ((turn-id (first arguments)))
    (when (and turn-id (not (stringp turn-id)))
      (error "TURN/STATUS requires a string turn id when provided"))
    (service-response-data
     (query-conversation-turn-detail-service session turn-id))))

(defun execute-incident-list-command (session)
  (service-response-data
   (query-incident-list-service session)))

(defun execute-incident-show-command (arguments session)
  (let ((incident-id (first arguments)))
    (unless (stringp incident-id)
      (error "INCIDENT/SHOW requires a string incident id"))
    (service-response-data
     (query-incident-detail-service session incident-id))))

(defun execute-environment-status-command (&optional environment)
  (service-response-data
   (query-environment-status-service environment)))

(defun execute-review-mutation-command (arguments session)
  (let ((turn-id (first arguments)))
    (when (and turn-id (not (stringp turn-id)))
      (error "REVIEW/MUTATION requires a string turn id when provided"))
    (mutation-review session turn-id)))

(defun execute-integration-rgp-bind-command (arguments session)
  (when (oddp (length arguments))
    (error "INTEGRATION/RGP-BIND arguments must be a property list"))
  (let* ((binding (bind-environment-to-rgp session
                                           :tenant-id (getf arguments :tenant-id)
                                           :request-id (getf arguments :request-id)
                                           :agent-session-id (getf arguments :agent-session-id)
                                           :integration-id (getf arguments :integration-id)
                                           :projection-id (getf arguments :projection-id)))
         (environment (ensure-environment)))
    (list :binding (rgp-binding-summary environment)
          :governed-runtime (environment-rgp-runtime-summary environment)
          :environment-id (environment-id environment)
          :session-id (agent-session-id session)
          :updated-binding binding)))

(defun execute-integration-rgp-show-command (session)
  (environment-rgp-snapshot (ensure-rgp-bound-environment session)))

(defun execute-integration-rgp-export-command (arguments session)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "INTEGRATION/RGP-EXPORT requires a string path"))
    (export-environment-rgp-snapshot path (ensure-rgp-bound-environment session))))

(defun execute-integration-rgp-artifacts-command (session)
  (environment-rgp-artifact-summaries (ensure-rgp-bound-environment session)))

(defun execute-integration-rgp-approvals-command (session)
  (environment-rgp-approval-summaries (ensure-rgp-bound-environment session)))

(defun execute-integration-rgp-approve-command (arguments session)
  (let ((work-item-id (first arguments))
        (policy (second arguments))
        (reason (getf (cddr arguments) :reason)))
    (unless (stringp work-item-id)
      (error "INTEGRATION/RGP-APPROVE requires a string work-item id"))
    (unless (keywordp policy)
      (error "INTEGRATION/RGP-APPROVE requires a keyword policy"))
    (ensure-rgp-bound-environment session)
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (request-work-item-approval session work-item policy :reason reason)
      (list :binding (rgp-binding-summary)
            :approval (work-item-wait-report session work-item)
            :work-item (enriched-work-item-detail session work-item)))))

(defun execute-integration-rgp-resume-command (arguments session)
  (let ((work-item-id (first arguments))
        (note (getf (rest arguments) :note)))
    (unless (stringp work-item-id)
      (error "INTEGRATION/RGP-RESUME requires a string work-item id"))
    (ensure-rgp-bound-environment session)
    (let ((work-item (find-work-item session work-item-id)))
      (unless work-item
        (error "Unknown work-item ~A" work-item-id))
      (resume-work-item session work-item :note note)
      (list :binding (rgp-binding-summary)
            :approval (work-item-wait-report session work-item)
            :work-item (enriched-work-item-detail session work-item)))))

(defun execute-runtime-current-package-command (session)
  (getf (service-response-data (query-runtime-summary-service session)) :package-details))

(defun execute-runtime-list-loaded-systems-command (session)
  (let ((summary (service-response-data (query-runtime-summary-service session))))
    (list :tool :runtime/list-loaded-systems
          :system-count (getf summary :loaded-system-count)
          :systems (getf summary :loaded-systems)
          :sandbox-profile :in-process)))

(defun execute-runtime-describe-symbol-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/DESCRIBE-SYMBOL requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/DESCRIBE-SYMBOL keyword options must be a property list"))
    (apply #'tool-runtime-describe-symbol session :symbol symbol-name options)))

(defun execute-runtime-find-definition-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/FIND-DEFINITION requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/FIND-DEFINITION keyword options must be a property list"))
    (apply #'tool-runtime-find-definition session :symbol symbol-name options)))

(defun execute-runtime-callers-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/CALLERS requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/CALLERS keyword options must be a property list"))
    (apply #'tool-runtime-callers session :symbol symbol-name options)))

(defun execute-runtime-methods-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/METHODS requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/METHODS keyword options must be a property list"))
    (apply #'tool-runtime-methods session :symbol symbol-name options)))

(defun execute-runtime-source-image-divergence-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/SOURCE-IMAGE-DIVERGENCE requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/SOURCE-IMAGE-DIVERGENCE keyword options must be a property list"))
    (apply #'tool-runtime-source-image-divergence session :symbol symbol-name options)))

(defun execute-runtime-set-package-command (arguments session)
  (let ((package-name (first arguments)))
    (unless (stringp package-name)
      (error "RUNTIME/SET-PACKAGE requires a string package name"))
    (service-response-data
     (command-runtime-set-package-service session package-name))))

(defun execute-runtime-eval-command (arguments session)
  (let ((form-or-source (first arguments))
        (options (rest arguments)))
    (when (null arguments)
      (error "RUNTIME/EVAL requires a form or source string"))
    (when (oddp (length options))
      (error "RUNTIME/EVAL keyword options must be a property list"))
    (service-response-data
     (apply #'command-runtime-eval-service session form-or-source options))))

(defun execute-runtime-history-command (arguments session)
  (let ((options arguments))
    (when (oddp (length options))
      (error "RUNTIME/HISTORY keyword options must be a property list"))
    (service-response-data
     (apply #'query-runtime-history-service session options))))

(defun execute-runtime-reload-file-command (arguments session)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "RUNTIME/RELOAD-FILE requires a string path"))
    (service-response-data
     (command-runtime-reload-file-service session path))))

(defun execute-environment-show-command (&optional environment)
  (service-response-data
   (query-environment-summary-service environment)))

(defun execute-environment-events-command (arguments &optional environment)
  (service-response-data
   (query-environment-events-service :tail (getf arguments :tail)
                                     :environment environment)))

(defun execute-environment-save-command (arguments &optional environment)
  (let ((path (first arguments))
        (active-environment (ensure-environment environment)))
    (unless (stringp path)
      (error "ENVIRONMENT/SAVE requires a string path"))
    (save-environment active-environment path)
    (list :saved path
          :summary (environment-summary active-environment))))

(defun execute-environment-load-command (arguments)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "ENVIRONMENT/LOAD requires a string path"))
    (let ((environment (load-environment path)))
      (let ((session (environment-session environment)))
      (values (list :loaded path
                    :summary (environment-summary environment))
              session)))))

(defun resume-turn-command-target (session turn-id)
  (if turn-id
      (or (find-turn session turn-id)
          (error "Unknown turn ~A" turn-id))
      (or (most-recent-thread-turn session)
          (error "No turns recorded for the current thread"))))

(defun execute-turn-resume-command (arguments session &optional provider)
  (let* ((turn-id (first arguments))
         (turn (resume-turn-command-target session turn-id)))
    (resume-conversation-turn provider session turn
                              :source (or (getf (turn-metadata turn) :source) :say)
                              :operator-mode :conversation)))

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
  (service-response-data
   (query-work-item-detail-service session (work-item-id work-item))))

(defun execute-describe-work-item-command (arguments session)
  (let ((work-item-id (first arguments)))
    (unless (stringp work-item-id)
      (error "DESCRIBE-WORK-ITEM requires a string work-item id"))
    (service-response-data
     (query-work-item-detail-service session work-item-id))))

(defun execute-list-workflow-records-command (session)
  (service-response-data
   (query-workflow-record-list-service session)))

(defun execute-describe-workflow-record-command (arguments session)
  (let ((workflow-record-id (first arguments)))
    (unless (stringp workflow-record-id)
      (error "DESCRIBE-WORKFLOW-RECORD requires a string workflow record id"))
    (service-response-data
     (query-workflow-record-detail-service session workflow-record-id))))
(defun execute-request-work-item-approval-command (arguments session)
  (let ((work-item-id (first arguments))
        (policy (second arguments))
        (reason (getf (cddr arguments) :reason)))
    (unless (stringp work-item-id)
      (error "REQUEST-WORK-ITEM-APPROVAL requires a string work-item id"))
    (unless (keywordp policy)
      (error "REQUEST-WORK-ITEM-APPROVAL requires a keyword policy"))
    (service-response-data
     (command-request-work-item-approval-service session work-item-id policy :reason reason))))

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
      (:assistant-action
       (let ((result (execute-assistant-action-command (command-arguments command) active-session)))
         (append-transcript-entry active-session :assistant-action (command-form command))
         (append-transcript-entry active-session :system result)
         (values result :assistant-action active-session)))
      (:ask
       (execute-ask-command (command-arguments command) provider active-session))
      (:say
       (execute-say-command (command-arguments command) provider active-session))
      (:thread-new
       (values (execute-thread-new-command (command-arguments command) active-session)
               :thread-new
               active-session))
      (:thread-list
       (values (execute-thread-list-command active-session)
               :thread-list
               active-session))
      (:thread-use
       (values (execute-thread-use-command (command-arguments command) active-session)
               :thread-use
               active-session))
      (:thread-show
       (values (execute-thread-show-command (command-arguments command) active-session)
               :thread-show
               active-session))
      (:turn-status
       (values (execute-turn-status-command (command-arguments command) active-session)
               :turn-status
               active-session))
      (:turn-resume
       (values (execute-turn-resume-command (command-arguments command) active-session provider)
               :turn-resume
               active-session))
      (:incident-list
       (values (execute-incident-list-command active-session)
               :incident-list
               active-session))
      (:incident-show
       (values (execute-incident-show-command (command-arguments command) active-session)
               :incident-show
               active-session))
      (:environment-status
       (values (execute-environment-status-command)
               :environment-status
               active-session))
      (:review-mutation
       (values (execute-review-mutation-command (command-arguments command) active-session)
               :review-mutation
               active-session))
      (:integration-rgp-bind
       (values (execute-integration-rgp-bind-command (command-arguments command) active-session)
               :integration-rgp-bind
               active-session))
      (:integration-rgp-show
       (values (execute-integration-rgp-show-command active-session)
               :integration-rgp-show
               active-session))
      (:integration-rgp-export
       (values (execute-integration-rgp-export-command (command-arguments command) active-session)
               :integration-rgp-export
               active-session))
      (:integration-rgp-artifacts
       (values (execute-integration-rgp-artifacts-command active-session)
               :integration-rgp-artifacts
               active-session))
      (:integration-rgp-approvals
       (values (execute-integration-rgp-approvals-command active-session)
               :integration-rgp-approvals
               active-session))
      (:integration-rgp-approve
       (values (execute-integration-rgp-approve-command (command-arguments command) active-session)
               :integration-rgp-approve
               active-session))
      (:integration-rgp-resume
       (values (execute-integration-rgp-resume-command (command-arguments command) active-session)
               :integration-rgp-resume
               active-session))
      (:runtime-current-package
       (values (execute-runtime-current-package-command active-session)
               :runtime-current-package
               active-session))
      (:runtime-list-loaded-systems
       (values (execute-runtime-list-loaded-systems-command active-session)
               :runtime-list-loaded-systems
               active-session))
      (:runtime-describe-symbol
       (values (execute-runtime-describe-symbol-command (command-arguments command) active-session)
               :runtime-describe-symbol
               active-session))
      (:runtime-find-definition
       (values (execute-runtime-find-definition-command (command-arguments command) active-session)
               :runtime-find-definition
               active-session))
      (:runtime-callers
       (values (execute-runtime-callers-command (command-arguments command) active-session)
               :runtime-callers
               active-session))
      (:runtime-methods
       (values (execute-runtime-methods-command (command-arguments command) active-session)
               :runtime-methods
               active-session))
      (:runtime-source-image-divergence
       (values (execute-runtime-source-image-divergence-command (command-arguments command) active-session)
               :runtime-source-image-divergence
               active-session))
      (:runtime-set-package
       (values (execute-runtime-set-package-command (command-arguments command) active-session)
               :runtime-set-package
               active-session))
      (:runtime-eval
       (values (execute-runtime-eval-command (command-arguments command) active-session)
               :runtime-eval
               active-session))
      (:runtime-history
       (values (execute-runtime-history-command (command-arguments command) active-session)
               :runtime-history
               active-session))
      (:runtime-reload-file
       (values (execute-runtime-reload-file-command (command-arguments command) active-session)
               :runtime-reload-file
               active-session))
      (:environment-show
       (values (execute-environment-show-command)
               :environment-show
               active-session))
      (:environment-events
       (values (execute-environment-events-command (command-arguments command))
               :environment-events
               active-session))
      (:environment-save
       (values (execute-environment-save-command (command-arguments command))
               :environment-save
               active-session))
      (:environment-load
       (multiple-value-bind (result loaded-environment)
           (execute-environment-load-command (command-arguments command))
         (declare (ignore loaded-environment))
         (values result :environment-load *current-session*)))
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
       (values (service-response-data
                (query-work-item-list-service active-session))
               :list-work-items
               active-session))
      (:describe-work-item
       (values (execute-describe-work-item-command (command-arguments command) active-session)
               :describe-work-item
               active-session))
      (:list-workflow-records
       (values (execute-list-workflow-records-command active-session) :list-workflow-records active-session))
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
    (:assistant-action
     (format t "assistant-action-result> ~S~%" result))
    ((:ask :say)
     (if (getf result :enqueued-p)
         (format t "assistant-task> ~S~%" (getf result :queued-task))
         (let ((response (getf result :response))
               (staged-count (getf result :staged-action-count)))
           (unless (getf result :streamed-p)
             (format t "assistant> ~A~%" (assistant-response->string response)))
           (when (assistant-response-actions response)
             (format t "assistant-actions> ~S~%" (assistant-response-actions response))
             (format t "assistant-actions-staged> ~D~%" staged-count)))))
    (:turn-status
     (format t "turn> ~A status=~A messages=~D operations=~D artifacts=~D incidents=~D~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :status) :unknown)
             (length (or (getf result :messages) '()))
             (length (or (getf result :operations) '()))
             (length (or (getf result :artifacts) '()))
             (length (or (getf result :incidents) '())))
     (let ((summary (getf result :detail-summary)))
       (when summary
         (format t "turn-summary> runtime-ops=~D runtime-artifacts=~D incidents=~D work-item=~A work-status=~A workflow=~A~%"
                 (or (getf summary :runtime-operation-count) 0)
                 (or (getf summary :runtime-artifact-count) 0)
                 (or (getf summary :incident-count) 0)
                 (or (getf summary :work-item-id) :none)
                 (or (getf summary :work-item-status) :none)
                 (or (getf summary :workflow-record-status) :none))))
     (let ((assistant-message (getf result :assistant-message)))
       (when assistant-message
         (format t "assistant> ~A~%" (getf assistant-message :content))))
     (let ((approval (getf result :awaiting-approval)))
       (when (and approval (getf approval :awaiting-approval-p))
         (format t "approval> blocked=~D~%" (getf approval :blocked-operation-count))))
     (let ((recovery (getf result :recovery)))
       (when (or (getf recovery :resumable-p)
                 (getf recovery :interrupted-p))
         (format t "recovery> resumable=~D interrupted=~D work-item=~A~%"
                 (or (getf recovery :resumable-operation-count) 0)
                 (or (getf recovery :interrupted-operation-count) 0)
                 (or (getf recovery :work-item-id) :none))
         (when (getf recovery :work-item-resume-payload)
           (format t "recovery-payload> ~S~%" (getf recovery :work-item-resume-payload)))))
     (finish-output))
    (:turn-resume
     (format t "turn-resume> turn=~A resumed=~D results=~D~%"
             (or (getf result :turn-id) "<unknown>")
             (or (getf result :resumed-operation-count) 0)
             (or (getf result :action-result-count) 0))
     (let ((followup (getf result :followup)))
       (when followup
         (let ((response (getf followup :response)))
           (when response
             (format t "followup> ~A~%" (assistant-response->string response))))))
     (finish-output))
    (:thread-show
     (format t "thread> ~A title=~A messages=~D turns=~D artifacts=~D incidents=~D~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :title) "<untitled>")
             (length (or (getf result :messages) '()))
             (length (or (getf result :turns) '()))
             (length (or (getf result :artifacts) '()))
             (length (or (getf result :incidents) '())))
     (let ((summary (getf result :detail-summary)))
       (when summary
         (format t "thread-summary> runtime-artifacts=~D work-item-artifacts=~D incidents=~D~%"
                 (or (getf summary :runtime-artifact-count) 0)
                 (or (getf summary :work-item-artifact-count) 0)
                 (or (getf summary :incident-count) 0))))
     (finish-output))
    (:environment-status
     (format t "environment> ~A thread=~A runtime=~A blocked=~D open-incidents=~D~%"
             (or (getf (getf result :environment) :id) "<unknown>")
             (or (getf (getf result :active-thread) :id) :none)
             (or (getf (getf result :active-runtime) :runtime-id) :none)
             (or (getf (getf result :blocked-work) :count) 0)
             (or (getf (getf result :incidents) :open-count) 0))
     (format t "operator-posture> ~S~%" (getf result :operator-posture))
     (finish-output))
    (:incident-list
     (format t "incidents> count=~D~%" (length (or result '())))
     (dolist (incident result)
       (format t "incident> ~A kind=~A status=~A turn=~A operation=~A~%"
               (getf incident :id)
               (getf incident :kind)
               (getf incident :status)
               (or (getf incident :turn-id) :none)
               (or (getf incident :operation-id) :none)))
     (finish-output))
    (:incident-show
     (format t "incident> ~A kind=~A status=~A~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :kind) :unknown)
             (or (getf result :status) :unknown))
     (format t "incident-summary> ~A~%" (or (getf result :summary) ""))
     (when (getf result :condition)
       (format t "condition> ~A~%" (getf result :condition)))
     (when (getf result :turn)
       (format t "incident-turn> ~A status=~A~%"
               (getf (getf result :turn) :id)
               (getf (getf result :turn) :status)))
     (when (getf result :operation)
       (format t "incident-operation> ~A name=~A status=~A~%"
               (getf (getf result :operation) :id)
               (getf (getf result :operation) :name)
               (getf (getf result :operation) :status)))
     (when (getf result :work-item)
       (format t "incident-work-item> ~A status=~A closure=~A~%"
               (getf (getf result :work-item) :id)
               (getf (getf result :work-item) :status)
               (getf (getf result :work-item) :closure-decision)))
     (when (getf result :recovery)
       (format t "incident-recovery> resumable=~D interrupted=~D work-item=~A~%"
               (or (getf (getf result :recovery) :resumable-operation-count) 0)
               (or (getf (getf result :recovery) :interrupted-operation-count) 0)
               (or (getf (getf result :recovery) :work-item-id) :none)))
     (when (getf result :runtime-context)
       (format t "incident-runtime> package=~A checkpoints=~D observations=~D~%"
               (or (getf (getf result :runtime-context) :package) :none)
               (or (getf (getf result :runtime-context) :work-item-checkpoint-count) 0)
               (or (getf (getf result :runtime-context) :runtime-observation-count) 0)))
     (when (getf result :wait)
       (format t "incident-wait> why=~A next=~A~%"
               (or (getf result :why) (getf (getf result :wait) :why) :none)
               (or (getf (getf result :wait) :next-action) :none)))
     (when (getf result :recovery-plan)
       (format t "incident-plan> wait=~A actions=~D~%"
               (or (getf (getf result :recovery-plan) :wait-reason) :none)
               (length (or (getf (getf result :recovery-plan) :actions) '()))))
     (dolist (action (or (getf result :recommended-actions) '()))
       (format t "incident-next> ~S~%" action))
     (finish-output))
    (:review-mutation
     (format t "mutation-review> turn=~A status=~A operations=~D artifacts=~D incidents=~D~%"
             (or (getf (getf result :turn) :id) "<unknown>")
             (or (getf (getf result :turn) :status) :unknown)
             (or (getf (getf result :mutation) :operation-count) 0)
             (or (getf (getf result :mutation) :artifact-count) 0)
             (length (or (getf result :incidents) '())))
     (when (getf (getf result :governance) :work-item)
       (format t "mutation-governance> work-item=~A status=~A wait=~A~%"
               (getf (getf (getf result :governance) :work-item) :id)
               (getf (getf (getf result :governance) :work-item) :status)
               (or (getf (getf (getf result :governance) :wait) :why) :none)))
     (when (getf (getf result :governance) :next-action)
       (format t "mutation-next> ~S~%" (getf (getf result :governance) :next-action)))
     (finish-output))
    ((:runtime-find-definition :runtime-callers :runtime-methods :runtime-source-image-divergence)
     (format t "runtime-nav> tool=~A symbol=~A package=~A~%"
             (getf result :tool)
             (or (getf result :symbol) :none)
             (or (getf result :package) :none))
     (when (getf result :definition-count)
       (format t "runtime-definitions> ~D~%" (getf result :definition-count)))
     (when (getf result :caller-count)
       (format t "runtime-callers> ~D~%" (getf result :caller-count)))
     (when (getf result :method-count)
       (format t "runtime-methods> ~D~%" (getf result :method-count)))
     (when (getf result :divergence)
       (format t "runtime-divergence> ~A~%" (getf result :divergence)))
     (finish-output))
    ((:thread-new :thread-list :thread-use :enqueue-task :list-tasks :describe-task :cancel-task :monitor-task :run-next-task :start-worker :stop-worker :list-workers :describe-worker :list-work-items :describe-work-item :list-workflow-records :describe-workflow-record :request-work-item-approval :quarantine-work-item :resume-work-item :why-waiting :list-replay-groups :list-image-reconciliations :replay-validator-task :replay-validator-set :reconcile-image-only-source :integration-rgp-artifacts :integration-rgp-approvals :integration-rgp-approve :integration-rgp-resume)
     (format t "tasks> ~S~%" result))
    ((:integration-rgp-bind :integration-rgp-show :integration-rgp-export)
     (format t "rgp> ~S~%" result))
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
    (:environment-show
     (format t "environment> ~A runtime=~A threads=~D artifacts=~D incidents=~D events=~D~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :active-runtime-id) :none)
             (or (getf result :thread-count) 0)
             (or (getf result :artifact-count) 0)
             (or (getf result :incident-count) 0)
             (or (getf result :event-count) 0))
     (let* ((operator-evidence (or (getf result :operator-evidence)
                                   (and (getf result :summary)
                                        (getf (getf result :summary) :operator-evidence))))
            (operator-status (or (and operator-evidence (getf operator-evidence :posture))
                                 (getf result :operator-status))))
       (when operator-status
         (format t "environment-operator> blocked=~D quarantined=~D incidents=~D open=~D~%"
                 (or (getf operator-status :blocked-count) 0)
                 (or (getf operator-status :quarantined-count) 0)
                 (or (getf operator-status :incident-count) 0)
                 (or (getf operator-status :open-incident-count) 0))))
     (finish-output))
    (:environment-events
     (format t "environment-events> env=~A count=~D shown=~D~%"
             (or (getf result :environment-id) "<unknown>")
             (or (getf result :event-count) 0)
             (length (or (getf result :events) '())))
     (dolist (event (or (getf result :events) '()))
       (format t "environment-event> ~A family=~A entity=~A env=~A~%"
               (event-kind event)
               (event-family event)
               (or (event-entity-id event) :none)
               (or (getf (event-metadata event) :environment-id) :none)))
     (finish-output))
    (:environment-load
     (format t "environment-load> ~A env=~A session=~A~%"
             (or (getf result :loaded) "<unknown>")
             (or (getf (getf result :summary) :id) "<unknown>")
             (or (getf (getf result :summary) :session-id) :none))
     (let* ((operator-evidence (getf (getf result :summary) :operator-evidence))
            (operator-status (or (and operator-evidence (getf operator-evidence :posture))
                                 (getf (getf result :summary) :operator-status))))
       (when operator-status
         (format t "environment-load-operator> blocked=~D quarantined=~D incidents=~D open=~D~%"
                 (or (getf operator-status :blocked-count) 0)
                 (or (getf operator-status :quarantined-count) 0)
                 (or (getf operator-status :incident-count) 0)
                 (or (getf operator-status :open-incident-count) 0))))
     (finish-output))
    (:describe-session
     (format t "session> ~A package=~A threads=~D turns=~D work-items=~D incidents=~D~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :package) "<unknown>")
             (or (getf (getf result :thread-state) :thread-count) 0)
             (or (getf result :turn-count) 0)
             (or (getf result :work-item-count) 0)
             (or (getf result :incident-count) 0))
     (let* ((operator-evidence (getf result :operator-evidence))
            (operator-status (or (and operator-evidence (getf operator-evidence :posture))
                                 (getf result :operator-status)))
            (incident-summary (or (and operator-evidence (getf operator-evidence :incidents))
                                  (getf result :incident-summary))))
       (when operator-status
         (format t "session-operator> blocked=~D quarantined=~D incidents=~D open=~D durable=~D~%"
                 (or (getf operator-status :blocked-count) 0)
                 (or (getf operator-status :quarantined-count) 0)
                 (or (getf operator-status :incident-count) 0)
                 (or (getf operator-status :open-incident-count) 0)
                 (or (getf operator-status :durable-count) 0)))
       (when incident-summary
         (format t "session-incidents> total=~D open=~D recent=~D~%"
                 (or (getf incident-summary :count) 0)
                 (or (getf incident-summary :open-count) 0)
                 (length (or (getf incident-summary :recent) '())))))
     (finish-output))
    (t
     (format t "=> ~S~%" result))))

(defun start-shell (provider &optional session &key (default-stream-p nil))
  (let* ((active-session (ensure-session session))
         (active-environment (or (session-bound-environment active-session)
                                 (bind-session-to-environment active-session (ensure-environment)))))
    (format t "Starting Lisp-native shell with provider ~A.~%" (provider-name provider))
    (when default-stream-p
      (format t "Interactive streaming is enabled by default for ask requests.~%"))
    (print-shell-environment-orientation active-environment)
    (format t "Session: ~A~%" (agent-session-id active-session))
    (format t "Enter (help) for commands. Press Ctrl-D to exit.~%")
    (let ((*stream-event-listener* #'render-stream-event)
          (*default-ask-streaming* default-stream-p))
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
