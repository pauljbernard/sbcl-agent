(in-package #:sbcl-agent)

(defstruct validation-result
  kind
  status
  executed-at
  evidence
  tainted-p)

(declaim (notinline validation-result-kind
                    validation-result-status
                    validation-result-executed-at
                    validation-result-evidence
                    validation-result-tainted-p))

(defstruct image-reconciliation-record
  recorded-at
  replay-id
  image-summary
  source-summary
  status)

(declaim (notinline image-reconciliation-record-recorded-at
                    image-reconciliation-record-replay-id
                    image-reconciliation-record-image-summary
                    image-reconciliation-record-source-summary
                    image-reconciliation-record-status))

(defstruct reconciliation-record
  status
  recorded-at
  summary
  live-status
  cold-status
  reproducibility-status
  taint-status
  taint-reasons)

(declaim (notinline reconciliation-record-status
                    reconciliation-record-recorded-at
                    reconciliation-record-summary
                    reconciliation-record-live-status
                    reconciliation-record-cold-status
                    reconciliation-record-reproducibility-status
                    reconciliation-record-taint-status
                    reconciliation-record-taint-reasons))

(defstruct checkpoint-record
  id
  captured-at
  source-snapshot
  image-snapshot-ref
  worker-summaries
  validation-baseline)

(declaim (notinline checkpoint-record-id
                    checkpoint-record-captured-at
                    checkpoint-record-source-snapshot
                    checkpoint-record-image-snapshot-ref
                    checkpoint-record-worker-summaries
                    checkpoint-record-validation-baseline))

(defstruct mutation-transaction
  id
  work-item-id
  replay-id
  scope
  checkpoint-id
  state
  lifecycle-phases
  source-mutations
  image-mutations
  resource-effects
  rollback-status
  rollback-detail
  quarantine-status)

(declaim (notinline mutation-transaction-id
                    mutation-transaction-work-item-id
                    mutation-transaction-replay-id
                    mutation-transaction-scope
                    mutation-transaction-checkpoint-id
                    mutation-transaction-state
                    mutation-transaction-lifecycle-phases
                    mutation-transaction-source-mutations
                    mutation-transaction-image-mutations
                    mutation-transaction-resource-effects
                    mutation-transaction-rollback-status
                    mutation-transaction-rollback-detail
                    mutation-transaction-quarantine-status))

(defstruct validator-task-record
  id
  replay-id
  kind
  checkpoint-id
  status
  resume-command
  created-at
  completed-at)

(declaim (notinline validator-task-record-id
                    validator-task-record-replay-id
                    validator-task-record-kind
                    validator-task-record-checkpoint-id
                    validator-task-record-status
                    validator-task-record-resume-command
                    validator-task-record-created-at
                    validator-task-record-completed-at))

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

(declaim (notinline provenance-record-source-hash
                    provenance-record-image-snapshot-id
                    provenance-record-introspection-queries
                    provenance-record-executed-mutations
                    provenance-record-before-after-map
                    provenance-record-runtime-observations
                    provenance-record-validation-outputs
                    provenance-record-final-source-diff
                    provenance-record-rollback-availability
                    provenance-record-taint-status
                    provenance-record-taint-reasons
                    provenance-record-approval-checkpoints
                    provenance-record-operator-interventions))

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

(declaim (notinline work-item-id
                    work-item-goal
                    work-item-status
                    work-item-created-at
                    work-item-updated-at
                    work-item-source-snapshot
                    work-item-image-snapshot-ref
                    work-item-workflow-record-ref
                    work-item-introspection-evidence
                    work-item-mutation-intent
                    work-item-runtime-observations
                    work-item-live-validation-result
                    work-item-cold-validation-result
                    work-item-pending-validations
                    work-item-validator-tasks
                    work-item-next-action
                    work-item-resume-payload
                    work-item-image-reconciliation
                    work-item-reconciliation-result
                    work-item-rollback-point
                    work-item-taint-status
                    work-item-closure-decision
                    work-item-transaction-ids
                    work-item-transactions
                    work-item-checkpoints
                    work-item-provenance))
