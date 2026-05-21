(defpackage #:sbcl-agent.system.kernel
  (:use #:cl))

(defpackage #:sbcl-agent.system.actor-runtime
  (:use #:cl))

(defpackage #:sbcl-agent.system.policy
  (:use #:cl)
  (:export #:package-trust-tier
           #:trusted-control-plane-package-p
           #:mutable-work-plane-package-p
           #:candidate-runtime-package-p
           #:generated-runtime-package-p
           #:capability-policy
           #:make-capability-policy
           #:capability-policy-id
           #:capability-policy-description
           #:capability-policy-risk-level
           #:capability-policy-default-grant-mode
           #:capability-grant
           #:make-capability-grant
           #:capability-grant-policy-id
           #:capability-grant-granted-at
           #:capability-grant-scope
           #:capability-grant-metadata
           #:register-capability-policy
           #:find-capability-policy
           #:ensure-capability-policy
           #:capability-policy-summary
           #:list-capability-policies
           #:command-approve-policy-service
           #:command-request-work-item-approval-service))

(defpackage #:sbcl-agent.system.registry
  (:use #:cl)
  (:export #:actor-address-equal-p
           #:actor-definition-address
           #:actor-registry-definitions
           #:actor-system-registry-definitions
           #:actor-registry-definition-by-id
           #:actor-registry-definition-by-role
           #:actor-registry-definitions-by-capability
           #:find-actor-definition-for-address
           #:canonical-actor-address-for-session
           #:ensure-environment-actor-registry-for-session
           #:capability-definition
           #:capability-definition-actor-role
           #:capability-definition-summary
           #:capability-registry-definitions
           #:capability-registry-query
           #:capability-registry-find
           #:tool-definition
           #:make-tool-definition
           #:tool-definition-id
           #:tool-definition-documentation
           #:tool-definition-policy
           #:tool-definition-isolation-profile
           #:tool-definition-compatibility-kind
           #:tool-definition-backend-profile-id
           #:compatibility-app-definition
           #:make-compatibility-app-definition
           #:compatibility-app-definition-id
           #:compatibility-app-definition-title
           #:compatibility-app-definition-executable
           #:compatibility-app-definition-default-arguments
           #:compatibility-app-definition-launch-tool-id
           #:compatibility-app-definition-backend-profile-id
           #:compatibility-app-definition-policy-id
           #:compatibility-app-definition-filesystem-scope-kind
           #:compatibility-app-definition-network-policy
           #:compatibility-app-definition-workspace-write-p
           #:compatibility-app-definition-display-surface-kind
           #:compatibility-app-definition-source-package-id
           #:compatibility-backend-profile
           #:make-compatibility-backend-profile
           #:compatibility-backend-profile-id
           #:compatibility-backend-profile-label
           #:compatibility-backend-profile-substrate-kind
           #:compatibility-backend-profile-isolation-class
           #:compatibility-backend-profile-control-plane-kind
           #:compatibility-backend-profile-display-bridge-kind
           #:compatibility-backend-profile-filesystem-model
           #:compatibility-backend-profile-network-model
           #:compatibility-backend-profile-persistence-model
           #:compatibility-backend-profile-host-process-p
           #:compatibility-backend-profile-runtime-class
           #:register-tool
           #:find-tool
           #:list-tools
           #:describe-tool
           #:tool-compatibility-target
           #:invoke-sandboxed-tool
           #:invoke-tool
           #:register-compatibility-backend-profile
           #:find-compatibility-backend-profile
           #:ensure-compatibility-backend-profile
           #:compatibility-backend-profile-summary
           #:register-compatibility-app
           #:find-compatibility-app
           #:compatibility-app-summary
           #:list-compatibility-apps
           #:compatibility-app-command-argv
           #:compatibility-app-target
           #:*compatibility-app-provider-function*))

(defpackage #:sbcl-agent.system.trace
  (:use #:cl)
  (:export #:trace-link
           #:trace-link-id
           #:make-trace-link-id
           #:build-trace-link
           #:canonicalize-trace-link-record
           #:trace-link-summary
           #:list-trace-links
           #:find-trace-link
           #:entity-trace-links
           #:trace-neighborhood-summary
           #:create-trace-link
           #:query-trace-link-list-service
           #:query-trace-link-detail-service
           #:query-trace-neighborhood-service
           #:command-trace-link-create-service))

(defpackage #:sbcl-agent.work.workspace
  (:use #:cl))

(defpackage #:sbcl-agent.candidate.actor
  (:use #:cl))

(defpackage #:sbcl-agent.generated.system
  (:use #:cl))

(defpackage #:sbcl-agent
  (:use #:cl)
  (:import-from #:uiop
                #:command-line-arguments
                #:getcwd
                #:getenv)
  (:import-from #:sbcl-agent.system.policy
                #:package-trust-tier
                #:trusted-control-plane-package-p
                #:mutable-work-plane-package-p
                #:candidate-runtime-package-p
                #:generated-runtime-package-p
                #:capability-policy
                #:make-capability-policy
                #:capability-policy-id
                #:capability-policy-description
                #:capability-policy-risk-level
                #:capability-policy-default-grant-mode
                #:capability-grant
                #:make-capability-grant
                #:capability-grant-policy-id
                #:capability-grant-granted-at
                #:capability-grant-scope
                #:capability-grant-metadata
                #:register-capability-policy
                #:find-capability-policy
                #:ensure-capability-policy
                #:capability-policy-summary
                #:list-capability-policies
                #:command-approve-policy-service
                #:command-request-work-item-approval-service)
  (:import-from #:sbcl-agent.system.trace
                #:trace-link
                #:trace-link-id
                #:make-trace-link-id
                #:build-trace-link
                #:canonicalize-trace-link-record
                #:trace-link-summary
                #:list-trace-links
                #:find-trace-link
                #:entity-trace-links
                #:trace-neighborhood-summary
                #:create-trace-link
                #:query-trace-link-list-service
                #:query-trace-link-detail-service
                #:query-trace-neighborhood-service
                #:command-trace-link-create-service)
  (:import-from #:sbcl-agent.system.registry
                #:actor-address-equal-p
                #:actor-definition-address
                #:actor-registry-definitions
                #:actor-system-registry-definitions
                #:actor-registry-definition-by-id
                #:actor-registry-definition-by-role
                #:actor-registry-definitions-by-capability
                #:find-actor-definition-for-address
                #:canonical-actor-address-for-session
                #:ensure-environment-actor-registry-for-session
                #:capability-definition
                #:capability-definition-actor-role
                #:capability-definition-summary
                #:capability-registry-definitions
                #:capability-registry-query
                #:capability-registry-find
                #:tool-definition
                #:make-tool-definition
                #:tool-definition-id
                #:tool-definition-documentation
                #:tool-definition-policy
                #:tool-definition-isolation-profile
                #:tool-definition-compatibility-kind
                #:tool-definition-backend-profile-id
                #:compatibility-app-definition
                #:make-compatibility-app-definition
                #:compatibility-app-definition-id
                #:compatibility-app-definition-title
                #:compatibility-app-definition-executable
                #:compatibility-app-definition-default-arguments
                #:compatibility-app-definition-launch-tool-id
                #:compatibility-app-definition-backend-profile-id
                #:compatibility-app-definition-policy-id
                #:compatibility-app-definition-filesystem-scope-kind
                #:compatibility-app-definition-network-policy
                #:compatibility-app-definition-workspace-write-p
                #:compatibility-app-definition-display-surface-kind
                #:compatibility-app-definition-source-package-id
                #:compatibility-backend-profile
                #:make-compatibility-backend-profile
                #:compatibility-backend-profile-id
                #:compatibility-backend-profile-label
                #:compatibility-backend-profile-substrate-kind
                #:compatibility-backend-profile-isolation-class
                #:compatibility-backend-profile-control-plane-kind
                #:compatibility-backend-profile-display-bridge-kind
                #:compatibility-backend-profile-filesystem-model
                #:compatibility-backend-profile-network-model
                #:compatibility-backend-profile-persistence-model
                #:compatibility-backend-profile-host-process-p
                #:compatibility-backend-profile-runtime-class
                #:register-tool
                #:find-tool
                #:list-tools
                #:describe-tool
                #:tool-compatibility-target
                #:invoke-sandboxed-tool
                #:invoke-tool
                #:register-compatibility-backend-profile
                #:find-compatibility-backend-profile
                #:ensure-compatibility-backend-profile
                #:compatibility-backend-profile-summary
                #:register-compatibility-app
                #:find-compatibility-app
                #:compatibility-app-summary
                #:list-compatibility-apps
                #:compatibility-app-command-argv
                #:compatibility-app-target
                #:*compatibility-app-provider-function*)
  (:export #:main
           #:query-execution-detail-service
           #:command-execution-control-service
           #:package-trust-tier
           #:trusted-control-plane-package-p
           #:mutable-work-plane-package-p
           #:candidate-runtime-package-p
           #:generated-runtime-package-p
           #:create-plan-record
           #:create-plan-step
           #:plan-record-summary
           #:plan-record-detail
           #:plan-step-summary
           #:plan-step-detail
           #:find-plan-step
           #:append-plan-step
           #:append-plan-evidence
           #:append-plan-step-evidence
           #:update-plan-status
           #:update-plan-step-status
           #:increment-plan-step-repair-count
           #:session-active-plan
           #:session-plan-set
           #:session-active-plan-id
           #:session-plan-display-value
           #:session-plan-summaries
           #:set-session-active-plan
           #:clear-session-active-plan
           #:actor-address-equal-p
           #:actor-definition-address
           #:actor-registry-definitions
           #:actor-system-registry-definitions
           #:actor-registry-definition-by-id
           #:actor-registry-definition-by-role
           #:actor-registry-definitions-by-capability
           #:find-actor-definition-for-address
           #:canonical-actor-address-for-session
           #:ensure-environment-actor-registry-for-session
           #:capability-definition
           #:capability-definition-actor-role
           #:capability-registry-definitions
           #:capability-registry-query
           #:capability-registry-find
           #:capability-definition-summary
           #:query-plan-list-service
           #:query-orchestration-list-service
           #:query-orchestration-inbox-service
           #:query-orchestration-focus-service
           #:query-plan-service
           #:query-active-plan-service
           #:query-plan-linked-workflow-service
           #:query-orchestration-snapshot-service
           #:query-plan-verification-service
           #:command-create-plan-service
           #:command-expand-plan-service
           #:command-assign-plan-step-service
           #:command-complete-plan-step-service
           #:command-fail-plan-step-service
           #:command-repair-plan-step-service
           #:find-workflow-record-by-plan-id
           #:ensure-plan-workflow-record))

(defpackage #:sbcl-agent.calculator
  (:use #:cl)
  (:export #:calculator-summary
           #:evaluate-expression))

(defpackage #:sbcl-agent-user
  (:use #:cl))

(in-package #:sbcl-agent)
