(in-package #:sbcl-agent)

(defstruct alignment-state
  intent-id
  score
  divergence-types
  confidence
  status
  last-evaluated
  gap-count
  linkage-state
  validation-state
  summary)

(defparameter +default-alignment-evaluation-prompt+
  "Evaluate the current environment, runtime, project, and governance posture for continuous alignment.")

(defun clamp-score (value)
  (max 0.0 (min 1.0 value)))

(defun alignment-gap-type (gap)
  (and (listp gap)
       (getf gap :type)))

(defun alignment-divergence-types-from-packet (packet)
  (let* ((intent (getf packet :intent))
         (gaps (or (getf packet :alignment-gaps) '()))
         (divergence-types '()))
    (when (null (getf intent :current-intent-id))
      (push :outdated-intent divergence-types))
    (when (or (null (getf intent :constraints))
              (null (getf intent :expected-behaviors)))
      (push :incomplete-specification divergence-types))
    (when (eq (getf (getf intent :summary) :status) :deprecated)
      (push :outdated-intent divergence-types))
    (dolist (gap gaps)
      (case (alignment-gap-type gap)
        (:missing-linked-event
         (push :incomplete-specification divergence-types))
        (:missing-linked-mutation
         (push :missing-capability divergence-types))
        (:source-divergence
         (push :behavioral-mismatch divergence-types))
        (:testing-failures-present
         (push :behavioral-mismatch divergence-types))
        (:project-readiness-blocked
         (push :incorrect-constraint-enforcement divergence-types))))
    (remove-duplicates (nreverse divergence-types) :test #'eq)))

(defun alignment-score-penalty (gap)
  (case (alignment-gap-type gap)
    (:missing-linked-event 0.12)
    (:missing-linked-mutation 0.15)
    (:source-divergence 0.25)
    (:testing-failures-present 0.25)
    (:project-readiness-blocked 0.20)
    (otherwise 0.05)))

(defun alignment-score-from-packet (packet)
  (let* ((intent (getf packet :intent))
         (gaps (or (getf packet :alignment-gaps) '()))
         (base-score (if (getf intent :current-intent-id) 1.0 0.55))
         (intent-completeness-penalty (if (and (getf intent :constraints)
                                               (getf intent :expected-behaviors))
                                          0.0
                                          0.10))
         (status-penalty (if (eq (getf (getf intent :summary) :status) :deprecated)
                             0.15
                             0.0))
         (gap-penalty (reduce #'+ gaps :initial-value 0.0 :key #'alignment-score-penalty)))
    (clamp-score (- base-score intent-completeness-penalty status-penalty gap-penalty))))

(defun alignment-confidence-from-packet (packet)
  (let* ((intent (getf packet :intent))
         (runtime-scope (getf packet :runtime-scope))
         (source-scope (getf packet :source-scope))
         (validation-state (getf packet :validation-state))
         (linkage-state (getf packet :linkage-state))
         (base 0.45)
         (intent-bonus (if (getf intent :current-intent-id) 0.12 0.0))
         (runtime-bonus (if runtime-scope 0.10 0.0))
         (source-bonus (if source-scope 0.10 0.0))
         (validation-bonus (if validation-state 0.08 0.0))
         (resolved-event-bonus (* 0.04 (min 3 (or (getf linkage-state :resolved-event-count) 0))))
         (resolved-mutation-bonus (* 0.05 (min 3 (or (getf linkage-state :resolved-mutation-count) 0)))))
    (clamp-score (+ base
                    intent-bonus
                    runtime-bonus
                    source-bonus
                    validation-bonus
                    resolved-event-bonus
                    resolved-mutation-bonus))))

(defun alignment-status-from-score (score)
  (cond
    ((>= score 0.90) :aligned)
    ((>= score 0.65) :degraded)
    (t :misaligned)))

(defun alignment-state-packet-summary (packet divergence-types)
  (list :intent-description (getf (getf packet :intent) :summary)
        :divergence-count (length divergence-types)
        :gap-count (length (or (getf packet :alignment-gaps) '()))
        :release-readiness (getf (getf packet :validation-state) :project-readiness)
        :linkage-state (getf packet :linkage-state)))

(defun build-alignment-state-from-packet (packet)
  (let* ((score (alignment-score-from-packet packet))
         (divergence-types (alignment-divergence-types-from-packet packet))
         (confidence (alignment-confidence-from-packet packet))
         (status (alignment-status-from-score score)))
    (make-alignment-state
     :intent-id (getf (getf packet :intent) :current-intent-id)
     :score score
     :divergence-types divergence-types
     :confidence confidence
     :status status
     :last-evaluated (get-universal-time)
     :gap-count (length (or (getf packet :alignment-gaps) '()))
     :linkage-state (copy-tree (or (getf packet :linkage-state) '()))
     :validation-state (copy-tree (or (getf packet :validation-state) '()))
     :summary (alignment-state-packet-summary packet divergence-types))))

(defun alignment-state->plist (state)
  (list :intent-id (alignment-state-intent-id state)
        :score (alignment-state-score state)
        :divergence-types (copy-list (or (alignment-state-divergence-types state) '()))
        :confidence (alignment-state-confidence state)
        :status (alignment-state-status state)
        :last-evaluated (alignment-state-last-evaluated state)
        :gap-count (alignment-state-gap-count state)
        :linkage-state (copy-tree (or (alignment-state-linkage-state state) '()))
        :validation-state (copy-tree (or (alignment-state-validation-state state) '()))
        :summary (copy-tree (or (alignment-state-summary state) '()))))

(defun compute-alignment-state (session &key (prompt +default-alignment-evaluation-prompt+)
                                           (operator-mode :conversation))
  (alignment-state->plist
   (build-alignment-state-from-packet
    (build-alignment-context-packet session prompt :operator-mode operator-mode))))

(defun project-alignment-evaluation-prompt (project)
  (format nil
          "Evaluate continuous alignment for project ~A across runtime, requirements, testing, readiness, and governance."
          (project-record-title project)))

(defun query-alignment-state-service (session prompt &key (operator-mode :conversation))
  (let* ((packet (build-alignment-context-packet session prompt :operator-mode operator-mode))
         (state (build-alignment-state-from-packet packet)))
    (make-service-query-response
     :alignment
     :state
     (append (alignment-state->plist state)
             (list :context-packet packet))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :alignment-state-v1
                                      :session session))))
