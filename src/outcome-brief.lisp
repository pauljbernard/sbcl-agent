(in-package #:sbcl-agent)

(defun planning-phase-present-p (planning-brief phase)
  (find phase
        (or (getf planning-brief :ordered-steps) '())
        :key (lambda (step) (getf step :phase))
        :test #'eq))

(defun outcome-expected-phases (planning-brief)
  (remove nil
          (list (when (planning-phase-present-p planning-brief :mutate) :mutate)
                (when (planning-phase-present-p planning-brief :validate) :validate)
                (when (planning-phase-present-p planning-brief :collect-evidence) :collect-evidence))))

(defun outcome-observed-summary (retrieval-dossier reasoning-brief)
  (list :observed-consequence-count (length (or (getf retrieval-dossier :observed-consequences) '()))
        :blocker-count (length (or (getf reasoning-brief :blockers) '()))
        :validation-obligation-count (length (or (getf reasoning-brief :validation-obligations) '()))
        :uncertainty-count (length (or (getf reasoning-brief :uncertainties) '()))))

(defun outcome-mismatches (planning-brief retrieval-dossier reasoning-brief)
  (let ((mismatches '())
        (observed (or (getf retrieval-dossier :observed-consequences) '())))
    (when (and (planning-phase-present-p planning-brief :mutate)
               (null observed))
      (push (list :kind :missing-observation
                  :statement "The plan expected mutation, but no observed consequences were captured.")
            mismatches))
    (when (and (planning-phase-present-p planning-brief :validate)
               (getf reasoning-brief :validation-obligations))
      (push (list :kind :validation-still-open
                  :statement "Validation was part of the plan, but validation obligations remain open.")
            mismatches))
    (when (getf reasoning-brief :blockers)
      (push (list :kind :blocked-state
                  :statement "Observed state still contains blockers after the mutation phase.")
            mismatches))
    (nreverse mismatches)))

(defun build-outcome-brief (planning-brief reasoning-brief retrieval-dossier)
  (list :outcome-mode :expectation-vs-observation
        :expected-phases (outcome-expected-phases planning-brief)
        :observed-summary (outcome-observed-summary retrieval-dossier reasoning-brief)
        :mismatches (outcome-mismatches planning-brief retrieval-dossier reasoning-brief)
        :recommended-next-step (cond
                                 ((getf reasoning-brief :validation-obligations) :validate)
                                 ((getf reasoning-brief :blockers) :resolve-blockers)
                                 ((getf reasoning-brief :uncertainties) :collect-evidence)
                                 (t :conclude))))
