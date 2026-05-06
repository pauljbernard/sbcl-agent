# Continuous Alignment System Enhancement Plan

## Purpose

Persist the concrete implementation plan for evolving `sbcl-agent` and `sbcl-agent-ux`
into a fully realized Continuous Alignment System while preserving the core invariant:

- alignment is continuous, durable, runtime-aware, and reconciliation-led

This document supplements the broader SDLC parity roadmap with the architecture-specific
CAS workstream.

## Core Invariants

These must remain true through every implementation slice:

- Runtime is authoritative reality
- Intent persists and remains first-class
- Alignment is continuous, not request-driven
- Reconciliation is authoritative

## Current Program Recalibration

The prior roadmap was near completion for SDLC panel/chat parity. This CAS enhancement
broadens the program materially beyond that surface parity work.

- Recalibrated total completion for the expanded program: `94%`

## Phase Mapping To Existing Modules

### Phase 0. Protect Core Invariants

Primary modules:

- `/Volumes/data/development/sbcl-agent/src/environment-sync.lisp`
- `/Volumes/data/development/sbcl-agent/src/environment-summary.lisp`
- `/Volumes/data/development/sbcl-agent/src/mutation-engine.lisp`
- `/Volumes/data/development/sbcl-agent/src/execution-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/mutation-review-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/traceability.lisp`

Guardrails:

- runtime state remains the canonical source of truth
- all corrective action remains governed, auditable, and approval-aware

### Phase 1. Intent As A First-Class Object

Primary modules:

- `/Volumes/data/development/sbcl-agent/src/intents.lisp`
- `/Volumes/data/development/sbcl-agent/src/intent-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/retrieval-intent.lisp`
- `/Volumes/data/development/sbcl-agent/src/retrieval-dossier.lisp`
- `/Volumes/data/development/sbcl-agent/src/traceability.lisp`
- `/Volumes/data/development/sbcl-agent-ux/src/shared/contracts.ts`

Required outcomes:

- canonical durable intent model
- intent versioning and diffing
- intent linkage to runtime objects, source artifacts, events, and mutations

### Phase 2. Context Resolution Engine

Primary modules:

- `/Volumes/data/development/sbcl-agent/src/retrieval-plan.lisp`
- `/Volumes/data/development/sbcl-agent/src/retrieval-ranking.lisp`
- `/Volumes/data/development/sbcl-agent/src/retrieval-dossier.lisp`
- `/Volumes/data/development/sbcl-agent/src/runtime-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/event-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/trace-service.lisp`

Required outcomes:

- symbolic runtime index
- source index
- event/alignment graph substrate
- context packets assembled by alignment need rather than similarity alone

### Phase 3. Alignment Engine

Primary modules:

- `/Volumes/data/development/sbcl-agent/src/cognition-bundle.lisp`
- `/Volumes/data/development/sbcl-agent/src/execution-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/retrieval-dossier.lisp`
- `/Volumes/data/development/sbcl-agent/src/environment-summary.lisp`

Required outcomes:

- formal alignment state
- divergence categories
- continuous observe -> compare -> score -> decide -> mutate -> validate -> update loop

### Phase 4. Reconciliation Engine

Primary modules:

- `/Volumes/data/development/sbcl-agent/src/mutation-engine.lisp`
- `/Volumes/data/development/sbcl-agent/src/mutation-review-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/workflow-state.lisp`
- `/Volumes/data/development/sbcl-agent/src/workflow-ops-service.lisp`

Required outcomes:

- explicit reconciliation objects
- runtime-vs-intent-vs-co-evolve decisions
- durable tracking of why corrections occurred and what changed

### Phase 5. Event Fabric

Primary modules:

- `/Volumes/data/development/sbcl-agent/src/events.lisp`
- `/Volumes/data/development/sbcl-agent/src/event-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/environment-sync.lisp`
- `/Volumes/data/development/sbcl-agent/src/incident-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/runtime-telemetry-service.lisp`

Required outcomes:

- every meaningful state transition becomes an explicit event
- no hidden corrective or alignment transitions

### Phase 6. Mutation System

Primary modules:

- `/Volumes/data/development/sbcl-agent/src/mutation-engine.lisp`
- `/Volumes/data/development/sbcl-agent/src/patch.lisp`
- `/Volumes/data/development/sbcl-agent/src/tools-*.lisp`
- `/Volumes/data/development/sbcl-agent/src/mutation-review-service.lisp`

Required outcomes:

- reversible and audited mutations
- constraint checking before and after mutation

### Phase 7. Governance As System Physics

Primary modules:

- `/Volumes/data/development/sbcl-agent/src/policy.lisp`
- `/Volumes/data/development/sbcl-agent/src/approval-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/execution-service.lisp`
- `/Volumes/data/development/sbcl-agent/src/project-service.lisp`

Required outcomes:

- invariants, policies, approvals, and safety boundaries enforced at all correction points

### Phase 8. Desktop Trust Interface

Primary modules:

- `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/App.tsx`
- `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/projects-workspace.tsx`
- `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/journey-workspaces.tsx`
- `/Volumes/data/development/sbcl-agent-ux/src/main/live-host-adapter.ts`
- `/Volumes/data/development/sbcl-agent-ux/src/shared/contracts.ts`

Required outcomes:

- explicit operator visibility into:
  - current intent
  - runtime state
  - alignment score
  - divergence
  - proposed actions
  - approvals
  - history
  - causal chain

### Phase 9. LLM Integration Role

Primary modules:

- `/Volumes/data/development/sbcl-agent/src/provider-protocol.lisp`
- `/Volumes/data/development/sbcl-agent/src/provider-openai.lisp`
- `/Volumes/data/development/sbcl-agent/src/provider-mock.lisp`
- `/Volumes/data/development/sbcl-agent/src/execution-service.lisp`

Required outcomes:

- LLM constrained to interpretation, hypothesis generation, proposal, and summarization
- LLM never owns state and never bypasses governance

### Phase 10. Metrics

Primary modules:

- `/Volumes/data/development/sbcl-agent/src/environment-summary.lisp`
- `/Volumes/data/development/sbcl-agent/src/platform-service.lisp`
- `/Volumes/data/development/sbcl-agent/tests/performance.lisp`
- `/Volumes/data/development/sbcl-agent-ux/tests/ui/*.ts`

Required outcomes:

- alignment convergence speed
- divergence frequency
- correction success rate
- manual intervention reduction
- operator clarity / trust indicators

## Execution Order

1. Phase 1 intent model foundation
2. Phase 5 event normalization hardening where needed
3. Phase 2 minimal context assembly engine
4. Phase 3 initial alignment scoring
5. Phase 4 reconciliation decision substrate
6. Phase 8 desktop visibility
7. deeper mutation/governance/autonomy refinement

## Iteration Log

### Iteration 1

- Persisted this CAS enhancement plan.
- Mapped CAS phases directly onto the current SBCL and Electron modules.
- Began Phase 1 implementation with the canonical intent model foundation.

### Iteration 2

- Added backend service-contract coverage for durable intent records.
- Verified intent create, detail, list, update, select, and diff behavior.
- Established the first governed backend boundary for first-class intent objects.

### Iteration 3

- Added durable intent projection into retrieval/dossier assembly.
- Added an explicit intent retrieval domain and intent-centered trace neighborhood support.
- Verified alignment-oriented prompts can resolve the selected durable intent and linked evidence through the existing retrieval stack.

### Iteration 4

- Added the first minimal alignment-driven context packet service on top of the retrieval stack.
- Introduced `query-alignment-context-packet-service` with read model `:alignment-context-packet-v1`.
- The packet now assembles:
  - current durable intent
  - agent/runtime identity
  - runtime scope
  - source scope
  - relevant events
  - active constraints
  - recent history
  - validation state
  - explicit alignment gaps
- Verified the packet contract with `alignment-context-packet-service-test`.
- Revalidated the full backend suite with `./bin/run-tests`.

### Iteration 5

- Strengthened intent linkage so durable intent references now synchronize into the trace graph automatically.
- Added automatic trace-link sync for intent-linked:
  - runtime objects
  - source artifacts
  - events
  - mutations
- Extended the event stream to expose stable event ids for downstream alignment resolution.
- Deepened the alignment context packet so it now resolves:
  - linked event ids into concrete event evidence
  - linked mutation ids into concrete operation evidence
- Added derived linkage and gap analysis to the packet:
  - resolved vs unresolved linkage counts
  - missing linked events
  - missing linked mutations
  - source divergence
  - blocked project readiness
  - testing failure presence
- Verified the strengthened linkage path with:
  - `intent-service-contract-test`
  - `alignment-context-packet-service-test`
  - full backend suite via `./bin/run-tests`

### Iteration 6

- Added a first-class backend `alignment-state` primitive in `/Volumes/data/development/sbcl-agent/src/alignment-state.lisp`.
- Introduced `query-alignment-state-service` with read model `:alignment-state-v1`.
- The alignment state now computes and projects:
  - intent id
  - score
  - divergence types
  - confidence
  - status
  - evaluation timestamp
  - gap count
  - linkage state
  - validation state
- Added initial divergence classification for:
  - behavioral mismatch
  - missing capability
  - incorrect constraint enforcement
  - outdated intent
  - incomplete specification
- Added aligned and degraded regression coverage in `/Volumes/data/development/sbcl-agent/tests/retrieval.lisp`.
- Revalidated the full backend suite with `./bin/run-tests`.

### Iteration 7

- Projected `alignment-state` into operator-facing backend trust surfaces instead of keeping it isolated as a retrieval-only primitive.
- Added alignment projection through:
  - `/Volumes/data/development/sbcl-agent/src/environment-summary.lisp`
  - `/Volumes/data/development/sbcl-agent/src/environment-service.lisp`
  - `/Volumes/data/development/sbcl-agent/src/project-service.lisp`
  - `/Volumes/data/development/sbcl-agent/src/retrieval-dossier.lisp`
  - `/Volumes/data/development/sbcl-agent/src/session.lisp`
- Added recursion guards so alignment evaluation no longer re-enters:
  - environment summary/status reads
  - project detail reads
  - retrieval dossier summaries
- Preserved the environment-owned-state contract:
  - compatibility payloads are no longer materialized into live sessions merely to compute alignment during status reads
  - alignment is only projected when a real materialized agent session already exists
- Added and extended regression coverage for:
  - environment summary alignment projection
  - session summary alignment projection
  - project detail alignment projection
- Revalidated the full backend suite with `./bin/run-tests`.

### Iteration 8

- Added the first formal reconciliation primitive in `/Volumes/data/development/sbcl-agent/src/reconciliation-decision.lisp`.
- Introduced `query-reconciliation-decision-service` with read model `:reconciliation-decision-v1`.
- The reconciliation decision now derives and projects:
  - intent id
  - alignment status
  - divergence types
  - decision direction:
    - `:maintain`
    - `:runtime`
    - `:intent`
    - `:co-evolve`
  - proposed corrective actions
  - confidence
  - approval requirement
  - rationale
  - evaluation timestamp
- The decision model is now derived from:
  - alignment divergence types
  - resolved alignment gap types
  - active governance constraints
  - current validation and release posture
- Added regression coverage in `/Volumes/data/development/sbcl-agent/tests/retrieval.lisp` for:
  - aligned maintain posture
  - governed co-evolution posture
- Revalidated the focused reconciliation regression and the full backend suite with:
  - `sbcl --non-interactive ... reconciliation-decision-service-test`
  - `./bin/run-tests`

### Iteration 9

- Projected `reconciliation-decision` into the same backend trust surfaces that already carry alignment state:
  - `/Volumes/data/development/sbcl-agent/src/environment-summary.lisp`
  - `/Volumes/data/development/sbcl-agent/src/environment-service.lisp`
  - `/Volumes/data/development/sbcl-agent/src/session.lisp`
  - `/Volumes/data/development/sbcl-agent/src/project-service.lisp`
- The operator-facing backend summaries now expose:
  - reconciliation direction
  - approval requirement
  - corrective rationale
  alongside alignment score and divergence state.
- Extended environment operator evidence so trust posture now includes both:
  - `:alignment`
  - `:reconciliation`
- Added recursion guards to keep reconciliation projection from re-entering alignment evaluation indirectly through:
  - environment summary/status helper reads
  - project readiness helper reads
  - dossier-side compact evidence helpers
- Extended regression coverage in:
  - `/Volumes/data/development/sbcl-agent/tests/smoke.lisp`
  - `/Volumes/data/development/sbcl-agent/tests/service-contracts.lisp`
- Revalidated the full backend suite with `./bin/run-tests`.

### Iteration 10

- Carried CAS trust posture into the desktop operator interface in `sbcl-agent-ux`.
- Added typed trust DTOs and payload projection in:
  - `/Volumes/data/development/sbcl-agent-ux/src/shared/contracts.ts`
  - `/Volumes/data/development/sbcl-agent-ux/src/main/live-host-adapter.ts`
- The live adapter now normalizes and exposes:
  - `alignmentState`
  - `reconciliationDecision`
  through:
  - environment summary
  - environment status
  - project detail
- Added an operator-facing trust view to the `Operate` workspace in:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/operate-workspace.tsx`
- Added a project-scoped trust posture section to the `Projects` workspace in:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/projects-workspace.tsx`
- Extended mock trust posture examples in:
  - `/Volumes/data/development/sbcl-agent-ux/src/shared/mock-environments.ts`
- Added live Electron regression coverage in:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
  - validated:
    - `surfaces live alignment and corrective direction in operate and projects`
- Revalidated desktop trust-surface wiring with:
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run build`
  - focused Playwright live regression

### Iteration 11

- Tightened the reconciliation object into a more reviewable closed-loop trust primitive.
- Extended `/Volumes/data/development/sbcl-agent/src/reconciliation-decision.lisp` so reconciliation decisions now project:
  - `trigger-events`
  - `approval-posture`
  - existing proposed corrective actions as an explicit corrective queue
- The reconciliation engine now connects proposed correction to the event fabric by surfacing the resolved linked trigger events that caused the current divergence posture.
- Extended regression coverage in `/Volumes/data/development/sbcl-agent/tests/retrieval.lisp` to validate:
  - observational maintain posture
  - governed review posture
  - trigger-event projection shape
- Extended the desktop trust interface in `sbcl-agent-ux`:
  - typed DTO support in `/Volumes/data/development/sbcl-agent-ux/src/shared/contracts.ts`
  - live adapter normalization in `/Volumes/data/development/sbcl-agent-ux/src/main/live-host-adapter.ts`
  - richer `Operate` trust facts and trigger-event snapshot in `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/operate-workspace.tsx`
  - richer `Projects` trust posture with:
    - corrective queue
    - trigger events
    in `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/projects-workspace.tsx`
- Extended mock trust posture fixtures in `/Volumes/data/development/sbcl-agent-ux/src/shared/mock-environments.ts`.
- Added focused live Electron validation in `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts` for:
  - trust posture
  - corrective queue
  - trigger-event visibility
- Revalidated end to end with:
  - `./bin/run-tests`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run build`
  - focused Playwright live regression

### Iteration 12

- Added the first governed corrective-execution backend slice for CAS in:
  - `/Volumes/data/development/sbcl-agent/src/reconciliation-execution-service.lisp`
  - `/Volumes/data/development/sbcl-agent/src/policy.lisp`
  - `/Volumes/data/development/sbcl-agent/sbcl-agent.asd`
- Introduced `:alignment-reconciliation-execute` as a first-class governed capability policy for materializing reconciliation into corrective work.
- Added `command-materialize-reconciliation-correction-service`, which now:
  - reads the current alignment context packet
  - computes alignment state
  - computes reconciliation direction
  - creates governed corrective work when divergence requires action
  - emits trace links from intent/event evidence to the corrective work item
  - records a corrective execution event in the session/event fabric
  - requests approval when governance requires review
- Added service-contract coverage in:
  - `/Volumes/data/development/sbcl-agent/tests/service-contracts.lisp`
  - `/Volumes/data/development/sbcl-agent/tests/test-runner.lisp`
- Fixed the regression chain exposed by making approval-gated governed work-items explicitly `:awaiting-approval`:
  - approved conversation `turn/resume` tool execution was no longer allowed to mutate through kernel preflight
  - `rgp/resume` was still being blocked by the same stale approval posture
  - long-horizon plan semantics had drifted so approval-gated work lost `:resumable` control posture and validation-gated work lost `:validate` current phase
- Corrected those semantics in:
  - `/Volumes/data/development/sbcl-agent/src/kernel-service.lisp`
  - `/Volumes/data/development/sbcl-agent/src/work-items.lisp`
- Revalidated the full backend suite with:
  - `./bin/run-tests`
  - `All tests passed.`

### Iteration 13

- Projected governed reconciliation execution into operator workflow surfaces in the backend instead of leaving it visible only in the correction command response.
- Added compact corrective-work context derived from reconciliation-created work items in:
  - `/Volumes/data/development/sbcl-agent/src/work-items.lisp`
  - `/Volumes/data/development/sbcl-agent/src/environment-service.lisp`
  - `/Volumes/data/development/sbcl-agent/src/shell-service.lisp`
- The new corrective context now carries:
  - corrective kind
  - intent id
  - reconciliation decision
  - approval posture
  - alignment score/status snapshot
  - proposed corrective actions
  - resolved trigger-event evidence
- This context now flows through:
  - work-item summaries/details
  - compact blocked-work and approval surfaces
  - shell governance queue items
- Extended service-contract coverage in:
  - `/Volumes/data/development/sbcl-agent/tests/service-contracts.lisp`
  - the reconciliation correction contract now verifies corrective context is preserved in:
    - work-item detail
    - session approval surfaces
    - shell governance queue
- Fixed the regression introduced by the first projection attempt:
  - `:relevant-events` in the alignment context packet is a plist, not a raw event list
  - corrective-context projection now reads `:resolved-linked-events` specifically instead of treating the whole packet as a list
- Revalidated the full backend suite with:
  - `./bin/run-tests`
  - `All tests passed.`

### Iteration 14

- Carried governed corrective-work context into the desktop operator workflow surfaces in `sbcl-agent-ux`.
- Extended typed contracts for corrective execution in:
  - `/Volumes/data/development/sbcl-agent-ux/src/shared/contracts.ts`
  - added:
    - `CorrectiveContextDto`
    - `CorrectiveActionDto`
    - `CorrectiveTriggerEventDto`
  - attached corrective context to:
    - `WorkItemSummaryDto`
    - `WorkItemDetailDto`
- Normalized live corrective-work payloads in:
  - `/Volumes/data/development/sbcl-agent-ux/src/main/live-host-adapter.ts`
  - the live adapter now projects:
    - reconciliation decision
    - approval posture
    - alignment status and score
    - proposed corrective actions
    - trigger-event evidence
    into work-item list/detail DTOs
- Exposed corrective execution directly in the `Work` surface in:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/journey-workspaces.tsx`
  - selected governed work items now show:
    - corrective kind
    - corrective decision
    - approval posture
    - alignment snapshot
    - proposed corrective actions
    - trigger evidence
- Exposed corrective execution in the browser governance lane in:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/App.tsx`
  - corrective work is now labeled explicitly as:
    - `Corrective Work Item`
  - governance detail now renders:
    - corrective identity rows
    - corrective action queue entries
    - trigger-event evidence
- Fixed the renderer typing drift surfaced during validation:
  - governance-entry unions did not all declare `correctiveContext`
  - corrected at the source by explicitly typing the governance-entry projection before mapping into governance rows
- Revalidated the desktop slice with:
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run build`
  - focused live Electron regression:
    - `surfaces live alignment and corrective direction in operate and projects`

### Iteration 15

- Began the first real operator corrective-control milestone instead of only expanding trust visibility.
- Extended the `Work` surface in `sbcl-agent-ux` so approval-bearing governed work can drive directly into the approval path:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/journey-workspaces.tsx`
  - added:
    - `Review Approval`
    - `Approve Corrective Work`
    - `Deny Corrective Work`
- Extended the app coordination path in:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/App.tsx`
  - approval decisions triggered from the `Work` surface now refresh the work workspace as well as approvals/project state
  - added direct approval navigation helper so governed work can route straight into the approvals workspace
- Fixed the underlying backend defect that prevented the desktop from seeing corrective approval burden:
  - `/Volumes/data/development/sbcl-agent/src/work-item-service.lisp`
  - `work-item` list summaries now project:
    - `:approval-requirements`
    - `:waiting-on`
    - `:wait-reason`
  - the fix was implemented without using a mutating wait-report helper, so provider-context bundle generation remains deterministic
- This also resolved the retrieval/provider regression caused by the first summary-projection attempt:
  - `provider-context-bundle-consistency-test` is green again after removing read-path side effects
- Added focused live Electron coverage in:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
  - new passing regression:
    - `routes corrective governed work into approval control directly from the work panel`
- Revalidated with:
  - `./bin/run-tests`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run build`
  - focused Playwright live regression

### Iteration 16

- Carried the first corrective-control semantics from the `Work` panel into the browser governance/operator trust flow in `sbcl-agent-ux`.
- Extended browser governance controls in:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/App.tsx`
  - the browser governance detail now supports:
    - `Review Approval`
    - `Approve Corrective Work`
    - `Deny Corrective Work`
  - using the same governed approval handlers as the `Work` and `Approvals` surfaces rather than introducing a parallel control path
- Corrected the browser governance component boundary so it consumes explicit props for:
  - approval-decision in-flight state
  - approval routing
  - approval decision submission
  instead of reaching across unrelated workspace state
- Tightened the live Electron regression to derive the real approval-bearing governed work target from the live query layer instead of assuming a brittle static row title:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
- Revalidated with:
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run build`
  - focused Playwright live regressions:
    - `routes corrective governed work into approval control directly from the work panel`
    - `routes corrective governed work into approval control directly from browser governance`

### Iteration 17

- Broadened operator corrective control into the remaining trust-facing desktop surfaces in `sbcl-agent-ux`.
- Extended the `Projects` trust posture surface so it can:
  - `Review Approval`
  - `Approve Corrective Work`
  - `Deny Corrective Work`
  using the same governed approval path already proven in `Work` and browser governance
- Extended the `Operate` trust posture surface so it can route directly into approval review for active corrective governed work
- Fixed the desktop data-loading gap that blocked those controls from appearing reliably:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/App.tsx`
  - `Operate` navigation now loads work and approval state explicitly instead of relying only on passive workspace effects
- Tightened the focused live coverage in:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
  - passing regressions now include:
    - `routes corrective governed work into approval control directly from operate trust posture`
    - `routes corrective governed work into approval control directly from projects trust posture`
- Revalidated with:
  - `./bin/run-tests`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run build`
  - focused Playwright live regressions for `Operate` and `Projects` trust control

### Iteration 18

- Carried corrective rationale and trigger evidence into the approval-decision surface itself so the operator does not lose alignment context at the final governed decision point.
- Extended the approvals workspace in:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/journey-workspaces.tsx`
  - approval detail now renders:
    - `Corrective Posture`
    - `Approval Posture`
    - `Alignment`
    - `Trigger Events`
    - corrective action rationale
- Joined corrective context into approval detail from:
  - linked governed work when item-level corrective context is present
  - environment reconciliation posture as a fallback when the live approval path only exposes broader trust evidence
- Wired the additional reconciliation fallback into:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/App.tsx`
- Added focused live Electron coverage in:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
  - new passing regression:
    - `surfaces corrective rationale and trigger evidence directly in approvals`
- Revalidated with:
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run build`
  - focused Playwright live regression for approvals corrective detail

### Iteration 19

- Extended corrective posture visibility into the inspector path so operators do not lose alignment context when pivoting from approval review into resident shell inspection.
- Updated the inspector selection view in:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/App.tsx`
  - approval selection now includes:
    - `Corrective Kind`
    - `Approval Posture`
    - `Alignment`
    - `Trigger Events`
    - the leading corrective rationale
- Reused the same corrective-context join strategy as the approvals surface:
  - linked governed work when item-level corrective context exists
  - reconciliation fallback when the live approval path exposes only trust-level alignment evidence
- Added focused live Electron coverage in:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
  - new passing regression:
    - `surfaces corrective posture directly in the inspector for approval review`
- Revalidated with:
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck`
  - focused Playwright live inspector regression

### Iteration 20

- Closed the remaining browser-governance inspector gap so corrective posture remains visible when the operator pivots into the resident inspector from browser governance, not only from approvals.
- Updated:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/App.tsx`
  - simplified browser-governance inspector posture to use the already-selected governed object state instead of trying to reconstruct selection from unrelated browser row context
- Tightened the focused live regression in:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
  - reused the known-good browser governance selection path from the existing approval-control regression instead of brittle stack-local assumptions
- Revalidated with:
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run build`
  - focused Playwright live regression:
    - `surfaces corrective posture in the inspector from browser governance`

### Iteration 21

- Began the event-driven closed-loop orchestration slice in the backend instead of leaving reconciliation materialization primarily explicit or operator-invoked.
- Wired the session event append path in:
  - `/Volumes/data/development/sbcl-agent/src/session.lisp`
  - it now calls the continuous alignment event loop when available
- Added the first governed continuous-alignment event loop in:
  - `/Volumes/data/development/sbcl-agent/src/reconciliation-execution-service.lisp`
  - trigger set currently includes:
    - `:incident-created`
    - `:validation-completed`
    - `:runtime-evaluated`
    - `:runtime-reloaded-file`
    - `:runtime-package-switched`
  - the loop now:
    - recomputes alignment state from the triggering event context
    - derives a reconciliation decision
    - auto-materializes governed corrective work when required
    - suppresses duplicate corrective work while an actionable corrective item for the same intent/decision is already active
- Refactored explicit reconciliation materialization so both:
  - direct command execution
  - event-driven orchestration
  share the same corrective work creation path and dedupe logic
- Added backend contract coverage in:
  - `/Volumes/data/development/sbcl-agent/tests/service-contracts.lisp`
  - `/Volumes/data/development/sbcl-agent/tests/test-runner.lisp`
  - new proof:
    - `continuous-alignment-event-loop-service-contract-test`
    - validates auto-materialization on a trigger event
    - validates no duplicate corrective work is created on a second trigger while the first corrective item remains actionable
- Revalidated with:
  - focused SBCL contract invocation:
    - `continuous-alignment-event-loop-service-contract-test ok`

### Iteration 22

- Extended the event-driven orchestration proof beyond initial auto-materialization so the loop now has validated lifecycle semantics, not only a first trigger.
- Added backend contract coverage in:
  - `/Volumes/data/development/sbcl-agent/tests/service-contracts.lisp`
  - `/Volumes/data/development/sbcl-agent/tests/test-runner.lisp`
  - new proof:
    - `continuous-alignment-event-loop-reopens-after-resolution-test`
- The expanded focused coverage now validates:
  - first relevant event auto-materializes governed corrective work
  - repeated relevant events do not duplicate a still-actionable corrective item
  - once the earlier corrective item is no longer actionable, a later relevant event can materialize a fresh correction
- Revalidated with:
  - focused SBCL contract invocation:
    - `continuous-alignment-event-loop-contracts ok`

### Iteration 23

- Added a deterministic desktop bridge path for first-class intent creation so live Electron coverage can establish explicit divergence instead of depending on ambient environment posture.
- Updated:
  - `/Volumes/data/development/sbcl-agent-ux/src/shared/contracts.ts`
  - `/Volumes/data/development/sbcl-agent-ux/src/main/adapter-contract.ts`
  - `/Volumes/data/development/sbcl-agent-ux/src/preload/index.ts`
  - `/Volumes/data/development/sbcl-agent-ux/src/main/ipc.ts`
  - `/Volumes/data/development/sbcl-agent-ux/src/main/live-host-adapter.ts`
  - `/Volumes/data/development/sbcl-agent-ux/src/main/mock-host-adapter.ts`
  - `/Volumes/data/development/sbcl-agent-ux/scripts/live-service-bridge.lisp`
- Added focused live end-to-end CAS coverage in:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
  - new proof:
    - `auto-creates corrective governed work from a live runtime event and routes it through approval`
- The live proof now validates:
  - create deprecated current intent through the desktop bridge
  - trigger a real `:runtime-evaluated` event from the live listener
  - observe event-driven auto-materialization of corrective governed work
  - route the resulting approval through the real `Approvals` surface
  - confirm the corrective approval is no longer awaiting after approval
- Folded that regression into the packaged routine live-governance journey entrypoint in:
  - `/Volumes/data/development/sbcl-agent-ux/package.json`
- Revalidated with:
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck`
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run build`
  - focused Playwright live regression:
    - `auto-creates corrective governed work from a live runtime event and routes it through approval`

### Iteration 24

- Split the remaining oversized governed chat live-governance scenarios into smaller proofs so the packaged journey suite stays green under the default test budget instead of depending on timeout changes.
- Updated:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
  - `/Volumes/data/development/sbcl-agent-ux/package.json`
- Replaced the prior overloaded project-governance conversation cases with focused tests for:
  - governed project creation through chat
  - governed project augmentation through chat
  - governed foundation revision through chat
  - governed architecture revision through chat
- Trimmed each focused case to prove the intended governed mutation path without redundant setup or unnecessary surface round-trips.
- Revalidated with:
  - focused Playwright runs for:
    - `authors governed early project artifacts through the conversation chat interface`
    - `augments governed early project artifacts through the conversation chat interface`
    - `revises governed project foundations through the conversation chat interface`
    - `revises governed project architecture through the conversation chat interface`
  - packaged live-governance suite:
    - `npm --prefix /Volumes/data/development/sbcl-agent-ux run test:journey:live-governance`
    - `10 passed (6.9m)`

### Iteration 25

- Closed the remaining late-suite journey regressions in the live Electron pack by updating stale UX assumptions rather than widening time budgets.
- Updated:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-sdlc-journey.spec.ts`
- Stabilized the final live test cluster around:
  - dashboard post-approval round-trips
  - conversation empty-state posture
  - browser manual-inspect posture
  - runtime/listener navigation
  - browser symbol/detail expectations
  - evidence/artifact empty-state projection
  - keyboard workspace switching
  - discard-image draft persistence checks
- The key shift was aligning tests to the current desktop contract:
  - explicit sidebar/workspace routing instead of older shortcut assumptions
  - current trust/overview copy instead of removed shell labels
  - current empty-state selection behavior in Conversations, Browser, and Evidence
  - desktop preference persistence checks where the composer is not necessarily mounted after relaunch
- Revalidated end to end with the packaged top-level journey entrypoint:
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run test:journey:full`
  - `test:journey` leg passed:
    - `76 passed (19.0m)`
  - `test:journey:sdlc` leg passed:
    - `6 passed (1.4m)`
  - `test:journey:live-governance` leg passed:
    - `10 passed (5.7m)`

### Iteration 26

- Closed the backend stability tranche that remained after the desktop journey chain was green.
- Updated:
  - `/Volumes/data/development/sbcl-agent/src/provider-protocol.lisp`
  - `/Volumes/data/development/sbcl-agent/src/retrieval-ranking.lisp`
  - `/Volumes/data/development/sbcl-agent/src/reconciliation-execution-service.lisp`
- Fixed two real backend issues:
  - retrieval ranking no longer tokenizes with quadratic string concatenation
  - retrieval ranking now bounds stringification of non-string dossier payloads locally instead of changing the provider summary contract
- Preserved the provider contract by keeping `provider-summary-content` pass-through semantics for non-string values.
- Fixed the continuous-alignment loop regression exposed by the full suite:
  - auto-materialized corrective work now requires an active current intent
  - plain sessions with incidents but no selected intent no longer create autonomous corrective governed work
- Revalidated in serial to avoid false negatives from parallel ASDF cache contention.
- Validation:
  - the deferred incident patch flow passed again:
    - `say-patch-action-deferred-by-incident-test`
  - the continuous-alignment loop contracts passed again:
    - `continuous-alignment-event-loop-service-contract-test`
    - `continuous-alignment-event-loop-reopens-after-resolution-test`
  - retrieval ranking coverage passed in the full serial backend run
  - full backend suite passed:
    - `./bin/run-tests`
    - `All tests passed.`

- Program completion after iteration: `97%`
- Next:
  - expand CAS beyond single-event corrective creation into richer repeated event-driven re-alignment coverage
  - harden longer-horizon backend scale characteristics now that the retrieval-ranking memory pathology is fixed

### Iteration 27

- Extended the Continuous Alignment System backend contracts from single-event corrective creation into repeated event-driven re-alignment over time.
- Updated:
  - `/Volumes/data/development/sbcl-agent/tests/service-contracts.lisp`
  - `/Volumes/data/development/sbcl-agent/tests/test-runner.lisp`
- Added two new lifecycle protections:
  - `continuous-alignment-event-loop-requires-active-intent-test`
    - proves the autonomous loop does not create corrective governed work when there is no active current intent
  - `continuous-alignment-event-loop-approval-resume-lifecycle-test`
    - proves the loop can:
      - create approval-gated corrective work from an event
      - survive explicit policy approval and resume
      - suppress duplicates while the earlier corrective item is still actionable
      - create a fresh corrective item after the earlier one is no longer actionable
- This complements the existing reopen-after-resolution coverage and closes the remaining repeated-event backend gap in the current CAS loop.
- Validation:
  - focused/full harness run passed with:
    - `./bin/run-tests continuous-alignment-event-loop-service-contract-test continuous-alignment-event-loop-reopens-after-resolution-test continuous-alignment-event-loop-requires-active-intent-test continuous-alignment-event-loop-approval-resume-lifecycle-test`
  - the run completed cleanly with:
    - `All tests passed.`

- Program completion after iteration: `98%`
- Next:
  - add end-to-end desktop journey coverage for repeated event-driven corrective reopening over time, not only the current single-event live proof
  - continue CAS scale hardening for longer-horizon retrieval/reconciliation workloads beyond the currently fixed ranking hotspot

### Iteration 28

- Added live desktop journey coverage for repeated event-driven corrective reopening over time.
- Updated:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
  - `/Volumes/data/development/sbcl-agent-ux/package.json`
- Added the new live CAS proof:
  - `reopens corrective governed work from later live runtime events after the earlier correction is no longer actionable`
- The live proof now validates the full reopened corrective lifecycle:
  - create an active deprecated intent through the desktop bridge
  - trigger a first live runtime event
  - observe autonomous corrective governed work creation
  - approve and resume that corrective work
  - prove a later event does not duplicate it while it is still actionable
  - terminalize the earlier corrective path
  - trigger a later runtime event
  - observe a fresh corrective governed work item and route back into approval review
- Hardened the live operator path while landing that coverage:
  - removed brittle approval-row title matching in favor of approval identity and work-routed review flow
  - aligned the assertions with the current desktop semantics:
    - resumed corrective work projects as `active`
    - rolled-back corrective work projects as `blocked`
    - the work detail surface renders `Corrective Direction`
- Validation:
  - focused live proof passed:
    - `./node_modules/.bin/playwright test /Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts -g "reopens corrective governed work from later live runtime events after the earlier correction is no longer actionable"`
    - `1 passed (27.6s)`
  - packaged live governance suite passed with the new CAS proof included:
    - `npm --prefix /Volumes/data/development/sbcl-agent-ux run test:journey:live-governance`
    - `11 passed (4.4m)`

- Program completion after iteration: `99%`
- Next:
  - return to the broader combined journey chain and CAS scale hardening so the repeated corrective lifecycle is covered in the wider top-level test pack, not only the live-governance package
  - continue longer-horizon retrieval/reconciliation load hardening beyond the ranking hotspot already fixed

### Iteration 29

- Revalidated the repeated-event CAS live proof inside the full packaged desktop journey chain, not only the focused and live-governance paths.
- Updated:
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
- Fixed the remaining combined-only dashboard expectation drift exposed during that broader run:
  - the default live Operate queue now projects `3` ranked items instead of `4`
  - the removed fourth expectation was the old alignment queue item that no longer appears after the active-intent CAS hardening
- Corrected the stale dashboard tests:
  - `suppresses derivative queue items when canonical recovery targets are present`
  - `keeps runtime recovery ahead of runtime listener stabilization in dashboard ordering`
- Validation:
  - focused dashboard shard passed:
    - `2 passed (18.8s)`
  - full packaged journey chain passed:
    - `npm --prefix /Volumes/data/development/sbcl-agent-ux run test:journey:full`
  - the successful clean run included:
    - the mock/live desktop journey leg
    - the SDLC journey leg
    - the live-governance leg with the repeated corrective reopening proof

- Program completion after iteration: `99%`
- Next:
  - continue CAS scale hardening for longer-horizon retrieval, reconciliation, and repeated alignment workloads
  - broaden repeated event-driven alignment coverage beyond the current live journey set into heavier, longer-running backend and desktop sequences

### Iteration 30

- Extended backend CAS lifecycle coverage from a single reopen-after-resolution sequence into a longer-horizon multi-reopen sequence.
- Updated:
  - `/Volumes/data/development/sbcl-agent/tests/service-contracts.lisp`
  - `/Volumes/data/development/sbcl-agent/tests/test-runner.lisp`
- Added:
  - `continuous-alignment-event-loop-multi-reopen-lifecycle-test`
- The new contract now proves:
  - a first trigger creates approval-gated corrective work
  - approval and resume keep that corrective work actionable
  - later triggers still suppress duplicates while it remains actionable
  - once the first corrective item is terminalized, a second trigger reopens a fresh corrective item
  - the same suppression and reopen behavior holds again across a second full cycle
  - a third trigger after the second resolution creates a third corrective item and emits a third corrective creation event
- Validation:
  - the continuous-alignment contract cluster passed with the new multi-reopen test included
  - the full backend suite passed cleanly:
    - `./bin/run-tests`
    - `All tests passed.`

- Program completion after iteration: `99%`
- Next:
  - continue CAS scale hardening for longer-horizon retrieval, reconciliation, and repeated alignment workloads
  - broaden repeated event-driven alignment coverage beyond the current backend/live journey set into heavier long-running desktop sequences

### Iteration 31

- Simplified the Operate `Orientation` surface so it no longer starts with the redundant top-level `Operate Snapshot` block.
- Updated:
  - `/Volumes/data/development/sbcl-agent-ux/src/renderer/src/operate-workspace.tsx`
  - `/Volumes/data/development/sbcl-agent-ux/tests/ui/electron-live.spec.ts`
- The change is intentionally scoped:
  - the overview panel is now hidden for `Orientation`
  - the `Journeys` and `Evidence` operate views still retain the shared overview card where it remains useful
- This removes the low-value duplicate environment summary and makes Orientation open directly on:
  - `Orientation Records`
  - the selected detail panel
  - explicit trust/control actions
- Validation:
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run typecheck` passed
  - `npm --prefix /Volumes/data/development/sbcl-agent-ux run build` passed
  - focused Operate regressions passed:
    - `surfaces live alignment and corrective direction in operate and projects`
    - `keeps dashboard trust and direct actions coherent after a recovery round-trip`

- Program completion after iteration: `99%`
- Next:
  - continue CAS scale hardening for longer-horizon retrieval, reconciliation, and repeated alignment workloads
  - keep trimming low-value duplicate trust/orientation summaries where they do not improve operator control
