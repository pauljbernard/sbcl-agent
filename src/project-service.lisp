(in-package #:sbcl-agent)

(defun service-project-linked-work-item-summary (session work-item-id)
  (let ((work-item (find-work-item session work-item-id)))
    (and work-item
         (list :id (work-item-id work-item)
               :title (work-item-goal work-item)
               :status (work-item-status work-item)
               :workflow-record-id (work-item-workflow-record-ref work-item)
               :pending-validations (copy-list (or (work-item-pending-validations work-item) '()))
               :source-mutation-count
               (length
                (or (provenance-record-executed-mutations (work-item-provenance work-item)) '()))))))

(defun service-project-linked-incident-summary (session incident-id)
  (let ((incident (find-incident session incident-id)))
    (and incident
         (list :id (incident-id incident)
               :title (incident-title incident)
               :summary (incident-summary incident)
               :status (incident-status incident)
               :kind (incident-kind incident)
               :work-item-id (incident-work-item-id incident)
               :workflow-record-id (incident-workflow-record-id incident)))))

(defun service-project-testing-harness-summaries (project)
  (let ((linked-ids (or (project-record-linked-testing-harness-ids project) '())))
    (mapcar (lambda (entry)
              (list :id (getf entry :id)
                    :label (getf entry :label)
                    :entrypoint (getf entry :entrypoint)
                    :kind (getf entry :kind)
                    :categories (copy-list (or (getf entry :categories) '()))))
            (remove-if-not (lambda (entry)
                             (find (getf entry :id) linked-ids :test #'eq))
                           (testing-harness-inventory)))))

(defun project-quality-gate-payload (gate)
  (list :id (project-quality-gate-id gate)
        :title (project-quality-gate-title gate)
        :summary (project-quality-gate-summary gate)
        :status (project-quality-gate-status gate)
        :required-harness-ids (copy-list (or (project-quality-gate-required-harness-ids gate) '()))
        :minimum-linked-work-items (or (project-quality-gate-minimum-linked-work-items gate) 0)
        :minimum-linked-incidents (or (project-quality-gate-minimum-linked-incidents gate) 0)
        :require-source-roots-p (not (null (project-quality-gate-require-source-roots-p gate)))
        :required-trace-target-kinds (copy-list (or (project-quality-gate-required-trace-target-kinds gate) '()))
        :maximum-failed-tests (project-quality-gate-maximum-failed-tests gate)
        :require-coverage-p (not (null (project-quality-gate-require-coverage-p gate)))
        :maximum-say-turn-latency-seconds (project-quality-gate-maximum-say-turn-latency-seconds gate)
        :maximum-environment-save-load-seconds (project-quality-gate-maximum-environment-save-load-seconds gate)
        :require-recovery-ready-p (not (null (project-quality-gate-require-recovery-ready-p gate)))
        :metadata (copy-list (or (project-quality-gate-metadata gate) '()))))

(defun project-quality-gate-testing-evidence ()
  (or (project-testing-evidence-summary)
      (list :latest-report nil
            :coverage (list :present-p nil)
            :performance nil)))

(defun testing-evidence-kind-present-p (testing-evidence evidence-kind)
  (let ((coverage (or (getf testing-evidence :coverage) '()))
        (performance (or (getf testing-evidence :performance) '()))
        (latest-report (or (getf testing-evidence :latest-report) '())))
    (case evidence-kind
      ((:coverage "coverage") (not (null (getf coverage :present-p))))
      ((:performance "performance") (not (null performance)))
      ((:latency "latency")
       (or (getf performance :say-turn-latency)
           (getf performance :environment-save-load)))
      ((:latest-report "latest-report") (not (null latest-report)))
      ((:governed-approval "governed-approval")
       (not (null (and sbcl-agent::*current-session*
                       (agent-session-pending-actions sbcl-agent::*current-session*)))))
      (otherwise nil))))

(defun normalize-testing-evidence-kind-label (value)
  (etypecase value
    (keyword (string-downcase (symbol-name value)))
    (string (string-downcase value))))

(defun project-testing-suite-statuses (project testing-strategy testing-evidence)
  (let ((linked-harness-ids (or (project-record-linked-testing-harness-ids project) '()))
        (suite-expectations (or (getf testing-strategy :suite-expectations) '())))
    (mapcar
     (lambda (entry)
       (let* ((harness-id (getf entry :harness-id))
              (purpose (getf entry :purpose))
              (evidence-kinds (mapcar #'normalize-testing-evidence-kind-label
                                      (or (getf entry :evidence-kinds) '())))
              (satisfied (remove-if-not
                          (lambda (kind)
                            (testing-evidence-kind-present-p testing-evidence kind))
                          evidence-kinds))
              (missing (set-difference evidence-kinds satisfied :test #'string=))
              (linked-p (find harness-id linked-harness-ids :test #'equal)))
         (list :harness-id harness-id
               :purpose purpose
               :linked-p (not (null linked-p))
               :evidence-kinds evidence-kinds
               :satisfied-evidence-kinds satisfied
               :missing-evidence-kinds missing
               :status (if (and linked-p (null missing)) :ready :blocked))))
     suite-expectations)))

(defun project-testing-evidence-status-summary (testing-strategy testing-evidence)
  (let* ((required-evidence (mapcar #'normalize-testing-evidence-kind-label
                                    (or (getf testing-strategy :required-evidence) '())))
         (available (remove-if-not
                     (lambda (kind)
                       (testing-evidence-kind-present-p testing-evidence kind))
                     required-evidence))
         (missing (set-difference required-evidence available :test #'string=)))
    (list :required-evidence required-evidence
          :available-evidence available
          :missing-evidence missing
          :status (if (null missing) :ready :blocked))))

(defun project-quality-gate-recovery-summary (session)
  (let* ((environment (or (and session (session-bound-environment session))
                          (ensure-environment)))
         (status-response (query-environment-status-service environment
                                                            :include-alignment-state-p nil
                                                            :include-reconciliation-decision-p nil))
         (status-data (service-response-data status-response)))
    (or (getf status-data :recovery)
        (environment-recovery-report environment)
        (list :recovery-valid-p t :status :steady))))

(defun readiness-obligation-ready-p (status)
  (let ((normalized (typecase status
                      (keyword (string-downcase (symbol-name status)))
                      (string (string-downcase status))
                      (t ""))))
    (member normalized '("ready" "complete" "completed" "satisfied" "closed" "approved" "done")
            :test #'string=)))

(defun project-readiness-obligation-summary (readiness-obligations)
  (let* ((obligations (or readiness-obligations '()))
         (ready-obligations
           (remove-if-not (lambda (entry)
                            (readiness-obligation-ready-p (getf entry :status)))
                          obligations))
         (blocked-obligations
           (remove-if (lambda (entry)
                        (or (not (getf entry :blocking-p))
                            (readiness-obligation-ready-p (getf entry :status))))
                      obligations)))
    (list :obligations (copy-list obligations)
          :obligation-count (length obligations)
          :ready-count (length ready-obligations)
          :blocked-count (length blocked-obligations)
          :blocked-obligations (copy-list blocked-obligations))))

(defun release-readiness-blocked-p (release-readiness)
  (let* ((release-stage (getf release-readiness :stage))
         (signoff-status (getf release-readiness :signoff-status))
         (required-approvers (or (getf release-readiness :required-approvers) '())))
    (and (or release-stage signoff-status required-approvers)
         (not (readiness-obligation-ready-p signoff-status)))))

(defun release-readiness-present-p (release-readiness)
  (let ((required-approvers (or (getf release-readiness :required-approvers) '())))
    (or (getf release-readiness :stage)
        (getf release-readiness :signoff-status)
        required-approvers
        (getf release-readiness :target-window)
        (getf release-readiness :observation-plan)
        (getf release-readiness :open-risks))))

(defun normalize-release-stage-label (value)
  (typecase value
    (keyword (string-downcase (symbol-name value)))
    (string (string-downcase value))
    (t "")))

(defun normalize-approver-label (value)
  (string-downcase (string-trim '(#\Space #\Tab #\Newline)
                                (typecase value
                                  (string value)
                                  (symbol (symbol-name value))
                                  (t (princ-to-string value))))))

(defun project-release-signoff-summary (release-readiness readiness-obligations)
  (let* ((required-approvers
           (remove-if (lambda (value) (string= value ""))
                      (mapcar #'normalize-approver-label
                              (or (getf release-readiness :required-approvers) '()))))
         (obligations (or readiness-obligations '()))
         (owned-approvers
           (remove-duplicates
            (remove-if (lambda (value) (string= value ""))
                       (mapcar (lambda (entry)
                                 (normalize-approver-label (or (getf entry :owner) "")))
                               obligations))
            :test #'string=))
         (approved-approvers
           (remove-duplicates
            (remove nil
                    (mapcar (lambda (approver)
                              (and (find approver obligations
                                         :test (lambda (needle entry)
                                                 (and (string= needle
                                                               (normalize-approver-label
                                                                (or (getf entry :owner) "")))
                                                      (readiness-obligation-ready-p
                                                       (getf entry :status)))))
                                   approver))
                            required-approvers))
            :test #'string=))
         (pending-approvers (set-difference required-approvers approved-approvers :test #'string=))
         (unassigned-approvers (set-difference required-approvers owned-approvers :test #'string=))
         (ownership-ready-p (null unassigned-approvers))
         (all-approved-p (and required-approvers (null pending-approvers)))
         (signoff-status (getf release-readiness :signoff-status))
         (signoff-ready-p (if required-approvers
                              (and ownership-ready-p
                                   all-approved-p
                                   (readiness-obligation-ready-p signoff-status))
                              (readiness-obligation-ready-p signoff-status)))
         (signoff-state (cond
                          ((null required-approvers)
                           (if signoff-ready-p :complete :not-required))
                          (unassigned-approvers :ownership-pending)
                          (pending-approvers :approvals-pending)
                          (signoff-ready-p :complete)
                          (t :approvals-pending)))
         (summary (cond
                    ((eq signoff-state :not-required)
                     "No explicit release approvers are required for this project.")
                    ((eq signoff-state :ownership-pending)
                     (format nil "Assign owned readiness obligations for: ~{~A~^, ~}."
                             unassigned-approvers))
                    ((eq signoff-state :approvals-pending)
                     (format nil "Await final signoff from: ~{~A~^, ~}."
                             pending-approvers))
                    (t
                     "Required release approvers have completed signoff."))))
    (list :required-approvers required-approvers
          :approved-approvers approved-approvers
          :pending-approvers pending-approvers
          :unassigned-approvers unassigned-approvers
          :ownership-ready-p ownership-ready-p
          :all-approved-p all-approved-p
          :signoff-ready-p signoff-ready-p
          :signoff-state signoff-state
          :summary summary)))

(defun project-release-review-summary (testing-readiness gate-readiness recovery-ready-p
                                        suite-blocked-count release-readiness release-signoff-summary
                                        blocked-readiness-obligations)
  (let* ((release-stage (getf release-readiness :stage))
         (release-present-p (release-readiness-present-p release-readiness))
         (signoff-ready-p (not (null (getf release-signoff-summary :signoff-ready-p))))
         (signoff-state (or (getf release-signoff-summary :signoff-state) :not-started))
         (pending-approvers (or (getf release-signoff-summary :pending-approvers) '()))
         (unassigned-approvers (or (getf release-signoff-summary :unassigned-approvers) '()))
         (blocked-p (or (eq testing-readiness :blocked)
                        (eq gate-readiness :blocked)
                        (not recovery-ready-p)
                        (> suite-blocked-count 0)
                        unassigned-approvers
                        blocked-readiness-obligations))
         (actions '()))
    (cond
      ((not release-present-p)
       (push "Define release readiness before attempting governed closure." actions)
       (list :state :not-started
             :next-actions (nreverse actions)))
      (blocked-p
       (when (eq testing-readiness :blocked)
         (push "Satisfy project testing evidence requirements." actions))
       (when (> suite-blocked-count 0)
         (push "Clear blocked testing suite expectations." actions))
       (when (eq gate-readiness :blocked)
         (push "Clear blocked project quality gates." actions))
       (unless recovery-ready-p
         (push "Restore recovery-ready environment posture." actions))
       (when unassigned-approvers
         (push (format nil "Assign blocking readiness obligations to required approvers: ~{~A~^, ~}."
                       unassigned-approvers)
               actions))
       (when blocked-readiness-obligations
         (push "Resolve blocking readiness obligations." actions))
       (push "Do not request final release signoff until closure blockers are cleared." actions)
       (list :state :blocked
             :next-actions (nreverse actions)))
      ((and signoff-ready-p
            release-stage
            (string-equal (string-downcase (princ-to-string release-stage)) "released"))
       (push "Monitor post-release evidence and operational outcomes." actions)
       (list :state :released
             :next-actions (nreverse actions)))
      (signoff-ready-p
       (push "Promote the release stage when rollout approval is complete." actions)
       (list :state :approved
             :next-actions (nreverse actions)))
      (t
       (push (if pending-approvers
                 (format nil "Collect signoff from: ~{~A~^, ~}." pending-approvers)
                 "Complete required release signoff.")
             actions)
       (list :state :awaiting-signoff
             :signoff-state signoff-state
             :next-actions (nreverse actions))))))

(defun project-release-transition-summary (release-readiness release-review-summary)
  (let* ((release-stage (normalize-release-stage-label (getf release-readiness :stage)))
         (review-state (getf release-review-summary :state))
         (transition-ready-p (member review-state '(:approved :released) :test #'eq))
         (target-phase
           (cond
             ((string= release-stage "released") nil)
             ((or (string= release-stage "approved")
                  (eq review-state :approved))
              :released)
             ((or (string= release-stage "candidate")
                  (eq review-state :awaiting-signoff)
                  (eq review-state :blocked))
              :approved)
             (t :candidate)))
         (summary
           (cond
             ((string= release-stage "released")
              "Release has been promoted; remain in observation and operational review.")
             ((eq review-state :approved)
              "Release candidate is approved and may be promoted to released.")
             ((eq review-state :awaiting-signoff)
              "Release candidate is staged and waiting for final signoff.")
             ((eq review-state :blocked)
              "Release cannot advance until readiness blockers are cleared.")
             (t
              "Define and stage release readiness before promoting the project."))))
    (list :current-phase (cond
                           ((string= release-stage "") review-state)
                           ((string= release-stage "candidate") :candidate)
                           ((string= release-stage "approved") :approved)
                           ((string= release-stage "released") :released)
                           (t review-state))
          :target-phase target-phase
          :transition-ready-p (not (null transition-ready-p))
          :summary summary)))

(defun project-readiness-summary (quality-gate-evaluation testing-evidence-status recovery-summary suite-statuses
                                 release-readiness readiness-obligation-summary)
  (let* ((gate-readiness (or (getf quality-gate-evaluation :readiness) :unknown))
         (testing-readiness (or (getf testing-evidence-status :status) :unknown))
         (recovery-ready-p (not (null (getf recovery-summary :recovery-valid-p))))
         (suite-blocked-count (count-if (lambda (entry)
                                          (eq (getf entry :status) :blocked))
                                        suite-statuses))
         (readiness-obligation-count (or (getf readiness-obligation-summary :obligation-count) 0))
         (blocked-readiness-obligations (or (getf readiness-obligation-summary :blocked-obligations) '()))
         (release-signoff-summary (project-release-signoff-summary
                                   release-readiness
                                   (or (getf readiness-obligation-summary :obligations) '())))
         (release-stage (getf release-readiness :stage))
         (release-signoff-status (getf release-readiness :signoff-status))
         (release-readiness-blocked-p (release-readiness-blocked-p release-readiness))
         (release-review-summary (project-release-review-summary
                                  testing-readiness
                                  gate-readiness
                                  recovery-ready-p
                                  suite-blocked-count
                                  release-readiness
                                  release-signoff-summary
                                  blocked-readiness-obligations))
         (release-transition-summary (project-release-transition-summary
                                      release-readiness
                                      release-review-summary))
         (obligations '()))
    (when (eq testing-readiness :blocked)
      (push "Testing evidence requirements remain unmet." obligations))
    (when (> suite-blocked-count 0)
      (push (format nil "~D testing suite expectations are still blocked." suite-blocked-count)
            obligations))
    (when (eq gate-readiness :blocked)
      (push "One or more project quality gates remain blocked." obligations))
    (unless recovery-ready-p
      (push "Recovery posture is not yet ready." obligations))
    (when release-readiness-blocked-p
      (push (if (getf release-signoff-summary :ownership-ready-p)
                "Release readiness signoff remains incomplete."
                "Release signoff ownership remains incomplete.")
            obligations))
    (dolist (obligation blocked-readiness-obligations)
      (push (or (getf obligation :summary)
                (getf obligation :title)
                "A governed readiness obligation remains blocked.")
            obligations))
    (list :status (if (and (not (eq testing-readiness :blocked))
                           (not (eq gate-readiness :blocked))
                           recovery-ready-p
                           (not release-readiness-blocked-p)
                           (null blocked-readiness-obligations))
                      :ready
                      :blocked)
          :testing-readiness testing-readiness
          :quality-gate-readiness gate-readiness
          :recovery-readiness (if recovery-ready-p :ready :blocked)
          :release-readiness-status (if release-readiness-blocked-p :blocked :ready)
          :release-review-state (getf release-review-summary :state)
          :release-signoff-state (getf release-signoff-summary :signoff-state)
          :release-signoff-ready-p (getf release-signoff-summary :signoff-ready-p)
          :release-signoff-summary (getf release-signoff-summary :summary)
          :release-required-approvers (getf release-signoff-summary :required-approvers)
          :release-approved-approvers (getf release-signoff-summary :approved-approvers)
          :release-pending-approvers (getf release-signoff-summary :pending-approvers)
          :release-unassigned-approvers (getf release-signoff-summary :unassigned-approvers)
          :release-signoff-ownership-ready-p (getf release-signoff-summary :ownership-ready-p)
          :release-current-phase (getf release-transition-summary :current-phase)
          :release-target-phase (getf release-transition-summary :target-phase)
          :release-transition-ready-p (getf release-transition-summary :transition-ready-p)
          :release-transition-summary (getf release-transition-summary :summary)
          :suite-blocked-count suite-blocked-count
          :suite-ready-count (- (length suite-statuses) suite-blocked-count)
          :release-stage release-stage
          :release-signoff-status release-signoff-status
          :readiness-obligation-count readiness-obligation-count
          :blocked-readiness-obligation-count (length blocked-readiness-obligations)
          :ready-readiness-obligation-count
          (or (getf readiness-obligation-summary :ready-count) 0)
          :release-next-actions (getf release-review-summary :next-actions)
          :unmet-obligations (nreverse obligations))))

(defun evaluate-project-quality-gate (session project gate)
  (let* ((trace-neighborhood (trace-neighborhood-summary session :project (project-record-id project)))
         (outbound (or (getf trace-neighborhood :outbound) '()))
         (testing-harness-ids (or (project-record-linked-testing-harness-ids project) '()))
         (trace-target-kinds (remove-duplicates
                              (mapcar (lambda (entry) (getf entry :target-kind)) outbound)
                              :test #'eq))
         (testing-evidence (project-quality-gate-testing-evidence))
         (latest-report (or (getf testing-evidence :latest-report) '()))
         (latest-summary (or (getf latest-report :summary) '()))
         (coverage (or (getf testing-evidence :coverage) '()))
         (performance (or (getf testing-evidence :performance) '()))
         (say-turn-latency (or (getf performance :say-turn-latency) '()))
         (environment-save-load (or (getf performance :environment-save-load) '()))
         (recovery-summary (project-quality-gate-recovery-summary session))
         (failed-tests (or (getf latest-summary :failed) 0))
         (unmet '()))
    (dolist (harness-id (or (project-quality-gate-required-harness-ids gate) '()))
      (unless (find harness-id testing-harness-ids :test #'eq)
        (push (format nil "Missing required testing harness ~A." harness-id) unmet)))
    (when (< (length (or (project-record-linked-work-item-ids project) '()))
             (or (project-quality-gate-minimum-linked-work-items gate) 0))
      (push (format nil "Requires at least ~D linked work items."
                    (or (project-quality-gate-minimum-linked-work-items gate) 0))
            unmet))
    (when (< (length (or (project-record-linked-incident-ids project) '()))
             (or (project-quality-gate-minimum-linked-incidents gate) 0))
      (push (format nil "Requires at least ~D linked incidents."
                    (or (project-quality-gate-minimum-linked-incidents gate) 0))
            unmet))
    (when (and (project-quality-gate-require-source-roots-p gate)
               (null (project-record-source-roots project)))
      (push "Requires at least one managed source root." unmet))
    (dolist (required-kind (or (project-quality-gate-required-trace-target-kinds gate) '()))
      (unless (find required-kind trace-target-kinds :test #'eq)
        (push (format nil "Missing trace linkage to ~A." required-kind) unmet)))
    (when (and (numberp (project-quality-gate-maximum-failed-tests gate))
               (> failed-tests (project-quality-gate-maximum-failed-tests gate)))
      (push (format nil "Allows at most ~D failed tests; observed ~D."
                    (project-quality-gate-maximum-failed-tests gate)
                    failed-tests)
            unmet))
    (when (and (project-quality-gate-require-coverage-p gate)
               (not (getf coverage :present-p)))
      (push "Requires a coverage artifact." unmet))
    (when (and (numberp (project-quality-gate-maximum-say-turn-latency-seconds gate))
               (> (or (getf say-turn-latency :avg-seconds) most-positive-double-float)
                  (project-quality-gate-maximum-say-turn-latency-seconds gate)))
      (push (format nil "Requires average say-turn latency <= ~,3Fs; observed ~,3Fs."
                    (project-quality-gate-maximum-say-turn-latency-seconds gate)
                    (or (getf say-turn-latency :avg-seconds) 0.0))
            unmet))
    (when (and (numberp (project-quality-gate-maximum-environment-save-load-seconds gate))
               (> (or (getf environment-save-load :total-seconds) most-positive-double-float)
                  (project-quality-gate-maximum-environment-save-load-seconds gate)))
      (push (format nil "Requires environment save/load <= ~,3Fs; observed ~,3Fs."
                    (project-quality-gate-maximum-environment-save-load-seconds gate)
                    (or (getf environment-save-load :total-seconds) 0.0))
            unmet))
    (when (and (project-quality-gate-require-recovery-ready-p gate)
               (not (getf recovery-summary :recovery-valid-p)))
      (push "Requires recovery-ready environment posture." unmet))
    (list :id (project-quality-gate-id gate)
          :title (project-quality-gate-title gate)
          :summary (project-quality-gate-summary gate)
          :status (if unmet :blocked :ready)
          :unmet-conditions (nreverse unmet)
          :required-harness-ids (copy-list (or (project-quality-gate-required-harness-ids gate) '()))
          :minimum-linked-work-items (or (project-quality-gate-minimum-linked-work-items gate) 0)
          :minimum-linked-incidents (or (project-quality-gate-minimum-linked-incidents gate) 0)
          :require-source-roots-p (not (null (project-quality-gate-require-source-roots-p gate)))
          :required-trace-target-kinds (copy-list (or (project-quality-gate-required-trace-target-kinds gate) '()))
          :maximum-failed-tests (project-quality-gate-maximum-failed-tests gate)
          :observed-failed-tests failed-tests
          :require-coverage-p (not (null (project-quality-gate-require-coverage-p gate)))
          :coverage-present-p (not (null (getf coverage :present-p)))
          :maximum-say-turn-latency-seconds (project-quality-gate-maximum-say-turn-latency-seconds gate)
          :observed-say-turn-latency-seconds (getf say-turn-latency :avg-seconds)
          :maximum-environment-save-load-seconds (project-quality-gate-maximum-environment-save-load-seconds gate)
          :observed-environment-save-load-seconds (getf environment-save-load :total-seconds)
          :require-recovery-ready-p (not (null (project-quality-gate-require-recovery-ready-p gate)))
          :recovery-ready-p (not (null (getf recovery-summary :recovery-valid-p))))))

(defun evaluate-project-quality-gates (session project)
  (let* ((evaluations (mapcar (lambda (gate)
                                (evaluate-project-quality-gate session project gate))
                              (or (project-record-quality-gates project) '())))
         (blocked-count (count-if (lambda (entry)
                                    (eq (getf entry :status) :blocked))
                                  evaluations)))
    (list :gates evaluations
          :gate-count (length evaluations)
          :blocked-count blocked-count
          :ready-count (- (length evaluations) blocked-count)
          :readiness (if (zerop blocked-count) :ready :blocked))))

(defun project-detail-payload (session project
                               &key
                                 (include-alignment-state-p t)
                                 (include-reconciliation-decision-p t))
  (let* ((quality-gate-evaluation (evaluate-project-quality-gates session project))
         (testing-strategy (or (getf (project-record-metadata project) +project-testing-strategy-key+) '()))
         (release-readiness (or (getf (project-record-metadata project) +project-release-readiness-key+) '()))
         (readiness-obligations (or (getf (project-record-metadata project) +project-readiness-obligations-key+) '()))
         (testing-evidence (project-quality-gate-testing-evidence))
         (testing-suite-statuses (project-testing-suite-statuses project testing-strategy testing-evidence))
         (testing-evidence-status (project-testing-evidence-status-summary testing-strategy testing-evidence))
         (recovery-summary (project-quality-gate-recovery-summary session))
         (readiness-obligation-summary (project-readiness-obligation-summary readiness-obligations))
         (readiness-summary (project-readiness-summary
                             quality-gate-evaluation
                             testing-evidence-status
                             recovery-summary
                             testing-suite-statuses
                             release-readiness
                             readiness-obligation-summary))
         (alignment-state (and include-alignment-state-p
                               (compute-alignment-state
                                session
                                :prompt (project-alignment-evaluation-prompt project)
                                :operator-mode :conversation)))
         (reconciliation-decision
           (and include-reconciliation-decision-p
                (compute-reconciliation-decision
                 session
                 :prompt (project-alignment-evaluation-prompt project)
                 :operator-mode :conversation))))
    (append
     (project-detail project)
     (list :linked-work-items
           (remove nil
                   (mapcar (lambda (work-item-id)
                             (service-project-linked-work-item-summary session work-item-id))
                           (or (project-record-linked-work-item-ids project) '())))
           :linked-incidents
           (remove nil
                   (mapcar (lambda (incident-id)
                             (service-project-linked-incident-summary session incident-id))
                           (or (project-record-linked-incident-ids project) '())))
           :linked-testing-harnesses
           (service-project-testing-harness-summaries project)
           :testing-evidence
           (append testing-evidence
                   (list :suite-statuses testing-suite-statuses
                         :evidence-status testing-evidence-status))
           :release-readiness release-readiness
           :readiness-obligations readiness-obligations
           :quality-gates
           (mapcar #'project-quality-gate-payload
                   (or (project-record-quality-gates project) '()))
           :quality-gate-summary quality-gate-evaluation
           :readiness-summary readiness-summary
           :alignment-state alignment-state
           :reconciliation-decision reconciliation-decision
           :trace-neighborhood
           (trace-neighborhood-summary session :project (project-record-id project))))))

(defun project-command-detail-payload (session project)
  (project-detail-payload session
                          project
                          :include-alignment-state-p nil
                          :include-reconciliation-decision-p nil))

(defun query-project-list-service (session)
  (make-service-query-response
   :project
   :list
   (list :current-project-id (agent-session-current-project-id session)
         :projects (mapcar #'project-summary (list-project-records session)))
   :metadata (make-service-metadata :authority :environment
                                    :read-model :project-list-v1
                                    :session session)))

(defun query-project-detail-service (session project-id)
  (let ((project (find-project-record session project-id)))
    (unless project
      (error "Unknown project ~A" project-id))
    (make-service-query-response
     :project
     :detail
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :project-detail-v1
                                      :session session))))

(defun make-project-control-actor-address (session)
  (make-standard-actor-address :project
                               :scope (agent-session-id session)))

(defun actorize-project-command-response (response
                                          &key actor-execution-job-id
                                            governance-authority
                                            policy-id
                                            approval-required-p
                                            approval-granted-p)
  (if (listp response)
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (when actor-execution-job-id
          (setf (getf metadata :actor-execution-job-id) actor-execution-job-id))
        (when governance-authority
          (setf (getf metadata :governance-authority) governance-authority))
        (when policy-id
          (setf (getf metadata :policy-id) policy-id))
        (setf (getf metadata :approval-required-p) (and approval-required-p t)
              (getf metadata :approval-granted-p) (and approval-granted-p t)
              (getf response :metadata) metadata)
        (when (keyword-plist-p data)
          (let ((updated-data (copy-list data)))
            (when actor-execution-job-id
              (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id))
            (when governance-authority
              (setf (getf updated-data :governance-authority) governance-authority))
            (when policy-id
              (setf (getf updated-data :policy-id) policy-id))
            (setf (getf updated-data :approval-required-p) (and approval-required-p t)
                  (getf updated-data :approval-granted-p) (and approval-granted-p t)
                  (getf response :data) updated-data)))
        response)
      response))

(defun actorize-project-query-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (keyword-plist-p data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun call-with-project-query-actor (session request thunk capability action
                                      &key project-id incident-id metadata)
  (let ((actor-address (make-project-control-actor-address session)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-project-query-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :operator
               :target :project
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata (append (when project-id
                                   (list :project-id project-id))
                                 (when incident-id
                                   (list :incident-id incident-id))
                                 metadata)))))

(defun command-project-list-query-service (session)
  (call-with-project-query-actor
   session
   (make-project-control-request session
                                 :project-list-query
                                 :project/list)
   (lambda ()
     (query-project-list-service session))
   :project/list
   :project-list-query))

(defun command-project-detail-query-service (session project-id)
  (call-with-project-query-actor
   session
   (make-project-control-request session
                                :project-detail-query
                                :project/detail
                                :payload (list :project-id project-id)
                                :project-id project-id)
   (lambda ()
     (query-project-detail-service session project-id))
   :project/detail
   :project-detail-query
   :project-id project-id))

(defun query-project-testing-harness-inventory-service (session)
  (make-service-query-response
   :project
   :testing-harness-inventory
   (list :count (length (testing-harness-inventory))
         :entries (copy-tree (testing-harness-inventory)))
   :metadata (make-service-metadata :authority :environment
                                    :read-model :project-testing-harness-inventory-v1
                                    :session session)))

(defun command-project-testing-harness-inventory-query-service (session)
  (call-with-project-query-actor
   session
   (make-project-control-request session
                                 :project-testing-harness-inventory-query
                                 :project/testing-harness-inventory)
   (lambda ()
     (query-project-testing-harness-inventory-service session))
   :project/testing-harness-inventory
   :project-testing-harness-inventory-query))

(defun make-project-control-request (session action capability
                                     &key payload metadata project-id work-item-id incident-id)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :project
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :project-control-v1)
                     (when project-id
                       (list :project-id project-id))
                     (when work-item-id
                       (list :work-item-id work-item-id))
                     (when incident-id
                       (list :incident-id incident-id))
                     metadata)))

(defun project-command-policy-id (capability)
  (let ((normalized (capability-name-string capability)))
    (cond
      ((or (string= normalized "project/planning")
           (string= normalized "project/binding"))
       :project-governance-write)
      (t nil))))

(defun project-command-approval-required-p (policy-id)
  (let ((policy (and policy-id
                     (ignore-errors (ensure-capability-policy policy-id)))))
    (and policy
         (not (eq (capability-policy-default-grant-mode policy) :implicit)))))

(defun call-with-project-actor (session request thunk capability action
                                &key project-id work-item-id incident-id)
  (let* ((actor-address (make-project-control-actor-address session))
         (policy-id (project-command-policy-id capability))
         (approval-required-p (project-command-approval-required-p policy-id))
         (actor-context (make-actor-execution-context
                         :actor-id (actor-address-id actor-address)
                         :capability capability
                         :authority :governance
                         :policy-id policy-id
                         :target :project
                         :operation action
                         :request-id (desktop-task-request-id request)
                         :work-item-id work-item-id
                         :approval-required-p approval-required-p
                         :metadata (append (when project-id
                                             (list :project-id project-id))
                                           (when incident-id
                                             (list :incident-id incident-id)))))
         (approval-granted-p (and approval-required-p
                                  policy-id
                                  (ignore-errors (policy-approved-p session policy-id)))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (when (fboundp 'update-current-actor-execution-context)
         (update-current-actor-execution-context actor-context :replace-p t))
       (when (and approval-required-p policy-id)
         (ensure-policy-approved session policy-id))
       (actorize-project-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)
        :governance-authority :actor-runtime
        :policy-id policy-id
        :approval-required-p approval-required-p
        :approval-granted-p approval-granted-p))
     :context actor-context)))

(defun perform-project-create-service (session &key title summary constitution requirements
                                               feature-specifications design-system
                                               style-guide user-journeys
                                               non-functional-requirements
                                               architecture-decisions source-roots metadata)
  (let ((project (create-project-record session
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
    (dolist (requirement (or (project-record-requirements project) '()))
      (create-trace-link session
                         :relation :contains-requirement
                         :source-kind :project
                         :source-id (project-record-id project)
                         :target-kind :requirement
                         :target-id (project-requirement-id requirement)
                         :metadata (list :project-id (project-record-id project)
                                         :requirement-id (project-requirement-id requirement))))
    (dolist (feature-spec (or (project-record-feature-specifications project) '()))
      (create-trace-link session
                         :relation :contains-feature-specification
                         :source-kind :project
                         :source-id (project-record-id project)
                         :target-kind :feature-specification
                         :target-id (project-feature-spec-id feature-spec)
                         :metadata (list :project-id (project-record-id project)
                                         :feature-specification-id (project-feature-spec-id feature-spec)))
      (dolist (requirement-id (or (project-feature-spec-linked-requirement-ids feature-spec) '()))
        (create-trace-link session
                           :relation :implements-requirement
                           :source-kind :feature-specification
                           :source-id (project-feature-spec-id feature-spec)
                           :target-kind :requirement
                           :target-id requirement-id
                           :metadata (list :project-id (project-record-id project)
                                           :feature-specification-id (project-feature-spec-id feature-spec)
                                           :requirement-id requirement-id)))
      (dolist (journey-id (or (project-feature-spec-linked-journey-ids feature-spec) '()))
        (create-trace-link session
                           :relation :realizes-user-journey
                           :source-kind :feature-specification
                           :source-id (project-feature-spec-id feature-spec)
                           :target-kind :user-journey
                           :target-id journey-id
                           :metadata (list :project-id (project-record-id project)
                                           :feature-specification-id (project-feature-spec-id feature-spec)
                                           :journey-id journey-id))))
    (dolist (journey (or (project-record-user-journeys project) '()))
      (create-trace-link session
                         :relation :contains-user-journey
                         :source-kind :project
                         :source-id (project-record-id project)
                         :target-kind :user-journey
                         :target-id (project-user-journey-id journey)
                         :metadata (list :project-id (project-record-id project)
                                         :journey-id (project-user-journey-id journey))))
    (dolist (decision (or (project-record-architecture-decisions project) '()))
      (create-trace-link session
                         :relation :contains-architecture-decision
                         :source-kind :project
                         :source-id (project-record-id project)
                         :target-kind :architecture-decision
                         :target-id (project-architecture-decision-id decision)
                         :metadata (list :project-id (project-record-id project)
                                         :architecture-decision-id (project-architecture-decision-id decision)))
      (dolist (requirement-id (or (project-architecture-decision-linked-requirement-ids decision) '()))
        (create-trace-link session
                           :relation :satisfies-requirement
                           :source-kind :architecture-decision
                           :source-id (project-architecture-decision-id decision)
                           :target-kind :requirement
                           :target-id requirement-id
                           :metadata (list :project-id (project-record-id project)
                                           :architecture-decision-id (project-architecture-decision-id decision)
                                           :requirement-id requirement-id))))
    (dolist (root (or (project-record-source-roots project) '()))
      (create-trace-link session
                         :relation :owns-source-root
                         :source-kind :project
                         :source-id (project-record-id project)
                         :target-kind :source-root
                         :target-id root
                         :metadata (list :project-id (project-record-id project)
                                         :source-root root)))
    (make-service-command-response
     :project
     :create
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-create-service (session &key title summary constitution requirements
                                               feature-specifications design-system
                                               style-guide user-journeys
                                               non-functional-requirements
                                               architecture-decisions source-roots metadata)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :create
                                 :project/planning
                                 :payload (list :title title
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
                                                :metadata metadata))
   (lambda ()
     (perform-project-create-service session
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
                                     :metadata metadata))
   :project/planning
   :create))

(defun perform-project-select-service (session project-id)
  (let ((project (select-project-record session project-id)))
    (make-service-command-response
     :project
     :select
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-select-service (session project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :select
                                 :project/control
                                 :payload (list :project-id project-id)
                                 :project-id project-id)
   (lambda ()
     (perform-project-select-service session project-id))
   :project/control
   :select
   :project-id project-id))

(defun perform-project-constitution-service (session constitution &key project-id)
  (let ((project (set-project-constitution session constitution project-id)))
    (make-service-command-response
     :project
     :set-constitution
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-constitution-service (session constitution &key project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :set-constitution
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :constitution constitution)
                                 :project-id project-id)
   (lambda ()
     (perform-project-constitution-service session constitution :project-id project-id))
   :project/planning
   :set-constitution
   :project-id project-id))

(defun perform-project-design-system-service (session design-system &key project-id)
  (let ((project (set-project-design-system session design-system project-id)))
    (make-service-command-response
     :project
     :set-design-system
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-design-system-service (session design-system &key project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :set-design-system
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :design-system design-system)
                                 :project-id project-id)
   (lambda ()
     (perform-project-design-system-service session design-system :project-id project-id))
   :project/planning
   :set-design-system
   :project-id project-id))

(defun perform-project-style-guide-service (session style-guide &key project-id)
  (let ((project (set-project-style-guide session style-guide project-id)))
    (make-service-command-response
     :project
     :set-style-guide
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-style-guide-service (session style-guide &key project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :set-style-guide
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :style-guide style-guide)
                                 :project-id project-id)
   (lambda ()
     (perform-project-style-guide-service session style-guide :project-id project-id))
   :project/planning
   :set-style-guide
   :project-id project-id))

(defun perform-project-testing-strategy-service (session testing-strategy &key project-id)
  (let ((project (set-project-testing-strategy session testing-strategy project-id)))
    (make-service-command-response
     :project
     :set-testing-strategy
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-testing-strategy-service (session testing-strategy &key project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :set-testing-strategy
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :testing-strategy testing-strategy)
                                 :project-id project-id)
   (lambda ()
     (perform-project-testing-strategy-service session testing-strategy :project-id project-id))
   :project/planning
   :set-testing-strategy
   :project-id project-id))

(defun perform-project-release-readiness-service (session release-readiness &key project-id)
  (let ((project (set-project-release-readiness session release-readiness project-id)))
    (make-service-command-response
     :project
     :set-release-readiness
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-release-readiness-service (session release-readiness &key project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :set-release-readiness
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :release-readiness release-readiness)
                                 :project-id project-id)
   (lambda ()
     (perform-project-release-readiness-service session release-readiness :project-id project-id))
   :project/planning
   :set-release-readiness
   :project-id project-id))

(defun perform-project-readiness-obligations-service (session readiness-obligations &key project-id)
  (let ((project (set-project-readiness-obligations session readiness-obligations project-id)))
    (make-service-command-response
     :project
     :set-readiness-obligations
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-readiness-obligations-service (session readiness-obligations &key project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :set-readiness-obligations
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :readiness-obligations readiness-obligations)
                                 :project-id project-id)
   (lambda ()
     (perform-project-readiness-obligations-service session readiness-obligations :project-id project-id))
   :project/planning
   :set-readiness-obligations
   :project-id project-id))

(defun perform-project-requirement-service (session &key project-id id title summary scope kind
                                                    priority status verification-kind
                                                    linked-artifact-ids metadata
                                                    non-functional-p)
  (let ((project (append-project-requirement
                  session
                  (make-project-requirement :id (or id (make-generated-project-id "req"))
                                            :title title
                                            :summary summary
                                            :scope scope
                                            :kind (or kind (if non-functional-p :non-functional :functional))
                                            :priority priority
                                            :status (or status :draft)
                                            :verification-kind verification-kind
                                            :linked-artifact-ids linked-artifact-ids
                                            :metadata metadata)
                  project-id)))
    (create-trace-link session
                       :relation :contains-requirement
                       :source-kind :project
                       :source-id (project-record-id project)
                       :target-kind :requirement
                       :target-id (project-requirement-id
                                   (car (last (project-record-requirements project))))
                       :metadata (list :project-id (project-record-id project)))
    (make-service-command-response
     :project
     :append-requirement
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-requirement-service (session &key project-id id title summary scope kind
                                                    priority status verification-kind
                                                    linked-artifact-ids metadata
                                                    non-functional-p)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :append-requirement
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :id id
                                                :title title
                                                :summary summary
                                                :scope scope
                                                :kind kind
                                                :priority priority
                                                :status status
                                                :verification-kind verification-kind
                                                :linked-artifact-ids linked-artifact-ids
                                                :metadata metadata
                                                :non-functional-p non-functional-p)
                                 :project-id project-id)
   (lambda ()
     (perform-project-requirement-service session
                                          :project-id project-id
                                          :id id
                                          :title title
                                          :summary summary
                                          :scope scope
                                          :kind kind
                                          :priority priority
                                          :status status
                                          :verification-kind verification-kind
                                          :linked-artifact-ids linked-artifact-ids
                                          :metadata metadata
                                          :non-functional-p non-functional-p))
   :project/planning
   :append-requirement
   :project-id project-id))

(defun perform-project-feature-spec-service (session &key project-id id title summary status
                                                     acceptance-criteria linked-requirement-ids
                                                     linked-journey-ids metadata)
  (let ((project (append-project-feature-specification
                  session
                  (make-project-feature-spec :id (or id (make-generated-project-id "spec"))
                                             :title title
                                             :summary summary
                                             :status (or status :draft)
                                             :acceptance-criteria acceptance-criteria
                                             :linked-requirement-ids linked-requirement-ids
                                             :linked-journey-ids linked-journey-ids
                                             :metadata metadata)
                  project-id)))
    (let ((feature-spec (car (last (project-record-feature-specifications project)))))
      (create-trace-link session
                         :relation :contains-feature-specification
                         :source-kind :project
                         :source-id (project-record-id project)
                         :target-kind :feature-specification
                         :target-id (project-feature-spec-id feature-spec)
                         :metadata (list :project-id (project-record-id project)))
      (dolist (requirement-id (or (project-feature-spec-linked-requirement-ids feature-spec) '()))
        (create-trace-link session
                           :relation :implements-requirement
                           :source-kind :feature-specification
                           :source-id (project-feature-spec-id feature-spec)
                           :target-kind :requirement
                           :target-id requirement-id
                           :metadata (list :project-id (project-record-id project))))
      (dolist (journey-id (or (project-feature-spec-linked-journey-ids feature-spec) '()))
        (create-trace-link session
                           :relation :realizes-journey
                           :source-kind :feature-specification
                           :source-id (project-feature-spec-id feature-spec)
                           :target-kind :user-journey
                           :target-id journey-id
                           :metadata (list :project-id (project-record-id project)))))
    (make-service-command-response
     :project
     :append-feature-specification
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-feature-spec-service (session &key project-id id title summary status
                                                     acceptance-criteria linked-requirement-ids
                                                     linked-journey-ids metadata)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :append-feature-specification
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :id id
                                                :title title
                                                :summary summary
                                                :status status
                                                :acceptance-criteria acceptance-criteria
                                                :linked-requirement-ids linked-requirement-ids
                                                :linked-journey-ids linked-journey-ids
                                                :metadata metadata)
                                 :project-id project-id)
   (lambda ()
     (perform-project-feature-spec-service session
                                           :project-id project-id
                                           :id id
                                           :title title
                                           :summary summary
                                           :status status
                                           :acceptance-criteria acceptance-criteria
                                           :linked-requirement-ids linked-requirement-ids
                                           :linked-journey-ids linked-journey-ids
                                           :metadata metadata))
   :project/planning
   :append-feature-specification
   :project-id project-id))

(defun perform-project-user-journey-service (session &key project-id id title summary actors
                                                     entrypoints steps outcomes edge-cases metadata)
  (let ((project (append-project-user-journey
                  session
                  (make-project-user-journey :id (or id (make-generated-project-id "journey"))
                                             :title title
                                             :summary summary
                                             :actors actors
                                             :entrypoints entrypoints
                                             :steps steps
                                             :outcomes outcomes
                                             :edge-cases edge-cases
                                             :metadata metadata)
                  project-id)))
    (create-trace-link session
                       :relation :contains-user-journey
                       :source-kind :project
                       :source-id (project-record-id project)
                       :target-kind :user-journey
                       :target-id (project-user-journey-id
                                   (car (last (project-record-user-journeys project))))
                       :metadata (list :project-id (project-record-id project)))
    (make-service-command-response
     :project
     :append-user-journey
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-user-journey-service (session &key project-id id title summary actors
                                                     entrypoints steps outcomes edge-cases metadata)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :append-user-journey
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :id id
                                                :title title
                                                :summary summary
                                                :actors actors
                                                :entrypoints entrypoints
                                                :steps steps
                                                :outcomes outcomes
                                                :edge-cases edge-cases
                                                :metadata metadata)
                                 :project-id project-id)
   (lambda ()
     (perform-project-user-journey-service session
                                           :project-id project-id
                                           :id id
                                           :title title
                                           :summary summary
                                           :actors actors
                                           :entrypoints entrypoints
                                           :steps steps
                                           :outcomes outcomes
                                           :edge-cases edge-cases
                                           :metadata metadata))
   :project/planning
   :append-user-journey
   :project-id project-id))

(defun perform-project-architecture-decision-service (session &key project-id id title status
                                                              summary drivers consequences
                                                              stack-choices linked-requirement-ids
                                                              metadata)
  (let ((project (append-project-architecture-decision
                  session
                  (make-project-architecture-decision
                   :id (or id (make-generated-project-id "adr"))
                   :title title
                   :status (or status :proposed)
                   :summary summary
                   :drivers drivers
                   :consequences consequences
                   :stack-choices stack-choices
                   :linked-requirement-ids linked-requirement-ids
                   :metadata metadata)
                  project-id)))
    (let ((decision (car (last (project-record-architecture-decisions project)))))
      (create-trace-link session
                         :relation :contains-architecture-decision
                         :source-kind :project
                         :source-id (project-record-id project)
                         :target-kind :architecture-decision
                         :target-id (project-architecture-decision-id decision)
                         :metadata (list :project-id (project-record-id project)))
      (dolist (requirement-id (or (project-architecture-decision-linked-requirement-ids decision) '()))
        (create-trace-link session
                           :relation :addresses-requirement
                           :source-kind :architecture-decision
                           :source-id (project-architecture-decision-id decision)
                           :target-kind :requirement
                           :target-id requirement-id
                           :metadata (list :project-id (project-record-id project)))))
    (make-service-command-response
     :project
     :append-architecture-decision
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-architecture-decision-service (session &key project-id id title status
                                                              summary drivers consequences
                                                              stack-choices linked-requirement-ids
                                                              metadata)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :append-architecture-decision
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :id id
                                                :title title
                                                :status status
                                                :summary summary
                                                :drivers drivers
                                                :consequences consequences
                                                :stack-choices stack-choices
                                                :linked-requirement-ids linked-requirement-ids
                                                :metadata metadata)
                                 :project-id project-id)
   (lambda ()
     (perform-project-architecture-decision-service session
                                                    :project-id project-id
                                                    :id id
                                                    :title title
                                                    :status status
                                                    :summary summary
                                                    :drivers drivers
                                                    :consequences consequences
                                                    :stack-choices stack-choices
                                                    :linked-requirement-ids linked-requirement-ids
                                                    :metadata metadata))
   :project/planning
   :append-architecture-decision
   :project-id project-id))

(defun perform-project-bind-work-item-service (session work-item-id &key project-id)
  (unless (find-work-item session work-item-id)
    (error "Unknown work item ~A" work-item-id))
  (let ((project (append-project-work-item-binding session work-item-id project-id)))
    (create-trace-link session
                       :relation :tracked-by-work-item
                       :source-kind :project
                       :source-id (project-record-id project)
                       :target-kind :work-item
                       :target-id work-item-id
                       :metadata (list :project-id (project-record-id project)))
    (make-service-command-response
     :project
     :bind-work-item
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-bind-work-item-service (session work-item-id &key project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :bind-work-item
                                 :project/binding
                                 :payload (list :project-id project-id
                                                :work-item-id work-item-id)
                                 :project-id project-id
                                 :work-item-id work-item-id)
   (lambda ()
     (perform-project-bind-work-item-service session work-item-id :project-id project-id))
   :project/binding
   :bind-work-item
   :project-id project-id
   :work-item-id work-item-id))

(defun perform-project-bind-incident-service (session incident-id &key project-id)
  (unless (find-incident session incident-id)
    (error "Unknown incident ~A" incident-id))
  (let ((project (append-project-incident-binding session incident-id project-id)))
    (create-trace-link session
                       :relation :tracked-by-incident
                       :source-kind :project
                       :source-id (project-record-id project)
                       :target-kind :incident
                       :target-id incident-id
                       :metadata (list :project-id (project-record-id project)))
    (make-service-command-response
     :project
     :bind-incident
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-bind-incident-service (session incident-id &key project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :bind-incident
                                 :project/binding
                                 :payload (list :project-id project-id
                                                :incident-id incident-id)
                                 :project-id project-id
                                 :incident-id incident-id)
   (lambda ()
     (perform-project-bind-incident-service session incident-id :project-id project-id))
   :project/binding
   :bind-incident
   :project-id project-id
   :incident-id incident-id))

(defun perform-project-bind-testing-harness-service (session harness-id &key project-id)
  (unless (find harness-id (testing-harness-inventory) :key (lambda (entry) (getf entry :id)) :test #'eq)
    (error "Unknown testing harness ~A" harness-id))
  (let ((project (append-project-testing-harness-binding session harness-id project-id)))
    (create-trace-link session
                       :relation :validated-by-testing-harness
                       :source-kind :project
                       :source-id (project-record-id project)
                       :target-kind :testing-harness
                       :target-id (string-downcase (symbol-name harness-id))
                       :metadata (list :project-id (project-record-id project)
                                       :harness-id harness-id))
    (make-service-command-response
     :project
     :bind-testing-harness
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-bind-testing-harness-service (session harness-id &key project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :bind-testing-harness
                                 :project/binding
                                 :payload (list :project-id project-id
                                                :harness-id harness-id)
                                 :project-id project-id)
   (lambda ()
     (perform-project-bind-testing-harness-service session harness-id :project-id project-id))
   :project/binding
   :bind-testing-harness
   :project-id project-id))

(defun perform-project-source-root-service (session source-root &key project-id)
  (let ((project (append-project-source-root session source-root project-id)))
    (create-trace-link session
                       :relation :owns-source-root
                       :source-kind :project
                       :source-id (project-record-id project)
                       :target-kind :source-root
                       :target-id source-root
                       :metadata (list :project-id (project-record-id project)))
    (make-service-command-response
     :project
     :append-source-root
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-source-root-service (session source-root &key project-id)
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :append-source-root
                                 :project/binding
                                 :payload (list :project-id project-id
                                                :source-root source-root)
                                 :project-id project-id)
   (lambda ()
     (perform-project-source-root-service session source-root :project-id project-id))
   :project/binding
   :append-source-root
   :project-id project-id))

(defun perform-project-quality-gate-service (session &key project-id id title summary status
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
  (let ((project (append-project-quality-gate
                  session
                  (make-project-quality-gate
                   :id (or id (make-generated-project-id "gate"))
                   :title (or title "Quality Gate")
                   :summary (or summary "Governed completion criteria.")
                   :status (or status :active)
                   :required-harness-ids (copy-list (or required-harness-ids '()))
                   :minimum-linked-work-items minimum-linked-work-items
                   :minimum-linked-incidents minimum-linked-incidents
                   :require-source-roots-p require-source-roots-p
                   :required-trace-target-kinds (copy-list (or required-trace-target-kinds '()))
                   :maximum-failed-tests maximum-failed-tests
                   :require-coverage-p require-coverage-p
                   :maximum-say-turn-latency-seconds maximum-say-turn-latency-seconds
                   :maximum-environment-save-load-seconds maximum-environment-save-load-seconds
                   :require-recovery-ready-p require-recovery-ready-p
                   :metadata metadata)
                  project-id)))
    (make-service-command-response
     :project
     :append-quality-gate
     (project-command-detail-payload session project)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :project-command-v1
                                      :session session))))

(defun command-project-quality-gate-service (session &key project-id id title summary status
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
  (call-with-project-actor
   session
   (make-project-control-request session
                                 :append-quality-gate
                                 :project/planning
                                 :payload (list :project-id project-id
                                                :id id
                                                :title title
                                                :summary summary
                                                :status status
                                                :required-harness-ids required-harness-ids
                                                :minimum-linked-work-items minimum-linked-work-items
                                                :minimum-linked-incidents minimum-linked-incidents
                                                :require-source-roots-p require-source-roots-p
                                                :required-trace-target-kinds required-trace-target-kinds
                                                :maximum-failed-tests maximum-failed-tests
                                                :require-coverage-p require-coverage-p
                                                :maximum-say-turn-latency-seconds maximum-say-turn-latency-seconds
                                                :maximum-environment-save-load-seconds maximum-environment-save-load-seconds
                                                :require-recovery-ready-p require-recovery-ready-p
                                                :metadata metadata)
                                 :project-id project-id)
   (lambda ()
     (perform-project-quality-gate-service session
                                           :project-id project-id
                                           :id id
                                           :title title
                                           :summary summary
                                           :status status
                                           :required-harness-ids required-harness-ids
                                           :minimum-linked-work-items minimum-linked-work-items
                                           :minimum-linked-incidents minimum-linked-incidents
                                           :require-source-roots-p require-source-roots-p
                                           :required-trace-target-kinds required-trace-target-kinds
                                           :maximum-failed-tests maximum-failed-tests
                                           :require-coverage-p require-coverage-p
                                           :maximum-say-turn-latency-seconds maximum-say-turn-latency-seconds
                                           :maximum-environment-save-load-seconds maximum-environment-save-load-seconds
                                           :require-recovery-ready-p require-recovery-ready-p
                                           :metadata metadata))
   :project/planning
   :append-quality-gate
   :project-id project-id))
