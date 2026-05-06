(in-package #:sbcl-agent)

(defstruct retrieval-plan
  intent
  domains
  per-domain-limits
  expansion-posture
  expansion-pass
  runtime-detail-p
  governance-detail-p
  project-detail-p
  source-detail-p
  semantic-ranking-p
  explanation)

(defun session-open-incident-count (session)
  (length (remove-if-not (lambda (incident)
                           (eq (incident-status incident) :open))
                         (agent-session-incidents session))))

(defun work-item-hard-blocker-p (work-item)
  (member (work-item-status work-item)
          '(:blocked :quarantined :awaiting-cold-validation)
          :test #'eq))

(defun session-governance-retrieval-bias (session)
  (let* ((work-items (agent-session-work-items session))
         (open-incidents (session-open-incident-count session))
         (hard-blockers (count-if #'work-item-hard-blocker-p work-items))
         (pending-validations (count-if (lambda (work-item)
                                          (not (null (work-item-pending-validations work-item))))
                                        work-items)))
    (list :open-incident-count open-incidents
          :hard-blocker-count hard-blockers
          :pending-validation-count pending-validations
          :conservative-p (or (> open-incidents 0)
                              (> hard-blockers 0)
                              (> pending-validations 0)))))

(defun retrieval-domain-limit (intent domain)
  (let ((category (retrieval-intent-category intent)))
    (case domain
      (:conversation (if (eq category :historical-recall) 8 4))
      (:intent (if (retrieval-intent-intent-context-p intent) 6 3))
      (:runtime (if (retrieval-intent-runtime-inspection-p intent) 6 2))
      (:telemetry (if (retrieval-intent-observability-context-p intent) 6 3))
      (:console (if (or (retrieval-intent-observability-context-p intent)
                        (retrieval-intent-historical-p intent))
                    8
                    4))
      (:diagnostic (if (retrieval-intent-observability-context-p intent) 6 3))
      (:testing (if (retrieval-intent-testing-context-p intent) 6 3))
      (:project (if (retrieval-intent-project-context-p intent) 6 3))
      (:workflow (if (retrieval-intent-governance-context-p intent) 6 2))
      (:incident (if (member category '(:incident-follow-up :runtime-debugging))
                     6
                     2))
      (:artifact (if (retrieval-intent-governance-context-p intent) 6 3))
      (:events (if (retrieval-intent-historical-p intent) 8 4))
      (:workspace (if (retrieval-intent-source-context-p intent) 6 2))
      (otherwise 3))))

(defun compact-list (items limit)
  (subseq items 0 (min (or limit (length items)) (length items))))

(defun governance-biased-retrieval-domains (plan)
  (remove-duplicates
   (append '(:incident :workflow :artifact :events)
           (retrieval-plan-domains plan))
   :test #'eq))

(defun governance-biased-domain-limit (plan domain)
  (let ((current (or (getf (retrieval-plan-per-domain-limits plan) domain)
                     (retrieval-domain-limit (retrieval-plan-intent plan) domain))))
    (case domain
      (:incident (max current 6))
      (:workflow (max current 6))
      (:artifact (max current 6))
      (:events (max current 8))
      (:console (max current 8))
      (:telemetry (max current 6))
      (:diagnostic (max current 6))
      (:testing (max current 6))
      (:intent (max current 6))
      (:project (max current 6))
      (otherwise current))))

(defun apply-governance-retrieval-bias (plan session)
  (let ((bias (session-governance-retrieval-bias session)))
    (if (getf bias :conservative-p)
        (let* ((domains (governance-biased-retrieval-domains plan))
               (limits (loop for domain in domains
                             append (list domain
                                          (governance-biased-domain-limit plan domain)))))
          (make-retrieval-plan
           :intent (retrieval-plan-intent plan)
           :domains domains
           :per-domain-limits limits
           :expansion-posture (if (eq (retrieval-plan-expansion-posture plan) :compact-first)
                                  :expand-on-gap
                                  (retrieval-plan-expansion-posture plan))
           :expansion-pass (or (retrieval-plan-expansion-pass plan) 0)
           :runtime-detail-p (retrieval-plan-runtime-detail-p plan)
           :governance-detail-p t
           :project-detail-p (retrieval-plan-project-detail-p plan)
           :source-detail-p (retrieval-plan-source-detail-p plan)
           :semantic-ranking-p (retrieval-plan-semantic-ranking-p plan)
           :explanation (format nil
                                "~A Governance bias prioritized incidents/workflow because open-incidents=~D hard-blockers=~D pending-validations=~D."
                                (retrieval-plan-explanation plan)
                                (getf bias :open-incident-count)
                                (getf bias :hard-blocker-count)
                                (getf bias :pending-validation-count))))
        plan)))

(defun build-retrieval-plan (prompt &key session (operator-mode :repl-bridge))
  (let* ((intent (classify-retrieval-intent prompt :operator-mode operator-mode))
         (domains (retrieval-intent-domains intent))
         (expansion-posture (if (or (retrieval-intent-historical-p intent)
                                    (retrieval-intent-mutation-likely-p intent)
                                    (retrieval-intent-governance-context-p intent))
                                :expand-on-gap
                                :compact-first))
         (per-domain-limits
           (loop for domain in domains
                 append (list domain (retrieval-domain-limit intent domain))))
         (plan (make-retrieval-plan
                :intent intent
                :domains domains
                :per-domain-limits per-domain-limits
                :expansion-posture expansion-posture
                :expansion-pass 0
                :runtime-detail-p (retrieval-intent-runtime-inspection-p intent)
                :governance-detail-p (retrieval-intent-governance-context-p intent)
                :project-detail-p (retrieval-intent-project-context-p intent)
                :source-detail-p (retrieval-intent-source-context-p intent)
                :semantic-ranking-p (retrieval-intent-historical-p intent)
                :explanation (format nil
                                     "Plan category ~S over domains ~S with posture ~S."
                                     (retrieval-intent-category intent)
                                     domains
                                     expansion-posture))))
    (if session
        (apply-governance-retrieval-bias plan session)
        plan)))

(defun expanded-retrieval-domain-limit (plan domain)
  (let ((current (or (getf (retrieval-plan-per-domain-limits plan) domain) 0)))
    (case domain
      ((:workflow :incident :events) (+ current 4))
      ((:runtime :conversation :artifact :workspace :intent) (+ current 2))
      ((:telemetry :console :diagnostic :testing) (+ current 2))
      (:project (+ current 2))
      (otherwise (+ current 2)))))

(defun retrieval-plan-limit (plan domain &optional default)
  (or (getf (retrieval-plan-per-domain-limits plan) domain)
      default))

(defun expand-retrieval-plan (plan reason)
  (let* ((domains (remove-duplicates
                   (append (retrieval-plan-domains plan)
                           (when (retrieval-plan-governance-detail-p plan)
                             '(:workflow :incident :events :artifact))
                           (when (retrieval-plan-project-detail-p plan)
                             '(:project))
                           (when (retrieval-plan-source-detail-p plan)
                             '(:workspace :artifact))
                           '(:conversation :events))
                   :test #'eq))
         (limits (loop for domain in domains
                       append (list domain (expanded-retrieval-domain-limit plan domain)))))
    (make-retrieval-plan
     :intent (retrieval-plan-intent plan)
     :domains domains
     :per-domain-limits limits
     :expansion-posture :expanded
     :expansion-pass (1+ (or (retrieval-plan-expansion-pass plan) 0))
     :runtime-detail-p (retrieval-plan-runtime-detail-p plan)
     :governance-detail-p (retrieval-plan-governance-detail-p plan)
     :project-detail-p (retrieval-plan-project-detail-p plan)
     :source-detail-p (retrieval-plan-source-detail-p plan)
     :semantic-ranking-p (retrieval-plan-semantic-ranking-p plan)
     :explanation (format nil
                          "Expanded retrieval after ~A from posture ~S."
                          reason
                          (retrieval-plan-expansion-posture plan)))))
