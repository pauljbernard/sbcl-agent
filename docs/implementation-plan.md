---
layout: default
title: Implementation Plan
hero_title: Implementation Plan
hero_text: "The program now has two linked tracks: preserve the transactional, workflow-governed SBCL core and complete the move from streamed ask to a persistent conversation runtime."
eyebrow: Roadmap
permalink: /implementation-plan.html
description: Detailed implementation roadmap for sbcl-agent.
---
## North Star

`sbcl-agent` should deliver Codex-class software engineering usefulness while using a different internal architecture:

- Common Lisp all the way down
- an inspectable and mutable SBCL image
- explicit source truth, image truth, and workflow truth
- governed execution rather than hidden side effects
- conversation-native interaction on top of the same runtime

The target is not parity in implementation detail. The target is parity or advantage in operator outcomes.

## Program Structure

The work is best understood as two coordinated programs.

### 1. Transactional live-image program

This is the original architectural thesis:

- bounded work-items
- checkpointing and rollback intent
- validation, replay, and reconciliation
- provenance and operator-visible evidence

### 2. Conversation runtime program

This is the newer interaction-layer program:

- threads, messages, turns, operations, and artifacts
- event-native streaming
- approval-aware turn orchestration
- durable conversational context
- REPL mode and conversation mode on one runtime

The second program does not replace the first. It gives the first a better operator contract.

## Current Status Snapshot

Implemented or substantially in place:

- SBCL-native CLI and Common Lisp shell
- provider abstraction with mock and OpenAI-compatible backends
- canonical provider-event normalization
- thread, message, turn, operation, and artifact records
- shell commands for `say`, thread management, turn status, and turn resume
- shared `ask` and `say` turn execution with `ask` kept as the REPL-bridge compatibility path
- approval-aware turn orchestration
- governed mutation binding for patch turns, mutating runtime eval turns, and write-class tool turns
- provider follow-up after resumed turns when the provider supports turn continuation
- richer shell rendering for turn status and turn resume results
- session persistence, tasks, workers, work-items, replay groups, and image reconciliation records

Still incomplete or still planned:

- a fully separated internal conversation/runtime/engineering state model
- richer operation and artifact coverage across all mutating paths
- runtime tool families for governed image inspection and mutation
- stronger crash recovery and resumability
- deeper cold-start validation and rollback fidelity

## Delivery Stages

### Stage 0. Documentation and design lock

Status: largely complete

Deliverables:

- architecture and rationale docs aligned with the three-truth model
- conversation-runtime blueprint
- streaming event model
- migration plan
- implementation plan tied to real source modules

Exit condition:

- public terminology is stable enough to implement against

### Stage 1. Event-native streaming foundation

Status: partially implemented

Already in place:

- canonical provider event structures and normalization in the provider layer
- shell support for event-driven streamed behavior
- compatibility with the existing streamed `ask` flow

Remaining work:

- eliminate remaining transitional in-band control behavior in provider integrations
- harden event replay and renderer separation
- broaden event coverage for operations and workflow evidence

Exit condition:

- assistant text, operation intents, approval states, and artifact signals all flow as explicit sibling events

### Stage 2. Thread and turn persistence

Status: materially implemented

Already in place:

- `thread`, `message`, `turn`, `operation`, and `artifact` records
- shell commands for thread creation, listing, switching, and inspection
- `say` as the conversation-first operator command
- turn inspection and resume commands

Remaining work:

- further decouple conversation state from the older flat session shape
- expand persistence versioning and migration behavior
- strengthen interrupted-turn recovery semantics

Exit condition:

- thread and turn state survive restart cleanly and old session compatibility remains reliable

### Stage 3. Turn orchestrator

Status: partially implemented

Already in place:

- a dedicated turn orchestration module
- turn creation, streaming, action recording, policy handling, and completion flow
- approval-aware pause and resume behavior
- provider follow-up after resumed mutation turns, including follow-up event visibility

Remaining work:

- richer multi-step provider follow-up loops with fuller structured operation/result payloads
- stronger operation-state transitions and artifact finalization
- clearer separation between conversation orchestration and shell rendering

Exit condition:

- one turn can stream, dispatch operations, pause, resume, and complete with durable evidence

### Stage 4. Runtime tool family

Status: planned

Goal:

- expose governed image-native operations such as runtime inspection, package control, and controlled evaluation as explicit tools rather than incidental shell effects

Expected deliverables:

- `src/tools-runtime.lisp`
- runtime-specific capability classes
- work-item-aware policies for mutating runtime operations

### Stage 5. Artifact and workflow bridge

Status: partially implemented conceptually, incomplete operationally

Already in place:

- artifact records linked to turns and operations
- existing workflow structures for validation, replay, and reconciliation
- work-item creation and checkpointing for governed mutation turns

Remaining work:

- emit and attach richer artifacts for file writes, diffs, tests, checkpoints, and validations
- make every governed mutating turn attach consistently to work-items and workflow records
- improve operator rendering of evidence

### Stage 6. Operator UX refinement

Status: in progress

Goal:

- make conversation mode feel coherent without weakening the fast REPL path

Work includes:

- better shell rendering
- concise turn summaries
- clearer approval prompts
- better artifact summaries
- improved session and thread visibility

### Stage 7. Hardening and recovery

Status: planned

Goal:

- make the conversation runtime durable under interruption, long turns, partial failures, and workflow-heavy mutation sessions

Work includes:

- crash recovery
- resumability tests
- interrupted-operation handling
- concurrency and worker-pool interaction tests
- stronger cold-start reproducibility checks after chat-driven edits

## Architectural Priorities

The sequencing matters.

1. Stabilize event and turn semantics before adding more provider cleverness.
2. Keep orchestration in Lisp rather than in prompt conventions.
3. Preserve REPL compatibility while making conversation first-class.
4. Route mutating behavior through workflow evidence rather than letting chat bypass governance.
5. Improve rollback, replay, and reproducibility before chasing aggressive multi-agent parallelism.

## File-Level Map

Current key implementation files:

- [`src/provider-protocol.lisp`](/Volumes/data/development/sbcl-agent/src/provider-protocol.lisp)
- [`src/provider-openai.lisp`](/Volumes/data/development/sbcl-agent/src/provider-openai.lisp)
- [`src/provider-mock.lisp`](/Volumes/data/development/sbcl-agent/src/provider-mock.lisp)
- [`src/events.lisp`](/Volumes/data/development/sbcl-agent/src/events.lisp)
- [`src/session.lisp`](/Volumes/data/development/sbcl-agent/src/session.lisp)
- [`src/shell.lisp`](/Volumes/data/development/sbcl-agent/src/shell.lisp)
- [`src/commands.lisp`](/Volumes/data/development/sbcl-agent/src/commands.lisp)
- [`src/conversation.lisp`](/Volumes/data/development/sbcl-agent/src/conversation.lisp)
- [`src/turn-orchestrator.lisp`](/Volumes/data/development/sbcl-agent/src/turn-orchestrator.lisp)
- [`src/policy.lisp`](/Volumes/data/development/sbcl-agent/src/policy.lisp)
- [`src/tasks.lisp`](/Volumes/data/development/sbcl-agent/src/tasks.lisp)
- [`src/work-items.lisp`](/Volumes/data/development/sbcl-agent/src/work-items.lisp)
- [`src/workflow.lisp`](/Volumes/data/development/sbcl-agent/src/workflow.lisp)

Likely future additions:

- `src/tools-runtime.lisp`
- a richer artifact bridge module if the current artifact support outgrows `conversation.lisp`
- optional renderer-specific modules if shell presentation becomes more layered

## Risks To Manage

### Too much orchestration in prompts

Mitigation:

- keep control flow in Lisp, not in prompt text

### Conversation state becoming a second session database

Mitigation:

- keep conversation, runtime, and workflow ownership boundaries explicit

### Chat-driven runtime mutation bypassing governance

Mitigation:

- require policy checks, approval checkpoints, and work-item-aware controls for mutating operations

### Rich shell rendering becoming more complex than the runtime itself

Mitigation:

- keep the event model canonical and renderers thin

## Practical Outcome

When this program is complete, the project should feel like:

- a persistent conversation runtime
- backed by a live SBCL image
- with REPL access still available
- and with governed engineering execution preserved as a first-class concern

That is the right next state for this codebase because the hard architectural core already exists. The remaining work is to finish aligning the interaction model, evidence model, and runtime controls around it.
