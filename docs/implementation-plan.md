---
layout: default
title: Implementation Plan
hero_title: Implementation Plan
hero_text: "The program now has a broader target: preserve the transactional, workflow-governed SBCL core while re-centering the architecture around an Environment object that contains runtimes, threads, agents, artifacts, and work-items."
eyebrow: Roadmap
permalink: /implementation-plan.html
description: Detailed implementation roadmap for sbcl-agent.
---
## Reading Position

This is a roadmap document, not an entry point.

Read [The Problem]({{ '/problem.html' | relative_url }}), [Foundation]({{ '/foundation.html' | relative_url }}), and [Architecture]({{ '/architecture.html' | relative_url }}) first if you want to understand the system before reading planned work.

## North Star

`sbcl-agent` should deliver Codex-class software engineering usefulness while using a different internal architecture:

- Common Lisp all the way down
- an inspectable and mutable SBCL image
- explicit source truth, image truth, and workflow truth
- governed execution rather than hidden side effects
- conversation-native interaction as one subsystem inside a larger environment

The target is not parity in implementation detail. The target is parity or advantage in operator outcomes.

## Program Structure

The work is now best understood as three coordinated programs.

The user-facing prioritization filter for these programs is captured in [User Journey Gap Matrix]({{ '/user-journey-gap-matrix.html' | relative_url }}), which evaluates the implemented system against the operator journeys implied by the objectives and vision.

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

### 3. Environment architecture program

This is the new program established by the roadmap vision:

- introduce a concrete Environment object
- treat runtimes, threads, agents, artifacts, and work-items as native environment entities
- move from session-centered composition to environment-centered composition
- make conversation one native medium of control rather than the whole architectural story
- translate the enduring powers of classic Lisp tooling into environment-native services instead of rebuilding legacy IDE surfaces

## Current Status Snapshot

This section should be read literally. It distinguishes implemented behavior from direction, because the project is now mature enough that overstating the roadmap would make the docs less trustworthy, not more.

Implemented or substantially in place:

- SBCL-native CLI and Common Lisp shell
- provider abstraction with mock and OpenAI-compatible backends
- canonical provider-event normalization
- concrete `Environment` object with save/load, summaries, and projected environment events
- thread, message, turn, operation, and artifact records
- shell commands for `say`, thread management, turn status, and turn resume
- shell commands for incident inspection, environment inspection, and environment event inspection
- shared `ask` and `say` turn execution with `ask` kept as the REPL-bridge compatibility path
- approval-aware turn orchestration
- governed mutation binding for patch turns, mutating runtime eval turns, and write-class tool turns
- provider follow-up after resumed turns when the provider supports turn continuation
- runtime commands for current package, loaded systems, symbol description, governed eval, history, and reload
- incident recording, quarantine-aware failure handling, and incident-aware operator summaries
- incident workspace-style inspection through `incident/show`, with linked turn, operation, work-item, and workflow summaries plus compact recovery and wait guidance
- richer shell rendering for turn status and turn resume results
- shell rendering that distinguishes resumable approval recovery from interrupted recovery
- session persistence, tasks, workers, work-items, replay groups, and image reconciliation records
- load-time interruption recovery for persisted in-flight turns and operations
- governed runtime mutation flows that stop at `:awaiting-cold-validation` until colder evidence is recorded
- provider requests enriched with compact environment-backed context
- validation and image-reconciliation artifact emission for thread-bound work-items, so governance evidence is visible in the artifact stream
- a real execution-kernel seam through `src/kernel-core.lisp`, `src/kernel-service.lisp`, and `src/shell-service.lisp`
- execution-handle-centered inspect/control behavior and execution-native shell commands
- execution surfaces, shell workspace, governance queue, object browser, inspector, and desktop host model
- compatibility app registry, Linux app execution, lifecycle posture, relaunch, and shell-visible display-surface bridging through the compatibility kernel
- developer-platform manifests and `.aop` package lifecycle flows including export, validation, import, activate, install, applied profile query, audit, history, harness, and package-provided compatibility app extension

Still enhancement-oriented or still planned:

- a fully separated internal conversation/runtime/engineering state model
- an explicit agent registry and environment-level resident actor model
- a capability-translation layer that preserves legacy Lisp tool powers without reproducing their architectural metaphors
- richer operation and artifact coverage across all mutating paths
- deeper cold-start validation and rollback fidelity
- deeper incident workspace and restart-oriented runtime debugging services
- broader alternative compatibility backends beyond the current governed host-process implementation
- fuller ecosystem/distribution depth for the platform layer beyond the now-implemented core package contract

## Architectural Conformance

Against the accepted [IntentOS target-state architecture]({{ '/agentos-target-state-architecture.html' | relative_url }}), the current codebase now satisfies the target architectural contract.

What remains after this point is best understood as:

- enhancement
- hardening
- distribution work
- alternative backend evolution

not unresolved current-vs-target architecture gaps.

## Delivery Stages

### Stage 0. Documentation and design lock

Status: largely complete, with continuing consistency cleanup

Deliverables:

- architecture and rationale docs aligned with the three-truth model
- environment vision and model
- capability translation matrix from legacy Lisp tool functions to environment primitives
- conversation-runtime blueprint, now reframed as one subsystem
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
- a shared event-envelope contract with explicit correlation metadata for environment, session, run, operation, work-item, artifact, and incident identity
- streamed provider events correlated to provider-run operations and active thread/turn identity before entering the session/environment event log
- workflow and incident milestone events correlated to work-item and workflow-record identity for validation, reconciliation, quarantine, resume, closure, and incident capture paths
- environment-backed event summaries available to session-facing summary and event tools, reducing duplicate evidence assembly across session/environment views
- consolidated operator-evidence bundles available to environment/session status surfaces, reducing renderer-side reconstruction of posture, blocked work, and incidents
- workflow monitoring summaries (wait state, replay groups, reconciliations) reading environment workflow state first with compatibility fallback when environment monitoring state is not yet materialized
- task and worker monitoring reads preferring environment agent state when authoritative, reducing dependence on session-owned task/worker lists for monitoring surfaces
- task and worker mutation paths immediately refreshing the bound environment agent domain after enqueue, cancel, execution, worker start, worker stop, and stop-all-workers, reducing reliance on later read-time resynchronization
- artifact summaries, lookup, and thread/turn artifact inspection preferring environment-owned artifact state when a session is bound, reducing dependence on duplicated compatibility-session artifact lists
- serializable environments preserving payload-only compatibility identity even without a materialized session, and load paths normalizing legacy embedded `agent-session` compatibility state down to payload form at the persistence boundary
- provider session/runtime/workspace/policy summaries resolving from one environment snapshot per request whenever a bound environment exists, with direct session fallbacks limited to the no-environment path and request-local transcript context
- provider default thread/turn context resolving from environment conversation state when a bound environment exists, with conversation-domain refresh updating full conversation records rather than only aggregate counters

Remaining work:

- eliminate remaining transitional in-band control behavior in provider integrations
- harden event replay and renderer separation
- broaden event coverage for operations and workflow evidence

Exit condition:

- assistant text, operation intents, approval states, and artifact signals all flow as explicit sibling events

### Stage 2. Thread and turn persistence

Status: implemented

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

### Stage 3.5. Environment composition root

Status: implemented, still being refined

Goal:

- introduce a concrete Environment object that becomes the primary architectural container

Delivered now:

- environment creation, load, save, and inspection APIs
- projected environment event log plus `environment/events`
- environment-aware shell, summary, and provider context integration
- environment-first shell entry and load rendering, so operators are oriented around environment identity and posture before compatibility-session detail

Remaining:

- further reduce architectural dependence on `agent-session` as implicit primary truth
- broaden environment-native APIs beyond the compatibility bridge

The remaining gap here is now narrower than when this stage was first written. Environment-native summaries, events, workflow monitoring, artifact inspection, provider request assembly, and default provider thread/turn context all now prefer environment-owned state when available. What remains is less about basic authority and more about finishing the operator and API surfaces that still speak through compatibility-session adapters.

Recent tightening:

- runtime and conversation domain logic now have explicit module homes in `src/runtime-state.lisp` and `src/conversation-state.lisp`
- environment summary and orientation paths consume those domain summary helpers instead of rebuilding runtime and conversation summaries entirely inside `src/environment.lisp`
- workflow and artifact domain logic now also have explicit module homes in `src/workflow-state.lisp` and `src/artifact-state.lisp`
- environment evidence and workflow summaries now consume those domain helpers instead of depending on mixed inline summary logic in `src/environment.lisp`
- session-facing summary and event tools now act more clearly as compatibility facades over bound environment state instead of assuming the session is always the primary inspection root

Expected deliverables:

- references to runtime set, thread set, artifact graph, work-item graph, policy engine, event bus, and agent registry
- a compatibility path where `agent-session` becomes a transitional component inside the Environment rather than the top-level concept

### Stage 4. Capability translation from legacy Lisp tooling

Status: now explicitly required

Goal:

- preserve the enduring powers of classic Common Lisp environments without rebuilding their legacy IDE metaphors

Expected deliverables:

- direct eval as a governed execution substrate rather than only a text listener
- debugging reframed as runtime incident and recovery workflow
- symbolic and source navigation reframed as environment graph traversal
- inspection reframed as queryable runtime/object graph access
- validation and compiler feedback reframed as continuous mutation feedback
- optional compatibility affordances kept separate from the architectural center

### Stage 5. Runtime tool family

Status: implemented, still expandable

Goal:

- expose governed image-native operations such as runtime inspection, package control, and controlled evaluation as explicit tools rather than incidental shell effects

Delivered now:

- `src/tools-runtime.lisp`
- runtime-specific capability classes
- work-item-aware policies for mutating runtime operations
- shell commands for package inspection, loaded-system listing, symbol description, governed eval, history, and reload

Remaining:

- deeper symbolic navigation such as definition/caller discovery
- richer runtime incident and debugger-style inspection services

### Stage 6. Artifact and workflow bridge

Status: partially implemented conceptually, incomplete operationally

Already in place:

- artifact records linked to turns and operations
- existing workflow structures for validation, replay, and reconciliation
- work-item creation and checkpointing for governed mutation turns

Remaining work:

- emit and attach richer artifacts for file writes, diffs, tests, checkpoints, and validations
- make every governed mutating turn attach consistently to work-items and workflow records
- improve operator rendering of evidence

### Stage 7. Operator UX refinement

Status: in progress

Goal:

- make conversation mode feel coherent without weakening the fast REPL path

Work includes:

- better shell rendering
- concise turn summaries
- clearer approval prompts
- better artifact summaries
- improved session and thread visibility
- better environment-level visibility across runtimes, threads, agents, artifacts, and work-items

### Stage 8. Hardening and recovery

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

1. Introduce the Environment object before the architecture fragments further around legacy session boundaries.
2. Stabilize event and turn semantics before adding more provider cleverness.
3. Keep orchestration in Lisp rather than in prompt conventions.
4. Preserve REPL compatibility while making conversation first-class without mistaking it for the whole system.
5. Route mutating behavior through workflow evidence rather than letting chat or agents bypass governance.
5. Improve rollback, replay, and reproducibility before chasing aggressive multi-agent parallelism.

## File-Level Map

Current key implementation files:

- `src/provider-protocol.lisp`
- `src/provider-openai.lisp`
- `src/provider-mock.lisp`
- `src/events.lisp`
- `src/session.lisp`
- `src/shell.lisp`
- `src/commands.lisp`
- `src/conversation.lisp`
- `src/turn-orchestrator.lisp`
- `src/policy.lisp`
- `src/tasks.lisp`
- `src/work-items.lisp`
- `src/workflow.lisp`

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
