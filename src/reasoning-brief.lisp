(in-package #:sbcl-agent)

(defun workflow-work-items-from-dossier (dossier)
  (or (getf (getf dossier :workflow-context) :work-items) '()))

(defun workflow-records-from-dossier (dossier)
  (or (getf (getf dossier :workflow-context) :workflow-records) '()))

(defun incident-records-from-dossier (dossier)
  (or (getf (getf dossier :incident-context) :incidents) '()))

(defun retrieval-gap-statements (dossier)
  (mapcar (lambda (gap)
            (list :kind :missing-context
                  :statement gap
                  :source :retrieval-dossier))
          (or (getf dossier :gaps) '())))

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

(defun reasoning-evidence-actions (uncertainties blockers obligations retrieval-dossier)
  (let ((actions '()))
    (when uncertainties
      (push (list :kind :collect-missing-context
                  :statement "Expand or refine retrieval before making strong claims from incomplete context."
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
    (nreverse actions)))

(defun build-reasoning-brief (session-summary environment-context retrieval-dossier)
  (let* ((facts (reasoning-facts session-summary environment-context retrieval-dossier))
         (uncertainties (retrieval-gap-statements retrieval-dossier))
         (blockers (reasoning-blockers session-summary retrieval-dossier))
         (validation-obligations (reasoning-validation-obligations retrieval-dossier))
         (evidence-actions (reasoning-evidence-actions uncertainties
                                                       blockers
                                                       validation-obligations
                                                       retrieval-dossier)))
    (list :reasoning-mode :environment-grounded
          :facts facts
          :uncertainties uncertainties
          :blockers blockers
          :validation-obligations validation-obligations
          :evidence-actions evidence-actions)))
