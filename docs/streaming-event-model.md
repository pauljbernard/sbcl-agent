---
layout: default
title: Streaming Event Model
hero_title: Streaming Event Model
hero_text: Event-native streaming is the contract that keeps visible assistant text, runtime execution, and engineering evidence separate but synchronized.
eyebrow: Blueprint
permalink: /streaming-event-model.html
description: Canonical event taxonomy and streaming rules for sbcl-agent.
---
## Why This Exists

The original streamed `ask` path was enough for text, but it was not a stable contract for a conversation runtime. Once turns can pause for approval, emit operations, and create artifacts, streamed text alone is not enough.

The event model therefore exists to ensure that:

- providers can stream incrementally
- the orchestrator can govern behavior in Lisp
- the shell can render coherent progress
- interrupted turns can preserve enough state to inspect or resume

## Current State

The codebase already has part of this model in place.

Implemented now:

- canonical provider-event normalization in `src/provider-protocol.lisp`
- shell handling for event-driven streamed behavior
- turn orchestration that can translate assistant activity into operation and artifact records
- actor-origin event annotations and recovery metadata on key governed execution paths
- replay and recovery classification on workflow-owned continuation and supervision-driven recovery

Still transitional:

- some provider behavior, especially the OpenAI-compatible streaming path, still carries compatibility logic from the older in-band action model
- the shell still blends legacy and newer event semantics in some paths

So this document describes both the current contract and the target contract.

## Design Rules

### Rule 1

Assistant-visible streaming contains only assistant-visible text.

### Rule 2

Tool intents, operation progress, approvals, checkpoints, and artifact creation are sibling events, not hidden fragments inside the visible text stream.

Project-context shifts, recovery posture, and resumable continuation should also remain explicit sibling facts rather than being flattened into assistant prose.

### Rule 3

Providers emit events, but the conversation orchestrator owns behavior.

### Rule 4

The event stream must be replayable enough for shell rendering, debugging, and interrupted-turn recovery.

## Canonical Event Shape

The current provider layer already normalizes events into a canonical struct. The long-term shape should remain rich enough to index by thread, turn, and entity.

Suggested shape:

```lisp
(defstruct runtime-event
  id
  timestamp
  family
  type
  entity-id
  thread-id
  turn-id
  parent-id
  payload
  visibility)
```

Practical expectations:

- `family` groups events by subsystem such as `:provider`, `:turn`, `:operation`, `:artifact`, or `:workflow`
- `type` gives the concrete event
- `entity-id` points at the primary object being described
- `payload` carries structured details
- `visibility` lets renderers distinguish user-facing output from operator or internal evidence

The service-facing and renderer-facing event model now also benefits from stable optional metadata for:

- actor origin
- workflow-record id
- project id when governed project work is involved
- recovery origin
- replay class

## Event Families

### Provider events

Examples:

- `:provider/run-started`
- `:provider/text-delta`
- `:provider/text-complete`
- `:provider/tool-intent`
- `:provider/run-complete`
- `:provider/run-failed`

### Turn events

Examples:

- `:turn/started`
- `:turn/message-delta`
- `:turn/message-finalized`
- `:turn/awaiting-approval`
- `:turn/completed`
- `:turn/failed`
- `:turn/cancelled`

### Operation events

Examples:

- `:operation/queued`
- `:operation/started`
- `:operation/stdout-delta`
- `:operation/stderr-delta`
- `:operation/completed`
- `:operation/failed`

### Artifact events

Examples:

- `:artifact/created`
- `:artifact/updated`
- `:artifact/linked`

### Workflow events

Examples:

- `:workflow/checkpoint-created`
- `:workflow/validation-started`
- `:workflow/validation-completed`
- `:workflow/reconciliation-created`
- `:workflow/rollback-started`
- `:workflow/rollback-completed`
- `:workflow/control-state-recovered`
- `:workflow/recovery-classified`

## Processing Contract

### Provider to orchestrator

Providers emit provider-scoped events and should not directly mutate conversation or workflow state.

### Orchestrator to durable state

The turn orchestrator consumes provider events and updates:

- the active assistant message
- the current turn
- operation records
- artifact linkage
- approval and resumability state
- recovery or replay posture when interrupted continuation is resumed or reconstructed

### Durable state to renderer

The shell and future UI should render from canonical events plus durable records, not from provider-specific streaming internals.

## Rendering Expectations

### Minimal REPL renderer

Show:

- assistant text deltas inline
- concise operation notices
- brief artifact lines
- final turn status

### Rich chat renderer

Show:

- assistant text as the primary stream
- operation lifecycle lines
- approval checkpoints
- artifact summaries
- final turn summary

Both renderers should consume the same event truth.

They should also be able to distinguish:

- normal forward execution
- approval-gated pause
- interrupted work
- checkpoint-backed recovery or replay

## Backward Compatibility

During migration, the runtime still needs to handle older event styles such as:

- `:message-start`
- `:message-delta`
- `:action-proposal`
- `:message-complete`

Those should be normalized at the provider boundary so the rest of the runtime can move toward one canonical model.

## Exit Condition

This work is complete when streamed text, operation dispatch, approval state, and artifact creation all appear as coordinated but independent event streams, and no provider needs in-band hidden payload markers to control the turn lifecycle.
