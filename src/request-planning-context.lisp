(in-package #:sbcl-agent)

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
                      :capability-inventory
                      :thread
                      :turn
                      :environment
                      :runtime-summary
                      :workspace-summary
                      :policy-summary
                      :surface-context
                      :surface-actions)
        :conflict-resolution
        '((:when (:project-context :environment) :prefer :project-context)
          (:when (:policy-summary :surface-actions) :prefer :policy-summary)
          (:when (:capability-inventory :runtime-summary :workspace-summary :optional-support)
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
