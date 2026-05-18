(defpackage #:sbcl-agent
  (:use #:cl)
  (:import-from #:uiop
                #:command-line-arguments
                #:getcwd
                #:getenv)
  (:export #:main
           #:kernel-invoke
           #:kernel-inspect
           #:kernel-control
           #:command-kernel-invoke-service
           #:query-kernel-inspect-service
           #:command-kernel-control-service
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
           #:actor-registry-definitions
           #:actor-system-registry-definitions
           #:actor-registry-definition-by-id
           #:actor-registry-definition-by-role
           #:actor-registry-definitions-by-capability
           #:find-actor-definition-for-address
           #:canonical-actor-address-for-session
           #:ensure-environment-actor-registry-for-session
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
