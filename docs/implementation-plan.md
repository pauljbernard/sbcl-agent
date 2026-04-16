---
layout: default
title: Implementation Plan
hero_title: Implementation Plan
hero_text: The roadmap prioritizes live-image transaction discipline first, then dual validation, governance, role isolation, and operator-grade hardening. Multi-agent sophistication comes after mutation safety, not before it.
eyebrow: Roadmap
permalink: /implementation-plan.html
description: Detailed implementation roadmap for sbcl-agent.
---
## North Star

`sbcl-agent` should achieve Codex-class functional outcomes for software engineering tasks while deliberately using a different architecture that exploits Common Lisp's differentiators.

The goal is not exact implementation parity.

The goal is:

- match or exceed Codex-like usefulness where operator outcomes matter
- diverge in mechanism where Lisp offers stronger introspection, mutation, rollback, and evidentiary control
- treat the running image as a first-class engineering substrate rather than a hidden execution detail

This means the system should eventually be able to do at least the following classes of work:

- inspect and understand source
- inspect and understand a live runtime image
- plan bounded engineering work
- mutate source intentionally
- mutate the live image intentionally
- validate both in-image and from cold start
- explain what it changed and why
- roll changes back safely when necessary
- support bounded multi-agent workflows
- preserve operator trust through provenance and review

## Design Mandate

The architecture must optimize for three explicit truths:

- source truth
- image truth
- workflow truth

Every meaningful work-item must answer:

- What changed in source?
- What changed in the running image?
- What evidence links the two?

Functional similarity to Codex is an external benchmark.

Transactional live-image discipline is the internal design rule.

## Program Structure

The implementation program is divided into nine major workstreams that are delivered across six execution stages.

### Core Workstreams

1. Work-item and transaction kernel
2. Source truth runtime
3. Image truth runtime
4. Checkpointing and rollback
5. Dual validation and reconciliation
6. Taint tracking and provenance
7. Runtime-governed skills
8. Role-isolated multi-agent supervision
9. Operator-grade review, replay, and hardening

### Execution Stages

1. Foundation realignment
2. Transactional kernel
3. Safety and validation
4. Governance and skills
5. Multi-agent supervision
6. Hardening and functional expansion

## Stage 1. Foundation Realignment

### Objective

Align the existing runtime with the new north star without destabilizing the current shell, task, and provider surface.

### Why This Stage Exists

The current codebase already has useful scaffolding:

- CLI shell
- session runtime
- provider abstraction
- structured tool registry
- task queue and workers
- subprocess sandbox path
- basic capability model

But the current abstractions are still centered on session plus task rather than work-item plus transaction.

This stage prepares the codebase for the deeper refactor.

### Deliverables

- formal north-star statement in architecture docs
- detailed plan and dependency map
- glossary for source truth, image truth, workflow truth, taint, checkpoint, rollback, quarantine, and provenance
- inventory of existing modules mapped to future workstreams
- gap matrix between current runtime primitives and target architecture

### Concrete Tasks

- Update `docs/architecture.md` to include a formal north-star mandate.
- Expand `docs/implementation-plan.md` into the detailed execution program.
- Add a section to `README.md` that explains the image-native system thesis in one concise form.
- Inventory the current modules and classify them as:
  - reusable as-is
  - reusable with refactor
  - transitional scaffolding
  - likely to be replaced
- Define terminology so later implementation work is consistent.

### Code Impact

Mostly docs and planning artifacts.

### Exit Criteria

- architecture docs clearly state that Codex is an outcome benchmark, not an implementation blueprint
- the repo has a detailed, ordered implementation program
- all future code work can be mapped to a named workstream and stage

## Stage 2. Transactional Kernel

### Objective

Introduce the first-class work-item and mutation transaction model.

### Why This Stage Comes First

Without transactional discipline, same-image autonomy will create nondeterministic state pollution. This must be solved before more autonomy or parallel mutation.

### Deliverables

- `work-item` data model
- transaction lifecycle model
- work-item persistence format
- source snapshot abstraction
- image snapshot reference abstraction
- mutation intent structure
- rollback point record
- closure state model

### New Primary Data Structures

#### Work Item

Minimum fields:

- `id`
- `goal`
- `status`
- `created-at`
- `updated-at`
- `source-snapshot`
- `image-snapshot-ref`
- `workflow-record-ref`
- `introspection-evidence`
- `mutation-intent`
- `runtime-observations`
- `live-validation-result`
- `cold-validation-result`
- `reconciliation-result`
- `rollback-point`
- `taint-status`
- `closure-decision`

#### Mutation Transaction

Minimum fields:

- `id`
- `work-item-id`
- `scope`
- `checkpoint-id`
- `state`
- `source-mutations`
- `image-mutations`
- `resource-effects`
- `rollback-status`
- `quarantine-status`

#### Image Snapshot Reference

Minimum fields:

- `id`
- `captured-at`
- `packages-in-scope`
- `symbols-in-scope`
- `thread-registry-ref`
- `resource-registry-ref`
- `dynamic-scope-ref`
- `taint-baseline`

### Concrete Tasks

- Add a `work-item` module and persistence layer.
- Refactor the current queue/task runtime so tasks can either:
  - remain low-level execution jobs
  - or become implementation details under a parent work-item
- Add work-item lifecycle transitions:
  - `:created`
  - `:inspecting`
  - `:planned`
  - `:checkpointed`
  - `:mutating`
  - `:observing`
  - `:live-validating`
  - `:cold-validating`
  - `:reconciling`
  - `:committed`
  - `:image-only`
  - `:rolled-back`
  - `:quarantined`
  - `:failed`
- Route nontrivial shell-level asks through work-item creation.
- Preserve the current REPL and command vocabulary while changing the internal execution substrate.

### Required Tests

- work-item creation preserves source snapshot and image snapshot references
- work-item transitions reject invalid state moves
- mutation transaction cannot begin without a valid checkpoint policy reference
- work-item persistence survives reload without losing closure or rollback metadata

### Exit Criteria

- work-item is the primary engineering unit in the runtime
- transaction lifecycle is explicit and test-covered
- the current task queue is no longer the top-level abstraction for meaningful work

## Stage 3. Source Truth Runtime

### Objective

Make source truth explicit and durable as a peer to image truth.

### Deliverables

- source snapshot service
- diff baseline service
- source mutation ledger
- cold-start source baseline record
- source truth inspection tools

### Concrete Tasks

- Add source snapshot capture:
  - current repo status
  - changed files
  - staged diff baseline
  - relevant file hashes or contents for touched scope
- Add source truth tools such as:
  - `:source/snapshot`
  - `:source/diff`
  - `:source/file-hash`
  - `:source/changed-files`
- Associate source mutations with work-item and transaction ids.
- Teach patch application to record source-truth evidence, not just write files.
- Define reproducibility baselines from source truth.

### Required Tests

- source snapshot records exact pre-mutation baseline
- source diff after patch can be linked back to work-item id
- source truth records survive rollback attempts and show final disposition clearly

### Exit Criteria

- source mutations are durable, attributable, and queryable as source truth
- cold-start validation can depend on a formal source baseline instead of ad hoc file state

## Stage 4. Image Truth Runtime

### Objective

Treat the live SBCL image as a first-class inspectable and governable domain.

### Deliverables

- image snapshot service
- symbol/package inspection registry
- dynamic binding capture hooks
- worker/thread registry abstraction
- resource registry abstraction
- image mutation ledger

### Concrete Tasks

- Introduce image introspection tools such as:
  - `:image/snapshot`
  - `:image/packages`
  - `:image/symbol`
  - `:image/bindings`
  - `:image/threads`
  - `:image/resources`
- Add structured capture for:
  - definitions likely to be touched
  - package membership and current package state
  - selected dynamic variable values
  - active worker and thread metadata
  - runtime resources relevant to the work-item
- Distinguish image mutations from source mutations in the event/workflow log.
- Add image-only experimental mutation support as an explicit closure class.

### Required Tests

- image snapshot captures symbols and package scope deterministically for test fixtures
- thread registry capture works before and after starting workers
- image-only mutation can be recorded without source mutation

### Exit Criteria

- the runtime can describe what changed in the live image independently of what changed on disk
- image truth queries are structured and attributable to a work-item

## Stage 5. Checkpointing and Rollback

### Objective

Make same-image mutation safe enough to support real autonomy.

### Deliverables

- checkpoint manager
- rollback manager
- rollback confidence model
- unresolved residue model
- quarantine support

### Concrete Tasks

- Define checkpoint capture policy for:
  - touched definitions
  - package and symbol state
  - relevant dynamic variables
  - worker/thread registry
  - resource registry
  - source diff baseline
  - validation baseline
- Implement rollback handles for:
  - source file restoration
  - symbol/function redefinition rollback where feasible
  - cache clearing or replacement
  - thread stop/cleanup tracking
  - runtime override removal
- Add quarantine state when full rollback is not possible.
- Add shell-visible rollback status summaries.

### Required Tests

- checkpoint can be created before patch and eval mutation
- rollback restores source and image state for a controlled fixture case
- partial rollback marks unresolved residue and quarantines the work-item

### Exit Criteria

- nontrivial mutation work is checkpointed by default
- rollback availability is explicit, not assumed
- quarantine is a first-class outcome rather than an error afterthought

## Stage 6. Dual Validation and Reconciliation

### Objective

Split validation into live validation and reproducibility validation.

### Deliverables

- live validator framework
- cold-start validator framework
- reconciliation report format
- validation doctrine hooks for skills

### Live Validation Scope

Live validation should answer:

- Did the runtime symptom improve?
- Did current flows continue correctly?
- Did active threads stabilize?
- Did current in-image behavior improve?

### Cold Validation Scope

Cold validation should answer:

- Does the system load from source?
- Do relevant tests pass from a fresh image?
- Is the fix durable without historical image state?

### Concrete Tasks

- Add validator result structs for live and cold validation separately.
- Introduce validator runners for:
  - runtime probes
  - REPL-based in-image assertions
  - fresh SBCL launch/load checks
  - test suite segments
- Add reconciliation reporting when live and cold diverge.
- Require explicit acknowledgment when a work-item closes with mismatch.

### Required Tests

- live pass plus cold fail produces reconciled "image-local success" result
- live fail plus cold pass is recorded distinctly
- both-pass work-item can close committed without manual discrepancy note

### Exit Criteria

- no work-item can claim completion on live validation alone without explicit mismatch status
- the system can distinguish runtime healing from durable code correction

## Stage 7. Taint Tracking and Provenance

### Objective

Make live-state contamination visible and make every conclusion auditable.

### Deliverables

- taint model
- taint propagation rules
- provenance record schema
- provenance persistence and query tools

### Taint Minimum Scope

Track at minimum:

- symbols redefined in the transaction
- objects or caches derived from changed code
- threads influenced by the transaction
- configuration overrides introduced during work
- runtime resources opened or altered
- validations executed against tainted state

### Provenance Minimum Scope

Record at minimum:

- initial source hash/baseline
- initial image snapshot id
- introspection queries used to form the plan
- all executed mutations
- before/after symbol or subsystem map
- runtime observations
- validation outputs
- final source diff
- rollback availability
- taint status
- operator interventions

### Concrete Tasks

- Introduce taint tags attached to work-items, image snapshots, and validation results.
- Propagate taint when image mutation occurs.
- Add provenance query tools such as:
  - `:workflow/provenance`
  - `:workflow/work-item`
  - `:workflow/evidence`
- Surface taint in monitor views and final work-item summaries.

### Required Tests

- redefining a symbol taints subsequent relevant validation results
- provenance record contains required mandatory fields
- reviewer view can reconstruct mutation chain and validation basis

### Exit Criteria

- live-image success claims are always accompanied by taint status
- provenance is complete enough to support review and replay work later

## Stage 8. Runtime-Governed Skills

### Objective

Turn skills into operational doctrines for live-system work rather than generic prompt bundles.

### Deliverables

- skill doctrine schema
- checkpoint doctrine hooks
- rollback doctrine hooks
- live/cold validator doctrine hooks
- approval doctrine hooks

### Concrete Tasks

- Define skill metadata fields for:
  - mutation class: read-only, source-only, image-only, dual-mutation
  - checkpoint requirement
  - rollback requirement
  - required live validators
  - required cold validators
  - persistent side-effect policy
  - operator approval requirements
- Implement initial skill doctrines:
  - live hotfix doctrine
  - source refactor doctrine
  - runtime diagnostic doctrine
  - cold reproducibility verification doctrine
- Ensure work-items inherit doctrine defaults from the selected skill.

### Required Tests

- work-item with live hotfix doctrine cannot skip checkpoint or live validation
- source refactor doctrine requires cold-start validation before closure
- read-only observer doctrine prevents mutation entrypoints

### Exit Criteria

- skills become governance capsules for work-item behavior
- different operational doctrines can be applied to the same shell and tool substrate safely

## Stage 9. Role-Isolated Multi-Agent Supervision

### Objective

Support multi-agent work without uncontrolled shared-image mutation.

### Deliverables

- observer role
- planner role
- mutation role
- reviewer role
- supervisor role
- state authority enforcement

### Role Rules

- Observer agents may inspect source and image but not mutate.
- Planner agents may inspect and propose transactions but not execute.
- Mutation agents may execute only inside a narrow transaction scope.
- Reviewer agents may inspect diffs, image deltas, taint, and evidence but may not alter the active transaction.
- Supervisor agent owns closure, rollback, retry, quarantine, and escalation.

### Concrete Tasks

- Add role metadata and authority checks to work-items.
- Restrict mutation entrypoints by agent role.
- Support multiple observers/planners in parallel.
- Forbid parallel mutation until disjointness is proven by:
  - file set
  - symbol set
  - subsystem boundary
- Add supervisor decision surfaces for retry, rollback, quarantine, and operator escalation.

### Required Tests

- observer cannot mutate source or image
- planner cannot execute transaction
- mutation agent cannot exceed declared transaction scope
- disjointness gate blocks overlapping parallel mutation attempts

### Exit Criteria

- multi-agent work is organized around state authority, not only task decomposition
- shared-image mutation risk is bounded by explicit role restrictions

## Stage 10. Challenge-Based Review and Operator Hardening

### Objective

Make review and operator workflows attack the real failure modes of live-image engineering.

### Deliverables

- challenge-based review framework
- deterministic replay roadmap and first implementation slice
- work-item resume support
- quarantine inspection surfaces
- why-am-I-waiting status surfaces

### Challenge Functions

Review should explicitly ask:

- Did the agent solve the current runtime symptom?
- Did it introduce hidden image-state dependency?
- Is the source patch sufficient from cold start?
- Can the transaction be replayed deterministically?
- Is rollback proven?
- Is the current validation tainted?
- Did the patch overfit to this process instance?

### Concrete Tasks

- Add review artifacts attached to work-item closure.
- Add operator views for:
  - pending approvals
  - missing validation
  - rollback uncertainty
  - quarantine reasons
  - taint warnings
- Add resume support for interrupted work-items.
- Add first deterministic replay primitives where feasible.

### Required Tests

- review artifact captures all mandatory challenge questions
- quarantined work-item can be resumed for operator review
- blocked work-item explains what evidence or approval it is waiting on

### Exit Criteria

- the system is not only powerful but operator-trustworthy under live-state complexity
- review loops target hidden-state false success rather than just source diff quality

## Cross-Cutting Engineering Policies

## Policy 1. Preserve Current Utility While Refactoring

The existing shell, tool registry, tests, and provider abstraction are useful scaffolding. Refactors should preserve day-to-day usefulness wherever practical.

## Policy 2. Prefer Explicit Structures Over Implicit Conventions

If a concept matters architecturally, it needs a real data structure.

This includes:

- work-items
- transactions
- checkpoints
- taint state
- provenance records
- validation results
- closure decisions

## Policy 3. Separate Source Mutation From Image Mutation Everywhere

No mutation API should blur the difference between:

- changing files
- redefining live symbols
- doing both as one transaction

## Policy 4. Do Not Add Broad Autonomy Before Rollback Is Trustworthy

Checkpointing and rollback are prerequisites for stronger autonomy, not follow-on polish.

## Policy 5. Measure Against Operator Value, Not Implementation Similarity

Success means:

- faster diagnosis of live problems
- safer hot repair
- higher reproducibility from cold start
- clearer rollback confidence
- stronger provenance and reviewability

## Milestone View

### Milestone A. Image-Native Foundations

Includes:

- Stage 1
- Stage 2
- Stage 3
- Stage 4

Outcome:

The system can represent and persist work-items that distinguish source, image, and workflow truth.

### Milestone B. Safe Mutation Discipline

Includes:

- Stage 5
- Stage 6
- Stage 7

Outcome:

The system can mutate safely with checkpointing, rollback, dual validation, taint, and provenance.

### Milestone C. Governed Scaling

Includes:

- Stage 8
- Stage 9
- Stage 10

Outcome:

The system can scale to doctrine-bearing skills, bounded multi-agent supervision, and operator-grade review workflows.

## Success Metrics

The project should be measured against its real thesis.

Primary metrics:

- mean time to identify live-runtime root cause
- mean time to hot-repair a running image safely
- percentage of live fixes that reproduce from cold start
- rollback success rate
- tainted-validation detection rate
- operator interventions per completed work-item
- number of tasks resolved without restart for diagnosis and repair
- delta between runtime symptom resolution and durable source correction

Secondary metrics:

- time from inspection start to checkpoint creation
- rate of quarantined work-items
- replay success rate once replay exists
- ratio of image-only experimental commits to durable commits

## Immediate Next Implementation Slice

The next concrete engineering slice should be:

1. introduce `work-item` and `mutation-transaction` structures
2. map existing `task` usage to transitional work-item wrappers
3. add source snapshot and image snapshot reference records
4. extend session/workflow persistence to include work-item truth
5. add shell inspection surfaces for work-item status and truth separation

That is the minimum viable start on the new architecture.

## Summary

`sbcl-agent` should not chase Codex by copying Codex's mechanics.

It should instead deliver Codex-class engineering outcomes through a stronger Lisp-native architecture built around:

- source truth
- image truth
- workflow truth
- transactional mutation
- checkpointing and rollback
- dual validation
- taint tracking
- provenance
- doctrine-bearing skills
- role-isolated multi-agent supervision

That is the route to achieving as much functionally, and eventually more, by leveraging the differentiators of Common Lisp rather than suppressing them.
