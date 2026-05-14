---
layout: default
title: Actor Model State Machine
hero_title: Actor Model State Machine
hero_text: State-machine framing for actor-based governed capability execution, starting with the Context Chat to Editor and Calculator slices.
eyebrow: Actor Model
permalink: /actor-model-context-chat-editor.html
description: Actor model state machine for governed capability execution in sbcl-agent.
---

# Actor-Model State Machine

This document defines the actor-model direction for governed capability execution and records the first migrated slice: `Context Chat -> Editor`.

## Why this exists

The current thread-centric desktop model mixes together:

- transcript ownership
- approval continuation
- capability routing
- UI hydration
- recovery state

That makes a stale or ghost thread capable of poisoning unrelated capability work. The actor model separates those concerns by making capability invocation a message exchange between durable actors rather than a side effect of whichever thread happens to be selected.

## Actor roles

### Conversation client actor

- Actor id: `actor/context-chat`
- Kind: `:internal`
- Role: `:context-chat`
- Responsibility:
  - interpret user intent
  - discover governed capabilities
  - send invocation messages
  - render results returned by capability actors

### Capability server actors

- Actor id: `actor/editor`
- Kind: `:internal`
- Role: `:editor`
- Responsibility:
  - receive invocation messages
  - optionally interpret requests locally
  - execute editor mutations
  - return canonical completion or failure results

- Actor id: `actor/calculator`
- Kind: `:internal`
- Role: `:calculator`
- Responsibility:
  - receive invocation messages
  - execute calculator operations
  - return canonical completion or failure results

## Actor subsystem

The actor subsystem is the communication spine between:

- the SBCL runtime
- governed environment state
- the UX surface
- the agent-facing conversation client

It is not a separate "robot" layer. It is the message-routing and lifecycle layer that keeps these concerns decoupled.

For internal capability servers, the initial actor topology is:

- `actor/context-chat`
- `actor/editor`
- `actor/calculator`

Future actors should include:

- `actor/governance`
- `actor/notifications`
- `actor/mcp/<server-id>`
- `actor/environment`

The design goal is that every significant integration boundary becomes an actor boundary with:

- an address
- a protocol
- a mailbox
- durable message history
- supervision and retry semantics

### Governance actor

- Logical role today:
  - policy evaluation
  - approval gating
  - audit recording
- This is currently represented through governed desktop-task transitions rather than a standalone actor object, but the state machine below treats governance as an explicit message-processing phase.

## Message envelope

Each governed capability invocation should be representable as an actor message with:

- `id`
- `protocol-version`
- `sender`
- `receiver`
- `request-id`
- `correlation-id`
- `target`
- `operation`
- `capability`
- `state`
- `payload`
- `metadata`
- `created-at`
- `received-at`
- `completed-at`

The current migration stores this envelope on:

- `desktop-task-request.actor-message`
- `desktop-task-record.actor-message`

That lets the system keep using governed desktop-task records while shifting routing semantics away from `current-thread`.

## Akka-aligned principles

This design should follow the useful parts of mature actor systems such as Akka Typed:

1. Addressed communication
   - actors communicate through explicit addresses, not implicit shared state.
   - in this system that means `actor/context-chat`, `actor/editor`, `actor/calculator`, and future bridge actors.

2. Protocol-first interaction
   - an actor should only accept messages from its own protocol.
   - here that means the capability manifest plus governed task request shape defines the accepted protocol for a capability actor.

3. Mailbox semantics
   - messages are durable mailbox entries before they are visible as completed work.
   - in this system the mailbox view is derived from governed task records keyed by receiver actor.

4. Request/reply rather than ambient thread coupling
   - the sender address and correlation id should be enough to complete an interaction.
   - a reply must not require the client to remain attached to one historical thread object.

5. Supervision and failure isolation
   - one actor failure should not poison unrelated actors.
   - governance, retries, and failure classification should attach to the message/task, not to global chat state.

6. Conversation as a client, not the transport
   - `Context Chat` is an actor and a user-facing client.
   - the conversation transcript is an artifact of interaction, not the routing spine of the platform.

## State machine

The actor-message lifecycle for a governed capability invocation is:

1. `:queued`
   - `Context Chat` creates a message for a capability actor.

2. `:governance-review`
   - the message is registered as a governed task record.
   - policy, approval, and retry posture are attached.

3. `:awaiting-approval`
   - explicit approval is required before dispatch.

4. `:approved`
   - approval has been granted.

5. `:executing`
   - the receiving actor has accepted the message and is applying it.

6. `:completed`
   - the receiving actor completed successfully and returned a canonical result.

7. `:failed`
   - execution failed and a canonical failure result was recorded.

8. `:canceled`
   - execution was intentionally canceled.

Optional future states:

- `:interpreting`
  - receiver is using local logic or an LLM to transform a generic invocation into an executable plan.
- `:retrying`
  - the message is being re-attempted according to retry policy.

## First migrated slices

### Context Chat -> Editor

The first end-to-end slice uses the actor model for editor append requests.

### Invocation path

1. `Context Chat` recognizes a governed editor mutation request.
2. The planner creates a governed request for:
   - `target=:editor`
   - `operation=:append-text`
3. The request is stamped with an actor message:
   - sender: `actor/context-chat`
   - receiver: `actor/editor`
   - state: `:queued`
4. Registering the task record transitions the message to `:governance-review`.
5. If policy is explicit, the task transitions to `:awaiting-approval`.
6. After approval, the editor actor transitions to `:executing`.
7. The editor actor applies `append-text` and returns a canonical completion result.
8. The task record and actor message transition to `:completed`.

### Context Chat -> Calculator

The second internal slice uses the same actor envelope for calculator requests.

1. `Context Chat` recognizes a governed calculator request.
2. The planner creates a governed request for:
   - `target=:calculator`
   - `operation=:evaluate-expression` or `:append-token`
3. The request is stamped with an actor message:
   - sender: `actor/context-chat`
   - receiver: `actor/calculator`
   - state: `:queued`
4. Registering the task record transitions the message to `:governance-review`.
5. Calculator execution transitions the message to `:executing`.
6. The calculator actor returns a canonical completion result and the message transitions to `:completed`.

The current implementation identifies this slice with:

- `:actor-slice :context-chat-calculator-v1`

### What is migrated now

The current implementation now carries actor semantics in the governed protocol for these internal slices:

- governed requests carry an `actor-message`
- task records persist the same message envelope
- approval and execution transitions update actor message state
- canonical result summaries surface the actor message summary
- the editor receiver is tagged via `:actor-slice :context-chat-editor-v1`
- the calculator receiver is tagged via `:actor-slice :context-chat-calculator-v1`
- actor inbox/read-model queries are available for capability actors

### What is not migrated yet

- a standalone actor inbox/query service
- actor-native UI panels instead of thread-centric chat panels
- actor-to-actor routing for MCP-backed capabilities and other environment actors
- governance as a first-class actor object rather than a governed phase attached to desktop tasks

## Migration rule

Conversation threads should become presentation artifacts, not routing keys.

The routing key for governed capability work should be:

- actor message id
- request id
- task record id
- correlation id

That is the architectural constraint for future migrations.
