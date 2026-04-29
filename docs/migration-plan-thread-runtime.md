---
layout: default
title: Thread Runtime Migration Plan
hero_title: Thread Runtime Migration Plan
hero_text: The migration path preserves the current shell and session model while progressively adding thread-based conversation, now understood as one subsystem within a larger Environment architecture.
eyebrow: Blueprint
permalink: /migration-plan-thread-runtime.html
description: Migration strategy for adding a thread-based conversation subsystem to sbcl-agent.
---
## Migration Constraints

The migration must preserve the current strengths of the repo:

- direct Lisp evaluation remains available
- `(ask ...)`, `(tool ...)`, and other existing shell commands keep working
- session persistence remains readable
- work-items and workflow records remain authoritative for governed engineering work

The conversation runtime is an insertion, not a destructive rewrite.

This document should now be read as a subsystem migration plan rather than as the whole architectural roadmap. The newer roadmap vision places conversation inside a larger Environment model that also includes runtimes, agents, artifacts, work-items, policies, and histories.

## Current Baseline

The repo is already mid-migration.

Implemented now:

- canonical provider-event normalization
- conversation records for threads, messages, turns, operations, and artifacts
- shell commands for thread management and conversation turns
- turn status and resume handling
- turn orchestration with approval-aware flow
- incident recording for failed governed runtime actions
- environment-aware summaries and projected environment events that preserve thread-runtime migration compatibility
- environment-first rehydration of transcript/events, conversation records, workflow records, incident state, staged actions, tasks/workers, capability grants, and plan state from persisted Environment domains

Still legacy-shaped:

- the shell still carries some original `ask` and staged-action assumptions
- top-level mutable state is still centered on `agent-session`
- provider integrations still include compatibility behavior for older streaming paths

## Migration Sequence

### Phase 0. Design lock

Status: complete enough to build against

Delivered:

- conversation architecture doc
- streaming event model
- migration plan
- updated implementation plan and architecture docs

### Phase 1. Event-native streaming foundation

Status: partially complete

Done:

- canonical provider-event normalization
- shell integration with canonical events
- compatibility with current streamed `ask`

Remaining:

- remove remaining transitional in-band control behavior
- extend event coverage across more operation and workflow paths

### Phase 2. Thread and turn persistence

Status: materially complete

Done:

- thread, message, turn, operation, and artifact records
- default-thread shell behavior
- thread commands and `say`
- turn status and resume commands

Remaining:

- strengthen persistence versioning
- improve interrupted-turn recovery semantics
- further disentangle conversation state from legacy transcript/session assumptions

### Phase 3. Turn orchestrator

Status: partially complete

Done:

- dedicated turn-orchestration module
- streaming and sync turn execution paths
- policy-aware action handling
- resumable approval flow

Remaining:

- fuller provider follow-up loops with structured operation results
- cleaner operation state machine coverage
- richer artifact finalization

### Phase 4. Governed runtime operations

Status: implemented, still expandable

Target:

- expose runtime inspection and mutation as explicit, capability-gated operations rather than incidental shell behavior

Delivered now:

- governed runtime package switching
- governed runtime eval with safe and mutating policy modes
- governed runtime file reload
- runtime history inspection

Remaining:

- deeper runtime inspection and symbolic navigation services

### Phase 5. Artifact and workflow bridge

Status: planned but partly foreshadowed by current artifact records

Target:

- attach file, diff, validation, checkpoint, and reconciliation outputs consistently to turns, operations, and work-items

### Phase 6. UX and recovery hardening

Status: planned

Target:

- make conversation mode feel cohesive
- keep REPL mode fast and direct
- recover interrupted state cleanly

## Compatibility Shims

### `ask`

`ask` remains supported while the runtime becomes more thread-oriented. It should continue to work as the older operator-facing compatibility surface even as `say` becomes the cleaner conversation command.

### Session APIs

Commands such as `describe-session`, `session/save`, and `session/load` remain valid. Internally they should increasingly act as wrappers over a more compositional runtime state model.

The persistence layer is now already moving in that direction:

- Environment is the durable object
- the compatibility session is reconstructed from Environment state at load time
- the serialized compatibility payload has been reduced to an identity-oriented shim instead of a duplicate session snapshot
- even legacy session header fields are reconstructed from Environment-owned runtime and conversation state rather than persisted inside the compatibility payload

### Direct Lisp evaluation

Unrecognized forms must continue to evaluate as normal Lisp. This is a hard compatibility requirement, not an optional convenience.

## Persistence Strategy

The migration should remain versioned and non-destructive.

Recommended rules:

1. Keep existing session files readable.
2. Synthesize conversation state when older persistence lacks explicit threads.
3. Preserve legacy transcript or event material when exact mapping is not possible.
4. Write back only after successful normalization into the newer model.

Current implementation note:

- environment persistence now derives `cwd`, `package`, `current-thread-id`, plan state, grant state, pending actions, tasks/workers, incidents, conversation records, workflow records, transcript, and event history from Environment-owned domains during load
- this means compatibility-session persistence is no longer the main truth path and should be treated as an adapter layer

## Risks

### State drift

If thread history becomes a second copy of runtime or workflow truth, the architecture will become inconsistent.

Mitigation:

- keep conversation records referential
- keep runtime and workflow state authoritative in their own domains

### Prompt-defined control flow

If orchestration logic drifts into prompt conventions, behavior will become fragile and provider-specific.

Mitigation:

- keep orchestration in Lisp and events

### Unsafe chat-driven mutation

Mitigation:

- use explicit policies, approvals, and workflow attachment for mutating behavior

## End State

The migration is complete when `sbcl-agent` supports:

- REPL mode for direct, Lisp-native request-response work
- conversation mode for persistent thread-based interaction

on one shared SBCL runtime, with workflow records still governing mutating engineering activity.

The migration should also end with one conceptual inversion fully in place:

- Environment is primary durable truth
- session compatibility is derived from Environment, not the other way around
