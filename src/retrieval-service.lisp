(in-package #:sbcl-agent)

(defun retrieval-string-preview (value &optional (limit 240))
  (let ((text (and value (princ-to-string value))))
    (when text
      (if (> (length text) limit)
          (concatenate 'string (subseq text 0 limit) "...")
          text))))

(defun summarized-console-entry (entry)
  (list :entry-id (getf entry :entry-id)
        :timestamp (getf entry :timestamp)
        :type (getf entry :type)
        :category (getf entry :category)
        :source (getf entry :source)
        :message (retrieval-string-preview (getf entry :message) 220)
        :process-name (getf entry :process-name)
        :pid (getf entry :pid)
        :thread-id (getf entry :thread-id)
        :activity-id (getf entry :activity-id)
        :runtime-id (getf entry :runtime-id)
        :work-item-id (getf entry :work-item-id)
        :workflow-record-id (getf entry :workflow-record-id)
        :incident-id (getf entry :incident-id)))

(defun summarized-diagnostic-report (report)
  (list :report-id (getf report :report-id)
        :kind (getf report :kind)
        :source (getf report :source)
        :process-name (getf report :process-name)
        :created-at (getf report :created-at)
        :bytes (getf report :bytes)
        :pid (getf report :pid)
        :incident-id (getf report :incident-id)
        :bug-type (getf report :bug-type)
        :responsible-process (getf report :responsible-process)
        :summary (retrieval-string-preview (getf report :summary) 180)
        :preview (retrieval-string-preview (getf report :preview) 240)))

(defun summarized-source-items (items &key (limit 4))
  (mapcar (lambda (item)
            (list :path (getf item :path)
                  :line (getf item :line)
                  :text (retrieval-string-preview (getf item :text) 180)
                  :definition-kind (getf item :definition-kind)))
          (subseq items 0 (min limit (length items)))))

(defun summarized-method-items (items &key (limit 4))
  (subseq items 0 (min limit (length items))))

(defun summarized-source-context (context)
  (when context
    (list :workspace-root (getf context :workspace-root)
          :package (getf context :package)
          :loaded-systems (subseq (or (getf context :loaded-systems) '())
                                  0
                                  (min 8 (length (or (getf context :loaded-systems) '()))))
          :symbol-target (getf context :symbol-target)
          :describe (getf context :describe)
          :definitions (let ((definitions (getf context :definitions)))
                         (and definitions
                              (list :count (getf definitions :count)
                                    :items (summarized-source-items (or (getf definitions :items) '())))))
          :callers (let ((callers (getf context :callers)))
                     (and callers
                          (list :count (getf callers :count)
                                :items (summarized-source-items (or (getf callers :items) '())))))
          :methods (let ((methods (getf context :methods)))
                     (and methods
                          (list :count (getf methods :count)
                                :items (summarized-method-items (or (getf methods :items) '())))))
          :divergence (getf context :divergence)
          :note (getf context :note))))

(defun summarized-transcript-memory-entry (entry)
  (list :entry-index (getf entry :entry-index)
        :role (getf entry :role)
        :content (retrieval-string-preview (getf entry :content) 240)
        :match-score (getf entry :match-score)
        :distance-from-latest (getf entry :distance-from-latest)))

(defun summarized-operator-memory-entry (entry)
  (list :memory-id (getf entry :memory-id)
        :category (getf entry :category)
        :attribute (getf entry :attribute)
        :value (retrieval-string-preview (getf entry :value) 180)
        :summary (retrieval-string-preview (getf entry :summary) 240)
        :confidence (getf entry :confidence)
        :score (getf entry :score)
        :updated-at (getf entry :updated-at)
        :recorded-at (getf entry :recorded-at)))

(defun summarized-conversation-context (context)
  (when context
    (list :thread (getf context :thread)
          :turn (getf context :turn)
          :recent-transcript (getf context :recent-transcript)
          :transcript-memory (let ((memory (getf context :transcript-memory)))
                               (and memory
                                    (list :query (getf memory :query)
                                          :transcript-count (getf memory :transcript-count)
                                          :entry-count (length (or (getf memory :entries) '()))
                                          :entries (mapcar #'summarized-transcript-memory-entry
                                                           (or (getf memory :entries) '())))))
          :operator-memory (let ((memory (getf context :operator-memory)))
                             (and memory
                                  (list :query (getf memory :query)
                                        :entry-count (length (or (getf memory :entries) '()))
                                        :entries (mapcar #'summarized-operator-memory-entry
                                                         (or (getf memory :entries) '())))))
          :limit (getf context :limit))))

(defun summarized-console-context (context)
  (when context
    (list :summary (getf context :summary)
          :focus-tokens (getf context :focus-tokens)
          :environment-entry-count (length (or (getf context :environment-entries) '()))
          :host-entry-count (length (or (getf context :host-entries) '()))
          :environment-entries (mapcar #'summarized-console-entry
                                       (or (getf context :environment-entries) '()))
          :host-entries (mapcar #'summarized-console-entry
                                (or (getf context :host-entries) '())))))

(defun summarized-diagnostic-context (context)
  (when context
    (list :summary (getf context :summary)
          :focus-tokens (getf context :focus-tokens)
          :report-count (getf context :report-count)
          :reports (mapcar #'summarized-diagnostic-report
                           (or (getf context :reports) '())))))

(defun summarized-testing-failure (entry)
  (list :name (getf entry :name)
        :category (getf entry :category)
        :status (getf entry :status)
        :duration-seconds (getf entry :duration-seconds)
        :error (retrieval-string-preview (getf entry :error) 220)))

(defun summarized-testing-harness (entry)
  (list :id (getf entry :id)
        :label (getf entry :label)
        :entrypoint (getf entry :entrypoint)
        :kind (getf entry :kind)
        :categories (getf entry :categories)))

(defun summarized-testing-context (context)
  (when context
    (list :summary (getf context :summary)
          :focus-tokens (getf context :focus-tokens)
          :harnesses (mapcar #'summarized-testing-harness
                             (or (getf context :harnesses) '()))
          :latest-report (getf context :latest-report)
          :failure-count (length (or (getf context :failures) '()))
          :failures (mapcar #'summarized-testing-failure
                            (or (getf context :failures) '()))
          :coverage (getf context :coverage)
          :performance (getf context :performance)
          :linked-work-items (getf context :linked-work-items)
          :replay-groups (getf context :replay-groups))))

(defun summarized-intent-context (context)
  (when context
    (list :current-intent-id (getf context :current-intent-id)
          :intent-count (getf context :intent-count)
          :intents (compact-list (or (getf context :intents) '()) 6)
          :summary (getf context :summary)
          :scope (getf context :scope)
          :constraints (compact-list (or (getf context :constraints) '()) 6)
          :expected-behaviors (compact-list (or (getf context :expected-behaviors) '()) 6)
          :non-goals (compact-list (or (getf context :non-goals) '()) 6)
          :linked-runtime-objects (compact-list (or (getf context :linked-runtime-objects) '()) 6)
          :linked-source-artifacts (compact-list (or (getf context :linked-source-artifacts) '()) 6)
          :linked-event-ids (compact-list (or (getf context :linked-event-ids) '()) 6)
          :linked-mutation-ids (compact-list (or (getf context :linked-mutation-ids) '()) 6))))

(defun summarized-project-context (context)
  (when context
    (list :current-project-id (getf context :current-project-id)
          :project-count (getf context :project-count)
          :projects (getf context :projects)
          :summary (getf context :summary)
          :constitution (let ((constitution (getf context :constitution)))
                          (and constitution
                               (list :mission (getf constitution :mission)
                                     :principles (compact-list (or (getf constitution :principles) '()) 6)
                                     :constraints (compact-list (or (getf constitution :constraints) '()) 6))))
          :requirements (compact-list (or (getf context :requirements) '()) 6)
          :feature-specifications (compact-list (or (getf context :feature-specifications) '()) 6)
          :user-journeys (compact-list (or (getf context :user-journeys) '()) 6)
          :non-functional-requirements (compact-list (or (getf context :non-functional-requirements) '()) 6)
          :architecture-decisions (compact-list (or (getf context :architecture-decisions) '()) 6)
          :linked-work-items (compact-list (or (getf context :linked-work-items) '()) 6)
          :linked-incidents (compact-list (or (getf context :linked-incidents) '()) 6)
          :linked-testing-harnesses (compact-list (or (getf context :linked-testing-harnesses) '()) 6)
          :testing-evidence (getf context :testing-evidence)
          :quality-gate-evidence (getf context :quality-gate-evidence)
          :design-system (let ((design-system (getf context :design-system)))
                           (and design-system
                                (list :tokens (compact-list (or (getf design-system :tokens) '()) 6)
                                      :components (compact-list (or (getf design-system :components) '()) 6)
                                      :interaction-rules (compact-list (or (getf design-system :interaction-rules) '()) 6))))
          :style-guide (let ((style-guide (getf context :style-guide)))
                         (and style-guide
                              (list :voice (getf style-guide :voice)
                                    :rules (compact-list (or (getf style-guide :rules) '()) 6))))
          :source-roots (compact-list (or (getf context :source-roots) '()) 6))))

(defun summarized-trace-neighborhood (summary)
  (when summary
    (list :entity-kind (getf summary :entity-kind)
          :entity-id (getf summary :entity-id)
          :count (getf summary :count)
          :outbound (compact-list (or (getf summary :outbound) '()) 6)
          :inbound (compact-list (or (getf summary :inbound) '()) 6))))

(defun summarized-trace-context (context)
  (when context
    (list :summary (getf context :summary)
          :link-count (getf context :link-count)
          :intent-neighborhood (summarized-trace-neighborhood
                                (getf context :intent-neighborhood))
          :project-neighborhood (summarized-trace-neighborhood
                                 (getf context :project-neighborhood))
          :work-item-neighborhoods (mapcar #'summarized-trace-neighborhood
                                           (or (getf context :work-item-neighborhoods) '()))
          :incident-neighborhoods (mapcar #'summarized-trace-neighborhood
                                          (or (getf context :incident-neighborhoods) '()))
          :focused-links (mapcar #'trace-link-summary
                                 (compact-list (or (getf context :focused-links) '()) 8)))))

(defun patch-result-paths (result)
  (when (listp result)
    (remove nil
            (mapcan (lambda (patch-entry)
                      (cond
                        ((and (listp patch-entry) (getf patch-entry :path))
                         (list (getf patch-entry :path)))
                        ((and (listp patch-entry)
                              (listp (getf patch-entry :result))
                              (getf (getf patch-entry :result) :path))
                         (list (getf (getf patch-entry :result) :path)))
                        (t nil)))
                    (or (getf result :patch)
                        result)))))

(defun action-result-summary-entry (entry)
  (let* ((action (getf entry :action))
         (result (or (getf entry :result) '()))
         (payload (and action (assistant-action-payload action)))
         (tool-id (and action
                       (eq (assistant-action-type action) :tool)
                       payload
                       (or (getf payload :tool-id)
                           (getf payload :TOOL-ID)
                           (getf payload :tool_id)
                           (getf payload :TOOL_ID))))
         (paths (cond
                  ((eq (and action (assistant-action-type action)) :patch)
                   (remove nil
                           (mapcar (lambda (patch-op)
                                     (and (listp patch-op)
                                         (second patch-op)))
                                   payload)))
                  ((or (eq (and action (assistant-action-type action)) :patch)
                       (and tool-id
                            (member tool-id '(:workspace/write :workspace/apply-patch)
                                    :test #'eq)))
                   (patch-result-paths result))
                  (t
                   nil))))
    (list :action-type (and action (assistant-action-type action))
          :tool-id tool-id
          :status (or (getf entry :status) :completed)
          :mutating-p (and action
                           (eq (assistant-action-type action) :eval)
                           (mutating-eval-action-p action))
          :paths paths
          :error (getf entry :error))))

(defun action-result-retrieval-domains (entry)
  (let* ((action (getf entry :action))
         (status (or (getf entry :status) :completed))
         (domains '()))
    (when action
      (case (assistant-action-type action)
        (:patch
         (setf domains (append domains '(:workspace :artifact :workflow :events))))
        (:eval
         (setf domains (append domains
                               (if (mutating-eval-action-p action)
                                   '(:runtime :workflow :artifact :events)
                                   '(:runtime :events)))))
        (:tool
         (setf domains (append domains
                               (if (governed-assistant-action-p action)
                                   '(:workflow :artifact :events)
                                   '(:events)))))))
    (when (eq status :failed)
      (setf domains (append domains '(:incident :workflow :events))))
    (remove-duplicates domains :test #'eq)))

(defun copy-retrieval-intent-with-domains (intent domains)
  (make-retrieval-intent
   :category (retrieval-intent-category intent)
   :domains domains
   :historical-p (retrieval-intent-historical-p intent)
   :intent-context-p (or (retrieval-intent-intent-context-p intent)
                         (member :intent domains :test #'eq))
   :runtime-inspection-p (or (retrieval-intent-runtime-inspection-p intent)
                             (member :runtime domains :test #'eq))
   :governance-context-p (or (retrieval-intent-governance-context-p intent)
                             (member :workflow domains :test #'eq)
                             (member :incident domains :test #'eq))
   :observability-context-p (or (retrieval-intent-observability-context-p intent)
                                (member :telemetry domains :test #'eq)
                                (member :console domains :test #'eq))
   :testing-context-p (or (retrieval-intent-testing-context-p intent)
                          (member :testing domains :test #'eq))
   :project-context-p (or (retrieval-intent-project-context-p intent)
                          (member :project domains :test #'eq))
   :source-context-p (or (retrieval-intent-source-context-p intent)
                         (member :workspace domains :test #'eq))
   :mutation-likely-p t
   :explanation (retrieval-intent-explanation intent)))

(defun copy-retrieval-plan-with-domains (plan intent domains)
  (let ((limits (copy-list (retrieval-plan-per-domain-limits plan))))
    (dolist (domain domains)
      (unless (getf limits domain)
        (setf limits (append limits
                             (list domain
                                   (retrieval-domain-limit intent domain))))))
    (make-retrieval-plan
     :intent intent
     :domains domains
     :per-domain-limits limits
     :expansion-posture :expand-on-gap
     :runtime-detail-p (or (retrieval-plan-runtime-detail-p plan)
                           (member :runtime domains :test #'eq))
     :governance-detail-p (or (retrieval-plan-governance-detail-p plan)
                              (member :workflow domains :test #'eq)
                              (member :incident domains :test #'eq))
     :project-detail-p (or (retrieval-plan-project-detail-p plan)
                           (member :project domains :test #'eq))
     :source-detail-p (or (retrieval-plan-source-detail-p plan)
                          (member :workspace domains :test #'eq))
     :semantic-ranking-p (retrieval-plan-semantic-ranking-p plan)
     :explanation "Post-mutation retrieval widened the domain set to inspect observed consequences.")))

(defun build-post-mutation-retrieval-dossier (session prompt action-results
                                              &key (operator-mode :conversation))
  (let* ((base (build-retrieval-dossier session prompt :operator-mode operator-mode))
         (observed (mapcar #'action-result-summary-entry action-results))
         (result-domains (remove-duplicates
                          (mapcan #'action-result-retrieval-domains action-results)
                          :test #'eq))
         (domains (remove-duplicates
                   (append (retrieval-intent-domains (retrieval-dossier-intent base))
                           result-domains)
                   :test #'eq))
         (intent (copy-retrieval-intent-with-domains (retrieval-dossier-intent base) domains))
         (plan (copy-retrieval-plan-with-domains (retrieval-dossier-plan base)
                                                 intent
                                                 domains)))
    (make-retrieval-dossier
     :phase :post-mutation
     :intent intent
     :alignment-intent-context (when (find :intent domains :test #'eq)
                                 (build-intent-dossier-section session plan))
     :plan plan
     :observed-consequences observed
     :conversation-context (when (find :conversation domains :test #'eq)
                             (or (retrieval-dossier-conversation-context base)
                                 (build-conversation-dossier-section session prompt plan)))
     :runtime-context (when (find :runtime domains :test #'eq)
                        (build-runtime-dossier-section session plan))
     :telemetry-context (when (find :telemetry domains :test #'eq)
                          (build-telemetry-dossier-section session plan))
     :workflow-context (when (find :workflow domains :test #'eq)
                         (build-workflow-dossier-section session plan))
     :incident-context (when (find :incident domains :test #'eq)
                         (build-incident-dossier-section session plan))
     :artifact-context (when (find :artifact domains :test #'eq)
                         (build-artifact-dossier-section session))
     :environment-context (build-environment-dossier-section plan)
     :console-context (when (find :console domains :test #'eq)
                        (build-console-dossier-section prompt plan))
     :diagnostic-context (when (find :diagnostic domains :test #'eq)
                           (build-diagnostic-dossier-section prompt plan))
     :testing-context (when (find :testing domains :test #'eq)
                        (build-testing-dossier-section session prompt plan))
     :project-context (when (find :project domains :test #'eq)
                        (build-project-dossier-section session plan))
     :source-context (when (find :workspace domains :test #'eq)
                       (build-source-dossier-section session prompt plan))
     :trace-context (when (or (find :intent domains :test #'eq)
                              (find :project domains :test #'eq)
                              (find :workflow domains :test #'eq)
                              (find :incident domains :test #'eq))
                      (build-trace-dossier-section session
                                                   plan
                                                   (when (find :intent domains :test #'eq)
                                                     (build-intent-dossier-section session plan))
                                                   (when (find :project domains :test #'eq)
                                                     (build-project-dossier-section session plan))
                                                   (when (find :workflow domains :test #'eq)
                                                     (build-workflow-dossier-section session plan))
                                                   (when (find :incident domains :test #'eq)
                                                     (build-incident-dossier-section session plan))))
     :gaps (append (when (and (find :workspace domains :test #'eq)
                              (null (build-source-dossier-section session prompt plan)))
                     (list "Workspace retrieval was requested after mutation but no source context was assembled."))
                   (when (and (find :artifact domains :test #'eq)
                              (null (build-artifact-dossier-section session)))
                     (list "Artifact retrieval was requested after mutation but no artifact context was assembled."))))))

(defun retrieval-dossier->plist (dossier)
  (let ((intent (retrieval-dossier-intent dossier))
        (plan (retrieval-dossier-plan dossier)))
    (list :phase (retrieval-dossier-phase dossier)
          :intent (list :category (retrieval-intent-category intent)
                        :domains (retrieval-intent-domains intent)
                        :historical-p (retrieval-intent-historical-p intent)
                        :intent-context-p (retrieval-intent-intent-context-p intent)
                        :runtime-inspection-p (retrieval-intent-runtime-inspection-p intent)
                        :governance-context-p (retrieval-intent-governance-context-p intent)
                        :observability-context-p (retrieval-intent-observability-context-p intent)
                        :testing-context-p (retrieval-intent-testing-context-p intent)
                        :project-context-p (retrieval-intent-project-context-p intent)
                        :source-context-p (retrieval-intent-source-context-p intent)
                        :mutation-likely-p (retrieval-intent-mutation-likely-p intent)
                        :explanation (retrieval-intent-explanation intent))
          :plan (list :domains (retrieval-plan-domains plan)
                      :per-domain-limits (retrieval-plan-per-domain-limits plan)
                      :expansion-posture (retrieval-plan-expansion-posture plan)
                      :expansion-pass (retrieval-plan-expansion-pass plan)
                      :runtime-detail-p (retrieval-plan-runtime-detail-p plan)
                      :governance-detail-p (retrieval-plan-governance-detail-p plan)
                      :project-detail-p (retrieval-plan-project-detail-p plan)
                      :source-detail-p (retrieval-plan-source-detail-p plan)
                      :semantic-ranking-p (retrieval-plan-semantic-ranking-p plan)
                      :explanation (retrieval-plan-explanation plan))
          :ranking (retrieval-dossier-ranking dossier)
          :observed-consequences (retrieval-dossier-observed-consequences dossier)
          :conversation-context (summarized-conversation-context
                                 (retrieval-dossier-conversation-context dossier))
          :runtime-context (retrieval-dossier-runtime-context dossier)
          :telemetry-context (retrieval-dossier-telemetry-context dossier)
          :workflow-context (retrieval-dossier-workflow-context dossier)
          :incident-context (retrieval-dossier-incident-context dossier)
          :artifact-context (retrieval-dossier-artifact-context dossier)
          :environment-context (retrieval-dossier-environment-context dossier)
          :console-context (summarized-console-context (retrieval-dossier-console-context dossier))
          :diagnostic-context (summarized-diagnostic-context (retrieval-dossier-diagnostic-context dossier))
          :testing-context (summarized-testing-context (retrieval-dossier-testing-context dossier))
          :alignment-intent-context (summarized-intent-context
                                     (retrieval-dossier-alignment-intent-context dossier))
          :project-context (summarized-project-context (retrieval-dossier-project-context dossier))
          :source-context (summarized-source-context (retrieval-dossier-source-context dossier))
          :trace-context (summarized-trace-context (retrieval-dossier-trace-context dossier))
          :gaps (retrieval-dossier-gaps dossier))))

(defun summarized-alignment-event-entry (entry)
  (list :id (getf entry :id)
        :cursor (getf entry :cursor)
        :kind (getf entry :kind)
        :family (getf entry :family)
        :timestamp (getf entry :timestamp)
        :entity-id (getf entry :entity-id)
        :thread-id (getf entry :thread-id)
        :turn-id (getf entry :turn-id)
        :work-item-id (getf entry :work-item-id)
        :operation-id (getf entry :operation-id)))

(defun find-linked-event-entry (event-entries event-id)
  (find event-id
        event-entries
        :test #'string=
        :key (lambda (entry)
               (or (getf entry :id)
                   (getf (getf entry :metadata) :source-event-id)))))

(defun resolved-alignment-events (intent-context event-stream)
  (let* ((linked-event-ids (copy-list (or (getf intent-context :linked-event-ids) '())))
         (event-entries (or (getf event-stream :events) '())))
    (mapcar #'summarized-alignment-event-entry
            (remove nil
                    (mapcar (lambda (event-id)
                              (find-linked-event-entry event-entries event-id))
                            linked-event-ids)))))

(defun resolved-alignment-mutations (session intent-context)
  (let ((linked-mutation-ids (copy-list (or (getf intent-context :linked-mutation-ids) '()))))
    (remove nil
            (mapcar (lambda (mutation-id)
                      (let ((operation (find-operation session mutation-id)))
                        (and operation
                             (operation-record-summary operation))))
                    linked-mutation-ids))))

(defun alignment-context-constraints (intent-context project-context)
  (append (copy-list (or (getf intent-context :constraints) '()))
          (copy-list (or (and project-context
                              (getf (getf project-context :constitution) :constraints))
                         '()))))

(defun alignment-context-history (dossier)
  (list :conversation (let ((context (retrieval-dossier-conversation-context dossier)))
                        (and context
                             (list :thread (getf context :thread)
                                   :turn (getf context :turn))))
        :runtime (let ((context (retrieval-dossier-runtime-context dossier)))
                   (and context
                        (getf context :history)))
        :observed-consequences (retrieval-dossier-observed-consequences dossier)))

(defun alignment-context-validation-state (dossier environment-status)
  (let* ((testing-context (retrieval-dossier-testing-context dossier))
         (project-context (retrieval-dossier-project-context dossier))
         (workflow-context (retrieval-dossier-workflow-context dossier))
         (operator-posture (getf environment-status :operator-posture)))
    (list :testing (and testing-context
                        (list :latest-report (getf testing-context :latest-report)
                              :failure-count (length (or (getf testing-context :failures) '()))
                              :replay-group-count (length (or (getf testing-context :replay-groups) '()))))
          :project-readiness (and project-context
                                  (getf project-context :readiness-summary))
          :workflow (and workflow-context
                         (list :work-item-count (length (or (getf workflow-context :work-items) '()))
                               :workflow-record-count (length (or (getf workflow-context :workflow-records) '()))))
          :operator-posture operator-posture)))

(defun derive-alignment-gaps (intent-context project-context source-context validation-state
                               linked-events linked-mutations dossier)
  (let ((gaps (copy-list (or (retrieval-dossier-gaps dossier) '()))))
    (dolist (event-id (or (getf intent-context :linked-event-ids) '()))
      (unless (find event-id linked-events :test #'string= :key (lambda (entry) (getf entry :id)))
        (push (list :type :missing-linked-event
                    :event-id event-id
                    :severity :medium)
              gaps)))
    (dolist (mutation-id (or (getf intent-context :linked-mutation-ids) '()))
      (unless (find mutation-id linked-mutations :test #'string= :key (lambda (entry) (getf entry :id)))
        (push (list :type :missing-linked-mutation
                    :mutation-id mutation-id
                    :severity :medium)
              gaps)))
    (let ((source-divergence (and source-context
                                  (getf source-context :divergence))))
      (when source-divergence
        (push (list :type :source-divergence
                    :detail source-divergence
                    :severity :high)
              gaps)))
    (let* ((testing (getf validation-state :testing))
           (failure-count (or (and testing (getf testing :failure-count)) 0)))
      (when (> failure-count 0)
        (push (list :type :testing-failures-present
                    :failure-count failure-count
                    :severity :high)
              gaps)))
    (let ((project-readiness (and project-context
                                  (getf validation-state :project-readiness))))
      (when (and project-readiness
                 (not (eq (getf project-readiness :status) :ready)))
        (push (list :type :project-readiness-blocked
                    :status (getf project-readiness :status)
                    :obligations (copy-list (or (getf project-readiness :obligations) '()))
                    :severity :high)
              gaps)))
    (nreverse gaps)))

(defun alignment-linkage-state (intent-context linked-events linked-mutations)
  (list :linked-event-count (length (or (getf intent-context :linked-event-ids) '()))
        :resolved-event-count (length linked-events)
        :linked-mutation-count (length (or (getf intent-context :linked-mutation-ids) '()))
        :resolved-mutation-count (length linked-mutations)))

(defun build-alignment-context-packet (session prompt &key (operator-mode :conversation))
  (let* ((dossier (build-retrieval-dossier session prompt :operator-mode operator-mode))
         (environment-status (service-response-data
                              (query-environment-status-service
                               (or (session-bound-environment session)
                                   (ensure-environment))
                               :include-alignment-state-p nil
                               :include-reconciliation-decision-p nil)))
         (environment-summary (getf environment-status :summary))
         (intent-context (retrieval-dossier-alignment-intent-context dossier))
         (project-context (retrieval-dossier-project-context dossier))
         (source-context (retrieval-dossier-source-context dossier))
         (runtime-context (retrieval-dossier-runtime-context dossier))
         (event-stream (service-response-data
                        (query-service-event-stream
                         :environment (or (session-bound-environment session)
                                          (ensure-environment))
                         :limit 16)))
         (linked-events (resolved-alignment-events intent-context event-stream))
         (linked-mutations (resolved-alignment-mutations session intent-context))
         (validation-state (alignment-context-validation-state dossier environment-status)))
    (list :intent intent-context
          :agent (list :session-id (compatibility-session-id session)
                       :environment-id (getf environment-summary :id)
                       :provider-profile (getf environment-status :provider-profile)
                       :active-thread (getf environment-status :active-thread)
                       :active-runtime (getf environment-status :active-runtime))
          :runtime-scope (and runtime-context
                              (list :summary (getf runtime-context :summary)
                                    :history (getf runtime-context :history)
                                    :linked-runtime-objects (copy-list
                                                             (or (getf intent-context :linked-runtime-objects) '()))))
          :source-scope (and source-context
                             (list :workspace-root (getf source-context :workspace-root)
                                   :package (getf source-context :package)
                                   :symbol-target (getf source-context :symbol-target)
                                   :definitions (getf source-context :definitions)
                                   :callers (getf source-context :callers)
                                   :methods (getf source-context :methods)
                                   :divergence (getf source-context :divergence)
                                   :linked-source-artifacts (copy-list
                                                             (or (getf intent-context :linked-source-artifacts) '()))))
          :relevant-events (list :linked-event-ids (copy-list (or (getf intent-context :linked-event-ids) '()))
                                 :resolved-linked-events linked-events
                                 :recent-events (mapcar #'summarized-alignment-event-entry
                                                        (or (getf event-stream :events) '())))
          :mutation-scope (list :linked-mutation-ids (copy-list (or (getf intent-context :linked-mutation-ids) '()))
                                :resolved-linked-mutations linked-mutations)
          :linkage-state (alignment-linkage-state intent-context linked-events linked-mutations)
          :constraints (alignment-context-constraints intent-context project-context)
          :history (alignment-context-history dossier)
          :validation-state validation-state
          :alignment-gaps (derive-alignment-gaps intent-context
                                                 project-context
                                                 source-context
                                                 validation-state
                                                 linked-events
                                                 linked-mutations
                                                 dossier))))

(defun query-retrieval-dossier-service (session prompt &key (operator-mode :repl-bridge))
  (let ((dossier (build-retrieval-dossier session
                                          prompt
                                          :operator-mode operator-mode)))
    (make-service-query-response :retrieval
                                 :dossier
                                 (retrieval-dossier->plist dossier)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :retrieval-dossier-v1
                                                                  :session session))))

(defun query-alignment-context-packet-service (session prompt &key (operator-mode :conversation))
  (make-service-query-response
   :retrieval
   :alignment-context-packet
   (build-alignment-context-packet session prompt :operator-mode operator-mode)
   :metadata (make-service-metadata :authority :environment
                                    :read-model :alignment-context-packet-v1
                                    :session session)))

(defun query-post-mutation-retrieval-dossier-service (session prompt action-results
                                                      &key (operator-mode :conversation))
  (let ((dossier (build-post-mutation-retrieval-dossier session
                                                        prompt
                                                        action-results
                                                        :operator-mode operator-mode)))
    (setf (retrieval-dossier-ranking dossier)
          (build-retrieval-ranking prompt dossier))
    (make-service-query-response :retrieval
                                 :dossier
                                 (retrieval-dossier->plist dossier)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :retrieval-dossier-v1
                                                                  :session session))))
