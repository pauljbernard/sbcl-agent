(in-package #:sbcl-agent.system.registry)

(defstruct capability-definition
  id
  source-kind
  provider-id
  actor-role
  mutation-class
  approval-required-p
  policy-id
  input-schema
  output-schema
  backend-kind
  backend-ref
  execution-mode
  retry-policy
  scope
  metadata)

(defparameter +kernel-capability-registry+
  (list
   (make-capability-definition
    :id "runtime/eval"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :runtime
    :mutation-class :runtime-mutation
    :approval-required-p nil
    :policy-id :runtime-mutation
    :input-schema '(:form string :mutating boolean)
    :output-schema '(:value t :result-type keyword)
    :metadata '(:category :runtime))
   (make-capability-definition
    :id "runtime/reload-file"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :runtime
    :mutation-class :runtime-reload
    :approval-required-p t
    :policy-id :runtime-reload
    :input-schema '(:path string)
    :output-schema '(:status keyword)
    :metadata '(:category :runtime))
   (make-capability-definition
    :id "runtime/set-package"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :runtime
    :mutation-class :runtime-package-switch
    :approval-required-p t
    :policy-id :runtime-package-switch
    :input-schema '(:package string)
   :output-schema '(:package string)
   :metadata '(:category :runtime))
   (make-capability-definition
    :id "runtime/summary"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :runtime
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:runtime-id string)
    :metadata '(:category :runtime))
   (make-capability-definition
    :id "runtime/telemetry"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :runtime
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:runtime-id string :processes list)
    :metadata '(:category :runtime))
   (make-capability-definition
    :id "runtime/package-browser"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :runtime
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:package-name string)
    :output-schema '(:package string)
    :metadata '(:category :runtime))
   (make-capability-definition
    :id "runtime/symbol-page"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :runtime
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:items list)
    :metadata '(:category :runtime))
   (make-capability-definition
    :id "runtime/inspect-symbol"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :runtime
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:symbol-name string)
    :output-schema '(:symbol string)
    :metadata '(:category :runtime))
   (make-capability-definition
    :id "runtime/entity-detail"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :runtime
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:symbol-name string)
    :output-schema '(:symbol string)
    :metadata '(:category :runtime))
   (make-capability-definition
    :id "memory/list"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :memory
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:entries list)
    :metadata '(:category :memory))
   (make-capability-definition
    :id "memory/detail"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :memory
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:memory-id string)
    :output-schema '(:id string)
    :metadata '(:category :memory))
   (make-capability-definition
    :id "console/stream"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:entries list)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/events"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:tail integer)
    :output-schema '(:events list)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/event-stream"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:events list)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "desktop-task/manifests"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :desktop-task-admin
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:manifests list)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/records"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :desktop-task-admin
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:records list)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/pending-approval"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :desktop-task-admin
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:approval-id string)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/actor-flow"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :desktop-task-admin
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:runtime-state list)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/mcp-servers"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :desktop-task-admin
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:servers list)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/mcp-server"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :desktop-task-admin
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:server-id string)
    :output-schema '(:server-id string)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/context-chat-context"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :desktop-task-admin
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:project-selection list)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/set-context-chat-projects"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :desktop-task-admin
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:project-ids list :primary-project-id string)
    :output-schema '(:project-selection list)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "workspace/patch"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :editor
    :mutation-class :workspace-mutation
    :approval-required-p t
    :policy-id :workspace-write
    :input-schema '(:patch string)
    :output-schema '(:status keyword)
    :metadata '(:category :workspace))
   (make-capability-definition
    :id "workspace/promote-patch"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :editor
    :mutation-class :workspace-mutation
    :approval-required-p t
    :policy-id :workspace-write
    :input-schema '(:verified-patch list :workspace-id string :staging-root string)
    :output-schema '(:status keyword)
    :metadata '(:category :workspace))
   (make-capability-definition
    :id "editor/append-text"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :editor
    :mutation-class :workspace-mutation
    :approval-required-p t
    :policy-id :workspace-write
    :input-schema '(:text string :scope-id string :buffer-id string :package-name string)
    :output-schema '(:status keyword)
    :metadata '(:category :workspace))
   (make-capability-definition
   :id "workflow/request-approval"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :governance
    :mutation-class :approval-request
    :approval-required-p nil
    :policy-id nil
    :input-schema '(:policy keyword :summary string)
   :output-schema '(:approval-id string)
   :metadata '(:category :governance))
   (make-capability-definition
    :id "workflow/work-item-list"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:items list)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/work-item-detail"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:work-item-id string)
    :output-schema '(:id string)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/work-item-plan"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:work-item-id string)
    :output-schema '(:id string)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/work-item-wait"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:work-item-id string)
    :output-schema '(:work-item-id string)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/record-detail"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:workflow-record-id string)
    :output-schema '(:id string)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/orchestration-list"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:plans list)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/orchestration-inbox"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:items list)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/orchestration-focus"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:plan-id string)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/active-plan"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:plan-id string)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/plan-linked-workflow"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:plan-id string)
    :output-schema '(:workflow-record-id string)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/orchestration-snapshot"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:plan-id string)
    :output-schema '(:plan-id string)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "workflow/plan-verification"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :workflow
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:plan-id string)
    :output-schema '(:workflow-record-id string)
    :metadata '(:category :workflow))
   (make-capability-definition
    :id "incident/list"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :incident
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:incidents list)
    :metadata '(:category :incident))
   (make-capability-definition
    :id "incident/detail"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :incident
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:incident-id string)
    :output-schema '(:id string)
    :metadata '(:category :incident))
   (make-capability-definition
    :id "project/list"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :project
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:projects list)
    :metadata '(:category :project))
   (make-capability-definition
    :id "project/detail"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :project
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:project-id string)
    :output-schema '(:id string)
    :metadata '(:category :project))
   (make-capability-definition
    :id "project/testing-harness-inventory"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :project
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:harnesses list)
    :metadata '(:category :project))
   (make-capability-definition
    :id "rgp/workspace"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:workspace-summary list)
    :metadata '(:category :rgp))
   (make-capability-definition
    :id "rgp/artifacts"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:artifacts list)
    :metadata '(:category :rgp))
   (make-capability-definition
    :id "rgp/artifact-detail"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:artifact-id string)
    :output-schema '(:id string)
    :metadata '(:category :rgp))
   (make-capability-definition
    :id "rgp/approvals"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:approvals list)
    :metadata '(:category :rgp))
   (make-capability-definition
    :id "authority/grant"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :governance
    :mutation-class :authority-grant
    :approval-required-p t
    :policy-id :authority-grant
    :input-schema '(:policy keyword)
    :output-schema '(:status keyword)
    :metadata '(:category :governance))
   (make-capability-definition
    :id "conversation/create-thread"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :context-chat
    :mutation-class :conversation
    :approval-required-p nil
    :input-schema '(:title string :summary string)
   :output-schema '(:id string)
   :metadata '(:category :conversation))
   (make-capability-definition
    :id "conversation/thread-list"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :context-chat
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:threads list)
    :metadata '(:category :conversation))
   (make-capability-definition
    :id "conversation/thread-detail"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :context-chat
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:thread-id string)
    :output-schema '(:id string)
    :metadata '(:category :conversation))
   (make-capability-definition
    :id "conversation/turn-detail"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :context-chat
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:turn-id string)
    :output-schema '(:id string)
    :metadata '(:category :conversation))
   (make-capability-definition
    :id "conversation/latency"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :context-chat
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:turn-id string)
    :output-schema '(:turn-id string :samples list)
    :metadata '(:category :conversation))
   (make-capability-definition
    :id "conversation/update-thread"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :context-chat
    :mutation-class :conversation
    :approval-required-p nil
    :input-schema '(:thread-id string :title string :summary string)
    :output-schema '(:id string)
    :metadata '(:category :conversation))
   (make-capability-definition
    :id "conversation/use-thread"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :context-chat
    :mutation-class :conversation
    :approval-required-p nil
    :input-schema '(:thread-id string)
    :output-schema '(:id string)
    :metadata '(:category :conversation))
   (make-capability-definition
    :id "memory/update"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :memory
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:memory-id string :attribute string :value t)
    :output-schema '(:memory-id string)
    :metadata '(:category :memory))
   (make-capability-definition
    :id "memory/delete"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :memory
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:memory-id string)
    :output-schema '(:memory-id string :deleted-p boolean)
    :metadata '(:category :memory))
   (make-capability-definition
    :id "intent/create"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :intent
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:description string)
    :output-schema '(:id string)
    :metadata '(:category :intent))
   (make-capability-definition
    :id "intent/update"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :intent
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:intent-id string)
    :output-schema '(:id string)
    :metadata '(:category :intent))
   (make-capability-definition
    :id "intent/select"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :intent
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:intent-id string)
    :output-schema '(:id string)
    :metadata '(:category :intent))
   (make-capability-definition
    :id "calculator/set-expression"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :calculator
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:expression string)
    :output-schema '(:current-expression string)
    :metadata '(:category :calculator))
   (make-capability-definition
    :id "calculator/append-token"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :calculator
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:token string)
    :output-schema '(:current-expression string)
    :metadata '(:category :calculator))
   (make-capability-definition
    :id "calculator/backspace"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :calculator
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:current-expression string)
    :metadata '(:category :calculator))
   (make-capability-definition
    :id "calculator/clear"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :calculator
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:current-expression string)
    :metadata '(:category :calculator))
   (make-capability-definition
    :id "calculator/set-mode"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :calculator
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:mode keyword)
    :output-schema '(:current-mode keyword)
    :metadata '(:category :calculator))
   (make-capability-definition
    :id "calculator/set-base"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :calculator
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:base integer)
    :output-schema '(:current-base integer)
    :metadata '(:category :calculator))
   (make-capability-definition
    :id "calculator/set-word-size"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :calculator
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:word-size integer)
    :output-schema '(:current-word-size integer)
    :metadata '(:category :calculator))
   (make-capability-definition
    :id "calculator/set-angle-unit"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :calculator
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:angle-unit keyword)
    :output-schema '(:current-angle-unit keyword)
    :metadata '(:category :calculator))
   (make-capability-definition
    :id "calculator/evaluate"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :calculator
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:expression string)
   :output-schema '(:display-value string)
   :metadata '(:category :calculator))
   (make-capability-definition
    :id "calculator/summary"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :calculator
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:current-expression string)
    :metadata '(:category :calculator))
   (make-capability-definition
    :id "environment/preferences"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:preferences list)
    :output-schema '(:theme-preference keyword)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/provider-configure"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:profile-name string :options list)
    :output-schema '(:profiles list)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/provider-use"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:profile-name string)
    :output-schema '(:active-provider-profile string)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/provider-routing"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:mode keyword)
    :output-schema '(:routing-mode keyword)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/save"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:path string)
    :output-schema '(:saved string)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/load"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:path string)
    :output-schema '(:loaded string)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/save-image"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:name string)
    :output-schema '(:image list)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/load-image"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:image-id-or-name string)
    :output-schema '(:image-id string)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/revert-image"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:image-id string)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "desktop-task/configure-mcp-server"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :desktop-task-admin
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:server-id string)
    :output-schema '(:id string)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/remove-mcp-server"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :desktop-task-admin
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:server-id string)
    :output-schema '(:id string :removed-p boolean)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "shell/desktop-panel"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :shell
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:panel-id keyword)
    :output-schema '(:active-panel keyword)
    :metadata '(:category :shell))
   (make-capability-definition
    :id "shell/desktop-select"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :shell
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:panel-id keyword)
    :output-schema '(:panel-id keyword)
    :metadata '(:category :shell))
   (make-capability-definition
    :id "shell/desktop-restore"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :shell
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:panel-id keyword :panel-state list)
    :output-schema '(:panel-id keyword)
    :metadata '(:category :shell))
   (make-capability-definition
    :id "shell/desktop-control"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :shell
    :mutation-class :environment-mutation
    :approval-required-p nil
    :input-schema '(:action list)
    :output-schema '(:action list)
    :metadata '(:category :shell))
   (make-capability-definition
    :id "shell/desktop-model"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :shell
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:active-panel keyword)
    :metadata '(:category :shell))
   (make-capability-definition
    :id "environment/preferences-read"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:theme-preference keyword)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/provider"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:profile-count integer)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/image-registry"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
   :output-schema '(:images list)
   :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/summary"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:environment-id string)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "environment/status"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :environment
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:environment-id string)
    :metadata '(:category :environment))
   (make-capability-definition
    :id "package-management/summary"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :package-management
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:working-directory string)
    :metadata '(:category :package-management))
   (make-capability-definition
    :id "desktop-task/governance-state"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :governance
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:records list)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/governance-inbox"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :governance
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:requests list)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/governance-decisions"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :governance
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:decisions list)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/editor-authorizations"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :editor
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '()
    :output-schema '(:authorizations list)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/consume-editor-authorization"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :editor
    :mutation-class :execution
    :approval-required-p nil
    :input-schema '(:pending-action-id string)
    :output-schema '(:status keyword)
    :metadata '(:category :desktop-task))
   (make-capability-definition
    :id "desktop-task/apply-editor-authorization"
    :source-kind :kernel
    :provider-id :kernel
    :actor-role :editor
    :mutation-class :workspace-mutation
    :approval-required-p t
    :policy-id :workspace-write
    :input-schema '(:pending-action-id string)
    :output-schema '(:status keyword)
    :metadata '(:category :desktop-task))))

(defun normalize-capability-id (value)
  (typecase value
    (string (string-downcase value))
    (keyword (string-downcase (symbol-name value)))
    (symbol (string-downcase (symbol-name value)))
    (t (string-downcase (princ-to-string value)))))

(defun capability-definition-summary (definition)
  (list :id (capability-definition-id definition)
        :source-kind (capability-definition-source-kind definition)
        :provider-id (capability-definition-provider-id definition)
        :actor-role (capability-definition-actor-role definition)
        :mutation-class (capability-definition-mutation-class definition)
        :approval-required-p (not (null (capability-definition-approval-required-p definition)))
        :policy-id (capability-definition-policy-id definition)
        :input-schema (copy-tree (capability-definition-input-schema definition))
        :output-schema (copy-tree (capability-definition-output-schema definition))
        :backend-kind (capability-definition-backend-kind definition)
        :backend-ref (capability-definition-backend-ref definition)
        :execution-mode (capability-definition-execution-mode definition)
        :retry-policy (copy-tree (capability-definition-retry-policy definition))
        :scope (copy-tree (capability-definition-scope definition))
        :metadata (copy-tree (capability-definition-metadata definition))))

(defun kernel-capability-registry-definitions ()
  (mapcar #'copy-capability-definition +kernel-capability-registry+))

(defun tool-capability-definition (tool-summary)
  (make-capability-definition
   :id (format nil "tool/~A" (normalize-capability-id (getf tool-summary :id)))
   :source-kind :tool
   :provider-id (getf tool-summary :id)
   :actor-role nil
   :mutation-class :tool-execution
   :approval-required-p t
   :policy-id (getf tool-summary :policy)
   :backend-kind :tool
   :backend-ref (getf tool-summary :backend-profile-id)
   :scope nil
   :metadata (list :documentation (getf tool-summary :documentation)
                   :compatibility-kind (getf tool-summary :compatibility-kind)
                   :backend-profile (getf tool-summary :backend-profile)
                   :isolation-profile (getf tool-summary :isolation-profile))))

(defun tool-capability-registry-definitions ()
  (mapcar #'tool-capability-definition (sbcl-agent::list-tools)))

(defun desktop-task-manifest-mutation-class (manifest)
  (let ((target (sbcl-agent::desktop-task-manifest-target manifest)))
    (cond
      ((eq target :editor) :workspace-mutation)
      ((eq target :runtime) :runtime-mutation)
      ((eq target :governance) :approval-request)
      ((eq target :environment) :environment-mutation)
      (t :execution))))

(defun desktop-task-capability-definition (manifest)
  (make-capability-definition
   :id (normalize-capability-id
        (or (sbcl-agent::desktop-task-manifest-capability manifest)
            (format nil "~(~A~)/~(~A~)"
                    (sbcl-agent::desktop-task-manifest-target manifest)
                    (sbcl-agent::desktop-task-manifest-operation manifest))))
   :source-kind :desktop-task
   :provider-id (sbcl-agent::desktop-task-manifest-id manifest)
   :actor-role (sbcl-agent::normalize-actor-role (sbcl-agent::desktop-task-manifest-target manifest) :capability-server)
   :mutation-class (desktop-task-manifest-mutation-class manifest)
   :approval-required-p (not (null (sbcl-agent::desktop-task-manifest-approval-policy manifest)))
   :policy-id (let ((approval-policy (sbcl-agent::desktop-task-manifest-approval-policy manifest)))
                (cond
                  ((listp approval-policy)
                   (or (getf approval-policy :policy)
                       (getf approval-policy :policy-id)))
                  ((or (keywordp approval-policy)
                       (symbolp approval-policy)
                       (stringp approval-policy))
                   approval-policy)
                  (t nil)))
   :input-schema (copy-tree (sbcl-agent::desktop-task-manifest-request-schema manifest))
   :output-schema (copy-tree (sbcl-agent::desktop-task-manifest-result-schema manifest))
   :backend-kind (sbcl-agent::desktop-task-manifest-backend-kind manifest)
   :backend-ref (sbcl-agent::desktop-task-manifest-backend-ref manifest)
   :execution-mode (sbcl-agent::desktop-task-manifest-execution-mode manifest)
   :retry-policy (copy-tree (sbcl-agent::desktop-task-manifest-retry-policy manifest))
   :metadata (list :manifest-id (sbcl-agent::desktop-task-manifest-id manifest)
                   :description (sbcl-agent::desktop-task-manifest-description manifest)
                   :discoverable-p (sbcl-agent::desktop-task-manifest-discoverable-p manifest)
                   :tags (copy-list (or (sbcl-agent::desktop-task-manifest-tags manifest) '()))
                   :manifest-metadata (copy-tree (or (sbcl-agent::desktop-task-manifest-metadata manifest) '())))))

(defun desktop-task-capability-registry-definitions ()
  (mapcar #'desktop-task-capability-definition
          (sbcl-agent::list-registered-desktop-task-manifests :discoverable-only-p nil)))

(defun actor-capability-registry-definitions (session)
  (loop for definition in (actor-registry-definitions session)
        append
        (loop for capability in (sbcl-agent::actor-definition-capabilities definition)
              collect
              (make-capability-definition
               :id (normalize-capability-id capability)
               :source-kind :actor
               :provider-id (sbcl-agent::actor-definition-id definition)
               :actor-role (sbcl-agent::actor-definition-role definition)
               :mutation-class :execution
               :approval-required-p nil
               :scope (list :actor-id (sbcl-agent::actor-definition-id definition))
               :metadata (list :display-name (sbcl-agent::actor-definition-display-name definition)
                               :actor-metadata (copy-tree (or (sbcl-agent::actor-definition-metadata definition) '())))))))

(defun capability-registry-definitions (&optional session)
  (append (kernel-capability-registry-definitions)
          (tool-capability-registry-definitions)
          (desktop-task-capability-registry-definitions)
          (if session
              (actor-capability-registry-definitions session)
              '())))

(defun capability-definition-matches-p (definition &key id source-kind actor-role mutation-class approval-required-p backend-kind)
  (and (or (null id)
           (string= (normalize-capability-id id)
                    (normalize-capability-id (capability-definition-id definition))))
       (or (null source-kind)
           (eq source-kind (capability-definition-source-kind definition)))
       (or (null actor-role)
           (eq (sbcl-agent::normalize-actor-role actor-role :unknown)
               (capability-definition-actor-role definition)))
       (or (null mutation-class)
           (eq mutation-class (capability-definition-mutation-class definition)))
       (or (null approval-required-p)
           (eq (not (null approval-required-p))
               (not (null (capability-definition-approval-required-p definition)))))
       (or (null backend-kind)
           (eq backend-kind (capability-definition-backend-kind definition)))))

(defun capability-registry-session-and-options (arguments)
  (if (and arguments
           (not (keywordp (first arguments))))
      (values (first arguments) (rest arguments))
      (values nil arguments)))

(defun capability-registry-query (&rest arguments)
  (multiple-value-bind (session options)
      (capability-registry-session-and-options arguments)
    (destructuring-bind (&key id source-kind actor-role mutation-class
                              approval-required-p backend-kind
                              &allow-other-keys)
        options
      (remove-if-not
       (lambda (definition)
         (capability-definition-matches-p
          definition
          :id id
          :source-kind source-kind
          :actor-role actor-role
          :mutation-class mutation-class
          :approval-required-p approval-required-p
          :backend-kind backend-kind))
       (capability-registry-definitions session)))))

(defun capability-registry-find (&rest arguments)
  (first (apply #'capability-registry-query arguments)))
