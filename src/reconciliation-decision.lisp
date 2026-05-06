(in-package #:sbcl-agent)

(defstruct reconciliation-decision
  intent-id
  alignment-status
  divergence-types
  decision
  proposed-actions
  trigger-events
  approval-posture
  confidence
  requires-approval-p
  rationale
  last-evaluated)

(defparameter +default-reconciliation-prompt+
  "Recommend how the system should reconcile current alignment divergence.")

(defun alignment-gap-types (packet)
  (remove nil
          (mapcar #'alignment-gap-type
                  (or (getf packet :alignment-gaps) '()))))

(defun constraint-entry-type (entry)
  (and (consp entry)
       (keywordp (first entry))
       (first entry)))

(defun constraints-require-governance-p (constraints)
  (or (find :policy constraints
            :key #'constraint-entry-type
            :test #'eq)
      (find :approval constraints
            :key #'constraint-entry-type
            :test #'eq)
      (find :safety-boundary constraints
            :key #'constraint-entry-type
            :test #'eq)))

(defun runtime-divergence-present-p (divergence-types gap-types)
  (or (find :behavioral-mismatch divergence-types :test #'eq)
      (find :incorrect-constraint-enforcement divergence-types :test #'eq)
      (find :source-divergence gap-types :test #'eq)
      (find :testing-failures-present gap-types :test #'eq)
      (find :project-readiness-blocked gap-types :test #'eq)))

(defun intent-divergence-present-p (divergence-types)
  (or (find :outdated-intent divergence-types :test #'eq)
      (find :incomplete-specification divergence-types :test #'eq)))

(defun capability-divergence-present-p (divergence-types gap-types)
  (or (find :missing-capability divergence-types :test #'eq)
      (find :missing-linked-mutation gap-types :test #'eq)))

(defun reconciliation-decision-kind (divergence-types gap-types)
  (let ((runtime-p (runtime-divergence-present-p divergence-types gap-types))
        (intent-p (intent-divergence-present-p divergence-types))
        (capability-p (capability-divergence-present-p divergence-types gap-types)))
    (cond
      ((and (not runtime-p) (not intent-p) (not capability-p))
       :maintain)
      ((and intent-p (not runtime-p) (not capability-p))
       :intent)
      ((and runtime-p (not intent-p) (not capability-p))
       :runtime)
      ((and capability-p (not intent-p) (not runtime-p))
       :runtime)
      (t
       :co-evolve))))

(defun reconciliation-proposed-actions (decision packet divergence-types gap-types)
  (let* ((intent (getf packet :intent))
         (validation-state (getf packet :validation-state))
         (actions '()))
    (when (member decision '(:intent :co-evolve) :test #'eq)
      (when (or (find :outdated-intent divergence-types :test #'eq)
                (find :incomplete-specification divergence-types :test #'eq))
        (push (list :kind :revise-intent
                    :target (or (getf intent :current-intent-id) :current-intent)
                    :reason "Intent constraints, behaviors, or status no longer fully match observed reality.")
              actions)))
    (when (member decision '(:runtime :co-evolve) :test #'eq)
      (when (runtime-divergence-present-p divergence-types gap-types)
        (push (list :kind :correct-runtime
                    :target :runtime
                    :reason "Observed runtime and governance evidence diverge from expected aligned behavior.")
              actions))
      (when (capability-divergence-present-p divergence-types gap-types)
        (push (list :kind :add-missing-capability
                    :target :runtime
                    :reason "Linked mutation or capability evidence is missing for the active intent.")
              actions)))
    (when (find :project-readiness-blocked gap-types :test #'eq)
      (push (list :kind :run-validation
                  :target :project-readiness
                  :reason (or (getf validation-state :readiness-summary)
                              "Project readiness remains blocked and must be revalidated."))
            actions))
    (when (null actions)
      (push (list :kind :monitor-alignment
                  :target :environment
                  :reason "No corrective mutation is currently required; continue observing for divergence.")
            actions))
    (nreverse actions)))

(defun reconciliation-trigger-events (packet)
  (let ((resolved-events (or (getf (getf packet :relevant-events) :resolved-linked-events) '())))
    (mapcar (lambda (entry)
              (list :event-id (getf entry :id)
                    :kind (getf entry :kind)
                    :family (getf entry :family)
                    :entity-id (getf entry :entity-id)
                    :thread-id (getf entry :thread-id)
                    :turn-id (getf entry :turn-id)
                    :timestamp (getf entry :timestamp)))
            resolved-events)))

(defun reconciliation-approval-posture (decision requires-approval-p packet)
  (let ((constraints (or (getf packet :constraints) '())))
    (cond
      (requires-approval-p
       (if (constraints-require-governance-p constraints)
           :governed-review
           :operator-review))
      ((eq decision :maintain)
       :observe)
      (t
       :directed-execution))))

(defun reconciliation-requires-approval-p (decision packet gap-types)
  (let ((constraints (or (getf packet :constraints) '()))
        (validation-state (or (getf packet :validation-state) '())))
    (or (member decision '(:runtime :co-evolve) :test #'eq)
        (constraints-require-governance-p constraints)
        (find :project-readiness-blocked gap-types :test #'eq)
        (eq (getf validation-state :release-review-state) :blocked))))

(defun reconciliation-rationale (decision packet state gap-types)
  (list :decision-basis decision
        :alignment-status (getf state :status)
        :divergence-types (copy-list (or (getf state :divergence-types) '()))
        :gap-types (copy-list gap-types)
        :intent-id (getf (getf packet :intent) :current-intent-id)
        :governance-required-p (constraints-require-governance-p (or (getf packet :constraints) '()))))

(defun build-reconciliation-decision-from-state (packet state)
  (let* ((divergence-types (or (getf state :divergence-types) '()))
         (gap-types (alignment-gap-types packet))
         (decision (reconciliation-decision-kind divergence-types gap-types))
         (confidence (clamp-score
                      (if (eq decision :maintain)
                          (+ 0.10 (or (getf state :confidence) 0.0))
                          (or (getf state :confidence) 0.0))))
         (requires-approval-p (reconciliation-requires-approval-p decision packet gap-types)))
    (make-reconciliation-decision
     :intent-id (getf state :intent-id)
     :alignment-status (getf state :status)
     :divergence-types (copy-list divergence-types)
     :decision decision
     :proposed-actions (reconciliation-proposed-actions decision packet divergence-types gap-types)
     :trigger-events (reconciliation-trigger-events packet)
     :approval-posture (reconciliation-approval-posture decision requires-approval-p packet)
     :confidence confidence
     :requires-approval-p requires-approval-p
     :rationale (reconciliation-rationale decision packet state gap-types)
     :last-evaluated (get-universal-time))))

(defun reconciliation-decision->plist (decision)
  (list :intent-id (reconciliation-decision-intent-id decision)
        :alignment-status (reconciliation-decision-alignment-status decision)
        :divergence-types (copy-list (or (reconciliation-decision-divergence-types decision) '()))
        :decision (reconciliation-decision-decision decision)
        :proposed-actions (copy-tree (or (reconciliation-decision-proposed-actions decision) '()))
        :trigger-events (copy-tree (or (reconciliation-decision-trigger-events decision) '()))
        :approval-posture (reconciliation-decision-approval-posture decision)
        :confidence (reconciliation-decision-confidence decision)
        :requires-approval-p (reconciliation-decision-requires-approval-p decision)
        :rationale (copy-tree (or (reconciliation-decision-rationale decision) '()))
        :last-evaluated (reconciliation-decision-last-evaluated decision)))

(defun compute-reconciliation-decision (session &key (prompt +default-reconciliation-prompt+)
                                                 (operator-mode :conversation))
  (let* ((packet (build-alignment-context-packet session prompt :operator-mode operator-mode))
         (state (alignment-state->plist
                 (build-alignment-state-from-packet packet))))
    (reconciliation-decision->plist
     (build-reconciliation-decision-from-state packet state))))

(defun query-reconciliation-decision-service (session prompt &key (operator-mode :conversation))
  (let* ((packet (build-alignment-context-packet session prompt :operator-mode operator-mode))
         (state (alignment-state->plist
                 (build-alignment-state-from-packet packet)))
         (decision (build-reconciliation-decision-from-state packet state)))
    (make-service-query-response
     :alignment
     :reconciliation-decision
     (append (reconciliation-decision->plist decision)
             (list :alignment-state state
                   :context-packet packet))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :reconciliation-decision-v1
                                      :session session))))
