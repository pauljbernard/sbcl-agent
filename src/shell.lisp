(in-package #:sbcl-agent)

(defparameter *shell-package* (find-package '#:sbcl-agent-user))

(defun print-shell-help ()
  (format t "Lisp shell commands:~%")
  (format t "  (ask \"prompt\")                   Send a prompt to the configured provider and stage proposed actions.~%")
  (format t "  (say \"prompt\")                   Conversation-style alias for ASK. Same execution path today.~%")
  (format t "  (ask \"prompt\" :stream t)         Stream assistant output while building the final response.~%")
  (format t "  (ask \"prompt\" :enqueue t)        Queue an agent request instead of executing it inline.~%")
  (format t "  (provider/show)                   Show the active provider profile for this environment.~%")
  (format t "  (provider/list)                   List configured provider profiles and the active selection.~%")
  (format t "  (provider/use \"profile\")         Switch the running shell to a configured provider profile through the environment control actor.~%")
  (format t "  (provider/configure \"profile\" :provider \"name\" :model \"name\" [:fast-model \"name\"] [:api-base \"url\"] [:intents '(:architecture-review :quick-turn)] [:latency-tier :fast|:balanced] [:review-bias :deep|:neutral] [:execution-bias :high|:balanced] [:locality :local|:network]) Save a provider profile through the environment control actor without storing secrets.~%")
  (format t "  (provider/routing [:mode])        Show or set provider routing mode (:auto or :manual).~%")
  (format t "  (provider/route)                  Show the most recent provider routing decision and ranked candidates.~%")
  (format t "  (platform/manifest [:capabilities '(:capability ...)]) Show the developer-platform capability manifest.~%")
  (format t "  (platform/package :output-path \"file.aop\" [:package-id \"id\"] [:package-version \"0.1.0\"] [:title \"name\"] [:publisher \"name\"] [:release-status \"deprecated\"] [:replacement-package-id \"id\"] [:rollback-strategy \"manual-recovery\"] [:failure-mode \"manual-intervention\"] [:backup-required nil] [:recovery-runbook \"uri\"] [:attested-p nil] [:capabilities '(:capability ...)] [:enqueue t]) Export a developer package descriptor, or enqueue governed actor execution.~%")
  (format t "  (platform/show-package \"file.aop\") Inspect an exported developer package descriptor.~%")
  (format t "  (platform/validate-package \"file.aop\") Validate an exported developer package descriptor.~%")
  (format t "  (platform/import-package \"file.aop\" [:allow-downgrade t] [:allow-deprecated t] [:allow-manual-recovery t] [:allow-untrusted t] [:enqueue t]) Validate and import a developer package into the bound environment registry, or enqueue governed actor execution.~%")
  (format t "  (platform/list-packages)          List imported developer packages from the bound environment registry.~%")
  (format t "  (platform/show-imported-package \"package-id\") Inspect one imported developer package from the bound environment registry.~%")
  (format t "  (platform/activate-package \"package-id\" [:enqueue t]) Activate one imported developer package in the bound environment registry, or enqueue governed actor execution.~%")
  (format t "  (platform/deactivate-package \"package-id\" [:enqueue t]) Deactivate one imported developer package in the bound environment registry, or enqueue governed actor execution.~%")
  (format t "  (platform/active-packages)        List active imported developer packages from the bound environment registry.~%")
  (format t "  (platform/profile)                Show the applied active-package platform profile for the bound environment registry.~%")
  (format t "  (platform/install-package \"file.aop\" [:allow-downgrade t] [:allow-deprecated t] [:allow-manual-recovery t] [:allow-untrusted t] [:enqueue t]) Validate, import, and activate one developer package in the bound environment registry, or enqueue governed actor execution.~%")
  (format t "  (platform/history [:package-id \"id\"] [:limit N]) Show package lifecycle history from the bound environment registry.~%")
  (format t "  (platform/audit)                  Show package trust, override, update, and lifecycle audit posture for the bound environment registry.~%")
  (format t "  (execution/show \"exec-id\")       Inspect a governed execution handle directly.~%")
  (format t "  (execution/control \"exec-id\" :action [:reason \"...\"] [:note \"...\"]) Intervene on a governed execution handle directly.~%")
  (format t "  (compatibility/list [:kind :host-process] [:backend :sbcl-sandbox-worker] [:sandbox-profile :process-run]) List hosted compatibility executions.~%")
  (format t "  (compatibility/show \"exec-id\")   Inspect one compatibility execution in detail.~%")
  (format t "  (compatibility/apps [:app-id \"linux.vscode\"]) List registered Linux compatibility app manifests.~%")
  (format t "  (compatibility/app-show \"linux.vscode\") Show one registered Linux compatibility app manifest.~%")
  (format t "  (compatibility/launch \"linux.vscode\" [:arguments '(...)] [:enqueue t]) Launch a registered Linux compatibility app, or enqueue governed actor execution.~%")
  (format t "  (compatibility/relaunch \"exec-id\") Relaunch a terminal or detached-loss Linux app through its manifest.~%")
  (format t "  (compatibility/windows [:app-id \"linux.vscode\"]) List visible Linux app display surfaces bridged into the shell model.~%")
  (format t "  (workspace/show)                   Show the shell workspace model built from execution surfaces.~%")
  (format t "  (desktop/show)                     Show the desktop-hostable shell model for the current workspace.~%")
  (format t "  (desktop-task/manifests)          List discoverable governed desktop task operations.~%")
  (format t "  (desktop-task/manifest :target :keyword :operation :keyword) Show one governed desktop task manifest.~%")
  (format t "  (desktop-task/records [:thread-id \"thread\"] [:status :keyword] [:approval-status :keyword]) List governed desktop task records.~%")
  (format t "  (desktop-task/actors)             List governed capability actors and mailbox summaries.~%")
  (format t "  (desktop-task/actor :actor-role :keyword) Show one governed capability actor summary.~%")
  (format t "  (desktop-task/actor-system-panel [:session-id \"session-id\"]) Show the live actor-system hierarchy, workflow edges, metrics, and supervision state.~%")
  (format t "  (desktop-task/supervision-incidents [:session-id \"session-id\"] [:actor-id \"actor/runtime\"] [:mailbox :runtime-inbox]) Show actor supervision incidents.~%")
  (format t "  (desktop-task/supervision-escalation-inbox [:session-id \"session-id\"] [:actor-id \"actor/runtime\"] [:parent-actor-id \"actor/governance\"] [:latest-only-p t]) Show routed parent/escalation-target supervision mailbox entries.~%")
  (format t "  (desktop-task/ack-supervision-escalation \"mailbox-entry-id\" [:session-id \"session-id\"] [:actor-message-id \"id\"]) Mark one supervision escalation mailbox entry resolved after parent/operator handling.~%")
  (format t "  (desktop-task/apply-supervision-escalation \"mailbox-entry-id\" [:session-id \"session-id\"] [:actor-message-id \"id\"] [:action :recommended|:dead-letter|:quarantine|:restart-child|:replace-child|:resume-from-checkpoint|:resume-work-item|:complete-validations|:rollback-work-item|:escalate-to-parent] [:note \"...\"]) Apply one routed supervision escalation through the linked actor-supervision incident.~%")
  (format t "  (desktop-task/process-supervision-escalation [:session-id \"session-id\"] [:actor-id \"actor/runtime\"] [:parent-actor-id \"actor/actor-system\"] [:action :recommended|:dead-letter|:quarantine|:restart-child|:replace-child|:resume-from-checkpoint|:resume-work-item|:complete-validations|:rollback-work-item|:escalate-to-parent] [:note \"...\"]) Let the supervisor consume and process the next queued escalation entry for a parent target.~%")
  (format t "  (desktop-task/fail-mailbox-entry :mailbox :keyword :mailbox-entry-id \"entry-id\" [:summary \"...\"] [:condition-string \"...\"] [:supervision-action :keyword]) Mark one actor mailbox entry failed and record a supervision incident.~%")
  (format t "  (desktop-task/apply-supervision-action \"incident-id\" [:action :recommended|:dead-letter|:quarantine|:restart-child|:replace-child|:resume-from-checkpoint|:resume-work-item|:complete-validations|:rollback-work-item] [:note \"...\"]) Apply one parent-directed or workflow-derived supervision action to a failed mailbox entry.~%")
  (format t "  (desktop-task/inbox :actor-role :keyword [:status :keyword]) Show one capability actor inbox from governed task records.~%")
  (format t "  (desktop-task/outbox :actor-role :keyword [:status :keyword]) Show one actor outbox from governed task records.~%")
  (format t "  (desktop-task/message \"actor-message-id\") Show one actor message via its governed task record.~%")
  (format t "  (desktop-task/editor-mailbox [:session-id \"session-id\"] [:pending-action-id \"id\"] [:status :keyword] [:approval-status :keyword] [:scope-id \"scope\"] [:latest-only-p t]) Show the editor actor mailbox keyed by editor pending-action ids.~%")
  (format t "  (desktop-task/editor-pending-mutations [:session-id \"session-id\"] [:pending-action-id \"id\"] [:status :keyword] [:approval-status :keyword] [:scope-id \"scope\"] [:latest-only-p t]) Show the editor actor pending mutation mailbox before and after governance approval.~%")
  (format t "  (desktop-task/context-chat-mailbox [:session-id \"session-id\"] [:status :keyword] [:approval-status :keyword] [:latest-only-p t]) Show the Context Chat actor mailbox keyed by session id.~%")
  (format t "  (desktop-task/context-chat-context) Show the explicit project targeting state for the Context Chat actor.~%")
  (format t "  (desktop-task/set-context-chat-projects :project-ids '(\"project-a\" \"project-b\") [:primary-project-id \"project-a\"]) Set or clear explicit project targeting for the Context Chat actor. Use an empty list to clear targeting.~%")
  (format t "  (desktop-task/context-chat-approval-inbox [:session-id \"session-id\"] [:latest-only-p t]) Show governance-issued approval requests addressed to the Context Chat actor.~%")
  (format t "  (desktop-task/ack-context-chat-approval \"approval-id\" [:session-id \"session-id\"] [:actor-message-id \"id\"] [:mailbox-entry-id \"entry-id\"]) Acknowledge one Context Chat approval-inbox message by approval id.~%")
  (format t "  (desktop-task/editor-authorizations [:session-id \"session-id\"] [:pending-action-id \"id\"] [:scope-id \"scope\"] [:latest-only-p t]) Show governance-authorized pending editor mutations keyed by pending action id.~%")
  (format t "  (desktop-task/consume-editor-authorization \"pending-action-id\" [:session-id \"session-id\"] [:scope-id \"scope\"] [:mailbox-entry-id \"entry-id\"]) Dequeue one editor authorization mailbox message by pending action id.~%")
  (format t "  (desktop-task/apply-editor-authorization \"pending-action-id\" [:session-id \"session-id\"] [:scope-id \"scope\"]) Apply one governance-authorized pending editor mutation by pending action id.~%")
  (format t "  (desktop-task/actor-trace [:actor-message-id \"id\"] [:actor-role :keyword] [:phase :keyword] [:latest-only-p t] [:dead-letters-only-p t]) Show actor transport trace events.~%")
  (format t "  (desktop-task/dlq [:actor-role :keyword]) Show dead-lettered actor messages from the DLQ trace.~%")
  (format t "  (desktop-task/replies :actor-role :keyword) Show completed/failed actor replies for one sender actor.~%")
  (format t "  (desktop-task/latest-reply :actor-role :keyword) Show the latest completed/failed actor reply for one sender actor.~%")
  (format t "  (desktop-task/approve-message \"actor-message-id\") Approve and resume one awaiting-approval actor message.~%")
  (format t "  (desktop-task/approve-approval \"approval-id\" [:session-id \"session-id\"]) Approve and resume one awaiting governance approval by approval id.~%")
  (format t "  (desktop-task/pending-approval)   Show the latest awaiting-approval actor-message context.~%")
  (format t "  (desktop-task/governance-state [:session-id \"session-id\"] [:approval-id \"approval-id\"] [:actor-message-id \"id\"] [:latest-only-p t]) Show explicit governance actor state keyed by session/approval/message id.~%")
  (format t "  (desktop-task/governance-inbox [:session-id \"session-id\"] [:approval-status :keyword] [:latest-only-p t]) Show the governance actor inbox keyed by session/approval state.~%")
  (format t "  (desktop-task/governance-decisions [:session-id \"session-id\"] [:approval-id \"approval-id\"] [:pending-action-id \"id\"] [:latest-only-p t]) Show governance-issued decision messages retained in the governance outbox.~%")
  (format t "  (desktop-task/runtime-outbox [:session-id \"session-id\"] [:latest-only-p t]) Show runtime-issued reply messages retained in the runtime outbox.~%")
  (format t "  (desktop-task/runtime-state [:session-id \"session-id\"] [:package-name \"package\"] [:symbol-name \"symbol\"]) Show runtime actor-owned definition continuity state.~%")
  (format t "  (desktop-task/actor-flow [:session-id \"session-id\"] [:approval-id \"approval-id\"] [:pending-action-id \"id\"] [:actor-message-id \"id\"] [:scope-id \"scope\"] [:latest-only-p t]) Show one combined actor-state packet spanning chat, governance, and editor mailboxes.~%")
  (format t "  (desktop-task/show \"task-id\")    Show one governed desktop task record.~%")
  (format t "  (desktop-task/mcp-servers)        List persisted MCP server configurations attached to the governed desktop task registry.~%")
  (format t "  (desktop-task/mcp-server \"server-id\") Show one MCP server configuration with its registered operations.~%")
  (format t "  (desktop-task/configure-mcp-server [:server-id \"id\"] :name \"name\" [:transport :stdio|:http] [:command \"cmd\"] [:arguments '(...) ] [:environment-variables '((\"KEY\" . \"VALUE\"))] [:working-directory \"/path\"] [:endpoint \"url\"] [:capabilities '(:capability ...)] [:retry-policy '(:retryable-p t :max-attempts 3 :backoff-seconds 5)] [:health-status :unknown|:healthy|:degraded] [:enabled-p t] [:discoverable-p t]) Create or update one MCP server configuration.~%")
  (format t "  (desktop-task/remove-mcp-server \"server-id\") Remove one persisted MCP server configuration.~%")
  (format t "  (desktop/panel :workspace|:display|:governance|:object-browser|:inspector) Persist the active desktop panel for the hosted shell model.~%")
  (format t "  (desktop/select :panel ... [:index N] [:kind :object-kind] [:execution-id \"exec-id\"] [:app-id \"linux.echo\"]) Select one desktop-panel item through the hosted shell model.~%")
  (format t "  (desktop/restore [:panel-id ...] [:panel-state '(... )]) Restore one hosted desktop panel from persisted shell model state.~%")
  (format t "  (desktop/action [:action-id \"...\"] | :action-kind ... :panel-id ...) Dispatch one structured desktop action directly from the hosted shell model.~%")
  (format t "  (surface/list)                     Show execution surfaces in the current workspace and current surface focus.~%")
  (format t "  (surface/select [:index N] [:execution-id \"exec-id\"]) Move shell focus to one workspace surface.~%")
  (format t "  (surface/step :next|:previous)     Move shell focus across workspace surfaces relative to the current focus.~%")
  (format t "  (display/list)                     Show Linux app display surfaces in the current workspace and current display focus.~%")
  (format t "  (display/show [\"exec-id\"] [:app-id \"linux.echo\"]) Show one display-bearing Linux app surface, or the current display focus.~%")
  (format t "  (display/select [:index N] [:execution-id \"exec-id\"] [:app-id \"linux.echo\"]) Move shell focus to one display-bearing Linux app surface.~%")
  (format t "  (display/step :next|:previous)     Move shell focus across display-bearing Linux app surfaces relative to the current focus.~%")
  (format t "  (display/control :action [:execution-id \"exec-id\"] [:app-id \"linux.echo\"] [:reason \"...\"] [:note \"...\"]) Control one display-bearing Linux app surface from the display lane.~%")
  (format t "  (open [:execution-id \"exec-id\"] [:surface-index N] [:display-index N] [:display-app-id \"linux.echo\"] [:governance-index N] [:object-kind :kind :object-index N]) Open one shell object and inspect it through the unified focus path.~%")
  (format t "  (focus/show)                       Show the current shell focus and its inspected object.~%")
  (format t "  (focus/set \"exec-id\")            Set the current shell focus explicitly to one execution handle.~%")
  (format t "  (governance/queue)                 Show the shell governance queue derived from blocked work, approvals, and incidents.~%")
  (format t "  (governance/select [:index N])     Move shell focus to one governance queue item.~%")
  (format t "  (object-browser [:kind])           Show grouped inspectable objects for the current shell workspace.~%")
  (format t "  (object-browser/select :kind [:index N]) Move shell focus to one grouped object-browser entry.~%")
  (format t "  (inspector/show [\"exec-id\"])      Inspect the current shell focus execution, or one explicit execution id.~%")
  (format t "  (thread/new [:title \"name\"])      Create and select a conversation thread.~%")
  (format t "  (thread/list)                      List conversation threads in the current session.~%")
  (format t "  (thread/use \"thread-id\")          Select the active conversation thread.~%")
  (format t "  (thread/show [\"thread-id\"])       Show one thread with persisted messages and turns.~%")
  (format t "  (turn/status [\"turn-id\"])         Show one turn, or the latest turn on the active thread.~%")
  (format t "  (turn/resume [\"turn-id\"])         Resume an approval-gated turn using current pending actions.~%")
  (format t "  (incident/list)                    List recorded incidents for the current session.~%")
  (format t "  (incident/show \"incident-id\")     Show one incident with linked turn, operation, and workflow context.~%")
  (format t "  (incident/condition \"incident-id\") Show structured condition detail for one incident.~%")
  (format t "  (incident/restarts \"incident-id\")  Show restart options captured for one incident.~%")
  (format t "  (environment/status)               Show where you are, what is blocked, and what needs attention next.~%")
  (format t "  (review/mutation [\"turn-id\"])     Show mutation, evidence, incidents, and closure state in one view.~%")
  (format t "  (integration/rgp-bind :request-id \"req\" :agent-session-id \"sess\") Bind this environment to an RGP governed runtime session through the RGP service layer.~%")
  (format t "  (integration/rgp-show)              Show the governed-runtime snapshot RGP will reconcile.~%")
  (format t "  (integration/rgp-workspace)         Show the desktop-facing RGP workspace summary surface.~%")
  (format t "  (integration/rgp-export \"path\")   Export the governed-runtime snapshot as JSON for RGP ingest through the RGP service layer.~%")
  (format t "  (integration/rgp-artifacts)         Show artifact summaries with lineage fields for RGP import.~%")
  (format t "  (integration/rgp-approvals)         Show blocked approvals and resumable work-items for governed runtime control.~%")
  (format t "  (integration/rgp-approve \"work-id\" :policy [:reason \"...\"]) Mark a governed runtime checkpoint as awaiting approval through the RGP service layer.~%")
  (format t "  (integration/rgp-resume \"work-id\" [:note \"...\"]) Resume a governed runtime work-item through the RGP service layer after operator action.~%")
  (format t "  (runtime/current-package)           Show the active Lisp package for the current runtime session.~%")
  (format t "  (runtime/list-loaded-systems)       Show ASDF systems currently loaded in the image.~%")
  (format t "  (runtime/describe-symbol \"name\" [:package \"PKG\"]) Inspect one symbol in the live image.~%")
  (format t "  (runtime/inspect \"name\" [:package \"PKG\"]) Inspect one symbol's live value and callable shape.~%")
  (format t "  (runtime/object \"name\" [:package \"PKG\"]) Inspect richer live object detail for one bound symbol.~%")
  (format t "  (runtime/condition \"incident-id\") Show runtime condition detail captured for one incident.~%")
  (format t "  (runtime/restarts \"incident-id\")  Show runtime restart options captured for one incident.~%")
  (format t "  (runtime/find-definition \"name\" [:package \"PKG\"]) Find workspace definitions for a symbol and relate them to the image.~%")
  (format t "  (runtime/callers \"name\" [:package \"PKG\"]) Find source-level callers for a symbol in the workspace.~%")
  (format t "  (runtime/methods \"name\" [:package \"PKG\"]) List generic-function methods for a symbol in the image.~%")
  (format t "  (runtime/source-image-divergence \"name\" [:package \"PKG\"]) Report source/image presence and pending drift for a symbol.~%")
  (format t "  (runtime/set-package \"PKG\" [:enqueue t]) Change the active Lisp package after approval, or enqueue governed actor execution.~%")
  (format t "  (runtime/eval form|string [:mutating t] [:enqueue t]) Evaluate in the active runtime package, or enqueue governed actor execution.~%")
  (format t "  (runtime/history [:tail N])         Show recent structured runtime operations recorded in the environment.~%")
  (format t "  (runtime/reload-file \"path\" [:enqueue t]) Load a workspace source file into the live image, or enqueue governed actor execution.~%")
  (format t "  (environment/show)                  Print a summary of the current environment state.~%")
  (format t "  (environment/events [:tail N])      Show recent projected environment events.~%")
  (format t "  (environment/save \"path\")        Persist the current environment and compatibility session through the environment control actor.~%")
  (format t "  (environment/load \"path\")        Load a persisted environment into the current image through the environment control actor.~%")
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
  (format t "  (describe-work-item-plan \"work-id\") Show the current long-horizon plan and steering state for one work-item.~%")
  (format t "  (list-workflow-records)           Show workflow records for the current session.~%")
  (format t "  (describe-workflow-record \"wf-id\") Show one workflow record with its durable log entries.~%")
  (format t "  (list-plans)                      Show durable plan summaries for the current session.~%")
  (format t "  (list-orchestrations)             Show compact orchestration posture for all durable plans.~%")
  (format t "  (list-orchestration-inbox)        Show actionable plans waiting on approval, review, or resume.~%")
  (format t "  (describe-plan [\"plan-id\"])      Show one plan detail record, defaulting to the active plan.~%")
  (format t "  (describe-active-plan)            Show the active plan detail record.~%")
  (format t "  (describe-plan-workflow [\"plan-id\"]) Show the workflow record linked to a plan.~%")
  (format t "  (describe-orchestration-focus [:plan-id \"...\"] [:workflow-record-id \"...\"] [:work-item-id \"...\"]) Resolve orchestration from plan, workflow, or work-item context.~%")
  (format t "  (describe-orchestration-snapshot [\"plan-id\"]) Show joined plan/workflow orchestration state.~%")
  (format t "  (describe-plan-verification [\"plan-id\"]) Show verification and reconciliation state for a plan.~%")
  (format t "  (request-work-item-approval \"work-id\" :policy [:reason \"...\"]) Mark a work-item as waiting for approval.~%")
  (format t "  (quarantine-work-item \"work-id\" \"reason\") Quarantine a work-item for operator review.~%")
  (format t "  (resume-work-item \"work-id\" [:note \"...\"]) Resume a quarantined or waiting work-item.~%")
  (format t "  (steer-work-item-plan \"work-id\" :phase :keyword :next-step :keyword [:note \"...\"]) Override plan steering for one work-item.~%")
  (format t "  (describe-worker \"worker-id\")     Show one worker summary.~%")
  (format t "  (approve :process-run)             Grant a capability policy to the current session.~%")
  (format t "  (tool :fs/read :path \"file\")     Read a workspace file.~%")
  (format t "  (tool :fs/list :path \"dir\")      List a workspace directory.~%")
  (format t "  (tool :proc/run :argv '(...))       Run a local process after approval.~%")
  (format t "  (patch '((:write \"file\" \"...\")) [:enqueue t]) Apply a governed patch, or enqueue mailbox-first workspace mutation after workspace-write approval.~%")
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
    (service-response-data
     (command-invoke-tool-service session tool-id tool-args))))

(defun execute-approve-command (arguments session)
  (let ((policy (first arguments)))
    (unless (keywordp policy)
      (error "APPROVE requires a keyword policy"))
    (service-response-data
     (command-approve-policy-service session policy))))

(defun execute-patch-command (arguments session)
  (let ((operations (first arguments))
        (options (rest arguments)))
    (when (null arguments)
      (error "PATCH requires a patch operation list"))
    (when (oddp (length options))
      (error "PATCH keyword options must be a property list"))
    (if (getf options :enqueue)
        (service-response-data
         (command-desktop-task-apply-patch-service
          session
          operations
          :metadata (list :source :shell-patch
                          :enqueue-p t)
          :register-record-p t
          :async-p t))
        (service-response-data
         (command-desktop-task-apply-patch-service
          session
          operations
          :metadata (list :source :shell-patch
                          :enqueue-p nil)
          :register-record-p t
          :async-p nil)))))

(defun execute-assistant-action-command (arguments session)
  (let ((action (first arguments)))
    (unless (typep action 'assistant-action)
      (error "ASSISTANT-ACTION command requires an assistant-action object"))
    (service-response-data
     (command-execute-assistant-action-service session action))))

(defun execute-pending-actions-command (session)
  (service-response-data
   (command-execute-pending-actions-service session)))

(defun execute-pending-actions-command-with-context (session &key thread turn operation)
  (service-response-data
   (command-execute-pending-actions-service session
                                            :thread thread
                                            :turn turn
                                            :operation operation)))

(defun execute-session-save-command (arguments session)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "SESSION/SAVE requires a string path"))
    (service-response-data
     (command-session-save-service session path))))

(defun execute-session-load-command (arguments session)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "SESSION/LOAD requires a string path"))
    (let* ((response (command-session-load-service path))
           (payload (service-response-data response))
           (session (getf payload :session))
           (workspace (and session
                           (service-response-data
                            (query-shell-workspace-service session)))))
      (values (list :loaded path
                    :summary (getf payload :summary)
                    :workspace workspace)
              session))))

(defun execute-workspace-show-command (session)
  (let ((result (service-response-data
                 (query-shell-workspace-service session))))
    (maybe-set-shell-focus-object-id session
                                     (getf result :inspector-focus-object-id))
    result))

(defun execute-desktop-show-command (session)
  (let ((result (service-response-data
                 (query-shell-desktop-model-service session))))
    (maybe-set-shell-focus-object-id session
                                     (getf result :focus-object-id))
    result))

(defun execute-desktop-task-manifests-command (session)
  (service-response-data
   (command-desktop-task-manifest-list-query-service session)))

(defun execute-desktop-task-manifest-command (arguments session)
  (let ((target (or (getf arguments :target)
                    (first arguments)))
        (operation (or (getf arguments :operation)
                       (second arguments))))
    (unless (keywordp target)
      (error "DESKTOP-TASK/MANIFEST requires a keyword :target"))
    (unless (keywordp operation)
      (error "DESKTOP-TASK/MANIFEST requires a keyword :operation"))
    (service-response-data
     (query-desktop-task-manifest-detail-service session target operation))))

(defun execute-desktop-task-records-command (arguments session)
  (service-response-data
   (command-desktop-task-record-list-query-service
    session
    :thread-id (getf arguments :thread-id)
    :status (getf arguments :status)
    :approval-status (getf arguments :approval-status))))

(defun execute-desktop-task-actors-command (session)
  (service-response-data
   (query-desktop-task-actor-list-service session)))

(defun execute-desktop-task-actor-command (arguments session)
  (let ((actor-role (or (getf arguments :actor-role)
                        (getf arguments :role)
                        (first arguments))))
    (unless (keywordp actor-role)
      (error "DESKTOP-TASK/ACTOR requires a keyword :actor-role"))
    (service-response-data
     (query-desktop-task-actor-detail-service session actor-role))))

(defun execute-desktop-task-inbox-command (arguments session)
  (let ((actor-role (or (getf arguments :actor-role)
                        (getf arguments :role)
                        (first arguments))))
    (unless (keywordp actor-role)
      (error "DESKTOP-TASK/INBOX requires a keyword :actor-role"))
    (service-response-data
     (query-desktop-task-actor-inbox-service session actor-role
                                             :status (getf arguments :status)))))

(defun execute-desktop-task-outbox-command (arguments session)
  (let ((actor-role (or (getf arguments :actor-role)
                        (getf arguments :role)
                        (first arguments))))
    (unless (keywordp actor-role)
      (error "DESKTOP-TASK/OUTBOX requires a keyword :actor-role"))
    (service-response-data
     (query-desktop-task-actor-outbox-service session actor-role
                                              :status (getf arguments :status)))))

(defun execute-desktop-task-message-command (arguments session)
  (let ((actor-message-id (or (first arguments)
                              (getf arguments :actor-message-id)
                              (getf arguments :message-id))))
    (unless (stringp actor-message-id)
      (error "DESKTOP-TASK/MESSAGE requires a string actor message id"))
    (service-response-data
     (query-desktop-task-actor-message-detail-service session actor-message-id))))

(defun execute-desktop-task-editor-mailbox-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (pending-action-id (or (getf arguments :pending-action-id)
                               (getf arguments :mutation-id)))
        (status (getf arguments :status))
        (approval-status (getf arguments :approval-status))
        (scope-id (or (getf arguments :scope-id)
                      (getf arguments :receiver-scope)))
        (latest-only-p (not (null (or (getf arguments :latest-only-p)
                                      (getf arguments :latest-only))))))
    (service-response-data
     (query-desktop-task-editor-mailbox-service
      session
      :session-id session-id
      :pending-action-id pending-action-id
      :status status
      :approval-status approval-status
      :scope-id scope-id
      :latest-only-p latest-only-p))))

(defun execute-desktop-task-context-chat-mailbox-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (status (getf arguments :status))
        (approval-status (getf arguments :approval-status))
        (latest-only-p (not (null (or (getf arguments :latest-only-p)
                                      (getf arguments :latest-only))))))
    (service-response-data
     (query-desktop-task-context-chat-mailbox-service
      session
      :session-id session-id
      :status status
      :approval-status approval-status
      :latest-only-p latest-only-p))))

(defun execute-desktop-task-context-chat-context-command (session)
  (service-response-data
   (query-desktop-task-context-chat-context-service session)))

(defun execute-desktop-task-set-context-chat-projects-command (arguments session)
  (let* ((raw-project-ids (or (getf arguments :project-ids)
                              (and (listp (first arguments))
                                   (first arguments))
                              '()))
         (project-ids (if (and (consp raw-project-ids)
                               (eq (first raw-project-ids) 'quote)
                               (consp (rest raw-project-ids)))
                          (second raw-project-ids)
                          raw-project-ids))
        (primary-project-id (getf arguments :primary-project-id)))
    (service-response-data
     (command-desktop-task-set-context-chat-projects-service
      session
      project-ids
      :primary-project-id primary-project-id))))

(defun execute-desktop-task-editor-pending-mutations-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (pending-action-id (or (getf arguments :pending-action-id)
                               (getf arguments :mutation-id)))
        (status (getf arguments :status))
        (approval-status (getf arguments :approval-status))
        (scope-id (or (getf arguments :scope-id)
                      (getf arguments :receiver-scope)))
        (latest-only-p (not (null (or (getf arguments :latest-only-p)
                                      (getf arguments :latest-only))))))
    (service-response-data
     (query-desktop-task-editor-mailbox-service
      session
      :session-id session-id
      :pending-action-id pending-action-id
      :status status
      :approval-status approval-status
      :scope-id scope-id
      :latest-only-p latest-only-p))))

(defun execute-desktop-task-context-chat-approval-inbox-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (latest-only-p (not (null (or (getf arguments :latest-only-p)
                                      (getf arguments :latest-only))))))
    (service-response-data
     (query-desktop-task-context-chat-approval-inbox-service
      session
      :session-id session-id
      :latest-only-p latest-only-p))))

(defun execute-desktop-task-ack-context-chat-approval-command (arguments session)
  (let ((approval-id (or (first arguments)
                         (getf arguments :approval-id)))
        (session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (actor-message-id (or (getf arguments :actor-message-id)
                              (getf arguments :message-id)))
        (mailbox-entry-id (or (getf arguments :mailbox-entry-id)
                              (getf arguments :entry-id))))
    (unless (stringp approval-id)
      (error "DESKTOP-TASK/ACK-CONTEXT-CHAT-APPROVAL requires a string approval id"))
    (service-response-data
     (command-desktop-task-ack-context-chat-approval-service
      session
      approval-id
      :session-id session-id
      :actor-message-id actor-message-id
      :mailbox-entry-id mailbox-entry-id))))

(defun execute-desktop-task-editor-authorizations-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (pending-action-id (or (getf arguments :pending-action-id)
                               (getf arguments :mutation-id)))
        (scope-id (or (getf arguments :scope-id)
                      (getf arguments :receiver-scope)))
        (latest-only-p (not (null (or (getf arguments :latest-only-p)
                                      (getf arguments :latest-only))))))
    (service-response-data
     (query-desktop-task-editor-authorization-mailbox-service
      session
      :session-id session-id
      :pending-action-id pending-action-id
      :scope-id scope-id
      :latest-only-p latest-only-p))))

(defun execute-desktop-task-consume-editor-authorization-command (arguments session)
  (let ((pending-action-id (or (first arguments)
                               (getf arguments :pending-action-id)
                               (getf arguments :mutation-id)))
        (session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (scope-id (or (getf arguments :scope-id)
                      (getf arguments :receiver-scope)))
        (mailbox-entry-id (or (getf arguments :mailbox-entry-id)
                              (getf arguments :entry-id))))
    (unless (stringp pending-action-id)
      (error "DESKTOP-TASK/CONSUME-EDITOR-AUTHORIZATION requires a pending-action-id"))
    (service-response-data
     (command-desktop-task-consume-editor-authorization-service
      session
      pending-action-id
      :session-id session-id
      :scope-id scope-id
      :mailbox-entry-id mailbox-entry-id))))

(defun execute-desktop-task-apply-editor-authorization-command (arguments session)
  (let ((pending-action-id (or (first arguments)
                               (getf arguments :pending-action-id)
                               (getf arguments :mutation-id)))
        (session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (scope-id (or (getf arguments :scope-id)
                      (getf arguments :receiver-scope))))
    (unless pending-action-id
      (error "desktop-task/apply-editor-authorization requires a pending-action-id"))
    (service-response-data
     (command-desktop-task-apply-editor-authorization-service
      session
      pending-action-id
      :session-id session-id
      :scope-id scope-id))))

(defun execute-desktop-task-actor-trace-command (arguments session)
  (let ((actor-message-id (or (getf arguments :actor-message-id)
                              (getf arguments :message-id)))
        (actor-role (or (getf arguments :actor-role)
                        (getf arguments :role)))
        (phase (getf arguments :phase)))
    (service-response-data
     (command-desktop-task-actor-trace-service
      session
      :actor-message-id actor-message-id
      :actor-role actor-role
      :phase phase
      :latest-only-p (getf arguments :latest-only-p)
      :dead-letters-only-p (getf arguments :dead-letters-only-p)))))

(defun execute-desktop-task-dlq-command (arguments session)
  (service-response-data
   (command-desktop-task-dead-letter-queue-service
    session
    :actor-role (or (getf arguments :actor-role)
                    (getf arguments :role)))))

(defun execute-desktop-task-replies-command (arguments session &key latest-only-p)
  (let ((actor-role (or (getf arguments :actor-role)
                        (getf arguments :role)
                        (first arguments))))
    (unless (keywordp actor-role)
      (error (if latest-only-p
                 "DESKTOP-TASK/LATEST-REPLY requires a keyword :actor-role"
                 "DESKTOP-TASK/REPLIES requires a keyword :actor-role")))
    (service-response-data
     (query-desktop-task-actor-replies-service session actor-role
                                               :latest-only-p latest-only-p))))

(defun execute-desktop-task-approve-message-command (arguments session provider)
  (let ((actor-message-id (or (first arguments)
                              (getf arguments :actor-message-id)
                              (getf arguments :message-id))))
    (unless (stringp actor-message-id)
      (error "DESKTOP-TASK/APPROVE-MESSAGE requires a string actor message id"))
    (unless provider
      (error "DESKTOP-TASK/APPROVE-MESSAGE requires a provider"))
    (service-response-data
     (command-desktop-task-approve-actor-message-service
      session provider actor-message-id))))

(defun execute-desktop-task-approve-approval-command (arguments session provider)
  (let ((approval-id (or (first arguments)
                         (getf arguments :approval-id)))
        (session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id))))
    (unless (stringp approval-id)
      (error "DESKTOP-TASK/APPROVE-APPROVAL requires a string approval id"))
    (service-response-data
     (command-desktop-task-approve-approval-service
      session provider approval-id :session-id session-id))))

(defun execute-desktop-task-pending-approval-command (session)
  (service-response-data
   (command-desktop-task-pending-approval-query-service session)))

(defun execute-desktop-task-governance-state-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (approval-id (getf arguments :approval-id))
        (actor-message-id (or (getf arguments :actor-message-id)
                              (getf arguments :message-id)))
        (latest-only-p (not (null (or (getf arguments :latest-only-p)
                                      (getf arguments :latest-only))))))
    (service-response-data
     (query-desktop-task-governance-state-service
      session
      :session-id session-id
      :approval-id approval-id
      :actor-message-id actor-message-id
      :latest-only-p latest-only-p))))

(defun execute-desktop-task-governance-inbox-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (approval-status (getf arguments :approval-status))
        (latest-only-p (not (null (or (getf arguments :latest-only-p)
                                      (getf arguments :latest-only))))))
    (service-response-data
     (query-desktop-task-governance-inbox-service
      session
      :session-id session-id
      :approval-status approval-status
      :latest-only-p latest-only-p))))

(defun execute-desktop-task-governance-decisions-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (approval-id (getf arguments :approval-id))
        (pending-action-id (or (getf arguments :pending-action-id)
                               (getf arguments :mutation-id)))
        (latest-only-p (not (null (or (getf arguments :latest-only-p)
                                      (getf arguments :latest-only))))))
    (service-response-data
     (query-desktop-task-governance-decision-outbox-service
      session
      :session-id session-id
      :approval-id approval-id
      :pending-action-id pending-action-id
      :latest-only-p latest-only-p))))

(defun execute-desktop-task-runtime-outbox-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (latest-only-p (not (null (or (getf arguments :latest-only-p)
                                      (getf arguments :latest-only))))))
    (service-response-data
     (query-desktop-task-runtime-outbox-service
      session
      :session-id session-id
      :latest-only-p latest-only-p))))

(defun execute-desktop-task-runtime-state-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (package-name (or (getf arguments :package-name)
                          (getf arguments :package)))
        (symbol-name (or (getf arguments :symbol-name)
                         (getf arguments :symbol))))
    (service-response-data
     (command-desktop-task-runtime-state-service
      session
      :session-id session-id
      :package-name package-name
      :symbol-name symbol-name))))

(defun execute-desktop-task-actor-flow-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id)))
        (approval-id (getf arguments :approval-id))
        (pending-action-id (or (getf arguments :pending-action-id)
                               (getf arguments :mutation-id)))
        (actor-message-id (or (getf arguments :actor-message-id)
                              (getf arguments :message-id)))
        (scope-id (or (getf arguments :scope-id)
                      (getf arguments :receiver-scope)))
        (latest-only-p (not (null (or (getf arguments :latest-only-p)
                                      (getf arguments :latest-only))))))
    (service-response-data
     (command-desktop-task-actor-flow-query-service
      session
      :session-id session-id
      :approval-id approval-id
      :pending-action-id pending-action-id
      :actor-message-id actor-message-id
      :scope-id scope-id
      :latest-only-p latest-only-p))))

(defun execute-desktop-task-actor-system-panel-command (arguments session)
  (let ((session-id (or (getf arguments :session-id)
                        (getf arguments :chat-session-id))))
    (service-response-data
     (command-desktop-task-actor-system-panel-service session
                                                      :session-id session-id))))

(defun execute-desktop-task-supervision-incidents-command (arguments session)
  (service-response-data
   (command-desktop-task-supervision-incidents-service
    session
    :actor-id (getf arguments :actor-id)
    :parent-actor-id (getf arguments :parent-actor-id)
    :mailbox (getf arguments :mailbox)
    :mailbox-entry-id (getf arguments :mailbox-entry-id)
    :session-id (or (getf arguments :session-id)
                    (getf arguments :chat-session-id))
    :latest-only-p (getf arguments :latest-only-p))))

(defun execute-desktop-task-supervision-escalation-inbox-command (arguments session)
  (service-response-data
   (command-desktop-task-supervision-escalation-inbox-service
    session
    :actor-id (getf arguments :actor-id)
    :parent-actor-id (getf arguments :parent-actor-id)
    :mailbox-entry-id (or (getf arguments :mailbox-entry-id)
                          (getf arguments :entry-id))
    :session-id (or (getf arguments :session-id)
                    (getf arguments :chat-session-id))
    :latest-only-p (getf arguments :latest-only-p))))

(defun execute-desktop-task-ack-supervision-escalation-command (arguments session)
  (let ((mailbox-entry-id (or (first arguments)
                              (getf arguments :mailbox-entry-id)
                              (getf arguments :entry-id))))
    (unless (stringp mailbox-entry-id)
      (error "DESKTOP-TASK/ACK-SUPERVISION-ESCALATION requires a string mailbox-entry-id"))
    (service-response-data
     (command-desktop-task-ack-supervision-escalation-admin-service
      session
      mailbox-entry-id
      :session-id (or (getf arguments :session-id)
                      (getf arguments :chat-session-id))
      :actor-message-id (or (getf arguments :actor-message-id)
                            (getf arguments :message-id))))))

(defun execute-desktop-task-apply-supervision-escalation-command (arguments session)
  (let ((mailbox-entry-id (or (first arguments)
                              (getf arguments :mailbox-entry-id)
                              (getf arguments :entry-id))))
    (unless (stringp mailbox-entry-id)
      (error "DESKTOP-TASK/APPLY-SUPERVISION-ESCALATION requires a string mailbox-entry-id"))
    (service-response-data
     (command-desktop-task-apply-supervision-escalation-admin-service
      session
      mailbox-entry-id
      :session-id (or (getf arguments :session-id)
                      (getf arguments :chat-session-id))
      :actor-message-id (or (getf arguments :actor-message-id)
                            (getf arguments :message-id))
      :action (or (getf arguments :action)
                  :recommended)
      :note (getf arguments :note)))))

(defun execute-desktop-task-process-supervision-escalation-command (arguments session)
  (service-response-data
   (command-desktop-task-process-supervision-escalation-admin-service
    session
    :session-id (or (getf arguments :session-id)
                    (getf arguments :chat-session-id))
    :actor-id (getf arguments :actor-id)
    :parent-actor-id (getf arguments :parent-actor-id)
    :action (or (getf arguments :action)
                :recommended)
    :note (getf arguments :note))))

(defun execute-desktop-task-fail-mailbox-entry-command (arguments session)
  (let ((mailbox (or (getf arguments :mailbox)
                     (first arguments)))
        (mailbox-entry-id (or (getf arguments :mailbox-entry-id)
                              (second arguments))))
    (unless mailbox
      (error "DESKTOP-TASK/FAIL-MAILBOX-ENTRY requires :mailbox"))
    (unless (stringp mailbox-entry-id)
      (error "DESKTOP-TASK/FAIL-MAILBOX-ENTRY requires a string :mailbox-entry-id"))
    (service-response-data
     (command-desktop-task-fail-mailbox-entry-service
      session
      mailbox
      mailbox-entry-id
      :actor-message-id (getf arguments :actor-message-id)
      :approval-id (getf arguments :approval-id)
      :pending-action-id (getf arguments :pending-action-id)
      :summary (getf arguments :summary)
      :condition-string (getf arguments :condition-string)
      :supervision-action (getf arguments :supervision-action)))))

(defun execute-desktop-task-apply-supervision-action-command (arguments session)
  (let ((incident-id (or (first arguments)
                         (getf arguments :incident-id))))
    (unless (stringp incident-id)
      (error "DESKTOP-TASK/APPLY-SUPERVISION-ACTION requires a string incident id"))
    (service-response-data
     (command-desktop-task-apply-supervision-action-service
      session
      incident-id
      :action (or (getf arguments :action) :dead-letter)
      :note (getf arguments :note)))))

(defun execute-desktop-task-show-command (arguments session)
  (let ((record-id (or (first arguments)
                       (getf arguments :record-id))))
    (unless (stringp record-id)
      (error "DESKTOP-TASK/SHOW requires a string record id"))
    (service-response-data
     (query-desktop-task-record-detail-service session record-id))))

(defun execute-desktop-task-mcp-servers-command (session)
  (service-response-data
   (command-desktop-task-mcp-server-list-query-service session)))

(defun execute-desktop-task-mcp-server-command (arguments session)
  (let ((server-id (or (first arguments)
                       (getf arguments :server-id))))
    (unless (stringp server-id)
      (error "DESKTOP-TASK/MCP-SERVER requires a string server id"))
    (service-response-data
     (command-desktop-task-mcp-server-detail-query-service session server-id))))

(defun execute-desktop-task-configure-mcp-server-command (arguments session)
  (let ((name (getf arguments :name)))
    (unless (and (stringp name) (> (length (string-trim " " name)) 0))
      (error "DESKTOP-TASK/CONFIGURE-MCP-SERVER requires :name"))
    (service-response-data
     (command-desktop-task-configure-mcp-server-service
      session
      :server-id (getf arguments :server-id)
      :name name
      :transport (getf arguments :transport)
      :command (getf arguments :command)
      :arguments (getf arguments :arguments)
      :environment-variables (getf arguments :environment-variables)
      :working-directory (getf arguments :working-directory)
      :endpoint (getf arguments :endpoint)
      :capabilities (getf arguments :capabilities)
      :retry-policy (getf arguments :retry-policy)
      :health-status (getf arguments :health-status)
      :enabled-p (getf arguments :enabled-p)
      :discoverable-p (getf arguments :discoverable-p)
      :metadata (getf arguments :metadata)))))

(defun execute-desktop-task-remove-mcp-server-command (arguments session)
  (let ((server-id (or (first arguments)
                       (getf arguments :server-id))))
    (unless (stringp server-id)
      (error "DESKTOP-TASK/REMOVE-MCP-SERVER requires a string server id"))
    (service-response-data
     (command-desktop-task-remove-mcp-server-service session server-id))))

(defun execute-desktop-panel-command (arguments session)
  (let ((panel-id (or (first arguments)
                      (getf arguments :panel))))
    (unless (keywordp panel-id)
      (error "DESKTOP/PANEL requires a keyword panel id"))
    (service-response-data
     (command-shell-desktop-panel-service session panel-id))))

(defun execute-desktop-select-command (arguments session)
  (let ((panel-id (getf arguments :panel))
        (index (getf arguments :index))
        (execution-id (getf arguments :execution-id))
        (app-id (getf arguments :app-id))
        (object-kind (getf arguments :kind)))
    (unless (keywordp panel-id)
      (error "DESKTOP/SELECT requires :panel"))
    (when (and index (not (and (integerp index) (<= 0 index))))
      (error "DESKTOP/SELECT :index must be a non-negative integer"))
    (when (and execution-id (not (stringp execution-id)))
      (error "DESKTOP/SELECT :execution-id must be a string"))
    (when (and app-id (not (stringp app-id)))
      (error "DESKTOP/SELECT :app-id must be a string"))
    (when (and object-kind (not (keywordp object-kind)))
      (error "DESKTOP/SELECT :kind must be a keyword"))
    (service-response-data
     (command-shell-desktop-select-service session
                                           panel-id
                                           :index index
                                           :execution-id execution-id
                                           :app-id app-id
                                           :object-kind object-kind))))

(defun execute-desktop-restore-command (arguments session)
  (let* ((panel-id (getf arguments :panel-id))
         (raw-panel-state (getf arguments :panel-state))
         (panel-state (if (and (consp raw-panel-state)
                               (eq (first raw-panel-state) 'quote)
                               (= (length raw-panel-state) 2))
                          (second raw-panel-state)
                          raw-panel-state)))
    (when (and panel-id (not (keywordp panel-id)))
      (error "DESKTOP/RESTORE :panel-id must be a keyword"))
    (when (and panel-state (not (listp panel-state)))
      (error "DESKTOP/RESTORE :panel-state must be a property list"))
    (service-response-data
     (command-shell-desktop-restore-service session
                                            :panel-id panel-id
                                            :panel-state panel-state))))

(defun execute-desktop-action-command (arguments session)
  (service-response-data
   (command-shell-desktop-action-service session arguments)))

(defun execute-surface-list-command (session)
  (service-response-data
   (query-shell-surface-list-service session)))

(defun execute-surface-select-command (arguments session)
  (let ((index (getf arguments :index))
        (execution-id (getf arguments :execution-id)))
    (when (and index (not (and (integerp index) (<= 0 index))))
      (error "SURFACE/SELECT :index must be a non-negative integer"))
    (when (and execution-id (not (stringp execution-id)))
      (error "SURFACE/SELECT :execution-id must be a string"))
    (when (and (null index) (null execution-id))
      (error "SURFACE/SELECT requires :index or :execution-id"))
    (service-response-data
     (command-shell-surface-select-service session
                                           :index index
                                           :execution-id execution-id
                                           :source :surface-select))))

(defun execute-surface-step-command (arguments session)
  (let ((direction (or (first arguments)
                       (getf arguments :direction))))
    (unless (member direction '(:next :previous) :test #'eq)
      (error "SURFACE/STEP requires direction :next or :previous"))
    (service-response-data
     (command-shell-surface-step-service session direction))))

(defun execute-display-list-command (session)
  (service-response-data
   (query-shell-display-list-service session)))

(defun execute-display-show-command (arguments session)
  (let ((execution-id (if (and (consp arguments)
                               (keywordp (first arguments)))
                          (getf arguments :execution-id)
                          (first arguments)))
        (app-id (and (consp arguments)
                     (keywordp (first arguments))
                     (getf arguments :app-id))))
    (when (and execution-id (not (stringp execution-id)))
      (error "DISPLAY/SHOW requires a string execution id when provided"))
    (when (and app-id (not (stringp app-id)))
      (error "DISPLAY/SHOW :app-id must be a string"))
    (service-response-data
     (query-shell-display-detail-service session execution-id :app-id app-id))))

(defun execute-display-select-command (arguments session)
  (let ((index (getf arguments :index))
        (execution-id (getf arguments :execution-id))
        (app-id (getf arguments :app-id)))
    (when (and index (not (and (integerp index) (<= 0 index))))
      (error "DISPLAY/SELECT :index must be a non-negative integer"))
    (when (and execution-id (not (stringp execution-id)))
      (error "DISPLAY/SELECT :execution-id must be a string"))
    (when (and app-id (not (stringp app-id)))
      (error "DISPLAY/SELECT :app-id must be a string"))
    (when (and (null index) (null execution-id) (null app-id))
      (error "DISPLAY/SELECT requires :index, :execution-id, or :app-id"))
    (service-response-data
     (command-shell-display-select-service session
                                           :index index
                                           :execution-id execution-id
                                           :app-id app-id
                                           :source :display-select))))

(defun execute-display-step-command (arguments session)
  (let ((direction (or (first arguments)
                       (getf arguments :direction))))
    (unless (member direction '(:next :previous) :test #'eq)
      (error "DISPLAY/STEP requires direction :next or :previous"))
    (service-response-data
     (command-shell-display-step-service session direction))))

(defun execute-display-control-command (arguments session)
  (let ((action (getf arguments :action))
        (execution-id (getf arguments :execution-id))
        (app-id (getf arguments :app-id))
        (reason (getf arguments :reason))
        (note (getf arguments :note))
        (status (getf arguments :status)))
    (unless (keywordp action)
      (error "DISPLAY/CONTROL requires :action as a keyword"))
    (when (and execution-id (not (stringp execution-id)))
      (error "DISPLAY/CONTROL :execution-id must be a string"))
    (when (and app-id (not (stringp app-id)))
      (error "DISPLAY/CONTROL :app-id must be a string"))
    (service-response-data
     (command-shell-display-control-service session
                                            action
                                            :execution-id execution-id
                                            :app-id app-id
                                            :reason reason
                                            :note note
                                            :status status))))

(defun execute-open-command (arguments session)
  (let ((execution-id (getf arguments :execution-id))
        (surface-index (getf arguments :surface-index))
        (display-index (getf arguments :display-index))
        (display-app-id (getf arguments :display-app-id))
        (governance-index (getf arguments :governance-index))
        (object-kind (getf arguments :object-kind))
        (object-index (getf arguments :object-index)))
    (when (and execution-id (not (stringp execution-id)))
      (error "OPEN :execution-id must be a string"))
    (when (and surface-index (not (and (integerp surface-index) (<= 0 surface-index))))
      (error "OPEN :surface-index must be a non-negative integer"))
    (when (and display-index (not (and (integerp display-index) (<= 0 display-index))))
      (error "OPEN :display-index must be a non-negative integer"))
    (when (and display-app-id (not (stringp display-app-id)))
      (error "OPEN :display-app-id must be a string"))
    (when (and governance-index (not (and (integerp governance-index) (<= 0 governance-index))))
      (error "OPEN :governance-index must be a non-negative integer"))
    (when (and object-kind (not (keywordp object-kind)))
      (error "OPEN :object-kind must be a keyword"))
    (when (and object-index (not (and (integerp object-index) (<= 0 object-index))))
      (error "OPEN :object-index must be a non-negative integer"))
    (service-response-data
     (command-shell-open-service session
                                 :execution-id execution-id
                                 :surface-index surface-index
                                 :display-index display-index
                                 :display-app-id display-app-id
                                 :governance-index governance-index
                                 :object-kind object-kind
                                 :object-index object-index
                                 :source :open))))

(defun execute-focus-show-command (session)
  (service-response-data
   (query-shell-inspector-service session)))

(defun execute-focus-set-command (arguments session)
  (let ((object-id (first arguments)))
    (unless (stringp object-id)
      (error "FOCUS/SET requires a string execution id"))
    (service-response-data
     (command-shell-focus-set-service session object-id :source :focus-set))))

(defun execute-governance-queue-command (session)
  (let ((result (service-response-data
                 (query-shell-governance-queue-service session))))
    (maybe-set-shell-focus-object-id session
                                     (getf (getf result :top-item) :execution-id))
    result))

(defun execute-governance-select-command (arguments session)
  (let ((index (or (getf arguments :index) 0)))
    (unless (and (integerp index) (<= 0 index))
      (error "GOVERNANCE/SELECT :index must be a non-negative integer"))
    (service-response-data
     (command-shell-governance-select-service session :index index))))

(defun execute-object-browser-command (arguments session)
  (let ((kind (first arguments)))
    (when (and kind (not (keywordp kind)))
      (error "OBJECT-BROWSER optional :kind filter must be a keyword"))
    (let ((result (service-response-data
                   (query-shell-object-browser-service session :object-kind kind))))
      (maybe-set-shell-focus-object-id session
                                       (getf result :focus-object-id))
      result)))

(defun execute-object-browser-select-command (arguments session)
  (let ((object-kind (or (getf arguments :kind)
                         (first arguments)))
        (index (or (getf arguments :index) 0)))
    (unless (keywordp object-kind)
      (error "OBJECT-BROWSER/SELECT requires a keyword :kind"))
    (unless (and (integerp index) (<= 0 index))
      (error "OBJECT-BROWSER/SELECT :index must be a non-negative integer"))
    (service-response-data
     (command-shell-object-select-service session object-kind :index index))))

(defun execute-inspector-show-command (arguments session)
  (let ((object-id (first arguments)))
    (when (and object-id (not (stringp object-id)))
      (error "INSPECTOR/SHOW optional focus object must be a string execution id"))
    (let ((result (service-response-data
                   (query-shell-inspector-service session object-id))))
      (maybe-set-shell-focus-object-id session
                                       (getf result :focus-object-id))
      result)))

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

(defun print-shell-workspace-startup-summary (session &optional environment)
  (let* ((workspace (service-response-data
                     (query-shell-workspace-service session :environment environment)))
         (top-surface (getf workspace :top-surface))
         (top-queue-item (getf (getf workspace :governance-queue) :top-item)))
    (format t "Workspace: surfaces=~D governance=~D groups=~D focus=~A~%"
            (or (getf (getf workspace :execution-surfaces) :count) 0)
            (or (getf (getf workspace :governance-queue) :count) 0)
            (or (getf (getf workspace :object-browser) :group-count) 0)
            (or (getf workspace :inspector-focus-object-id) :none))
    (when (getf (getf workspace :display-surfaces) :top-surface)
      (format t "Workspace display: app=~A state=~A exec=~A~%"
              (or (getf (getf (getf workspace :display-surfaces) :top-surface) :app-id) :none)
              (or (getf (getf (getf workspace :display-surfaces) :top-surface) :window-state) :unknown)
              (or (getf (getf (getf workspace :display-surfaces) :top-surface) :execution-id) :none)))
    (when top-surface
      (format t "Workspace top surface: ~A status=~A exec=~A~%"
              (or (getf top-surface :surface-kind) :none)
              (or (getf top-surface :status) :unknown)
              (or (getf top-surface :execution-id) :none)))
    (when top-surface
      (format t "Workspace open: (open :surface-index 0)~%"))
    (when (getf (getf workspace :display-surfaces) :top-surface)
      (format t "Workspace display open: (open :execution-id ~S)~%"
              (getf (getf (getf workspace :display-surfaces) :top-surface) :execution-id)))
    (when top-queue-item
      (format t "Workspace governance top: queue=~A status=~A exec=~A~%"
              (or (getf top-queue-item :queue-kind) :none)
              (or (getf top-queue-item :status) :unknown)
              (or (getf top-queue-item :execution-id) :none)))
    (when top-queue-item
      (format t "Workspace governance open: (open :governance-index 0)~%"))
    (finish-output)
    workspace))

(defun render-shell-open-handoff (label command)
  (when command
    (format t "~A> ~A~%" label command)))

(defun shell-open-command-for-surface (surface)
  (let ((execution-id (and surface
                           (getf surface :execution-id))))
    (when execution-id
      (format nil "(open :execution-id ~S)" execution-id))))

(defun shell-open-command-for-surface-index (index)
  (when (and (integerp index) (<= 0 index))
    (format nil "(open :surface-index ~D)" index)))

(defun shell-open-command-for-governance-index (index)
  (when (and (integerp index) (<= 0 index))
    (format nil "(open :governance-index ~D)" index)))

(defun shell-open-command-for-object-browser-group (group)
  (let ((object-kind (and group (getf group :object-kind))))
    (when object-kind
      (format nil "(open :object-kind ~S :object-index 0)" object-kind))))

(defun provider-routing-enabled-p (provider)
  (member (string-downcase (provider-name provider))
          '("openai" "openai-compatible" "anthropic"
            "google" "gemini" "google-openai-compatible" "gemini-openai-compatible"
            "lm-studio" "lmstudio" "local-openai-compatible"
            "meta-compatible" "meta-openai-compatible")
          :test #'string=))

(defun execute-ask-command (arguments provider session)
  (multiple-value-bind (prompt options)
      (parse-ask-arguments arguments)
    (let* ((bound-environment (and (provider-routing-enabled-p provider)
                                   (session-bound-environment session)))
           (route (and bound-environment
                       (select-environment-provider-profile prompt
                                                            :environment bound-environment
                                                            :options options)))
           (selected-profile (and route (getf route :selected-profile)))
           (selected-provider (or (and selected-profile
                                       (provider-from-profile selected-profile))
                                  provider))
           (result (service-response-data
                    (command-conversation-execution-service
                     session
                     selected-provider
                     prompt
                     options
                     :source :ask
                     :operator-mode :repl-bridge)))
           (route-summary (if route
                              (record-environment-provider-route route bound-environment)
                              (list :routing-mode :provider-default
                                    :reason :unbound-session
                                    :selected-profile-name nil
                                    :selected-provider (provider-name provider)
                                    :selected-model nil))))
      (values (append result (list :provider-route route-summary))
              :ask
              session
              selected-provider))))

(defun execute-say-command (arguments provider session)
  (multiple-value-bind (prompt options)
      (parse-ask-arguments arguments)
    (let* ((bound-environment (and (provider-routing-enabled-p provider)
                                   (session-bound-environment session)))
           (route (and bound-environment
                       (select-environment-provider-profile prompt
                                                            :environment bound-environment
                                                            :options options)))
           (selected-profile (and route (getf route :selected-profile)))
           (selected-provider (or (and selected-profile
                                       (provider-from-profile selected-profile))
                                  provider))
           (result (service-response-data
                    (command-conversation-execution-service
                     session
                     selected-provider
                     prompt
                     options
                     :source :say
                     :operator-mode :conversation)))
           (route-summary (if route
                              (record-environment-provider-route route bound-environment)
                              (list :routing-mode :provider-default
                                    :reason :unbound-session
                                    :selected-profile-name nil
                                    :selected-provider (provider-name provider)
                                    :selected-model nil))))
      (values (append result (list :provider-route route-summary))
              :say
              session
              selected-provider))))

(defun execute-provider-show-command (&optional environment)
  (service-response-data
   (query-environment-provider-service environment)))

(defun execute-provider-list-command (&optional environment)
  (execute-provider-show-command environment))

(defun execute-provider-configure-command (arguments session &optional environment)
  (let ((profile-name (first arguments))
        (options (rest arguments)))
    (unless (stringp profile-name)
      (error "PROVIDER/CONFIGURE requires a string profile name"))
    (when (oddp (length options))
      (error "PROVIDER/CONFIGURE keyword options must be a property list"))
    (unless (stringp (getf options :provider))
      (error "PROVIDER/CONFIGURE requires a string :provider"))
    (unless (stringp (getf options :model))
      (error "PROVIDER/CONFIGURE requires a string :model"))
    (service-response-data
     (command-environment-provider-configure-service profile-name
                                                     options
                                                     (or environment
                                                         (service-active-environment :session session))))))

(defun execute-provider-use-command (arguments session &optional environment)
  (let ((profile-name (first arguments)))
    (unless (stringp profile-name)
      (error "PROVIDER/USE requires a string profile name"))
    (service-response-data
     (command-environment-provider-use-service profile-name
                                               (or environment
                                                   (service-active-environment :session session))))))

(defun execute-provider-routing-command (arguments session &optional environment)
  (let ((mode (first arguments)))
    (when (> (length arguments) 1)
      (error "PROVIDER/ROUTING accepts at most one mode argument"))
    (service-response-data
     (command-environment-provider-routing-service mode
                                                   (or environment
                                                       (service-active-environment :session session))))))

(defun execute-provider-route-command (&optional environment)
  (service-response-data
   (query-environment-provider-route-service environment)))

(defun execute-platform-manifest-command (arguments session)
  (service-response-data
   (query-platform-manifest-service :capability-ids (getf arguments :capabilities)
                                    :session session)))

(defun execute-platform-package-command (arguments session)
  (service-response-data
   (command-desktop-task-platform-command-service
    session
    :package
    (remove-plist-key arguments :enqueue)
    :capability :platform-package
    :async-p (getf arguments :enqueue))))

(defun execute-platform-show-package-command (arguments session)
  (let ((path (first arguments)))
    (unless (or (stringp path) (pathnamep path))
      (error "PLATFORM/SHOW-PACKAGE requires a string path"))
    (service-response-data
     (query-platform-package-service path :session session))))

(defun execute-platform-validate-package-command (arguments session)
  (let ((path (first arguments)))
    (unless (or (stringp path) (pathnamep path))
      (error "PLATFORM/VALIDATE-PACKAGE requires a string path"))
    (service-response-data
     (command-platform-validate-package-service path :session session))))

(defun execute-platform-import-package-command (arguments session)
  (let ((path (first arguments))
        (options (rest arguments)))
    (unless (or (stringp path) (pathnamep path))
      (error "PLATFORM/IMPORT-PACKAGE requires a string path"))
    (service-response-data
     (command-desktop-task-platform-command-service
     session
      :import-package
      (list :path path
            :allow-downgrade (getf options :allow-downgrade)
            :allow-deprecated (getf options :allow-deprecated)
            :allow-manual-recovery (getf options :allow-manual-recovery)
            :allow-untrusted (getf options :allow-untrusted))
      :capability :platform-import-package
      :async-p (getf options :enqueue)))))

(defun execute-platform-list-packages-command (session)
  (service-response-data
   (query-platform-package-registry-service :session session)))

(defun execute-platform-show-imported-package-command (arguments session)
  (let ((package-id (first arguments)))
    (unless (stringp package-id)
      (error "PLATFORM/SHOW-IMPORTED-PACKAGE requires a string package id"))
    (service-response-data
     (query-platform-imported-package-service package-id :session session))))

(defun execute-platform-activate-package-command (arguments session)
  (let ((package-id (first arguments))
        (options (rest arguments)))
    (unless (stringp package-id)
      (error "PLATFORM/ACTIVATE-PACKAGE requires a string package id"))
    (service-response-data
     (command-desktop-task-platform-command-service
      session
      :activate-package
      (list :package-id package-id)
      :capability :platform-activate-package
      :async-p (getf options :enqueue)))))

(defun execute-platform-deactivate-package-command (arguments session)
  (let ((package-id (first arguments))
        (options (rest arguments)))
    (unless (stringp package-id)
      (error "PLATFORM/DEACTIVATE-PACKAGE requires a string package id"))
    (service-response-data
     (command-desktop-task-platform-command-service
      session
      :deactivate-package
      (list :package-id package-id)
      :capability :platform-deactivate-package
      :async-p (getf options :enqueue)))))

(defun execute-platform-active-packages-command (session)
  (service-response-data
   (query-platform-active-packages-service :session session)))

(defun execute-platform-profile-command (session)
  (service-response-data
   (query-platform-profile-service :session session)))

(defun execute-platform-install-package-command (arguments session)
  (let ((path (first arguments))
        (options (rest arguments)))
    (unless (or (stringp path) (pathnamep path))
      (error "PLATFORM/INSTALL-PACKAGE requires a string path"))
    (service-response-data
     (command-desktop-task-platform-command-service
     session
      :install-package
      (list :path path
            :allow-downgrade (getf options :allow-downgrade)
            :allow-deprecated (getf options :allow-deprecated)
            :allow-manual-recovery (getf options :allow-manual-recovery)
            :allow-untrusted (getf options :allow-untrusted))
      :capability :platform-install-package
      :async-p (getf options :enqueue)))))

(defun execute-platform-simulate-package-command (arguments session)
  (let ((path (first arguments)))
    (unless (or (stringp path) (pathnamep path))
      (error "PLATFORM/SIMULATE-PACKAGE requires a string path"))
    (service-response-data
     (query-platform-simulate-package-service path :session session))))

(defun execute-platform-history-command (arguments session)
  (service-response-data
   (query-platform-package-history-service :session session
                                           :package-id (getf arguments :package-id)
                                           :limit (getf arguments :limit))))

(defun execute-platform-audit-command (session)
  (service-response-data
   (query-platform-audit-service :session session)))

(defun execute-platform-harness-command (session)
  (service-response-data
   (query-platform-harness-service :session session)))

(defun execute-platform-run-harness-command (arguments session)
  (let ((harness-id (or (getf arguments :harness-id)
                        (first arguments)
                        :internal-evaluations)))
    (unless (keywordp harness-id)
      (error "PLATFORM/RUN-HARNESS requires a keyword harness id"))
    (service-response-data
     (command-desktop-task-platform-command-service
     session
      :run-harness
      (list :harness-id harness-id)
      :capability :platform-run-harness
      :async-p (getf arguments :enqueue)))))

(defun execute-execution-show-command (arguments session)
  (let ((execution-id (first arguments)))
    (unless (stringp execution-id)
      (error "EXECUTION/SHOW requires a string execution id"))
    (service-response-data
     (query-execution-detail-service session execution-id))))

(defun execute-execution-control-command (arguments session provider)
  (let ((execution-id (first arguments))
        (action (getf (rest arguments) :action))
        (reason (getf (rest arguments) :reason))
        (note (getf (rest arguments) :note)))
    (unless (stringp execution-id)
      (error "EXECUTION/CONTROL requires a string execution id"))
    (unless (keywordp action)
      (error "EXECUTION/CONTROL requires a keyword :action"))
    (service-response-data
     (command-execution-control-service session
                                        execution-id
                                        action
                                        :reason reason
                                        :note note
                                        :provider provider))))

(defun execute-compatibility-list-command (arguments session)
  (service-response-data
   (query-compatibility-executions-service session
                                           :kind (getf arguments :kind)
                                           :app-id (getf arguments :app-id)
                                           :backend (getf arguments :backend)
                                           :sandbox-profile (getf arguments :sandbox-profile))))

(defun execute-compatibility-show-command (arguments session)
  (let ((execution-id (first arguments)))
    (unless (stringp execution-id)
      (error "COMPATIBILITY/SHOW requires a string execution id"))
    (service-response-data
     (query-compatibility-execution-detail-service session execution-id))))

(defun execute-compatibility-apps-command (arguments session)
  (service-response-data
   (query-compatibility-apps-service :app-id (getf arguments :app-id)
                                     :session session)))

(defun execute-compatibility-app-show-command (arguments session)
  (let ((app-id (first arguments)))
    (unless (stringp app-id)
      (error "COMPATIBILITY/APP-SHOW requires a string app id"))
    (service-response-data
     (query-compatibility-apps-service :app-id app-id
                                       :session session))))

(defun execute-compatibility-launch-command (arguments session)
  (let ((app-id (first arguments))
        (options (rest arguments)))
    (unless (stringp app-id)
      (error "COMPATIBILITY/LAUNCH requires a string app id"))
    (let* ((definition (or (find-compatibility-app app-id
                                                   :session session
                                                   :environment (session-bound-environment session))
                           (error "Unknown compatibility app ~S" app-id)))
           (policy-id (compatibility-app-definition-policy-id definition))
           (response (command-desktop-task-compatibility-launch-service
                      session
                      app-id
                      (unwrap-task-form (getf options :arguments))
                      :capability policy-id
                      :metadata (list :source :shell-compatibility-launch
                                      :enqueue-p (not (null (getf options :enqueue)))
                                      :app-id app-id)
                      :register-record-p t
                      :async-p (getf options :enqueue)))
           (result (service-response-data response))
           (execution-id (or (getf result :execution-id)
                             (getf (service-response-metadata response) :execution-id)))
           (execution (and execution-id
                           (find-execution-handle execution-id
                                                  (session-bound-environment session)))))
      (append result
              (list :execution-id execution-id
                    :execution (and execution
                                    (execution-handle-summary execution)))))))

(defun execute-compatibility-relaunch-command (arguments session)
  (let ((execution-id (first arguments)))
    (unless (stringp execution-id)
      (error "COMPATIBILITY/RELAUNCH requires a string execution id"))
    (service-response-data
     (command-execution-control-service session
                                        execution-id
                                        :relaunch))))

(defun execute-compatibility-windows-command (arguments session)
  (service-response-data
   (query-compatibility-display-surfaces-service session
                                                 :app-id (getf arguments :app-id)
                                                 :display-surface-kind (getf arguments :display-surface-kind))))

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

(defun execution-id-string-p (value)
  (and (stringp value)
       (>= (length value) 5)
       (string= "exec-" value :end1 5 :end2 5)))

(defun resolve-shell-execution-handle (session execution-or-id)
  (when (execution-id-string-p execution-or-id)
    (let* ((environment (ensure-execution-bound-environment session))
           (handle (find-execution-handle execution-or-id environment)))
      (unless handle
        (error "Unknown execution ~A" execution-or-id))
      handle)))

(defun resolve-shell-work-item-id (session work-item-or-execution-id command-name)
  (let ((handle (resolve-shell-execution-handle session work-item-or-execution-id)))
    (cond
      ((null handle) work-item-or-execution-id)
      ((execution-handle-target-value handle :work-item-id)
       (execution-handle-target-value handle :work-item-id))
      (t
       (error "~A execution ~A is not bound to a work-item"
              command-name
              work-item-or-execution-id)))))

(defun resolve-shell-work-item-execution-id (session work-item-or-execution-id)
  (let ((handle (resolve-shell-execution-handle session work-item-or-execution-id)))
    (cond
      (handle
       (getf handle :execution-id))
      ((stringp work-item-or-execution-id)
       (let* ((environment (ensure-execution-bound-environment session))
              (matching-handles (find-execution-handles-by-target :work-item-id
                                                                  work-item-or-execution-id
                                                                  environment))
              (first-handle (first matching-handles)))
         (and first-handle
              (getf first-handle :execution-id))))
      (t nil))))

(defun resolve-shell-workflow-record-id (session workflow-or-execution-id command-name)
  (let ((handle (resolve-shell-execution-handle session workflow-or-execution-id)))
    (cond
      ((null handle) workflow-or-execution-id)
      ((execution-handle-target-value handle :workflow-record-id)
       (execution-handle-target-value handle :workflow-record-id))
      ((execution-handle-target-value handle :work-item-id)
       (let* ((work-item-id (execution-handle-target-value handle :work-item-id))
              (work-item (find-work-item session work-item-id))
              (record (and work-item
                           (work-item-workflow-record session work-item))))
         (unless record
           (error "~A execution ~A does not resolve to a workflow record"
                  command-name
                  workflow-or-execution-id))
         (workflow-record-id record)))
      (t
       (error "~A execution ~A is not bound to a workflow record"
              command-name
              workflow-or-execution-id)))))

(defun resolve-shell-plan-id (session plan-or-execution-id command-name)
  (let ((handle (resolve-shell-execution-handle session plan-or-execution-id)))
    (cond
      ((null handle) plan-or-execution-id)
      ((execution-handle-target-value handle :plan-id)
       (execution-handle-target-value handle :plan-id))
      ((execution-handle-target-value handle :workflow-record-id)
       (let* ((workflow-record-id (execution-handle-target-value handle :workflow-record-id))
              (workflow-record (find-workflow-record session workflow-record-id))
              (plan-id (and workflow-record
                            (workflow-record-plan-id workflow-record))))
         (unless plan-id
           (error "~A execution ~A does not resolve to a plan"
                  command-name
                  plan-or-execution-id))
         plan-id))
      ((execution-handle-target-value handle :work-item-id)
       (let* ((work-item-id (execution-handle-target-value handle :work-item-id))
              (work-item (find-work-item session work-item-id))
              (workflow-record (and work-item
                                    (work-item-workflow-record session work-item)))
              (plan-id (and workflow-record
                            (workflow-record-plan-id workflow-record))))
         (unless plan-id
           (error "~A execution ~A does not resolve to a plan"
                  command-name
                  plan-or-execution-id))
         plan-id))
      (t
       (error "~A execution ~A is not bound to a plan"
              command-name
              plan-or-execution-id)))))

(defun resolve-shell-incident-id (session incident-or-execution-id command-name)
  (let ((handle (resolve-shell-execution-handle session incident-or-execution-id)))
    (cond
      ((null handle) incident-or-execution-id)
      ((execution-handle-target-value handle :incident-id)
       (execution-handle-target-value handle :incident-id))
      (t
       (error "~A execution ~A is not bound to an incident"
              command-name
              incident-or-execution-id)))))

(defun shell-execution-control-inspection (session response)
  (let* ((data (service-response-data response))
         (post-state (and (listp data) (getf data :post-state)))
         (target (and (listp post-state) (getf post-state :target)))
         (work-item-id (and (listp target) (getf target :work-item-id)))
         (inspection (and (listp post-state) (getf post-state :inspection))))
    (or (and work-item-id
             (service-response-data
              (query-work-item-detail-service session work-item-id)))
        inspection
        post-state
        data)))

(defun execute-incident-show-command (arguments session)
  (let ((incident-id (resolve-shell-incident-id session
                                                (first arguments)
                                                "INCIDENT/SHOW")))
    (unless (stringp incident-id)
      (error "INCIDENT/SHOW requires a string incident id"))
    (service-response-data
     (query-incident-detail-service session incident-id))))

(defun execute-incident-condition-command (arguments session)
  (let ((incident-id (resolve-shell-incident-id session
                                                (first arguments)
                                                "INCIDENT/CONDITION")))
    (unless (stringp incident-id)
      (error "INCIDENT/CONDITION requires a string incident id"))
    (service-response-data
     (query-incident-condition-service session incident-id))))

(defun execute-incident-restarts-command (arguments session)
  (let ((incident-id (resolve-shell-incident-id session
                                                (first arguments)
                                                "INCIDENT/RESTARTS")))
    (unless (stringp incident-id)
      (error "INCIDENT/RESTARTS requires a string incident id"))
    (service-response-data
     (query-incident-restarts-service session incident-id))))

(defun execute-environment-status-command (session &optional environment)
  (service-response-data
   (query-environment-status-service
    (service-active-environment :session session
                                :environment environment))))

(defun execute-review-mutation-command (arguments session)
  (let ((turn-id (first arguments)))
    (when (and turn-id (not (stringp turn-id)))
      (error "REVIEW/MUTATION requires a string turn id when provided"))
    (service-response-data
     (query-mutation-review-service session turn-id))))

(defun execute-integration-rgp-bind-command (arguments session)
  (when (oddp (length arguments))
    (error "INTEGRATION/RGP-BIND arguments must be a property list"))
  (service-response-data
   (apply #'command-rgp-bind-service session arguments)))

(defun execute-integration-rgp-show-command (session)
  (service-response-data
   (query-rgp-show-service session)))

(defun execute-integration-rgp-workspace-command (session)
  (service-response-data
   (query-rgp-workspace-service session)))

(defun execute-integration-rgp-export-command (arguments session)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "INTEGRATION/RGP-EXPORT requires a string path"))
    (service-response-data
     (command-rgp-export-service session path))))

(defun execute-integration-rgp-artifacts-command (session)
  (service-response-data
   (query-rgp-artifacts-service session)))

(defun execute-integration-rgp-approvals-command (session)
  (service-response-data
   (query-rgp-approvals-service session)))

(defun execute-integration-rgp-approve-command (arguments session)
  (let ((work-item-id (resolve-shell-work-item-id session
                                                  (first arguments)
                                                  "INTEGRATION/RGP-APPROVE"))
        (policy (second arguments))
        (reason (getf (cddr arguments) :reason)))
    (unless (stringp work-item-id)
      (error "INTEGRATION/RGP-APPROVE requires a string work-item id"))
    (unless (keywordp policy)
      (error "INTEGRATION/RGP-APPROVE requires a keyword policy"))
    (service-response-data
     (command-rgp-approve-service session
                                  work-item-id
                                  policy
                                  :reason reason))))

(defun execute-integration-rgp-resume-command (arguments session)
  (let ((work-item-id (resolve-shell-work-item-id session
                                                  (first arguments)
                                                  "INTEGRATION/RGP-RESUME"))
        (note (getf (rest arguments) :note)))
    (unless (stringp work-item-id)
      (error "INTEGRATION/RGP-RESUME requires a string work-item id"))
    (service-response-data
     (command-rgp-resume-service session
                                 work-item-id
                                 :note note))))

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
    (service-response-data
     (apply #'query-runtime-describe-symbol-service session symbol-name options))))

(defun execute-runtime-inspect-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/INSPECT requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/INSPECT keyword options must be a property list"))
    (service-response-data
     (apply #'query-runtime-inspect-service session symbol-name options))))

(defun execute-runtime-object-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/OBJECT requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/OBJECT keyword options must be a property list"))
    (service-response-data
     (apply #'query-runtime-object-service session symbol-name options))))

(defun execute-runtime-condition-command (arguments session)
  (let ((incident-id (resolve-shell-incident-id session
                                                (first arguments)
                                                "RUNTIME/CONDITION")))
    (unless (stringp incident-id)
      (error "RUNTIME/CONDITION requires a string incident id"))
    (service-response-data
     (query-runtime-condition-service session incident-id))))

(defun execute-runtime-restarts-command (arguments session)
  (let ((incident-id (resolve-shell-incident-id session
                                                (first arguments)
                                                "RUNTIME/RESTARTS")))
    (unless (stringp incident-id)
      (error "RUNTIME/RESTARTS requires a string incident id"))
    (service-response-data
     (query-runtime-restarts-service session incident-id))))

(defun execute-runtime-find-definition-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/FIND-DEFINITION requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/FIND-DEFINITION keyword options must be a property list"))
    (service-response-data
     (apply #'query-runtime-find-definition-service session symbol-name options))))

(defun execute-runtime-callers-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/CALLERS requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/CALLERS keyword options must be a property list"))
    (service-response-data
     (apply #'query-runtime-callers-service session symbol-name options))))

(defun execute-runtime-methods-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/METHODS requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/METHODS keyword options must be a property list"))
    (service-response-data
     (apply #'query-runtime-methods-service session symbol-name options))))

(defun execute-runtime-source-image-divergence-command (arguments session)
  (let ((symbol-name (first arguments))
        (options (rest arguments)))
    (unless (stringp symbol-name)
      (error "RUNTIME/SOURCE-IMAGE-DIVERGENCE requires a string symbol name"))
    (when (oddp (length options))
      (error "RUNTIME/SOURCE-IMAGE-DIVERGENCE keyword options must be a property list"))
    (service-response-data
     (apply #'query-runtime-source-image-divergence-service session symbol-name options))))

(defun execute-runtime-set-package-command (arguments session)
  (let ((package-name (first arguments))
        (options (rest arguments)))
    (unless (stringp package-name)
      (error "RUNTIME/SET-PACKAGE requires a string package name"))
    (service-response-data
     (command-desktop-task-runtime-set-package-service
      session
      package-name
      :metadata (list :source :shell-runtime-set-package
                      :enqueue-p (not (null (getf options :enqueue))))
      :register-record-p t
      :async-p (getf options :enqueue)))))

(defun execute-runtime-eval-command (arguments session)
  (let ((form-or-source (first arguments))
        (options (rest arguments)))
    (when (null arguments)
      (error "RUNTIME/EVAL requires a form or source string"))
    (when (oddp (length options))
      (error "RUNTIME/EVAL keyword options must be a property list"))
    (let ((enqueue-p (getf options :enqueue)))
      (if enqueue-p
        (service-response-data
         (command-desktop-task-runtime-eval-service
          session
          form-or-source
            :package (getf options :package)
            :metadata (list :source :shell-runtime-eval
                            :enqueue-p t)
          :register-record-p t
          :async-p t))
          (service-response-data
           (command-runtime-eval-service session
                                         form-or-source
                                         :package (getf options :package)
                                         :mutating (getf options :mutating)
                                         :recovery-launch (getf options :recovery-launch)))))))

(defun execute-runtime-history-command (arguments session)
  (let ((options arguments))
    (when (oddp (length options))
      (error "RUNTIME/HISTORY keyword options must be a property list"))
    (service-response-data
     (apply #'query-runtime-history-service session options))))

(defun execute-runtime-reload-file-command (arguments session)
  (let ((path (first arguments))
        (options (rest arguments)))
    (unless (stringp path)
      (error "RUNTIME/RELOAD-FILE requires a string path"))
    (when (oddp (length options))
      (error "RUNTIME/RELOAD-FILE keyword options must be a property list"))
    (if (getf options :enqueue)
        (service-response-data
         (command-desktop-task-runtime-reload-file-service
          session
          path
          :metadata (list :source :shell-runtime-reload-file
                          :enqueue-p t)
          :register-record-p t
          :async-p t))
        (service-response-data
         (command-runtime-reload-file-service session path)))))

(defun execute-environment-show-command (&optional environment)
  (service-response-data
   (query-environment-summary-service environment)))

(defun execute-environment-events-command (arguments &optional environment)
  (service-response-data
   (query-environment-events-service :tail (getf arguments :tail)
                                     :environment environment)))

(defun execute-environment-save-command (arguments &optional environment)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "ENVIRONMENT/SAVE requires a string path"))
    (service-response-data
     (command-environment-save-service path environment))))

(defun execute-environment-load-command (arguments session)
  (let ((path (first arguments)))
    (unless (stringp path)
      (error "ENVIRONMENT/LOAD requires a string path"))
    (let* ((*current-session* session)
           (response (command-environment-load-service path))
           (payload (service-response-data response))
           (session (getf payload :session))
           (workspace (and session
                           (service-response-data
                            (query-shell-workspace-service session)))))
      (values (list :loaded path
                    :summary (getf payload :summary)
                    :workspace workspace)
              session))))

(defun resume-turn-command-target (session turn-id)
  (if turn-id
      (or (find-turn session turn-id)
          (error "Unknown turn ~A" turn-id))
      (or (most-recent-thread-turn session)
          (error "No turns recorded for the current thread"))))

(defun execute-turn-resume-command (arguments session &optional provider)
  (let* ((turn-id (first arguments))
         (turn (resume-turn-command-target session turn-id))
         (environment (session-bound-environment session))
         (handle (and environment
                      (find-execution-handle-by-target :turn-id
                                                       (turn-id turn)
                                                       environment))))
    (if handle
        (let* ((payload (service-response-data
                         (command-execution-control-service session
                                                            (getf handle :execution-id)
                                                            :resume
                                                            :provider provider
                                                            :environment environment)))
               (resume-envelope (getf payload :result))
               (resume-result (and (listp resume-envelope)
                                   (getf resume-envelope :result))))
          (if (listp resume-result)
              resume-result
              payload))
        (resume-conversation-turn provider session turn
                                  :source (or (getf (turn-metadata turn) :source) :say)
                                  :operator-mode :conversation))))

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
         (response (command-task-enqueue-service session
                                                 form
                                                 (make-command :kind :task
                                                               :arguments arguments
                                                               :form raw-form)
                                                 priority)))
    (service-response-data response)))

(defun execute-describe-task-command (arguments session)
  (let ((task-id (first arguments)))
    (unless (stringp task-id)
      (error "DESCRIBE-TASK requires a string task id"))
    (service-response-data
     (query-task-detail-service session task-id))))

(defun execute-monitor-task-command (arguments session)
  (let ((task-id (first arguments)))
    (unless (stringp task-id)
      (error "MONITOR-TASK requires a string task id"))
    (service-response-data
     (query-task-monitor-service session task-id))))

(defun execute-cancel-task-command (arguments session)
  (let ((task-id (first arguments)))
    (unless (stringp task-id)
      (error "CANCEL-TASK requires a string task id"))
    (service-response-data
     (command-task-cancel-service session task-id))))

(defun execute-run-next-task-command (provider session)
  (service-response-data
   (command-task-run-next-service session provider)))

(defun execute-start-worker-command (provider session)
  (service-response-data
   (command-worker-start-service session provider)))

(defun execute-stop-worker-command (arguments session)
  (let ((worker-id (first arguments)))
    (unless (stringp worker-id)
      (error "STOP-WORKER requires a string worker id"))
    (service-response-data
     (command-worker-stop-service session worker-id))))

(defun execute-describe-worker-command (arguments session)
  (let ((worker-id (first arguments)))
    (unless (stringp worker-id)
      (error "DESCRIBE-WORKER requires a string worker id"))
    (service-response-data
     (query-worker-detail-service session worker-id))))

(defun enriched-work-item-detail (session work-item)
  (service-response-data
   (query-work-item-detail-service session (work-item-id work-item))))

(defun execute-describe-work-item-command (arguments session)
  (let ((work-item-id (resolve-shell-work-item-id session
                                                  (first arguments)
                                                  "DESCRIBE-WORK-ITEM")))
    (unless (stringp work-item-id)
      (error "DESCRIBE-WORK-ITEM requires a string work-item id"))
    (service-response-data
     (query-work-item-detail-service session work-item-id))))

(defun execute-describe-work-item-plan-command (arguments session)
  (let ((work-item-id (resolve-shell-work-item-id session
                                                  (first arguments)
                                                  "DESCRIBE-WORK-ITEM-PLAN")))
    (unless (stringp work-item-id)
      (error "DESCRIBE-WORK-ITEM-PLAN requires a string work-item id"))
    (service-response-data
     (query-work-item-plan-service session work-item-id))))

(defun execute-list-workflow-records-command (session)
  (service-response-data
   (query-workflow-record-list-service session)))

(defun execute-describe-workflow-record-command (arguments session)
  (let ((workflow-record-id (resolve-shell-workflow-record-id session
                                                              (first arguments)
                                                              "DESCRIBE-WORKFLOW-RECORD")))
    (unless (stringp workflow-record-id)
      (error "DESCRIBE-WORKFLOW-RECORD requires a string workflow record id"))
    (service-response-data
     (query-workflow-record-detail-service session workflow-record-id))))

(defun execute-list-plans-command (session)
  (service-response-data
   (query-plan-list-service session)))

(defun execute-list-orchestrations-command (session)
  (service-response-data
   (command-orchestration-list-query-service session)))

(defun execute-list-orchestration-inbox-command (session)
  (service-response-data
   (command-orchestration-inbox-query-service session)))

(defun execute-describe-orchestration-focus-command (arguments session)
  (let ((plan-id (getf arguments :plan-id))
        (workflow-record-id (getf arguments :workflow-record-id))
        (work-item-id (getf arguments :work-item-id)))
    (when (and plan-id workflow-record-id)
      (error "DESCRIBE-ORCHESTRATION-FOCUS accepts only one of :plan-id, :workflow-record-id, or :work-item-id"))
    (when (and plan-id work-item-id)
      (error "DESCRIBE-ORCHESTRATION-FOCUS accepts only one of :plan-id, :workflow-record-id, or :work-item-id"))
    (when (and workflow-record-id work-item-id)
      (error "DESCRIBE-ORCHESTRATION-FOCUS accepts only one of :plan-id, :workflow-record-id, or :work-item-id"))
    (when (and plan-id (not (stringp plan-id)))
      (error "DESCRIBE-ORCHESTRATION-FOCUS requires a string :plan-id when provided"))
    (when (and workflow-record-id (not (stringp workflow-record-id)))
      (error "DESCRIBE-ORCHESTRATION-FOCUS requires a string :workflow-record-id when provided"))
    (when (and work-item-id (not (stringp work-item-id)))
      (error "DESCRIBE-ORCHESTRATION-FOCUS requires a string :work-item-id when provided"))
    (service-response-data
     (command-orchestration-focus-query-service
      session
      :plan-id plan-id
      :workflow-record-id workflow-record-id
      :work-item-id work-item-id))))

(defun execute-describe-plan-command (arguments session)
  (let ((plan-id (and (first arguments)
                      (resolve-shell-plan-id session
                                             (first arguments)
                                             "DESCRIBE-PLAN"))))
    (when (and plan-id (not (stringp plan-id)))
      (error "DESCRIBE-PLAN requires a string plan id when provided"))
    (service-response-data
     (query-plan-service session plan-id))))

(defun execute-describe-active-plan-command (session)
  (service-response-data
   (command-active-plan-query-service session)))

(defun execute-describe-plan-workflow-command (arguments session)
  (let ((plan-id (and (first arguments)
                      (resolve-shell-plan-id session
                                             (first arguments)
                                             "DESCRIBE-PLAN-WORKFLOW"))))
    (when (and plan-id (not (stringp plan-id)))
      (error "DESCRIBE-PLAN-WORKFLOW requires a string plan id when provided"))
    (service-response-data
     (command-plan-linked-workflow-query-service session plan-id))))

(defun execute-describe-orchestration-snapshot-command (arguments session)
  (let ((plan-id (and (first arguments)
                      (resolve-shell-plan-id session
                                             (first arguments)
                                             "DESCRIBE-ORCHESTRATION-SNAPSHOT"))))
    (when (and plan-id (not (stringp plan-id)))
      (error "DESCRIBE-ORCHESTRATION-SNAPSHOT requires a string plan id when provided"))
    (service-response-data
     (command-orchestration-snapshot-query-service session plan-id))))

(defun execute-describe-plan-verification-command (arguments session)
  (let ((plan-id (and (first arguments)
                      (resolve-shell-plan-id session
                                             (first arguments)
                                             "DESCRIBE-PLAN-VERIFICATION"))))
    (when (and plan-id (not (stringp plan-id)))
      (error "DESCRIBE-PLAN-VERIFICATION requires a string plan id when provided"))
    (service-response-data
     (command-plan-verification-query-service session plan-id))))
(defun execute-request-work-item-approval-command (arguments session)
  (let ((work-item-id (resolve-shell-work-item-id session
                                                  (first arguments)
                                                  "REQUEST-WORK-ITEM-APPROVAL"))
        (policy (second arguments))
        (reason (getf (cddr arguments) :reason)))
    (unless (stringp work-item-id)
      (error "REQUEST-WORK-ITEM-APPROVAL requires a string work-item id"))
    (unless (keywordp policy)
      (error "REQUEST-WORK-ITEM-APPROVAL requires a keyword policy"))
    (service-response-data
     (command-request-work-item-approval-service session work-item-id policy
                                                 :reason reason))))

(defun execute-quarantine-work-item-command (arguments session)
  (let* ((work-item-or-execution-id (first arguments))
         (work-item-id (resolve-shell-work-item-id session
                                                  work-item-or-execution-id
                                                  "QUARANTINE-WORK-ITEM"))
        (execution-id (resolve-shell-work-item-execution-id session work-item-or-execution-id))
        (reason (second arguments)))
    (unless (stringp work-item-id)
      (error "QUARANTINE-WORK-ITEM requires a string work-item id"))
    (unless (stringp reason)
      (error "QUARANTINE-WORK-ITEM requires a string reason"))
    (if execution-id
        (shell-execution-control-inspection session
                                         (command-execution-control-service session execution-id :quarantine :reason reason))
        (service-response-data
         (command-work-item-quarantine-service session work-item-id reason)))))

(defun execute-resume-work-item-command (arguments session)
  (let* ((work-item-or-execution-id (first arguments))
         (work-item-id (resolve-shell-work-item-id session
                                                  work-item-or-execution-id
                                                  "RESUME-WORK-ITEM"))
        (execution-id (resolve-shell-work-item-execution-id session work-item-or-execution-id))
        (note (getf (rest arguments) :note)))
    (unless (stringp work-item-id)
      (error "RESUME-WORK-ITEM requires a string work-item id"))
    (if execution-id
        (shell-execution-control-inspection session
                                         (command-execution-control-service session execution-id :resume :note note))
        (service-response-data
         (command-work-item-resume-service session work-item-id :note note)))))

(defun execute-steer-work-item-plan-command (arguments session)
  (let ((work-item-id (resolve-shell-work-item-id session
                                                  (first arguments)
                                                  "STEER-WORK-ITEM-PLAN"))
        (phase (getf (rest arguments) :phase))
        (next-step (getf (rest arguments) :next-step))
        (note (getf (rest arguments) :note)))
    (unless (stringp work-item-id)
      (error "STEER-WORK-ITEM-PLAN requires a string work-item id"))
    (unless (keywordp phase)
      (error "STEER-WORK-ITEM-PLAN requires a keyword :phase"))
    (unless (keywordp next-step)
      (error "STEER-WORK-ITEM-PLAN requires a keyword :next-step"))
    (service-response-data
     (command-work-item-steer-service session work-item-id
                                      :phase phase
                                      :next-step next-step
                                      :note note))))

(defun execute-why-waiting-command (arguments session)
  (let ((work-item-id (resolve-shell-work-item-id session
                                                  (first arguments)
                                                  "WHY-WAITING")))
    (unless (stringp work-item-id)
      (error "WHY-WAITING requires a string work-item id"))
    (service-response-data
     (query-work-item-wait-service session work-item-id))))

(defun execute-list-replay-groups-command (session)
  (service-response-data
   (query-replay-groups-service session)))

(defun execute-list-image-reconciliations-command (session)
  (service-response-data
   (query-image-reconciliations-service session)))

(defun execute-replay-validator-task-command (arguments session)
  (let ((work-item-id (resolve-shell-work-item-id session
                                                  (first arguments)
                                                  "REPLAY-VALIDATOR-TASK"))
        (validator-task-id (second arguments))
        (status (or (getf (cddr arguments) :status) :passed)))
    (unless (stringp work-item-id)
      (error "REPLAY-VALIDATOR-TASK requires a string work-item id"))
    (unless (stringp validator-task-id)
      (error "REPLAY-VALIDATOR-TASK requires a string validator task id"))
    (service-response-data
     (command-replay-validator-task-service session
                                            work-item-id
                                            validator-task-id
                                            :status status))))

(defun execute-replay-validator-set-command (arguments session)
  (let ((work-item-id (resolve-shell-work-item-id session
                                                  (first arguments)
                                                  "REPLAY-VALIDATOR-SET"))
        (replay-id (second arguments))
        (status (or (getf (cddr arguments) :status) :passed))
        (statuses (getf (cddr arguments) :statuses)))
    (unless (stringp work-item-id)
      (error "REPLAY-VALIDATOR-SET requires a string work-item id"))
    (unless (stringp replay-id)
      (error "REPLAY-VALIDATOR-SET requires a string replay id"))
    (service-response-data
     (command-replay-validator-set-service session
                                           work-item-id
                                           replay-id
                                           :status status
                                           :statuses statuses))))

(defun execute-reconcile-image-only-source-command (arguments session)
  (let ((work-item-id (resolve-shell-work-item-id session
                                                  (first arguments)
                                                  "RECONCILE-IMAGE-ONLY-SOURCE"))
        (summary (second arguments)))
    (unless (stringp work-item-id)
      (error "RECONCILE-IMAGE-ONLY-SOURCE requires a string work-item id"))
    (unless (stringp summary)
      (error "RECONCILE-IMAGE-ONLY-SOURCE requires a string summary"))
    (service-response-data
     (command-reconcile-image-only-source-service session
                                                  work-item-id
                                                  summary))))


(defun execute-command (command provider &optional session)
  (let ((active-session (ensure-session session)))
    (append-session-event active-session :command (command-summary command))
    (let ((active-environment (or (session-bound-environment active-session)
                                  (bind-session-to-environment active-session (ensure-environment)))))
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
      (:provider-show
       (values (execute-provider-show-command active-environment)
               :provider-show
               active-session
               provider))
      (:provider-list
       (values (execute-provider-list-command active-environment)
               :provider-list
               active-session
               provider))
      (:provider-configure
       (values (execute-provider-configure-command (command-arguments command)
                                                  active-session
                                                  active-environment)
               :provider-configure
               active-session
               provider))
      (:provider-routing
       (values (execute-provider-routing-command (command-arguments command)
                                                active-session
                                                active-environment)
               :provider-routing
               active-session
               provider))
      (:provider-route
       (values (execute-provider-route-command active-environment)
               :provider-route
               active-session
               provider))
      (:platform-manifest
       (values (execute-platform-manifest-command (command-arguments command) active-session)
               :platform-manifest
               active-session
               provider))
      (:platform-package
       (values (execute-platform-package-command (command-arguments command) active-session)
               :platform-package
               active-session
               provider))
      (:platform-show-package
       (values (execute-platform-show-package-command (command-arguments command) active-session)
               :platform-show-package
               active-session
               provider))
      (:platform-validate-package
       (values (execute-platform-validate-package-command (command-arguments command) active-session)
               :platform-validate-package
               active-session
               provider))
      (:platform-import-package
       (values (execute-platform-import-package-command (command-arguments command) active-session)
               :platform-import-package
               active-session
               provider))
      (:platform-list-packages
       (values (execute-platform-list-packages-command active-session)
               :platform-list-packages
               active-session
               provider))
      (:platform-show-imported-package
       (values (execute-platform-show-imported-package-command (command-arguments command) active-session)
               :platform-show-imported-package
               active-session
               provider))
      (:platform-activate-package
       (values (execute-platform-activate-package-command (command-arguments command) active-session)
               :platform-activate-package
               active-session
               provider))
      (:platform-deactivate-package
       (values (execute-platform-deactivate-package-command (command-arguments command) active-session)
               :platform-deactivate-package
               active-session
               provider))
      (:platform-active-packages
       (values (execute-platform-active-packages-command active-session)
               :platform-active-packages
               active-session
               provider))
      (:platform-profile
       (values (execute-platform-profile-command active-session)
               :platform-profile
               active-session
               provider))
      (:platform-install-package
       (values (execute-platform-install-package-command (command-arguments command) active-session)
               :platform-install-package
               active-session
               provider))
      (:platform-simulate-package
       (values (execute-platform-simulate-package-command (command-arguments command) active-session)
               :platform-simulate-package
               active-session
               provider))
      (:platform-history
       (values (execute-platform-history-command (command-arguments command) active-session)
               :platform-history
               active-session
               provider))
      (:platform-audit
       (values (execute-platform-audit-command active-session)
               :platform-audit
               active-session
               provider))
      (:platform-harness
       (values (execute-platform-harness-command active-session)
               :platform-harness
               active-session
               provider))
      (:platform-run-harness
       (values (execute-platform-run-harness-command (command-arguments command) active-session)
               :platform-run-harness
               active-session
               provider))
      (:provider-use
       (let* ((result (execute-provider-use-command (command-arguments command)
                                                   active-session
                                                   active-environment))
              (active-profile (getf result :active-profile))
              (updated-provider (or (and active-profile
                                         (provider-from-profile active-profile))
                                    provider)))
         (values result :provider-use active-session updated-provider)))
      (:execution-show
       (values (execute-execution-show-command (command-arguments command) active-session)
               :execution-show
               active-session
               provider))
      (:execution-control
       (values (execute-execution-control-command (command-arguments command) active-session provider)
               :execution-control
               active-session
               provider))
      (:compatibility-list
       (values (execute-compatibility-list-command (command-arguments command) active-session)
               :compatibility-list
               active-session
               provider))
      (:compatibility-show
       (values (execute-compatibility-show-command (command-arguments command) active-session)
               :compatibility-show
               active-session
               provider))
      (:compatibility-apps
       (values (execute-compatibility-apps-command (command-arguments command) active-session)
               :compatibility-apps
               active-session
               provider))
      (:compatibility-app-show
       (values (execute-compatibility-app-show-command (command-arguments command) active-session)
               :compatibility-app-show
               active-session
               provider))
      (:compatibility-launch
       (values (execute-compatibility-launch-command (command-arguments command) active-session)
               :compatibility-launch
               active-session
               provider))
      (:compatibility-relaunch
       (values (execute-compatibility-relaunch-command (command-arguments command) active-session)
               :compatibility-relaunch
               active-session
               provider))
      (:compatibility-windows
       (values (execute-compatibility-windows-command (command-arguments command) active-session)
               :compatibility-windows
               active-session
               provider))
      (:workspace-show
       (values (execute-workspace-show-command active-session)
               :workspace-show
               active-session
               provider))
      (:desktop-show
       (values (execute-desktop-show-command active-session)
               :desktop-show
               active-session
               provider))
      (:desktop-task-manifests
       (values (execute-desktop-task-manifests-command active-session)
               :desktop-task-manifests
               active-session
               provider))
      (:desktop-task-manifest
       (values (execute-desktop-task-manifest-command (command-arguments command) active-session)
               :desktop-task-manifest
               active-session
               provider))
      (:desktop-task-records
       (values (execute-desktop-task-records-command (command-arguments command) active-session)
               :desktop-task-records
               active-session
               provider))
      (:desktop-task-actors
       (values (execute-desktop-task-actors-command active-session)
               :desktop-task-actors
               active-session
               provider))
      (:desktop-task-actor
       (values (execute-desktop-task-actor-command (command-arguments command) active-session)
               :desktop-task-actor
               active-session
               provider))
      (:desktop-task-inbox
       (values (execute-desktop-task-inbox-command (command-arguments command) active-session)
               :desktop-task-inbox
               active-session
               provider))
      (:desktop-task-outbox
       (values (execute-desktop-task-outbox-command (command-arguments command) active-session)
               :desktop-task-outbox
               active-session
               provider))
      (:desktop-task-message
       (values (execute-desktop-task-message-command (command-arguments command) active-session)
               :desktop-task-message
               active-session
               provider))
      (:desktop-task-editor-mailbox
       (values (execute-desktop-task-editor-mailbox-command (command-arguments command) active-session)
               :desktop-task-editor-mailbox
               active-session
               provider))
      (:desktop-task-editor-pending-mutations
       (values (execute-desktop-task-editor-pending-mutations-command (command-arguments command) active-session)
               :desktop-task-editor-pending-mutations
               active-session
               provider))
      (:desktop-task-context-chat-mailbox
       (values (execute-desktop-task-context-chat-mailbox-command (command-arguments command) active-session)
               :desktop-task-context-chat-mailbox
               active-session
               provider))
      (:desktop-task-context-chat-context
       (values (execute-desktop-task-context-chat-context-command active-session)
               :desktop-task-context-chat-context
               active-session
               provider))
      (:desktop-task-set-context-chat-projects
       (values (execute-desktop-task-set-context-chat-projects-command (command-arguments command) active-session)
               :desktop-task-set-context-chat-projects
               active-session
               provider))
      (:desktop-task-context-chat-approval-inbox
       (values (execute-desktop-task-context-chat-approval-inbox-command (command-arguments command) active-session)
               :desktop-task-context-chat-approval-inbox
               active-session
               provider))
      (:desktop-task-ack-context-chat-approval
       (values (execute-desktop-task-ack-context-chat-approval-command (command-arguments command) active-session)
               :desktop-task-ack-context-chat-approval
               active-session
               provider))
      (:desktop-task-editor-authorizations
       (values (execute-desktop-task-editor-authorizations-command (command-arguments command) active-session)
               :desktop-task-editor-authorizations
               active-session
               provider))
      (:desktop-task-consume-editor-authorization
       (values (execute-desktop-task-consume-editor-authorization-command (command-arguments command) active-session)
               :desktop-task-consume-editor-authorization
               active-session
               provider))
      (:desktop-task-apply-editor-authorization
       (values (execute-desktop-task-apply-editor-authorization-command (command-arguments command) active-session)
               :desktop-task-apply-editor-authorization
               active-session
               provider))
      (:desktop-task-actor-trace
       (values (execute-desktop-task-actor-trace-command (command-arguments command) active-session)
               :desktop-task-actor-trace
               active-session
               provider))
      (:desktop-task-dlq
       (values (execute-desktop-task-dlq-command (command-arguments command) active-session)
               :desktop-task-dlq
               active-session
               provider))
      (:desktop-task-replies
       (values (execute-desktop-task-replies-command (command-arguments command) active-session)
               :desktop-task-replies
               active-session
               provider))
      (:desktop-task-latest-reply
       (values (execute-desktop-task-replies-command (command-arguments command)
                                                     active-session
                                                     :latest-only-p t)
               :desktop-task-latest-reply
               active-session
               provider))
      (:desktop-task-approve-message
       (values (execute-desktop-task-approve-message-command (command-arguments command)
                                                             active-session
                                                             provider)
               :desktop-task-approve-message
               active-session
               provider))
      (:desktop-task-approve-approval
       (values (execute-desktop-task-approve-approval-command (command-arguments command)
                                                              active-session
                                                              provider)
               :desktop-task-approve-approval
               active-session
               provider))
      (:desktop-task-pending-approval
       (values (execute-desktop-task-pending-approval-command active-session)
               :desktop-task-pending-approval
               active-session
               provider))
      (:desktop-task-governance-state
       (values (execute-desktop-task-governance-state-command (command-arguments command) active-session)
               :desktop-task-governance-state
               active-session
               provider))
      (:desktop-task-governance-inbox
       (values (execute-desktop-task-governance-inbox-command (command-arguments command) active-session)
               :desktop-task-governance-inbox
               active-session
               provider))
      (:desktop-task-governance-decisions
       (values (execute-desktop-task-governance-decisions-command (command-arguments command) active-session)
               :desktop-task-governance-decisions
               active-session
               provider))
      (:desktop-task-runtime-outbox
       (values (execute-desktop-task-runtime-outbox-command (command-arguments command) active-session)
               :desktop-task-runtime-outbox
               active-session
               provider))
      (:desktop-task-runtime-state
       (values (execute-desktop-task-runtime-state-command (command-arguments command) active-session)
               :desktop-task-runtime-state
               active-session
               provider))
      (:desktop-task-actor-flow
       (values (execute-desktop-task-actor-flow-command (command-arguments command) active-session)
               :desktop-task-actor-flow
               active-session
               provider))
      (:desktop-task-actor-system-panel
       (values (execute-desktop-task-actor-system-panel-command (command-arguments command) active-session)
               :desktop-task-actor-system-panel
               active-session
               provider))
      (:desktop-task-supervision-incidents
       (values (execute-desktop-task-supervision-incidents-command (command-arguments command) active-session)
               :desktop-task-supervision-incidents
               active-session
               provider))
      (:desktop-task-supervision-escalation-inbox
       (values (execute-desktop-task-supervision-escalation-inbox-command (command-arguments command) active-session)
               :desktop-task-supervision-escalation-inbox
               active-session
               provider))
      (:desktop-task-ack-supervision-escalation
       (values (execute-desktop-task-ack-supervision-escalation-command (command-arguments command) active-session)
               :desktop-task-ack-supervision-escalation
               active-session
               provider))
      (:desktop-task-apply-supervision-escalation
       (values (execute-desktop-task-apply-supervision-escalation-command (command-arguments command) active-session)
               :desktop-task-apply-supervision-escalation
               active-session
               provider))
      (:desktop-task-process-supervision-escalation
       (values (execute-desktop-task-process-supervision-escalation-command (command-arguments command) active-session)
               :desktop-task-process-supervision-escalation
               active-session
               provider))
      (:desktop-task-fail-mailbox-entry
       (values (execute-desktop-task-fail-mailbox-entry-command (command-arguments command) active-session)
               :desktop-task-fail-mailbox-entry
               active-session
               provider))
      (:desktop-task-apply-supervision-action
       (values (execute-desktop-task-apply-supervision-action-command (command-arguments command) active-session)
               :desktop-task-apply-supervision-action
               active-session
               provider))
      (:desktop-task-show
       (values (execute-desktop-task-show-command (command-arguments command) active-session)
               :desktop-task-show
               active-session
               provider))
      (:desktop-task-mcp-servers
       (values (execute-desktop-task-mcp-servers-command active-session)
               :desktop-task-mcp-servers
               active-session
               provider))
      (:desktop-task-mcp-server
       (values (execute-desktop-task-mcp-server-command (command-arguments command) active-session)
               :desktop-task-mcp-server
               active-session
               provider))
      (:desktop-task-configure-mcp-server
       (values (execute-desktop-task-configure-mcp-server-command (command-arguments command) active-session)
               :desktop-task-configure-mcp-server
               active-session
               provider))
      (:desktop-task-remove-mcp-server
       (values (execute-desktop-task-remove-mcp-server-command (command-arguments command) active-session)
               :desktop-task-remove-mcp-server
               active-session
               provider))
      (:desktop-panel
       (values (execute-desktop-panel-command (command-arguments command) active-session)
               :desktop-panel
               active-session
               provider))
      (:desktop-select
       (values (execute-desktop-select-command (command-arguments command) active-session)
               :desktop-select
               active-session
               provider))
      (:desktop-restore
       (values (execute-desktop-restore-command (command-arguments command) active-session)
               :desktop-restore
               active-session
               provider))
      (:desktop-action
       (values (execute-desktop-action-command (command-arguments command) active-session)
               :desktop-action
               active-session
               provider))
      (:surface-list
       (values (execute-surface-list-command active-session)
               :surface-list
               active-session
               provider))
      (:surface-select
       (values (execute-surface-select-command (command-arguments command) active-session)
               :surface-select
               active-session
               provider))
      (:surface-step
       (values (execute-surface-step-command (command-arguments command) active-session)
               :surface-step
               active-session
               provider))
      (:display-list
       (values (execute-display-list-command active-session)
               :display-list
               active-session
               provider))
      (:display-show
       (values (execute-display-show-command (command-arguments command) active-session)
               :display-show
               active-session
               provider))
      (:display-select
       (values (execute-display-select-command (command-arguments command) active-session)
               :display-select
               active-session
               provider))
      (:display-step
       (values (execute-display-step-command (command-arguments command) active-session)
               :display-step
               active-session
               provider))
      (:display-control
       (values (execute-display-control-command (command-arguments command) active-session)
               :display-control
               active-session
               provider))
      (:open
       (values (execute-open-command (command-arguments command) active-session)
               :open
               active-session
               provider))
      (:focus-show
       (values (execute-focus-show-command active-session)
               :focus-show
               active-session
               provider))
      (:focus-set
       (values (execute-focus-set-command (command-arguments command) active-session)
               :focus-set
               active-session
               provider))
      (:governance-queue
       (values (execute-governance-queue-command active-session)
               :governance-queue
               active-session
               provider))
      (:governance-select
       (values (execute-governance-select-command (command-arguments command) active-session)
               :governance-select
               active-session
               provider))
      (:object-browser
       (values (execute-object-browser-command (command-arguments command) active-session)
               :object-browser
               active-session
               provider))
      (:object-browser-select
       (values (execute-object-browser-select-command (command-arguments command) active-session)
               :object-browser-select
               active-session
               provider))
      (:inspector-show
       (values (execute-inspector-show-command (command-arguments command) active-session)
               :inspector-show
               active-session
               provider))
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
      (:incident-condition
       (values (execute-incident-condition-command (command-arguments command) active-session)
               :incident-condition
               active-session))
      (:incident-restarts
       (values (execute-incident-restarts-command (command-arguments command) active-session)
               :incident-restarts
               active-session))
      (:runtime-condition
       (values (execute-runtime-condition-command (command-arguments command) active-session)
               :runtime-condition
               active-session))
      (:runtime-object
       (values (execute-runtime-object-command (command-arguments command) active-session)
               :runtime-object
               active-session))
      (:runtime-restarts
       (values (execute-runtime-restarts-command (command-arguments command) active-session)
               :runtime-restarts
               active-session))
      (:environment-status
       (values (execute-environment-status-command active-session)
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
      (:integration-rgp-workspace
       (values (execute-integration-rgp-workspace-command active-session)
               :integration-rgp-workspace
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
      (:runtime-inspect
       (values (execute-runtime-inspect-command (command-arguments command) active-session)
               :runtime-inspect
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
           (execute-environment-load-command (command-arguments command) active-session)
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
       (values (service-response-data
                (query-task-list-service active-session))
               :list-tasks
               active-session))
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
       (values (execute-run-next-task-command provider active-session)
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
       (values (service-response-data
                (query-worker-list-service active-session))
               :list-workers
               active-session))
      (:list-work-items
       (values (service-response-data
                (query-work-item-list-service active-session))
               :list-work-items
               active-session))
      (:describe-work-item
       (values (execute-describe-work-item-command (command-arguments command) active-session)
               :describe-work-item
               active-session))
      (:describe-work-item-plan
       (values (execute-describe-work-item-plan-command (command-arguments command) active-session)
               :describe-work-item-plan
               active-session))
      (:list-workflow-records
       (values (execute-list-workflow-records-command active-session) :list-workflow-records active-session))
      (:describe-workflow-record
       (values (execute-describe-workflow-record-command (command-arguments command) active-session)
               :describe-workflow-record
               active-session))
      (:list-plans
       (values (execute-list-plans-command active-session)
               :list-plans
               active-session))
      (:list-orchestrations
       (values (execute-list-orchestrations-command active-session)
               :list-orchestrations
               active-session))
      (:list-orchestration-inbox
       (values (execute-list-orchestration-inbox-command active-session)
               :list-orchestration-inbox
               active-session))
      (:describe-orchestration-focus
       (values (execute-describe-orchestration-focus-command (command-arguments command) active-session)
               :describe-orchestration-focus
               active-session))
      (:describe-plan
       (values (execute-describe-plan-command (command-arguments command) active-session)
               :describe-plan
               active-session))
      (:describe-active-plan
       (values (execute-describe-active-plan-command active-session)
               :describe-active-plan
               active-session))
      (:describe-plan-workflow
       (values (execute-describe-plan-workflow-command (command-arguments command) active-session)
               :describe-plan-workflow
               active-session))
      (:describe-orchestration-snapshot
       (values (execute-describe-orchestration-snapshot-command (command-arguments command) active-session)
               :describe-orchestration-snapshot
               active-session))
      (:describe-plan-verification
       (values (execute-describe-plan-verification-command (command-arguments command) active-session)
               :describe-plan-verification
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
      (:steer-work-item-plan
       (values (execute-steer-work-item-plan-command (command-arguments command) active-session)
               :steer-work-item-plan
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
           (execute-session-load-command (command-arguments command) active-session)
         (values result :session-load loaded-session)))
      (:session-reset
       (let ((fresh-session (reset-session active-session)))
         (values (list :reset (agent-session-id fresh-session)
                       :summary (session-summary fresh-session)
                       :workspace (service-response-data
                                   (query-shell-workspace-service fresh-session)))
                 :session-reset
                 fresh-session)))
      (:describe-session
       (values (service-response-data
                (query-session-summary-service active-session))
               :describe-session
               active-session))
      (:help
       (print-shell-help)
       (values nil :help active-session))
      (t
       (error "Unsupported command kind ~S" (command-kind command)))))))

(defun print-shell-result (result kind)
  (case kind
    (:help nil)
    (:assistant-action
     (format t "assistant-action-result> ~S~%" result))
    (:execution-show
     (format t "execution> ~A object=~A status=~A capability=~A~%"
             (or (getf (getf result :execution) :execution-id) "<unknown>")
             (or (getf result :object-kind) :unknown)
             (or (getf (getf result :execution) :status) :unknown)
             (or (getf (getf result :execution) :capability) :unknown))
     (let ((inspection (getf result :inspection))
           (related (getf result :related)))
       (when (listp inspection)
         (format t "execution-inspection> ~S~%" inspection))
       (when (listp related)
         (format t "execution-related> ~S~%" related)))
     (finish-output))
    (:execution-control
     (format t "execution-control> ~A action=~A status=~A~%"
             (or (getf (getf result :execution) :execution-id) "<unknown>")
             (or (getf result :action) :unknown)
             (or (getf (getf (getf result :post-state) :inspection) :status)
                 (getf (getf result :execution) :status)
                 :unknown))
     (when (getf result :post-state)
       (format t "execution-post-state> ~S~%" (getf result :post-state)))
     (finish-output))
    (:runtime-eval
     (if (getf result :queued-p)
         (format t "runtime-task> queued=~A job=~A record=~S~%"
                 t
                 (or (getf result :actor-execution-job-id) :none)
                 (or (getf result :task-record) '()))
         (format t "runtime-eval> ~S~%" result))
     (finish-output))
    (:runtime-reload-file
     (if (getf result :queued-p)
         (format t "runtime-task> queued=~A job=~A record=~S~%"
                 t
                 (or (getf result :actor-execution-job-id) :none)
                 (or (getf result :task-record) '()))
         (format t "runtime-reload-file> ~S~%" result))
     (finish-output))
    (:compatibility-list
     (format t "compatibility> count=~D filters=~S~%"
             (or (getf result :count) 0)
             (or (getf result :filters) '()))
     (dolist (entry (or (getf result :entries) '()))
       (format t "compatibility-entry> ~A kind=~A status=~A backend=~A sandbox=~A actions=~S relaunch=~A loss=~A ack=~A cwd=~A argv=~S~%"
               (or (getf entry :execution-id) "<unknown>")
               (or (getf entry :kind) :none)
               (or (getf entry :status) :unknown)
               (or (getf entry :backend) :none)
               (or (getf entry :sandbox-profile) :none)
               (or (getf (getf entry :control-posture) :supported-actions) '())
               (not (null (member :relaunch
                                  (getf (getf entry :control-posture) :supported-actions))))
               (or (getf entry :detached-runtime-loss-p) nil)
               (or (getf entry :loss-acknowledged-p) nil)
               (or (getf (getf entry :compatibility) :cwd) :none)
               (or (getf (getf entry :compatibility) :argv) '())))
     (finish-output))
    (:compatibility-show
     (format t "compatibility-show> ~A status=~A mode=~A terminal=~A~%"
             (or (getf (getf result :execution) :execution-id) "<unknown>")
             (or (getf (getf result :lifecycle) :status) :unknown)
             (or (getf (getf result :lifecycle) :execution-mode) :unknown)
             (or (getf (getf result :lifecycle) :terminal-p) nil))
     (format t "compatibility-control> ~S~%"
             (or (getf (getf result :lifecycle) :control-posture) '()))
     (format t "compatibility-lifecycle> ~S~%"
             (or (getf result :lifecycle) '()))
     (when (getf (getf result :lifecycle) :relaunch-ready-p)
       (format t "compatibility-relaunch> app=~A latest=~A~%"
               (or (getf (getf result :lifecycle) :relaunch-app-id) :none)
               (or (getf (getf result :lifecycle) :relaunch-execution-id) :none)))
     (format t "compatibility-inspection> ~S~%"
             (or (getf result :inspection) '()))
     (finish-output))
    (:compatibility-apps
     (format t "compatibility-apps> count=~D selected=~A~%"
             (or (getf result :count) 0)
             (or (getf result :selected-app-id) :none))
     (dolist (entry (or (getf result :entries) '()))
       (format t "compatibility-app> ~A title=~A tool=~A exec=~A defaults=~S executions=~D running=~D~%"
               (or (getf entry :id) "<unknown>")
               (or (getf entry :title) :none)
               (or (getf entry :launch-tool-id) :none)
               (or (getf entry :executable) :none)
               (or (getf entry :default-arguments) '())
               (or (getf entry :execution-count) 0)
               (or (getf entry :running-count) 0)))
     (finish-output))
    (:compatibility-app-show
     (format t "compatibility-app-show> ~S~%" result)
     (finish-output))
    (:compatibility-launch
     (format t "compatibility-launch> exec=~A app=~A status=~A~%"
             (or (getf (getf result :execution) :execution-id) "<unknown>")
             (or (getf result :app-id)
                 (getf (getf result :compatibility-target) :app-id)
                 :none)
             (or (getf result :status) :unknown))
     (when (getf result :compatibility-target)
       (format t "compatibility-launch-target> ~S~%" (getf result :compatibility-target)))
     (finish-output))
    (:compatibility-relaunch
     (format t "compatibility-relaunch> exec=~A previous=~A status=~A~%"
             (or (getf (getf result :execution) :execution-id) "<unknown>")
             (or (getf (getf (getf result :result) :compatibility-result) :previous-execution-id) :none)
             (or (getf (getf (getf result :result) :compatibility-result) :status) :unknown))
     (when (getf result :post-state)
       (format t "compatibility-relaunch-post-state> ~S~%" (getf result :post-state)))
     (finish-output))
    (:compatibility-windows
     (format t "compatibility-windows> count=~D filters=~S~%"
             (or (getf result :count) 0)
             (or (getf result :filters) '()))
     (dolist (entry (or (getf result :entries) '()))
       (format t "compatibility-window> ~A app=~A kind=~A state=~A status=~A open=~A~%"
               (or (getf entry :display-id) "<unknown>")
               (or (getf entry :app-id) :none)
               (or (getf entry :display-surface-kind) :none)
               (or (getf entry :window-state) :unknown)
               (or (getf entry :status) :unknown)
               (format nil "(open :execution-id ~S)" (getf entry :execution-id))))
     (finish-output))
    (:workspace-show
     (format t "workspace> session=~A env=~A plan=~A surfaces=~D displays=~D governance=~D groups=~D~%"
             (or (getf result :workspace-id) :none)
             (or (getf result :environment-id) :none)
             (or (getf result :plan) :none)
             (or (getf (getf result :execution-surfaces) :count) 0)
             (or (getf (getf result :display-surfaces) :count) 0)
             (or (getf (getf result :governance-queue) :count) 0)
             (or (getf result :object-browser-group-count)
                 (getf (getf result :object-browser) :group-count)
                 0))
     (when (getf result :inspector-focus-object-id)
       (format t "workspace-focus> ~A~%" (getf result :inspector-focus-object-id)))
     (when (getf result :current-focus)
       (format t "workspace-current-focus> kind=~A label=~A status=~A exec=~A app=~A~%"
               (or (getf (getf result :current-focus) :focus-kind) :none)
               (or (getf (getf result :current-focus) :label) :none)
               (or (getf (getf result :current-focus) :status) :unknown)
               (or (getf (getf result :current-focus) :execution-id) :none)
               (or (getf (getf result :current-focus) :app-id) :none)))
     (when (getf result :recommended-action)
       (format t "workspace-next-action> label=~A kind=~A command=~A action-id=~A~%"
               (or (getf (getf result :recommended-action) :label) :none)
               (or (getf (getf result :recommended-action) :action-kind) :none)
               (or (getf (getf result :recommended-action) :command) :none)
               (or (getf (getf result :recommended-action) :action-id) :none)))
     (when (getf result :top-surface)
       (format t "workspace-top-surface> ~A status=~A exec=~A~%"
               (or (getf (getf result :top-surface) :surface-kind) :none)
               (or (getf (getf result :top-surface) :status) :unknown)
               (or (getf (getf result :top-surface) :execution-id) :none)))
     (when (getf (getf result :display-surfaces) :top-surface)
       (format t "workspace-top-display> ~A state=~A exec=~A~%"
               (or (getf (getf (getf result :display-surfaces) :top-surface) :app-id) :none)
               (or (getf (getf (getf result :display-surfaces) :top-surface) :window-state) :unknown)
               (or (getf (getf (getf result :display-surfaces) :top-surface) :execution-id) :none)))
     (when (getf result :current-display-surface)
       (format t "workspace-current-display> app=~A state=~A exec=~A~%"
               (or (getf (getf result :current-display-surface) :app-id) :none)
               (or (getf (getf result :current-display-surface) :window-state) :unknown)
               (or (getf (getf result :current-display-surface) :execution-id) :none)))
     (when (getf result :current-display-posture)
       (format t "workspace-display-state> status=~A kind=~A controllable=~A relaunch=~A source=~A actions=~S~%"
               (or (getf (getf result :current-display-posture) :status) :unknown)
               (or (getf (getf result :current-display-posture) :display-surface-kind) :none)
               (or (getf (getf result :current-display-posture) :controllable-p) nil)
               (or (getf (getf result :current-display-posture) :relaunch-ready-p) nil)
               (or (getf (getf result :current-display-posture) :source-package-id) :none)
               (or (getf (getf result :current-display-posture) :supported-actions) '())))
     (render-shell-open-handoff "workspace-open"
                                (shell-open-command-for-surface-index 0))
     (when (getf (getf result :display-surfaces) :top-surface)
       (render-shell-open-handoff "workspace-display-open"
                                  (shell-open-command-for-surface
                                   (getf (getf result :display-surfaces) :top-surface))))
     (when (getf result :display-actions)
       (format t "workspace-display-actions> show=~A next=~A previous=~A relaunch=~A stop=~A~%"
               (or (getf (getf result :display-actions) :show-command) :none)
               (or (getf (getf result :display-actions) :next-command) :none)
               (or (getf (getf result :display-actions) :previous-command) :none)
               (or (getf (getf result :display-actions) :relaunch-command) :none)
               (or (getf (getf result :display-actions) :stop-command) :none)))
     (when (getf result :display-actions)
       (format t "workspace-display-action-ids> show=~A next=~A previous=~A relaunch=~A stop=~A~%"
               (or (getf (getf result :display-action-ids) :show) :none)
               (or (getf (getf result :display-action-ids) :next) :none)
               (or (getf (getf result :display-action-ids) :previous) :none)
               (or (getf (getf result :display-action-ids) :relaunch) :none)
               (or (getf (getf result :display-action-ids) :stop) :none)))
     (when (getf result :display-entry-actions)
       (format t "workspace-display-entry-actions> open=~A show=~A next=~A previous=~A relaunch=~A stop=~A~%"
               (or (getf (getf (getf result :display-entry-actions) :open) :command) :none)
               (or (getf (getf (getf result :display-entry-actions) :show) :command) :none)
               (or (getf (getf (getf result :display-entry-actions) :next) :command) :none)
               (or (getf (getf (getf result :display-entry-actions) :previous) :command) :none)
               (or (getf (getf (getf result :display-entry-actions) :relaunch) :command) :none)
               (or (getf (getf (getf result :display-entry-actions) :stop) :command) :none)))
     (when (getf result :display-entry-actions)
       (format t "workspace-display-entry-action-ids> open=~A show=~A next=~A previous=~A relaunch=~A stop=~A~%"
               (or (getf (getf result :display-entry-action-ids) :open) :none)
               (or (getf (getf result :display-entry-action-ids) :show) :none)
               (or (getf (getf result :display-entry-action-ids) :next) :none)
               (or (getf (getf result :display-entry-action-ids) :previous) :none)
               (or (getf (getf result :display-entry-action-ids) :relaunch) :none)
               (or (getf (getf result :display-entry-action-ids) :stop) :none)))
     (when (getf (getf result :governance-queue) :top-item)
       (render-shell-open-handoff "workspace-governance-open"
                                  (shell-open-command-for-governance-index 0)))
     (finish-output))
    (:desktop-show
     (format t "desktop> session=~A env=~A plan=~A surfaces=~D displays=~D governance=~D groups=~D focus=~A entries=~D~%"
             (or (getf result :workspace-id) :none)
             (or (getf result :environment-id) :none)
             (or (getf result :plan) :none)
             (or (getf result :surface-count) 0)
             (or (getf result :display-count) 0)
             (or (getf result :governance-count) 0)
             (or (getf result :object-group-count) 0)
             (or (getf result :focus-object-id) :none)
             (length (or (getf result :entry-points) '())))
    (format t "desktop-active-panel> ~A~%"
            (or (getf result :active-panel) :none))
    (when (getf result :active-panel-summary)
      (format t "desktop-active-summary> panel=~A label=~A focus=~A exec=~A app=~A status=~A~%"
              (or (getf (getf result :active-panel-summary) :panel-id) :none)
              (or (getf (getf result :active-panel-summary) :label) :none)
              (or (getf (getf result :active-panel-summary) :focus-object-id) :none)
              (or (getf (getf result :active-panel-summary) :execution-id) :none)
              (or (getf (getf result :active-panel-summary) :app-id) :none)
              (or (getf (getf result :active-panel-summary) :status) :unknown)))
    (when (and (eq (getf result :active-panel) :inspector)
               (getf result :active-panel-summary))
      (format t "desktop-inspector-summary> object=~A resolved=~A history=~A~%"
              (or (getf (getf result :active-panel-summary) :object-kind) :unknown)
              (or (getf (getf result :active-panel-summary) :resolved-via) :unknown)
              (or (getf (getf result :active-panel-summary) :history-count) 0)))
    (when (getf result :recommended-action)
      (format t "desktop-next-action> label=~A kind=~A command=~A action-id=~A~%"
              (or (getf (getf result :recommended-action) :label) :none)
              (or (getf (getf result :recommended-action) :action-kind) :none)
              (or (getf (getf result :recommended-action) :command) :none)
              (or (getf (getf result :recommended-action) :action-id) :none)))
    (when (getf result :top-surface)
      (format t "desktop-top-surface> ~A status=~A exec=~A~%"
              (or (getf (getf result :top-surface) :surface-kind) :none)
               (or (getf (getf result :top-surface) :status) :unknown)
               (or (getf (getf result :top-surface) :execution-id) :none)))
     (when (getf result :top-display-surface)
       (format t "desktop-top-display> app=~A state=~A exec=~A~%"
               (or (getf (getf result :top-display-surface) :app-id) :none)
               (or (getf (getf result :top-display-surface) :window-state) :unknown)
               (or (getf (getf result :top-display-surface) :execution-id) :none)))
     (when (getf result :top-governance-item)
       (format t "desktop-top-governance> queue=~A status=~A exec=~A~%"
               (or (getf (getf result :top-governance-item) :queue-kind) :none)
               (or (getf (getf result :top-governance-item) :status) :unknown)
               (or (getf (getf result :top-governance-item) :execution-id) :none)))
     (dolist (entry (or (getf result :entry-points) '()))
       (format t "desktop-entry> kind=~A label=~A command=~A focus=~A action=~A actions=~S~%"
               (or (getf entry :entry-kind) :none)
               (or (getf entry :label) :none)
               (or (getf entry :command) :none)
               (or (getf entry :focus-object-id) :none)
               (or (getf (getf entry :action) :action-id) :none)
               (and (getf entry :actions)
                    (loop for (key value) on (getf entry :actions) by #'cddr
                          collect (list key (getf value :action-id))))))
     (let ((panels (getf result :panels)))
       (when panels
         (case (getf result :active-panel)
           (:workspace
            (format t "desktop-panel> workspace selected=~A exec=~A focus=~A open=~A~%"
                    (or (getf (getf panels :workspace) :selected-index) :none)
                    (or (getf (getf panels :workspace) :selected-execution-id) :none)
                    (or (getf (getf panels :workspace) :focus-object-id) :none)
                    (or (getf (getf (getf panels :workspace) :actions) :open-command) :none))
            (format t "desktop-panel/actions> workspace activate=~A open=~A restore=~A~%"
                    (or (getf (getf (getf (getf panels :workspace) :actions) :activate) :action-id) :none)
                    (or (getf (getf (getf (getf panels :workspace) :actions) :open) :action-id) :none)
                    (or (getf (getf (getf (getf panels :workspace) :actions) :restore) :action-id) :none)))
           (:display
            (format t "desktop-panel> display selected=~A exec=~A app=~A state=~A open=~A~%"
                    (or (getf (getf panels :display) :selected-index) :none)
                    (or (getf (getf panels :display) :selected-execution-id) :none)
                    (or (getf (getf panels :display) :selected-app-id) :none)
                    (or (getf (getf panels :display) :selected-window-state) :none)
                    (or (getf (getf (getf panels :display) :actions) :open-command) :none))
            (format t "desktop-panel/display-state> status=~A kind=~A controllable=~A relaunch=~A actions=~S~%"
                    (or (getf (getf panels :display) :selected-status) :unknown)
                    (or (getf (getf panels :display) :selected-display-surface-kind) :none)
                    (or (getf (getf panels :display) :selected-controllable-p) nil)
                    (or (getf (getf panels :display) :selected-relaunch-ready-p) nil)
                    (or (getf (getf panels :display) :selected-supported-actions) '()))
            (format t "desktop-panel/actions> display show=~A next=~A previous=~A relaunch=~A stop=~A~%"
                    (or (getf (getf (getf panels :display) :actions) :show-command) :none)
                    (or (getf (getf (getf panels :display) :actions) :next-command) :none)
                    (or (getf (getf (getf panels :display) :actions) :previous-command) :none)
                    (or (getf (getf (getf panels :display) :actions) :relaunch-command) :none)
                    (or (getf (getf (getf panels :display) :actions) :stop-command) :none)))
           (:governance
            (format t "desktop-panel> governance selected=~A title=~A focus=~A open=~A~%"
                    (or (getf (getf panels :governance) :selected-index) :none)
                    (or (getf (getf panels :governance) :selected-title) :none)
                    (or (getf (getf panels :governance) :focus-object-id) :none)
                    (or (getf (getf (getf panels :governance) :actions) :open-command) :none)))
           (:object-browser
            (format t "desktop-panel> object-browser kind=~A index=~A title=~A focus=~A open=~A~%"
                    (or (getf (getf panels :object-browser) :selected-kind) :none)
                    (or (getf (getf panels :object-browser) :selected-index) :none)
                    (or (getf (getf panels :object-browser) :selected-title) :none)
                    (or (getf (getf panels :object-browser) :focus-object-id) :none)
                    (or (getf (getf (getf panels :object-browser) :actions) :open-command) :none)))
           (:inspector
            (format t "desktop-panel> inspector object=~A focus=~A open=~A~%"
                    (or (getf (getf panels :inspector) :object-kind) :none)
                    (or (getf (getf panels :inspector) :focus-object-id) :none)
                    (or (getf (getf (getf panels :inspector) :actions) :open-command) :none)))
           (otherwise nil))))
    (finish-output))
    (:desktop-task-manifests
     (format t "desktop-task-manifests> count=~D~%"
             (length (or result '())))
     (dolist (entry (or result '()))
       (format t "desktop-task-manifest> id=~A target=~A operation=~A capability=~A backend=~A mode=~A policy=~A version=~A~%"
               (or (getf entry :id) :none)
               (or (getf entry :target) :none)
               (or (getf entry :operation) :none)
               (or (getf entry :capability) :none)
               (or (getf entry :backend-kind) :none)
               (or (getf entry :execution-mode) :none)
               (or (getf entry :approval-policy) :none)
               (or (getf entry :version) :none)))
     (finish-output))
    (:desktop-task-manifest
     (format t "desktop-task-manifest> id=~A target=~A operation=~A capability=~A backend=~A mode=~A policy=~A version=~A~%"
             (or (getf result :id) :none)
             (or (getf result :target) :none)
             (or (getf result :operation) :none)
             (or (getf result :capability) :none)
             (or (getf result :backend-kind) :none)
             (or (getf result :execution-mode) :none)
             (or (getf result :approval-policy) :none)
             (or (getf result :version) :none))
     (when (getf result :description)
       (format t "desktop-task-manifest-description> ~A~%" (getf result :description)))
     (when (getf result :request-schema)
       (format t "desktop-task-manifest-request> ~S~%" (getf result :request-schema)))
     (when (getf result :result-schema)
       (format t "desktop-task-manifest-result> ~S~%" (getf result :result-schema)))
     (finish-output))
    (:desktop-task-records
     (format t "desktop-task-records> count=~D~%" (length (or result '())))
     (dolist (entry (or result '()))
       (format t "desktop-task-record> id=~A target=~A operation=~A status=~A governance=~A approval=~A thread=~A turn=~A backend=~A retries=~A/~A~%"
               (or (getf entry :id) :none)
               (or (getf entry :target) :none)
               (or (getf entry :operation) :none)
               (or (getf entry :status) :unknown)
               (or (getf entry :governance-status) :unknown)
               (or (getf entry :approval-status) :unknown)
               (or (getf entry :thread-id) :none)
               (or (getf entry :turn-id) :none)
               (or (getf entry :backend-kind) :none)
               (or (getf entry :retry-count) 0)
               (or (getf entry :max-attempts) 0)))
     (finish-output))
    (:desktop-task-show
     (format t "desktop-task-show> id=~A target=~A operation=~A status=~A governance=~A approval=~A backend=~A retryable=~A retries=~A/~A~%"
             (or (getf result :id) :none)
             (or (getf result :target) :none)
             (or (getf result :operation) :none)
             (or (getf result :status) :unknown)
             (or (getf result :governance-status) :unknown)
             (or (getf result :approval-status) :unknown)
             (or (getf result :backend-kind) :none)
             (if (getf result :retryable-p) :yes :no)
             (or (getf result :retry-count) 0)
             (or (getf result :max-attempts) 0))
     (when (getf result :resolution)
       (format t "desktop-task-resolution> ~S~%" (getf result :resolution)))
     (when (getf result :result)
       (format t "desktop-task-result> ~S~%" (getf result :result)))
     (when (getf result :last-error)
       (format t "desktop-task-error> ~S~%" (getf result :last-error)))
     (finish-output))
    (:desktop-task-governance-state
     (format t "desktop-task-governance> session=~A approval=~A count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :approval-id) :none)
             (or (getf result :count) 0))
     (dolist (entry (or (getf result :requests) '()))
       (format t "governance-request> approval=~A session=~A actor-message=~A target=~A operation=~A status=~A governance=~A approval-status=~A~%"
               (or (getf entry :approval-id) :none)
               (or (getf entry :session-id) :none)
               (or (getf entry :actor-message-id) :none)
               (or (getf entry :target) :none)
               (or (getf entry :operation) :none)
               (or (getf entry :status) :unknown)
               (or (getf entry :governance-status) :unknown)
               (or (getf entry :approval-status) :unknown)))
     (finish-output))
    (:desktop-task-governance-inbox
     (format t "desktop-task-governance-inbox> session=~A request-count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :request-count) 0))
     (dolist (entry (or (getf result :requests) '()))
       (format t "governance-inbox> approval=~A session=~A actor-message=~A target=~A operation=~A status=~A governance=~A approval-status=~A~%"
               (or (getf entry :approval-id) :none)
               (or (getf entry :session-id) :none)
               (or (getf entry :actor-message-id) :none)
               (or (getf entry :target) :none)
               (or (getf entry :operation) :none)
               (or (getf entry :status) :unknown)
               (or (getf entry :governance-status) :unknown)
               (or (getf entry :approval-status) :unknown)))
     (finish-output))
    (:desktop-task-editor-mailbox
     (format t "desktop-task-editor-mailbox> session=~A mutation-count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :mutation-count) 0))
     (dolist (entry (or (getf result :mutations) '()))
       (format t "editor-mutation> pending-action=~A approval=~A actor-message=~A scope=~A buffer=~A status=~A governance=~A approval-status=~A~%"
               (or (getf entry :pending-action-id) :none)
               (or (getf entry :approval-id) :none)
               (or (getf entry :actor-message-id) :none)
               (or (getf entry :scope-id) :none)
               (or (getf entry :buffer-id) :none)
               (or (getf entry :status) :unknown)
               (or (getf entry :governance-status) :unknown)
               (or (getf entry :approval-status) :unknown)))
     (finish-output))
    (:desktop-task-editor-pending-mutations
     (format t "desktop-task-editor-pending-mutations> session=~A mutation-count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :mutation-count) 0))
     (dolist (entry (or (getf result :mutations) '()))
       (format t "editor-pending-mutation> approval=~A pending-action=~A actor-message=~A scope=~A buffer=~A delivery=~A status=~A governance=~A approval-status=~A~%"
               (or (getf entry :approval-id) :none)
               (or (getf entry :pending-action-id) :none)
               (or (getf entry :actor-message-id) :none)
               (or (getf entry :scope-id) :none)
               (or (getf entry :buffer-id) :none)
               (or (getf entry :delivery-status) :unknown)
               (or (getf entry :status) :unknown)
               (or (getf entry :governance-status) :unknown)
               (or (getf entry :approval-status) :unknown)))
     (finish-output))
    (:desktop-task-context-chat-mailbox
     (format t "desktop-task-context-chat-mailbox> session=~A message-count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :message-count) 0))
     (when (listp (getf result :project-selection))
       (format t "  project-selection=~A primary=~A projects=~S~%"
               (or (getf (getf result :project-selection) :selection-source) :none)
               (or (getf (getf result :project-selection) :primary-project-id) :none)
               (or (getf (getf result :project-selection) :selected-project-ids) '())))
     (dolist (entry (or (getf result :messages) '()))
       (format t "context-chat-message> approval=~A pending-action=~A actor-message=~A target=~A operation=~A status=~A governance=~A approval-status=~A~%"
               (or (getf entry :approval-id) :none)
               (or (getf entry :pending-action-id) :none)
               (or (getf entry :actor-message-id) :none)
               (or (getf entry :target) :none)
               (or (getf entry :operation) :none)
               (or (getf entry :status) :unknown)
               (or (getf entry :governance-status) :unknown)
               (or (getf entry :approval-status) :unknown)))
     (finish-output))
    (:desktop-task-context-chat-context
     (format t "desktop-task-context-chat-context> session=~A selection=~A project-count=~D primary=~A~%"
             (or (getf result :session-id) :none)
             (or (getf result :selection-source) :none)
             (or (getf result :project-count) 0)
             (or (getf result :primary-project-id) :none))
     (dolist (project (or (getf result :selected-projects) '()))
       (format t "context-chat-project> id=~A title=~A~%"
               (or (getf project :id) :none)
               (or (getf project :title) :none)))
     (finish-output))
    (:desktop-task-set-context-chat-projects
     (format t "desktop-task-set-context-chat-projects> session=~A selection=~A project-count=~D primary=~A~%"
             (or (getf result :session-id) :none)
             (or (getf result :selection-source) :none)
             (or (getf result :project-count) 0)
             (or (getf result :primary-project-id) :none))
     (dolist (project (or (getf result :selected-projects) '()))
       (format t "context-chat-project> id=~A title=~A~%"
               (or (getf project :id) :none)
               (or (getf project :title) :none)))
     (finish-output))
    (:desktop-task-governance-decisions
     (format t "desktop-task-governance-decisions> session=~A decision-count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :decision-count) 0))
     (dolist (entry (or (getf result :decisions) '()))
       (format t "governance-decision> approval=~A pending-action=~A actor-message=~A target=~A operation=~A delivery=~A status=~A governance=~A approval-status=~A~%"
               (or (getf entry :approval-id) :none)
               (or (getf entry :pending-action-id) :none)
               (or (getf entry :actor-message-id) :none)
               (or (getf entry :target) :none)
               (or (getf entry :operation) :none)
               (or (getf entry :delivery-status) :unknown)
               (or (getf entry :status) :unknown)
               (or (getf entry :governance-status) :unknown)
               (or (getf entry :approval-status) :unknown)))
     (finish-output))
    (:desktop-task-runtime-outbox
     (format t "desktop-task-runtime-outbox> session=~A reply-count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :reply-count) 0))
     (dolist (entry (or (getf result :replies) '()))
       (format t "runtime-reply> actor-message=~A form=~S package=~A delivery=~A status=~A result=~S~%"
               (or (getf entry :actor-message-id) :none)
               (getf entry :form)
               (or (getf entry :package-name) :none)
               (or (getf entry :delivery-status) :unknown)
               (or (getf entry :status) :unknown)
               (getf entry :result)))
     (finish-output))
    (:desktop-task-runtime-state
     (format t "desktop-task-runtime-state> definition-count=~D~%"
             (or (getf result :definition-count) 0))
     (dolist (entry (or (getf result :definitions) '()))
       (format t "runtime-definition> symbol=~A package=~A status=~A form=~S~%"
               (or (getf entry :qualified-symbol-name)
                   (getf entry :symbol-name)
                   :none)
               (or (getf entry :package-name) :none)
               (or (getf entry :status) :unknown)
               (getf entry :form)))
     (finish-output))
    (:desktop-task-actor-flow
     (format t "desktop-task-actor-flow> session=~A approval=~A pending-action=~A actor-message=~A~%"
             (or (getf result :session-id) :none)
             (or (getf result :approval-id) :none)
             (or (getf result :pending-action-id) :none)
             (or (getf result :actor-message-id) :none))
     (format t "  chat-mailbox=~D approval-inbox=~D governance-inbox=~D governance-decisions=~D runtime-inbox=~D runtime-outbox=~D supervision-escalations=~D runtime-definitions=~D editor-pending=~D editor-authorizations=~D~%"
             (or (getf (getf result :context-chat-mailbox) :message-count) 0)
             (or (getf (getf result :context-chat-approval-inbox) :request-count) 0)
             (or (getf (getf result :governance-inbox) :request-count) 0)
             (or (getf (getf result :governance-decisions) :decision-count) 0)
             (or (getf (getf result :runtime-inbox) :message-count) 0)
             (or (getf (getf result :runtime-outbox) :reply-count) 0)
             (or (getf (getf result :supervision-escalation-inbox) :message-count) 0)
             (or (getf (getf result :runtime-state) :definition-count) 0)
             (or (getf (getf result :editor-pending-mutations) :mutation-count) 0)
             (or (getf (getf result :editor-authorizations) :authorization-count) 0))
     (finish-output))
    (:desktop-task-actor-system-panel
     (format t "desktop-task-actor-system-panel> root=~A session=~A actors=~D hierarchy-edges=~D workflow-edges=~D supervision-incidents=~D supervision-escalations=~D~%"
             (or (getf result :root-actor-id) :none)
             (or (getf result :session-id) :none)
             (or (getf result :actor-count) 0)
             (or (getf result :hierarchy-edge-count) 0)
             (or (getf result :workflow-edge-count) 0)
             (or (getf (getf result :supervision-incidents) :incident-count) 0)
             (or (getf (getf result :supervision-escalation-inbox) :message-count) 0))
     (dolist (actor (or (getf result :actors) '()))
       (format t "actor-system-panel-actor> id=~A role=~A parent=~A allocation=~A inbox-depth=~A outbox-depth=~A open-incidents=~A~%"
               (or (getf actor :id) :none)
               (or (getf actor :role) :none)
               (or (getf actor :parent-actor-id) :none)
               (or (getf (getf actor :allocation-strategy) :type) :unknown)
               (or (getf (getf actor :metrics) :inbox-depth) 0)
               (or (getf (getf actor :metrics) :outbox-depth) 0)
               (or (getf (getf actor :metrics) :open-supervision-incident-count) 0)))
     (finish-output))
    (:desktop-task-supervision-incidents
     (format t "desktop-task-supervision-incidents> session=~A incident-count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :incident-count) 0))
     (dolist (incident (or (getf result :incidents) '()))
       (format t "supervision-incident> id=~A actor=~A parent=~A mailbox=~A mailbox-entry=~A action=~A recommended=~A state-class=~A open=~A~%"
               (or (getf incident :incident-id) :none)
               (or (getf incident :actor-id) :none)
               (or (getf incident :parent-actor-id) :none)
               (or (getf incident :mailbox) :none)
               (or (getf incident :mailbox-entry-id) :none)
               (or (getf incident :supervision-action) :none)
               (or (getf incident :recommended-supervision-action) :none)
               (or (getf incident :workflow-state-class) :none)
               (not (null (getf incident :open-p)))))
     (finish-output))
    (:desktop-task-supervision-escalation-inbox
     (format t "desktop-task-supervision-escalation-inbox> session=~A parent=~A message-count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :parent-actor-id) :none)
             (or (getf result :message-count) 0))
     (dolist (entry (or (getf result :messages) '()))
       (format t "supervision-escalation> entry=~A actor=~A parent=~A failed-entry=~A request=~A target=~A operation=~A delivery=~A~%"
               (or (getf entry :mailbox-entry-id) :none)
               (or (getf entry :actor-id) :none)
               (or (getf entry :escalation-target) :none)
               (or (getf entry :failed-mailbox-entry-id) :none)
               (or (getf entry :request-id) :none)
               (or (getf entry :target) :none)
               (or (getf entry :operation) :none)
               (or (getf entry :delivery-status) :unknown)))
     (finish-output))
    (:desktop-task-ack-supervision-escalation
     (format t "desktop-task-ack-supervision-escalation> entry=~A session=~A delivery=~A~%"
             (or (getf result :mailbox-entry-id) :none)
             (or (getf result :session-id) :none)
             (or (getf result :delivery-status) :unknown))
     (finish-output))
    (:desktop-task-apply-supervision-escalation
     (format t "desktop-task-apply-supervision-escalation> failed-entry=~A action=~A incident=~A escalation-entry=~A~%"
             (or (getf result :failed-mailbox-entry-id) :none)
             (or (getf result :action) :none)
             (or (getf (getf result :incident) :incident-id) :none)
             (or (getf (getf result :mailbox-entry) :mailbox-entry-id) :none))
     (finish-output))
    (:desktop-task-process-supervision-escalation
     (format t "desktop-task-process-supervision-escalation> selected-entry=~A parent=~A action=~A incident=~A~%"
             (or (getf result :selected-mailbox-entry-id) :none)
             (or (getf result :selected-parent-actor-id) :none)
             (or (getf result :action) :none)
             (or (getf (getf result :incident) :incident-id) :none))
     (finish-output))
    (:desktop-task-fail-mailbox-entry
     (format t "desktop-task-fail-mailbox-entry> mailbox=~A mailbox-entry=~A incident=~A action=~A delivery=~A~%"
             (or (getf result :mailbox) :none)
             (or (getf (getf result :mailbox-entry) :mailbox-entry-id) :none)
             (or (getf (getf result :incident) :incident-id) :none)
             (or (getf (getf result :incident) :supervision-action) :none)
             (or (getf (getf result :mailbox-entry) :delivery-status) :unknown))
     (finish-output))
    (:desktop-task-apply-supervision-action
     (format t "desktop-task-apply-supervision-action> incident=~A requested=~A action=~A mailbox=~A mailbox-entry=~A delivery=~A incident-status=~A~%"
             (or (getf (getf result :incident) :incident-id) :none)
             (or (getf result :requested-action) :none)
             (or (getf result :action) :none)
             (or (getf result :mailbox) :none)
             (or (getf (getf result :mailbox-entry) :mailbox-entry-id) :none)
             (or (getf (getf result :mailbox-entry) :delivery-status) :unknown)
             (or (getf (getf result :incident) :status) :unknown))
     (finish-output))
    (:desktop-task-context-chat-approval-inbox
     (format t "desktop-task-context-chat-approval-inbox> session=~A request-count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :request-count) 0))
     (dolist (entry (or (getf result :requests) '()))
       (format t "context-chat-approval> approval=~A pending-action=~A actor-message=~A target=~A operation=~A status=~A governance=~A approval-status=~A~%"
               (or (getf entry :approval-id) :none)
               (or (getf entry :pending-action-id) :none)
               (or (getf entry :actor-message-id) :none)
               (or (getf entry :target) :none)
               (or (getf entry :operation) :none)
               (or (getf entry :status) :unknown)
               (or (getf entry :governance-status) :unknown)
               (or (getf entry :approval-status) :unknown)))
     (finish-output))
    (:desktop-task-ack-context-chat-approval
     (format t "desktop-task-ack-context-chat-approval> approval=~A mailbox-entry=~A session=~A delivery=~A~%"
             (or (getf result :approval-id) :none)
             (or (getf result :mailbox-entry-id) :none)
             (or (getf result :session-id) :none)
             (or (getf result :delivery-status) :unknown))
     (finish-output))
    (:desktop-task-editor-authorizations
     (format t "desktop-task-editor-authorizations> session=~A authorization-count=~D~%"
             (or (getf result :session-id) :none)
             (or (getf result :authorization-count) 0))
     (dolist (entry (or (getf result :authorizations) '()))
       (format t "editor-authorization> approval=~A pending-action=~A actor-message=~A scope=~A buffer=~A status=~A governance=~A approval-status=~A~%"
               (or (getf entry :approval-id) :none)
               (or (getf entry :pending-action-id) :none)
               (or (getf entry :actor-message-id) :none)
               (or (getf entry :scope-id) :none)
               (or (getf entry :buffer-id) :none)
               (or (getf entry :status) :unknown)
               (or (getf entry :governance-status) :unknown)
               (or (getf entry :approval-status) :unknown)))
     (finish-output))
    (:desktop-task-consume-editor-authorization
     (format t "desktop-task-consume-editor-authorization> pending-action=~A mailbox-entry=~A session=~A delivery=~A~%"
             (or (getf result :pending-action-id) :none)
             (or (getf result :mailbox-entry-id) :none)
             (or (getf result :session-id) :none)
             (or (getf result :delivery-status) :unknown))
     (finish-output))
    (:desktop-task-apply-editor-authorization
     (format t "desktop-task-apply-editor-authorization> pending-action=~A session=~A approval-ids=~S~%"
             (or (getf result :pending-action-id) :none)
             (or (getf result :session-id) :none)
             (or (getf result :approval-ids) '()))
     (when (getf result :summary)
       (format t "assistant> ~A~%" (getf result :summary)))
     (finish-output))
    (:desktop-task-approve-approval
     (format t "desktop-task-approve-approval> session=~A approval-ids=~S actor-message=~A turn=~A~%"
             (or (getf result :session-id) :none)
             (or (getf result :approval-ids) '())
             (or (getf result :actor-message-id) :none)
             (or (getf result :turn-id) :none))
     (when (getf result :summary)
       (format t "assistant> ~A~%" (getf result :summary)))
     (finish-output))
    (:desktop-task-mcp-servers
     (format t "desktop-task-mcp-servers> count=~D~%" (length (or result '())))
     (dolist (entry (or result '()))
       (format t "desktop-task-mcp-server> id=~A name=~A transport=~A enabled=~A discoverable=~A health=~A operations=~A~%"
               (or (getf entry :id) :none)
               (or (getf entry :name) :none)
               (or (getf entry :transport) :unknown)
               (if (getf entry :enabled-p) :yes :no)
               (if (getf entry :discoverable-p) :yes :no)
               (or (getf entry :health-status) :unknown)
               (or (getf entry :operation-count) 0)))
     (finish-output))
    (:desktop-task-mcp-server
     (format t "desktop-task-mcp-server> id=~A name=~A transport=~A enabled=~A discoverable=~A health=~A endpoint=~A command=~A operations=~A~%"
             (or (getf result :id) :none)
             (or (getf result :name) :none)
             (or (getf result :transport) :unknown)
             (if (getf result :enabled-p) :yes :no)
             (if (getf result :discoverable-p) :yes :no)
             (or (getf result :health-status) :unknown)
             (or (getf result :endpoint) :none)
             (or (getf result :command) :none)
             (or (getf result :operation-count) 0))
     (when (getf result :arguments)
       (format t "desktop-task-mcp-server-arguments> ~S~%" (getf result :arguments)))
     (when (getf result :capabilities)
       (format t "desktop-task-mcp-server-capabilities> ~S~%" (getf result :capabilities)))
     (finish-output))
    (:desktop-task-configure-mcp-server
     (format t "desktop-task-configure-mcp-server> id=~A name=~A transport=~A enabled=~A discoverable=~A~%"
             (or (getf result :id) :none)
             (or (getf result :name) :none)
             (or (getf result :transport) :unknown)
             (if (getf result :enabled-p) :yes :no)
             (if (getf result :discoverable-p) :yes :no))
     (finish-output))
    (:desktop-task-remove-mcp-server
     (format t "desktop-task-remove-mcp-server> id=~A removed=~A~%"
             (or (getf result :id) :none)
             (if (getf result :removed-p) :yes :no))
     (finish-output))
    (:desktop-panel
     (let ((desktop-model (getf result :desktop-model)))
       (format t "desktop-panel> active=~A focus=~A~%"
               (or (getf result :active-panel) :none)
               (or (getf desktop-model :focus-object-id) :none))
       (finish-output)))
    (:desktop-select
     (let ((selection (getf result :selection))
           (desktop-model (getf result :desktop-model)))
       (format t "desktop-select> panel=~A focus=~A active=~A~%"
               (or (getf result :panel-id) :none)
               (or (getf desktop-model :focus-object-id)
                   (getf selection :focus-object-id)
                   :none)
               (or (getf desktop-model :active-panel) :none))
       (when (getf selection :selected-index)
         (format t "desktop-select/index> ~A~%" (getf selection :selected-index)))
       (when (getf selection :selected-title)
         (format t "desktop-select/title> ~A~%" (getf selection :selected-title)))
       (finish-output)))
    (:desktop-restore
     (let ((desktop-model (getf result :desktop-model))
           (restore-result (getf result :result)))
       (format t "desktop-restore> panel=~A active=~A focus=~A~%"
               (or (getf result :panel-id) :none)
               (or (getf desktop-model :active-panel) :none)
               (or (getf desktop-model :focus-object-id) :none))
       (when (getf restore-result :panel-id)
         (format t "desktop-restore/result> panel=~A~%" (getf restore-result :panel-id)))
       (finish-output)))
    (:desktop-action
     (let ((action (getf result :action))
           (desktop-model (getf result :desktop-model))
           (action-result (getf result :result)))
       (format t "desktop-action> kind=~A panel=~A active=~A focus=~A~%"
               (or (getf action :action-kind) :none)
               (or (getf action :panel-id) :none)
               (or (getf desktop-model :active-panel) :none)
               (or (getf desktop-model :focus-object-id) :none))
       (when (getf action :action-id)
         (format t "desktop-action/id> ~A~%" (getf action :action-id)))
       (when (getf action-result :open-via)
         (format t "desktop-action/open> via=~A~%" (getf action-result :open-via)))
       (when (getf action-result :panel-id)
         (format t "desktop-action/restore> panel=~A~%" (getf action-result :panel-id)))
       (finish-output)))
    (:surface-list
     (format t "surface-list> count=~D focus=~A index=~A~%"
             (or (getf result :count) 0)
             (or (getf result :focus-object-id) :none)
             (or (getf result :focus-index) :none))
     (when (getf result :top-surface)
       (format t "surface-top> ~A status=~A exec=~A~%"
               (or (getf (getf result :top-surface) :surface-kind) :none)
               (or (getf (getf result :top-surface) :status) :unknown)
               (or (getf (getf result :top-surface) :execution-id) :none)))
     (finish-output))
    (:surface-select
     (format t "surface-select> index=~A focus=~A~%"
             (or (getf result :selected-index) :none)
             (or (getf result :focus-object-id) :none))
     (when (getf result :selected-surface)
       (format t "surface-selected> ~A status=~A exec=~A~%"
               (or (getf (getf result :selected-surface) :surface-kind) :none)
               (or (getf (getf result :selected-surface) :status) :unknown)
               (or (getf (getf result :selected-surface) :execution-id) :none)))
     (finish-output))
    (:surface-step
     (format t "surface-step> direction=~A index=~A focus=~A~%"
             (or (getf result :direction) :none)
             (or (getf result :selected-index) :none)
             (or (getf result :focus-object-id) :none))
     (when (getf result :selected-surface)
       (format t "surface-selected> ~A status=~A exec=~A~%"
               (or (getf (getf result :selected-surface) :surface-kind) :none)
               (or (getf (getf result :selected-surface) :status) :unknown)
               (or (getf (getf result :selected-surface) :execution-id) :none)))
     (finish-output))
    (:display-list
     (format t "display-list> count=~D focus=~A index=~A~%"
             (or (getf result :count) 0)
             (or (getf result :focus-object-id) :none)
             (or (getf result :focus-index) :none))
     (dolist (entry (or (getf result :items) '()))
       (format t "display-entry> exec=~A app=~A state=~A status=~A~%"
               (or (getf entry :execution-id) :none)
               (or (getf entry :app-id) :none)
               (or (getf entry :window-state) :unknown)
               (or (getf entry :status) :unknown)))
     (finish-output))
    (:display-show
     (format t "display-show> focus=~A app=~A state=~A status=~A~%"
             (or (getf result :focus-object-id) :none)
             (or (getf (getf result :display-surface) :app-id) :none)
             (or (getf (getf result :display-surface) :window-state) :unknown)
             (or (getf (getf (getf result :lifecycle) :lifecycle) :status)
                 (getf (getf result :display-surface) :status)
                 :unknown))
     (when (getf result :inspection)
       (format t "display-inspection> ~S~%" (getf result :inspection)))
     (when (getf result :lifecycle)
       (format t "display-lifecycle> ~S~%" (getf result :lifecycle)))
     (finish-output))
    (:display-select
     (format t "display-select> index=~A focus=~A app=~A state=~A~%"
             (or (getf result :selected-index) :none)
             (or (getf result :focus-object-id) :none)
             (or (getf (getf result :display-surface) :app-id) :none)
             (or (getf (getf result :display-surface) :window-state) :unknown))
     (finish-output))
    (:display-step
     (format t "display-step> direction=~A index=~A focus=~A app=~A state=~A~%"
             (or (getf result :direction) :none)
             (or (getf result :selected-index) :none)
             (or (getf result :focus-object-id) :none)
             (or (getf (getf result :display-surface) :app-id) :none)
             (or (getf (getf result :display-surface) :window-state) :unknown))
     (finish-output))
    (:display-control
     (format t "display-control> action=~A focus=~A app=~A state=~A~%"
             (or (getf result :action) :none)
             (or (getf result :focus-object-id) :none)
             (or (getf (getf result :display-surface) :app-id)
                 (getf (getf (getf result :result) :execution) :capability)
                 :none)
             (or (getf (getf result :display-surface) :window-state) :unknown))
     (when (getf result :result)
       (format t "display-control/result> ~S~%" (getf result :result)))
     (finish-output))
    (:open
     (format t "open> via=~A focus=~A~%"
             (or (getf result :open-via) :none)
             (or (getf result :focus-object-id) :none))
     (when (getf result :selected-index)
       (format t "open/index> ~A~%" (getf result :selected-index)))
     (when (getf result :selected-title)
       (format t "open/title> ~A~%" (getf result :selected-title)))
     (when (getf result :selected-item)
       (format t "open/item> ~S~%" (getf result :selected-item)))
     (when (getf result :inspection)
       (format t "open/object> ~A resolved=~A~%"
               (or (getf (getf result :inspection) :object-kind) :unknown)
               (or (getf (getf result :inspection) :resolved-via) :unknown)))
     (finish-output))
    (:focus-show
     (format t "focus> ~A object=~A resolved=~A~%"
             (or (getf result :focus-object-id) :none)
             (or (getf result :object-kind) :unknown)
             (or (getf result :resolved-via) :unknown))
     (finish-output))
    (:focus-set
     (format t "focus-set> ~A source=~A~%"
             (or (getf result :focus-object-id) :none)
             (or (getf result :source) :unknown))
     (finish-output))
    (:governance-queue
     (format t "governance-queue> count=~D~%"
             (or (getf result :count) 0))
     (when (getf result :top-item)
       (format t "governance-top> queue=~A surface=~A status=~A exec=~A~%"
               (or (getf (getf result :top-item) :queue-kind) :none)
               (or (getf (getf (getf result :top-item) :surface) :surface-kind) :none)
               (or (getf (getf result :top-item) :status) :unknown)
               (or (getf (getf result :top-item) :execution-id) :none)))
     (when (getf result :top-item)
       (render-shell-open-handoff "governance-open"
                                  (shell-open-command-for-governance-index 0)))
     (finish-output))
    (:governance-select
     (format t "governance-select> index=~D focus=~A~%"
             (or (getf result :selected-index) 0)
             (or (getf result :focus-object-id) :none))
     (finish-output))
    (:object-browser
     (format t "object-browser> groups=~D~%"
             (or (getf result :group-count) 0))
     (when (getf result :focus-object-id)
       (format t "object-browser-focus> ~A~%"
               (getf result :focus-object-id)))
     (when (getf result :top-group)
       (format t "object-browser-top> kind=~A count=~D~%"
               (or (getf (getf result :top-group) :object-kind) :none)
               (or (getf (getf result :top-group) :count) 0)))
     (when (getf result :top-group)
       (render-shell-open-handoff "object-browser-open"
                                  (shell-open-command-for-object-browser-group
                                   (getf result :top-group))))
     (finish-output))
    (:object-browser-select
     (format t "object-browser-select> kind=~A index=~D focus=~A title=~A~%"
             (or (getf result :object-kind) :none)
             (or (getf result :selected-index) 0)
             (or (getf result :focus-object-id) :none)
             (or (getf result :selected-title) :none))
     (finish-output))
    (:inspector-show
     (format t "inspector> focus=~A object=~A resolved=~A~%"
             (or (getf result :focus-object-id) :none)
             (or (getf result :object-kind) :unknown)
             (or (getf result :resolved-via) :unknown))
     (when (getf result :summary)
       (format t "inspector-summary> status=~A capability=~A history=~A app=~A actions=~S~%"
               (or (getf (getf result :summary) :status) :unknown)
               (or (getf (getf result :summary) :capability) :none)
               (or (getf (getf result :summary) :history-count) 0)
               (or (getf (getf result :summary) :app-id) :none)
               (or (getf (getf result :summary) :supported-actions) '())))
     (when (getf result :recommended-action)
       (format t "inspector-next-action> label=~A kind=~A command=~A action-id=~A~%"
               (or (getf (getf result :recommended-action) :label) :none)
               (or (getf (getf result :recommended-action) :action-kind) :none)
               (or (getf (getf result :recommended-action) :command) :none)
               (or (getf (getf result :recommended-action) :action-id) :none)))
     (finish-output))
    ((:ask :say)
     (if (getf result :enqueued-p)
         (format t "assistant-task> ~S~%" (getf result :queued-task))
         (let ((response (getf result :response))
               (staged-count (getf result :staged-action-count))
               (provider-route (getf result :provider-route)))
           (when provider-route
             (format t "provider-route> mode=~A reason=~A profile=~A provider=~A model=~A~%"
                     (or (getf provider-route :routing-mode) :none)
                     (or (getf provider-route :reason) :none)
                     (or (getf provider-route :selected-profile-name) :none)
                     (or (getf provider-route :selected-provider) :none)
                     (or (getf provider-route :selected-model) :none))
             (let ((candidates (getf provider-route :candidate-rankings)))
               (when candidates
                 (format t "provider-route-candidates> ~S~%" candidates))))
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
         (format t "turn-summary> runtime-ops=~D runtime-artifacts=~D incidents=~D weakly-grounded=~D deferred-weakly-grounded=~D work-item=~A work-status=~A workflow=~A~%"
                 (or (getf summary :runtime-operation-count) 0)
                 (or (getf summary :runtime-artifact-count) 0)
                 (or (getf summary :incident-count) 0)
                 (or (getf summary :weakly-grounded-operation-count) 0)
                 (or (getf summary :deferred-weakly-grounded-operation-count) 0)
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
     (let ((surface (getf result :execution-surface)))
       (when surface
         (format t "turn-surface> ~A status=~A exec=~A~%"
                 (or (getf surface :surface-kind) :none)
                 (or (getf surface :status) :unknown)
                 (or (getf surface :execution-id) :none))))
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
     (let ((provider-profile (getf result :provider-profile)))
       (when provider-profile
         (format t "provider> active=~A provider=~A model=~A profiles=~D~%"
                 (or (getf provider-profile :active-profile-name) :none)
                 (or (getf (getf provider-profile :active-profile) :provider) :none)
                 (or (getf (getf provider-profile :active-profile) :model) :none)
                 (or (getf provider-profile :profile-count) 0))))
     (format t "operator-posture> ~S~%" (getf result :operator-posture))
     (let ((surfaces (getf result :execution-surfaces)))
       (when surfaces
         (format t "environment-surfaces> count=~D~%"
                 (or (getf surfaces :count) 0))
         (let ((top-surface (getf surfaces :top-surface)))
           (when top-surface
             (format t "environment-top-surface> ~A status=~A exec=~A~%"
                     (or (getf top-surface :surface-kind) :none)
                     (or (getf top-surface :status) :unknown)
                     (or (getf top-surface :execution-id) :none))
             (render-shell-open-handoff "environment-open"
                                        (shell-open-command-for-surface top-surface))))))
     (let ((blocked-surfaces (getf result :blocked-work-surfaces)))
       (when blocked-surfaces
         (format t "blocked-work-surfaces> count=~D~%"
                 (or (getf blocked-surfaces :count) 0))
         (let ((top-surface (getf blocked-surfaces :top-surface)))
           (when top-surface
             (format t "blocked-top-surface> ~A status=~A exec=~A~%"
                     (or (getf top-surface :surface-kind) :none)
                     (or (getf top-surface :status) :unknown)
                     (or (getf top-surface :execution-id) :none))
             (render-shell-open-handoff "blocked-open"
                                        (shell-open-command-for-surface top-surface))))))
     (let ((approval-surfaces (getf result :approval-surfaces)))
       (when approval-surfaces
         (format t "approval-surfaces> count=~D~%"
                 (or (getf approval-surfaces :count) 0))
         (let ((top-surface (getf approval-surfaces :top-surface)))
           (when top-surface
             (format t "approval-top-surface> ~A status=~A exec=~A~%"
                     (or (getf top-surface :surface-kind) :none)
                     (or (getf top-surface :status) :unknown)
                     (or (getf top-surface :execution-id) :none))
             (render-shell-open-handoff "approval-open"
                                        (shell-open-command-for-surface top-surface))))))
     (finish-output))
    ((:provider-show :provider-list :provider-configure :provider-use :provider-routing)
     (format t "provider> active=~A profiles=~D~%"
             (or (getf result :active-profile-name) :none)
             (or (getf result :profile-count) 0))
     (format t "provider-routing> mode=~A~%"
             (or (getf result :routing-mode) :auto))
     (let ((active-profile (getf result :active-profile)))
       (when active-profile
         (format t "provider-active> name=~A provider=~A model=~A fast-model=~A api-base=~A intents=~S latency=~A review=~A execution=~A locality=~A~%"
                 (or (getf active-profile :name) :none)
                 (or (getf active-profile :provider) :none)
                 (or (getf active-profile :model) :none)
                 (or (getf active-profile :fast-model) :none)
                 (or (getf active-profile :api-base) :none)
                 (or (getf active-profile :intents) '())
                 (or (getf active-profile :latency-tier) :balanced)
                 (or (getf active-profile :review-bias) :neutral)
                 (or (getf active-profile :execution-bias) :balanced)
                 (or (getf active-profile :locality) :network))))
     (dolist (profile (or (getf result :profiles) '()))
       (format t "provider-profile> ~A provider=~A model=~A intents=~S latency=~A review=~A execution=~A locality=~A~%"
               (or (getf profile :name) :none)
               (or (getf profile :provider) :none)
               (or (getf profile :model) :none)
               (or (getf profile :intents) '())
               (or (getf profile :latency-tier) :balanced)
               (or (getf profile :review-bias) :neutral)
               (or (getf profile :execution-bias) :balanced)
               (or (getf profile :locality) :network)))
     (let ((last-route (getf result :last-route)))
       (when last-route
         (format t "provider-last-route> mode=~A reason=~A profile=~A provider=~A model=~A~%"
                 (or (getf last-route :routing-mode) :none)
                 (or (getf last-route :reason) :none)
                 (or (getf last-route :selected-profile-name) :none)
                 (or (getf last-route :selected-provider) :none)
                 (or (getf last-route :selected-model) :none))))
     (finish-output))
    (:provider-route
     (format t "provider-route> mode=~A~%"
             (or (getf result :routing-mode) :auto))
     (let ((last-route (getf result :last-route)))
       (if last-route
           (progn
             (format t "provider-route-last> reason=~A profile=~A provider=~A model=~A~%"
                     (or (getf last-route :reason) :none)
                     (or (getf last-route :selected-profile-name) :none)
                     (or (getf last-route :selected-provider) :none)
                     (or (getf last-route :selected-model) :none))
             (format t "provider-route-candidates> ~S~%"
                     (or (getf last-route :candidate-rankings) '())))
           (format t "provider-route-last> :none~%")))
     (finish-output))
    (:platform-manifest
     (format t "platform-manifest> version=~A package-format=~A capabilities=~D policies=~D workflows=~D sdk-commands=~D compatibility-kinds=~D~%"
             (or (getf result :manifest-version) :none)
             (or (getf result :package-format) :none)
             (or (getf result :capability-count) 0)
             (or (getf result :policy-count) 0)
             (or (getf result :workflow-count) 0)
             (or (getf result :sdk-command-count) 0)
             (or (getf result :compatibility-kind-count) 0))
     (dolist (entry (or (getf result :capabilities) '()))
       (format t "platform-capability> ~A policy=~A risk=~A compatibility=~A isolation=~A~%"
               (or (getf entry :capability-id) :none)
               (or (getf entry :policy-id) :none)
               (or (getf entry :risk-level) :none)
               (or (getf entry :compatibility-kind) :none)
               (or (getf entry :isolation-profile) :none)))
     (dolist (entry (or (getf result :workflows) '()))
       (format t "platform-workflow> ~A surface=~A controls=~S~%"
               (or (getf entry :workflow-id) :none)
               (or (getf entry :surface-kind) :none)
               (or (getf entry :control-actions) '())))
     (finish-output))
    (:platform-package
     (format t "platform-package> id=~A version=~A output=~A capabilities=~D workflows=~D sdk-commands=~D compatibility-kinds=~D~%"
             (or (getf result :package-id) :none)
             (or (getf result :package-version) :none)
             (or (getf result :output-path) :none)
             (or (getf result :capability-count) 0)
             (or (getf result :workflow-count) 0)
             (or (getf result :sdk-command-count) 0)
             (or (getf result :compatibility-kind-count) 0))
     (finish-output))
    (:platform-show-package
     (format t "platform-package-detail> id=~A version=~A path=~A valid=~A update=~A capabilities=~D workflows=~D sdk-commands=~D~%"
             (or (getf result :package-id) :none)
             (or (getf result :package-version) :none)
             (or (getf result :path) :none)
             (if (getf result :valid-p) :yes :no)
             (or (getf result :update-posture) :none)
             (or (getf result :capability-count) 0)
             (or (getf result :workflow-count) 0)
             (or (getf result :sdk-command-count) 0))
     (when (getf result :validation-issues)
       (format t "platform-package-issues> ~S~%" (getf result :validation-issues)))
     (finish-output))
    (:platform-validate-package
     (format t "platform-package-validation> path=~A version=~A valid=~A update=~A issues=~D~%"
             (or (getf result :path) :none)
             (or (getf result :package-version) :none)
             (if (getf result :valid-p) :yes :no)
             (or (getf result :update-posture) :none)
             (length (or (getf result :validation-issues) '())))
     (when (getf result :validation-issues)
       (format t "platform-package-issues> ~S~%" (getf result :validation-issues)))
     (finish-output))
    (:platform-import-package
     (format t "platform-package-import> id=~A version=~A update=~A path=~A registry-count=~D~%"
             (or (getf (getf result :package) :package-id) :none)
             (or (getf (getf result :package) :package-version) :none)
             (or (getf (getf result :package) :update-posture) :none)
             (or (getf result :path) :none)
             (or (getf result :registry-count) 0))
     (finish-output))
    (:platform-list-packages
     (format t "platform-packages> count=~D active=~D~%"
             (or (getf result :count) 0)
             (or (getf result :active-count) 0))
     (dolist (entry (or (getf result :packages) '()))
       (format t "platform-package> id=~A version=~A title=~A active=~A capabilities=~D workflows=~D imported-at=~A~%"
               (or (getf entry :package-id) :none)
               (or (getf entry :package-version) :none)
               (or (getf entry :title) :none)
               (if (getf entry :active-p) :yes :no)
               (or (getf entry :capability-count) 0)
               (or (getf entry :workflow-count) 0)
               (or (getf entry :imported-at) :none)))
     (finish-output))
    (:platform-show-imported-package
     (format t "platform-imported-package> id=~A version=~A title=~A path=~A active=~A update=~A capabilities=~D workflows=~D sdk-commands=~D~%"
             (or (getf result :package-id) :none)
             (or (getf result :package-version) :none)
             (or (getf result :title) :none)
             (or (getf result :path) :none)
             (if (getf result :active-p) :yes :no)
             (or (getf result :update-posture) :none)
             (or (getf result :capability-count) 0)
             (or (getf result :workflow-count) 0)
             (or (getf result :sdk-command-count) 0))
     (finish-output))
    (:platform-activate-package
     (format t "platform-package-activate> id=~A version=~A active=~A active-count=~D~%"
             (or (getf (getf result :package) :package-id) :none)
             (or (getf (getf result :package) :package-version) :none)
             (if (getf (getf result :package) :active-p) :yes :no)
             (or (getf result :active-count) 0))
     (finish-output))
    (:platform-deactivate-package
     (format t "platform-package-deactivate> id=~A version=~A active=~A active-count=~D~%"
             (or (getf (getf result :package) :package-id) :none)
             (or (getf (getf result :package) :package-version) :none)
             (if (getf (getf result :package) :active-p) :yes :no)
             (or (getf result :active-count) 0))
     (finish-output))
    (:platform-active-packages
     (format t "platform-active-packages> count=~D~%"
             (or (getf result :count) 0))
     (dolist (entry (or (getf result :packages) '()))
       (format t "platform-active-package> id=~A version=~A title=~A activated-at=~A~%"
               (or (getf entry :package-id) :none)
               (or (getf entry :package-version) :none)
               (or (getf entry :title) :none)
               (or (getf entry :activated-at) :none)))
     (finish-output))
    (:platform-profile
     (format t "platform-profile> active=~D capabilities=~D workflows=~D sdk-commands=~D compatibility-kinds=~D~%"
             (or (getf result :count) 0)
             (or (getf result :capability-count) 0)
             (or (getf result :workflow-count) 0)
             (or (getf result :sdk-command-count) 0)
             (or (getf result :compatibility-kind-count) 0))
     (finish-output))
    (:platform-install-package
     (format t "platform-package-install> id=~A version=~A active=~A active-count=~D registry-count=~D~%"
             (or (getf (getf result :package) :package-id) :none)
             (or (getf (getf result :package) :package-version) :none)
             (if (getf (getf result :package) :active-p) :yes :no)
             (or (getf result :active-count) 0)
             (or (getf result :registry-count) 0))
     (finish-output))
    (:platform-simulate-package
     (format t "platform-package-simulate> id=~A version=~A path=~A valid=~A update=~A replace-existing=~A~%"
             (or (getf result :package-id) :none)
             (or (getf result :package-version) :none)
             (or (getf result :path) :none)
             (if (getf result :valid-p) :yes :no)
             (or (getf result :update-posture) :none)
             (if (getf result :would-replace-existing-p) :yes :no))
     (when (getf result :simulated-profile)
       (format t "platform-simulated-profile> active=~D capabilities=~D workflows=~D sdk-commands=~D compatibility-kinds=~D~%"
               (or (getf (getf result :simulated-profile) :count) 0)
               (or (getf (getf result :simulated-profile) :capability-count) 0)
               (or (getf (getf result :simulated-profile) :workflow-count) 0)
               (or (getf (getf result :simulated-profile) :sdk-command-count) 0)
               (or (getf (getf result :simulated-profile) :compatibility-kind-count) 0)))
     (when (getf result :validation-issues)
       (format t "platform-package-issues> ~S~%" (getf result :validation-issues)))
     (finish-output))
    (:platform-history
     (format t "platform-package-history> count=~D limit=~D package=~A~%"
             (or (getf result :count) 0)
             (or (getf result :limit) 0)
             (or (getf result :package-id) :all))
     (dolist (entry (or (getf result :entries) '()))
       (format t "platform-package-history-entry> action=~A id=~A version=~A active=~A update=~A deprecated=~A manual-recovery=~A untrusted=~A timestamp=~A~%"
               (or (getf entry :action) :none)
               (or (getf entry :package-id) :none)
               (or (getf entry :package-version) :none)
               (if (getf entry :active-p) :yes :no)
               (or (getf entry :update-posture) :none)
               (if (getf entry :deprecated-p) :yes :no)
               (if (getf entry :manual-recovery-p) :yes :no)
               (if (getf entry :untrusted-p) :yes :no)
               (or (getf entry :timestamp) :none)))
     (finish-output))
    (:platform-audit
     (format t "platform-audit> count=~D active=~D history=~D overrides=~D attention=~D untrusted=~D deprecated=~D manual-recovery=~D manual-update=~D~%"
             (or (getf result :count) 0)
             (or (getf result :active-count) 0)
             (or (getf result :history-count) 0)
             (or (getf result :override-count) 0)
             (or (getf result :attention-count) 0)
             (or (getf result :untrusted-count) 0)
             (or (getf result :deprecated-count) 0)
             (or (getf result :manual-recovery-count) 0)
             (or (getf result :manual-update-count) 0))
     (dolist (entry (or (getf result :packages) '()))
       (format t "platform-audit-package> id=~A version=~A active=~A trusted=~A release=~A update=~A overrides=~A attention=~A latest=~A~%"
               (or (getf entry :package-id) :none)
               (or (getf entry :package-version) :none)
               (if (getf entry :active-p) :yes :no)
               (if (getf entry :provenance-trusted-p) :yes :no)
               (or (getf entry :release-status) :none)
               (or (getf entry :update-channel) :none)
               (or (getf entry :override-count) 0)
               (if (getf entry :attention-required-p) :yes :no)
               (or (getf entry :latest-action) :none)))
     (finish-output))
    (:platform-harness
     (format t "platform-harnesses> count=~D available=~D~%"
             (or (getf result :count) 0)
             (or (getf result :available-count) 0))
     (dolist (entry (or (getf result :harnesses) '()))
       (format t "platform-harness> id=~A available=~A report=~A blocked=~A~%"
               (or (getf entry :harness-id) :none)
               (if (getf entry :available-p) :yes :no)
               (or (getf entry :report-shape) :none)
               (or (getf entry :blocked-reason) :none)))
     (finish-output))
    (:platform-run-harness
     (format t "platform-harness-run> id=~A available=~A report=~A~%"
             (or (getf (getf result :harness) :harness-id) :none)
             (if (getf (getf result :harness) :available-p) :yes :no)
             (or (getf (getf result :harness) :report-shape) :none))
     (when (getf result :report)
       (format t "platform-harness-report> implemented=~A passed=~A score=~A~%"
               (or (getf (getf result :report) :implemented-family-count) :none)
               (or (getf (getf result :report) :passed-family-count) :none)
               (or (getf (getf result :report) :implemented-score) :none)))
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
     (when (getf result :execution-surface)
       (format t "incident-surface> ~A status=~A exec=~A~%"
               (or (getf (getf result :execution-surface) :surface-kind) :none)
               (or (getf (getf result :execution-surface) :status) :unknown)
               (or (getf (getf result :execution-surface) :execution-id) :none)))
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
    (:describe-work-item
     (format t "work-item> ~A status=~A goal=~A~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :status) :unknown)
             (or (getf result :goal) "<none>"))
     (when (getf result :execution-surface)
       (format t "work-item-surface> ~A status=~A exec=~A~%"
               (or (getf (getf result :execution-surface) :surface-kind) :none)
               (or (getf (getf result :execution-surface) :status) :unknown)
               (or (getf (getf result :execution-surface) :execution-id) :none)))
     (finish-output))
    (:describe-work-item-plan
     (format t "work-item-plan> ~A status=~A next=~A~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :status) :unknown)
             (or (getf result :next-action) :none))
     (when (getf result :execution-surface)
       (format t "work-item-plan-surface> ~A status=~A exec=~A~%"
               (or (getf (getf result :execution-surface) :surface-kind) :none)
               (or (getf (getf result :execution-surface) :status) :unknown)
               (or (getf (getf result :execution-surface) :execution-id) :none)))
     (finish-output))
    (:describe-workflow-record
     (format t "workflow-record> ~A status=~A goal=~A~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :status) :unknown)
             (or (getf result :goal) "<none>"))
     (when (getf result :execution-surface)
       (format t "workflow-surface> ~A status=~A exec=~A~%"
               (or (getf (getf result :execution-surface) :surface-kind) :none)
               (or (getf (getf result :execution-surface) :status) :unknown)
               (or (getf (getf result :execution-surface) :execution-id) :none)))
     (finish-output))
    (:describe-plan
     (format t "plan> ~A status=~A goal=~A steps=~D workflow=~A active=~A~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :status) :unknown)
             (or (getf result :goal) "<none>")
             (length (or (getf result :steps) '()))
             (or (getf result :workflow-record-id) :none)
             (or (getf result :active-plan-p) nil))
     (finish-output))
    (:describe-active-plan
     (format t "active-plan> ~A status=~A goal=~A steps=~D workflow=~A~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :status) :unknown)
             (or (getf result :goal) "<none>")
             (length (or (getf result :steps) '()))
             (or (getf result :workflow-record-id) :none))
     (finish-output))
    (:describe-plan-workflow
     (format t "plan-workflow> plan=~A workflow=~A status=~A~%"
             (or (getf result :plan-id) :none)
             (or (getf result :workflow-record-id) :none)
             (or (getf (getf result :workflow-record) :status) :unknown))
     (finish-output))
    (:describe-orchestration-focus
     (format t "orchestration-focus> resolved-by=~A plan=~A workflow=~A work-item=~A status=~A active=~A~%"
             (or (getf result :resolved-by) :none)
             (or (getf result :id) "<unknown>")
             (or (getf result :resolved-workflow-record-id)
                 (getf result :workflow-record-id)
                 :none)
             (or (getf result :resolved-work-item-id) :none)
             (or (getf result :status) :unknown)
             (or (getf result :active-plan-p) nil))
     (when (getf result :primary-command)
       (format t "orchestration-focus-command> primary=~A kind=~A label=~A available=~D~%"
               (or (getf result :primary-command-operator)
                   (getf (getf result :primary-command) :operator)
                   :none)
               (or (getf result :primary-command-kind)
                   (getf (getf result :primary-command) :kind)
                   :none)
               (or (getf result :primary-command-label)
                   (getf (getf result :primary-command) :label)
                   :none)
               (or (getf result :available-command-count)
                   (length (or (getf result :available-commands) '())))))
     (when (getf result :available-command-summaries)
       (format t "orchestration-focus-actions> ~{~A~^, ~}~%"
               (mapcar (lambda (command)
                         (or (getf command :label)
                             (getf command :operator)
                             "<unknown>"))
                       (getf result :available-command-summaries))))
     (when (getf result :latest-step-summary)
       (format t "orchestration-focus-step> id=~A verification=~A capability=~A target=~A operation=~A~%"
               (or (getf (getf result :latest-step-summary) :step-id) :none)
               (or (getf (getf result :latest-step-summary) :verification-status) :unknown)
               (or (getf (getf result :latest-step-summary) :capability) :none)
               (or (getf (getf result :latest-step-summary) :target) :none)
               (or (getf (getf result :latest-step-summary) :operation) :none)))
     (finish-output))
    (:describe-orchestration-snapshot
     (format t "orchestration> plan=~A status=~A workflow=~A workflow-status=~A active=~A~%"
             (or (getf result :id) "<unknown>")
             (or (getf result :status) :unknown)
             (or (getf (getf result :workflow-record-summary) :id)
                 (getf result :workflow-record-id)
                 :none)
             (or (getf (getf result :workflow-record-summary) :status) :unknown)
             (or (getf result :active-plan-p) nil))
     (when (getf result :primary-command)
       (format t "orchestration-command> primary=~A kind=~A label=~A available=~D~%"
               (or (getf result :primary-command-operator)
                   (getf (getf result :primary-command) :operator)
                   :none)
               (or (getf result :primary-command-kind)
                   (getf (getf result :primary-command) :kind)
                   :none)
               (or (getf result :primary-command-label)
                   (getf (getf result :primary-command) :label)
                   :none)
               (or (getf result :available-command-count)
                   (length (or (getf result :available-commands) '())))))
     (when (getf result :available-command-summaries)
       (format t "orchestration-actions> ~{~A~^, ~}~%"
               (mapcar (lambda (command)
                         (or (getf command :label)
                             (getf command :operator)
                             "<unknown>"))
                       (getf result :available-command-summaries))))
     (when (getf result :posture-summary)
       (format t "orchestration-posture> waiting-on=~A approval-required=~A approvals=~D pending-validations=~D next-action=~A~%"
               (or (getf (getf result :posture-summary) :waiting-on) :none)
               (or (getf (getf result :posture-summary) :approval-required-p) nil)
               (or (getf (getf result :posture-summary) :approval-requirement-count) 0)
               (or (getf (getf result :posture-summary) :pending-validation-count) 0)
               (or (getf (getf result :posture-summary) :next-action) :none)))
     (when (getf result :latest-step-summary)
       (format t "orchestration-step> id=~A status=~A verification=~A capability=~A target=~A operation=~A actor=~A~%"
               (or (getf (getf result :latest-step-summary) :step-id) :none)
               (or (getf (getf result :latest-step-summary) :status) :unknown)
               (or (getf (getf result :latest-step-summary) :verification-status) :unknown)
               (or (getf (getf result :latest-step-summary) :capability) :none)
               (or (getf (getf result :latest-step-summary) :target) :none)
               (or (getf (getf result :latest-step-summary) :operation) :none)
               (or (getf (getf result :latest-step-summary) :assigned-actor) :none)))
     (finish-output))
    (:describe-plan-verification
     (format t "plan-verification> plan=~A status=~A workflow=~A workflow-status=~A verified=~D failed=~D pending=~D~%"
             (or (getf result :plan-id) "<unknown>")
             (or (getf result :plan-status) :unknown)
             (or (getf result :workflow-record-id) :none)
             (or (getf result :workflow-status) :unknown)
             (or (getf result :verified-step-count) 0)
             (or (getf result :failed-step-count) 0)
             (or (getf result :pending-step-count) 0))
     (dolist (step (or (getf result :steps) '()))
       (format t "plan-step-verification> id=~A status=~A verification=~A reconciliation=~A~%"
               (or (getf step :step-id) :none)
               (or (getf step :status) :unknown)
               (or (getf step :verification-status) :unknown)
               (or (getf step :reconciliation-status) :none))
       (let ((runtime-post-state
               (getf (getf step :evidence-summary) :runtime-post-state)))
         (when runtime-post-state
           (format t "plan-step-runtime> package=~A runtime=~A fboundp=~A divergence=~A loaded=~A~%"
                   (or (getf runtime-post-state :package) :none)
                   (or (getf runtime-post-state :runtime-id) :none)
                   (or (getf runtime-post-state :fboundp) :none)
                   (or (getf runtime-post-state :divergence) :none)
                   (or (getf runtime-post-state :loaded-system-count) :none))))
       (when (getf (getf step :evidence-summary) :defined-name)
         (format t "plan-step-symbol> defined=~A reason=~A~%"
                 (or (getf (getf step :evidence-summary) :defined-name) :none)
                 (or (getf (getf step :evidence-summary) :reason) :none)))
       (when (or (getf (getf step :evidence-summary) :target)
                 (getf (getf step :evidence-summary) :operation)
                 (getf (getf step :evidence-summary) :capability))
         (format t "plan-step-workspace> target=~A operation=~A capability=~A target-observed=~A operation-observed=~A~%"
                 (or (getf (getf step :evidence-summary) :target) :none)
                 (or (getf (getf step :evidence-summary) :operation) :none)
                 (or (getf (getf step :evidence-summary) :capability) :none)
                 (or (getf (getf step :evidence-summary) :target-observed-p) nil)
                 (or (getf (getf step :evidence-summary) :operation-observed-p) nil))))
     (finish-output))
    (:review-mutation
     (format t "mutation-review> turn=~A status=~A operations=~D artifacts=~D incidents=~D~%"
             (or (getf (getf result :turn) :id) "<unknown>")
             (or (getf (getf result :turn) :status) :unknown)
             (or (getf (getf result :mutation) :operation-count) 0)
             (or (getf (getf result :mutation) :artifact-count) 0)
             (length (or (getf result :incidents) '())))
     (when (getf (getf result :turn) :execution-surface)
       (format t "mutation-turn-surface> ~A status=~A exec=~A~%"
               (or (getf (getf (getf result :turn) :execution-surface) :surface-kind) :none)
               (or (getf (getf (getf result :turn) :execution-surface) :status) :unknown)
               (or (getf (getf (getf result :turn) :execution-surface) :execution-id) :none)))
     (when (getf (getf result :governance) :work-item)
       (format t "mutation-governance> work-item=~A status=~A wait=~A weakly-grounded=~D deferred-weakly-grounded=~D~%"
               (getf (getf (getf result :governance) :work-item) :id)
               (getf (getf (getf result :governance) :work-item) :status)
               (or (getf (getf (getf result :governance) :wait) :why) :none)
               (or (getf (getf (getf result :governance) :action-assessment-summary)
                         :weakly-grounded-operation-count)
                   0)
               (or (getf (getf (getf result :governance) :action-assessment-summary)
                         :deferred-weakly-grounded-operation-count)
                   0)))
     (when (getf (getf result :governance) :work-item-surface)
       (format t "mutation-work-surface> ~A status=~A exec=~A~%"
               (or (getf (getf (getf result :governance) :work-item-surface) :surface-kind) :none)
               (or (getf (getf (getf result :governance) :work-item-surface) :status) :unknown)
               (or (getf (getf (getf result :governance) :work-item-surface) :execution-id) :none)))
     (when (getf (getf result :governance) :workflow-record-surface)
       (format t "mutation-workflow-surface> ~A status=~A exec=~A~%"
               (or (getf (getf (getf result :governance) :workflow-record-surface) :surface-kind) :none)
               (or (getf (getf (getf result :governance) :workflow-record-surface) :status) :unknown)
               (or (getf (getf (getf result :governance) :workflow-record-surface) :execution-id) :none)))
     (unless (getf (getf result :governance) :work-item)
       (let ((assessment-summary (getf (getf result :governance) :action-assessment-summary)))
         (when assessment-summary
           (format t "mutation-assessment> weakly-grounded=~D deferred-weakly-grounded=~D~%"
                   (or (getf assessment-summary :weakly-grounded-operation-count) 0)
                   (or (getf assessment-summary :deferred-weakly-grounded-operation-count) 0)))))
     (when (first (getf result :incidents))
       (let ((incident-surface (getf (first (getf result :incidents)) :execution-surface)))
         (when incident-surface
           (format t "mutation-incident-surface> ~A status=~A exec=~A~%"
                   (or (getf incident-surface :surface-kind) :none)
                   (or (getf incident-surface :status) :unknown)
                   (or (getf incident-surface :execution-id) :none)))))
     (when (getf (getf result :governance) :next-action)
       (format t "mutation-next> ~S~%" (getf (getf result :governance) :next-action)))
     (finish-output))
    (:runtime-inspect
     (format t "runtime-inspect> symbol=~A package=~A~%"
             (or (getf result :symbol) :none)
             (or (getf result :package) :none))
     (when (getf result :value-summary)
       (format t "runtime-value> kind=~A type=~A class=~A~%"
               (or (getf (getf result :value-summary) :kind) :unknown)
               (or (getf (getf result :value-summary) :type) :unknown)
               (or (getf (getf result :value-summary) :class) :unknown)))
     (when (getf result :function-summary)
       (format t "runtime-function> kind=~A methods=~A~%"
               (or (getf (getf result :function-summary) :kind) :unknown)
               (or (getf result :method-count) 0)))
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
    (:incident-condition
     (format t "incident-condition> id=~A kind=~A status=~A~%"
             (or (getf result :incident-id) :none)
             (or (getf result :kind) :unknown)
             (or (getf result :status) :unknown))
     (when (getf result :condition-summary)
       (format t "incident-condition-summary> type=~A restarts=~A~%"
               (or (getf (getf result :condition-summary) :type) :unknown)
               (or (getf (getf result :condition-summary) :restart-count) 0)))
     (finish-output))
    (:incident-restarts
     (format t "incident-restarts> id=~A count=~D~%"
             (or (getf result :incident-id) :none)
             (or (getf result :restart-count) 0))
     (finish-output))
    (:runtime-condition
     (format t "runtime-condition> incident=~A status=~A~%"
             (or (getf result :incident-id) :none)
             (or (getf result :status) :unknown))
     (when (getf result :condition-summary)
       (format t "runtime-condition-summary> type=~A restarts=~A~%"
               (or (getf (getf result :condition-summary) :type) :unknown)
               (or (getf (getf result :condition-summary) :restart-count) 0)))
     (finish-output))
    (:runtime-restarts
     (format t "runtime-restarts> incident=~A count=~D~%"
             (or (getf result :incident-id) :none)
             (or (getf result :restart-count) 0))
     (finish-output))
    (:runtime-object
     (format t "runtime-object> symbol=~A package=~A kind=~A~%"
             (or (getf result :symbol) :none)
             (or (getf result :package) :none)
             (or (getf (getf result :object-detail) :kind) :unknown))
     (finish-output))
    (:list-orchestrations
     (dolist (entry (or result '()))
       (format t "orchestration-list> plan=~A status=~A workflow=~A workflow-status=~A waiting-on=~A approval-required=~A verified=~D failed=~D pending=~D~%"
               (or (getf entry :id) :none)
               (or (getf entry :status) :unknown)
               (or (getf entry :workflow-record-id) :none)
               (or (getf entry :workflow-status) :unknown)
               (or (getf (getf entry :posture-summary) :waiting-on) :none)
               (or (getf (getf entry :posture-summary) :approval-required-p) nil)
               (or (getf (getf entry :verification-summary) :verified-step-count) 0)
               (or (getf (getf entry :verification-summary) :failed-step-count) 0)
               (or (getf (getf entry :verification-summary) :pending-step-count) 0))
       (when (getf entry :latest-step-summary)
         (format t "orchestration-list-step> step=~A status=~A verification=~A capability=~A target=~A operation=~A~%"
                 (or (getf (getf entry :latest-step-summary) :step-id) :none)
                 (or (getf (getf entry :latest-step-summary) :status) :unknown)
                 (or (getf (getf entry :latest-step-summary) :verification-status) :unknown)
                 (or (getf (getf entry :latest-step-summary) :capability) :none)
                 (or (getf (getf entry :latest-step-summary) :target) :none)
                 (or (getf (getf entry :latest-step-summary) :operation) :none))))
     (finish-output))
    (:list-orchestration-inbox
     (dolist (entry (or result '()))
       (format t "orchestration-inbox> plan=~A status=~A workflow=~A waiting-on=~A action=~A urgency=~A approval-required=~A failed=~D pending=~D~%"
               (or (getf entry :id) :none)
               (or (getf entry :status) :unknown)
               (or (getf entry :workflow-record-id) :none)
               (or (getf entry :waiting-on) :none)
               (or (getf entry :action) :inspect)
               (or (getf entry :urgency) :low)
               (or (getf entry :approval-required-p) nil)
               (or (getf entry :failed-step-count) 0)
               (or (getf entry :pending-step-count) 0))
       (when (getf entry :primary-command)
         (format t "orchestration-inbox-command> primary=~A kind=~A label=~A available=~D~%"
                 (or (getf entry :primary-command-operator)
                     (getf (getf entry :primary-command) :operator)
                     :none)
                 (or (getf entry :primary-command-kind)
                     (getf (getf entry :primary-command) :kind)
                     :none)
                 (or (getf entry :primary-command-label)
                     (getf (getf entry :primary-command) :label)
                     :none)
                 (or (getf entry :available-command-count)
                     (length (or (getf entry :available-commands) '())))))
       (when (getf entry :available-command-summaries)
         (format t "orchestration-inbox-actions> ~{~A~^, ~}~%"
                 (mapcar (lambda (command)
                           (or (getf command :label)
                               (getf command :operator)
                               "<unknown>"))
                         (getf entry :available-command-summaries))))
       (when (getf entry :next-action)
         (format t "orchestration-inbox-next> ~S~%" (getf entry :next-action)))
       (when (getf entry :latest-step-summary)
         (format t "orchestration-inbox-step> step=~A status=~A verification=~A capability=~A target=~A operation=~A~%"
                 (or (getf (getf entry :latest-step-summary) :step-id) :none)
                 (or (getf (getf entry :latest-step-summary) :status) :unknown)
                 (or (getf (getf entry :latest-step-summary) :verification-status) :unknown)
                 (or (getf (getf entry :latest-step-summary) :capability) :none)
                 (or (getf (getf entry :latest-step-summary) :target) :none)
                 (or (getf (getf entry :latest-step-summary) :operation) :none))))
     (finish-output))
    ((:thread-new :thread-list :thread-use :list-work-items :list-workflow-records :list-plans :quarantine-work-item :resume-work-item :steer-work-item-plan :list-replay-groups :list-image-reconciliations :replay-validator-task :replay-validator-set :reconcile-image-only-source :integration-rgp-artifacts :integration-rgp-approve :integration-rgp-resume)
     (format t "tasks> ~S~%" result))
    (:enqueue-task
     (format t "task> id=~A status=~A work-item=~A~%"
             (or (getf result :id) :none)
             (or (getf result :status) :unknown)
             (or (getf result :work-item-id) :none))
     (let ((surface (getf result :execution-surface)))
       (when surface
         (format t "task-surface> ~A status=~A exec=~A~%"
                 (or (getf surface :surface-kind) :none)
                 (or (getf surface :status) :unknown)
                 (or (getf surface :execution-id) :none))))
     (finish-output))
    (:list-tasks
     (format t "tasks> count=~D~%" (length (or result '())))
     (dolist (task (or result '()))
       (format t "task> id=~A status=~A work-item=~A surface=~A exec=~A~%"
               (or (getf task :id) :none)
               (or (getf task :status) :unknown)
               (or (getf task :work-item-id) :none)
               (or (getf (getf task :execution-surface) :surface-kind) :none)
               (or (getf (getf task :execution-surface) :execution-id) :none)))
     (finish-output))
    ((:describe-task :cancel-task :run-next-task)
     (format t "task> id=~A status=~A work-item=~A progress=~A~%"
             (or (getf result :id) :none)
             (or (getf result :status) :unknown)
             (or (getf result :work-item-id) :none)
             (or (getf result :progress-event-count) 0))
     (let ((surface (getf result :execution-surface)))
       (when surface
         (format t "task-surface> ~A status=~A exec=~A~%"
                 (or (getf surface :surface-kind) :none)
                 (or (getf surface :status) :unknown)
                 (or (getf surface :execution-id) :none))))
     (finish-output))
    (:monitor-task
     (format t "task-monitor> id=~A status=~A recent=~D~%"
             (or (getf result :id) :none)
             (or (getf result :status) :unknown)
             (length (or (getf result :recent-progress-events) '())))
     (let ((surface (getf result :execution-surface)))
       (when surface
         (format t "task-monitor-surface> ~A status=~A exec=~A~%"
                 (or (getf surface :surface-kind) :none)
                 (or (getf surface :status) :unknown)
                 (or (getf surface :execution-id) :none))))
     (finish-output))
    (:start-worker
     (format t "worker> id=~A running=~A~%"
             (or (getf result :id) :none)
             (or (getf result :running-p) nil))
     (let ((surface (getf result :execution-surface)))
       (when surface
         (format t "worker-surface> ~A status=~A exec=~A~%"
                 (or (getf surface :surface-kind) :none)
                 (or (getf surface :status) :unknown)
                 (or (getf surface :execution-id) :none))))
     (finish-output))
    (:list-workers
     (format t "workers> count=~D~%" (length (or result '())))
     (dolist (worker (or result '()))
       (format t "worker> id=~A running=~A surface=~A~%"
               (or (getf worker :id) :none)
               (or (getf worker :running-p) nil)
               (or (getf (getf worker :execution-surface) :surface-kind) :none)))
     (finish-output))
    ((:describe-worker :stop-worker)
     (format t "worker> id=~A running=~A~%"
             (or (getf result :id) :none)
             (or (getf result :running-p) nil))
     (let ((surface (getf result :execution-surface)))
       (when surface
         (format t "worker-surface> ~A status=~A exec=~A~%"
                 (or (getf surface :surface-kind) :none)
                 (or (getf surface :status) :unknown)
                 (or (getf surface :execution-id) :none))))
     (finish-output))
    (:request-work-item-approval
     (format t "approval-request> work-item=~A wait=~A workflow=~A~%"
             (or (getf (getf result :work-item) :id) :none)
             (or (getf (getf result :wait) :why) :none)
             (or (getf (getf result :workflow-record) :status) :none))
     (let ((surface (getf (getf result :work-item) :execution-surface)))
       (when surface
         (format t "approval-work-surface> ~A status=~A exec=~A~%"
                 (or (getf surface :surface-kind) :none)
                 (or (getf surface :status) :unknown)
                 (or (getf surface :execution-id) :none))))
     (finish-output))
    (:why-waiting
     (format t "why-waiting> why=~A waiting-on=~A~%"
             (or (getf result :why) :none)
             (or (getf result :waiting-on) :none))
     (when (getf result :next-action)
       (format t "why-waiting-next> ~S~%" (getf result :next-action)))
     (let ((surface (getf result :execution-surface)))
       (when surface
         (format t "why-waiting-surface> ~A status=~A exec=~A~%"
                 (or (getf surface :surface-kind) :none)
                 (or (getf surface :status) :unknown)
                 (or (getf surface :execution-id) :none))))
     (finish-output))
    (:integration-rgp-workspace
     (format t "rgp-workspace> node=~A attention=~D execution-surfaces=~D publication=~A business-gate=~A~%"
             (or (getf (getf result :node-mode) :employment-model) :none)
             (or (getf (getf result :attention-queue) :count) 0)
             (or (getf (getf result :execution-surfaces) :count) 0)
             (or (getf (getf result :publication-summary) :attention-class) :none)
             (or (getf (getf result :business-summary) :current-gate) :none))
     (when (getf (getf result :execution-surfaces) :top-surface)
       (format t "rgp-workspace-surface> ~S~%"
               (getf (getf result :execution-surfaces) :top-surface)))
     (finish-output))
    (:integration-rgp-approvals
     (format t "rgp-approvals> count=~D~%"
             (length (or result '())))
     (dolist (approval (or result '()))
       (format t "rgp-approval> work-item=~A wait=~A exec=~A surface=~A status=~A~%"
               (or (getf approval :id) :none)
               (or (getf approval :wait-reason) :none)
               (or (getf (getf approval :primary-execution-handle) :execution-id) :none)
               (or (getf (getf approval :execution-surface) :surface-kind) :none)
               (or (getf (getf approval :execution-surface) :status) :unknown)))
     (finish-output))
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
     (if (getf result :queued-p)
         (format t "patch-task> queued=~A job=~A record=~S~%"
                 t
                 (or (getf result :actor-execution-job-id) :none)
                 (or (getf result :task-record) '()))
         (format t "patch> ~S~%" result)))
    (:session-save
     (format t "session> ~S~%" result))
    (:session-load
     (format t "session> ~S~%" result)
     (when (getf result :workspace)
       (format t "session-workspace-focus> ~A~%"
               (or (getf (getf result :workspace) :inspector-focus-object-id) :none))))
    (:session-reset
     (format t "session> ~S~%" result)
     (when (getf result :workspace)
       (format t "session-workspace-focus> ~A~%"
               (or (getf (getf result :workspace) :inspector-focus-object-id) :none))))
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
     (when (getf result :workspace)
       (format t "environment-load-workspace-focus> ~A~%"
               (or (getf (getf result :workspace) :inspector-focus-object-id) :none)))
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
     (let ((surfaces (getf result :execution-surfaces)))
       (when surfaces
         (format t "session-surfaces> count=~D~%"
                 (or (getf surfaces :count) 0))
         (let ((top-surface (getf surfaces :top-surface)))
           (when top-surface
             (format t "session-top-surface> ~A status=~A exec=~A~%"
                     (or (getf top-surface :surface-kind) :none)
                     (or (getf top-surface :status) :unknown)
                     (or (getf top-surface :execution-id) :none))
             (render-shell-open-handoff "session-open"
                                        (shell-open-command-for-surface top-surface))))))
     (let ((blocked-surfaces (getf result :blocked-work-surfaces)))
       (when blocked-surfaces
         (format t "session-blocked-surfaces> count=~D~%"
                 (or (getf blocked-surfaces :count) 0))
         (let ((top-surface (getf blocked-surfaces :top-surface)))
           (when top-surface
             (format t "session-blocked-top-surface> ~A status=~A exec=~A~%"
                     (or (getf top-surface :surface-kind) :none)
                     (or (getf top-surface :status) :unknown)
                     (or (getf top-surface :execution-id) :none))
             (render-shell-open-handoff "session-blocked-open"
                                        (shell-open-command-for-surface top-surface))))))
     (let ((approval-surfaces (getf result :approval-surfaces)))
       (when approval-surfaces
         (format t "session-approval-surfaces> count=~D~%"
                 (or (getf approval-surfaces :count) 0))
         (let ((top-surface (getf approval-surfaces :top-surface)))
           (when top-surface
             (format t "session-approval-top-surface> ~A status=~A exec=~A~%"
                     (or (getf top-surface :surface-kind) :none)
                     (or (getf top-surface :status) :unknown)
                     (or (getf top-surface :execution-id) :none))
             (render-shell-open-handoff "session-approval-open"
                                        (shell-open-command-for-surface top-surface))))))
     (finish-output))
    (t
     (format t "=> ~S~%" result))))

(defun start-shell (provider &rest arguments)
  (let* ((session (and arguments
                       (not (keywordp (first arguments)))
                       (first arguments)))
         (options (if session
                      (rest arguments)
                      arguments))
         (default-stream-p (getf options :default-stream-p nil))
         (active-session (ensure-session session))
         (active-environment (or (session-bound-environment active-session)
                                 (bind-session-to-environment active-session (ensure-environment)))))
    (unless (environment-provider-profiles active-environment)
      (ensure-environment-provider-profile
       :environment active-environment
       :config (config-with-overrides
                (load-config)
                :provider (provider-name provider)
                :model (or (ignore-errors (slot-value provider 'model))
                           (config-model (load-config)))
                :fast-model (ignore-errors (slot-value provider 'fast-model))
                :api-base (ignore-errors (slot-value provider 'api-base)))))
    (format t "Starting Lisp-native shell with provider ~A.~%" (provider-name provider))
    (when default-stream-p
      (format t "Interactive streaming is enabled by default for ask requests.~%"))
    (print-shell-environment-orientation active-environment)
    (print-shell-workspace-startup-summary active-session active-environment)
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
                   (multiple-value-bind (result kind updated-session updated-provider)
                       (execute-command (normalize-form-command form) provider active-session)
                     (setf active-session updated-session
                           provider (or updated-provider provider)
                           *current-session* updated-session)
                     (print-shell-result result kind))
                 (error (condition)
                   (format *error-output* "error> ~A~%" condition))))))))
