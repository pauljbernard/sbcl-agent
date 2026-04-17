---
layout: default
title: Architecture and Design
hero_title: Architecture and Design
hero_text: The goal is not a literal Codex clone. The goal is an SBCL-native engineering runtime where conversation, execution, and workflow governance are explicit, inspectable layers.
eyebrow: Architecture
permalink: /architecture.html
description: Detailed architecture for sbcl-agent.
---
## System Objective

Build a governed, transactional, image-native engineering environment that can inspect and mutate the same running system it is reasoning about while preserving reproducibility, rollback intent, provenance, and operator trust.

The current codebase now sits between two phases:

- the original shell-plus-streamed-ask runtime is still supported
- the conversation-native runtime is partially implemented and now shapes the architecture

## The Three Truths

The architecture is built around three explicit truth domains.

### Source truth

Source truth covers file-backed and reproducible state:

- source files
- patches and diffs
- tests and fixtures
- generated durable artifacts
- git state and other persistent inputs

### Image truth

Image truth covers the live SBCL image:

- loaded definitions
- packages and symbols
- object identity and heap state
- dynamic bindings
- active workers and threads
- open resources and runtime handles

### Workflow truth

Workflow truth covers the durable engineering record:

- work-items
- plans and hypotheses
- operations and approvals
- validations and replay records
- checkpoints, quarantine, and reconciliation
- operator-facing evidence

Every meaningful piece of work should answer:

- what changed in source?
- what changed in image?
- what evidence links the two?

## Ownership Rule

The current refactor is organized around one rule:

- conversation owns interaction state
- runtime owns execution state
- workflow owns engineering governance

This prevents conversation history from becoming a second runtime database, and it prevents runtime activity from bypassing workflow evidence.

## Current Runtime Shape

The codebase still exposes one shell-facing session handle, but the internal architecture now spans several real layers.

### CLI and shell

Top-level entrypoints in [`bin/`](/Volumes/data/development/sbcl-agent/bin) dispatch into the Common Lisp runtime. The interactive shell in [`src/shell.lisp`](/Volumes/data/development/sbcl-agent/src/shell.lisp) accepts both:

- recognized shell commands such as `(ask ...)`, `(say ...)`, `(tool ...)`, `(thread/new ...)`, and `(turn/status ...)`
- ordinary Lisp forms for direct evaluation in the `SBCL-AGENT-USER` package

`chat -i` preserves the original interactive streamed-ask feel while the new conversation layer is introduced incrementally.

### Command normalization

[`src/commands.lisp`](/Volumes/data/development/sbcl-agent/src/commands.lisp) maps recognized forms into structured command records and leaves everything else as ordinary Lisp evaluation. This compatibility rule is deliberate: the conversation runtime is an added layer, not a replacement for the REPL-backed operator model.

### Provider boundary and streaming

[`src/provider-protocol.lisp`](/Volumes/data/development/sbcl-agent/src/provider-protocol.lisp) normalizes provider events into a canonical shape. The system currently supports:

- a mock provider in [`src/provider-mock.lisp`](/Volumes/data/development/sbcl-agent/src/provider-mock.lisp)
- an OpenAI-compatible provider in [`src/provider-openai.lisp`](/Volumes/data/development/sbcl-agent/src/provider-openai.lisp)

Streaming is now more event-aware than the original shell implementation, although the OpenAI path still carries some transitional behavior while the event model continues to harden.

### Conversation layer

[`src/conversation.lisp`](/Volumes/data/development/sbcl-agent/src/conversation.lisp) introduces durable interaction objects:

- `thread`
- `message`
- `turn`
- `operation`
- `artifact`

These records make interaction state explicit instead of treating transcript entries as the only durable truth.

### Turn orchestration

[`src/turn-orchestrator.lisp`](/Volumes/data/development/sbcl-agent/src/turn-orchestrator.lisp) is the new boundary between provider streaming and governed execution. It is responsible for:

- creating turn records
- updating assistant messages during streaming
- mapping assistant actions into operation records
- applying policy decisions
- pausing for approvals when needed
- resuming a turn after approval
- finalizing artifacts and turn outcomes

This is the structural shift from "one streamed response" to "one interaction lifecycle."

### Session runtime

[`src/session.lisp`](/Volumes/data/development/sbcl-agent/src/session.lisp) still acts as the shell-facing composition root. It persists:

- events and transcript-like history
- pending assistant actions
- capability grants and approvals
- tasks and worker metadata
- work-items and workflow records
- conversation state that is now threaded into the shell experience

The long-term direction is a cleaner internal split between conversation, runtime, and engineering state while preserving one ergonomic session handle in the shell.

### Tool and policy layer

Tools remain structured, explicit capabilities. Current tool families include:

- filesystem tools
- documentation tools
- session visibility tools
- process tools
- git tools
- patch application

Policy and capability control live in [`src/policy.lisp`](/Volumes/data/development/sbcl-agent/src/policy.lisp) and [`src/sandbox.lisp`](/Volumes/data/development/sbcl-agent/src/sandbox.lisp). The system is designed so conversation mode does not bypass those gates.

### Tasks, workers, and governed workflow

[`src/tasks.lisp`](/Volumes/data/development/sbcl-agent/src/tasks.lisp), [`src/work-items.lisp`](/Volumes/data/development/sbcl-agent/src/work-items.lisp), and [`src/workflow.lisp`](/Volumes/data/development/sbcl-agent/src/workflow.lisp) hold the governed engineering layer.

That layer currently supports:

- queued tasks and background workers
- work-item lifecycle visibility
- approval requests and wait-state reporting
- validator replay groups and validator task records
- image-only outcomes
- image-to-source reconciliation records

## Interaction Modes

The target end state has two operator styles on one runtime, and the current implementation already spans both partially.

### REPL mode

The user types Lisp forms or shell commands and gets results immediately. This is the original operator surface and remains a first-class mode.

### Conversation mode

The user works through persistent threads and turns. Assistant text can stream, operations can be represented explicitly, approvals can pause the turn, and artifacts can be attached to the result.

`(say ...)` is the clearest expression of this direction today, while `(ask ...)` remains as a compatibility surface.

## Transactional Engineering Model

The workflow architecture still centers transactional discipline rather than unconstrained autonomy.

The intended loop is:

1. inspect source and image
2. plan bounded mutations
3. checkpoint relevant state
4. mutate deliberately
5. observe runtime effects
6. validate in-image
7. validate from a colder baseline
8. reconcile differences
9. commit, quarantine, or roll back

Not every part of that loop is equally mature in code today, but the work-item and workflow systems already preserve the design intent and evidence model.

## Artifacts and Evidence

One of the important changes in the current refactor is that useful outputs are becoming explicit records rather than only transcript text.

The artifact model currently covers conversation-visible results such as:

- files
- patches and diffs
- operation outputs
- validation summaries
- checkpoints and reconciliation records
- plan-like or summary records linked to turns

The implementation is still growing, but the direction is clear: if the assistant changed or validated something important, that outcome should be representable as a durable artifact.

## Safety Model

### Capability gates

The runtime uses explicit capability grants for stateful operations. Important current gates include:

- `:safe-read`
- `:process-run`
- `:git-read`
- `:git-write`
- `:workspace-write`

The conversation runtime is being built to consume the same gates rather than creating a second, less-governed execution path.

### Approval checkpoints

Assistant-proposed actions and certain turn operations can pause in an approval state. The user can then inspect the turn and explicitly resume it.

### Checkpointing, replay, and reconciliation

The work-item system already models checkpoint-like metadata, replayable validation records, and image reconciliation. These remain part of the core architecture because live-image success is not enough on its own.

## Module Map

The current source tree maps to the architecture like this:

- [`src/main.lisp`](/Volumes/data/development/sbcl-agent/src/main.lisp): CLI dispatch and top-level commands
- [`src/commands.lisp`](/Volumes/data/development/sbcl-agent/src/commands.lisp): shell command normalization
- [`src/shell.lisp`](/Volumes/data/development/sbcl-agent/src/shell.lisp), [`src/repl.lisp`](/Volumes/data/development/sbcl-agent/src/repl.lisp): operator interface and command execution
- [`src/provider-protocol.lisp`](/Volumes/data/development/sbcl-agent/src/provider-protocol.lisp), [`src/provider-mock.lisp`](/Volumes/data/development/sbcl-agent/src/provider-mock.lisp), [`src/provider-openai.lisp`](/Volumes/data/development/sbcl-agent/src/provider-openai.lisp): provider boundary
- [`src/conversation.lisp`](/Volumes/data/development/sbcl-agent/src/conversation.lisp), [`src/turn-orchestrator.lisp`](/Volumes/data/development/sbcl-agent/src/turn-orchestrator.lisp): conversation and turn lifecycle
- [`src/session.lisp`](/Volumes/data/development/sbcl-agent/src/session.lisp), [`src/events.lisp`](/Volumes/data/development/sbcl-agent/src/events.lisp), [`src/tasks.lisp`](/Volumes/data/development/sbcl-agent/src/tasks.lisp): runtime state, event log, tasks, workers
- [`src/tools-*.lisp`](/Volumes/data/development/sbcl-agent/src): structured capability surface
- [`src/policy.lisp`](/Volumes/data/development/sbcl-agent/src/policy.lisp), [`src/sandbox.lisp`](/Volumes/data/development/sbcl-agent/src/sandbox.lisp), [`src/patch.lisp`](/Volumes/data/development/sbcl-agent/src/patch.lisp): execution governance and mutation controls
- [`src/work-items.lisp`](/Volumes/data/development/sbcl-agent/src/work-items.lisp), [`src/workflow.lisp`](/Volumes/data/development/sbcl-agent/src/workflow.lisp): governed engineering records

## What Is Implemented Versus Planned

Already implemented in code:

- Common Lisp shell and direct Lisp evaluation
- provider abstraction and streaming support
- thread, message, turn, operation, and artifact records
- shell commands for threads, `say`, turn status, and turn resume
- approval-aware turn orchestration
- persisted session state, tasks, workers, work-items, replay, and reconciliation

Still partial or still planned:

- a fully separated internal conversation/runtime/engineering state model
- a richer event bus that fully eliminates transitional in-band control behavior
- governed runtime tool families for image inspection and mutation
- stronger artifact coverage and workflow binding for every mutating turn
- deeper rollback and cold-start reproducibility orchestration

Those are roadmap items, not hidden assumptions. See [Implementation Plan]({{ '/implementation-plan.html' | relative_url }}) for sequencing.
