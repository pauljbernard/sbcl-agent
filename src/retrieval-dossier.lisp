(in-package #:sbcl-agent)

(defstruct retrieval-dossier
  phase
  intent
  plan
  ranking
  observed-consequences
  conversation-context
  runtime-context
  workflow-context
  incident-context
  artifact-context
  environment-context
  source-context
  gaps)

(defun retrieval-plan-limit (plan domain &optional default)
  (or (getf (retrieval-plan-per-domain-limits plan) domain)
      default))

(defun compact-list (items limit)
  (subseq items 0 (min (or limit (length items)) (length items))))

(defun dossier-section (domain operation response)
  (list :domain domain
        :operation operation
        :metadata (service-response-metadata response)
        :data (service-response-data response)))

(defun build-conversation-dossier-section (session plan)
  (let ((thread-response (query-conversation-thread-detail-service session))
        (turn-response (ignore-errors (query-conversation-turn-detail-service session))))
    (list :thread (dossier-section :conversation :thread-detail thread-response)
          :turn (and turn-response
                     (dossier-section :conversation :turn-detail turn-response))
          :limit (retrieval-plan-limit plan :conversation 4))))

(defun build-runtime-dossier-section (session plan)
  (let ((summary-response (query-runtime-summary-service session))
        (history-response (query-runtime-history-service session
                                                         :tail (retrieval-plan-limit plan :runtime 3))))
    (list :summary (dossier-section :runtime :summary summary-response)
          :history (dossier-section :runtime :history history-response)
          :detail-p (retrieval-plan-runtime-detail-p plan))))

(defun build-workflow-dossier-section (session plan)
  (let* ((limit (retrieval-plan-limit plan :workflow 4))
         (work-item-list-response (query-work-item-list-service session))
         (workflow-list-response (query-workflow-record-list-service session)))
    (list :work-items (compact-list (service-response-data work-item-list-response) limit)
          :workflow-records (compact-list (service-response-data workflow-list-response) limit)
          :work-item-metadata (service-response-metadata work-item-list-response)
          :workflow-metadata (service-response-metadata workflow-list-response)
          :detail-p (retrieval-plan-governance-detail-p plan))))

(defun build-incident-dossier-section (session plan)
  (let* ((limit (retrieval-plan-limit plan :incident 3))
         (incident-list-response (query-incident-list-service session)))
    (list :incidents (compact-list (service-response-data incident-list-response) limit)
          :metadata (service-response-metadata incident-list-response)
          :detail-p (retrieval-plan-governance-detail-p plan))))

(defun build-artifact-dossier-section (session)
  (let ((review-response (ignore-errors (query-mutation-review-service session))))
    (if review-response
        (list :review (dossier-section :mutation :review review-response))
        (list :review nil
              :note "No mutation review is available for the current thread yet."))))

(defun build-environment-dossier-section (plan)
  (let* ((environment (ensure-environment))
         (summary-response (query-environment-summary-service environment))
         (status-response (query-environment-status-service environment))
         (event-response (query-service-event-stream :environment environment
                                                     :limit (retrieval-plan-limit plan :events 4))))
    (list :summary (dossier-section :environment :summary summary-response)
          :status (dossier-section :environment :status status-response)
          :events (dossier-section :events :stream event-response))))

(defun build-source-dossier-section ()
  (let ((environment-summary (service-response-data
                              (query-environment-summary-service (ensure-environment)))))
    (list :workspace-root (getf environment-summary :storage-root)
          :artifact-summary (getf environment-summary :artifact-summary)
          :note "Source/workspace retrieval is currently summary-backed until dedicated source retrieval lands.")))

(defun build-retrieval-dossier-from-plan (session intent plan)
  (let* ((domains (retrieval-plan-domains plan))
         (artifact-context (when (find :artifact domains)
                             (build-artifact-dossier-section session)))
         (source-context (when (find :workspace domains)
                           (build-source-dossier-section))))
    (make-retrieval-dossier
     :phase :pre-prompt
     :intent intent
     :plan plan
     :observed-consequences nil
     :conversation-context (when (find :conversation domains)
                             (build-conversation-dossier-section session plan))
     :runtime-context (when (find :runtime domains)
                        (build-runtime-dossier-section session plan))
     :workflow-context (when (find :workflow domains)
                         (build-workflow-dossier-section session plan))
     :incident-context (when (find :incident domains)
                         (build-incident-dossier-section session plan))
     :artifact-context artifact-context
     :environment-context (build-environment-dossier-section plan)
     :source-context source-context
     :gaps (append (when (and (find :workspace domains) (null source-context))
                     (list "Workspace retrieval was requested but no source context was assembled."))
                   (when (and (find :artifact domains) (null artifact-context))
                     (list "Artifact retrieval was requested but no artifact context was assembled."))))))

(defun dossier-thin-domain-p (dossier domain)
  (case domain
    (:workflow
     (let ((context (retrieval-dossier-workflow-context dossier)))
       (and context
            (null (or (getf context :work-items) '()))
            (null (or (getf context :workflow-records) '())))))
    (:incident
     (let ((context (retrieval-dossier-incident-context dossier)))
       (and context
            (null (or (getf context :incidents) '())))))
    (:runtime
     (let ((context (retrieval-dossier-runtime-context dossier)))
       (and context
            (null (getf context :history)))))
    (otherwise
     nil)))

(defun retrieval-expansion-reason (dossier)
  (let* ((plan (retrieval-dossier-plan dossier))
         (domains (retrieval-plan-domains plan)))
    (cond
      ((or (null (retrieval-plan-expansion-posture plan))
           (eq (retrieval-plan-expansion-posture plan) :compact-first))
       nil)
      ((> (length (or (retrieval-dossier-gaps dossier) '())) 0)
       :gaps)
      ((find-if (lambda (domain) (dossier-thin-domain-p dossier domain)) domains)
       :thin-context)
      (t
       nil))))

(defun maybe-expand-retrieval-dossier (session intent dossier)
  (let* ((plan (retrieval-dossier-plan dossier))
         (reason (retrieval-expansion-reason dossier)))
    (if (and reason
             (< (or (retrieval-plan-expansion-pass plan) 0) 1))
        (build-retrieval-dossier-from-plan session
                                           intent
                                           (expand-retrieval-plan plan reason))
        dossier)))

(defun build-retrieval-dossier (session prompt &key (operator-mode :repl-bridge))
  (let* ((intent (classify-retrieval-intent prompt :operator-mode operator-mode))
         (plan (build-retrieval-plan prompt
                                     :session session
                                     :operator-mode operator-mode))
         (dossier (maybe-expand-retrieval-dossier session
                                                  intent
                                                  (build-retrieval-dossier-from-plan session intent plan))))
    (setf (retrieval-dossier-ranking dossier)
          (build-retrieval-ranking prompt dossier))
    dossier))
