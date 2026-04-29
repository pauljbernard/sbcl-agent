(in-package #:sbcl-agent/tests)

(defun retrieval-intent-runtime-debugging-test ()
  (let* ((intent (sbcl-agent::classify-retrieval-intent
                  "Investigate the runtime failure, inspect the symbol, and recover the incident."
                  :operator-mode :conversation))
         (domains (sbcl-agent::retrieval-intent-domains intent)))
    (assert-equal :runtime-debugging
                  (sbcl-agent::retrieval-intent-category intent)
                  "runtime/incident prompts should classify as runtime debugging")
    (assert-true (find :runtime domains)
                 "runtime debugging intent should include the runtime domain")
    (assert-true (find :incident domains)
                 "runtime debugging intent should include the incident domain")
    (assert-true (sbcl-agent::retrieval-intent-governance-context-p intent)
                 "runtime debugging intent should request governance context")
    (assert-true (search "incident" (string-downcase (sbcl-agent::retrieval-intent-explanation intent)))
                 "runtime debugging intent should explain the classification")))

(defun retrieval-intent-code-change-test ()
  (let* ((intent (sbcl-agent::classify-retrieval-intent
                  "Implement the patch in the source file and update the workflow."
                  :operator-mode :conversation))
         (domains (sbcl-agent::retrieval-intent-domains intent)))
    (assert-equal :code-change
                  (sbcl-agent::retrieval-intent-category intent)
                  "source mutation prompts should classify as code change")
    (assert-true (find :workspace domains)
                 "code change intent should include the workspace domain")
    (assert-true (find :workflow domains)
                 "code change intent should include the workflow domain")
    (assert-true (sbcl-agent::retrieval-intent-source-context-p intent)
                 "code change intent should request source context")
    (assert-true (sbcl-agent::retrieval-intent-mutation-likely-p intent)
                 "code change intent should mark mutation likely")))

(defun retrieval-plan-compact-first-test ()
  (let* ((plan (sbcl-agent::build-retrieval-plan
                "Summarize the current thread and explain the latest code."
                :operator-mode :conversation))
         (intent (sbcl-agent::retrieval-plan-intent plan)))
    (assert-equal :compact-first
                  (sbcl-agent::retrieval-plan-expansion-posture plan)
                  "lightweight inspection should prefer compact-first retrieval")
    (assert-equal nil
                  (sbcl-agent::retrieval-plan-semantic-ranking-p plan)
                  "first retrieval plan iteration should not enable semantic ranking")
    (assert-true (listp (sbcl-agent::retrieval-plan-per-domain-limits plan))
                 "retrieval plan should include per-domain limits")
    (assert-equal (sbcl-agent::retrieval-intent-domains intent)
                  (sbcl-agent::retrieval-plan-domains plan)
                  "retrieval plan domains should follow the classified intent")))

(defun retrieval-plan-expand-on-gap-test ()
  (let* ((plan (sbcl-agent::build-retrieval-plan
                "Review the incident history, approvals, and blocked work-items before patching."
                :operator-mode :conversation))
         (limits (sbcl-agent::retrieval-plan-per-domain-limits plan)))
    (assert-equal :expand-on-gap
                  (sbcl-agent::retrieval-plan-expansion-posture plan)
                  "governance-heavy prompts should prefer expand-on-gap retrieval")
    (assert-true (sbcl-agent::retrieval-plan-governance-detail-p plan)
                 "governance-heavy prompts should request governance detail")
    (assert-true (find :incident (sbcl-agent::retrieval-plan-domains plan))
                 "governance-heavy prompts should include incidents")
    (assert-true (>= (or (getf limits :workflow) 0) 6)
                 "governance-heavy prompts should allocate a deeper workflow limit")))

(defun retrieval-dossier-auto-expansion-test ()
  (let* ((session (make-test-session :cwd "/tmp/retrieval-auto-expansion/"))
         (dossier (sbcl-agent::build-retrieval-dossier
                   session
                   "Review the incident history, approvals, and blocked work-items before patching."
                   :operator-mode :conversation))
         (plan (sbcl-agent::retrieval-dossier-plan dossier)))
    (assert-equal :expanded
                  (sbcl-agent::retrieval-plan-expansion-posture plan)
                  "thin governance-heavy dossiers should trigger one bounded expansion pass")
    (assert-equal 1
                  (sbcl-agent::retrieval-plan-expansion-pass plan)
                  "auto-expansion should run at most one bounded pass")
    (assert-true (>= (or (getf (sbcl-agent::retrieval-plan-per-domain-limits plan) :workflow) 0) 10)
                 "auto-expansion should widen workflow retrieval limits when context remains thin")))

(defun retrieval-dossier-no-auto-expansion-compact-test ()
  (let* ((session (make-test-session :cwd "/tmp/retrieval-no-auto-expansion/"))
         (dossier (sbcl-agent::build-retrieval-dossier
                   session
                   "Summarize the current thread and explain the latest code."
                   :operator-mode :conversation))
         (plan (sbcl-agent::retrieval-dossier-plan dossier)))
    (assert-equal :compact-first
                  (sbcl-agent::retrieval-plan-expansion-posture plan)
                  "compact-first retrieval should not auto-expand when the prompt does not justify it")
    (assert-equal 0
                  (sbcl-agent::retrieval-plan-expansion-pass plan)
                  "compact-first retrieval should remain on the initial pass")))

(defun retrieval-plan-semantic-ranking-history-test ()
  (let ((plan (sbcl-agent::build-retrieval-plan
               "What happened earlier with that incident and prior patch?"
               :operator-mode :conversation)))
    (assert-true (sbcl-agent::retrieval-plan-semantic-ranking-p plan)
                 "historical prompts should enable optional semantic ranking metadata")))

(defun retrieval-plan-governance-bias-test ()
  (let* ((session (make-test-session :cwd "/tmp/retrieval-plan-governance-bias/"))
         (work-item (sbcl-agent::create-work-item session "Governance-biased retrieval")))
    (sbcl-agent::create-incident session
                                 :runtime-eval-failure
                                 "Open incident"
                                 "Governance burden should bias retrieval.")
    (setf (sbcl-agent::work-item-status work-item) :awaiting-cold-validation
          (sbcl-agent::work-item-pending-validations work-item) '(:cold))
    (let* ((plan (sbcl-agent::build-retrieval-plan
                  "Summarize the current thread and explain the latest code."
                  :session session
                  :operator-mode :conversation))
           (domains (sbcl-agent::retrieval-plan-domains plan))
           (limits (sbcl-agent::retrieval-plan-per-domain-limits plan)))
      (assert-equal :incident
                    (first domains)
                    "governance-biased retrieval should prioritize incidents first")
      (assert-true (find :workflow domains)
                   "governance-biased retrieval should include workflow context")
      (assert-true (find :artifact domains)
                   "governance-biased retrieval should include artifact context")
      (assert-equal :expand-on-gap
                    (sbcl-agent::retrieval-plan-expansion-posture plan)
                    "governance bias should upgrade compact plans to expand-on-gap")
      (assert-true (>= (or (getf limits :incident) 0) 6)
                   "governance-biased retrieval should deepen incident limits")
      (assert-true (>= (or (getf limits :events) 0) 8)
                   "governance-biased retrieval should deepen event limits")
      (assert-true (search "Governance bias prioritized incidents/workflow"
                           (sbcl-agent::retrieval-plan-explanation plan))
                   "governance-biased retrieval should explain why the plan was widened"))))

(defun retrieval-dossier-governance-bias-test ()
  (let* ((session (make-test-session :cwd "/tmp/retrieval-dossier-governance-bias/"))
         (work-item (sbcl-agent::create-work-item session "Governance-biased dossier")))
    (sbcl-agent::create-incident session
                                 :runtime-eval-failure
                                 "Open incident"
                                 "Governance burden should appear in the dossier plan.")
    (setf (sbcl-agent::work-item-status work-item) :awaiting-cold-validation
          (sbcl-agent::work-item-pending-validations work-item) '(:cold))
    (let* ((dossier (sbcl-agent::build-retrieval-dossier
                     session
                     "Summarize the current thread and explain the latest code."
                     :operator-mode :conversation))
           (plan (sbcl-agent::retrieval-dossier-plan dossier)))
      (assert-true (find :incident (sbcl-agent::retrieval-plan-domains plan))
                   "governance-biased dossier plans should include incident context")
      (assert-true (find :workflow (sbcl-agent::retrieval-plan-domains plan))
                   "governance-biased dossier plans should include workflow context")
      (assert-true (listp (getf (sbcl-agent::retrieval-dossier-incident-context dossier) :incidents))
                   "governance-biased dossier should assemble incident context")
      (assert-true (listp (getf (sbcl-agent::retrieval-dossier-workflow-context dossier) :work-items))
                   "governance-biased dossier should assemble workflow context"))))

(defun retrieval-dossier-runtime-debugging-test ()
  (let* ((session (make-test-session :cwd "/tmp/retrieval-dossier-runtime-debugging/"))
         (work-item (sbcl-agent::create-work-item session "Investigate runtime failure")))
    (sbcl-agent::create-incident session
                                 :runtime-eval-failure
                                 "Runtime failure"
                                 "Need retrieval dossier incident context")
    (sbcl-agent::create-workflow-record session
                                        "Investigate runtime failure"
                                        :work-item-id (sbcl-agent::work-item-id work-item))
    (let ((dossier (sbcl-agent::build-retrieval-dossier
                    session
                    "Investigate the runtime incident and blocked work-item."
                    :operator-mode :conversation)))
      (assert-equal :runtime-debugging
                    (sbcl-agent::retrieval-intent-category (sbcl-agent::retrieval-dossier-intent dossier))
                    "runtime dossier should preserve intent classification")
      (assert-true (listp (getf (sbcl-agent::retrieval-dossier-runtime-context dossier) :summary))
                   "runtime dossier should include runtime summary")
      (assert-true (listp (getf (sbcl-agent::retrieval-dossier-environment-context dossier) :events))
                   "runtime dossier should include environment event context")
      (assert-true (listp (getf (sbcl-agent::retrieval-dossier-incident-context dossier) :incidents))
                   "runtime dossier should include incident context")
      (assert-true (listp (getf (sbcl-agent::retrieval-dossier-workflow-context dossier) :work-items))
                   "runtime dossier should include workflow context"))))

(defun retrieval-dossier-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/retrieval-dossier-service/"))
         (response (sbcl-agent::query-retrieval-dossier-service
                    session
                    "Summarize the current thread and relevant code context."
                    :operator-mode :conversation))
         (payload (sbcl-agent::service-response-data response)))
    (assert-equal :retrieval
                  (getf response :domain)
                  "retrieval dossier service should report the retrieval domain")
    (assert-equal :dossier
                  (getf response :operation)
                  "retrieval dossier service should identify the dossier operation")
    (assert-equal :environment
                  (getf (sbcl-agent::service-response-metadata response) :authority)
                  "retrieval dossier service should declare environment authority")
    (assert-true (listp (getf payload :intent))
                 "retrieval dossier service should return an intent summary")
    (assert-true (listp (getf payload :ranking))
                 "retrieval dossier service should return ranking metadata")
    (assert-true (listp (getf payload :environment-context))
                 "retrieval dossier service should return environment context")))

(defun retrieval-ranking-history-dossier-test ()
  (let* ((session (make-test-session :cwd "/tmp/retrieval-ranking-history/"))
         (payload (sbcl-agent::service-response-data
                   (sbcl-agent::query-retrieval-dossier-service
                    session
                    "What happened earlier with that prior incident?"
                    :operator-mode :conversation)))
         (ranking (getf payload :ranking)))
    (assert-true (getf ranking :enabled-p)
                 "historical retrieval should enable ranking metadata")
    (assert-true (> (length (or (getf ranking :top-candidates) '())) 0)
                 "ranking metadata should expose top candidates for historical prompts")))

(defun retrieval-ranking-governance-bias-test ()
  (let* ((session (make-test-session :cwd "/tmp/retrieval-ranking-governance-bias/"))
         (work-item (sbcl-agent::create-work-item session "Governance-ranked retrieval")))
    (sbcl-agent::create-incident session
                                 :runtime-eval-failure
                                 "Open incident"
                                 "Governance-aware ranking should prioritize incident evidence.")
    (setf (sbcl-agent::work-item-status work-item) :awaiting-cold-validation
          (sbcl-agent::work-item-pending-validations work-item) '(:cold))
    (let* ((payload (sbcl-agent::service-response-data
                     (sbcl-agent::query-retrieval-dossier-service
                      session
                      "Summarize the current thread and explain the latest code."
                      :operator-mode :conversation)))
           (ranking (getf payload :ranking))
           (top-candidates (or (getf ranking :top-candidates) '()))
           (labels (mapcar (lambda (entry) (getf entry :label)) top-candidates))
           (incident-candidate (find :incident top-candidates :key (lambda (entry) (getf entry :label)) :test #'eq))
           (workflow-candidate (find :workflow top-candidates :key (lambda (entry) (getf entry :label)) :test #'eq)))
      (assert-true (getf ranking :enabled-p)
                   "governance-biased retrieval should still emit ranking metadata")
      (assert-true (search "governance-relevant retrieved domains"
                           (string-downcase (getf ranking :explanation)))
                   "governance-biased ranking should explain the governance emphasis")
      (assert-true (or (member :incident labels :test #'eq)
                       (member :workflow labels :test #'eq))
                   "governance-biased ranking should elevate incident or workflow context into top candidates")
      (when incident-candidate
        (assert-true (> (or (getf incident-candidate :governance-bonus) 0) 0)
                     "incident candidates should receive a governance bonus"))
      (when workflow-candidate
        (assert-true (> (or (getf workflow-candidate :governance-bonus) 0) 0)
                     "workflow candidates should receive a governance bonus")))))

(defun retrieval-ranking-disabled-guardrail-test ()
  (let ((sbcl-agent::*retrieval-ranking-mode* :off))
    (let* ((session (make-test-session :cwd "/tmp/retrieval-ranking-disabled/"))
           (payload (sbcl-agent::service-response-data
                     (sbcl-agent::query-retrieval-dossier-service
                      session
                      "What happened earlier with that prior incident?"
                      :operator-mode :conversation)))
           (ranking (getf payload :ranking)))
      (assert-equal nil
                    (getf ranking :enabled-p)
                    "ranking guardrails should allow retrieval ranking to be disabled explicitly")
      (assert-equal '()
                    (getf ranking :top-candidates)
                    "disabled ranking should not surface ranked candidates"))))

(defun reasoning-brief-grounding-test ()
  (let* ((session (make-test-session :cwd "/tmp/reasoning-brief-grounding/"))
         (work-item (sbcl-agent::create-work-item session "Validate reasoning brief")))
    (sbcl-agent::create-incident session
                                 :runtime-eval-failure
                                 "Runtime incident"
                                 "Open incident for reasoning brief coverage")
    (setf (sbcl-agent::work-item-status work-item) :awaiting-cold-validation
          (sbcl-agent::work-item-pending-validations work-item) '(:cold))
    (let* ((dossier (sbcl-agent::service-response-data
                     (sbcl-agent::query-retrieval-dossier-service
                      session
                      "Review the incident history, approvals, and blocked work-items before patching."
                      :operator-mode :conversation)))
           (brief (sbcl-agent::build-reasoning-brief
                   (sbcl-agent::provider-session-summary session)
                   (sbcl-agent::provider-environment-context session)
                   dossier)))
      (assert-equal :environment-grounded
                    (getf brief :reasoning-mode)
                    "reasoning brief should declare environment-grounded reasoning mode")
      (assert-true (> (length (getf brief :facts)) 0)
                   "reasoning brief should surface environment-backed facts")
      (assert-true (> (length (getf brief :blockers)) 0)
                   "reasoning brief should surface current blockers")
      (assert-true (> (length (getf brief :validation-obligations)) 0)
                   "reasoning brief should surface validation obligations")
      (assert-true (> (length (getf brief :evidence-actions)) 0)
                   "reasoning brief should suggest evidence-oriented next actions"))))

(defun planning-brief-grounding-test ()
  (let* ((session (make-test-session :cwd "/tmp/planning-brief-grounding/"))
         (work-item (sbcl-agent::create-work-item session "Plan from environment state")))
    (setf (sbcl-agent::work-item-status work-item) :awaiting-approval
          (sbcl-agent::work-item-pending-validations work-item) '(:live :cold))
    (let* ((dossier (sbcl-agent::service-response-data
                     (sbcl-agent::query-retrieval-dossier-service
                      session
                      "Implement the patch in the source file and update the workflow."
                      :operator-mode :conversation)))
           (reasoning-brief (sbcl-agent::build-reasoning-brief
                             (sbcl-agent::provider-session-summary session)
                             (sbcl-agent::provider-environment-context session)
                             dossier))
           (planning-brief (sbcl-agent::build-planning-brief
                            "Implement the patch in the source file and update the workflow."
                            reasoning-brief
                            dossier)))
      (assert-equal :environment-grounded
                    (getf planning-brief :planning-mode)
                    "planning brief should declare environment-grounded planning mode")
      (assert-true (> (length (getf planning-brief :ordered-steps)) 0)
                   "planning brief should provide ordered steps")
      (assert-true (> (length (getf planning-brief :constraints)) 0)
                   "planning brief should preserve workflow and validation constraints")
      (assert-true (> (length (getf planning-brief :success-criteria)) 0)
                   "planning brief should provide success criteria grounded in the environment"))))

(defun validation-plan-grounding-test ()
  (let* ((session (make-test-session :cwd "/tmp/validation-plan-grounding/"))
         (work-item (sbcl-agent::create-work-item session "Validation plan grounding" :transaction-scope :test)))
    (sbcl-agent::append-work-item-checkpoint session work-item)
    (setf (sbcl-agent::work-item-status work-item) :awaiting-cold-validation)
    (sbcl-agent::refresh-work-item-pending-validations session work-item)
    (let* ((dossier (sbcl-agent::service-response-data
                     (sbcl-agent::query-retrieval-dossier-service
                      session
                      "Validate the pending runtime mutation before doing anything else."
                      :operator-mode :conversation)))
           (bundle (sbcl-agent::build-cognition-bundle
                    "Validate the pending runtime mutation before doing anything else."
                    (sbcl-agent::provider-session-summary session)
                    (sbcl-agent::provider-environment-context session)
                    dossier
                    :session session))
           (validation-plan (sbcl-agent::cognition-bundle-validation-plan bundle)))
      (assert-equal :required
                    (getf validation-plan :mode)
                    "validation plan should inherit required mode when obligations are open")
      (assert-equal :run-required-validations
                    (getf validation-plan :next-step)
                    "validation plan should point to required validation execution")
      (assert-equal 1
                    (getf validation-plan :work-item-count)
                    "validation plan should surface the work-item that still needs validation")
      (assert-true (> (length (getf (first (getf validation-plan :entries)) :validator-actions)) 0)
                   "validation plan should include concrete validator actions from workflow state"))))

(defun retrieval-focus-plan-grounding-test ()
  (let* ((session (make-test-session :cwd "/tmp/retrieval-focus-plan-grounding/"))
         (work-item (sbcl-agent::create-work-item session "Governance-ranked retrieval focus")))
    (sbcl-agent::create-incident session
                                 :runtime-eval-failure
                                 "Open incident"
                                 "Retrieval focus should prioritize governance evidence.")
    (setf (sbcl-agent::work-item-status work-item) :awaiting-cold-validation
          (sbcl-agent::work-item-pending-validations work-item) '(:cold))
    (let* ((dossier (sbcl-agent::service-response-data
                     (sbcl-agent::query-retrieval-dossier-service
                      session
                      "Summarize the current thread and explain the latest code."
                      :operator-mode :conversation)))
           (bundle (sbcl-agent::build-cognition-bundle
                    "Summarize the current thread and explain the latest code."
                    (sbcl-agent::provider-session-summary session)
                    (sbcl-agent::provider-environment-context session)
                    dossier
                    :session session))
           (focus-plan (sbcl-agent::cognition-bundle-retrieval-focus-plan bundle))
           (focus-labels (getf focus-plan :focus-labels)))
      (assert-true (getf focus-plan :ranking-enabled-p)
                   "retrieval focus plan should preserve ranking enablement")
      (assert-true (> (getf focus-plan :entry-count) 0)
                   "retrieval focus plan should surface ranked focus entries")
      (assert-true (or (member :incident focus-labels :test #'eq)
                       (member :workflow focus-labels :test #'eq))
                   "retrieval focus plan should carry the governance-ranked focus labels into cognition")
      (assert-true (listp (getf focus-plan :primary-focus))
                   "retrieval focus plan should expose a primary focus candidate"))))

(defun action-agenda-grounding-test ()
  (let* ((session (make-test-session :cwd "/tmp/action-agenda-grounding/"))
         (work-item (sbcl-agent::create-work-item session "Action agenda grounding")))
    (sbcl-agent::create-incident session
                                 :runtime-eval-failure
                                 "Open incident"
                                 "Action agenda should front-load evidence and validation work.")
    (setf (sbcl-agent::work-item-status work-item) :awaiting-cold-validation
          (sbcl-agent::work-item-pending-validations work-item) '(:cold))
    (let* ((dossier (sbcl-agent::service-response-data
                     (sbcl-agent::query-retrieval-dossier-service
                      session
                      "Summarize the current thread and explain the latest code."
                      :operator-mode :conversation)))
           (bundle (sbcl-agent::build-cognition-bundle
                    "Summarize the current thread and explain the latest code."
                    (sbcl-agent::provider-session-summary session)
                    (sbcl-agent::provider-environment-context session)
                    dossier
                    :session session))
           (agenda (sbcl-agent::cognition-bundle-action-agenda bundle))
           (steps (getf agenda :steps))
           (kinds (mapcar (lambda (entry) (getf entry :kind)) steps)))
      (assert-true (> (getf agenda :step-count) 0)
                   "action agenda should surface ordered next steps")
      (assert-true (member :focus-context kinds :test #'eq)
                   "action agenda should include retrieval focus as an explicit first-class step")
      (assert-true (member :run-validations kinds :test #'eq)
                   "action agenda should include validation work when required")
      (assert-true (listp (getf agenda :primary-step))
                   "action agenda should expose a primary step"))))

(defun outcome-brief-grounding-test ()
  (let* ((session (make-test-session :cwd "/tmp/outcome-brief-grounding/"))
         (action-results (list (list :action (sbcl-agent::make-assistant-action
                                              :type :patch
                                              :payload '((:write "tmp/generated.txt" "hello")))
                                     :status :completed
                                     :result '(:patch ((:path "/tmp/outcome-brief-grounding/tmp/generated.txt"))))))
         (dossier (sbcl-agent::service-response-data
                   (sbcl-agent::query-post-mutation-retrieval-dossier-service
                    session
                    "apply a patch and validate the result"
                    action-results
                    :operator-mode :conversation)))
         (reasoning-brief (sbcl-agent::build-reasoning-brief
                           (sbcl-agent::provider-session-summary session)
                           (sbcl-agent::provider-environment-context session)
                           dossier))
         (planning-brief (sbcl-agent::build-planning-brief
                          "apply a patch and validate the result"
                          reasoning-brief
                          dossier))
         (outcome-brief (sbcl-agent::build-outcome-brief planning-brief reasoning-brief dossier)))
    (assert-equal :expectation-vs-observation
                  (getf outcome-brief :outcome-mode)
                  "outcome brief should declare expectation-vs-observation mode")
    (assert-true (> (length (getf outcome-brief :expected-phases)) 0)
                 "outcome brief should preserve expected phases")
    (assert-true (listp (getf outcome-brief :observed-summary))
                 "outcome brief should summarize observed consequences")
    (assert-true (member (getf outcome-brief :recommended-next-step)
                         '(:conclude :validate :resolve-blockers :collect-evidence)
                         :test #'eq)
                 "outcome brief should recommend a concrete next step")))

(defun prior-outcome-brief-reuse-test ()
  (let* ((session (make-test-session :cwd "/tmp/prior-outcome-reuse/"))
         (thread (sbcl-agent::current-thread session)))
    (flet ((record-turn (prompt reply &key (status :completed) incident-summary)
             (let* ((user-message (sbcl-agent::create-message session thread :user prompt))
                    (turn (sbcl-agent::start-turn session thread user-message
                                                  :metadata '(:source :test)))
                    (assistant-message (sbcl-agent::create-message session thread :assistant reply))
                    (operation (sbcl-agent::start-operation session
                                                            thread
                                                            turn
                                                            :provider-run
                                                            "mock"
                                                            (list :prompt prompt)
                                                            :policy-decision
                                                            (sbcl-agent::mutation-policy-decision-summary
                                                             :safe-read
                                                             :decision :allowed
                                                             :reason "test"))))
               (sbcl-agent::complete-operation session
                                              thread
                                              turn
                                              operation
                                              (list :message reply)
                                              :status (if (eq status :completed) :completed :failed))
               (sbcl-agent::complete-turn session thread turn assistant-message :status status)
               (when incident-summary
                 (sbcl-agent::create-incident session
                                              :runtime-eval-failure
                                              "Similar prior failure"
                                              incident-summary
                                              :thread thread
                                              :turn turn
                                              :operation operation))
               turn)))
      (record-turn "Implement the runtime patch and validate it." "Earlier success path.")
      (record-turn "Implement the runtime patch but it crashes." "Earlier failure path."
                   :status :failed
                   :incident-summary "Patch crashed during runtime mutation."))
    (let ((brief (sbcl-agent::build-prior-outcome-brief
                  session
                  "Implement the runtime patch and validate the fix."
                  :current-turn-id nil)))
      (assert-equal :historical-analogy
                    (getf brief :mode)
                    "prior outcome reuse should identify its operating mode")
      (assert-true (> (length (getf brief :similar-successes)) 0)
                   "prior outcome reuse should surface similar successful work")
      (assert-true (> (length (getf brief :similar-failures)) 0)
                   "prior outcome reuse should surface similar failed work")
      (assert-true (> (length (getf brief :avoidance-guidance)) 0)
                   "prior outcome reuse should derive avoidance guidance from failures")
      (assert-equal :reuse-with-caution
                    (getf brief :reuse-recommendation)
                    "prior outcome reuse should bias toward caution when similar failures exist"))))

(defun turn-outcome-memory-recording-test ()
  (let* ((session (make-test-session :cwd "/tmp/turn-outcome-memory/"))
         (environment (sbcl-agent::make-default-environment :session session
                                                            :storage-root "/tmp/turn-outcome-memory/"))
         (provider (make-test-provider)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::run-conversation-turn provider
                                       session
                                       "Inspect the runtime and summarize the current code context."
                                       :stream-p nil
                                       :source :say
                                       :operator-mode :conversation)
    (let* ((entries (sbcl-agent::environment-memory environment))
           (entry (first entries))
           (memory-event (find :memory-entry-recorded
                               (sbcl-agent::agent-session-events session)
                               :key #'sbcl-agent::event-kind)))
      (assert-true (> (length entries) 0)
                   "turn execution should persist reusable memory into the bound environment")
      (assert-equal :turn-outcome
                    (getf entry :kind)
                    "turn memory entries should preserve their durable kind")
      (assert-equal :inspection-first
                    (getf entry :execution-mode)
                    "turn memory entries should capture execution strategy")
      (assert-equal :opportunistic
                    (getf entry :validation-mode)
                    "turn memory entries should capture validation strategy")
      (assert-true memory-event
                   "turn memory recording should emit an explicit memory event"))))

(defun durable-memory-prior-outcome-reuse-test ()
  (let* ((session-one (make-test-session :cwd "/tmp/durable-memory-reuse/"))
         (environment (sbcl-agent::make-default-environment :session session-one
                                                            :storage-root "/tmp/durable-memory-reuse/"))
         (provider (make-test-provider)))
    (sbcl-agent::bind-session-to-environment session-one environment)
    (sbcl-agent::run-conversation-turn provider
                                       session-one
                                       "Inspect the runtime and summarize the current code context."
                                       :stream-p nil
                                       :source :say
                                       :operator-mode :conversation)
    (let* ((session-two (make-test-session :cwd "/tmp/durable-memory-reuse/")))
      (sbcl-agent::bind-session-to-environment session-two environment)
      (let ((brief (sbcl-agent::build-prior-outcome-brief
                    session-two
                    "Inspect the runtime and summarize the current code context."
                    :current-turn-id nil)))
        (assert-true (> (length (getf brief :similar-successes)) 0)
                     "durable memory should let a fresh bound session recover similar successful work")
        (assert-true (> (or (getf brief :memory-match-count) 0) 0)
                     "durable memory reuse should report explicit environment memory matches")
        (assert-equal :memory
                      (getf (first (getf brief :similar-successes)) :source)
                      "durable memory reuse should prefer reusable environment memory entries")
        (assert-equal :inspection-first
                      (getf brief :preferred-execution-mode)
                      "durable memory reuse should recover preferred execution strategy")
        (assert-equal :opportunistic
                      (getf brief :preferred-validation-mode)
                      "durable memory reuse should recover preferred validation strategy")
        (assert-true (> (length (or (getf brief :strategy-patterns) '())) 0)
                     "durable memory reuse should surface reusable strategy patterns")))))

(defun durable-playbook-synthesis-test ()
  (let* ((session (make-test-session :cwd "/tmp/durable-playbook-synthesis/"))
         (environment (sbcl-agent::make-default-environment :session session
                                                            :storage-root "/tmp/durable-playbook-synthesis/"))
         (provider (make-test-provider)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::run-conversation-turn provider
                                       session
                                       "Inspect the runtime and summarize the current code context."
                                       :stream-p nil
                                       :source :say
                                       :operator-mode :conversation)
    (sbcl-agent::run-conversation-turn provider
                                       session
                                       "Inspect the runtime and summarize the current code context again."
                                       :stream-p nil
                                       :source :say
                                       :operator-mode :conversation)
    (let* ((playbooks (remove-if-not #'sbcl-agent::environment-memory-playbook-entry-p
                                     (sbcl-agent::environment-memory environment)))
           (playbook (first playbooks)))
      (assert-true (> (length playbooks) 0)
                   "durable memory should synthesize advisory playbooks from repeated outcomes")
      (assert-equal :runtime-inspection
                    (getf playbook :retrieval-category)
                    "playbooks should retain the task-class retrieval category")
      (assert-equal :inspection-first
                    (getf playbook :execution-mode)
                    "playbooks should retain the preferred execution mode")
      (assert-true (> (or (getf playbook :success-count) 0) 0)
                   "playbooks should aggregate successful occurrences")
      (assert-true (stringp (getf playbook :guidance))
                   "playbooks should provide reusable operator guidance"))))

(defun fresh-session-playbook-reuse-test ()
  (let* ((session-one (make-test-session :cwd "/tmp/fresh-session-playbook-reuse/"))
         (environment (sbcl-agent::make-default-environment :session session-one
                                                            :storage-root "/tmp/fresh-session-playbook-reuse/"))
         (provider (make-test-provider)))
    (sbcl-agent::bind-session-to-environment session-one environment)
    (sbcl-agent::run-conversation-turn provider
                                       session-one
                                       "Inspect the runtime and summarize the current code context."
                                       :stream-p nil
                                       :source :say
                                       :operator-mode :conversation)
    (let ((session-two (make-test-session :cwd "/tmp/fresh-session-playbook-reuse/")))
      (sbcl-agent::bind-session-to-environment session-two environment)
      (let* ((brief (sbcl-agent::build-prior-outcome-brief
                     session-two
                     "Inspect the runtime and summarize the current code context."
                     :current-turn-id nil))
             (playbook (first (getf brief :playbooks))))
        (assert-true (> (or (getf brief :playbook-count) 0) 0)
                     "fresh bound sessions should recover durable playbooks")
        (assert-equal :playbook
                      (getf playbook :source)
                      "recovered playbooks should be explicitly marked as durable playbooks")
        (assert-equal :inspection-first
                      (getf playbook :execution-mode)
                      "recovered playbooks should preserve execution guidance")
        (assert-true (stringp (getf playbook :guidance))
                     "recovered playbooks should surface reusable guidance")))))

(defun playbook-ranking-prefers-category-and-history-test ()
  (let* ((session (make-test-session :cwd "/tmp/playbook-ranking-preference/"))
         (environment (sbcl-agent::make-default-environment :session session
                                                            :storage-root "/tmp/playbook-ranking-preference/")))
    (sbcl-agent::bind-session-to-environment session environment)
    (setf (sbcl-agent::environment-memory environment)
          (list
           (list :kind :playbook
                 :memory-id "playbook-runtime-safe"
                 :playbook-key "playbook-runtime-safe"
                 :title "Runtime debugging safe path"
                 :retrieval-category :runtime-debugging
                 :intent '(:category :runtime-debugging
                           :domains (:runtime :incident :workflow)
                           :governance-context-p t
                           :source-context-p nil
                           :mutation-likely-p nil)
                 :execution-mode :historically-cautious
                 :validation-mode :required
                 :agenda-primary-step '(:kind :collect-evidence)
                 :success-count 3
                 :failure-count 0
                 :reuse-recommendation :reuse-success-patterns
                 :guidance "Investigate the incident and runtime state before attempting mutations."
                 :sample-prompts '("Investigate the runtime incident and recover safely."))
           (list :kind :playbook
                 :memory-id "playbook-runtime-patch-risky"
                 :playbook-key "playbook-runtime-patch-risky"
                 :title "Runtime patch fast path"
                 :retrieval-category :code-change
                 :intent '(:category :code-change
                           :domains (:workspace :workflow)
                           :governance-context-p t
                           :source-context-p t
                           :mutation-likely-p t)
                 :execution-mode :mutation-ready
                 :validation-mode :opportunistic
                 :agenda-primary-step '(:kind :plan-mutation)
                 :success-count 1
                 :failure-count 2
                 :reuse-recommendation :reuse-with-caution
                 :guidance "Patch the code quickly to resolve the runtime issue."
                 :sample-prompts '("Patch the runtime code and update the file immediately."))))
    (let* ((brief (sbcl-agent::build-prior-outcome-brief
                   session
                   "Investigate the runtime incident and recover the blocked workflow."
                   :current-turn-id nil))
           (playbook (first (getf brief :playbooks))))
      (assert-true (> (or (getf brief :playbook-count) 0) 1)
                   "playbook ranking test should consider multiple candidate playbooks")
      (assert-equal "playbook-runtime-safe"
                    (getf playbook :playbook-key)
                    "playbook ranking should prefer the category-aligned safer playbook")
      (assert-true (member :category-match (getf playbook :ranking-explanation) :test #'eq)
                   "playbook ranking should explain the category match")
      (assert-true (member :governance-match (getf playbook :ranking-explanation) :test #'eq)
                   "playbook ranking should explain governance alignment"))))

(defun durable-failure-cluster-synthesis-test ()
  (let* ((session (make-test-session :cwd "/tmp/durable-failure-cluster/"))
         (thread (sbcl-agent::current-thread session))
         (environment (sbcl-agent::make-default-environment :session session
                                                            :storage-root "/tmp/durable-failure-cluster/")))
    (sbcl-agent::bind-session-to-environment session environment)
    (flet ((record-failure (prompt incident-summary)
             (let* ((user-message (sbcl-agent::create-message session thread :user prompt))
                    (turn (sbcl-agent::start-turn session thread user-message
                                                  :metadata '(:source :test)))
                    (assistant-message (sbcl-agent::create-message session thread :assistant "Failure path."))
                    (operation (sbcl-agent::start-operation session
                                                            thread
                                                            turn
                                                            :provider-run
                                                            "mock"
                                                            (list :prompt prompt)
                                                            :policy-decision
                                                            (sbcl-agent::mutation-policy-decision-summary
                                                             :safe-read
                                                             :decision :allowed
                                                             :reason "test"))))
               (sbcl-agent::complete-operation session
                                              thread
                                              turn
                                              operation
                                              (list :message "Failure path.")
                                              :status :failed)
               (sbcl-agent::complete-turn session thread turn assistant-message :status :failed)
               (sbcl-agent::create-incident session
                                            :runtime-eval-failure
                                            "Repeated failure"
                                            incident-summary
                                            :thread thread
                                            :turn turn
                                            :operation operation)
               (sbcl-agent::remember-turn-outcome-memory session
                                                         thread
                                                         turn
                                                         prompt
                                                         (sbcl-agent::make-cognition-bundle
                                                          :retrieval-dossier '(:intent (:category :runtime-debugging
                                                                                  :domains (:runtime :incident :workflow)
                                                                                  :governance-context-p t))
                                                          :execution-strategy '(:mode :historically-cautious)
                                                          :validation-strategy '(:mode :required)
                                                          :action-agenda '(:primary-step (:kind :collect-evidence))
                                                          :prior-outcome-brief '(:reuse-recommendation :reuse-with-caution))
                                                         "Failure path."))))
      (record-failure "Investigate the runtime incident and recover safely." "Incident repeated during runtime recovery.")
      (record-failure "Investigate the runtime incident before patching." "Runtime incident repeated during patch planning."))
    (let* ((clusters (remove-if-not #'sbcl-agent::environment-memory-failure-cluster-entry-p
                                    (sbcl-agent::environment-memory environment)))
           (cluster (first clusters)))
      (assert-true (> (length clusters) 0)
                   "repeated failures should synthesize a durable failure cluster")
      (assert-true (> (or (getf cluster :failure-count) 0) 1)
                   "failure clusters should aggregate repeated failures")
      (assert-true (stringp (getf cluster :guidance))
                   "failure clusters should provide recurring guidance")
      (assert-true (> (length (or (getf cluster :improvement-proposals) '())) 0)
                   "failure clusters should surface improvement proposals"))))

(defun fresh-session-self-improvement-brief-test ()
  (let* ((session (make-test-session :cwd "/tmp/fresh-session-self-improvement/"))
         (environment (sbcl-agent::make-default-environment :session session
                                                            :storage-root "/tmp/fresh-session-self-improvement/")))
    (sbcl-agent::bind-session-to-environment session environment)
    (setf (sbcl-agent::environment-memory environment)
          (list
           (list :kind :failure-cluster
                 :memory-id "cluster-runtime-incidents"
                 :cluster-key "cluster-runtime-incidents"
                 :title "runtime-debugging / incidents=yes / weak-grounding=no"
                 :retrieval-category :runtime-debugging
                 :failure-count 3
                 :guidance "Inspect incident evidence and recovery history before repeating this path."
                 :sample-prompts '("Investigate the runtime incident and recover safely.")
                 :improvement-proposals
                 '((:kind :incident-preflight
                    :statement "Add incident-aware preflight checks before mutating along this path.")
                   (:kind :workflow-visibility
                    :statement "Surface workflow state earlier so blocked or validation-heavy paths are obvious before execution.")))))
    (let* ((fresh-session (make-test-session :cwd "/tmp/fresh-session-self-improvement/")))
      (sbcl-agent::bind-session-to-environment fresh-session environment)
      (let ((brief (sbcl-agent::build-prior-outcome-brief
                    fresh-session
                    "Investigate the runtime incident and recover safely."
                    :current-turn-id nil)))
        (assert-true (> (or (getf brief :failure-cluster-count) 0) 0)
                     "fresh bound sessions should recover durable failure clusters")
        (assert-true (> (length (or (getf brief :improvement-proposals) '())) 0)
                     "fresh bound sessions should surface self-improvement proposals from recurring failures")
        (assert-equal :incident-preflight
                      (getf (first (getf brief :improvement-proposals)) :kind)
                      "self-improvement proposals should preserve their actionable kind")))))

(defun evaluation-report-memory-recording-test ()
  (let* ((session (make-test-session :cwd "/tmp/evaluation-report-memory/"))
         (environment (sbcl-agent::make-default-environment :session session
                                                            :storage-root "/tmp/evaluation-report-memory/"))
         (report '(:generated-at 12345
                   :family-count 7
                   :implemented-family-count 7
                   :passed-family-count 6
                   :implemented-score 0.86
                   :results ((:family-id :parallel-orchestration
                              :label "Parallel Orchestration"
                              :description "Coordinated multi-worker execution tasks."
                              :status :failed
                              :score 0.0
                              :duration-seconds 15.0
                              :notes "Timed out waiting for condition")))))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::remember-evaluation-report-memory session report)
    (let* ((entries (sbcl-agent::environment-memory environment))
           (run-entry (find :evaluation-run entries
                            :key (lambda (entry) (getf entry :kind))
                            :test #'eq))
           (failure-entry (find :evaluation-failure entries
                                :key (lambda (entry) (getf entry :kind))
                                :test #'eq)))
      (assert-true run-entry
                   "remember-evaluation-report-memory should persist an evaluation-run entry")
      (assert-true failure-entry
                   "remember-evaluation-report-memory should persist failed family entries")
      (assert-equal :parallel-orchestration
                    (getf failure-entry :family-id)
                    "failed family entries should preserve the evaluation family id")
      (assert-true (> (length (or (getf failure-entry :improvement-proposals) '())) 0)
                   "failed family entries should carry concrete improvement proposals"))))

(defun evaluation-failure-self-improvement-brief-test ()
  (let* ((session (make-test-session :cwd "/tmp/evaluation-failure-self-improvement/"))
         (environment (sbcl-agent::make-default-environment :session session
                                                            :storage-root "/tmp/evaluation-failure-self-improvement/")))
    (sbcl-agent::bind-session-to-environment session environment)
    (setf (sbcl-agent::environment-memory environment)
          (list
           (list :kind :evaluation-failure
                 :memory-id "evaluation-failure-parallel"
                 :recorded-at 12345
                 :family-id :parallel-orchestration
                 :label "Parallel Orchestration"
                 :description "Coordinated multi-worker execution tasks."
                 :status :failed
                 :score 0.0
                 :notes "Timed out waiting for condition"
                 :improvement-proposals
                 '((:kind :parallel-execution-hardening
                    :statement "Harden multi-worker execution against contention, scheduling drift, and timeout-sensitive orchestration paths.")))))
    (let ((brief (sbcl-agent::build-prior-outcome-brief
                  session
                  "How should the agent improve its engineering quality and orchestration capability?"
                  :current-turn-id nil)))
      (assert-true (> (or (getf brief :evaluation-failure-count) 0) 0)
                   "self-improvement prompts should surface relevant evaluation failure memory")
      (assert-true (> (length (or (getf brief :improvement-proposals) '())) 0)
                   "evaluation failures should contribute actionable improvement proposals")
      (assert-equal :parallel-execution-hardening
                    (getf (first (getf brief :improvement-proposals)) :kind)
                    "evaluation-derived improvement proposals should preserve their actionable kind"))))

(defun governed-turn-persists-long-horizon-plan-test ()
  (let* ((provider (make-instance 'patch-action-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/governed-turn-long-horizon/")))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare governed patch"))
     provider
     session)
    (let* ((turn (sbcl-agent::most-recent-thread-turn session))
           (work-item-id (getf (sbcl-agent::turn-metadata turn) :work-item-id))
           (work-item (sbcl-agent::find-work-item session work-item-id))
           (summary (sbcl-agent::work-item-summary work-item))
           (plan (getf summary :long-horizon-plan)))
      (assert-true work-item
                   "governed turns should still create a bound work-item")
      (assert-true (listp plan)
                   "governed work-items should persist a durable long-horizon plan")
      (assert-true (> (or (getf plan :agenda-step-count) 0) 0)
                   "long-horizon plan should carry the action agenda step count")
      (assert-true (listp (getf summary :resume-payload))
                   "governed work-items should expose a resume payload")
      (assert-true (listp (getf (getf summary :resume-payload) :long-horizon-plan))
                   "resume payload should carry the durable long-horizon plan")
      (assert-equal :resumable
                    (getf summary :plan-health)
                    "approval-gated governed work should surface resumable plan health through the durable control payload"))))

(defun long-horizon-resume-payload-flow-test ()
  (let* ((provider (make-instance 'followup-patch-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/long-horizon-resume-flow/")))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare patch and continue"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :workspace-write))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (let* ((turn (sbcl-agent::most-recent-thread-turn session))
           (work-item-id (getf (sbcl-agent::turn-metadata turn) :work-item-id))
           (work-item (sbcl-agent::find-work-item session work-item-id))
           (summary (sbcl-agent::work-item-summary work-item)))
      (assert-true (listp (getf summary :long-horizon-plan))
                   "long-horizon flow should preserve the durable plan after resume")
      (assert-true (member (getf summary :plan-health) '(:active :resumable :waiting) :test #'eq)
                   "long-horizon flow should surface a valid plan-health state")
      (assert-true (listp (getf summary :plan-steering))
                   "long-horizon flow should surface a steering snapshot alongside the durable plan")
      (assert-true (or (null (getf summary :resume-payload))
                       (listp (getf (getf summary :resume-payload) :long-horizon-plan)))
                   "any remaining resume payload should preserve the durable long-horizon plan"))))

(defun long-horizon-plan-steering-test ()
  (let* ((provider (make-instance 'patch-action-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/long-horizon-plan-steering/")))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare governed patch"))
     provider
     session)
    (let* ((turn (sbcl-agent::most-recent-thread-turn session))
           (work-item-id (getf (sbcl-agent::turn-metadata turn) :work-item-id))
           (work-item (sbcl-agent::find-work-item session work-item-id))
           (summary (sbcl-agent::work-item-summary work-item))
           (steering (getf summary :plan-steering)))
      (assert-true (listp steering)
                   "approval-gated governed work should expose a plan steering snapshot")
      (assert-equal :resolve-blockers
                    (getf steering :current-phase)
                    "approval-gated governed work should steer the plan toward blocker resolution")
      (assert-equal :blocked-awaiting-resume
                    (getf steering :revision-reason)
                    "approval-gated governed work should report a blocked-awaiting-resume revision reason")
      (assert-true (> (or (getf steering :phase-count) 0) 0)
                   "plan steering should preserve the long-horizon decomposition size"))))

(defun long-horizon-validation-revision-test ()
  (let* ((provider (make-instance 'mutating-eval-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/long-horizon-validation-revision/")))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "mutate runtime safely"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (let* ((turn (sbcl-agent::most-recent-thread-turn session))
           (work-item-id (getf (sbcl-agent::turn-metadata turn) :work-item-id))
           (work-item (sbcl-agent::find-work-item session work-item-id))
           (steering (getf (sbcl-agent::work-item-summary work-item) :plan-steering)))
      (assert-equal :awaiting-cold-validation
                    (sbcl-agent::work-item-status work-item)
                    "mutating runtime work should remain validation-gated")
      (assert-equal :validation-pending
                    (getf steering :revision-reason)
                    "validation-gated work should revise the long-horizon plan toward validation")
      (assert-equal :validate
                    (getf steering :current-phase)
                    "validation-gated work should shift the current phase to validate")
      (assert-true (getf steering :compacted-p)
                   "validation-gated work should compact earlier phases from the remaining plan")
      (assert-true (member :validate (getf steering :remaining-phases) :test #'eq)
                   "validation-gated work should preserve validate in the remaining phase set"))))

(defun long-horizon-incident-revision-test ()
  (let* ((provider (make-instance 'failing-mutating-eval-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/long-horizon-incident-revision/")))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "mutate runtime and fail"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :runtime-eval-mutate))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(turn/resume))
     provider
     session)
    (let* ((turn (sbcl-agent::most-recent-thread-turn session))
           (work-item-id (getf (sbcl-agent::turn-metadata turn) :work-item-id))
           (work-item (sbcl-agent::find-work-item session work-item-id))
           (steering (getf (sbcl-agent::work-item-summary work-item) :plan-steering)))
      (assert-equal :quarantined
                    (sbcl-agent::work-item-status work-item)
                    "failing governed runtime work should become quarantined")
      (assert-equal :incident-recovery
                    (getf steering :revision-reason)
                    "quarantined work should revise the long-horizon plan toward incident recovery")
      (assert-equal :resolve-blockers
                    (getf steering :current-phase)
                    "quarantined work should steer back to blocker resolution")
      (assert-true (getf steering :compacted-p)
                   "incident recovery should compact already-completed phases out of the remaining plan"))))

(defun durable-decomposition-playbook-synthesis-test ()
  (let* ((session (make-test-session :cwd "/tmp/durable-decomposition-playbook/"))
         (environment (sbcl-agent::make-default-environment :session session
                                                            :storage-root "/tmp/durable-decomposition-playbook/"))
         (provider (make-instance 'patch-action-provider)))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare governed patch"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare governed patch again"))
     provider
     session)
    (let* ((playbooks (remove-if-not #'sbcl-agent::environment-memory-decomposition-playbook-entry-p
                                     (sbcl-agent::environment-memory environment)))
           (playbook (first playbooks)))
      (assert-true (> (length playbooks) 0)
                   "repeated governed long-horizon outcomes should synthesize decomposition playbooks")
      (assert-true (getf playbook :decomposition-pattern-p)
                   "decomposition playbooks should be explicitly marked")
      (assert-true (> (or (getf playbook :phase-count) 0) 0)
                   "decomposition playbooks should preserve the learned phase count")
      (assert-true (listp (getf playbook :planning-phases))
                   "decomposition playbooks should preserve the learned planning phases"))))

(defun decomposition-playbook-reuse-test ()
  (let* ((session-one (make-test-session :cwd "/tmp/decomposition-playbook-reuse/"))
         (environment (sbcl-agent::make-default-environment :session session-one
                                                            :storage-root "/tmp/decomposition-playbook-reuse/"))
         (provider (make-instance 'patch-action-provider)))
    (sbcl-agent::bind-session-to-environment session-one environment)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare governed patch"))
     provider
     session-one)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare governed patch again"))
     provider
     session-one)
    (let ((session-two (make-test-session :cwd "/tmp/decomposition-playbook-reuse/")))
      (sbcl-agent::bind-session-to-environment session-two environment)
      (let* ((brief (sbcl-agent::build-prior-outcome-brief
                     session-two
                     "Prepare a governed patch with resumable validation."
                     :current-turn-id nil))
             (playbook (first (getf brief :playbooks)))
             (dossier (sbcl-agent::service-response-data
                       (sbcl-agent::query-retrieval-dossier-service
                        session-two
                        "Prepare a governed patch with resumable validation."
                        :operator-mode :conversation)))
             (bundle (sbcl-agent::build-cognition-bundle
                      "Prepare a governed patch with resumable validation."
                      (sbcl-agent::provider-session-summary session-two)
                      (sbcl-agent::provider-environment-context session-two)
                      dossier
                      :session session-two))
             (agenda (sbcl-agent::cognition-bundle-action-agenda bundle)))
        (assert-true (or (getf playbook :decomposition-pattern-p)
                         (find-if (lambda (candidate)
                                    (getf candidate :decomposition-pattern-p))
                                  (getf brief :playbooks)))
                     "decomposition reuse should surface a learned long-horizon pattern in the playbook set")
        (assert-true (find :reuse-decomposition
                           (getf agenda :steps)
                           :key (lambda (step) (getf step :kind))
                           :test #'eq)
                     "the default cognition loop should surface decomposition reuse guidance in the action agenda")))))

(defun parallel-orchestration-group-metadata-test ()
  (let* ((session (make-test-session :cwd "/tmp/parallel-orchestration-group/"))
         (command-a (sbcl-agent::normalize-form-command '(say "parallel task a")))
         (command-b (sbcl-agent::normalize-form-command '(say "parallel task b")))
         (tasks (sbcl-agent::enqueue-parallel-task-group
                 session
                 (list (list :command command-a :ownership-scope '("src/a.lisp"))
                       (list :command command-b :ownership-scope '("src/b.lisp")))
                 :shared-context '(:goal "parallel patch set")
                 :merge-policy :serial-review))
         (group-id (sbcl-agent::task-orchestration-group-id (first tasks))))
    (assert-true (every (lambda (task)
                          (string= group-id (sbcl-agent::task-orchestration-group-id task)))
                        tasks)
                 "parallel task groups should stamp a shared orchestration group id")
    (assert-true (every (lambda (task)
                          (eq :serial-review (sbcl-agent::task-merge-policy task)))
                        tasks)
                 "parallel task groups should stamp a shared merge policy")
    (let* ((work-items (mapcar (lambda (task)
                                 (sbcl-agent::find-work-item session (sbcl-agent::task-work-item-id task)))
                               tasks))
           (intents (mapcar #'sbcl-agent::work-item-mutation-intent work-items)))
      (assert-true (every (lambda (intent)
                            (string= group-id (getf intent :orchestration-group-id)))
                          intents)
                   "parallel task group work-items should preserve orchestration-group linkage")
      (assert-true (equal '(:goal "parallel patch set")
                          (getf (first intents) :shared-context))
                   "parallel task group work-items should preserve shared context"))))

(defun parallel-orchestration-worker-flow-test ()
  (let* ((provider (make-instance 'slow-test-provider))
         (session (make-test-session :cwd "/tmp/parallel-orchestration-worker-flow/"))
         (command-a (sbcl-agent::normalize-form-command '(say "parallel task a")))
         (command-b (sbcl-agent::normalize-form-command '(say "parallel task b")))
         (tasks (sbcl-agent::enqueue-parallel-task-group
                 session
                 (list (list :command command-a :ownership-scope '("src/a.lisp"))
                       (list :command command-b :ownership-scope '("src/b.lisp")))
                 :shared-context '(:goal "parallel patch set")
                 :merge-policy :serial-review)))
    (sbcl-agent::start-worker session provider)
    (sbcl-agent::start-worker session provider)
    (wait-for (lambda ()
                (every (lambda (task)
                         (eq :completed (sbcl-agent::task-status task)))
                       tasks))
              :timeout-seconds 30.0
              :sleep-seconds 0.05)
    (let* ((group-id (sbcl-agent::task-orchestration-group-id (first tasks)))
           (worker-ids (remove-duplicates (mapcar #'sbcl-agent::task-worker-id tasks) :test #'string=))
           (summaries (mapcar #'sbcl-agent::task-summary tasks)))
      (assert-true (= 2 (length worker-ids))
                   "parallel orchestration should distribute grouped tasks across multiple workers in the happy path")
      (assert-true (every (lambda (summary)
                            (string= group-id (getf (getf summary :orchestration) :group-id)))
                          summaries)
                   "parallel orchestration summaries should preserve the shared group id")
      (assert-true (every (lambda (summary)
                            (eq :serial-review (getf (getf summary :orchestration) :merge-policy)))
                          summaries)
                   "parallel orchestration summaries should preserve merge policy"))
    (sbcl-agent::stop-all-workers session)))

(defun parallel-orchestration-review-posture-test ()
  (let* ((provider (make-test-provider))
         (session (make-test-session :cwd "/tmp/parallel-orchestration-review-posture/"))
         (tasks (sbcl-agent::enqueue-parallel-task-group
                 session
                 (list (list :command (sbcl-agent::normalize-form-command '(say "parallel review task a"))
                             :ownership-scope '("src/review-a.lisp"))
                       (list :command (sbcl-agent::normalize-form-command '(say "parallel review task b"))
                             :ownership-scope '("src/review-b.lisp")))
                 :shared-context '(:goal "parallel review patch set")
                 :merge-policy :serial-review)))
    (sbcl-agent::run-next-task session provider)
    (sbcl-agent::run-next-task session provider)
    (dolist (task tasks)
      (let* ((work-item (sbcl-agent::find-work-item session (sbcl-agent::task-work-item-id task)))
             (summary (sbcl-agent::work-item-summary work-item))
             (next-action (getf summary :next-action))
             (resume-payload (getf summary :resume-payload)))
        (assert-equal :serial-review-merge
                      (getf next-action :type)
                      "serial-review groups should surface a governed review next-action after execution")
        (assert-equal :review-orchestration-group
                      (getf resume-payload :resume-command)
                      "serial-review groups should preserve a review-oriented resume payload")
        (assert-equal :serial-review
                      (getf resume-payload :merge-policy)
                      "serial-review groups should preserve merge policy in the review payload")))))

(defun orchestration-playbook-reuse-test ()
  (let* ((provider (make-instance 'slow-test-provider))
         (session-one (make-test-session :cwd "/tmp/orchestration-playbook-reuse/"))
         (environment (sbcl-agent::make-default-environment :session session-one
                                                            :storage-root "/tmp/orchestration-playbook-reuse/")))
    (sbcl-agent::bind-session-to-environment session-one environment)
    (let ((tasks (sbcl-agent::enqueue-parallel-task-group
                  session-one
                  (list (list :command (sbcl-agent::normalize-form-command '(say "parallel reuse task a"))
                              :ownership-scope '("src/reuse-a.lisp"))
                        (list :command (sbcl-agent::normalize-form-command '(say "parallel reuse task b"))
                              :ownership-scope '("src/reuse-b.lisp")))
                  :shared-context '(:goal "parallel reuse patch set")
                  :merge-policy :serial-review)))
      (sbcl-agent::start-worker session-one provider)
      (sbcl-agent::start-worker session-one provider)
      (unwind-protect
           (progn
             (wait-for (lambda ()
                         (every (lambda (task)
                                  (eq :completed (sbcl-agent::task-status task)))
                                tasks))
                       :timeout-seconds 30.0
                       :sleep-seconds 0.05))
        (sbcl-agent::stop-all-workers session-one)))
    (let* ((session-two (make-test-session :cwd "/tmp/orchestration-playbook-reuse/")))
      (sbcl-agent::bind-session-to-environment session-two environment)
      (let* ((brief (sbcl-agent::build-prior-outcome-brief
                     session-two
                     "Plan a parallel patch set with explicit ownership and merge review."
                     :current-turn-id nil))
             (playbook (first (getf brief :playbooks)))
             (dossier (sbcl-agent::service-response-data
                       (sbcl-agent::query-retrieval-dossier-service
                        session-two
                        "Plan a parallel patch set with explicit ownership and merge review."
                        :operator-mode :conversation)))
             (bundle (sbcl-agent::build-cognition-bundle
                      "Plan a parallel patch set with explicit ownership and merge review."
                      (sbcl-agent::provider-session-summary session-two)
                      (sbcl-agent::provider-environment-context session-two)
                      dossier
                      :session session-two))
             (agenda (sbcl-agent::cognition-bundle-action-agenda bundle)))
        (assert-true (> (or (getf brief :playbook-count) 0) 0)
                     "parallel orchestration outcomes should become reusable playbooks")
        (assert-true (getf playbook :orchestration-pattern-p)
                     "the preferred playbook should identify the orchestration reuse pattern")
        (assert-equal :serial-review
                      (getf playbook :merge-policy)
                      "orchestration playbooks should preserve merge policy guidance")
        (assert-true (find :review-orchestration
                           (getf agenda :steps)
                           :key (lambda (step) (getf step :kind))
                           :test #'eq)
                     "the default cognition loop should surface orchestration reuse guidance in the action agenda")))))

(defun cautious-execution-strategy-grounding-test ()
  (let* ((session (make-test-session :cwd "/tmp/cautious-execution-strategy/"))
         (thread (sbcl-agent::current-thread session)))
    (flet ((record-turn (prompt reply &key (status :completed) incident-summary)
             (let* ((user-message (sbcl-agent::create-message session thread :user prompt))
                    (turn (sbcl-agent::start-turn session thread user-message
                                                  :metadata '(:source :test)))
                    (assistant-message (sbcl-agent::create-message session thread :assistant reply))
                    (operation (sbcl-agent::start-operation session
                                                            thread
                                                            turn
                                                            :provider-run
                                                            "mock"
                                                            (list :prompt prompt)
                                                            :policy-decision
                                                            (sbcl-agent::mutation-policy-decision-summary
                                                             :safe-read
                                                             :decision :allowed
                                                             :reason "test"))))
               (sbcl-agent::complete-operation session
                                              thread
                                              turn
                                              operation
                                              (list :message reply)
                                              :status (if (eq status :completed) :completed :failed))
               (sbcl-agent::complete-turn session thread turn assistant-message :status status)
               (when incident-summary
                 (sbcl-agent::create-incident session
                                              :runtime-eval-failure
                                              "Similar prior failure"
                                              incident-summary
                                              :thread thread
                                              :turn turn
                                              :operation operation))
               turn)))
      (record-turn "Implement the runtime patch but it crashes." "Earlier failure path."
                   :status :failed
                   :incident-summary "Patch crashed during runtime mutation."))
    (let* ((dossier (sbcl-agent::service-response-data
                     (sbcl-agent::query-retrieval-dossier-service
                      session
                      "Implement the runtime patch and validate the fix."
                      :operator-mode :conversation)))
           (bundle (sbcl-agent::build-cognition-bundle
                    "Implement the runtime patch and validate the fix."
                    (sbcl-agent::provider-session-summary session)
                    (sbcl-agent::provider-environment-context session)
                    dossier
                    :session session))
           (execution-strategy (sbcl-agent::cognition-bundle-execution-strategy bundle)))
      (assert-equal :historically-cautious
                    (getf execution-strategy :mode)
                    "execution strategy should become historically cautious when similar failures exist")
      (assert-equal :collect-evidence
                    (getf execution-strategy :next-step)
                    "execution strategy should bias toward evidence before mutation when prior similar work failed")
      (assert-true (getf execution-strategy :history-caution-p)
                   "execution strategy should record when historical caution is active"))))

(defun retrieval-aware-turn-flow-test ()
  (let* ((session (make-test-session :cwd "/tmp/retrieval-aware-turn-flow/"))
         (provider (make-test-provider))
         (thread (sbcl-agent::current-thread session)))
    (let* ((prior-user (sbcl-agent::create-message session thread :user "Inspect the runtime and summarize the current code context."))
           (prior-turn (sbcl-agent::start-turn session thread prior-user :metadata '(:source :test)))
           (prior-assistant (sbcl-agent::create-message session thread :assistant "Earlier completed runtime inspection."))
           (prior-operation (sbcl-agent::start-operation session
                                                         thread
                                                         prior-turn
                                                         :provider-run
                                                         "mock"
                                                         (list :prompt "Inspect the runtime and summarize the current code context.")
                                                         :policy-decision
                                                         (sbcl-agent::mutation-policy-decision-summary
                                                          :safe-read
                                                          :decision :allowed
                                                          :reason "test"))))
      (sbcl-agent::complete-operation session thread prior-turn prior-operation
                                      (list :message "Earlier completed runtime inspection.")
                                      :status :completed)
      (sbcl-agent::complete-turn session thread prior-turn prior-assistant :status :completed))
    (let* (
         (result (sbcl-agent::run-conversation-turn provider
                                                    session
                                                    "Inspect the runtime and summarize the current code context."
                                                    :stream-p nil
                                                    :source :say
                                                    :operator-mode :conversation))
         (retrieval-summary (getf result :retrieval-summary))
         (cognition-summary (getf result :cognition-summary))
         (reasoning-summary (getf result :reasoning-summary))
         (planning-summary (getf result :planning-summary))
         (cognition-event (find :cognition-bundle
                                (sbcl-agent::agent-session-events session)
                                :key #'sbcl-agent::event-kind))
         (retrieval-event (find :retrieval-dossier
                                (sbcl-agent::agent-session-events session)
                                :key #'sbcl-agent::event-kind))
         (reasoning-event (find :reasoning-brief
                                (sbcl-agent::agent-session-events session)
                                :key #'sbcl-agent::event-kind))
         (planning-event (find :planning-brief
                               (sbcl-agent::agent-session-events session)
                               :key #'sbcl-agent::event-kind)))
    (assert-true (listp retrieval-summary)
                 "turn flow should surface a retrieval summary in the turn result")
    (assert-true (listp cognition-summary)
                 "turn flow should surface a cognition summary in the turn result")
    (assert-true (listp (getf result :action-agenda-summary))
                 "turn flow should surface an action agenda summary in the turn result")
    (assert-true (listp reasoning-summary)
                 "turn flow should surface a reasoning summary in the turn result")
    (assert-true (listp planning-summary)
                 "turn flow should surface a planning summary in the turn result")
    (assert-true (find :runtime (getf retrieval-summary :domains))
                 "retrieval-aware turn flow should include runtime retrieval when prompted")
    (assert-equal :inspection-first
                  (getf cognition-summary :execution-mode)
                  "cognition summary should expose the execution strategy")
    (assert-equal :opportunistic
                  (getf cognition-summary :validation-mode)
                  "cognition summary should expose the validation strategy")
    (assert-true (> (or (getf (getf result :action-agenda-summary) :step-count) 0) 0)
                 "action agenda summary should expose ordered next steps")
    (assert-true (> (or (getf cognition-summary :prior-success-count) 0) 0)
                 "cognition summary should expose prior similar successes")
    (assert-equal :reuse-success-patterns
                  (getf cognition-summary :reuse-recommendation)
                  "cognition summary should surface prior-outcome reuse guidance")
    (assert-true cognition-event
                 "turn flow should record a cognition-bundle event before provider execution")
    (assert-true retrieval-event
                 "turn flow should record a retrieval-dossier event before provider execution")
    (assert-true reasoning-event
                 "turn flow should record a reasoning-brief event before provider execution")
    (assert-true planning-event
                 "turn flow should record a planning-brief event before provider execution")
    (assert-equal :retrieval
                  (sbcl-agent::event-family cognition-event)
                  "cognition-bundle events should use the retrieval family")
    (assert-equal :retrieval
                  (sbcl-agent::event-family retrieval-event)
                  "retrieval-dossier events should use the retrieval family")
    (assert-equal :retrieval
                  (sbcl-agent::event-family reasoning-event)
                  "reasoning-brief events should use the retrieval family")
    (assert-equal :retrieval
                  (sbcl-agent::event-family planning-event)
                  "planning-brief events should use the retrieval family")
    (assert-true (listp (sbcl-agent::event-payload cognition-event))
                 "cognition-bundle event payload should carry the canonical cognition data")
    (assert-true (listp (getf (sbcl-agent::event-payload cognition-event) :prior-outcome-brief))
                 "cognition-bundle event payload should carry prior-outcome reuse data")
    (assert-true (listp (sbcl-agent::event-payload retrieval-event))
                 "retrieval-dossier event payload should carry the dossier data")
    (assert-true (listp (sbcl-agent::event-payload reasoning-event))
                 "reasoning-brief event payload should carry the reasoning data")
    (assert-true (listp (sbcl-agent::event-payload planning-event))
                 "planning-brief event payload should carry the planning data"))))

(defun post-mutation-retrieval-dossier-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/post-mutation-retrieval-dossier/"))
         (action-results (list (list :action (sbcl-agent::make-assistant-action
                                              :type :patch
                                              :payload '((:write "tmp/generated.txt" "hello")))
                                     :status :completed
                                     :result '(:patch ((:path "/tmp/post-mutation-retrieval-dossier/tmp/generated.txt"))))))
         (response (sbcl-agent::query-post-mutation-retrieval-dossier-service
                    session
                    "apply a patch and validate the result"
                    action-results
                    :operator-mode :conversation))
         (payload (sbcl-agent::service-response-data response)))
    (assert-equal :retrieval
                  (getf response :domain)
                  "post-mutation retrieval should report the retrieval domain")
    (assert-equal :post-mutation
                  (getf payload :phase)
                  "post-mutation retrieval should mark the dossier phase explicitly")
    (assert-true (find :workspace (getf (getf payload :intent) :domains))
                 "patch outcomes should widen the retrieval domains to workspace state")
    (assert-true (> (length (or (getf payload :observed-consequences) '())) 0)
                 "post-mutation retrieval should include observed mutation consequences")))
