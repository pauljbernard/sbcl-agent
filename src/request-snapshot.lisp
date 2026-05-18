(in-package #:sbcl-agent)

(defstruct provider-environment-snapshot
  environment
  environment-summary
  conversation-state
  workflow-state
  incident-summary)

(defstruct provider-context-bundle
  snapshot
  session-summary
  thread-context
  turn-context
  environment-context
  surface-context
  surface-actions
  runtime-summary
  workspace-summary
  policy-summary
  retrieval-dossier
  cognition-bundle
  reasoning-brief
  planning-brief
  planning-context-packet
  outcome-brief)

(defstruct provider-request-snapshot
  generated-at
  domain-generated-at
  session-summary
  thread-context
  turn-context
  environment-context
  surface-context
  surface-actions
  runtime-summary
  workspace-summary
  policy-summary
  retrieval-dossier
  cognition-bundle
  reasoning-brief
  planning-brief
  planning-context-packet
  outcome-brief
  cached-context-entries
  cached-context-index)

(defparameter +provider-request-snapshot-cache-key+ :provider-request-snapshot-cache)
(defparameter +provider-request-snapshot-refresh-pending-key+
  :provider-request-snapshot-refresh-pending-p)
(defparameter +provider-request-snapshot-dirty-at-key+
  :provider-request-snapshot-dirty-at)
(defparameter +provider-request-snapshot-dirty-domain-times-key+
  :provider-request-snapshot-dirty-domain-times)
(defparameter +provider-request-snapshot-dirty-reasons-key+
  :provider-request-snapshot-dirty-reasons)
(defparameter +provider-request-snapshot-dirty-domains-key+
  :provider-request-snapshot-dirty-domains)
(defparameter +provider-request-snapshot-stale-seconds+ 15)
(defparameter *provider-request-snapshot-cache-lock*
  (sb-thread:make-mutex :name "sbcl-agent-provider-request-snapshot-cache"))

(defparameter +provider-request-snapshot-known-domains+
  '(:conversation :runtime :workspace :policy :environment))

(defun normalize-provider-request-dirty-domain (domain)
  (case domain
    ((:conversation) :conversation)
    ((:runtime) :runtime)
    ((:workspace :project :artifact :events :workflow :testing) :workspace)
    ((:incident :telemetry :console :diagnostic) :runtime)
    ((:intent :policy) :policy)
    ((:environment) :environment)
    (otherwise nil)))

(defun normalize-provider-request-dirty-domains (domains)
  (let ((normalized '()))
    (dolist (domain domains)
      (let ((mapped (normalize-provider-request-dirty-domain domain)))
        (when mapped
          (pushnew mapped normalized :test #'eq))))
    (nreverse normalized)))

(defun limited-planning-context-list (entries &key (limit 4))
  (subseq (or entries '()) 0 (min limit (length (or entries '())))))

(defun provider-planning-context-task-frame (prompt operator-mode stream-p retrieval-dossier)
  (let ((intent (and (listp retrieval-dossier) (getf retrieval-dossier :intent))))
    (list :prompt prompt
          :operator-mode operator-mode
          :stream-requested stream-p
          :task-archetype (and intent (getf intent :task-archetype))
          :primary-intent (and intent (getf intent :primary-intent))
          :secondary-intents (limited-planning-context-list
                              (and intent (getf intent :secondary-intents))
                              :limit 4)
          :requested-deliverable (and intent (getf intent :requested-deliverable))
          :phase-intent (and intent (getf intent :phase-intent))
          :domains (limited-planning-context-list
                    (and intent (getf intent :domains))
                    :limit 6))))

(defun provider-planning-context-linked-project-summaries (session current-project-id &optional (limit 4))
  (when session
    (limited-planning-context-list
     (remove nil
             (mapcar (lambda (project)
                       (unless (and current-project-id
                                    (string= (project-record-id project) current-project-id))
                         (project-summary project)))
                     (or (list-project-records session) '())))
     :limit limit)))

(defun provider-planning-project-alignment-field-tokens (value)
  (remove-duplicates
   (prompt-match-tokens
    (string-downcase
     (with-output-to-string (stream)
       (labels ((emit-value (entry)
                  (cond
                    ((null entry) nil)
                    ((listp entry) (dolist (nested entry) (emit-value nested)))
                    (t
                     (princ entry stream)
                     (write-char #\Space stream)))))
         (emit-value value)))))
   :test #'string=))

(defparameter +provider-planning-project-alignment-stopwords+
  '("project" "context" "planning" "plan" "state" "runtime" "environment"
    "provider" "response" "decisive" "evidence" "posture" "inspect" "detail"
    "current" "govern" "governed" "changes" "change" "validate" "validation"
    "explain" "identify" "should" "what" "which" "under" "with" "into"))

(defun provider-planning-project-relevant-tokens (value)
  (remove-if (lambda (token)
               (or (< (length token) 4)
                   (member token +provider-planning-project-alignment-stopwords+ :test #'string=)))
             (provider-planning-project-alignment-field-tokens value)))

(defun provider-planning-project-alignment-score (prompt project-summary &optional project-record)
  (let* ((prompt-tokens (remove-duplicates (provider-planning-project-relevant-tokens prompt) :test #'string=))
         (weighted-fields
          (remove nil
                  (list (list :weight 3
                              :tokens (provider-planning-project-relevant-tokens
                                       (list (getf project-summary :id)
                                             (getf project-summary :title)
                                             (getf project-summary :source-roots))))
                        (and project-record
                             (list :weight 2
                                   :tokens (provider-planning-project-relevant-tokens
                                            (project-record-constitution project-record))))
                        (and project-record
                             (list :weight 2
                                   :tokens (provider-planning-project-relevant-tokens
                                            (mapcar #'summarized-project-requirement
                                                    (or (project-record-requirements project-record) '())))))
                        (and project-record
                             (list :weight 1
                                   :tokens (provider-planning-project-relevant-tokens
                                            (mapcar #'summarized-project-architecture-decision
                                                    (or (project-record-architecture-decisions project-record) '())))))
                        (and project-record
                             (list :weight 1
                                   :tokens (provider-planning-project-relevant-tokens
                                            (mapcar #'summarized-project-feature-spec
                                                    (or (project-record-feature-specifications project-record) '()))))))))
         (field-matches
          (mapcar (lambda (field)
                    (let ((matches (loop for token in prompt-tokens
                                         count (member token (getf field :tokens) :test #'string=))))
                      (list :weight (getf field :weight)
                            :match-count matches)))
                  weighted-fields)))
    (loop for field in field-matches
          sum (* (getf field :weight) (getf field :match-count)))))

(defun provider-planning-project-selection-posture (prompt current-project-summary project-summaries
                                                     &optional project-records)
  (let* ((confidence-threshold 2)
         (record-for-summary
          (lambda (summary)
            (find (getf summary :id)
                  project-records
                  :key #'project-record-id
                  :test #'string=)))
         (current-score (and current-project-summary
                             (provider-planning-project-alignment-score prompt
                                                                       current-project-summary
                                                                       (funcall record-for-summary
                                                                                current-project-summary))))
         (linked-scores
          (remove nil
                  (mapcar (lambda (summary)
                            (unless (and current-project-summary
                                         (string= (getf summary :id)
                                                  (getf current-project-summary :id)))
                              (list :project-id (getf summary :id)
                                    :title (getf summary :title)
                                    :score (provider-planning-project-alignment-score prompt
                                                                                     summary
                                                                                     (funcall record-for-summary summary)))))
                          (or project-summaries '()))))
         (best-linked-score
          (first (sort (copy-list (remove-if-not (lambda (entry)
                                                   (> (or (getf entry :score) 0) 0))
                                                 linked-scores))
                       #'>
                       :key (lambda (entry) (or (getf entry :score) 0)))))
         (project-count (length (or project-summaries '())))
         (selection-confident-p
          (cond
            ((<= project-count 1) t)
            ((and (>= current-score confidence-threshold)
                  (or (null best-linked-score)
                      (> current-score (getf best-linked-score :score))))
             t)
            (t nil)))
         (selection-basis
          (cond
            ((<= project-count 1) :single-project)
            ((and (= current-score 0) best-linked-score) :prompt-mismatch)
            ((and (>= current-score confidence-threshold)
                  best-linked-score
                  (= current-score (getf best-linked-score :score)))
             :prompt-ambiguous)
            ((>= current-score confidence-threshold) :prompt-aligned)
            (t :weak-prompt-alignment))))
    (list :selection-confident-p selection-confident-p
          :selection-basis selection-basis
          :prompt-match-score current-score
          :best-linked-project-match best-linked-score)))

(defun provider-planning-context-project-context (session prompt retrieval-dossier)
  (let* ((project-context (and (listp retrieval-dossier)
                               (getf retrieval-dossier :project-context)))
         (explicit-selected-projects (and session
                                          (context-chat-selected-project-records session)))
         (explicit-primary-project (and session
                                        (context-chat-primary-project-record session)))
         (current-project (or explicit-primary-project
                              (and session (current-project-record session))))
         (all-project-summaries (or (and project-context (getf project-context :projects))
                                    (mapcar #'project-summary
                                            (or (and session (list-project-records session)) '()))))
         (current-project-id (or (and explicit-primary-project
                                      (project-record-id explicit-primary-project))
                                 (and current-project (project-record-id current-project))
                                 (getf project-context :current-project-id)))
         (project-count (or (and project-context (getf project-context :project-count))
                            (and session (length (or (list-project-records session) '())))
                            0))
         (linked-projects (or (and project-context (getf project-context :linked-projects))
                              (and explicit-selected-projects
                                   (mapcar #'project-summary
                                           (remove-if (lambda (project)
                                                        (and current-project-id
                                                             (string= current-project-id
                                                                      (project-record-id project))))
                                                      explicit-selected-projects)))
                              (provider-planning-context-linked-project-summaries session
                                                                                  current-project-id)))
         (linked-work-items
          (limited-planning-context-list
           (or (and project-context (getf project-context :linked-work-items))
               (and current-project
                    (remove nil
                            (mapcar (lambda (work-item-id)
                                      (summarized-project-linked-work-item session work-item-id))
                                    (or (project-record-linked-work-item-ids current-project) '()))))
               '())
           :limit 6))
         (linked-incidents
          (limited-planning-context-list
           (or (and project-context (getf project-context :linked-incidents))
               (and current-project
                    (remove nil
                            (mapcar (lambda (incident-id)
                                      (summarized-project-linked-incident session incident-id))
                                    (or (project-record-linked-incident-ids current-project) '()))))
               '())
           :limit 6))
         (selected-project-source (or (and explicit-selected-projects
                                           :explicit-context-chat-selection)
                                      (and project-context
                                           (getf project-context :selected-project-source))
                                      (and current-project :session-selection)
                                      :none))
         (ambiguity-risk (or (and project-context
                                  (getf project-context :ambiguity-risk))
                             (cond
                               ((and explicit-selected-projects
                                     (> (length explicit-selected-projects) 1))
                                :explicit-multi-project)
                               ((> project-count 1) :multi-project)
                               ((= project-count 1) :single-project)
                               (t :none))))
         (derived-selection-posture
          (if explicit-selected-projects
              (list :selection-confident-p t
                    :selection-basis :explicit-context-chat-selection
                    :prompt-match-score nil
                    :matching-linked-project-count
                    (max 0 (1- (length explicit-selected-projects)))
                    :best-linked-project-match nil)
              (provider-planning-project-selection-posture prompt
                                                           (or (and current-project
                                                                    (project-summary current-project))
                                                               (and project-context
                                                                    (getf project-context :summary)))
                                                           all-project-summaries
                                                           (and session (list-project-records session)))))
         (selection-confident-p (if (and (not explicit-selected-projects)
                                         project-context
                                         (member :selection-confident-p project-context))
                                    (getf project-context :selection-confident-p)
                                    (getf derived-selection-posture :selection-confident-p)))
         (selection-posture (or (and (not explicit-selected-projects)
                                     project-context
                                     (copy-tree (getf project-context :selection-posture)))
                                derived-selection-posture)))
    (when (or project-context current-project)
      (list :current-project-id current-project-id
            :selected-project-ids
            (if explicit-selected-projects
                (mapcar #'project-record-id explicit-selected-projects)
                (and current-project-id
                     (list current-project-id)))
            :primary-project-id current-project-id
            :project-count project-count
            :selected-project-source selected-project-source
            :ambiguity-risk ambiguity-risk
            :selection-confident-p selection-confident-p
            :selection-posture
            (append selection-posture
                    (list :selected-project-source selected-project-source
                          :ambiguity-risk ambiguity-risk
                          :selection-confident-p selection-confident-p))
            :summary (or (and current-project (project-summary current-project))
                         (getf project-context :summary))
            :constitution (or (and current-project
                                   (copy-list (or (project-record-constitution current-project) '())))
                              (getf project-context :constitution))
            :requirements (limited-planning-context-list
                           (or (and current-project
                                    (mapcar #'summarized-project-requirement
                                            (or (project-record-requirements current-project) '())))
                               (getf project-context :requirements))
                           :limit 6)
            :feature-specifications (limited-planning-context-list
                                     (or (and current-project
                                              (mapcar #'summarized-project-feature-spec
                                                      (or (project-record-feature-specifications current-project)
                                                          '())))
                                         (getf project-context :feature-specifications))
                                     :limit 4)
            :non-functional-requirements (limited-planning-context-list
                                          (or (and current-project
                                                   (mapcar #'summarized-project-requirement
                                                           (or (project-record-non-functional-requirements
                                                                current-project)
                                                               '())))
                                              (getf project-context :non-functional-requirements))
                                          :limit 6)
            :architecture-decisions (limited-planning-context-list
                                     (or (and current-project
                                              (mapcar #'summarized-project-architecture-decision
                                                      (or (project-record-architecture-decisions current-project)
                                                          '())))
                                         (getf project-context :architecture-decisions))
                                     :limit 4)
            :design-system (limited-planning-context-list
                            (or (and current-project
                                     (copy-list (or (project-record-design-system current-project) '())))
                                (getf project-context :design-system))
                            :limit 6)
            :style-guide (limited-planning-context-list
                          (or (and current-project
                                   (copy-list (or (project-record-style-guide current-project) '())))
                              (getf project-context :style-guide))
                          :limit 6)
            :source-roots (limited-planning-context-list
                           (or (and current-project
                                    (copy-list (or (project-record-source-roots current-project) '())))
                               (getf project-context :source-roots))
                           :limit 6)
            :readiness-summary (getf project-context :readiness-summary)
            :readiness-obligations (limited-planning-context-list
                                    (getf project-context :readiness-obligations)
                                    :limit 6)
            :linked-work-items linked-work-items
            :linked-incidents linked-incidents
            :linked-projects linked-projects
            :quality-gate-evidence (getf project-context :quality-gate-evidence)))))

(defun provider-planning-context-authority-state (prompt session thread-context turn-context
                                                  environment-context surface-context
                                                  surface-actions runtime-summary
                                                  workspace-summary policy-summary
                                                  retrieval-dossier)
  (list :agent-constitution (and environment-context
                                 (getf environment-context :agent-constitution))
        :project-context (provider-planning-context-project-context session
                                                                   prompt
                                                                   retrieval-dossier)
        :capability-inventory (and environment-context
                                 (getf environment-context :capability-inventory))
        :thread thread-context
        :turn turn-context
        :environment environment-context
        :runtime-summary runtime-summary
        :workspace-summary workspace-summary
        :policy-summary policy-summary
        :surface-context surface-context
        :surface-actions (limited-planning-context-list surface-actions :limit 6)
        :precedence '(:agent-constitution
                      :project-context
                      :environment
                      :policy-summary
                      :capability-inventory
                      :runtime-summary
                      :workspace-summary
                      :thread
                      :turn
                      :surface-context
                      :surface-actions
                      :optional-support)
        :conflict-resolution
        '((:when (:agent-constitution :optional-support)
           :prefer :agent-constitution)
          (:when (:project-context :optional-support)
           :prefer :project-context)
          (:when (:environment :policy-summary :optional-support)
           :prefer :environment)
          (:when (:capability-inventory :optional-support)
           :prefer :capability-inventory)
          (:when (:runtime-summary :workspace-summary :optional-support)
           :prefer :runtime-summary)
          (:when (:thread :turn :optional-support)
           :prefer :turn)
          (:when (:surface-context :optional-support)
           :prefer :surface-context))))

(defun provider-planning-context-decisive-evidence (retrieval-dossier)
  (let* ((decisive-core (and (listp retrieval-dossier)
                             (getf retrieval-dossier :decisive-context-core)))
         (entries (and (listp decisive-core) (getf decisive-core :entries))))
    (list :strategy :decisive-context-first
          :explanation (and (listp decisive-core) (getf decisive-core :explanation))
          :entries (limited-planning-context-list entries :limit 5)
          :entry-count (length (or entries '())))))

(defun provider-planning-context-uncertainty-and-obligations (reasoning-brief authority-state)
  (let* ((blockers (limited-planning-context-list
                    (and reasoning-brief (getf reasoning-brief :blockers))
                    :limit 4))
         (validation-obligations (limited-planning-context-list
                                  (and reasoning-brief
                                       (getf reasoning-brief :validation-obligations))
                                  :limit 4))
         (missing-authority-facts (limited-planning-context-list
                                   (and reasoning-brief
                                        (getf reasoning-brief :missing-authority-facts))
                                   :limit 4))
         (decisive-unknowns (limited-planning-context-list
                             (and reasoning-brief
                                  (getf reasoning-brief :decisive-unknowns))
                             :limit 4))
         (conflict-candidates (limited-planning-context-list
                               (and reasoning-brief
                                    (getf reasoning-brief :conflict-candidates))
                               :limit 4))
         (authority-conflicts (limited-planning-context-list
                               (and reasoning-brief
                                    (getf reasoning-brief :authority-conflicts))
                               :limit 4))
         (project-context (and (listp authority-state)
                               (getf authority-state :project-context)))
         (project-selection-low-confidence
           (and (listp project-context)
                (> (or (getf project-context :project-count) 0) 1)
                (not (getf project-context :selection-confident-p))
                (list :kind :project-selection-low-confidence
                      :statement
                      "The current project selection is not strongly supported by prompt evidence, so project-specific constraints should be treated as provisional."
                      :source :planning-context-packet
                      :severity :high
                      :selection-posture
                      (copy-tree (or (getf project-context :selection-posture) '())))))
         (project-work-item-linkage-gap
           (and (listp authority-state)
                (listp project-context)
                (> (or (getf (getf authority-state :environment) :work-item-count) 0) 0)
                (getf project-context :current-project-id)
                (null (getf project-context :linked-work-items))
                (list :kind :project-work-item-linkage-gap
                      :statement
                      "The environment reports active governed work, but the selected project has no linked work-item evidence."
                      :source :planning-context-packet
                      :severity :high)))
         (stale-context-suspicions (limited-planning-context-list
                                    (and reasoning-brief
                                         (getf reasoning-brief :stale-context-suspicions))
                                    :limit 4))
         (next-inspection-obligations
           (limited-planning-context-list
            (and reasoning-brief
                 (getf reasoning-brief :next-inspection-obligations))
            :limit 4)))
    (when (and project-selection-low-confidence
               (not (find :project-selection-low-confidence authority-conflicts
                          :key (lambda (entry) (getf entry :kind))
                          :test #'eq)))
      (setf authority-conflicts
            (append authority-conflicts
                    (list project-selection-low-confidence))))
    (when (and project-work-item-linkage-gap
               (not (find :project-work-item-linkage-gap authority-conflicts
                          :key (lambda (entry) (getf entry :kind))
                          :test #'eq)))
      (setf authority-conflicts
            (append authority-conflicts
                    (list project-work-item-linkage-gap))))
    (list :blockers blockers
          :validation-obligations validation-obligations
          :missing-authority-facts missing-authority-facts
          :decisive-unknowns decisive-unknowns
          :conflict-candidates conflict-candidates
          :authority-conflicts authority-conflicts
          :stale-context-suspicions stale-context-suspicions
          :next-inspection-obligations next-inspection-obligations
          :escalation-required-p (or missing-authority-facts
                                   authority-conflicts
                                   conflict-candidates
                                   blockers
                                   validation-obligations)
          :escalation-priority
          (cond
            (authority-conflicts :critical)
            (missing-authority-facts :critical)
            (conflict-candidates :high)
            (blockers :high)
            (validation-obligations :medium)
            (t :low))
          :default-action
          (cond
            (authority-conflicts :resolve-authority-conflicts-before-mutate)
            (missing-authority-facts :resolve-authority-before-mutate)
            (conflict-candidates :arbitrate-conflicts-before-mutate)
            (blockers :clear-blockers-before-mutate)
            (validation-obligations :satisfy-validation-obligations)
            (decisive-unknowns :inspect-decisive-unknowns)
            (t :proceed-with-grounded-plan)))))

(defun provider-planning-context-planner-directives (retrieval-dossier reasoning-brief)
  (let* ((intent (and (listp retrieval-dossier) (getf retrieval-dossier :intent)))
         (primary-intent (and intent (getf intent :primary-intent)))
         (task-archetype (and intent (getf intent :task-archetype)))
         (mutation-likely-p (and intent (getf intent :mutation-likely-p)))
         (blockers (and reasoning-brief (getf reasoning-brief :blockers)))
         (validation-obligations
           (and reasoning-brief (getf reasoning-brief :validation-obligations)))
         (missing-authority-facts
           (and reasoning-brief (getf reasoning-brief :missing-authority-facts)))
         (authority-conflicts
           (and reasoning-brief (getf reasoning-brief :authority-conflicts)))
         (conflict-candidates
           (and reasoning-brief (getf reasoning-brief :conflict-candidates)))
         (needs-escalation-p
           (or missing-authority-facts
               authority-conflicts
               conflict-candidates
               blockers
               validation-obligations))
         (high-risk-posture-p
           (or missing-authority-facts
               authority-conflicts
               conflict-candidates
               blockers
               (and validation-obligations mutation-likely-p))))
    (list :authority-precedence '(:authority-state :decisive-evidence :uncertainty-and-obligations :strategy :optional-support)
          :uncertainty-policy (if needs-escalation-p
                                  :escalate-before-mutate
                                  :grounded-progress)
          :default-planning-posture
          (cond
            (high-risk-posture-p :stabilize-before-change)
            ((member task-archetype '(:debugging :analysis :review) :test #'eq)
             :inspect-before-change)
            ((eq task-archetype :implement-and-validate) :mutate-then-validate)
            ((member task-archetype '(:implement-change :plan-before-change) :test #'eq)
             :plan-before-mutate)
            ((member task-archetype '(:recover-remediate :workflow-supervision) :test #'eq)
             :recover-before-mutate)
            (mutation-likely-p :plan-before-mutate)
            ((eq primary-intent :recovery) :recover-before-mutate)
            (t :ground-before-conclude))
          :budget-emphasis
          (cond
            (high-risk-posture-p
             '(:uncertainty-and-obligations :authority-state :decisive-evidence :strategy :optional-support))
            ((member task-archetype '(:debugging :investigate-runtime-failure) :test #'eq)
             '(:authority-state :decisive-evidence :uncertainty-and-obligations :strategy :optional-support))
            ((eq task-archetype :implement-and-validate)
             '(:decisive-evidence :strategy :uncertainty-and-obligations :authority-state :optional-support))
            ((member task-archetype '(:implement-change :plan-before-change) :test #'eq)
             '(:decisive-evidence :strategy :authority-state :uncertainty-and-obligations :optional-support))
            ((member task-archetype '(:recover-remediate :workflow-supervision) :test #'eq)
             '(:uncertainty-and-obligations :authority-state :decisive-evidence :strategy :optional-support))
            (t
             '(:authority-state :decisive-evidence :strategy :uncertainty-and-obligations :optional-support)))
          :strategy-shape
          (cond
            (high-risk-posture-p :risk-managed)
            ((member task-archetype '(:debugging :investigate-runtime-failure) :test #'eq)
             :diagnostic)
            ((eq task-archetype :implement-and-validate)
             :implementation-with-validation)
            ((member task-archetype '(:implement-change :plan-before-change) :test #'eq)
             :implementation)
            ((member task-archetype '(:recover-remediate :workflow-supervision) :test #'eq)
             :recovery)
            ((eq task-archetype :architecture-review)
             :assessment)
            (t :general))
          :required-sections
          '(:task-frame :authority-state :decisive-evidence :uncertainty-and-obligations :strategy)
          :optional-sections '(:optional-support))))

(defun provider-planning-context-strategy-phase-order (task-archetype)
  (cond
    ((member task-archetype '(:debugging :investigate-runtime-failure) :test #'eq)
     '(:inspect :isolate :explain :plan))
    ((eq task-archetype :implement-and-validate)
     '(:inspect :plan :mutate :validate))
    ((member task-archetype '(:implement-change :plan-before-change) :test #'eq)
     '(:inspect :plan :mutate))
    ((member task-archetype '(:recover-remediate :workflow-supervision) :test #'eq)
     '(:inspect :recover :validate))
    ((eq task-archetype :architecture-review)
     '(:inspect :assess :recommend))
    (t
     '(:inspect :plan :conclude))))

(defun provider-planning-context-risk-managed-phase-order (task-archetype)
  (cond
    ((member task-archetype '(:recover-remediate :workflow-supervision) :test #'eq)
     '(:inspect :stabilize :recover :validate))
    ((member task-archetype '(:implement-change :implement-and-validate :plan-before-change) :test #'eq)
     '(:inspect :stabilize :plan :validate))
    (t
     '(:inspect :stabilize :plan))))

(defun provider-planning-context-strategy-output-shape (task-archetype requested-deliverable)
  (cond
    ((member task-archetype '(:debugging :investigate-runtime-failure) :test #'eq)
     :diagnostic-explanation)
    ((eq task-archetype :implement-and-validate)
     :patch-with-validation)
    ((member task-archetype '(:implement-change :plan-before-change) :test #'eq)
     :change-plan)
    ((member task-archetype '(:recover-remediate :workflow-supervision) :test #'eq)
     :recovery-plan)
    (requested-deliverable requested-deliverable)
    (t :grounded-response)))

(defun provider-planning-context-strategy (retrieval-dossier cognition-bundle planning-brief outcome-brief)
  (let* ((intent (and (listp retrieval-dossier) (getf retrieval-dossier :intent)))
         (task-archetype (and intent (getf intent :task-archetype)))
         (requested-deliverable (and intent (getf intent :requested-deliverable)))
         (reasoning-brief (and cognition-bundle
                               (cognition-bundle-reasoning-brief cognition-bundle)))
         (high-risk-posture-p
           (or (and reasoning-brief (getf reasoning-brief :missing-authority-facts))
               (and reasoning-brief (getf reasoning-brief :conflict-candidates))
               (and reasoning-brief (getf reasoning-brief :blockers))
               (and (and reasoning-brief (getf reasoning-brief :validation-obligations))
                    (and intent (getf intent :mutation-likely-p))))))
    (list :archetype-layout
          (cond
            (high-risk-posture-p :risk-managed)
            ((member task-archetype '(:debugging :investigate-runtime-failure) :test #'eq)
             :diagnostic)
            ((eq task-archetype :implement-and-validate)
             :implementation-with-validation)
            ((member task-archetype '(:implement-change :plan-before-change) :test #'eq)
             :implementation)
            ((member task-archetype '(:recover-remediate :workflow-supervision) :test #'eq)
             :recovery)
            ((eq task-archetype :architecture-review)
             :assessment)
            (t :general))
          :phase-order (if high-risk-posture-p
                           (provider-planning-context-risk-managed-phase-order task-archetype)
                           (provider-planning-context-strategy-phase-order task-archetype))
          :preferred-output-shape
          (provider-planning-context-strategy-output-shape task-archetype
                                                           requested-deliverable)
          :retrieval-focus (and cognition-bundle
                                (cognition-bundle-retrieval-focus-plan cognition-bundle))
          :execution-strategy (and cognition-bundle
                                   (cognition-bundle-execution-strategy cognition-bundle))
          :validation-strategy (and cognition-bundle
                                   (cognition-bundle-validation-strategy cognition-bundle))
          :validation-plan (and cognition-bundle
                                (cognition-bundle-validation-plan cognition-bundle))
          :action-agenda (and cognition-bundle
                              (cognition-bundle-action-agenda cognition-bundle))
          :ordered-steps (limited-planning-context-list
                          (and planning-brief (getf planning-brief :ordered-steps))
                          :limit 6)
          :constraints (limited-planning-context-list
                        (and planning-brief (getf planning-brief :constraints))
                        :limit 6)
          :success-criteria (limited-planning-context-list
                             (and planning-brief (getf planning-brief :success-criteria))
                             :limit 6)
          :outcome-brief outcome-brief)))

(defun provider-planning-context-optional-support (retrieval-dossier cognition-bundle session-summary)
  (let ((ranking (and (listp retrieval-dossier) (getf retrieval-dossier :ranking))))
    (list :top-ranked-context (limited-planning-context-list
                               (and ranking (getf ranking :top-candidates))
                               :limit 4)
          :prior-outcome-brief (and cognition-bundle
                                    (cognition-bundle-prior-outcome-brief cognition-bundle))
          :session-summary session-summary)))

(defun build-provider-planning-context-packet (prompt operator-mode stream-p session-summary
                                                session
                                                thread-context turn-context environment-context
                                                surface-context surface-actions runtime-summary
                                                workspace-summary policy-summary retrieval-dossier
                                                cognition-bundle reasoning-brief planning-brief
                                                outcome-brief)
  (when retrieval-dossier
    (let ((authority-state (provider-planning-context-authority-state
                            prompt
                            session
                            thread-context
                            turn-context
                            environment-context
                            surface-context
                            surface-actions
                            runtime-summary
                            workspace-summary
                            policy-summary
                            retrieval-dossier)))
      (list :task-frame (provider-planning-context-task-frame prompt
                                                              operator-mode
                                                              stream-p
                                                              retrieval-dossier)
            :planner-directives
            (provider-planning-context-planner-directives retrieval-dossier
                                                          reasoning-brief)
            :authority-state authority-state
            :decisive-evidence (provider-planning-context-decisive-evidence retrieval-dossier)
            :uncertainty-and-obligations
            (provider-planning-context-uncertainty-and-obligations reasoning-brief
                                                                   authority-state)
            :strategy (provider-planning-context-strategy retrieval-dossier
                                                          cognition-bundle
                                                          planning-brief
                                                          outcome-brief)
            :optional-support (provider-planning-context-optional-support
                               retrieval-dossier
                               cognition-bundle
                               session-summary)))))

(defun clone-provider-request-snapshot (snapshot)
  (when snapshot
    (make-provider-request-snapshot
     :generated-at (provider-request-snapshot-generated-at snapshot)
     :domain-generated-at (copy-tree (provider-request-snapshot-domain-generated-at snapshot))
     :session-summary (provider-request-snapshot-session-summary snapshot)
     :thread-context (provider-request-snapshot-thread-context snapshot)
     :turn-context (provider-request-snapshot-turn-context snapshot)
     :environment-context (provider-request-snapshot-environment-context snapshot)
     :surface-context (provider-request-snapshot-surface-context snapshot)
     :surface-actions (provider-request-snapshot-surface-actions snapshot)
     :runtime-summary (provider-request-snapshot-runtime-summary snapshot)
     :workspace-summary (provider-request-snapshot-workspace-summary snapshot)
     :policy-summary (provider-request-snapshot-policy-summary snapshot)
     :retrieval-dossier (provider-request-snapshot-retrieval-dossier snapshot)
     :cognition-bundle (provider-request-snapshot-cognition-bundle snapshot)
     :reasoning-brief (provider-request-snapshot-reasoning-brief snapshot)
     :planning-brief (provider-request-snapshot-planning-brief snapshot)
     :planning-context-packet (provider-request-snapshot-planning-context-packet snapshot)
     :outcome-brief (provider-request-snapshot-outcome-brief snapshot)
     :cached-context-entries (provider-request-snapshot-cached-context-entries snapshot)
     :cached-context-index (provider-request-snapshot-cached-context-index snapshot))))

(defun provider-request-snapshot-age-seconds (snapshot &optional (now (get-universal-time)))
  (let ((generated-at (and snapshot
                           (provider-request-snapshot-generated-at snapshot))))
    (when generated-at
      (max 0 (- now generated-at)))))

(defun provider-request-snapshot-domain-generated-at-value (snapshot domain)
  (or (getf (provider-request-snapshot-domain-generated-at snapshot) domain)
      (provider-request-snapshot-generated-at snapshot)))

(defun provider-request-snapshot-domain-generation-map (&optional (generated-at (get-universal-time)))
  (loop for domain in +provider-request-snapshot-known-domains+
        append (list domain generated-at)))

(defun provider-request-snapshot-refresh-domains (domains)
  (let ((normalized (normalize-provider-request-dirty-domains domains)))
    (or normalized +provider-request-snapshot-known-domains+)))

(defun provider-request-snapshot-domain-age-seconds (snapshot domain &optional (now (get-universal-time)))
  (let ((generated-at (and snapshot
                           (provider-request-snapshot-domain-generated-at-value snapshot domain))))
    (when generated-at
      (max 0 (- now generated-at)))))

(defun provider-request-snapshot-stale-p (snapshot
                                          &key (now (get-universal-time))
                                            (max-age-seconds +provider-request-snapshot-stale-seconds+))
  (let ((age (provider-request-snapshot-age-seconds snapshot now)))
    (or (null snapshot)
        (null age)
        (> age max-age-seconds))))

(defun provider-request-snapshot-domain-stale-p (snapshot domain
                                                 &key (now (get-universal-time))
                                                   (max-age-seconds +provider-request-snapshot-stale-seconds+))
  (let ((age (provider-request-snapshot-domain-age-seconds snapshot domain now)))
    (or (null snapshot)
        (null age)
        (> age max-age-seconds))))

(defun provider-request-snapshot-dirty-domains-for-reason (reason)
  (case reason
    ((:transcript) '(:conversation))
    ((:plan :pending-actions :pending-actions-cleared) '(:policy :workspace :environment))
    ((:capability-granted :capability-required) '(:policy))
    ((:patch) '(:workspace))
    ((:assistant-actions-executed) '(:runtime :workspace :policy :environment))
    ((:task-enqueued :task-started :task-completed :task-failed :task-cancelled
      :worker-started :worker-stopped)
     '(:workspace :environment))
    ((:incident :sandbox-exec :environment-test) '(:runtime :workspace :policy :environment))
    (otherwise +provider-request-snapshot-known-domains+)))

(defun provider-request-snapshot-dirty-domains-for-family (family)
  (case family
    ((:conversation) '(:conversation))
    ((:runtime :telemetry :diagnostic :console) '(:runtime :environment))
    ((:workflow :artifact :workspace :testing) '(:workspace :environment))
    ((:policy :intent) '(:policy :environment))
    ((:environment) '(:environment))
    (otherwise '())))

(defun provider-request-snapshot-dirty-domains-for-event (&key reason family)
  (normalize-provider-request-dirty-domains
   (append (provider-request-snapshot-dirty-domains-for-reason reason)
           (provider-request-snapshot-dirty-domains-for-family family))))

(defun provider-request-snapshot-domain-selected-p (domains domain)
  (member domain domains :test #'eq))

(defun provider-request-snapshot-dirty-p (session snapshot &key relevant-domains)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let ((dirty-at (environment-metadata-value environment
                                                  +provider-request-snapshot-dirty-at-key+))
            (dirty-domain-times (or (environment-metadata-value environment
                                                                +provider-request-snapshot-dirty-domain-times-key+)
                                    '()))
            (dirty-domains (or (environment-metadata-value environment
                                                            +provider-request-snapshot-dirty-domains-key+)
                               '())))
        (and dirty-at
             (or (null relevant-domains)
                 (null dirty-domains)
                 (some (lambda (domain)
                         (and (member domain dirty-domains :test #'eq)
                              (let ((domain-dirty-at (or (getf dirty-domain-times domain)
                                                         dirty-at)))
                                (or (null snapshot)
                                    (null (provider-request-snapshot-domain-generated-at-value snapshot
                                                                                              domain))
                                    (>= domain-dirty-at
                                        (provider-request-snapshot-domain-generated-at-value snapshot
                                                                                              domain))))))
                       relevant-domains))
             (or (null snapshot)
                 (null relevant-domains)
                 (null (provider-request-snapshot-generated-at snapshot))
                 (>= dirty-at (provider-request-snapshot-generated-at snapshot))))))))

(defun provider-request-snapshot-needs-refresh-p (session snapshot
                                                  &key relevant-domains
                                                    (now (get-universal-time))
                                                    (max-age-seconds +provider-request-snapshot-stale-seconds+))
  (or (if relevant-domains
          (some (lambda (domain)
                  (provider-request-snapshot-domain-stale-p snapshot
                                                           domain
                                                           :now now
                                                           :max-age-seconds max-age-seconds))
                relevant-domains)
          (provider-request-snapshot-stale-p snapshot
                                             :now now
                                             :max-age-seconds max-age-seconds))
      (provider-request-snapshot-dirty-p session snapshot
                                         :relevant-domains relevant-domains)))

(defun mark-provider-request-snapshot-dirty (session &key reason family)
  (let ((environment (session-bound-environment session)))
    (when environment
      (sb-thread:with-mutex (*provider-request-snapshot-cache-lock*)
        (set-environment-metadata-value environment
                                        +provider-request-snapshot-dirty-at-key+
                                        (get-universal-time))
        (when (or reason family)
          (let ((existing (copy-list
                           (or (environment-metadata-value environment
                                                           +provider-request-snapshot-dirty-reasons-key+)
                               '())))
                (dirty-domain-times (copy-list
                                     (or (environment-metadata-value environment
                                                                     +provider-request-snapshot-dirty-domain-times-key+)
                                         '())))
                (dirty-domains (copy-list
                                (or (environment-metadata-value environment
                                                                +provider-request-snapshot-dirty-domains-key+)
                                    '()))))
            (when reason
              (pushnew reason existing :test #'equal))
            (set-environment-metadata-value environment
                                            +provider-request-snapshot-dirty-reasons-key+
                                            existing)
            (dolist (domain (provider-request-snapshot-dirty-domains-for-event
                             :reason reason
                             :family family))
              (pushnew domain dirty-domains :test #'eq)
              (setf (getf dirty-domain-times domain) (get-universal-time)))
            (set-environment-metadata-value environment
                                            +provider-request-snapshot-dirty-domain-times-key+
                                            dirty-domain-times)
            (set-environment-metadata-value environment
                                            +provider-request-snapshot-dirty-domains-key+
                                            dirty-domains)))))))

(defun lightweight-conversation-request-p (prompt &key (operator-mode :repl-bridge)
                                                  attachments surface-actions)
  (declare (ignore surface-actions))
  (let* ((normalized (string-trim '(#\Space #\Tab #\Newline #\Return) (or prompt "")))
         (decision (classify-interaction-decision normalized :operator-mode operator-mode)))
    (and (eq operator-mode :conversation)
         (> (length normalized) 0)
         (<= (length normalized) 160)
         (not (find #\Newline normalized))
         (null attachments)
         (eq (interaction-decision-mode decision) :conversation))))

(defun cached-conversation-context-request-p (prompt &key (operator-mode :repl-bridge)
                                                        attachments surface-actions)
  (let* ((normalized (string-trim '(#\Space #\Tab #\Newline #\Return) (or prompt "")))
         (decision (classify-interaction-decision normalized :operator-mode operator-mode)))
    (and (eq operator-mode :conversation)
         (> (length normalized) 0)
         (null attachments)
         (member (interaction-decision-mode decision) '(:conversation :inspect) :test #'eq)
         (not (lightweight-conversation-request-p normalized
                                                  :operator-mode operator-mode
                                                  :attachments attachments
                                                  :surface-actions surface-actions)))))

(defun context-search-text (value)
  (labels ((collect-text (item)
             (cond
               ((null item) "")
               ((stringp item) item)
               ((symbolp item) (string-downcase (string item)))
               ((numberp item) (princ-to-string item))
               ((listp item)
                (with-output-to-string (stream)
                  (dolist (entry item)
                    (let ((text (collect-text entry)))
                      (when (> (length text) 0)
                        (write-string text stream)
                        (write-char #\Space stream))))))
               (t
                (princ-to-string item)))))
    (string-downcase (collect-text value))))

(defun context-summary-text (value &key (limit 240))
  (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return)
                           (context-search-text value))))
    (if (> (length text) limit)
        (concatenate 'string (subseq text 0 limit) "...")
        text)))

(defun cached-context-entry-with-index (entry)
  (let* ((label (or (getf entry :label) ""))
         (domain (or (getf entry :domain) ""))
         (text (or (getf entry :text) ""))
         (summary (or (getf entry :summary) ""))
         (label-tokens (remove-duplicates (prompt-match-tokens label) :test #'string=))
         (domain-tokens (remove-duplicates (prompt-match-tokens domain) :test #'string=))
         (summary-tokens (remove-duplicates (prompt-match-tokens summary) :test #'string=))
         (text-tokens (remove-duplicates (prompt-match-tokens text) :test #'string=)))
    (append entry
            (list :label-tokens label-tokens
                  :domain-tokens domain-tokens
                  :summary-tokens summary-tokens
                  :text-tokens text-tokens))))

(defun cached-context-entry-score (prompt-tokens entry)
  (let ((label-tokens (getf entry :label-tokens))
        (domain-tokens (getf entry :domain-tokens))
        (summary-tokens (getf entry :summary-tokens))
        (text-tokens (getf entry :text-tokens)))
    (loop for token in prompt-tokens
          sum (+ (if (member token label-tokens :test #'string=) 4 0)
                 (if (member token domain-tokens :test #'string=) 3 0)
                 (if (member token summary-tokens :test #'string=) 2 0)
                 (if (member token text-tokens :test #'string=) 1 0)))))

(defun cached-context-entry-token-weight (entry token)
  (+ (if (member token (getf entry :label-tokens) :test #'string=) 4 0)
     (if (member token (getf entry :domain-tokens) :test #'string=) 3 0)
     (if (member token (getf entry :summary-tokens) :test #'string=) 2 0)
     (if (member token (getf entry :text-tokens) :test #'string=) 1 0)))

(defun build-cached-context-index (entries)
  (let ((index (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (let ((tokens (remove-duplicates
                     (append (or (getf entry :label-tokens) '())
                             (or (getf entry :domain-tokens) '())
                             (or (getf entry :summary-tokens) '())
                             (or (getf entry :text-tokens) '()))
                     :test #'string=)))
        (dolist (token tokens)
          (push (cons entry (cached-context-entry-token-weight entry token))
                (gethash token index)))))
    index))

(defun copy-cached-context-index (index)
  (let ((copy (make-hash-table :test #'equal)))
    (when index
      (maphash (lambda (token postings)
                 (setf (gethash token copy) (copy-list postings)))
               index))
    copy))

(defun merge-cached-context-index (existing-index replacement-entries domains)
  (let* ((replacement-domains
           (mapcar #'provider-request-domain->cached-context-domain domains))
         (merged-index (copy-cached-context-index existing-index))
         (replacement-index (build-cached-context-index replacement-entries)))
    (maphash (lambda (token postings)
               (let ((filtered
                       (remove-if (lambda (posting)
                                    (member (getf (car posting) :domain)
                                            replacement-domains
                                            :test #'string=))
                                  postings)))
                 (if filtered
                     (setf (gethash token merged-index) filtered)
                     (remhash token merged-index))))
             (copy-cached-context-index merged-index))
    (maphash (lambda (token postings)
               (let* ((filtered
                        (or (gethash token merged-index) '()))
                      (combined (append filtered postings)))
                 (if combined
                     (setf (gethash token merged-index) combined)
                     (remhash token merged-index))))
             replacement-index)
    merged-index))

(defun cached-context-ranked-items (prompt-tokens entries index)
  (if (and index prompt-tokens)
      (let ((scores (make-hash-table :test #'eq)))
        (dolist (token prompt-tokens)
          (dolist (posting (gethash token index))
            (incf (gethash (car posting) scores 0) (cdr posting))))
        (let ((ranked '()))
          (maphash (lambda (entry score)
                     (push (list :entry entry :score score) ranked))
                   scores)
          (if ranked
              (sort ranked #'> :key (lambda (item) (getf item :score)))
              (sort (loop for entry in entries
                          for score = (cached-context-entry-score prompt-tokens entry)
                          collect (list :entry entry :score score))
                    #'>
                    :key (lambda (item) (getf item :score))))))
      (sort (loop for entry in entries
                  for score = (cached-context-entry-score prompt-tokens entry)
                  collect (list :entry entry :score score))
            #'>
            :key (lambda (item) (getf item :score)))))

(defun cached-context-ranking-entry (entry score)
  (list :label (getf entry :label)
        :kind :cached-context
        :domain (getf entry :domain)
        :score score
        :summary (getf entry :summary)
        :ref (getf entry :ref)))

(defun provider-request-domain->cached-context-domain (domain)
  (string-downcase (string domain)))

(defun cached-conversation-context-entries-for-domain (snapshot domain)
  (ecase domain
    (:conversation
     (remove nil
             (list
              (let ((thread-context (and snapshot
                                         (provider-request-snapshot-thread-context snapshot))))
                (when thread-context
                  (list :domain "conversation"
                        :label "Active Thread"
                        :summary (or (getf thread-context :summary)
                                     (getf thread-context :title))
                        :ref (list :type :thread
                                   :id (getf thread-context :id))
                        :text (context-search-text thread-context))))
              (let ((turn-context (and snapshot
                                       (provider-request-snapshot-turn-context snapshot))))
                (when turn-context
                  (list :domain "conversation"
                        :label "Current Turn"
                        :summary (or (getf (getf turn-context :assistant-message) :content)
                                     (getf (getf turn-context :user-message) :content)
                                     (context-summary-text (getf turn-context :detail-summary)))
                        :ref (list :type :turn
                                   :id (getf turn-context :id))
                        :text (context-search-text turn-context))))
              (let ((session-summary (and snapshot
                                          (provider-request-snapshot-session-summary snapshot))))
                (when session-summary
                  (list :domain "conversation"
                        :label "Recent Transcript"
                        :summary (format nil "~D recent transcript entries"
                                         (length (or (getf session-summary :recent-transcript) '())))
                        :ref (list :type :transcript
                                   :count (getf session-summary :transcript-count))
                        :text (context-search-text (getf session-summary :recent-transcript))))))))
    (:runtime
     (let ((runtime-summary (and snapshot
                                 (provider-request-snapshot-runtime-summary snapshot))))
       (remove nil
               (list
                (when runtime-summary
                  (list :domain "runtime"
                        :label "Runtime Summary"
                        :summary (format nil "Package ~A, ~D open incidents"
                                         (or (getf runtime-summary :package) "CL-USER")
                                         (or (getf runtime-summary :open-incident-count) 0))
                        :ref (list :type :runtime
                                   :environment-id (getf runtime-summary :environment-id))
                        :text (context-search-text runtime-summary)))))))
    (:workspace
     (let ((workspace-summary (and snapshot
                                   (provider-request-snapshot-workspace-summary snapshot))))
       (remove nil
               (list
                (when workspace-summary
                  (list :domain "workspace"
                        :label "Workspace Summary"
                        :summary (format nil "~D work items, ~D artifacts"
                                         (or (getf workspace-summary :work-item-count) 0)
                                         (or (getf workspace-summary :artifact-count) 0))
                        :ref (list :type :workspace
                                   :cwd (getf workspace-summary :cwd))
                        :text (context-search-text workspace-summary)))))))
    (:policy
     (let ((policy-summary (and snapshot
                                (provider-request-snapshot-policy-summary snapshot))))
       (remove nil
               (list
                (when policy-summary
                  (list :domain "policy"
                        :label "Policy Summary"
                        :summary (format nil "~D open incidents"
                                         (or (getf policy-summary :open-incident-count) 0))
                        :ref (list :type :policy
                                   :environment-id (getf policy-summary :environment-id))
                        :text (context-search-text policy-summary)))))))
    (:environment
     (let ((environment-context (and snapshot
                                     (provider-request-snapshot-environment-context snapshot))))
       (remove nil
               (list
                (when environment-context
                  (list :domain "environment"
                        :label "Environment Refs"
                        :summary (format nil "~D threads, ~D work items, ~D incidents"
                                         (or (getf environment-context :thread-count) 0)
                                         (or (getf environment-context :work-item-count) 0)
                                         (or (getf environment-context :open-incident-count) 0))
                        :ref (list :type :environment
                                   :environment-id (getf environment-context :environment-id))
                        :text (context-search-text environment-context)))))))))

(defun cached-conversation-context-entries-for-domains (snapshot domains)
  (mapcar #'cached-context-entry-with-index
          (loop for domain in domains
                append (cached-conversation-context-entries-for-domain snapshot domain))))

(defun merge-cached-conversation-context-entries (existing-entries replacement-entries domains)
  (let ((replacement-domains
          (mapcar #'provider-request-domain->cached-context-domain domains)))
    (append
     (remove-if (lambda (entry)
                  (member (getf entry :domain) replacement-domains :test #'string=))
                (or existing-entries '()))
     replacement-entries)))

(defun cached-conversation-context-entries (snapshot)
  (mapcar #'cached-context-entry-with-index
          (loop for domain in +provider-request-snapshot-known-domains+
                append (cached-conversation-context-entries-for-domain snapshot domain))))

(defun build-cached-conversation-retrieval-dossier (prompt snapshot &key (operator-mode :conversation))
  (let* ((prompt-tokens (remove-duplicates (prompt-match-tokens prompt) :test #'string=))
         (intent (classify-retrieval-intent prompt :operator-mode operator-mode))
         (entries (or (and snapshot
                           (provider-request-snapshot-cached-context-entries snapshot))
                      (cached-conversation-context-entries snapshot)))
         (index (and snapshot
                     (provider-request-snapshot-cached-context-index snapshot)))
         (ranked (cached-context-ranked-items prompt-tokens entries index))
         (hits (subseq ranked 0 (min 6 (length ranked))))
         (domains (remove-duplicates
                   (append (or (retrieval-intent-domains intent) '())
                           (mapcar (lambda (item)
                                     (intern (string-upcase (getf (getf item :entry) :domain))
                                             :keyword))
                                   hits))
                   :test #'eq)))
    (list :phase :cached-conversation
          :intent (list :category (or (retrieval-intent-category intent) :conversation)
                        :primary-intent (or (retrieval-intent-primary-intent intent)
                                            (retrieval-intent-category intent)
                                            :conversation)
                        :secondary-intents (copy-list (or (retrieval-intent-secondary-intents intent) '()))
                        :task-archetype (retrieval-intent-task-archetype intent)
                        :requested-deliverable (retrieval-intent-requested-deliverable intent)
                        :phase-intent (or (retrieval-intent-phase-intent intent) :inspect)
                        :domains domains
                        :historical-p (retrieval-intent-historical-p intent)
                        :intent-context-p (retrieval-intent-intent-context-p intent)
                        :runtime-inspection-p (retrieval-intent-runtime-inspection-p intent)
                        :governance-context-p (retrieval-intent-governance-context-p intent)
                        :observability-context-p (retrieval-intent-observability-context-p intent)
                        :testing-context-p (retrieval-intent-testing-context-p intent)
                        :project-context-p (retrieval-intent-project-context-p intent)
                        :source-context-p (retrieval-intent-source-context-p intent)
                        :mutation-likely-p nil
                        :explanation "Cached conversational context relevance over a warm snapshot.")
          :plan (list :domains domains
                      :per-domain-limits '((:conversation . 3)
                                           (:runtime . 2)
                                           (:workspace . 2)
                                           (:policy . 1)
                                           (:environment . 2))
                      :expansion-posture :cached-search
                      :expansion-pass 0
                      :runtime-detail-p nil
                      :governance-detail-p nil
                      :project-detail-p nil
                      :source-detail-p nil
                      :semantic-ranking-p nil
                      :explanation "Use warm snapshot search results instead of building a full retrieval dossier.")
          :ranking (mapcar (lambda (item)
                             (cached-context-ranking-entry (getf item :entry)
                                                           (getf item :score)))
                           hits)
          :conversation-context (list :thread (and snapshot
                                                   (provider-request-snapshot-thread-context snapshot))
                                      :turn (and snapshot
                                                 (provider-request-snapshot-turn-context snapshot))
                                      :recent-transcript (and snapshot
                                                              (getf (provider-request-snapshot-session-summary snapshot)
                                                                    :recent-transcript)))
          :runtime-context (and snapshot
                                (provider-request-snapshot-runtime-summary snapshot))
          :workflow-context (and snapshot
                                 (provider-request-snapshot-workspace-summary snapshot))
          :artifact-context (and snapshot
                                 (getf (provider-request-snapshot-workspace-summary snapshot)
                                       :artifact-summary))
          :environment-context (and snapshot
                                    (provider-request-snapshot-environment-context snapshot))
          :observed-consequences '()
          :gaps '())))

(defun build-prompt-independent-provider-request-snapshot (session
                                                           &key thread turn
                                                             surface-context surface-actions)
  (ensure-default-thread session)
  (let* ((snapshot (build-provider-environment-snapshot session))
         (thread-context (provider-thread-context session thread snapshot))
         (turn-context (provider-turn-context session turn snapshot))
         (session-summary (provider-session-summary session snapshot))
         (environment-context (provider-environment-context session snapshot))
         (generated-at (get-universal-time))
         (base-snapshot (make-provider-request-snapshot
                         :generated-at generated-at
                         :domain-generated-at (provider-request-snapshot-domain-generation-map generated-at)
                         :session-summary session-summary
                         :thread-context thread-context
                         :turn-context turn-context
                         :environment-context environment-context
                         :surface-context surface-context
                         :surface-actions surface-actions
                         :runtime-summary (provider-runtime-summary session snapshot)
                         :workspace-summary (provider-workspace-summary session snapshot)
                         :policy-summary (provider-policy-summary session snapshot)
                         :retrieval-dossier nil
                         :cognition-bundle nil
                         :reasoning-brief nil
                         :planning-brief nil
                         :planning-context-packet nil
                         :outcome-brief nil
                         :cached-context-entries nil
                         :cached-context-index nil))
         (cached-context-entries (cached-conversation-context-entries base-snapshot))
         (cached-context-index (build-cached-context-index cached-context-entries)))
    (make-provider-request-snapshot
     :generated-at (provider-request-snapshot-generated-at base-snapshot)
     :domain-generated-at (copy-tree (provider-request-snapshot-domain-generated-at base-snapshot))
     :session-summary session-summary
     :thread-context thread-context
     :turn-context turn-context
     :environment-context environment-context
     :surface-context surface-context
     :surface-actions surface-actions
     :runtime-summary (provider-request-snapshot-runtime-summary base-snapshot)
     :workspace-summary (provider-request-snapshot-workspace-summary base-snapshot)
     :policy-summary (provider-request-snapshot-policy-summary base-snapshot)
     :retrieval-dossier nil
     :cognition-bundle nil
     :reasoning-brief nil
     :planning-brief nil
     :planning-context-packet nil
     :outcome-brief nil
     :cached-context-entries cached-context-entries
     :cached-context-index cached-context-index)))

(defun merge-provider-request-snapshot-domains (session existing-snapshot
                                                &key thread turn
                                                  surface-context surface-actions
                                                  domains)
  (let* ((refresh-domains (provider-request-snapshot-refresh-domains domains))
         (environment-snapshot (build-provider-environment-snapshot session))
         (generated-at (get-universal-time))
         (domain-generated-at (copy-tree
                               (or (provider-request-snapshot-domain-generated-at existing-snapshot)
                                   (provider-request-snapshot-domain-generation-map generated-at))))
         (thread-context (if (provider-request-snapshot-domain-selected-p refresh-domains :conversation)
                             (provider-thread-context session thread environment-snapshot)
                             (or thread
                                 (provider-request-snapshot-thread-context existing-snapshot))))
         (turn-context (if (provider-request-snapshot-domain-selected-p refresh-domains :conversation)
                           (provider-turn-context session turn environment-snapshot)
                           (or turn
                               (provider-request-snapshot-turn-context existing-snapshot))))
         (merged-snapshot
           (make-provider-request-snapshot
            :generated-at generated-at
            :domain-generated-at domain-generated-at
            :session-summary (provider-session-summary session environment-snapshot)
            :thread-context thread-context
            :turn-context turn-context
            :environment-context (if (provider-request-snapshot-domain-selected-p refresh-domains :environment)
                                     (provider-environment-context session environment-snapshot)
                                     (provider-request-snapshot-environment-context existing-snapshot))
            :surface-context (or surface-context
                                 (provider-request-snapshot-surface-context existing-snapshot))
            :surface-actions (or surface-actions
                                 (provider-request-snapshot-surface-actions existing-snapshot))
            :runtime-summary (if (provider-request-snapshot-domain-selected-p refresh-domains :runtime)
                                 (provider-runtime-summary session environment-snapshot)
                                 (provider-request-snapshot-runtime-summary existing-snapshot))
            :workspace-summary (if (provider-request-snapshot-domain-selected-p refresh-domains :workspace)
                                   (provider-workspace-summary session environment-snapshot)
                                   (provider-request-snapshot-workspace-summary existing-snapshot))
            :policy-summary (if (provider-request-snapshot-domain-selected-p refresh-domains :policy)
                                (provider-policy-summary session environment-snapshot)
                                (provider-request-snapshot-policy-summary existing-snapshot))
            :retrieval-dossier nil
            :cognition-bundle nil
            :reasoning-brief nil
            :planning-brief nil
            :planning-context-packet nil
            :outcome-brief nil
            :cached-context-entries nil
            :cached-context-index nil)))
    (dolist (domain refresh-domains)
      (setf (getf domain-generated-at domain) generated-at))
    (let ((merged-entries
            (merge-cached-conversation-context-entries
             (provider-request-snapshot-cached-context-entries existing-snapshot)
             (cached-conversation-context-entries-for-domains merged-snapshot refresh-domains)
             refresh-domains))
          (replacement-entries
            (cached-conversation-context-entries-for-domains merged-snapshot refresh-domains)))
      (setf (provider-request-snapshot-domain-generated-at merged-snapshot) domain-generated-at
            (provider-request-snapshot-cached-context-entries merged-snapshot) merged-entries
            (provider-request-snapshot-cached-context-index merged-snapshot)
            (merge-cached-context-index
             (provider-request-snapshot-cached-context-index existing-snapshot)
             replacement-entries
             refresh-domains)))
    merged-snapshot))

(defun provider-request-snapshot-with-overrides (snapshot
                                                 &key thread-context turn-context
                                                   surface-context surface-actions
                                                   retrieval-dossier cognition-bundle
                                                   reasoning-brief planning-brief
                                                   planning-context-packet
                                                   outcome-brief)
  (make-provider-request-snapshot
   :generated-at (provider-request-snapshot-generated-at snapshot)
   :domain-generated-at (copy-tree (provider-request-snapshot-domain-generated-at snapshot))
   :session-summary (provider-request-snapshot-session-summary snapshot)
   :thread-context (or thread-context
                       (provider-request-snapshot-thread-context snapshot))
   :turn-context (or turn-context
                     (provider-request-snapshot-turn-context snapshot))
   :environment-context (provider-request-snapshot-environment-context snapshot)
   :surface-context (or surface-context
                        (provider-request-snapshot-surface-context snapshot))
   :surface-actions (or surface-actions
                        (provider-request-snapshot-surface-actions snapshot))
   :runtime-summary (provider-request-snapshot-runtime-summary snapshot)
   :workspace-summary (provider-request-snapshot-workspace-summary snapshot)
   :policy-summary (provider-request-snapshot-policy-summary snapshot)
   :retrieval-dossier (or retrieval-dossier
                          (provider-request-snapshot-retrieval-dossier snapshot))
   :cognition-bundle (or cognition-bundle
                         (provider-request-snapshot-cognition-bundle snapshot))
   :reasoning-brief (or reasoning-brief
                        (provider-request-snapshot-reasoning-brief snapshot))
   :planning-brief (or planning-brief
                       (provider-request-snapshot-planning-brief snapshot))
   :planning-context-packet (or planning-context-packet
                                (provider-request-snapshot-planning-context-packet snapshot))
   :outcome-brief (or outcome-brief
                      (provider-request-snapshot-outcome-brief snapshot))
   :cached-context-entries (provider-request-snapshot-cached-context-entries snapshot)
   :cached-context-index (provider-request-snapshot-cached-context-index snapshot)))

(defun cached-provider-request-snapshot (session)
  (let ((environment (session-bound-environment session)))
    (when environment
      (sb-thread:with-mutex (*provider-request-snapshot-cache-lock*)
        (clone-provider-request-snapshot
         (environment-metadata-value environment
                                     +provider-request-snapshot-cache-key+))))))

(defun refresh-provider-request-snapshot-cache (session
                                                &key thread turn
                                                  surface-context surface-actions
                                                  domains)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let* ((existing-snapshot (environment-metadata-value environment
                                                            +provider-request-snapshot-cache-key+))
             (snapshot (if (and existing-snapshot domains)
                           (merge-provider-request-snapshot-domains
                            session
                            existing-snapshot
                            :thread thread
                            :turn turn
                            :surface-context surface-context
                            :surface-actions surface-actions
                            :domains domains)
                           (build-prompt-independent-provider-request-snapshot
                            session
                            :thread thread
                            :turn turn
                            :surface-context surface-context
                            :surface-actions surface-actions))))
        (sb-thread:with-mutex (*provider-request-snapshot-cache-lock*)
          (set-environment-metadata-value environment
                                          +provider-request-snapshot-cache-key+
                                          snapshot)
          (set-environment-metadata-value environment
                                          +provider-request-snapshot-dirty-at-key+
                                          nil)
          (set-environment-metadata-value environment
                                          +provider-request-snapshot-dirty-domain-times-key+
                                          nil)
          (set-environment-metadata-value environment
                                          +provider-request-snapshot-dirty-reasons-key+
                                          nil)
          (set-environment-metadata-value environment
                                          +provider-request-snapshot-dirty-domains-key+
                                          nil))
        snapshot))))

(defun provider-request-relevant-dirty-domains (prompt operator-mode attachments surface-actions)
  (when (cached-conversation-context-request-p prompt
                                               :operator-mode operator-mode
                                               :attachments attachments
                                               :surface-actions surface-actions)
    (or (normalize-provider-request-dirty-domains
         (retrieval-intent-domains (classify-retrieval-intent prompt
                                                              :operator-mode operator-mode)))
        '(:conversation))))

(defun schedule-provider-request-snapshot-refresh (session
                                                   &key thread turn
                                                     surface-context surface-actions
                                                     domains)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let ((start-refresh-p nil))
        (sb-thread:with-mutex (*provider-request-snapshot-cache-lock*)
          (unless (environment-metadata-value environment
                                              +provider-request-snapshot-refresh-pending-key+)
            (set-environment-metadata-value environment
                                            +provider-request-snapshot-refresh-pending-key+
                                            t)
            (setf start-refresh-p t)))
        (when start-refresh-p
          (sb-thread:make-thread
           (lambda ()
             (unwind-protect
                  (refresh-provider-request-snapshot-cache session
                                                           :thread thread
                                                           :turn turn
                                                           :surface-context surface-context
                                                           :surface-actions surface-actions
                                                           :domains domains)
               (sb-thread:with-mutex (*provider-request-snapshot-cache-lock*)
                 (set-environment-metadata-value environment
                                                 +provider-request-snapshot-refresh-pending-key+
                                                 nil))))
           :name "sbcl-agent-provider-request-snapshot-refresh"))))))

(defun notify-provider-request-snapshot-environment-change (environment
                                                            &key reason family
                                                              domains)
  (let* ((active-environment (ensure-environment environment))
         (sessionish (environment-compatibility-session active-environment))
         (session (and (compatibility-session-materialized-p sessionish)
                       sessionish))
         (resolved-domains (provider-request-snapshot-refresh-domains
                            (or domains
                                (provider-request-snapshot-dirty-domains-for-event
                                 :reason reason
                                 :family family)))))
    (when session
      (mark-provider-request-snapshot-dirty session :reason reason :family family)
      (schedule-provider-request-snapshot-refresh session :domains resolved-domains))
    resolved-domains))

(defun provider-bound-environment (session)
  (let ((environment (and (boundp '*current-environment*)
                          *current-environment*)))
    (when (and environment
               (eq (environment-compatibility-session environment) session))
      environment)))

(defun build-provider-environment-snapshot (session)
  (let ((environment (provider-bound-environment session)))
    (when environment
      (make-provider-environment-snapshot
       :environment environment
       :environment-summary (environment-summary environment)
       :conversation-state (environment-conversation-state environment)
       :workflow-state (environment-workflow-state environment)
       :incident-summary (getf (environment-summaries environment) :incident-summary)))))

(defun ensure-provider-environment-snapshot (session snapshot)
  (or snapshot
      (build-provider-environment-snapshot session)))

(defun provider-snapshot-environment-summary-value (snapshot key)
  (and snapshot
       (getf (provider-environment-snapshot-environment-summary snapshot) key)))

(defun provider-snapshot-runtime-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :runtime-state)
             key)))

(defun provider-snapshot-conversation-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :conversation-state)
             key)))

(defun provider-snapshot-workflow-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :workflow-state)
             key)))

(defun provider-snapshot-agent-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :agent-state)
             key)))

(defun provider-snapshot-policy-state-value (snapshot key)
  (let ((environment (and snapshot
                          (provider-environment-snapshot-environment snapshot))))
    (and environment
         (getf (environment-policy-state environment) key))))

(defun provider-snapshot-open-incident-count (snapshot)
  (and snapshot
       (getf (provider-snapshot-environment-summary-value snapshot :incident-summary)
             :open-count)))

(defun provider-snapshot-operator-status-value (snapshot key)
  (and snapshot
       (getf (provider-snapshot-environment-summary-value snapshot :operator-status)
             key)))

(defun provider-session-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :id (provider-snapshot-environment-summary-value snapshot :session-id)
              :cwd (provider-snapshot-environment-summary-value snapshot :storage-root)
              :package (provider-snapshot-runtime-summary-value snapshot :package)
              :current-thread-id (provider-snapshot-environment-summary-value snapshot :active-thread-id)
              :thread-count (provider-snapshot-environment-summary-value snapshot :thread-count)
              :message-count (provider-snapshot-conversation-summary-value snapshot :message-count)
              :turn-count (provider-snapshot-conversation-summary-value snapshot :turn-count)
              :operation-count (provider-snapshot-conversation-summary-value snapshot :operation-count)
              :incident-count (provider-snapshot-environment-summary-value snapshot :incident-count)
              :open-incident-count (provider-snapshot-open-incident-count snapshot)
              :plan (provider-snapshot-environment-summary-value snapshot :plan)
              :approved-policies (provider-snapshot-policy-state-value snapshot :approved-policies)
              :pending-action-count (provider-snapshot-agent-summary-value snapshot :pending-action-count)
              :active-worker-count (provider-snapshot-agent-summary-value snapshot :active-worker-count)
              :environment-id (and environment (environment-id environment))
              :active-runtime-id (and environment (environment-active-runtime-id environment))
              :artifact-summary (provider-snapshot-environment-summary-value snapshot :artifact-summary)
              :transcript-count (length (agent-session-transcript session))
              :recent-transcript (mapcar #'provider-transcript-entry
                                         (recent-session-transcript session)))
        (list :id (agent-session-id session)
              :cwd (agent-session-cwd session)
              :package (agent-session-package session)
              :current-thread-id (agent-session-current-thread-id session)
              :thread-count (length (agent-session-threads session))
              :message-count (length (agent-session-messages session))
              :turn-count (length (agent-session-turns session))
              :operation-count (length (agent-session-operations session))
              :incident-count (length (agent-session-incidents session))
              :open-incident-count (getf (session-incident-summary session) :open-count)
              :plan (session-plan-display-value session)
              :approved-policies (session-approved-policies session)
              :pending-action-count (length (agent-session-pending-actions session))
              :active-worker-count (active-worker-count session)
              :environment-id nil
              :active-runtime-id nil
              :artifact-summary (session-artifact-summary session)
              :transcript-count (length (agent-session-transcript session))
              :recent-transcript (mapcar #'provider-transcript-entry
                                         (recent-session-transcript session))))))

(defun provider-runtime-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :cwd (provider-snapshot-environment-summary-value snapshot :storage-root)
              :package (provider-snapshot-runtime-summary-value snapshot :package)
              :approved-policies (provider-snapshot-policy-state-value snapshot :approved-policies)
              :pending-action-count (provider-snapshot-agent-summary-value snapshot :pending-action-count)
              :active-worker-count (provider-snapshot-agent-summary-value snapshot :active-worker-count)
              :incident-count (provider-snapshot-environment-summary-value snapshot :incident-count)
              :open-incident-count (provider-snapshot-open-incident-count snapshot)
              :environment-id (and environment (environment-id environment))
              :active-runtime-id (and environment (environment-active-runtime-id environment)))
        (list :cwd (agent-session-cwd session)
              :package (agent-session-package session)
              :approved-policies (session-approved-policies session)
              :pending-action-count (length (agent-session-pending-actions session))
              :active-worker-count (active-worker-count session)
              :incident-count (length (agent-session-incidents session))
              :open-incident-count (getf (session-incident-summary session) :open-count)
              :environment-id nil
              :active-runtime-id nil))))

(defun provider-workspace-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :cwd (provider-snapshot-environment-summary-value snapshot :storage-root)
              :artifact-count (provider-snapshot-environment-summary-value snapshot :artifact-count)
              :artifact-summary (provider-snapshot-environment-summary-value snapshot :artifact-summary)
              :work-item-count (provider-snapshot-environment-summary-value snapshot :work-item-count)
              :workflow-record-count (provider-snapshot-workflow-summary-value snapshot :workflow-record-count)
              :incident-count (provider-snapshot-environment-summary-value snapshot :incident-count)
              :quarantined-work-item-count (provider-snapshot-operator-status-value snapshot :quarantined-count)
              :environment-id (and environment (environment-id environment)))
        (list :cwd (agent-session-cwd session)
              :artifact-count (length (agent-session-artifacts session))
              :artifact-summary (session-artifact-summary session)
              :work-item-count (length (agent-session-work-items session))
              :workflow-record-count (length (agent-session-workflow-records session))
              :incident-count (length (agent-session-incidents session))
              :quarantined-work-item-count (getf (session-operator-status session) :quarantined-count)
              :environment-id nil))))

(defun provider-policy-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :approved-policies (provider-snapshot-policy-state-value snapshot :approved-policies)
              :capability-grants (provider-snapshot-policy-state-value snapshot :capability-grants)
              :open-incident-count (provider-snapshot-open-incident-count snapshot)
              :environment-id (and environment (environment-id environment)))
        (list :approved-policies (session-approved-policies session)
              :capability-grants (session-capability-grants-summary session)
              :open-incident-count (getf (session-incident-summary session) :open-count)
              :environment-id nil))))

(defun provider-thread-context (session &optional thread snapshot)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (active-thread (or thread
                            (and snapshot
                                 (environment-active-thread-summary
                                  (provider-environment-snapshot-environment snapshot)))
                            (current-thread session))))
    (when active-thread
      (if (typep active-thread 'thread)
          (thread-record-summary active-thread)
          active-thread))))

(defun provider-turn-context (session &optional turn snapshot)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (active-turn (or turn
                          (and snapshot
                               (environment-active-turn-summary
                                (provider-environment-snapshot-environment snapshot)))
                          (most-recent-thread-turn session))))
    (when active-turn
      (if (typep active-turn 'turn)
          (turn-detail session (turn-id active-turn))
          active-turn))))

(defun limited-record-refs (records id-key &key (limit 5) extra-keys)
  (mapcar (lambda (record)
            (append (list :id (getf record id-key))
                    (loop for key in extra-keys
                          append (list key (getf record key)))))
          (subseq records 0 (min limit (length records)))))

(defun provider-work-item-refs (work-items &key (limit 5))
  (limited-record-refs (mapcar #'work-item-summary work-items)
                       :id
                       :limit limit
                       :extra-keys '(:status :goal :closure-decision)))

(defun provider-environment-context (session &optional snapshot)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot
                           (provider-environment-snapshot-environment snapshot))))
    (when environment
      (let* ((conversation-state (provider-environment-snapshot-conversation-state snapshot))
             (workflow-state (provider-environment-snapshot-workflow-state snapshot))
             (conversation-summary (and conversation-state
                                        (environment-conversation-state-summaries conversation-state)))
             (workflow-summary (and workflow-state
                                    (environment-workflow-state-summaries workflow-state)))
             (threads (and conversation-state
                           (environment-conversation-state-threads conversation-state)))
             (artifacts (and conversation-state
                             (environment-conversation-state-artifacts conversation-state)))
             (work-items (and workflow-state
                              (environment-workflow-state-work-items workflow-state)))
             (incidents (provider-environment-snapshot-incident-summary snapshot)))
        (list :environment-id (environment-id environment)
              :active-runtime-id (environment-active-runtime-id environment)
              :active-thread-id (environment-active-thread-id environment)
              :thread-count (getf conversation-summary :thread-count)
              :artifact-count (getf conversation-summary :artifact-count)
              :work-item-count (getf workflow-summary :work-item-count)
              :reconciliation-count (getf workflow-summary :reconciliation-count)
              :open-incident-count (getf incidents :open-count)
              :agent-constitution
              (provider-snapshot-environment-summary-value snapshot :agent-constitution)
              :capability-inventory
              (provider-snapshot-environment-summary-value snapshot :capability-inventory)
              :context-chat-project-selection
              (provider-snapshot-environment-summary-value snapshot :context-chat-project-selection)
              :thread-refs (limited-record-refs threads :id :extra-keys '(:title :status))
              :artifact-refs (limited-record-refs artifacts :id :extra-keys '(:kind :title :turn-id))
              :work-item-refs (provider-work-item-refs work-items)
              :recent-incident-refs (limited-record-refs (or (getf incidents :recent) '())
                                                         :id
                                                         :extra-keys '(:kind :status :turn-id)))))))

(defun build-provider-context-bundle (session &key thread turn prompt retrieval-dossier outcome-brief
                                        surface-context surface-actions
                                        (operator-mode :repl-bridge)
                                        attachments)
  (ensure-default-thread session)
  (let* ((snapshot (build-provider-environment-snapshot session))
         (thread-context (provider-thread-context session thread snapshot))
         (turn-context (provider-turn-context session turn snapshot))
         (session-summary (provider-session-summary session snapshot))
         (environment-context (provider-environment-context session snapshot))
         (runtime-summary (provider-runtime-summary session snapshot))
         (workspace-summary (provider-workspace-summary session snapshot))
         (policy-summary (provider-policy-summary session snapshot))
         (lightweight-conversation-p
           (lightweight-conversation-request-p prompt
                                               :operator-mode operator-mode
                                               :attachments attachments
                                               :surface-actions surface-actions))
         (cached-conversation-context-p
           (cached-conversation-context-request-p prompt
                                                 :operator-mode operator-mode
                                                 :attachments attachments
                                                 :surface-actions surface-actions))
         (base-request-snapshot
           (make-provider-request-snapshot
            :session-summary session-summary
            :thread-context thread-context
            :turn-context turn-context
            :environment-context environment-context
            :surface-context surface-context
            :surface-actions surface-actions
            :runtime-summary runtime-summary
            :workspace-summary workspace-summary
            :policy-summary policy-summary
            :retrieval-dossier nil
            :cognition-bundle nil
            :reasoning-brief nil
            :planning-brief nil
            :planning-context-packet nil
            :outcome-brief nil))
         (resolved-retrieval-dossier
           (or retrieval-dossier
               (and prompt
                    (cond
                      (lightweight-conversation-p
                       nil)
                      (cached-conversation-context-p
                       (build-cached-conversation-retrieval-dossier
                        prompt
                        base-request-snapshot
                        :operator-mode operator-mode))
                      (t
                       (service-response-data
                        (query-retrieval-dossier-service
                         session
                         prompt
                         :operator-mode operator-mode)))))))
         (resolved-cognition-bundle
           (and resolved-retrieval-dossier
                (not lightweight-conversation-p)
                (not cached-conversation-context-p)
                (build-cognition-bundle prompt
                                        session-summary
                                        environment-context
                                        resolved-retrieval-dossier
                                        :session session
                                        :outcome-brief outcome-brief
                                        :current-turn-id (and turn
                                                              (turn-id turn)))))
         (resolved-reasoning-brief
           (and resolved-cognition-bundle
                (cognition-bundle-reasoning-brief resolved-cognition-bundle)))
         (resolved-planning-brief
           (and resolved-cognition-bundle
                (cognition-bundle-planning-brief resolved-cognition-bundle)))
         (resolved-outcome-brief
           (or (and resolved-cognition-bundle
                    (cognition-bundle-outcome-brief resolved-cognition-bundle))
               outcome-brief))
         (planning-context-packet
           (and resolved-cognition-bundle
                (build-provider-planning-context-packet prompt
                                                        operator-mode
                                                        nil
                                                        session-summary
                                                        session
                                                        thread-context
                                                        turn-context
                                                        environment-context
                                                        surface-context
                                                        surface-actions
                                                        runtime-summary
                                                        workspace-summary
                                                        policy-summary
                                                        resolved-retrieval-dossier
                                                        resolved-cognition-bundle
                                                        resolved-reasoning-brief
                                                        resolved-planning-brief
                                                        resolved-outcome-brief))))
    (make-provider-context-bundle
     :snapshot snapshot
     :session-summary session-summary
     :thread-context thread-context
     :turn-context turn-context
     :environment-context environment-context
     :surface-context surface-context
     :surface-actions surface-actions
     :runtime-summary runtime-summary
     :workspace-summary workspace-summary
     :policy-summary policy-summary
     :retrieval-dossier resolved-retrieval-dossier
     :cognition-bundle resolved-cognition-bundle
     :reasoning-brief resolved-reasoning-brief
     :planning-brief resolved-planning-brief
     :planning-context-packet planning-context-packet
     :outcome-brief resolved-outcome-brief)))

(defun provider-context-bundle->request-snapshot (bundle)
  (when bundle
    (let* ((generated-at (get-universal-time))
           (base-snapshot
             (make-provider-request-snapshot
              :generated-at generated-at
              :session-summary (provider-context-bundle-session-summary bundle)
              :thread-context (provider-context-bundle-thread-context bundle)
              :turn-context (provider-context-bundle-turn-context bundle)
              :environment-context (provider-context-bundle-environment-context bundle)
              :surface-context (provider-context-bundle-surface-context bundle)
              :surface-actions (provider-context-bundle-surface-actions bundle)
              :runtime-summary (provider-context-bundle-runtime-summary bundle)
              :workspace-summary (provider-context-bundle-workspace-summary bundle)
              :policy-summary (provider-context-bundle-policy-summary bundle)
              :retrieval-dossier (provider-context-bundle-retrieval-dossier bundle)
              :cognition-bundle (provider-context-bundle-cognition-bundle bundle)
              :reasoning-brief (provider-context-bundle-reasoning-brief bundle)
              :planning-brief (provider-context-bundle-planning-brief bundle)
              :planning-context-packet (provider-context-bundle-planning-context-packet bundle)
              :outcome-brief (provider-context-bundle-outcome-brief bundle)
              :cached-context-entries nil
              :cached-context-index nil))
           (cached-context-entries (cached-conversation-context-entries base-snapshot)))
      (make-provider-request-snapshot
       :generated-at generated-at
       :session-summary (provider-context-bundle-session-summary bundle)
       :thread-context (provider-context-bundle-thread-context bundle)
       :turn-context (provider-context-bundle-turn-context bundle)
       :environment-context (provider-context-bundle-environment-context bundle)
       :surface-context (provider-context-bundle-surface-context bundle)
       :surface-actions (provider-context-bundle-surface-actions bundle)
       :runtime-summary (provider-context-bundle-runtime-summary bundle)
       :workspace-summary (provider-context-bundle-workspace-summary bundle)
       :policy-summary (provider-context-bundle-policy-summary bundle)
       :retrieval-dossier (provider-context-bundle-retrieval-dossier bundle)
       :cognition-bundle (provider-context-bundle-cognition-bundle bundle)
       :reasoning-brief (provider-context-bundle-reasoning-brief bundle)
       :planning-brief (provider-context-bundle-planning-brief bundle)
       :planning-context-packet (provider-context-bundle-planning-context-packet bundle)
       :outcome-brief (provider-context-bundle-outcome-brief bundle)
       :cached-context-entries cached-context-entries
       :cached-context-index (build-cached-context-index cached-context-entries)))))

(defun make-provider-request-from-snapshot (prompt request-snapshot
                                           &key (operator-mode :repl-bridge)
                                             stream-p
                                             attachments)
  (make-provider-request :prompt prompt
                         :attachments attachments
                         :session-summary (and request-snapshot
                                               (provider-request-snapshot-session-summary request-snapshot))
                         :thread-context (and request-snapshot
                                              (provider-request-snapshot-thread-context request-snapshot))
                         :turn-context (and request-snapshot
                                            (provider-request-snapshot-turn-context request-snapshot))
                         :environment-context (and request-snapshot
                                                 (provider-request-snapshot-environment-context request-snapshot))
                         :surface-context (and request-snapshot
                                               (provider-request-snapshot-surface-context request-snapshot))
                         :surface-actions (and request-snapshot
                                               (provider-request-snapshot-surface-actions request-snapshot))
                         :runtime-summary (and request-snapshot
                                               (provider-request-snapshot-runtime-summary request-snapshot))
                         :workspace-summary (and request-snapshot
                                                 (provider-request-snapshot-workspace-summary request-snapshot))
                         :policy-summary (and request-snapshot
                                              (provider-request-snapshot-policy-summary request-snapshot))
                         :retrieval-dossier (and request-snapshot
                                                (provider-request-snapshot-retrieval-dossier request-snapshot))
                         :cognition-bundle (and request-snapshot
                                                (provider-request-snapshot-cognition-bundle request-snapshot))
                         :reasoning-brief (and request-snapshot
                                              (provider-request-snapshot-reasoning-brief request-snapshot))
                         :planning-brief (and request-snapshot
                                             (provider-request-snapshot-planning-brief request-snapshot))
                         :planning-context-packet (and request-snapshot
                                                      (provider-request-snapshot-planning-context-packet request-snapshot))
                         :outcome-brief (and request-snapshot
                                            (provider-request-snapshot-outcome-brief request-snapshot))
                         :operator-mode operator-mode
                         :stream-p stream-p))

(defun make-provider-request-from-session (prompt session
                                          &key thread turn
                                            retrieval-dossier
                                            outcome-brief
                                            surface-context
                                            surface-actions
                                            (operator-mode :repl-bridge)
                                            stream-p
                                            attachments)
  (let* ((active-session (or session (ignore-errors (ensure-session))))
         (cached-snapshot (and active-session
                               (cached-provider-request-snapshot active-session)))
         (relevant-dirty-domains
           (and prompt
                (provider-request-relevant-dirty-domains prompt
                                                         operator-mode
                                                         attachments
                                                         surface-actions)))
         (cached-snapshot-needs-refresh-p
           (and active-session
                (provider-request-snapshot-needs-refresh-p active-session
                                                           cached-snapshot
                                                           :relevant-domains relevant-dirty-domains)))
         (base-snapshot (or cached-snapshot
                            (and active-session
                                 (or (refresh-provider-request-snapshot-cache active-session
                                                                             :thread thread
                                                                             :turn turn
                                                                             :surface-context surface-context
                                                                             :surface-actions surface-actions)
                                     (build-prompt-independent-provider-request-snapshot
                                      active-session
                                      :thread thread
                                      :turn turn
                                      :surface-context surface-context
                                      :surface-actions surface-actions)))))
         (resolved-thread-context (and active-session
                                       (provider-thread-context active-session thread)))
         (resolved-turn-context (and active-session
                                     (provider-turn-context active-session turn)))
         (resolved-snapshot (and base-snapshot
                                 (provider-request-snapshot-with-overrides
                                  base-snapshot
                                  :thread-context resolved-thread-context
                                  :turn-context resolved-turn-context
                                  :surface-context surface-context
                                  :surface-actions surface-actions)))
         (session-summary (and resolved-snapshot
                               (provider-request-snapshot-session-summary resolved-snapshot)))
         (environment-context (and resolved-snapshot
                                   (provider-request-snapshot-environment-context resolved-snapshot)))
         (lightweight-conversation-p
           (lightweight-conversation-request-p prompt
                                               :operator-mode operator-mode
                                               :attachments attachments
                                               :surface-actions surface-actions))
         (cached-conversation-context-p
           (cached-conversation-context-request-p prompt
                                                 :operator-mode operator-mode
                                                 :attachments attachments
                                                 :surface-actions surface-actions))
         (resolved-retrieval-dossier
           (or retrieval-dossier
               (and prompt
                    active-session
                    (cond
                      (lightweight-conversation-p
                       nil)
                      (cached-conversation-context-p
                       (build-cached-conversation-retrieval-dossier prompt
                                                                    resolved-snapshot
                                                                    :operator-mode operator-mode))
                      (t
                       (service-response-data
                        (query-retrieval-dossier-service active-session
                                                         prompt
                                                         :operator-mode operator-mode)))))))
         (cognition-bundle
           (and resolved-retrieval-dossier
                (not lightweight-conversation-p)
                (not cached-conversation-context-p)
                active-session
                (build-cognition-bundle prompt
                                        session-summary
                                        environment-context
                                        resolved-retrieval-dossier
                                        :session active-session
                                        :outcome-brief outcome-brief
                                        :current-turn-id (and turn
                                                              (turn-id turn)))))
         (resolved-reasoning-brief
           (and cognition-bundle
                (cognition-bundle-reasoning-brief cognition-bundle)))
         (planning-brief (and cognition-bundle
                              (cognition-bundle-planning-brief cognition-bundle)))
         (resolved-outcome-brief (or (and cognition-bundle
                                         (cognition-bundle-outcome-brief cognition-bundle))
                                     outcome-brief))
         (planning-context-packet
           (and cognition-bundle
                resolved-snapshot
                (build-provider-planning-context-packet prompt
                                                        operator-mode
                                                        stream-p
                                                        session-summary
                                                        active-session
                                                        resolved-thread-context
                                                        resolved-turn-context
                                                        environment-context
                                                        surface-context
                                                        surface-actions
                                                        (provider-request-snapshot-runtime-summary
                                                         resolved-snapshot)
                                                        (provider-request-snapshot-workspace-summary
                                                         resolved-snapshot)
                                                        (provider-request-snapshot-policy-summary
                                                         resolved-snapshot)
                                                        resolved-retrieval-dossier
                                                        cognition-bundle
                                                        resolved-reasoning-brief
                                                        planning-brief
                                                        resolved-outcome-brief)))
         (request-snapshot
           (and resolved-snapshot
                (provider-request-snapshot-with-overrides
                 resolved-snapshot
                 :retrieval-dossier resolved-retrieval-dossier
                 :cognition-bundle cognition-bundle
                 :reasoning-brief resolved-reasoning-brief
                 :planning-brief planning-brief
                 :planning-context-packet planning-context-packet
                 :outcome-brief resolved-outcome-brief))))
    (when (and active-session
               (or (null cached-snapshot)
                   cached-snapshot-needs-refresh-p))
      (schedule-provider-request-snapshot-refresh active-session
                                                  :thread thread
                                                  :turn turn
                                                  :surface-context surface-context
                                                  :surface-actions surface-actions
                                                  :domains relevant-dirty-domains))
    (make-provider-request-from-snapshot prompt
                                         request-snapshot
                                         :operator-mode operator-mode
                                         :stream-p stream-p
                                         :attachments attachments)))
