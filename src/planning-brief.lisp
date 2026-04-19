(in-package #:sbcl-agent)

(defun planning-primary-goal (prompt retrieval-dossier)
  (let ((intent (getf retrieval-dossier :intent)))
    (list :statement (or prompt "No prompt supplied.")
          :intent-category (and intent (getf intent :category))
          :domains (and intent (getf intent :domains)))))

(defun planning-ordered-steps (reasoning-brief)
  (let ((steps '()))
    (push (list :phase :inspect
                :statement "Start from environment-backed facts and currently retrieved state."
                :gating :always)
          steps)
    (when (or (getf reasoning-brief :uncertainties)
              (getf reasoning-brief :evidence-actions))
      (push (list :phase :collect-evidence
                  :statement "Fill missing context before making strong claims or choosing risky mutations."
                  :gating :when-uncertain)
            steps))
    (when (getf reasoning-brief :blockers)
      (push (list :phase :resolve-blockers
                  :statement "Resolve or account for approvals, quarantines, or blocked workflow state before mutation."
                  :gating :when-blocked)
            steps))
    (push (list :phase :plan
                :statement "Form a plan that is grounded in the retrieved environment state."
                :gating :always)
          steps)
    (push (list :phase :mutate
                :statement "Execute only the minimum necessary mutation consistent with the environment-backed plan."
                :gating :when-needed)
          steps)
    (when (getf reasoning-brief :validation-obligations)
      (push (list :phase :validate
                  :statement "Run required validation and reconciliation work before treating the change as closed."
                  :gating :when-mutation-occurs)
            steps))
    (nreverse steps)))

(defun planning-constraints (reasoning-brief)
  (append
   (mapcar (lambda (blocker)
             (list :kind :blocker
                   :statement (getf blocker :statement)
                   :source (getf blocker :source)))
           (or (getf reasoning-brief :blockers) '()))
   (mapcar (lambda (obligation)
             (list :kind :validation
                   :statement (getf obligation :statement)
                   :source (getf obligation :source)))
           (or (getf reasoning-brief :validation-obligations) '()))))

(defun planning-success-criteria (reasoning-brief retrieval-dossier)
  (remove nil
          (append
           (when (getf reasoning-brief :facts)
             (list (list :kind :grounding
                         :statement "The response and actions stay consistent with environment-backed facts.")))
           (when (getf reasoning-brief :uncertainties)
             (list (list :kind :uncertainty
                         :statement "Remaining assumptions are explicitly called out instead of being treated as facts.")))
           (when (getf reasoning-brief :validation-obligations)
             (list (list :kind :validation
                         :statement "Validation obligations remain visible and are not silently skipped.")))
           (when (getf retrieval-dossier :observed-consequences)
             (list (list :kind :observation
                         :statement "Observed post-mutation consequences are used for follow-up reasoning."))))))

(defun build-planning-brief (prompt reasoning-brief retrieval-dossier)
  (list :planning-mode :environment-grounded
        :primary-goal (planning-primary-goal prompt retrieval-dossier)
        :ordered-steps (planning-ordered-steps reasoning-brief)
        :constraints (planning-constraints reasoning-brief)
        :success-criteria (planning-success-criteria reasoning-brief retrieval-dossier)))
