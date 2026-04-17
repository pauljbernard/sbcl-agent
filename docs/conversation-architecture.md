---
layout: default
title: Conversation Runtime Blueprint
hero_title: Conversation Runtime Blueprint
hero_text: The conversation layer is no longer just a design idea. sbcl-agent now has real thread and turn primitives, but the roadmap now treats conversation as one native subsystem within a larger Environment architecture.
eyebrow: Blueprint
permalink: /conversation-architecture.html
description: Technical blueprint for threads, turns, operations, and artifacts in sbcl-agent.
---
## Intent

This document defines the conversation-runtime architecture that evolves `sbcl-agent` from a shell with streamed ask into a persistent conversation subsystem backed by the same SBCL image and workflow-governed engineering model.

It is intentionally not a plan to replace the existing shell. The shell, direct Lisp evaluation, capability gates, work-items, and background execution model remain strengths that the conversation layer should preserve.

The newer roadmap narrows the role of this document: conversation is now one native medium within the Environment rather than the singular destination of the architecture.

## Ownership Rule

The architectural rule is:

- conversation owns interaction state
- runtime owns execution state
- workflow owns engineering governance

That rule is the cleanest way to align the conversation runtime with the project's source truth, image truth, and workflow truth model.

## What Exists Today

The codebase already implements part of this blueprint.

Present in code now:

- durable `thread`, `message`, `turn`, `operation`, and `artifact` records in [`src/conversation.lisp`](/Volumes/data/development/sbcl-agent/src/conversation.lisp)
- thread-aware shell commands in [`src/commands.lisp`](/Volumes/data/development/sbcl-agent/src/commands.lisp) and [`src/shell.lisp`](/Volumes/data/development/sbcl-agent/src/shell.lisp)
- `say` as a conversation-first command
- `ask` routed through the same turn runner with `:repl-bridge` operator semantics
- `turn/status` and `turn/resume`
- turn orchestration in [`src/turn-orchestrator.lisp`](/Volumes/data/development/sbcl-agent/src/turn-orchestrator.lisp)
- canonical provider-event normalization in [`src/provider-protocol.lisp`](/Volumes/data/development/sbcl-agent/src/provider-protocol.lisp)
- governed mutation binding for patches, mutating eval, and write-class tool actions
- provider follow-up after turn resume, with follow-up lifecycle metadata and events

Still transitional:

- the top-level mutable state is still largely organized through `agent-session`
- event flow is more structured than before but not yet fully separated from every legacy path
- runtime and workflow operations are not yet uniformly exposed as first-class conversation operations

## Place in the Larger Architecture

Conversation is still important, but it is no longer the whole architectural frame. In the new vision:

- Environment becomes the top-level object
- Runtime, Thread, Artifact, Work-Item, Agent, and Policy become peer native entities
- conversation remains the subsystem that gives threads, turns, and conversational coordination their structure

## Runtime Shape

The current shell still keeps one live session handle, but the intended structure is compositional.

### Practical composition root

The code effectively needs one shell-facing runtime object with these responsibilities:

- provider
- tool registry
- policy engine
- event bus
- conversation manager
- runtime manager
- engineering manager

That can remain one ergonomic shell handle while still separating internal ownership.

## Conversation Domain Objects

The conversation layer is built around durable records instead of transcript-only history.

### Thread

A long-lived conversation container.

Responsibilities:

- title and identity
- message membership
- turn membership
- artifact linkage
- summary and last-activity state

### Message

A durable utterance or tool/runtime narration.

Responsibilities:

- role tracking
- text or structured content
- stream fragments during generation
- finalized state

### Turn

One user interaction lifecycle.

Responsibilities:

- the user message and assistant message relationship
- status transitions
- operation linkage
- artifact linkage
- approval pause and resume state
- terminal outcome

### Operation

A runtime or tool action associated with a turn.

Responsibilities:

- action kind
- input and output
- policy decision
- execution status
- linkage to created artifacts

### Artifact

A user-visible output of a turn or operation.

Responsibilities:

- kind, title, and summary
- optional path or diff target
- linkage to thread, turn, operation, and work-item
- source/image references where relevant

## Turn Lifecycle

Conversation mode is a workflow, not a single streamed string.

Recommended state model:

- `:initialized`
- `:building-context`
- `:streaming-assistant`
- `:awaiting-operation-dispatch`
- `:running-operations`
- `:awaiting-approval`
- `:awaiting-provider-resume`
- `:finalizing`
- `:completed`
- `:failed`
- `:cancelled`

The current implementation covers the most important early states and approval-aware completion flow, even though the full lifecycle remains a target for refinement.

## Turn Orchestrator Responsibilities

The turn orchestrator is the bridge between provider text generation and governed execution.

Its responsibilities are:

1. Resolve the current thread and turn context.
2. Build provider input from conversation and runtime summaries.
3. Create and update assistant message state during streaming.
4. Record structured operation intents when the assistant proposes actions.
5. Apply policy decisions and pause when approval is needed.
6. Resume the turn after approval.
7. Optionally resume the provider after the operation phase when the provider supports structured turn follow-up.
8. Finalize turn, operation, and artifact state.

This keeps behavior in Lisp rather than encoding it in prompt tricks.

## `ask` and `say`

The migration strategy is compatibility first.

- `(ask ...)` remains supported as the original shell-oriented interaction
- `(say ...)` is the conversation-first entrypoint
- both commands now share one conversation turn runner and persist the same core turn records

The long-term design is for `ask` to remain a thin compatibility surface while the runtime increasingly treats thread-and-turn interaction as the primary operator model.

## Event-Native Streaming

The conversation runtime depends on one architectural rule:

- assistant-visible text is only assistant-visible text
- tool intents, operation progress, approvals, and artifacts are sibling events

This is partly implemented now through provider-event normalization and shell handling, but the OpenAI-backed path still contains transitional behavior. The goal is to let the orchestrator and shell consume one canonical event stream regardless of provider specifics.

The event model now also includes explicit follow-up lifecycle signals for resumed turns, which keeps provider continuation visible without collapsing it into assistant text.

## Relationship To Workflow Governance

Conversation does not replace work-items. It feeds them.

Rules of thumb:

- a read-only turn may not need a work-item
- a mutating turn should usually create or attach to governed workflow state
- approval-gated mutation turns should record checkpoint and approval evidence before execution continues
- validation, reconciliation, quarantine, and replay remain workflow-owned concerns

This matters because the value of the system is not just that it can chat about changes. The value is that it can preserve evidence about what it changed and why the result should be trusted.

## Current Gaps

The biggest remaining gaps in the conversation architecture are:

- cleaner internal separation of conversation, runtime, and engineering state
- richer operation coverage beyond the current assistant-action and tool-oriented paths
- fuller artifact surfacing for every validation and reconciliation path
- stronger interrupted-turn recovery and resumability
- governed runtime tooling for image-native inspection and mutation

## End State

When this blueprint is fully realized, `sbcl-agent` will support:

- REPL mode for direct Lisp and shell-style request-response work
- conversation mode for persistent thread-based interaction

on one common SBCL-native runtime, with workflow records still governing mutating engineering activity.
