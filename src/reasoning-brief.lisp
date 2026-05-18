(in-package #:sbcl-agent)

(defun workflow-work-items-from-dossier (dossier)
  (or (getf (getf dossier :workflow-context) :work-items) '()))

(defun workflow-records-from-dossier (dossier)
  (or (getf (getf dossier :workflow-context) :workflow-records) '()))

(defun incident-records-from-dossier (dossier)
  (or (getf (getf dossier :incident-context) :incidents) '()))

(defun project-context-from-dossier (dossier)
  (or (getf dossier :project-context) '()))

(defun decisive-context-core-entries (dossier)
  (or (getf (getf dossier :decisive-context-core) :entries) '()))

(defun plist-with-key-p (value key)
  (and (listp value)
       (ignore-errors
         (not (null (getf value key))))))

(defun retrieval-gap-type-statement (gap-type gap)
  (case gap-type
    (:missing-linked-event
     (format nil "Linked event ~A could not be resolved from the current environment evidence."
             (or (getf gap :event-id) "<unknown>")))
    (:missing-linked-mutation
     (format nil "Linked mutation ~A could not be resolved from the current environment evidence."
             (or (getf gap :mutation-id) "<unknown>")))
    (:source-divergence
     "Source divergence is present between the expected and current workspace state.")
    (:testing-failures-present
     (format nil "Testing context still reports ~D failure~:P."
             (or (getf gap :failure-count) 0)))
    (:project-readiness-blocked
     (format nil "Project readiness is currently ~S and may block safe execution."
             (or (getf gap :status) :blocked)))
    (otherwise
     (format nil "Retrieval surfaced unresolved context of type ~S." gap-type))))

(defun retrieval-gap-entry (gap)
  (cond
    ((stringp gap)
     (list :kind :missing-context
           :statement gap
           :source :retrieval-dossier
           :severity :medium))
    ((plist-with-key-p gap :type)
     (let ((gap-type (getf gap :type)))
       (append (list :kind :missing-context
                     :statement (retrieval-gap-type-statement gap-type gap)
                     :source :retrieval-dossier
                     :gap-type gap-type
                     :severity (or (getf gap :severity) :medium))
               (copy-list gap))))
    (t
     (list :kind :missing-context
           :statement (princ-to-string gap)
           :source :retrieval-dossier
           :severity :medium))))

(defun retrieval-gap-statements (dossier)
  (mapcar #'retrieval-gap-entry
          (or (getf dossier :gaps) '())))

(defun reasoning-missing-authority-facts (dossier)
  (let ((facts '()))
    (dolist (gap (or (getf dossier :gaps) '()))
      (when (plist-with-key-p gap :type)
        (case (getf gap :type)
          (:missing-linked-event
           (push (list :kind :missing-linked-event
                       :statement (format nil "The authoritative linked event ~A is missing from the current retrieval scope."
                                          (or (getf gap :event-id) "<unknown>"))
                       :source :retrieval-dossier
                       :severity (or (getf gap :severity) :medium)
                       :event-id (getf gap :event-id))
                 facts))
          (:missing-linked-mutation
           (push (list :kind :missing-linked-mutation
                       :statement (format nil "The authoritative linked mutation ~A is missing from the current retrieval scope."
                                          (or (getf gap :mutation-id) "<unknown>"))
                       :source :retrieval-dossier
                       :severity (or (getf gap :severity) :medium)
                       :mutation-id (getf gap :mutation-id))
                 facts)))))
    (nreverse facts)))

(defun reasoning-decisive-unknowns (dossier)
  (let ((unknowns '()))
    (dolist (gap (or (getf dossier :gaps) '()))
      (when (plist-with-key-p gap :type)
        (let ((gap-type (getf gap :type)))
          (when (member gap-type
                        '(:missing-linked-event
                          :missing-linked-mutation
                          :source-divergence
                          :testing-failures-present
                          :project-readiness-blocked)
                        :test #'eq)
            (push (list :kind :decisive-unknown
                        :statement (retrieval-gap-type-statement gap-type gap)
                        :source :retrieval-dossier
                        :gap-type gap-type
                        :severity (or (getf gap :severity) :medium))
                  unknowns)))))
    (when (and (null (decisive-context-core-entries dossier))
               (or (getf dossier :workflow-context)
                   (getf dossier :incident-context)
                   (getf dossier :source-context)))
      (push (list :kind :decisive-unknown
                  :statement "No decisive governing evidence was derived from the retrieved environment state."
                  :source :reasoning-brief
                  :gap-type :missing-decisive-core
                  :severity :medium)
            unknowns))
    (nreverse unknowns)))

(defun reasoning-conflict-candidates (session-summary dossier)
  (let ((candidates '()))
    (when (> (or (getf session-summary :open-incident-count) 0) 0)
      (push (list :kind :incident-conflict
                  :statement "Open incidents may conflict with assumptions that the environment is mutation-clean."
                  :source :session-summary
                  :severity :high)
            candidates))
    (dolist (gap (or (getf dossier :gaps) '()))
      (when (plist-with-key-p gap :type)
        (case (getf gap :type)
          (:source-divergence
           (push (list :kind :source-divergence
                       :statement "Source divergence indicates the expected source state may not match the live workspace."
                       :source :retrieval-dossier
                       :severity (or (getf gap :severity) :high))
                 candidates))
          (:testing-failures-present
           (push (list :kind :testing-failures
                       :statement (format nil "Outstanding test failures may conflict with a clean validation posture (~D failure~:P)."
                                          (or (getf gap :failure-count) 0))
                       :source :retrieval-dossier
                       :severity (or (getf gap :severity) :high))
                 candidates))
          (:project-readiness-blocked
           (push (list :kind :project-readiness
                       :statement (format nil "Project readiness remains ~S and may conflict with immediate execution."
                                          (or (getf gap :status) :blocked))
                       :source :retrieval-dossier
                       :severity (or (getf gap :severity) :high))
                 candidates)))))
    (nreverse candidates)))

(defun reasoning-authority-conflicts (session-summary environment-context dossier)
  (let* ((project-context (project-context-from-dossier dossier))
         (readiness-summary (and project-context
                                 (getf project-context :readiness-summary)))
         (capability-inventory (and (listp environment-context)
                                    (getf environment-context :capability-inventory)))
         (missing-prerequisites (and capability-inventory
                                     (getf capability-inventory :missing-prerequisites)))
         (conflicts '()))
    (when (and (> (or (getf session-summary :open-incident-count) 0) 0)
               (eq (getf readiness-summary :status) :ready))
      (push (list :kind :incident-vs-project-readiness
                  :statement "Project readiness is reported as ready while the live session still carries open incidents."
                  :source :reasoning-brief
                  :severity :high)
            conflicts))
    (when (and (> (or (getf environment-context :work-item-count) 0) 0)
               (null (workflow-work-items-from-dossier dossier)))
      (push (list :kind :workflow-visibility-gap
                  :statement "The environment reports active work-items, but workflow context is absent from the retrieved dossier."
                  :source :reasoning-brief
                  :severity :high)
            conflicts))
    (when (and (> (or (getf environment-context :work-item-count) 0) 0)
               (getf project-context :current-project-id)
               (null (getf project-context :linked-work-items)))
      (push (list :kind :project-work-item-linkage-gap
                  :statement "The environment reports active governed work, but the selected project has no linked work-item evidence."
                  :source :reasoning-brief
                  :severity :high)
            conflicts))
    (when (and (> (or (getf project-context :project-count) 0) 1)
               (getf project-context :current-project-id)
               (getf project-context :linked-projects))
      (push (list :kind :multi-project-ambiguity
                  :statement "Multiple projects are available, so the selected project should be confirmed before relying on project-specific constraints."
                  :source :reasoning-brief
                  :severity :high)
            conflicts))
    (when (and (> (or (getf project-context :project-count) 0) 1)
               (not (getf project-context :selection-confident-p)))
      (push (list :kind :project-selection-low-confidence
                  :statement "The current project selection is not strongly supported by prompt evidence, so project-specific constraints should be treated as provisional."
                  :source :reasoning-brief
                  :severity :high
                  :selection-posture (copy-tree (or (getf project-context :selection-posture) '())))
            conflicts))
    (when (and (eq (getf readiness-summary :status) :ready)
               missing-prerequisites)
      (push (list :kind :project-readiness-vs-capability-posture
                  :statement "Project readiness is reported as ready while environment capability posture still reports missing prerequisites."
                  :source :reasoning-brief
                  :severity :high)
            conflicts))
    (nreverse conflicts)))

(defun reasoning-stale-context-suspicions (session-summary environment-context dossier)
  (let* ((project-context (project-context-from-dossier dossier))
         (suspicions '()))
    (when (and (> (or (getf session-summary :open-incident-count) 0) 0)
               (null (incident-records-from-dossier dossier)))
      (push (list :kind :incident-context-thin
                  :statement "Live session posture shows open incidents, but incident context is missing from the retrieved dossier."
                  :source :reasoning-brief
                  :severity :medium)
            suspicions))
    (when (and (> (or (getf environment-context :work-item-count) 0) 0)
               (null (decisive-context-core-entries dossier)))
      (push (list :kind :decisive-core-stale
                  :statement "The environment reports active governed work, but no decisive governing evidence was derived."
                  :source :reasoning-brief
                  :severity :medium)
            suspicions))
    (when (and (> (or (getf project-context :project-count) 0) 1)
               (null (getf project-context :linked-projects)))
      (push (list :kind :project-context-thin
                  :statement "Multiple projects exist, but the retrieved dossier did not carry enough linked project context to disambiguate safely."
                  :source :reasoning-brief
                  :severity :medium)
            suspicions))
    (nreverse suspicions)))

(defun reasoning-next-inspection-obligations (blockers missing-authority-facts conflict-candidates
                                               authority-conflicts stale-context-suspicions dossier)
  (let ((obligations '()))
    (when blockers
      (push (list :kind :inspect-workflow-blockers
                  :statement "Inspect the current workflow blockers before choosing mutation or recovery actions."
                  :source :reasoning-brief
                  :priority :high)
            obligations))
    (when missing-authority-facts
      (push (list :kind :resolve-missing-authority
                  :statement "Resolve missing linked authority records before relying on derived workflow or alignment state."
                  :source :reasoning-brief
                  :priority :high)
            obligations))
    (when (find :source-divergence conflict-candidates
                :key (lambda (entry) (getf entry :kind))
                :test #'eq)
      (push (list :kind :inspect-source-divergence
                  :statement "Inspect the live source state before trusting cached or expected workspace assumptions."
                  :source :reasoning-brief
                  :priority :high)
            obligations))
    (when (find :testing-failures conflict-candidates
                :key (lambda (entry) (getf entry :kind))
                :test #'eq)
      (push (list :kind :inspect-testing-failures
                  :statement "Inspect the failing validation evidence before treating the environment as ready."
                  :source :reasoning-brief
                  :priority :high)
            obligations))
    (when (or (incident-records-from-dossier dossier)
              (find :incident-conflict conflict-candidates
                    :key (lambda (entry) (getf entry :kind))
                    :test #'eq))
      (push (list :kind :inspect-incidents
                  :statement "Inspect incident evidence before assuming the environment is clean."
                  :source :reasoning-brief
                  :priority :high)
            obligations))
    (when authority-conflicts
      (push (list :kind :inspect-authority-conflicts
                  :statement "Inspect the conflicting authority signals before relying on project or workflow posture."
                  :source :reasoning-brief
                  :priority :high)
            obligations))
    (when stale-context-suspicions
      (push (list :kind :refresh-stale-context
                  :statement "Refresh the relevant dossier slice before treating the current context as complete."
                  :source :reasoning-brief
                  :priority :medium)
            obligations))
    (nreverse obligations)))

(defun reasoning-facts (session-summary environment-context retrieval-dossier)
  (remove nil
          (list (let ((environment-id (getf environment-context :environment-id)))
                  (when environment-id
                    (list :kind :environment-authority
                          :statement (format nil "Environment ~A is the active authority for this request."
                                             environment-id)
                          :source :environment-context)))
                (let ((thread-id (getf session-summary :current-thread-id)))
                  (when thread-id
                    (list :kind :active-thread
                          :statement (format nil "Thread ~A is the active conversation thread."
                                             thread-id)
                          :source :session-summary)))
                (let ((intent (getf retrieval-dossier :intent)))
                  (when intent
                    (list :kind :retrieval-intent
                          :statement (format nil "Retrieved intent ~S spans domains ~S."
                                             (getf intent :category)
                                             (getf intent :domains))
                          :source :retrieval-dossier)))
                (let ((count (getf environment-context :work-item-count)))
                  (when count
                    (list :kind :workflow-load
                          :statement (format nil "The environment currently tracks ~D work-item~:P."
                                             count)
                          :source :environment-context)))
                (let ((count (getf session-summary :open-incident-count)))
                  (when (> (or count 0) 0)
                    (list :kind :incident-posture
                          :statement (format nil "There are ~D open incident~:P that may constrain safe mutation."
                                             count)
                          :source :session-summary))))))

(defun reasoning-blockers (session-summary retrieval-dossier)
  (let ((blockers '()))
    (when (> (or (getf session-summary :pending-action-count) 0) 0)
      (push (list :kind :pending-actions
                  :statement "There are already staged or pending assistant actions in session state."
                  :source :session-summary)
            blockers))
    (dolist (item (workflow-work-items-from-dossier retrieval-dossier))
      (when (member (getf item :status)
                    '(:awaiting-approval :blocked :quarantined :awaiting-cold-validation)
                    :test #'eq)
        (push (list :kind (getf item :status)
                    :statement (format nil "Work-item ~A is currently ~S."
                                       (or (getf item :id) "<unknown>")
                                       (getf item :status))
                    :source :workflow-context
                    :work-item-id (getf item :id))
              blockers)))
    (nreverse blockers)))

(defun reasoning-validation-obligations (retrieval-dossier)
  (let ((obligations '()))
    (dolist (item (workflow-work-items-from-dossier retrieval-dossier))
      (let ((pending (or (getf item :pending-validations) '()))
            (status (getf item :status)))
        (when pending
          (when (member status '(:awaiting-cold-validation :committed :resumed :mutating)
                        :test #'eq)
            (push (list :kind :work-item-validation
                        :statement (format nil "Work-item ~A still requires validations ~S."
                                           (or (getf item :id) "<unknown>")
                                           pending)
                        :source :workflow-context
                        :work-item-id (getf item :id)
                        :pending-validations pending)
                  obligations)))))
    (dolist (record (workflow-records-from-dossier retrieval-dossier))
      (let ((pending (or (getf record :pending-validations) '()))
            (status (getf record :status)))
        (when pending
          (when (member status '(:awaiting-cold-validation :open :resumed)
                        :test #'eq)
            (push (list :kind :workflow-validation
                        :statement (format nil "Workflow record ~A still carries pending validations ~S."
                                           (or (getf record :id) "<unknown>")
                                           pending)
                        :source :workflow-context
                        :workflow-record-id (getf record :id)
                        :pending-validations pending)
                  obligations)))))
    (nreverse obligations)))

(defun reasoning-evidence-actions (uncertainties blockers obligations missing-authority-facts
                                     conflict-candidates authority-conflicts stale-context-suspicions
                                     inspection-obligations retrieval-dossier)
  (let ((actions '()))
    (when uncertainties
      (push (list :kind :collect-missing-context
                  :statement "Expand or refine retrieval before making strong claims from incomplete context."
                  :source :reasoning-brief)
            actions))
    (when missing-authority-facts
      (push (list :kind :resolve-authoritative-context
                  :statement "Resolve missing linked authority records before trusting derived state."
                  :source :reasoning-brief)
            actions))
    (when conflict-candidates
      (push (list :kind :arbitrate-conflicts
                  :statement "Arbitrate conflicting or dirty environment signals before proceeding with strategy or mutation."
                  :source :reasoning-brief)
            actions))
    (when authority-conflicts
      (push (list :kind :resolve-authority-conflicts
                  :statement "Resolve conflicting authority signals before trusting project, workflow, or incident posture."
                  :source :reasoning-brief)
            actions))
    (when stale-context-suspicions
      (push (list :kind :refresh-context
                  :statement "Refresh stale or missing dossier slices before treating the context as sufficient."
                  :source :reasoning-brief)
            actions))
    (when blockers
      (push (list :kind :resolve-blockers
                  :statement "Address approval, quarantine, or other blocked workflow state before continuing mutation."
                  :source :reasoning-brief)
            actions))
    (when obligations
      (push (list :kind :validate-before-close
                  :statement "Treat validation as part of the execution contract, not as optional follow-up."
                  :source :reasoning-brief)
            actions))
    (when (incident-records-from-dossier retrieval-dossier)
      (push (list :kind :inspect-incidents
                  :statement "Inspect incident evidence before assuming the environment is clean."
                  :source :reasoning-brief)
            actions))
    (dolist (obligation inspection-obligations)
      (push (list :kind :inspect-next
                  :statement (getf obligation :statement)
                  :source :reasoning-brief
                  :inspection-kind (getf obligation :kind)
                  :priority (getf obligation :priority))
            actions))
    (nreverse actions)))

(defun build-reasoning-brief (session-summary environment-context retrieval-dossier)
  (let* ((facts (reasoning-facts session-summary environment-context retrieval-dossier))
         (gap-uncertainties (retrieval-gap-statements retrieval-dossier))
         (missing-authority-facts (reasoning-missing-authority-facts retrieval-dossier))
         (decisive-unknowns (reasoning-decisive-unknowns retrieval-dossier))
         (conflict-candidates (reasoning-conflict-candidates session-summary retrieval-dossier))
         (authority-conflicts (reasoning-authority-conflicts session-summary
                                                             environment-context
                                                             retrieval-dossier))
         (stale-context-suspicions (reasoning-stale-context-suspicions session-summary
                                                                       environment-context
                                                                       retrieval-dossier))
         (blockers (reasoning-blockers session-summary retrieval-dossier))
         (validation-obligations (reasoning-validation-obligations retrieval-dossier))
         (inspection-obligations (reasoning-next-inspection-obligations blockers
                                                                        missing-authority-facts
                                                                        conflict-candidates
                                                                        authority-conflicts
                                                                        stale-context-suspicions
                                                                        retrieval-dossier))
         (uncertainties (append gap-uncertainties
                                decisive-unknowns
                                conflict-candidates
                                authority-conflicts
                                stale-context-suspicions))
         (evidence-actions (reasoning-evidence-actions uncertainties
                                                       blockers
                                                       validation-obligations
                                                       missing-authority-facts
                                                       conflict-candidates
                                                       authority-conflicts
                                                       stale-context-suspicions
                                                       inspection-obligations
                                                       retrieval-dossier)))
    (list :reasoning-mode :environment-grounded
          :facts facts
          :uncertainties uncertainties
          :missing-authority-facts missing-authority-facts
          :decisive-unknowns decisive-unknowns
          :conflict-candidates conflict-candidates
          :authority-conflicts authority-conflicts
          :stale-context-suspicions stale-context-suspicions
          :blockers blockers
          :validation-obligations validation-obligations
          :next-inspection-obligations inspection-obligations
          :evidence-actions evidence-actions)))
