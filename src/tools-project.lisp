(in-package #:sbcl-agent)

(defun project-tool-keyword (value)
  (cond
    ((null value) nil)
    ((keywordp value) value)
    ((symbolp value)
     (intern (string-upcase (symbol-name value)) "KEYWORD"))
    ((stringp value)
     (intern (string-upcase (substitute #\- #\_ value)) "KEYWORD"))
    (t nil)))

(defun project-tool-keyword-list (values)
  (remove nil (mapcar #'project-tool-keyword (or values '()))))

(defun project-tool-response (tool-id response)
  (list :tool tool-id
        :project (service-response-data response)
        :metadata (service-response-metadata response)
        :sandbox-profile :in-process))

(defun tool-project-create (session &key title summary constitution requirements
                                    feature-specifications design-system style-guide
                                    user-journeys non-functional-requirements
                                    architecture-decisions source-roots metadata)
  (project-tool-response
   :project/create
   (command-project-create-service
    session
    :title title
    :summary summary
    :constitution constitution
    :requirements requirements
    :feature-specifications feature-specifications
    :design-system design-system
    :style-guide style-guide
    :user-journeys user-journeys
    :non-functional-requirements non-functional-requirements
    :architecture-decisions architecture-decisions
    :source-roots source-roots
    :metadata metadata)))

(defun tool-project-select (session &key project-id)
  (project-tool-response
   :project/select
   (command-project-select-service session project-id)))

(defun tool-project-set-constitution (session &key project-id constitution)
  (project-tool-response
   :project/set-constitution
   (command-project-constitution-service session constitution :project-id project-id)))

(defun tool-project-set-design-system (session &key project-id design-system)
  (project-tool-response
   :project/set-design-system
   (command-project-design-system-service session design-system :project-id project-id)))

(defun tool-project-set-style-guide (session &key project-id style-guide)
  (project-tool-response
   :project/set-style-guide
   (command-project-style-guide-service session style-guide :project-id project-id)))

(defun tool-project-set-testing-strategy (session &key project-id testing-strategy)
  (project-tool-response
   :project/set-testing-strategy
   (command-project-testing-strategy-service session testing-strategy :project-id project-id)))

(defun tool-project-set-release-readiness (session &key project-id release-readiness)
  (project-tool-response
   :project/set-release-readiness
   (command-project-release-readiness-service session release-readiness :project-id project-id)))

(defun tool-project-set-readiness-obligations (session &key project-id readiness-obligations)
  (project-tool-response
   :project/set-readiness-obligations
   (command-project-readiness-obligations-service session readiness-obligations :project-id project-id)))

(defun tool-project-append-requirement (session &key project-id id title summary scope kind
                                                priority status verification-kind
                                                linked-artifact-ids metadata non-functional-p)
  (project-tool-response
   :project/append-requirement
   (command-project-requirement-service
    session
    :project-id project-id
    :id id
    :title title
    :summary summary
    :scope scope
    :kind (project-tool-keyword kind)
    :priority (project-tool-keyword priority)
    :status (project-tool-keyword status)
    :verification-kind (project-tool-keyword verification-kind)
    :linked-artifact-ids linked-artifact-ids
    :metadata metadata
    :non-functional-p non-functional-p)))

(defun tool-project-append-feature-specification (session &key project-id id title summary status
                                                          acceptance-criteria
                                                          linked-requirement-ids
                                                          linked-journey-ids metadata)
  (project-tool-response
   :project/append-feature-specification
   (command-project-feature-spec-service
    session
    :project-id project-id
    :id id
    :title title
    :summary summary
    :status (project-tool-keyword status)
    :acceptance-criteria acceptance-criteria
    :linked-requirement-ids linked-requirement-ids
    :linked-journey-ids linked-journey-ids
    :metadata metadata)))

(defun tool-project-append-user-journey (session &key project-id id title summary actors
                                                 entrypoints steps outcomes edge-cases metadata)
  (project-tool-response
   :project/append-user-journey
   (command-project-user-journey-service
    session
    :project-id project-id
    :id id
    :title title
    :summary summary
    :actors actors
    :entrypoints entrypoints
    :steps steps
    :outcomes outcomes
    :edge-cases edge-cases
    :metadata metadata)))

(defun tool-project-append-architecture-decision (session &key project-id id title status summary
                                                          drivers consequences stack-choices
                                                          linked-requirement-ids metadata)
  (project-tool-response
   :project/append-architecture-decision
   (command-project-architecture-decision-service
    session
    :project-id project-id
    :id id
    :title title
    :status (project-tool-keyword status)
    :summary summary
    :drivers drivers
    :consequences consequences
    :stack-choices stack-choices
    :linked-requirement-ids linked-requirement-ids
    :metadata metadata)))

(defun tool-project-append-source-root (session &key project-id source-root)
  (project-tool-response
   :project/append-source-root
   (command-project-source-root-service session source-root :project-id project-id)))

(defun tool-project-bind-testing-harness (session &key project-id harness-id)
  (project-tool-response
   :project/bind-testing-harness
   (command-project-bind-testing-harness-service
    session
    (project-tool-keyword harness-id)
    :project-id project-id)))

(defun tool-project-append-quality-gate (session &key project-id id title summary status
                                                 required-harness-ids
                                                 minimum-linked-work-items
                                                 minimum-linked-incidents
                                                 require-source-roots-p
                                                 required-trace-target-kinds
                                                 maximum-failed-tests
                                                 require-coverage-p
                                                 maximum-say-turn-latency-seconds
                                                 maximum-environment-save-load-seconds
                                                 require-recovery-ready-p
                                                 metadata)
  (project-tool-response
   :project/append-quality-gate
   (command-project-quality-gate-service
    session
    :project-id project-id
    :id id
    :title title
    :summary summary
    :status (project-tool-keyword status)
    :required-harness-ids (project-tool-keyword-list required-harness-ids)
    :minimum-linked-work-items minimum-linked-work-items
    :minimum-linked-incidents minimum-linked-incidents
    :require-source-roots-p require-source-roots-p
    :required-trace-target-kinds (project-tool-keyword-list required-trace-target-kinds)
    :maximum-failed-tests maximum-failed-tests
    :require-coverage-p require-coverage-p
    :maximum-say-turn-latency-seconds maximum-say-turn-latency-seconds
    :maximum-environment-save-load-seconds maximum-environment-save-load-seconds
    :require-recovery-ready-p require-recovery-ready-p
    :metadata metadata)))

(register-tool :project/create
               "Create a governed project record in the current environment."
               :project-governance-write
               #'tool-project-create)

(register-tool :project/select
               "Select the active governed project in the current environment."
               :project-governance-write
               #'tool-project-select)

(register-tool :project/set-constitution
               "Replace the constitution for a governed project."
               :project-governance-write
               #'tool-project-set-constitution)

(register-tool :project/set-design-system
               "Replace the design system payload for a governed project."
               :project-governance-write
               #'tool-project-set-design-system)

(register-tool :project/set-style-guide
               "Replace the style guide payload for a governed project."
               :project-governance-write
               #'tool-project-set-style-guide)

(register-tool :project/set-testing-strategy
               "Replace the testing strategy payload for a governed project."
               :project-governance-write
               #'tool-project-set-testing-strategy)

(register-tool :project/set-release-readiness
               "Replace the release readiness payload for a governed project."
               :project-governance-write
               #'tool-project-set-release-readiness)

(register-tool :project/set-readiness-obligations
               "Replace the readiness obligations payload for a governed project."
               :project-governance-write
               #'tool-project-set-readiness-obligations)

(register-tool :project/append-requirement
               "Append a governed requirement to a project."
               :project-governance-write
               #'tool-project-append-requirement)

(register-tool :project/append-feature-specification
               "Append a governed feature specification to a project."
               :project-governance-write
               #'tool-project-append-feature-specification)

(register-tool :project/append-user-journey
               "Append a governed user journey to a project."
               :project-governance-write
               #'tool-project-append-user-journey)

(register-tool :project/append-architecture-decision
               "Append a governed architecture decision to a project."
               :project-governance-write
               #'tool-project-append-architecture-decision)

(register-tool :project/append-source-root
               "Attach a managed source root to a project."
               :project-governance-write
               #'tool-project-append-source-root)

(register-tool :project/bind-testing-harness
               "Bind a testing harness to a project."
               :project-governance-write
               #'tool-project-bind-testing-harness)

(register-tool :project/append-quality-gate
               "Append a governed quality gate to a project."
               :project-governance-write
               #'tool-project-append-quality-gate)
