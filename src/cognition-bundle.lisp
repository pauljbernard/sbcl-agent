(in-package #:sbcl-agent)

(defstruct cognition-bundle
  retrieval-dossier
  retrieval-focus-plan
  prior-outcome-brief
  reasoning-brief
  planning-brief
  execution-strategy
  validation-strategy
  validation-plan
  action-agenda
  outcome-brief)

(defun execution-strategy-mode (retrieval-dossier reasoning-brief planning-brief prior-outcome-brief)
  (declare (ignore planning-brief))
  (let ((intent (getf retrieval-dossier :intent)))
    (cond
      ((or (getf reasoning-brief :blockers)
           (getf reasoning-brief :validation-obligations))
       :governed-conservative)
      ((eq (and prior-outcome-brief
                (getf prior-outcome-brief :reuse-recommendation))
           :reuse-with-caution)
       :historically-cautious)
      ((and prior-outcome-brief
            (getf prior-outcome-brief :preferred-execution-mode))
       (getf prior-outcome-brief :preferred-execution-mode))
      ((and intent (getf intent :mutation-likely-p))
       :mutation-ready)
      (t
       :inspection-first))))

(defun execution-strategy-next-step (reasoning-brief planning-brief prior-outcome-brief)
  (cond
    ((getf reasoning-brief :blockers) :resolve-blockers)
    ((eq (and prior-outcome-brief
              (getf prior-outcome-brief :reuse-recommendation))
         :reuse-with-caution)
     :collect-evidence)
    ((getf reasoning-brief :uncertainties) :collect-evidence)
    ((find :plan
           (or (getf planning-brief :ordered-steps) '())
           :key (lambda (step) (getf step :phase))
           :test #'eq)
     :plan)
    (t
     :conclude)))

(defun build-execution-strategy (retrieval-dossier reasoning-brief planning-brief prior-outcome-brief)
  (list :mode (execution-strategy-mode retrieval-dossier
                                       reasoning-brief
                                       planning-brief
                                       prior-outcome-brief)
        :next-step (execution-strategy-next-step reasoning-brief
                                                 planning-brief
                                                 prior-outcome-brief)
        :mutation-likely-p (getf (getf retrieval-dossier :intent) :mutation-likely-p)
        :blocked-p (not (null (getf reasoning-brief :blockers)))
        :history-caution-p (eq (and prior-outcome-brief
                                    (getf prior-outcome-brief :reuse-recommendation))
                               :reuse-with-caution)
        :validation-gated-p (not (null (getf reasoning-brief :validation-obligations)))
        :required-evidence-actions (copy-list (or (getf reasoning-brief :evidence-actions) '()))
        :constraints (copy-list (or (getf planning-brief :constraints) '()))))

(defun validation-strategy-mode (reasoning-brief)
  (cond
    ((getf reasoning-brief :validation-obligations) :required)
    ((getf reasoning-brief :blockers) :defer-until-clean)
    (t :opportunistic)))

(defun validation-strategy-next-step (reasoning-brief)
  (cond
    ((getf reasoning-brief :validation-obligations) :run-required-validations)
    ((getf reasoning-brief :blockers) :clear-governance-blockers)
    (t :no-additional-validation-required)))

(defun build-validation-strategy (reasoning-brief planning-brief)
  (declare (ignore planning-brief))
  (list :mode (validation-strategy-mode reasoning-brief)
        :next-step (validation-strategy-next-step reasoning-brief)
        :obligation-count (length (or (getf reasoning-brief :validation-obligations) '()))
        :obligations (copy-list (or (getf reasoning-brief :validation-obligations) '()))))

(defun apply-prior-validation-preference (validation-strategy prior-outcome-brief reasoning-brief)
  (if (or (getf reasoning-brief :validation-obligations)
          (not (getf prior-outcome-brief :preferred-validation-mode)))
      validation-strategy
      (append (copy-list validation-strategy)
              (list :mode (getf prior-outcome-brief :preferred-validation-mode)
                    :memory-shaped-p t))))

(defun workflow-validation-candidates (retrieval-dossier)
  (remove-if-not (lambda (item)
                   (or (getf item :pending-validations)
                       (getf item :validator-tasks)))
                 (or (getf (getf retrieval-dossier :workflow-context) :work-items) '())))

(defun validator-task-plan-entry (task)
  (list :validator-task-id (getf task :id)
        :kind (getf task :kind)
        :status (getf task :status)
        :checkpoint-id (getf task :checkpoint-id)
        :resume-command (getf task :resume-command)
        :replay-id (getf task :replay-id)))

(defun work-item-validation-plan-entry (item)
  (list :work-item-id (getf item :id)
        :status (getf item :status)
        :pending-validations (copy-list (or (getf item :pending-validations) '()))
        :next-action (getf item :next-action)
        :resume-payload (getf item :resume-payload)
        :validator-actions (mapcar #'validator-task-plan-entry
                                   (or (getf item :validator-tasks) '()))))

(defun validation-plan-priority (validation-strategy)
  (case (getf validation-strategy :mode)
    (:required :high)
    (:defer-until-clean :medium)
    (otherwise :low)))

(defun build-validation-plan (retrieval-dossier validation-strategy)
  (let* ((candidates (workflow-validation-candidates retrieval-dossier))
         (entries (mapcar #'work-item-validation-plan-entry candidates)))
    (list :mode (getf validation-strategy :mode)
          :next-step (getf validation-strategy :next-step)
          :priority (validation-plan-priority validation-strategy)
          :work-item-count (length entries)
          :entries entries)))

(defun retrieval-focus-priority (score)
  (cond
    ((>= (or score 0) 8) :high)
    ((>= (or score 0) 3) :medium)
    (t :low)))

(defun retrieval-focus-entry (candidate)
  (list :label (getf candidate :label)
        :score (getf candidate :score)
        :priority (retrieval-focus-priority (getf candidate :score))
        :summary (getf candidate :summary)
        :governance-bonus (getf candidate :governance-bonus)
        :base-score (getf candidate :base-score)))

(defun build-retrieval-focus-plan (retrieval-dossier)
  (let* ((ranking (getf retrieval-dossier :ranking))
         (candidates (or (getf ranking :top-candidates) '()))
         (entries (mapcar #'retrieval-focus-entry candidates)))
    (list :ranking-enabled-p (getf ranking :enabled-p)
          :strategy (getf ranking :strategy)
          :entry-count (length entries)
          :entries entries
          :primary-focus (and entries (first entries))
          :focus-labels (mapcar (lambda (entry) (getf entry :label)) entries)
          :explanation (getf ranking :explanation))))

(defun agenda-step-priority (kind)
  (case kind
    (:resolve-blockers :high)
    (:collect-evidence :high)
    (:run-validations :high)
    (:plan-mutation :medium)
    (:conclude :low)
    (otherwise :medium)))

(defun build-action-agenda (retrieval-focus-plan execution-strategy validation-plan outcome-brief prior-outcome-brief)
  (let ((steps '()))
    (when (> (or (getf retrieval-focus-plan :entry-count) 0) 0)
      (push (list :kind :focus-context
                  :priority :high
                  :statement "Prioritize the highest-ranked retrieved domains before acting."
                  :focus-labels (getf retrieval-focus-plan :focus-labels)
                  :primary-focus (getf retrieval-focus-plan :primary-focus))
            steps))
    (case (getf execution-strategy :next-step)
      (:resolve-blockers
       (push (list :kind :resolve-blockers
                   :priority (agenda-step-priority :resolve-blockers)
                   :statement "Resolve governance blockers before continuing mutation work.")
             steps))
      (:collect-evidence
       (push (list :kind :collect-evidence
                   :priority (agenda-step-priority :collect-evidence)
                   :statement "Collect additional evidence from the focused environment domains before mutating.")
             steps))
      (:plan
       (push (list :kind :plan-mutation
                   :priority (agenda-step-priority :plan-mutation)
                   :statement "Plan the next governed change against the current evidence before executing it.")
             steps))
      (:conclude
       (push (list :kind :conclude
                   :priority (agenda-step-priority :conclude)
                   :statement "No further execution steps are required if the evidence is already sufficient.")
             steps)))
    (when (eq (getf validation-plan :next-step) :run-required-validations)
      (push (list :kind :run-validations
                  :priority (agenda-step-priority :run-validations)
                  :statement "Execute the required validation agenda before accepting further governed mutations."
                  :validation-work-item-count (getf validation-plan :work-item-count))
            steps))
    (let* ((preferred-playbook (and prior-outcome-brief
                                    (getf prior-outcome-brief :preferred-playbook)))
           (decomposition-playbook
             (or (and (getf preferred-playbook :decomposition-pattern-p)
                      preferred-playbook)
                 (and prior-outcome-brief
                      (find-if (lambda (entry)
                                 (getf entry :decomposition-pattern-p))
                               (getf prior-outcome-brief :playbooks))))))
      (when decomposition-playbook
        (push (list :kind :reuse-decomposition
                    :priority :high
                    :statement "Reuse the prior long-horizon decomposition pattern and steer the work phase by phase."
                    :planning-phases (getf decomposition-playbook :planning-phases)
                    :phase-count (getf decomposition-playbook :phase-count))
              steps))
      (when (getf preferred-playbook :orchestration-pattern-p)
        (push (list :kind :review-orchestration
                    :priority :high
                    :statement "Reuse the prior parallel orchestration pattern, keeping ownership scopes explicit and merge review governed."
                    :merge-policy (getf preferred-playbook :merge-policy)
                    :parallel-task-count (getf preferred-playbook :parallel-task-count))
              steps)))
    (when (eq (getf outcome-brief :recommended-next-step) :conclude)
      (push (list :kind :conclude
                  :priority (agenda-step-priority :conclude)
                  :statement "The outcome brief indicates the current turn may be concluded.")
            steps))
    (let ((ordered (nreverse steps)))
      (list :step-count (length ordered)
            :primary-step (and ordered (first ordered))
            :steps ordered))))

(defun build-cognition-bundle (prompt session-summary environment-context retrieval-dossier
                               &key reasoning-brief planning-brief outcome-brief current-turn-id session)
  (let* ((resolved-session (or session
                               (ignore-errors (ensure-session))))
         (prior-outcome-brief (and resolved-session
                                   (build-prior-outcome-brief resolved-session
                                                              prompt
                                                              :current-turn-id current-turn-id)))
         (resolved-reasoning-brief (or reasoning-brief
                                       (build-reasoning-brief session-summary
                                                              environment-context
                                                              retrieval-dossier)))
         (resolved-planning-brief (or planning-brief
                                      (build-planning-brief prompt
                                                            resolved-reasoning-brief
                                                            retrieval-dossier)))
         (resolved-retrieval-focus-plan (build-retrieval-focus-plan retrieval-dossier))
         (resolved-validation-strategy (build-validation-strategy resolved-reasoning-brief
                                                                  resolved-planning-brief))
         (resolved-execution-strategy (build-execution-strategy retrieval-dossier
                                                                resolved-reasoning-brief
                                                                resolved-planning-brief
                                                                prior-outcome-brief))
         (memory-shaped-validation-strategy
           (apply-prior-validation-preference resolved-validation-strategy
                                              prior-outcome-brief
                                              resolved-reasoning-brief))
         (resolved-validation-plan (build-validation-plan retrieval-dossier
                                                          memory-shaped-validation-strategy))
         (resolved-outcome-brief (or outcome-brief
                                     (build-outcome-brief resolved-planning-brief
                                                          resolved-reasoning-brief
                                                          retrieval-dossier))))
    (make-cognition-bundle
     :retrieval-dossier retrieval-dossier
     :retrieval-focus-plan resolved-retrieval-focus-plan
     :prior-outcome-brief prior-outcome-brief
     :reasoning-brief resolved-reasoning-brief
     :planning-brief resolved-planning-brief
     :execution-strategy resolved-execution-strategy
     :validation-strategy memory-shaped-validation-strategy
     :validation-plan resolved-validation-plan
     :action-agenda (build-action-agenda resolved-retrieval-focus-plan
                                         resolved-execution-strategy
                                         resolved-validation-plan
                                         resolved-outcome-brief
                                         prior-outcome-brief)
     :outcome-brief resolved-outcome-brief)))

(defun cognition-bundle-summary (bundle)
  (when bundle
    (list :reasoning-mode (getf (cognition-bundle-reasoning-brief bundle) :reasoning-mode)
          :planning-mode (getf (cognition-bundle-planning-brief bundle) :planning-mode)
          :retrieval-focus-count
          (getf (cognition-bundle-retrieval-focus-plan bundle) :entry-count)
          :retrieval-primary-focus
          (getf (cognition-bundle-retrieval-focus-plan bundle) :primary-focus)
          :execution-mode (getf (cognition-bundle-execution-strategy bundle) :mode)
          :execution-next-step (getf (cognition-bundle-execution-strategy bundle) :next-step)
          :validation-mode (getf (cognition-bundle-validation-strategy bundle) :mode)
          :validation-next-step (getf (cognition-bundle-validation-strategy bundle) :next-step)
          :validation-plan-work-item-count
          (getf (cognition-bundle-validation-plan bundle) :work-item-count)
          :agenda-step-count
          (getf (cognition-bundle-action-agenda bundle) :step-count)
          :agenda-primary-step
          (getf (cognition-bundle-action-agenda bundle) :primary-step)
          :prior-success-count
          (length (or (getf (cognition-bundle-prior-outcome-brief bundle) :similar-successes) '()))
          :prior-failure-count
          (length (or (getf (cognition-bundle-prior-outcome-brief bundle) :similar-failures) '()))
          :memory-match-count
          (getf (cognition-bundle-prior-outcome-brief bundle) :memory-match-count)
          :playbook-count
          (getf (cognition-bundle-prior-outcome-brief bundle) :playbook-count)
          :reuse-recommendation
          (getf (cognition-bundle-prior-outcome-brief bundle) :reuse-recommendation)
          :strategy-pattern-count
          (length (or (getf (cognition-bundle-prior-outcome-brief bundle) :strategy-patterns) '()))
          :blocker-count (length (or (getf (cognition-bundle-reasoning-brief bundle) :blockers) '()))
          :validation-obligation-count
          (length (or (getf (cognition-bundle-reasoning-brief bundle) :validation-obligations) '()))
          :uncertainty-count (length (or (getf (cognition-bundle-reasoning-brief bundle) :uncertainties) '())))))
