(in-package #:sbcl-agent)

(defstruct validation-result
  kind
  status
  executed-at
  evidence
  tainted-p)

(defstruct image-reconciliation-record
  recorded-at
  replay-id
  image-summary
  source-summary
  status)

(defstruct reconciliation-record
  status
  recorded-at
  summary
  live-status
  cold-status
  reproducibility-status
  taint-status
  taint-reasons)

(defstruct checkpoint-record
  id
  captured-at
  source-snapshot
  image-snapshot-ref
  worker-summaries
  validation-baseline)

(defstruct mutation-transaction
  id
  work-item-id
  replay-id
  scope
  checkpoint-id
  state
  source-mutations
  image-mutations
  resource-effects
  rollback-status
  rollback-detail
  quarantine-status)

(defstruct validator-task-record
  id
  replay-id
  kind
  checkpoint-id
  status
  resume-command
  created-at
  completed-at)

(defstruct provenance-record
  source-hash
  image-snapshot-id
  introspection-queries
  executed-mutations
  before-after-map
  runtime-observations
  validation-outputs
  final-source-diff
  rollback-availability
  taint-status
  taint-reasons
  approval-checkpoints
  operator-interventions)

(defstruct work-item
  id
  goal
  status
  created-at
  updated-at
  source-snapshot
  image-snapshot-ref
  workflow-record-ref
  introspection-evidence
  mutation-intent
  runtime-observations
  live-validation-result
  cold-validation-result
  pending-validations
  validator-tasks
  next-action
  resume-payload
  image-reconciliation
  reconciliation-result
  rollback-point
  taint-status
  closure-decision
  transaction-ids
  transactions
  checkpoints
  provenance)

(defun work-item-long-horizon-plan (work-item)
  (getf (work-item-mutation-intent work-item) :long-horizon-plan))

(defun work-item-operator-steering-history (work-item)
  (copy-list (or (getf (work-item-mutation-intent work-item) :operator-steering-history) '())))

(defun set-work-item-long-horizon-plan (work-item long-horizon-plan)
  (setf (getf (work-item-mutation-intent work-item) :long-horizon-plan) long-horizon-plan
        (work-item-updated-at work-item) (get-universal-time))
  long-horizon-plan)

(defun append-work-item-operator-steering-history (work-item directive)
  (setf (getf (work-item-mutation-intent work-item) :operator-steering-history)
        (append (work-item-operator-steering-history work-item)
                (list directive))
        (work-item-updated-at work-item) (get-universal-time))
  directive)

(defun work-item-plan-health (work-item)
  (cond
    ((work-item-resume-payload work-item)
     :resumable)
    ((member (work-item-status work-item)
             '(:awaiting-approval :awaiting-cold-validation :quarantined)
             :test #'eq)
     :waiting)
    ((member (work-item-status work-item)
             '(:failed :rolled-back)
             :test #'eq)
     :interrupted)
    (t
     :active)))

(defun work-item-plan-current-phase (work-item)
  (cond
    ((member (work-item-status work-item) '(:awaiting-cold-validation :committed) :test #'eq)
     :validate)
    ((member (work-item-status work-item) '(:awaiting-approval :quarantined :failed :rolled-back) :test #'eq)
     :resolve-blockers)
    ((eq (work-item-plan-health work-item) :resumable)
     :resolve-blockers)
    (t
     (case (work-item-status work-item)
       (:planned :plan)
       ((:checkpointed :mutating) :mutate)
       (t (or (first (getf (work-item-long-horizon-plan work-item) :planning-phases))
              :inspect))))))

(defun work-item-plan-revision-reason (work-item)
  (cond
    ((member (work-item-status work-item) '(:quarantined :failed :rolled-back) :test #'eq)
     :incident-recovery)
    ((member (work-item-status work-item) '(:awaiting-cold-validation :committed) :test #'eq)
     :validation-pending)
    ((eq (work-item-plan-health work-item) :resumable)
     :blocked-awaiting-resume)
    ((member (work-item-status work-item) '(:checkpointed :mutating) :test #'eq)
     :partial-progress)
    (t
     :steady-state)))

(defun work-item-plan-phase-index (phases phase)
  (position phase phases :test #'eq))

(defun work-item-remaining-planning-phases (work-item)
  (let* ((phases (copy-list (or (getf (work-item-long-horizon-plan work-item) :planning-phases) '())))
         (current-phase (work-item-plan-current-phase work-item))
         (index (work-item-plan-phase-index phases current-phase)))
    (cond
      (index
       (subseq phases index))
      ((null phases)
       (list current-phase))
      (t
       (append (list current-phase)
               phases)))))

(defun work-item-completed-phase-count (work-item)
  (let* ((phases (or (getf (work-item-long-horizon-plan work-item) :planning-phases) '()))
         (current-phase (work-item-plan-current-phase work-item))
         (index (work-item-plan-phase-index phases current-phase)))
    (or index 0)))

(defun work-item-plan-steering (work-item)
  (let* ((resume-payload (work-item-resume-payload work-item))
         (next-action (work-item-next-action work-item))
         (plan (work-item-long-horizon-plan work-item))
         (remaining-phases (work-item-remaining-planning-phases work-item))
         (completed-phase-count (work-item-completed-phase-count work-item))
         (revision-reason (work-item-plan-revision-reason work-item))
         (original-phases (copy-list (or (getf plan :planning-phases) '())))
         (latest-operator-steering (car (last (work-item-operator-steering-history work-item)))))
    (when (or plan latest-operator-steering)
      (list :current-phase (work-item-plan-current-phase work-item)
            :next-step (or (getf next-action :suggested-step)
                           (getf next-action :type)
                           (getf resume-payload :resume-command))
            :resume-anchor (or (getf resume-payload :resume-command)
                               (getf next-action :type))
            :phase-count (or (getf plan :phase-count) 0)
            :planning-phases original-phases
            :remaining-phases remaining-phases
            :completed-phase-count completed-phase-count
            :decomposition-ready-p (> (or (getf plan :phase-count) 0) 1)
            :compacted-p (or (not (equal remaining-phases original-phases))
                             (not (eq revision-reason :steady-state)))
            :revision-reason revision-reason
            :operator-directed-phase (and latest-operator-steering
                                          (getf latest-operator-steering :phase))
            :operator-directed-next-step (and latest-operator-steering
                                              (getf latest-operator-steering :next-step))
            :operator-steering-count (length (work-item-operator-steering-history work-item))
            :review-required-p (eq (getf next-action :type) :serial-review-merge)
            :plan-health (work-item-plan-health work-item)))))

(defun enrich-work-item-control-payload (work-item payload)
  (append (copy-list (or payload '()))
          (let ((plan (work-item-long-horizon-plan work-item)))
            (when plan
              (list :long-horizon-plan plan
                    :plan-health (work-item-plan-health work-item)
                    :plan-steering (work-item-plan-steering work-item))))))

(defun make-work-item-id ()
  (format nil "work-~D-~D" (get-universal-time) (random 1000000)))

(defun make-mutation-transaction-id ()
  (format nil "txn-~D-~D" (get-universal-time) (random 1000000)))

(defun make-checkpoint-id ()
  (format nil "checkpoint-~D-~D" (get-universal-time) (random 1000000)))

(defun make-replay-id (prefix work-item-id &optional detail)
  (format nil "~A-~X"
          prefix
          (abs (sxhash (list prefix work-item-id detail)))))

(defun make-validator-task-id (work-item-id kind checkpoint-id)
  (make-replay-id "validator" work-item-id (list kind checkpoint-id)))

(defun session-work-items (session)
  (agent-session-work-items session))

(defun capture-work-item-source-snapshot (session)
  (list :captured-at (get-universal-time)
        :cwd (agent-session-cwd session)
        :plan (session-plan-display-value session)
        :transcript-count (length (agent-session-transcript session))
        :event-count (length (agent-session-events session))))

(defun capture-work-item-image-snapshot-reference (session)
  (list :captured-at (get-universal-time)
        :session-id (agent-session-id session)
        :package (agent-session-package session)
        :task-count (length (agent-session-tasks session))
        :worker-count (length (agent-session-workers session))
        :event-count (length (agent-session-events session))))

(defun make-work-item-transaction (work-item-id &key scope)
  (let ((transaction-id (make-mutation-transaction-id)))
    (make-mutation-transaction :id transaction-id
                               :work-item-id work-item-id
                               :replay-id (make-replay-id "txn" work-item-id (list scope transaction-id))
                               :scope (or scope :transitional-task)
                               :checkpoint-id nil
                               :state :created
                               :source-mutations '()
                               :image-mutations '()
                               :resource-effects '()
                               :rollback-status :not-started
                               :rollback-detail nil
                               :quarantine-status nil)))

(defun validation-result-summary (result)
  (and result
       (list :kind (validation-result-kind result)
             :status (validation-result-status result)
             :executed-at (validation-result-executed-at result)
             :tainted-p (validation-result-tainted-p result)
             :evidence (validation-result-evidence result))))

(defun reconciliation-record-view (record)
  (and record
       (list :status (reconciliation-record-status record)
             :recorded-at (reconciliation-record-recorded-at record)
             :summary (reconciliation-record-summary record)
             :live-status (reconciliation-record-live-status record)
             :cold-status (reconciliation-record-cold-status record)
             :reproducibility-status (reconciliation-record-reproducibility-status record)
             :taint-status (reconciliation-record-taint-status record)
             :taint-reasons (reconciliation-record-taint-reasons record))))

(defun checkpoint-summary (checkpoint)
  (list :id (checkpoint-record-id checkpoint)
        :captured-at (checkpoint-record-captured-at checkpoint)
        :worker-count (length (checkpoint-record-worker-summaries checkpoint))
        :validation-baseline (checkpoint-record-validation-baseline checkpoint)))

(defun latest-work-item-checkpoint (work-item)
  (car (last (work-item-checkpoints work-item))))

(defun latest-work-item-checkpoint-id (work-item)
  (let ((checkpoint (latest-work-item-checkpoint work-item)))
    (and checkpoint (checkpoint-record-id checkpoint))))

(defun validator-task-record-summary (record)
  (list :id (validator-task-record-id record)
        :replay-id (validator-task-record-replay-id record)
        :kind (validator-task-record-kind record)
        :checkpoint-id (validator-task-record-checkpoint-id record)
        :status (validator-task-record-status record)
        :resume-command (validator-task-record-resume-command record)
        :created-at (validator-task-record-created-at record)
        :completed-at (validator-task-record-completed-at record)))

(defun work-item-validator-actions (work-item)
  (mapcar #'validator-task-record-summary (work-item-validator-tasks work-item)))

(defun find-validator-task-record (work-item validator-task-id)
  (find validator-task-id (work-item-validator-tasks work-item)
        :key #'validator-task-record-id :test #'string=))

(defun find-validator-task-record-by-replay-id (work-item replay-id)
  (find replay-id (work-item-validator-tasks work-item)
        :key #'validator-task-record-replay-id :test #'string=))

(defun work-item-bound-thread (session work-item)
  (let* ((thread-id (getf (work-item-mutation-intent work-item) :thread-id))
         (thread (and thread-id
                      (find-thread session thread-id))))
    (or thread
        (ignore-errors (current-thread session)))))

(defun work-item-bound-turn (session work-item)
  (let* ((turn-id (getf (work-item-mutation-intent work-item) :turn-id))
         (turn (and turn-id
                    (find-turn session turn-id))))
    turn))

(defun create-work-item-artifact (session work-item kind title summary &key metadata)
  (let ((thread (work-item-bound-thread session work-item)))
    (if thread
        (create-artifact session
                         thread
                         (work-item-bound-turn session work-item)
                         nil
                         kind
                         nil
                         :title title
                         :summary summary
                         :work-item-id (work-item-id work-item)
                         :metadata metadata)
        (create-environment-artifact session
                                     kind
                                     nil
                                     :title title
                                     :summary summary
                                     :work-item-id (work-item-id work-item)
                                     :metadata metadata))))

(defun normalize-validator-status (status)
  (case status
    ((:passed :failed :partial) status)
    (t (error "Unsupported validator status ~S" status))))

(defun validator-status-for-kind (kind default statuses)
  (or (and statuses (getf statuses kind)) default))

(defun execute-validator-task-record (session work-item validator-task-id &key (status :passed) evidence)
  (let ((record (find-validator-task-record work-item validator-task-id))
        (final-closure-decision (work-item-final-closure-decision work-item))
        (normalized-status (normalize-validator-status status)))
    (unless record
      (error "Unknown validator task ~A for work-item ~A" validator-task-id (work-item-id work-item)))
    (setf (validator-task-record-status record) normalized-status
          (validator-task-record-completed-at record) (get-universal-time))
    (ecase (validator-task-record-kind record)
      (:live
       (setf (work-item-live-validation-result work-item)
             (make-live-validation-result normalized-status
                                          (or evidence
                                              (list :validator-task-id validator-task-id
                                                    :replay-id (validator-task-record-replay-id record)
                                                    :checkpoint-id (validator-task-record-checkpoint-id record))))))
      (:cold
       (setf (work-item-cold-validation-result work-item)
             (make-cold-validation-result normalized-status
                                          (or evidence
                                              (list :validator-task-id validator-task-id
                                                    :replay-id (validator-task-record-replay-id record)
                                                    :checkpoint-id (validator-task-record-checkpoint-id record)))))))
    (refresh-work-item-pending-validations session work-item)
    (set-work-item-next-action session work-item
                               (if (work-item-pending-validations work-item)
                                   (list :type :complete-pending-validations
                                         :pending (work-item-pending-validations work-item)
                                         :final-closure-decision final-closure-decision)
                                   nil))
    (set-work-item-resume-payload session work-item
                                  (if (work-item-pending-validations work-item)
                                      (list :resume-command :complete-validations
                                            :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                            :pending (work-item-pending-validations work-item)
                                            :validator-actions (work-item-validator-actions work-item)
                                            :replay-id (mutation-transaction-replay-id (current-work-item-transaction work-item))
                                            :rollback-point (work-item-rollback-point work-item)
                                            :final-closure-decision final-closure-decision)
                                      nil))
    (reconcile-validation-results work-item)
    (finalize-work-item-cold-validation session
                                        work-item
                                        :final-closure-decision final-closure-decision)
    (append-work-item-workflow-entry session work-item
                                     :validate
                                     :validator-task-executed
                                     (list :validator-task (validator-task-record-summary record)
                                           :validation-result (case (validator-task-record-kind record)
                                                                (:live (validation-result-summary (work-item-live-validation-result work-item)))
                                                                (:cold (validation-result-summary (work-item-cold-validation-result work-item))))))
    (create-work-item-artifact session
                               work-item
                               :validation
                               (format nil "~(~A~) validation ~A"
                                       (validator-task-record-kind record)
                                       normalized-status)
                               "Validator result recorded."
                               :metadata (list :validator-task-id (validator-task-record-id record)
                                               :validator-kind (validator-task-record-kind record)
                                               :status normalized-status
                                               :checkpoint-id (validator-task-record-checkpoint-id record)
                                               :replay-id (validator-task-record-replay-id record)
                                               :evidence (or evidence
                                                             (case (validator-task-record-kind record)
                                                               (:live (validation-result-summary (work-item-live-validation-result work-item)))
                                                               (:cold (validation-result-summary (work-item-cold-validation-result work-item)))))))
    record))

(defun execute-validator-replay-set (session work-item replay-id &key (status :passed) statuses)
  (let* ((normalized-status (normalize-validator-status status))
         (records (remove-if-not (lambda (record)
                                   (string= replay-id (validator-task-record-replay-id record)))
                                 (work-item-validator-tasks work-item))))
    (unless records
      (error "Unknown validator replay id ~A for work-item ~A" replay-id (work-item-id work-item)))
    (dolist (record records)
      (execute-validator-task-record session
                                     work-item
                                     (validator-task-record-id record)
                                     :status (normalize-validator-status
                                              (validator-status-for-kind (validator-task-record-kind record)
                                                                         normalized-status
                                                                         statuses))
                                     :evidence (list :validator-task-id (validator-task-record-id record)
                                                     :replay-id replay-id
                                                     :checkpoint-id (validator-task-record-checkpoint-id record)
                                                     :batch-replay-p t)))
    records))

(defun reconcile-image-only-work-item-to-source (session work-item summary)
  (unless (eq (work-item-status work-item) :image-only)
    (error "Work-item ~A is not in image-only state" (work-item-id work-item)))
  (let ((transaction (current-work-item-transaction work-item)))
    (when transaction
      (setf (mutation-transaction-state transaction) :committed))
    (setf (work-item-status work-item) :committed
          (work-item-closure-decision work-item) :committed-to-source-and-image
          (work-item-image-reconciliation work-item)
          (make-image-reconciliation-record :recorded-at (get-universal-time)
                                            :replay-id (and transaction (mutation-transaction-replay-id transaction))
                                            :image-summary (work-item-resume-payload work-item)
                                            :source-summary summary
                                            :status :attached-to-source)
          (work-item-updated-at work-item) (get-universal-time))
    (refresh-work-item-pending-validations session work-item)
    (set-work-item-next-action session work-item nil)
    (set-work-item-resume-payload session work-item nil)
    (append-work-item-source-mutation work-item
                                      (list :kind :image-only-reconciliation
                                            :summary summary)
                                      session)
    (append-work-item-workflow-entry session work-item
                                     :reconcile
                                     :image-only-reconciled-to-source
                                     (list :summary summary
                                           :replay-id (and transaction (mutation-transaction-replay-id transaction)))
                                     :status :committed)
    (create-work-item-artifact session
                               work-item
                               :reconciliation
                               "Image-only reconciliation"
                               "Image-only work reconciled back to source."
                               :metadata (list :summary summary
                                               :status :attached-to-source
                                               :replay-id (and transaction
                                                               (mutation-transaction-replay-id transaction))))
    (let ((record (work-item-workflow-record session work-item)))
      (when record
        (close-workflow-record session
                               record
                               (list :work-item-status :committed
                                     :closure-decision :committed-to-source-and-image
                                     :summary summary)
                               :status :committed
                               :evidence (work-item-summary work-item))))
    work-item))

(defun refresh-work-item-validator-tasks (session work-item)
  (let* ((checkpoint-id (latest-work-item-checkpoint-id work-item))
         (pending (work-item-pending-validations work-item))
         (existing (work-item-validator-tasks work-item))
         (updated
          (mapcar (lambda (kind)
                    (or (find kind existing :key #'validator-task-record-kind :test #'eq)
                        (make-validator-task-record
                         :id (make-validator-task-id (work-item-id work-item) kind checkpoint-id)
                         :replay-id (make-replay-id "validator-replay" (work-item-id work-item) (list kind checkpoint-id))
                         :kind kind
                         :checkpoint-id checkpoint-id
                         :status :pending
                         :resume-command :complete-validations
                         :created-at (get-universal-time)
                         :completed-at nil)))
                  pending)))
    (dolist (record updated)
      (setf (validator-task-record-checkpoint-id record) checkpoint-id)
      (when (null (validator-task-record-completed-at record))
        (setf (validator-task-record-status record) :pending)))
    (dolist (record existing)
      (unless (member (validator-task-record-kind record) pending :test #'eq)
        (when (eq (validator-task-record-status record) :pending)
          (setf (validator-task-record-status record) :completed))
        (setf (validator-task-record-completed-at record) (or (validator-task-record-completed-at record)
                                                              (get-universal-time)))))
    (setf (work-item-validator-tasks work-item)
          (append
           (mapcar (lambda (record)
                     (or (find (validator-task-record-kind record) updated
                               :key #'validator-task-record-kind :test #'eq)
                         record))
                   existing)
           (remove-if (lambda (record)
                        (find (validator-task-record-kind record) existing
                              :key #'validator-task-record-kind :test #'eq))
                      updated))
          (work-item-updated-at work-item) (get-universal-time))
    (append-work-item-workflow-entry session
                                     work-item
                                     :validate
                                     :validator-tasks-updated
                                     (mapcar #'validator-task-record-summary (work-item-validator-tasks work-item)))
    (work-item-validator-tasks work-item)))

(defun transaction-summary (transaction)
  (list :id (mutation-transaction-id transaction)
        :replay-id (mutation-transaction-replay-id transaction)
        :scope (mutation-transaction-scope transaction)
        :checkpoint-id (mutation-transaction-checkpoint-id transaction)
        :state (mutation-transaction-state transaction)
        :rollback-status (mutation-transaction-rollback-status transaction)
        :rollback-detail (mutation-transaction-rollback-detail transaction)
        :quarantine-status (mutation-transaction-quarantine-status transaction)
        :source-mutation-count (length (mutation-transaction-source-mutations transaction))
        :image-mutation-count (length (mutation-transaction-image-mutations transaction))
        :resource-effect-count (length (mutation-transaction-resource-effects transaction))))

(defun summarize-corrective-action (action)
  (when action
    (list :kind (getf action :kind)
          :target (getf action :target)
          :reason (getf action :reason))))

(defun summarize-corrective-trigger-event (event)
  (when event
    (list :event-id (getf event :event-id)
          :kind (getf event :kind)
          :family (getf event :family)
          :entity-id (getf event :entity-id))))

(defun work-item-corrective-context (work-item)
  (let ((intent (work-item-mutation-intent work-item)))
    (when (eq (getf intent :source) :reconciliation-decision)
      (list :kind :alignment-reconciliation
            :intent-id (getf intent :intent-id)
            :decision (getf intent :decision)
            :approval-posture (getf intent :approval-posture)
            :alignment-status (getf (getf intent :alignment-state) :status)
            :alignment-score (getf (getf intent :alignment-state) :score)
            :proposed-actions (mapcar #'summarize-corrective-action
                                      (or (getf intent :proposed-actions) '()))
            :trigger-events (mapcar #'summarize-corrective-trigger-event
                                    (or (getf (getf (getf intent :context-packet) :relevant-events)
                                              :resolved-linked-events)
                                        '()))))))

(defun provenance-record-summary (record)
  (and record
       (list :source-hash (provenance-record-source-hash record)
             :image-snapshot-id (provenance-record-image-snapshot-id record)
             :introspection-query-count (length (provenance-record-introspection-queries record))
             :executed-mutation-count (length (provenance-record-executed-mutations record))
             :validation-output-count (length (provenance-record-validation-outputs record))
             :rollback-availability (provenance-record-rollback-availability record)
             :taint-status (provenance-record-taint-status record)
             :taint-reasons (provenance-record-taint-reasons record)
             :approval-checkpoint-count (length (provenance-record-approval-checkpoints record))
             :operator-intervention-count (length (provenance-record-operator-interventions record)))))

(defun make-initial-provenance-record (source-snapshot image-snapshot-ref)
  (make-provenance-record :source-hash (sxhash source-snapshot)
                          :image-snapshot-id (getf image-snapshot-ref :session-id)
                          :introspection-queries '()
                          :executed-mutations '()
                          :before-after-map '()
                          :runtime-observations '()
                          :validation-outputs '()
                          :final-source-diff nil
                          :rollback-availability :not-started
                          :taint-status :clean
                          :taint-reasons '()
                          :approval-checkpoints '()
                          :operator-interventions '()))

(defun append-work-item-source-mutation (work-item payload &optional session)
  (let ((transaction (current-work-item-transaction work-item)))
    (when transaction
      (setf (mutation-transaction-source-mutations transaction)
            (append (mutation-transaction-source-mutations transaction) (list payload))))
    (setf (provenance-record-executed-mutations (work-item-provenance work-item))
          (append (provenance-record-executed-mutations (work-item-provenance work-item))
                  (list (list :kind :source :payload payload))))
    (when session
      (append-work-item-workflow-entry session work-item :mutate-source :source-mutation payload :status :in-progress))
    payload))

(defun append-work-item-image-mutation (work-item payload &optional session)
  (let ((transaction (current-work-item-transaction work-item)))
    (when transaction
      (setf (mutation-transaction-image-mutations transaction)
            (append (mutation-transaction-image-mutations transaction) (list payload))))
    (setf (provenance-record-executed-mutations (work-item-provenance work-item))
          (append (provenance-record-executed-mutations (work-item-provenance work-item))
                  (list (list :kind :image :payload payload))))
    (when session
      (append-work-item-workflow-entry session work-item :mutate-image :image-mutation payload :status :in-progress))
    payload))

(defun append-work-item-resource-effect (work-item payload &optional session)
  (let ((transaction (current-work-item-transaction work-item)))
    (when transaction
      (setf (mutation-transaction-resource-effects transaction)
            (append (mutation-transaction-resource-effects transaction) (list payload))))
    (when session
      (append-work-item-workflow-entry session work-item :observe-runtime :resource-effect payload :status :in-progress))
    payload))


(defun work-item-summary (work-item)
  (list :id (work-item-id work-item)
        :goal (work-item-goal work-item)
        :status (work-item-status work-item)
        :created-at (work-item-created-at work-item)
        :updated-at (work-item-updated-at work-item)
        :source-snapshot (work-item-source-snapshot work-item)
        :image-snapshot-ref (work-item-image-snapshot-ref work-item)
        :mutation-intent (work-item-mutation-intent work-item)
        :long-horizon-plan (work-item-long-horizon-plan work-item)
        :plan-health (work-item-plan-health work-item)
        :plan-steering (work-item-plan-steering work-item)
        :operator-steering-history (work-item-operator-steering-history work-item)
        :runtime-observation-count (length (work-item-runtime-observations work-item))
        :live-validation-result (validation-result-summary (work-item-live-validation-result work-item))
        :cold-validation-result (validation-result-summary (work-item-cold-validation-result work-item))
        :pending-validations (work-item-pending-validations work-item)
        :validator-tasks (mapcar #'validator-task-record-summary (work-item-validator-tasks work-item))
        :next-action (work-item-next-action work-item)
        :resume-payload (work-item-resume-payload work-item)
        :corrective-context (work-item-corrective-context work-item)
        :image-reconciliation (let ((record (work-item-image-reconciliation work-item)))
                                (and record
                                     (list :recorded-at (image-reconciliation-record-recorded-at record)
                                           :replay-id (image-reconciliation-record-replay-id record)
                                           :image-summary (image-reconciliation-record-image-summary record)
                                           :source-summary (image-reconciliation-record-source-summary record)
                                           :status (image-reconciliation-record-status record))))
        :reconciliation-result (reconciliation-record-view (work-item-reconciliation-result work-item))
        :rollback-point (work-item-rollback-point work-item)
        :taint-status (work-item-taint-status work-item)
        :taint-reasons (work-item-taint-reasons work-item)
        :closure-decision (work-item-closure-decision work-item)
        :workflow-record-ref (work-item-workflow-record-ref work-item)
        :transaction-ids (work-item-transaction-ids work-item)
        :checkpoint-count (length (work-item-checkpoints work-item))
        :provenance (provenance-record-summary (work-item-provenance work-item))))

(defun work-item-detail (work-item)
  (append (work-item-summary work-item)
          (list :transactions (mapcar #'transaction-summary (work-item-transactions work-item))
                :checkpoints (mapcar #'checkpoint-summary (work-item-checkpoints work-item))
                :latest-runtime-observation (let ((events (work-item-runtime-observations work-item)))
                                              (and events (car (last events))))
                :provenance-detail (provenance-record-summary (work-item-provenance work-item))
                :workflow-record-ref (work-item-workflow-record-ref work-item))))

(defun find-work-item (session work-item-id)
  (find work-item-id (agent-session-work-items session)
        :key #'work-item-id :test #'string=))

(defun list-work-item-summaries (session)
  (mapcar #'work-item-summary (agent-session-work-items session)))

(defun work-item-workflow-record (session work-item)
  (and (work-item-workflow-record-ref work-item)
       (find-workflow-record session (work-item-workflow-record-ref work-item))))

(defun append-work-item-workflow-entry (session work-item phase kind payload &key status)
  (let ((record (work-item-workflow-record session work-item)))
    (when record
      (append-workflow-record-entry session record phase kind payload :status status))))

(defun work-item-pending-validation-kinds (work-item)
  (let ((pending '()))
    (unless (work-item-live-validation-result work-item)
      (push :live pending))
    (unless (work-item-cold-validation-result work-item)
      (push :cold pending))
    (nreverse pending)))

(defun refresh-work-item-pending-validations (session work-item)
  (let ((pending (if (member (work-item-status work-item)
                             '(:committed :rolled-back :failed :image-only)
                             :test #'eq)
                     '()
                     (work-item-pending-validation-kinds work-item))))
    (setf (work-item-pending-validations work-item) pending
          (work-item-updated-at work-item) (get-universal-time))
    (let ((record (work-item-workflow-record session work-item)))
      (when record
        (update-workflow-record-pending-validations record pending :session session)))
    (refresh-work-item-validator-tasks session work-item)
    pending))

(defun set-work-item-next-action (session work-item next-action)
  (setf (work-item-next-action work-item) (and next-action
                                               (enrich-work-item-control-payload work-item next-action))
        (work-item-updated-at work-item) (get-universal-time))
  (let ((record (work-item-workflow-record session work-item)))
    (when record
      (update-workflow-record-next-action record (work-item-next-action work-item) :session session)))
  (work-item-next-action work-item))

(defun set-work-item-resume-payload (session work-item resume-payload)
  (setf (work-item-resume-payload work-item) (and resume-payload
                                                  (enrich-work-item-control-payload work-item resume-payload))
        (work-item-updated-at work-item) (get-universal-time))
  (let ((record (work-item-workflow-record session work-item)))
    (when record
      (update-workflow-record-resume-payload record (work-item-resume-payload work-item) :session session)))
  (work-item-resume-payload work-item))

(defun latest-work-item-approval-policy (session work-item)
  (let* ((record (work-item-workflow-record session work-item))
         (requirement (and record
                           (car (last (workflow-record-approval-requirements record))))))
    (and requirement
         (getf requirement :policy))))

(defun latest-work-item-approval-reason (session work-item)
  (let* ((record (work-item-workflow-record session work-item))
         (requirement (and record
                           (car (last (workflow-record-approval-requirements record))))))
    (and requirement
         (getf requirement :reason))))

(defun derived-work-item-next-action (session work-item)
  (let ((policy (latest-work-item-approval-policy session work-item))
        (reason (or (and (work-item-workflow-record session work-item)
                         (workflow-record-quarantine-reason
                          (work-item-workflow-record session work-item)))
                    (latest-work-item-approval-reason session work-item))))
    (case (work-item-status work-item)
      (:awaiting-approval
       (list :type :await-approval
             :policy policy
             :resume-command `(resume-work-item ,(work-item-id work-item))))
      (:quarantined
       (list :type :operator-review
             :resume-command `(resume-work-item ,(work-item-id work-item))
             :reason reason))
      (:resumed
       (list :type :continue-transaction
             :suggested-step :run-live-and-cold-validation))
      (:awaiting-cold-validation
       (list :type :complete-pending-validations
             :suggested-step :run-cold-validation
             :final-closure-decision (work-item-closure-decision work-item)))
      (:failed
       (list :type :review-failure
             :suggested-step :quarantine-or-rollback))
      (otherwise nil))))

(defun derived-work-item-resume-payload (session work-item)
  (let* ((transaction (current-work-item-transaction work-item))
         (checkpoint-id (latest-work-item-checkpoint-id work-item))
         (replay-id (and transaction
                         (mutation-transaction-replay-id transaction)))
         (rollback-point (work-item-rollback-point work-item))
         (pending-validations (work-item-pending-validation-kinds work-item))
         (validator-actions (work-item-validator-actions work-item))
         (policy (latest-work-item-approval-policy session work-item))
         (reason (latest-work-item-approval-reason session work-item))
         (quarantine-reason (or (and (work-item-workflow-record session work-item)
                                     (workflow-record-quarantine-reason
                                      (work-item-workflow-record session work-item)))
                                reason)))
    (case (work-item-status work-item)
      (:awaiting-approval
       (list :resume-command `(resume-work-item ,(work-item-id work-item))
             :rollback-point rollback-point
             :checkpoint-id checkpoint-id
             :pending-validations pending-validations
             :validator-actions validator-actions
             :replay-id replay-id
             :approval-policy policy))
      (:quarantined
       (list :resume-command `(resume-work-item ,(work-item-id work-item))
             :rollback-point rollback-point
             :checkpoint-id checkpoint-id
             :validator-actions validator-actions
             :replay-id replay-id
             :quarantine-reason quarantine-reason
             :operator-options '(:resume :rollback)))
      (:resumed
       (list :resume-command :continue-transaction
             :checkpoint-id checkpoint-id
             :pending-validations pending-validations
             :validator-actions validator-actions
             :replay-id replay-id))
      (:awaiting-cold-validation
       (list :resume-command :complete-validations
             :checkpoint-id checkpoint-id
             :pending pending-validations
             :validator-actions validator-actions
             :replay-id replay-id
             :rollback-point rollback-point
             :final-closure-decision (work-item-closure-decision work-item)))
      (:failed
       (list :resume-command :quarantine-or-rollback
             :checkpoint-id checkpoint-id
             :replay-id replay-id))
      (otherwise nil))))

(defun recover-work-item-control-state (session work-item
                                        &key (recovery-origin :session-load))
  (let* ((record (work-item-workflow-record session work-item))
         (status (work-item-status work-item))
         (record-next-action (and record
                                  (copy-tree (workflow-record-next-action record))))
         (record-resume-payload (and record
                                     (copy-tree (workflow-record-resume-payload record))))
         (recovered-next-action nil)
         (recovered-resume-payload nil)
         (replay-class nil))
    (refresh-work-item-pending-validations session work-item)
    (when (null (work-item-next-action work-item))
      (setf recovered-next-action
            (or record-next-action
                (derived-work-item-next-action session work-item)))
      (when recovered-next-action
        (set-work-item-next-action session work-item (copy-tree recovered-next-action))))
    (when (null (work-item-resume-payload work-item))
      (setf recovered-resume-payload
            (or record-resume-payload
                (derived-work-item-resume-payload session work-item)))
      (when recovered-resume-payload
        (set-work-item-resume-payload session work-item
                                      (copy-tree recovered-resume-payload))))
    (setf replay-class
          (case status
            (:awaiting-approval :approval-resume)
            (:awaiting-cold-validation :validation-replay)
            (:failed :rollback-replay)
            (:quarantined :operator-review-replay)
            (:resumed :workflow-resume)
            (otherwise :state-restoration)))
    (when (and record
               (or recovered-next-action
                   recovered-resume-payload))
      (append-workflow-record-entry
       session
       record
       :recovery
       :control-state-recovered
       (list :recovery-origin recovery-origin
             :replay-class replay-class
             :work-item-id (work-item-id work-item)
             :work-item-status status
             :recovered-next-action-p (not (null recovered-next-action))
             :recovered-resume-payload-p (not (null recovered-resume-payload)))
       :status (workflow-record-status record))
      (append-workflow-record-event
       session
       :workflow-record-control-state-recovered
       record
       (list :recovery-origin recovery-origin
             :replay-class replay-class
             :work-item-id (work-item-id work-item)
             :work-item-status status
             :recovered-next-action-p (not (null recovered-next-action))
             :recovered-resume-payload-p (not (null recovered-resume-payload)))
       :metadata (list :recovery-origin recovery-origin
                       :replay-class replay-class)))
    work-item))

(defun work-item-final-closure-decision (work-item)
  (or (getf (work-item-resume-payload work-item) :final-closure-decision)
      (getf (work-item-next-action work-item) :final-closure-decision)))

(defun finalize-work-item-cold-validation (session work-item &key final-closure-decision)
  (let ((final-closure-decision (or final-closure-decision
                                    (work-item-final-closure-decision work-item)))
        (record (work-item-workflow-record session work-item))
        (transaction (current-work-item-transaction work-item))
        (cold (work-item-cold-validation-result work-item)))
    (when (and final-closure-decision
               (null (work-item-pending-validations work-item))
               cold)
      (if (validation-result-passed-p cold)
          (progn
            (when transaction
              (setf (mutation-transaction-state transaction) :committed
                    (mutation-transaction-rollback-status transaction) :not-needed
                    (mutation-transaction-rollback-detail transaction)
                    (list :reason :cold-validation-passed
                          :checkpoint-id (latest-work-item-checkpoint-id work-item))))
            (setf (work-item-status work-item) :committed
                  (work-item-closure-decision work-item) final-closure-decision
                  (work-item-updated-at work-item) (get-universal-time))
            (set-work-item-next-action session work-item nil)
            (set-work-item-resume-payload session work-item nil)
            (append-work-item-workflow-entry session
                                             work-item
                                             :validate
                                             :cold-validation-committed
                                             (list :closure-decision final-closure-decision
                                                   :checkpoint-id (latest-work-item-checkpoint-id work-item))
                                             :status :committed)
            (when record
              (close-workflow-record session
                                     record
                                     (list :work-item-status :committed
                                           :closure-decision final-closure-decision
                                           :rollback-point (work-item-rollback-point work-item)
                                           :reconciliation (reconciliation-record-view
                                                            (work-item-reconciliation-result work-item)))
                                     :status :committed
                                     :evidence (work-item-summary work-item))))
          (progn
            (when transaction
              (setf (mutation-transaction-rollback-status transaction) :required
                    (mutation-transaction-rollback-detail transaction)
                    (list :reason :cold-validation-failed
                          :checkpoint-id (latest-work-item-checkpoint-id work-item))))
            (setf (work-item-status work-item) :quarantined
                  (work-item-closure-decision work-item) :cold-validation-failed
                  (work-item-updated-at work-item) (get-universal-time))
            (set-work-item-next-action session work-item
                                       (list :type :operator-review
                                             :suggested-step :reconcile-or-rollback
                                             :final-closure-decision final-closure-decision))
            (set-work-item-resume-payload session work-item
                                          (list :resume-command :review-cold-validation
                                                :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                                :final-closure-decision final-closure-decision
                                                :replay-id (and transaction
                                                                (mutation-transaction-replay-id transaction))
                                                :operator-options '(:resume :rollback)))
            (append-work-item-workflow-entry session
                                             work-item
                                             :validate
                                             :cold-validation-failed
                                             (list :closure-decision final-closure-decision
                                                   :checkpoint-id (latest-work-item-checkpoint-id work-item))
                                             :status :quarantined)
            (when record
              (setf (workflow-record-status record) :quarantined
                    (workflow-record-waiting-on record) :operator-review
                    (workflow-record-quarantine-reason record)
                    "Cold validation failed after governed runtime mutation."
                    (workflow-record-updated-at record) (get-universal-time))))))
    work-item))

(defun work-item-wait-report (session work-item)
  (let* ((record (work-item-workflow-record session work-item))
         (pending (refresh-work-item-pending-validations session work-item))
         (waiting-on (and record (workflow-record-waiting-on record)))
         (reason (cond
                   ((eq waiting-on :approval) :approval-required)
                   ((eq waiting-on :operator-review) :operator-review-required)
                   ((eq (work-item-status work-item) :awaiting-cold-validation)
                    :cold-validation-required)
                   ((equal pending '(:cold))
                    :cold-validation-required)
                   ((null pending) :ready)
                   (t :pending-validation))))
    (list :work-item-id (work-item-id work-item)
          :status (work-item-status work-item)
          :waiting-on waiting-on
          :why reason
          :pending-validations pending
          :next-action (or (work-item-next-action work-item)
                           (and record (workflow-record-next-action record)))
          :resume-payload (or (work-item-resume-payload work-item)
                              (and record (workflow-record-resume-payload record)))
          :validator-tasks (mapcar #'validator-task-record-summary (work-item-validator-tasks work-item))
          :approval-requirements (and record (workflow-record-approval-requirements record))
          :quarantine-reason (and record (workflow-record-quarantine-reason record))
          :resume-count (and record (workflow-record-resume-count record))
          :workflow-record-ref (work-item-workflow-record-ref work-item))))

(defun mirror-work-item-operator-intervention (work-item intervention)
  (setf (provenance-record-operator-interventions (work-item-provenance work-item))
        (append (provenance-record-operator-interventions (work-item-provenance work-item))
                (list intervention))
        (work-item-updated-at work-item) (get-universal-time))
  intervention)

(defun append-work-item-operator-intervention (session work-item kind payload &key status)
  (let ((record (work-item-workflow-record session work-item)))
    (when record
      (mirror-work-item-operator-intervention
       work-item
       (record-operator-intervention session record kind payload :status status)))))

(defun ensure-work-item-approval-checkpoint (session work-item policy &key reason)
  (or (latest-work-item-checkpoint work-item)
      (append-work-item-checkpoint
       session
       work-item
       :validation-baseline (list :approval-requested-p t
                                  :policy policy
                                  :reason reason
                                  :work-item-id (work-item-id work-item)))))

(defun request-work-item-approval (session work-item policy &key reason)
  (let ((record (work-item-workflow-record session work-item)))
    (unless record
      (error "Work-item ~A has no workflow record" (work-item-id work-item)))
    (ensure-work-item-approval-checkpoint session work-item policy :reason reason)
    (let ((requirement (mark-workflow-record-awaiting-approval session record policy :reason reason)))
      (setf (provenance-record-approval-checkpoints (work-item-provenance work-item))
            (append (provenance-record-approval-checkpoints (work-item-provenance work-item))
                    (list requirement))
            (work-item-status work-item) :awaiting-approval
            (work-item-updated-at work-item) (get-universal-time))
      (mirror-work-item-operator-intervention
       work-item
       (list :kind :approval-requested
             :timestamp (get-universal-time)
             :payload requirement))
      (set-work-item-next-action session work-item
                                 (list :type :await-approval
                                       :policy policy
                                       :resume-command `(resume-work-item ,(work-item-id work-item))))
      (set-work-item-resume-payload session work-item
                                    (list :resume-command `(resume-work-item ,(work-item-id work-item))
                                          :rollback-point (work-item-rollback-point work-item)
                                          :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                          :pending-validations (work-item-pending-validation-kinds work-item)
                                          :validator-actions (work-item-validator-actions work-item)
                                          :replay-id (mutation-transaction-replay-id (current-work-item-transaction work-item))
                                          :approval-policy policy))
      (refresh-work-item-pending-validations session work-item)
      requirement)))

(defun quarantine-work-item (session work-item reason &key evidence)
  (let ((record (work-item-workflow-record session work-item)))
    (unless record
      (error "Work-item ~A has no workflow record" (work-item-id work-item)))
    (quarantine-workflow-record session record reason :evidence evidence)
    (let ((transaction (current-work-item-transaction work-item)))
      (when transaction
        (setf (mutation-transaction-quarantine-status transaction) :quarantined)))
    (mirror-work-item-operator-intervention
     work-item
     (list :kind :quarantined
           :timestamp (get-universal-time)
           :payload reason))
    (setf (work-item-status work-item) :quarantined
          (work-item-updated-at work-item) (get-universal-time))
    (set-work-item-next-action session work-item
                               (list :type :operator-review
                                     :resume-command `(resume-work-item ,(work-item-id work-item))
                                     :reason reason))
    (set-work-item-resume-payload session work-item
                                  (list :resume-command `(resume-work-item ,(work-item-id work-item))
                                        :rollback-point (work-item-rollback-point work-item)
                                        :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                        :validator-actions (work-item-validator-actions work-item)
                                        :replay-id (mutation-transaction-replay-id (current-work-item-transaction work-item))
                                        :quarantine-reason reason
                                        :operator-options '(:resume :rollback)))
    (refresh-work-item-taint-state work-item)
    (refresh-work-item-pending-validations session work-item)
    work-item))

(defun resume-work-item (session work-item &key note)
  (let ((record (work-item-workflow-record session work-item)))
    (unless record
      (error "Work-item ~A has no workflow record" (work-item-id work-item)))
    (resume-workflow-record session record :note note)
    (let ((transaction (current-work-item-transaction work-item)))
      (when transaction
        (setf (mutation-transaction-quarantine-status transaction) nil)))
    (mirror-work-item-operator-intervention
     work-item
     (list :kind :resumed
           :timestamp (get-universal-time)
           :payload (or note :resume-requested)))
    (setf (work-item-status work-item) :resumed
          (work-item-updated-at work-item) (get-universal-time))
    (set-work-item-next-action session work-item
                               (list :type :continue-transaction
                                     :note note
                                     :suggested-step :run-live-and-cold-validation))
    (set-work-item-resume-payload session work-item
                                  (list :resume-command :continue-transaction
                                        :note note
                                        :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                        :pending-validations (work-item-pending-validation-kinds work-item)
                                        :validator-actions (work-item-validator-actions work-item)
                                        :replay-id (mutation-transaction-replay-id (current-work-item-transaction work-item))))
    (refresh-work-item-taint-state work-item)
    (refresh-work-item-pending-validations session work-item)
    work-item))

(defun rollback-work-item (session work-item &key reason note)
  (let ((record (work-item-workflow-record session work-item)))
    (unless record
      (error "Work-item ~A has no workflow record" (work-item-id work-item)))
    (let ((transaction (current-work-item-transaction work-item))
          (rollback-point (work-item-rollback-point work-item)))
      (unless transaction
        (error "Work-item ~A has no active transaction to roll back" (work-item-id work-item)))
      (unless rollback-point
        (error "Work-item ~A has no rollback point" (work-item-id work-item)))
      (setf (mutation-transaction-state transaction) :rolled-back
            (mutation-transaction-rollback-status transaction) :rolled-back
            (mutation-transaction-rollback-detail transaction)
            (list :reason reason
                  :note note
                  :rollback-point rollback-point
                  :operator-triggered-p t)
            (mutation-transaction-quarantine-status transaction) nil)
      (mirror-work-item-operator-intervention
       work-item
       (list :kind :rolled-back
             :timestamp (get-universal-time)
             :payload (list :reason reason
                            :note note
                            :rollback-point rollback-point)))
      (setf (work-item-status work-item) :rolled-back
            (work-item-closure-decision work-item) :rolled-back-by-operator
            (work-item-updated-at work-item) (get-universal-time))
      (set-work-item-next-action session work-item nil)
      (set-work-item-resume-payload session work-item nil)
      (append-work-item-workflow-entry session
                                       work-item
                                       :reconcile
                                       :operator-rolled-back
                                       (list :reason reason
                                             :note note
                                             :rollback-point rollback-point)
                                       :status :rolled-back)
      (append-work-item-runtime-observation session
                                            work-item
                                            :rollback-completed
                                            (list :reason reason
                                                  :note note
                                                  :rollback-point rollback-point
                                                  :transaction-id (mutation-transaction-id transaction)))
      (close-workflow-record session
                             record
                             (list :work-item-status :rolled-back
                                   :closure-decision :rolled-back-by-operator
                                   :rollback-point rollback-point)
                             :status :rolled-back
                             :evidence (work-item-summary work-item))
      (refresh-work-item-taint-state work-item)
      (refresh-work-item-pending-validations session work-item)
      work-item)))

(defun steer-work-item-plan (session work-item &key phase next-step note)
  (let* ((directive (list :phase phase
                          :next-step next-step
                          :note note
                          :timestamp (get-universal-time)))
         (record (work-item-workflow-record session work-item)))
    (append-work-item-operator-steering-history work-item directive)
    (append-work-item-operator-intervention session
                                           work-item
                                           :plan-steered
                                           directive
                                           :status (work-item-status work-item))
    (when record
      (append-workflow-record-entry session
                                    record
                                    :plan
                                    :operator-plan-steered
                                    directive
                                    :status (workflow-record-status record)))
    (set-work-item-next-action session work-item
                               (append (list :type :operator-steered
                                             :phase phase
                                             :suggested-step next-step)
                                       (when note
                                         (list :note note))))
    (set-work-item-resume-payload session work-item
                                  (append (list :resume-command :operator-steered
                                                :phase phase
                                                :next-step next-step
                                                :checkpoint-id (latest-work-item-checkpoint-id work-item))
                                          (when note
                                            (list :note note))))
    work-item))

(defun find-work-item-transaction (work-item transaction-id)
  (find transaction-id (work-item-transactions work-item)
        :key #'mutation-transaction-id :test #'string=))

(defun current-work-item-transaction (work-item)
  (first (last (work-item-transactions work-item))))

(defun make-live-validation-result (status evidence &key tainted-p)
  (make-validation-result :kind :live
                          :status status
                          :executed-at (get-universal-time)
                          :evidence evidence
                          :tainted-p tainted-p))

(defun make-cold-validation-result (status evidence &key tainted-p)
  (make-validation-result :kind :cold
                          :status status
                          :executed-at (get-universal-time)
                          :evidence evidence
                          :tainted-p tainted-p))

(defun validation-result-passed-p (result)
  (and result (eq (validation-result-status result) :passed)))

(defun work-item-taint-reasons (work-item)
  (let* ((transaction (current-work-item-transaction work-item))
         (live (work-item-live-validation-result work-item))
         (cold (work-item-cold-validation-result work-item))
         (status (work-item-status work-item))
         (reasons '()))
    (when (and transaction
               (member status '(:mutating :failed :rolled-back :quarantined) :test #'eq))
      (push :live-image-mutated reasons))
    (when (and transaction
               (plusp (length (mutation-transaction-image-mutations transaction)))
               (not (validation-result-passed-p cold)))
      (push :image-state-not-reproduced reasons))
    (when (and transaction
               (eq (mutation-transaction-rollback-status transaction) :required))
      (push :rollback-required reasons))
    (when (eq status :failed)
      (push :task-failed reasons))
    (when (eq status :rolled-back)
      (push :rollback-state reasons))
    (when (eq status :quarantined)
      (push :quarantined-state reasons))
    (when (and live cold
               (not (eq (validation-result-status live)
                        (validation-result-status cold))))
      (push :validation-diverged reasons))
    (nreverse (remove-duplicates reasons :test #'eq))))

(defun refresh-work-item-taint-state (work-item)
  (let ((reasons (work-item-taint-reasons work-item)))
    (setf (work-item-taint-status work-item) (if reasons :tainted :clean)
          (provenance-record-taint-status (work-item-provenance work-item)) (if reasons :tainted :clean)
          (provenance-record-taint-reasons (work-item-provenance work-item)) reasons)
    reasons))

(defun work-item-mutation-block-reasons (work-item)
  (let ((status (work-item-status work-item))
        (transaction (current-work-item-transaction work-item))
        (reasons '()))
    (when (eq status :awaiting-approval)
      (push :awaiting-approval reasons))
    (when (eq status :quarantined)
      (push :quarantined reasons))
    (when (eq status :rolled-back)
      (push :rolled-back reasons))
    (when (eq status :awaiting-cold-validation)
      (push :awaiting-cold-validation reasons))
    (when (and transaction
               (eq (mutation-transaction-rollback-status transaction) :required))
      (push :rollback-required reasons))
    (nreverse (remove-duplicates reasons :test #'eq))))

(defun reconciliation-summary-message (status taint-reasons)
  (let ((base (case status
                (:durable "Live and cold validation both passed.")
                (:tainted-durable "Live and cold validation both passed, but the result is still tainted by image state.")
                (:live-only "Live validation passed but cold validation failed.")
                (:tainted-live-only "Live validation passed but cold validation failed, and the result remains tainted by image state.")
                (:cold-only "Cold validation passed but live validation failed.")
                (:failed "Live and cold validation both failed.")
                (t "Validation is incomplete."))))
    (if taint-reasons
        (format nil "~A Taint reasons: ~{~A~^, ~}." base taint-reasons)
        base)))

(defun reconcile-validation-results (work-item)
  (let* ((live (work-item-live-validation-result work-item))
         (cold (work-item-cold-validation-result work-item))
         (live-status (and live (validation-result-status live)))
         (cold-status (and cold (validation-result-status cold)))
         (taint-reasons (refresh-work-item-taint-state work-item))
         (tainted-p (not (null taint-reasons)))
         (summary (cond
                    ((and (eq live-status :passed) (eq cold-status :passed) tainted-p)
                     :tainted-durable)
                    ((and (eq live-status :passed) (eq cold-status :passed))
                     :durable)
                    ((and (eq live-status :passed) (eq cold-status :failed) tainted-p)
                     :tainted-live-only)
                    ((and (eq live-status :passed) (eq cold-status :failed))
                     :live-only)
                    ((and (eq live-status :failed) (eq cold-status :passed))
                     :cold-only)
                    ((and (eq live-status :failed) (eq cold-status :failed))
                     :failed)
                    (t :incomplete)))
         (reproducibility-status (cond
                                   ((eq cold-status :passed) :reproduced)
                                   ((eq cold-status :failed) :not-reproduced)
                                   (t :unknown))))
    (setf (work-item-reconciliation-result work-item)
          (make-reconciliation-record :status summary
                                      :recorded-at (get-universal-time)
                                      :summary (reconciliation-summary-message summary taint-reasons)
                                      :live-status live-status
                                      :cold-status cold-status
                                      :reproducibility-status reproducibility-status
                                      :taint-status (if tainted-p :tainted :clean)
                                      :taint-reasons taint-reasons))
    (work-item-reconciliation-result work-item)))

(defun mark-work-item-image-only (session work-item &key reason)
  (let ((transaction (current-work-item-transaction work-item)))
    (when transaction
      (setf (mutation-transaction-state transaction) :image-only))
    (setf (work-item-status work-item) :image-only
          (work-item-closure-decision work-item) :committed-to-image-only
          (work-item-updated-at work-item) (get-universal-time))
    (refresh-work-item-taint-state work-item)
    (refresh-work-item-pending-validations session work-item)
    (set-work-item-next-action session work-item nil)
    (set-work-item-resume-payload session work-item
                                  (list :resume-command :reconcile-image-only
                                        :replay-id (and transaction (mutation-transaction-replay-id transaction))
                                        :reason reason))
    (append-work-item-workflow-entry session work-item
                                     :reconcile
                                     :image-only-commit
                                     (list :reason reason
                                           :replay-id (and transaction (mutation-transaction-replay-id transaction)))
                                     :status :image-only)
    (let ((record (work-item-workflow-record session work-item)))
      (when record
        (close-workflow-record session
                               record
                               (list :work-item-status :image-only
                                     :closure-decision :committed-to-image-only
                                     :reason reason)
                               :status :image-only
                               :evidence (work-item-summary work-item))))
    work-item))

(defun update-work-item-validation-results (session work-item live-status live-evidence cold-status cold-evidence)
  (refresh-work-item-taint-state work-item)
  (setf (work-item-live-validation-result work-item)
        (make-live-validation-result live-status live-evidence
                                     :tainted-p (eq (work-item-taint-status work-item) :tainted))
        (work-item-cold-validation-result work-item)
        (make-cold-validation-result cold-status cold-evidence)
        (work-item-updated-at work-item) (get-universal-time)
        (provenance-record-validation-outputs (work-item-provenance work-item))
        (list (validation-result-summary (work-item-live-validation-result work-item))
              (validation-result-summary (work-item-cold-validation-result work-item))))
  (refresh-work-item-pending-validations session work-item)
  (set-work-item-next-action session work-item
                             (if (null (work-item-pending-validations work-item))
                                 nil
                                 (list :type :complete-pending-validations
                                       :pending (work-item-pending-validations work-item))))
  (set-work-item-resume-payload session work-item
                                (if (null (work-item-pending-validations work-item))
                                    nil
                                    (list :resume-command :complete-validations
                                          :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                          :pending (work-item-pending-validations work-item)
                                          :validator-actions (work-item-validator-actions work-item)
                                          :replay-id (mutation-transaction-replay-id (current-work-item-transaction work-item))
                                          :rollback-point (work-item-rollback-point work-item))))
  (reconcile-validation-results work-item)
  (append-work-item-workflow-entry session work-item
                                   :validate
                                   :validation-results
                                   (list :live (validation-result-summary (work-item-live-validation-result work-item))
                                         :cold (validation-result-summary (work-item-cold-validation-result work-item))
                                         :reconciliation (reconciliation-record-view (work-item-reconciliation-result work-item)))
                                   :status :validating)
  (append-session-event session
                        :validation-completed
                        (list :work-item-id (work-item-id work-item)
                              :live (validation-result-summary (work-item-live-validation-result work-item))
                              :cold (validation-result-summary (work-item-cold-validation-result work-item)))
                        :family :workflow
                        :entity-id (work-item-id work-item)
                        :metadata (list :workflow-record-id (work-item-workflow-record-ref work-item)
                                        :reconciliation (reconciliation-record-view (work-item-reconciliation-result work-item)))
                        :work-item-id (work-item-id work-item))
  (append-session-event session
                        :reconciliation-created
                        (reconciliation-record-view (work-item-reconciliation-result work-item))
                        :family :workflow
                        :entity-id (work-item-id work-item)
                        :metadata (list :workflow-record-id (work-item-workflow-record-ref work-item))
                        :work-item-id (work-item-id work-item))
  work-item)

(defun create-work-item (session goal &key mutation-intent transaction-scope workflow-record-ref)
  (let* ((id (make-work-item-id))
         (source-snapshot (capture-work-item-source-snapshot session))
         (image-snapshot-ref (capture-work-item-image-snapshot-reference session))
         (transaction (make-work-item-transaction id :scope transaction-scope))
         (workflow-record (or (and workflow-record-ref
                                   (find-workflow-record session workflow-record-ref))
                              (create-workflow-record session
                                                      goal
                                                      :work-item-id id
                                                      :initial-phase :inspect
                                                      :initial-kind :source-and-image-snapshots
                                                      :initial-payload (list :source-snapshot source-snapshot
                                                                             :image-snapshot-ref image-snapshot-ref))))
         (work-item (make-work-item
                     :id id
                     :goal goal
                     :status :created
                     :created-at (get-universal-time)
                     :updated-at (get-universal-time)
                     :source-snapshot source-snapshot
                     :image-snapshot-ref image-snapshot-ref
                     :workflow-record-ref (and workflow-record (workflow-record-id workflow-record))
                     :introspection-evidence '()
                     :mutation-intent mutation-intent
                     :runtime-observations '()
                     :live-validation-result nil
                     :cold-validation-result nil
                     :pending-validations '(:live :cold)
                     :validator-tasks '()
                     :next-action (list :type :capture-checkpoint-and-validate
                                        :suggested-step :checkpoint)
                     :resume-payload (list :resume-command :start-work-item
                                           :checkpoint-id nil
                                           :pending '(:live :cold)
                                           :validator-actions '()
                                           :replay-id (mutation-transaction-replay-id transaction))
                     :image-reconciliation nil
                     :reconciliation-result nil
                     :rollback-point (list :transaction-id (mutation-transaction-id transaction)
                                           :rollback-status :not-started)
                     :taint-status :clean
                     :closure-decision nil
                     :transaction-ids (list (mutation-transaction-id transaction))
                     :transactions (list transaction)
                     :checkpoints '()
                     :provenance (make-initial-provenance-record source-snapshot image-snapshot-ref))))
    (multiple-value-bind (work-items tail)
        (append-linked-item (agent-session-work-items session)
                            (agent-session-work-items-tail session)
                            work-item)
      (setf (agent-session-work-items session) work-items
            (agent-session-work-items-tail session) tail))
    (when workflow-record
      (create-trace-link session
                         :relation :tracked-in-workflow-record
                         :source-kind :work-item
                         :source-id (work-item-id work-item)
                         :target-kind :workflow-record
                         :target-id (workflow-record-id workflow-record)
                         :metadata (list :goal goal)))
    (let ((environment (session-bound-environment session)))
      (when environment
        (environment-append-work-item environment session work-item)))
    (append-work-item-workflow-entry session work-item :inspect :work-item-created (work-item-summary work-item) :status :open)
    (refresh-work-item-pending-validations session work-item)
    (append-session-event session
                          :work-item-created
                          (work-item-summary work-item)
                          :family :workflow
                          :entity-id (work-item-id work-item)
                          :metadata (list :workflow-record-id (work-item-workflow-record-ref work-item))
                          :work-item-id (work-item-id work-item))
    work-item))

(defun create-work-item-for-task (session task &key mutation-intent)
  (create-work-item session
                    (format nil "Execute task ~A (~A)" (task-id task) (task-kind task))
                    :mutation-intent (or mutation-intent
                                         (list :task-id (task-id task)
                                               :command-kind (task-kind task)
                                               :payload (task-payload task)
                                               :orchestration-group-id (task-orchestration-group-id task)
                                               :ownership-scope (task-ownership-scope task)
                                               :merge-policy (task-merge-policy task)
                                               :shared-context (task-shared-context task)))
                    :transaction-scope :task))

(defun append-work-item-runtime-observation (session work-item kind payload)
  (let ((event (make-event-now kind payload)))
    (setf (work-item-runtime-observations work-item)
          (append (work-item-runtime-observations work-item) (list event))
          (work-item-updated-at work-item) (get-universal-time)
          (provenance-record-runtime-observations (work-item-provenance work-item))
          (append (provenance-record-runtime-observations (work-item-provenance work-item))
                  (list event)))
    (append-work-item-workflow-entry session work-item :observe-runtime kind payload :status :in-progress)
    event))

(defun append-work-item-checkpoint (session work-item &key validation-baseline)
  (let ((checkpoint (make-checkpoint-record
                     :id (make-checkpoint-id)
                     :captured-at (get-universal-time)
                     :source-snapshot (capture-work-item-source-snapshot session)
                     :image-snapshot-ref (capture-work-item-image-snapshot-reference session)
                     :worker-summaries (list-worker-summaries session)
                     :validation-baseline (or validation-baseline
                                              (list :event-count (length (agent-session-events session))
                                                    :task-count (length (agent-session-tasks session)))))))
    (setf (work-item-checkpoints work-item)
          (append (work-item-checkpoints work-item) (list checkpoint))
          (work-item-updated-at work-item) (get-universal-time)
          (provenance-record-rollback-availability (work-item-provenance work-item)) :captured)
    (let ((transaction (current-work-item-transaction work-item)))
      (when transaction
        (setf (mutation-transaction-checkpoint-id transaction) (checkpoint-record-id checkpoint)
              (mutation-transaction-state transaction) :checkpointed
              (mutation-transaction-rollback-status transaction) :captured
              (mutation-transaction-rollback-detail transaction)
              (list :checkpoint-id (checkpoint-record-id checkpoint)
                    :restorable-p nil))))
    (append-work-item-workflow-entry session work-item :checkpoint :checkpoint-created (checkpoint-summary checkpoint) :status :checkpointed)
    (refresh-work-item-pending-validations session work-item)
    (set-work-item-resume-payload session work-item
                                  (list :resume-command :run-task
                                        :checkpoint-id (checkpoint-record-id checkpoint)
                                        :replay-id (mutation-transaction-replay-id (current-work-item-transaction work-item))
                                        :rollback-point (work-item-rollback-point work-item)
                                        :validator-actions (work-item-validator-actions work-item)))
    (append-work-item-runtime-observation session work-item :checkpoint-created (checkpoint-summary checkpoint))
    checkpoint))

(defun update-work-item-status-from-task (session task status &key closure-decision error)
  (let ((work-item (and (task-work-item-id task)
                        (find-work-item session (task-work-item-id task)))))
    (when work-item
      (let ((transaction (current-work-item-transaction work-item)))
        (when transaction
          (setf (mutation-transaction-state transaction)
                (case status
                  (:planned (if (mutation-transaction-checkpoint-id transaction)
                                (mutation-transaction-state transaction)
                                :planned))
                  (:checkpointed :checkpointed)
                  (:mutating :mutating)
                  (:committed :committed)
                  (:rolled-back :rolled-back)
                  (:failed :failed)
                  (t (or (mutation-transaction-state transaction) :created)))
                (mutation-transaction-rollback-status transaction)
                (case status
                  (:rolled-back :rolled-back)
                  (:failed :required)
                  (:committed :not-needed)
                  (:quarantined :required)
                  (t (mutation-transaction-rollback-status transaction)))
                (mutation-transaction-rollback-detail transaction)
                (case status
                  (:failed (list :reason error :recommended-action :rollback-or-quarantine))
                  (:rolled-back (list :reason :cancelled :restored-p nil))
                  (:quarantined (list :reason error :recommended-action :operator-review))
                  (:committed (list :reason :commit-succeeded))
                  (t (mutation-transaction-rollback-detail transaction)))))
        (setf (work-item-status work-item) status
              (work-item-updated-at work-item) (get-universal-time)
              (work-item-closure-decision work-item) closure-decision
              (work-item-rollback-point work-item)
              (list :transaction-id (first (last (work-item-transaction-ids work-item)))
                    :rollback-status (if (member status '(:rolled-back :failed) :test #'eq)
                                         :available
                                         :captured))
              (provenance-record-rollback-availability (work-item-provenance work-item))
              (if (member status '(:rolled-back :failed) :test #'eq) :available :captured))
        (refresh-work-item-taint-state work-item)
        (refresh-work-item-pending-validations session work-item)
        (set-work-item-next-action session work-item
                                   (case status
                                     (:planned (list :type :checkpoint :suggested-step :checkpoint))
                                     (:checkpointed (list :type :mutate :suggested-step :run-task))
                                     (:mutating (list :type :observe-runtime :suggested-step :await-runtime-effects))
                                     (:committed nil)
                                     (:failed (list :type :review-failure :suggested-step :quarantine-or-rollback))
                                     (:rolled-back nil)
                                     (:quarantined (list :type :operator-review :suggested-step :resume-or-rollback))
                                     (t (work-item-next-action work-item))))
        (set-work-item-resume-payload session work-item
                                      (case status
                                        (:planned (list :resume-command :checkpoint
                                                        :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                                        :replay-id (mutation-transaction-replay-id transaction)
                                                        :rollback-point (work-item-rollback-point work-item)))
                                        (:checkpointed (list :resume-command :run-task
                                                             :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                                             :replay-id (mutation-transaction-replay-id transaction)
                                                             :checkpoint-count (length (work-item-checkpoints work-item))))
                                        (:mutating (list :resume-command :observe-runtime
                                                         :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                                         :replay-id (mutation-transaction-replay-id transaction)
                                                         :transaction-id (first (last (work-item-transaction-ids work-item)))))
                                        (:committed nil)
                                        (:rolled-back nil)
                                        (:failed (list :resume-command :quarantine-or-rollback
                                                       :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                                       :replay-id (mutation-transaction-replay-id transaction)
                                                       :error error))
                                        (:quarantined (work-item-resume-payload work-item))
                                        (t (work-item-resume-payload work-item))))
        (append-work-item-runtime-observation
         session
         work-item
         :task-state
         (list :task-id (task-id task)
               :task-status (task-status task)
               :work-item-status status
               :error error))
        (append-work-item-workflow-entry session work-item :reconcile :task-status-transition
                                         (list :task-id (task-id task)
                                               :status status
                                               :closure-decision closure-decision
                                               :error error)
                                         :status (case status
                                                   (:planned :planned)
                                                   (:mutating :in-progress)
                                                   (:committed :ready-to-close)
                                                   (:failed :requires-review)
                                                   (:rolled-back :rolled-back)
                                                   (t :open)))
        (when (member status '(:committed :failed :rolled-back) :test #'eq)
          (update-work-item-validation-results
           session
           work-item
           (if (eq status :committed) :passed :failed)
           (list :task-id (task-id task)
                 :status status
                 :event-count (length (task-progress-events task)))
           (if (eq status :committed) :passed :failed)
           (list :task-id (task-id task)
                 :status status
                 :requires-fresh-run-p t))
          (let ((record (work-item-workflow-record session work-item)))
            (when record
              (close-workflow-record session
                                     record
                                     (list :work-item-status status
                                           :closure-decision closure-decision
                                           :rollback-point (work-item-rollback-point work-item)
                                           :reconciliation (reconciliation-record-view (work-item-reconciliation-result work-item)))
                                     :status (case status
                                               (:committed :committed)
                                               (:failed :quarantined)
                                               (:rolled-back :rolled-back)
                                               (t :closed))
                                                 :evidence (work-item-summary work-item)))))
      work-item))))

(defun operation-bound-work-item (session operation)
  (let ((work-item-id (getf (operation-metadata operation) :work-item-id)))
    (and work-item-id
         (find-work-item session work-item-id))))

(defun update-work-item-status-from-operation (session operation status
                                               &key closure-decision error result)
  (let ((work-item (operation-bound-work-item session operation)))
    (when work-item
      (let ((transaction (current-work-item-transaction work-item))
            (result-payload (and (listp result) (getf result :result)))
            (patch-results (and (listp (and (listp result) (getf result :result)))
                                (getf (getf result :result) :patch)))
            (policy-id (getf (operation-policy-decision operation) :policy-id)))
        (when transaction
          (setf (mutation-transaction-state transaction)
                (case status
                  (:planned (if (mutation-transaction-checkpoint-id transaction)
                                (mutation-transaction-state transaction)
                                :planned))
                  (:checkpointed :checkpointed)
                  (:mutating :mutating)
                  (:awaiting-cold-validation :committed)
                  (:committed :committed)
                  (:rolled-back :rolled-back)
                  (:failed :failed)
                  (t (or (mutation-transaction-state transaction) :created)))
                (mutation-transaction-rollback-status transaction)
                (case status
                  (:rolled-back :rolled-back)
                  (:failed :required)
                  (:awaiting-cold-validation :captured)
                  (:committed :not-needed)
                  (:quarantined :required)
                  (t (mutation-transaction-rollback-status transaction)))
                (mutation-transaction-rollback-detail transaction)
                (case status
                  (:failed (list :reason error :recommended-action :rollback-or-quarantine))
                  (:awaiting-cold-validation (list :reason :warm-image-validation-only
                                                   :recommended-action :run-cold-validation
                                                   :operation-id (operation-id operation)
                                                   :turn-id (operation-turn-id operation)))
                  (:rolled-back (list :reason :cancelled :restored-p nil))
                  (:quarantined (list :reason error :recommended-action :operator-review))
                  (:committed (list :reason :commit-succeeded
                                    :operation-id (operation-id operation)
                                    :turn-id (operation-turn-id operation)))
                  (t (mutation-transaction-rollback-detail transaction)))))
        (setf (work-item-status work-item) status
              (work-item-updated-at work-item) (get-universal-time)
              (work-item-closure-decision work-item) closure-decision
              (work-item-rollback-point work-item)
              (list :transaction-id (first (last (work-item-transaction-ids work-item)))
                    :rollback-status (if (member status '(:rolled-back :failed) :test #'eq)
                                         :available
                                         :captured))
              (provenance-record-rollback-availability (work-item-provenance work-item))
              (if (member status '(:rolled-back :failed) :test #'eq) :available :captured))
        (when (and patch-results (member status '(:mutating :committed) :test #'eq))
          (append-work-item-source-mutation
           work-item
           (list :kind :conversation-patch
                 :operation-id (operation-id operation)
                 :turn-id (operation-turn-id operation)
                 :result patch-results)
           session))
        (when (and (eq policy-id :git-write)
                   (member status '(:mutating :committed) :test #'eq))
          (append-work-item-source-mutation
           work-item
           (list :kind :conversation-tool-write
                 :operation-id (operation-id operation)
                 :turn-id (operation-turn-id operation)
                 :operation-name (operation-name operation)
                 :result result-payload)
           session))
        (when (and (eq policy-id :runtime-eval-mutate)
                   (member status '(:mutating :committed) :test #'eq))
          (append-work-item-image-mutation
           work-item
           (list :kind :conversation-runtime-mutation
                 :operation-id (operation-id operation)
                 :turn-id (operation-turn-id operation)
                 :operation-name (operation-name operation)
                 :result result-payload)
           session))
        (append-work-item-resource-effect
         work-item
         (list :kind :conversation-operation-result
               :operation-id (operation-id operation)
               :turn-id (operation-turn-id operation)
               :operation-name (operation-name operation)
               :policy-id policy-id
               :status status
               :result result-payload)
         session)
        (refresh-work-item-taint-state work-item)
        (refresh-work-item-pending-validations session work-item)
        (set-work-item-next-action session work-item
                                   (case status
                                     (:planned (list :type :checkpoint :suggested-step :checkpoint))
                                     (:checkpointed (list :type :mutate :suggested-step :resume-turn))
                                     (:mutating (list :type :observe-runtime :suggested-step :await-runtime-effects))
                                     (:awaiting-cold-validation (list :type :complete-pending-validations
                                                                      :suggested-step :run-cold-validation
                                                                      :final-closure-decision closure-decision))
                                     (:committed nil)
                                     (:failed (list :type :review-failure :suggested-step :quarantine-or-rollback))
                                     (:rolled-back nil)
                                     (:quarantined (list :type :operator-review :suggested-step :resume-or-rollback))
                                     (t (work-item-next-action work-item))))
        (set-work-item-resume-payload session work-item
                                      (case status
                                        (:planned (list :resume-command :checkpoint
                                                        :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                                        :replay-id (mutation-transaction-replay-id transaction)
                                                        :rollback-point (work-item-rollback-point work-item)))
                                        (:checkpointed (list :resume-command :turn/resume
                                                             :turn-id (operation-turn-id operation)
                                                             :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                                             :replay-id (mutation-transaction-replay-id transaction)))
                                        (:mutating (list :resume-command :observe-runtime
                                                         :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                                         :replay-id (mutation-transaction-replay-id transaction)
                                                         :operation-id (operation-id operation)))
                                        (:awaiting-cold-validation (list :resume-command :complete-validations
                                                                         :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                                                         :pending (work-item-pending-validations work-item)
                                                                         :validator-actions (work-item-validator-actions work-item)
                                                                         :replay-id (mutation-transaction-replay-id transaction)
                                                                         :operation-id (operation-id operation)
                                                                         :rollback-point (work-item-rollback-point work-item)
                                                                         :final-closure-decision closure-decision))
                                        (:committed nil)
                                        (:rolled-back nil)
                                        (:failed (list :resume-command :quarantine-or-rollback
                                                       :checkpoint-id (latest-work-item-checkpoint-id work-item)
                                                       :replay-id (mutation-transaction-replay-id transaction)
                                                       :error error))
                                        (:quarantined (work-item-resume-payload work-item))
                                        (t (work-item-resume-payload work-item))))
        (append-work-item-runtime-observation
         session
         work-item
         :conversation-operation-state
         (list :operation-id (operation-id operation)
               :turn-id (operation-turn-id operation)
               :operation-name (operation-name operation)
               :work-item-status status
               :error error))
        (append-work-item-workflow-entry session work-item :reconcile :conversation-operation-status-transition
                                         (list :operation-id (operation-id operation)
                                               :turn-id (operation-turn-id operation)
                                               :operation-name (operation-name operation)
                                               :status status
                                               :closure-decision closure-decision
                                               :error error)
                                         :status (case status
                                                   (:planned :planned)
                                                   (:mutating :in-progress)
                                                   (:awaiting-cold-validation :awaiting-cold-validation)
                                                   (:committed :ready-to-close)
                                                   (:failed :requires-review)
                                                   (:rolled-back :rolled-back)
                                                   (t :open)))
        (when (member status '(:committed :failed :rolled-back) :test #'eq)
          (update-work-item-validation-results
           session
           work-item
           (if (eq status :committed) :passed :failed)
           (list :operation-id (operation-id operation)
                 :status status
                 :result-summary result-payload)
           (if (eq status :committed) :passed :failed)
           (list :operation-id (operation-id operation)
                 :status status
                 :requires-fresh-run-p t))
          (let ((record (work-item-workflow-record session work-item)))
            (when record
              (close-workflow-record session
                                     record
                                     (list :work-item-status status
                                           :closure-decision closure-decision
                                           :rollback-point (work-item-rollback-point work-item)
                                           :reconciliation (reconciliation-record-view (work-item-reconciliation-result work-item))
                                           :operation-id (operation-id operation))
                                     :status (case status
                                               (:committed :committed)
                                               (:failed :quarantined)
                                               (:rolled-back :rolled-back)
                                               (t :closed))
                                     :evidence (work-item-summary work-item)))))
      work-item))))
