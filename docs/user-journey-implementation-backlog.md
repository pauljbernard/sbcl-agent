---
layout: default
title: User Journey Implementation Backlog
hero_title: User Journey Implementation Backlog
hero_text: A prioritized, executable backlog derived from the user-journey gap matrix and aligned to the environment-first architecture.
eyebrow: Execution
permalink: /user-journey-implementation-backlog.html
description: Prioritized epics, file targets, acceptance criteria, and iteration order for closing the highest-value user-journey gaps.
---

## Purpose

This document converts the [User Journey Gap Matrix](/Volumes/data/development/sbcl-agent/docs/user-journey-gap-matrix.md) into an implementation backlog that can be executed incrementally.

It is intentionally narrower than the full [Implementation Plan](/Volumes/data/development/sbcl-agent/docs/implementation-plan.md). The implementation plan describes the whole program. This backlog describes the next user-journey-driven slice of work.

## Backlog Principles

The backlog follows five rules:

1. Improve coherence before adding breadth.
2. Strengthen the environment model before introducing full agent-mode behavior.
3. Prefer user-visible closure surfaces over additional hidden state.
4. Preserve REPL directness while deepening environment-native services.
5. Ship each epic with tests and documentation updates.

## Priority Order

The current execution order should be:

1. Environment Orientation Surface
2. Mutation Closure Surface
3. Symbolic Runtime Navigation
4. Incident Recovery Workspace
5. Uniform Artifact Surfacing
6. Environment-First Composition Tightening

Agent-mode work should remain deferred until the first four backlog items are materially implemented.

## Epic 1. Environment Orientation Surface

### User Journey Problem

The user can enter the system, but they do not yet land in a clearly legible environment state. The experience still feels like “starting a tool” rather than “entering a world.”

### Goal

Deliver one default orientation surface that answers:

1. What environment is active?
2. What thread is active?
3. What runtime is active?
4. What work is blocked?
5. What incidents are open?
6. What approvals or validations are outstanding?

### Likely Files

- [src/environment.lisp](/Volumes/data/development/sbcl-agent/src/environment.lisp)
- [src/session.lisp](/Volumes/data/development/sbcl-agent/src/session.lisp)
- [src/shell.lisp](/Volumes/data/development/sbcl-agent/src/shell.lisp)
- [src/commands.lisp](/Volumes/data/development/sbcl-agent/src/commands.lisp)
- [docs/user-guide.md](/Volumes/data/development/sbcl-agent/docs/user-guide.md)

### Likely Commands / Surfaces

- `(environment/status)`
- optional richer default output for `doctor`
- optional shell entry banner tied to active environment state

### Acceptance Criteria

- a single command returns environment identity, active thread, active runtime, blocked work-item count, open incident count, and operator posture
- shell users do not need multiple commands to answer “where am I and what needs attention?”
- docs show this as the default orientation pattern

### Tests To Add

- `environment-status-command-test`
- `environment-status-blocked-work-summary-test`
- `environment-status-incident-summary-test`

## Epic 2. Mutation Closure Surface

### User Journey Problem

Governed mutation is rigorous but still too architecture-dependent for the operator. The user often needs to combine turn, incident, work-item, and wait-state views mentally.

### Goal

Provide one mutation-review surface that explains:

- what changed
- what work-item governs it
- what evidence exists
- what is still blocked
- what specific next action closes the loop

### Likely Files

- [src/work-items.lisp](/Volumes/data/development/sbcl-agent/src/work-items.lisp)
- [src/turn-orchestrator.lisp](/Volumes/data/development/sbcl-agent/src/turn-orchestrator.lisp)
- [src/incidents.lisp](/Volumes/data/development/sbcl-agent/src/incidents.lisp)
- [src/conversation.lisp](/Volumes/data/development/sbcl-agent/src/conversation.lisp)
- [src/shell.lisp](/Volumes/data/development/sbcl-agent/src/shell.lisp)

### Likely Commands / Surfaces

- `(review/mutation)`
- `(review/mutation "turn-id")`
- or a richer `(turn/status)` extension if that proves cleaner

### Acceptance Criteria

- the user can inspect one governed mutation and see mutation summary, artifacts, work-item status, wait reason, incident linkage, and next action in one place
- `:awaiting-cold-validation` and operator-review-required states are explicitly legible
- resumed follow-up paths remain visible after approval or validation completion

### Tests To Add

- `mutation-review-command-test`
- `mutation-review-cold-validation-test`
- `mutation-review-incident-linked-test`

## Epic 3. Symbolic Runtime Navigation

### User Journey Problem

The runtime is live and governable, but symbolic navigation is still thinner than the long-term Common Lisp environment vision requires.

### Goal

Expose richer environment-native symbolic services without drifting into IDE metaphors.

### Scope

- package navigation
- symbol lookup
- definition lookup
- method and caller relationships
- source/image divergence visibility

### Likely Files

- [src/tools-runtime.lisp](/Volumes/data/development/sbcl-agent/src/tools-runtime.lisp)
- [src/environment.lisp](/Volumes/data/development/sbcl-agent/src/environment.lisp)
- optional new modules:
  - `src/runtime-services.lisp`
  - `src/symbol-graph.lisp`

### Likely Commands / Surfaces

- `(runtime/find-definition "symbol")`
- `(runtime/callers "symbol")`
- `(runtime/methods "generic-function")`
- `(runtime/source-image-divergence "symbol")`

### Acceptance Criteria

- users can navigate the live image semantically instead of relying only on raw eval and ad hoc inspection
- the shell exposes these as explicit services rather than editor-style metaphors
- source/image divergence is inspectable as an environment-native concept

### Tests To Add

- `runtime-find-definition-test`
- `runtime-callers-test`
- `runtime-methods-test`
- `runtime-source-image-divergence-test`

## Epic 4. Incident Recovery Workspace

### User Journey Problem

`incident/show` is structurally good but still shallow as a runtime debugging experience.

### Goal

Expand incidents into richer runtime recovery workspaces that support understanding and remediation, not just evidence review.

### Scope

- richer captured context
- possible restart suggestions
- recovery plan artifacts
- explicit relation between incident and remediation path

### Likely Files

- [src/incidents.lisp](/Volumes/data/development/sbcl-agent/src/incidents.lisp)
- [src/tools-runtime.lisp](/Volumes/data/development/sbcl-agent/src/tools-runtime.lisp)
- [src/work-items.lisp](/Volumes/data/development/sbcl-agent/src/work-items.lisp)
- [src/shell.lisp](/Volumes/data/development/sbcl-agent/src/shell.lisp)

### Acceptance Criteria

- incident inspection includes richer captured runtime context when available
- the user can see a recommended remediation path, not only a linked failure graph
- recovery steps can become explicit artifacts or governed follow-up operations

### Tests To Add

- `incident-workspace-runtime-context-test`
- `incident-recommended-recovery-test`
- `incident-recovery-artifact-test`

## Epic 5. Uniform Artifact Surfacing

### User Journey Problem

Artifact generation is improving, but still strongest in thread-bound and conversation-bound paths.

### Goal

Broaden artifact surfacing so important evidence is visible regardless of how the governed work was initiated.

### Scope

- non-thread-bound validations
- reconciliation outcomes
- environment-level evidence objects
- richer mutation summary artifacts

### Likely Files

- [src/conversation.lisp](/Volumes/data/development/sbcl-agent/src/conversation.lisp)
- [src/work-items.lisp](/Volumes/data/development/sbcl-agent/src/work-items.lisp)
- [src/environment.lisp](/Volumes/data/development/sbcl-agent/src/environment.lisp)
- [src/session.lisp](/Volumes/data/development/sbcl-agent/src/session.lisp)

### Acceptance Criteria

- validation and reconciliation evidence no longer depends so heavily on thread-bound execution
- artifact listings better reflect the real governed history of work
- environment-level summaries include richer evidence counts and kinds

### Tests To Add

- `non-thread-validation-artifact-test`
- `environment-level-evidence-summary-test`
- `reconciliation-artifact-coverage-test`

## Epic 6. Environment-First Composition Tightening

### User Journey Problem

Persistence and orientation are good, but the internal architecture still often thinks through `agent-session` first and `environment` second.

### Goal

Keep compatibility, but continue reducing the gap between the documented center of gravity and the implemented one.

### Likely Files

- [src/environment.lisp](/Volumes/data/development/sbcl-agent/src/environment.lisp)
- [src/environment-store.lisp](/Volumes/data/development/sbcl-agent/src/environment-store.lisp)
- [src/session.lisp](/Volumes/data/development/sbcl-agent/src/session.lisp)
- [src/provider-protocol.lisp](/Volumes/data/development/sbcl-agent/src/provider-protocol.lisp)
- [src/shell.lisp](/Volumes/data/development/sbcl-agent/src/shell.lisp)

### Acceptance Criteria

- more core flows resolve environment state first
- compatibility-session bridging remains present but is less architecturally central
- provider and shell summaries increasingly reflect environment-owned state directly

### Tests To Add

- `environment-first-binding-test`
- `environment-provider-context-precedence-test`
- `environment-load-shell-orientation-test`

## Suggested Iteration Plan

## Iteration 1

Focus:

- Epic 1: Environment Orientation Surface
- Epic 2: Mutation Closure Surface

Exit criteria:

- one command answers “where am I?”
- one command answers “what closes this governed mutation?”

## Iteration 2

Focus:

- Epic 3: Symbolic Runtime Navigation

Exit criteria:

- package, definition, method, and caller navigation exists as explicit environment-native services

## Iteration 3

Focus:

- Epic 4: Incident Recovery Workspace

Exit criteria:

- incidents move from compact evidence views toward remediation-oriented runtime workspaces

## Iteration 4

Focus:

- Epic 5: Uniform Artifact Surfacing
- Epic 6: Environment-First Composition Tightening

Exit criteria:

- artifact evidence is less path-dependent
- more operator-facing behavior is clearly environment-centered

## Deferred Work

These should remain deferred until the backlog above is materially advanced:

- full resident agent / multi-actor model
- broad editor-style affordances
- UI expansion beyond the shell

The reason is architectural discipline: the environment must become legible and trustworthy before it becomes crowded.

## Practical Use

This backlog should be used as the planning filter for the next implementation phase.

When evaluating a proposed change, ask:

1. Which user journey does this improve?
2. Does it reduce friction in inhabiting the environment?
3. Does it strengthen environment identity, runtime legibility, or governed closure?
4. Is it more important than the current higher-priority epic?

If the answer to those questions is weak, the work is probably premature.
