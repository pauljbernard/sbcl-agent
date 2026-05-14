---
layout: default
title: Actor Runtime And Kernel
hero_title: Actor Runtime And Governed Kernel
hero_text: The system now layers an address-based actor runtime above the governed kernel while keeping SBCL/Common Lisp as the foundational runtime and persistence substrate.
eyebrow: Actor Runtime
permalink: /robust-actor-kernel-architecture.html
description: Robust actor model architecture for sbcl-agent within the governed kernel.
---

# Robust Actor Model Within The Governed Kernel

This document defines the updated target architecture for a robust actor model that still respects the existing kernel doctrine:

- all execution begins with `invoke`
- authority and governance remain kernel-owned
- actors become the primary execution and messaging substrate above the kernel
- transcripts and UI surfaces remain projections, not routing backbones
- the integrated agent inhabits the same environment it is inspecting and changing

## Visual Architecture

```mermaid
flowchart TB
    User["User"] --> ChatUI["Context Chat UI"]
    User --> EditorUI["Editor Surface UI"]
    User --> CalcUI["Calculator UI"]
    User --> RuntimeUI["Runtime / REPL UI"]

    subgraph UX["UX Projection Layer"]
        ChatUI
        EditorUI
        CalcUI
        RuntimeUI
    end

    subgraph Kernel["Governed Execution Kernel"]
        Invoke["Kernel API<br/>invoke / inspect / control"]
        Trace["Execution Trace / Event Log"]
        Ledger["Execution Ledger / Task Records"]
        Policy["Governance Kernel<br/>policy / approval / mutation authority"]
        Registry["Capability Registry / Manifests"]
    end

    subgraph ActorRuntime["Actor Runtime"]
        Router["Actor Router / Address Directory"]
        Mailboxes["Persistent Mailboxes"]
        DLQ["Dead Letter Queue"]
        Supervisor["Supervision / Retry / Restart Policy"]

        ContextChat["ContextChatActor(session-id)"]
        Governance["GovernanceActor(session-id)"]
        RuntimeActor["RuntimeActor(runtime-scope-id)"]
        EditorActor["EditorActor(editor-scope-id)"]
        CalculatorActor["CalculatorActor(calc-scope-id)"]
        MCPActor["MCPBridgeActor(server-id)"]
        EnvironmentActor["EnvironmentActor(environment-id)"]
    end

    subgraph State["Persistent Actor State"]
        ChatState["Chat Session State"]
        GovernanceState["Approval / Policy State"]
        RuntimeState["Runtime Eval History / Bindings"]
        EditorState["Pending Mutations / Buffer State"]
        CalcState["Calculator Session State"]
    end

    ChatUI --> ContextChat
    EditorUI --> EditorActor
    CalcUI --> CalculatorActor
    RuntimeUI --> RuntimeActor

    ContextChat <--> Router
    Governance <--> Router
    RuntimeActor <--> Router
    EditorActor <--> Router
    CalculatorActor <--> Router
    MCPActor <--> Router
    EnvironmentActor <--> Router

    Router --> Mailboxes
    Mailboxes --> DLQ
    Supervisor --> Mailboxes
    Supervisor --> DLQ

    ContextChat <--> ChatState
    Governance <--> GovernanceState
    RuntimeActor <--> RuntimeState
    EditorActor <--> EditorState
    CalculatorActor <--> CalcState

    ContextChat --> Invoke
    Governance --> Policy
    RuntimeActor --> Invoke
    EditorActor --> Invoke
    CalculatorActor --> Invoke
    MCPActor --> Registry
    EnvironmentActor --> Ledger

    Invoke --> Ledger
    Invoke --> Trace
    Policy --> Ledger
    Policy --> Trace
    Mailboxes --> Trace
    Mailboxes --> Ledger

    Trace --> UX
    Ledger --> UX
```

## Current Implemented Status

The target model above is no longer only aspirational. The current code now includes these implemented slices:

- actor registry definitions for core singleton actors and pooled manifest-backed actors
- canonical session-scoped actor identity for core singletons such as:
  - `ContextChatActor(session-id)`
  - `GovernanceActor(session-id)`
  - `RuntimeActor(session-id)`
  - `EditorActor(session-id)`
  - `CalculatorActor(session-id)`
- runtime inbox, outbox, and actor-owned runtime continuity state
- actor-system panel queries that project:
  - hierarchy
  - workflow edges
  - supervision incidents
  - worker-pool execution metrics
- a real SBCL worker-pool runner for thread-pool-backed actor execution

The system is therefore in the middle phase:

- no longer a purely metadata-shaped actor model
- not yet a complete mailbox-first actor runtime across every execution path

## Layered Stack

The target architecture is intentionally layered:

1. `SBCL / Common Lisp`
   - primary implementation runtime
   - primary in-process state model
   - primary persistence/materialization layer
   - full introspection of runtime objects, packages, symbols, methods, and persisted state

2. `Kernel`
   - more traditional governed execution substrate
   - authority boundary for invoke / inspect / control
   - execution recording, policy, and capability mediation
   - introspectable by both humans and agents as a first-class peer surface

3. `Actor System`
   - primary messaging and workflow substrate
   - address registry
   - mailbox execution
   - supervision hierarchy
   - singleton/pool allocation policy
   - introspectable actor hierarchy, message graph, mailbox pressure, and failure state

4. `React Presentation Tier`
   - projection of actor/kernel/runtime state
   - human-facing workflow surfaces
   - never the owner of routing or continuity
   - should remain fully reconstructible from lower-layer state

```mermaid
flowchart TB
    React["React Presentation Tier<br/>projection / UI / human workflows"]
    Actor["Actor System<br/>messaging / workflow / supervision / registry"]
    Kernel["Kernel<br/>invoke / inspect / control / authority / governance"]
    Runtime["SBCL / Common Lisp<br/>runtime / persistence / introspection"]

    React --> Actor
    Actor --> Kernel
    Kernel --> Runtime
```

### Layering Rules

1. The presentation tier projects state; it does not own workflow continuity.
2. The actor system owns message-driven business workflow.
3. The kernel owns authority, governance, and execution mediation.
4. SBCL/Common Lisp remains the foundational runtime and persistence substrate.
5. Every layer must be introspectable so agents and humans can inspect the same system from different vantage points.

## Shared Environment Principle

The integrated agent does not stand outside the environment.

It:

- draws context from the same SBCL environment
- reasons over the same runtime and persisted state
- performs work inside that same environment
- and is constrained by the same kernel-owned policy and governance boundaries as any other actor-driven execution

## Actor Message Spine

```mermaid
flowchart LR
    Msg["Actor Message"] --> Addr["sender / receiver / reply-to / originator"]
    Msg --> Corr["correlation-id / request-id / session-id"]
    Msg --> Flow["approval-id / pending-action-id / actor-slice"]
    Msg --> Work["target / operation / capability / payload"]
    Msg --> Life["state / created-at / received-at / completed-at"]
```

## Canonical Flow

```mermaid
sequenceDiagram
    participant U as User
    participant CUI as ContextChat UI
    participant C as ContextChatActor(session-id)
    participant G as GovernanceActor(session-id)
    participant R as RuntimeActor(runtime-scope-id)
    participant E as EditorActor(editor-scope-id)
    participant K as Kernel

    U->>CUI: Submit intent
    CUI->>C: SubmitUserIntent(message)
    C->>K: invoke(intent, capability, authority, context)
    C->>G: RequestExecution(actor-message)
    G->>G: Persist approval / policy state

    alt Approval required
        G->>C: ApprovalRequested(approval-id, actor-message-id)
        C->>C: Persist approval inbox state
        C->>CUI: Project approval prompt
        U->>CUI: yes
        CUI->>C: ConfirmApproval(approval-id)
        C->>G: ApprovalDecision(approval-id, approved)
    end

    alt Runtime evaluation
        G->>R: AuthorizeRuntimeEvaluation(request-id, session-id)
        R->>R: Load runtime state / mailbox
        R->>K: invoke(runtime-eval)
        R->>R: Persist result / bindings / history
        R->>C: RuntimeEvaluationCompleted(result)
    else Editor mutation
        G->>E: AuthorizePendingEditorMutation(pending-action-id)
        E->>E: Load pending mutation state
        E->>K: invoke(editor-mutation)
        E->>E: Persist updated editor state
        E->>C: EditorMutationApplied(result)
    end

    C->>C: Persist reply in outbox/history
    C->>CUI: Project reply
```

## Design Rules

1. The kernel remains the authority boundary.
   - Actors do not bypass policy or execution recording.
   - They send requests through kernel-governed execution surfaces.

2. Actors own routing and continuity.
   - Threads, turns, and transcript panels are presentation artifacts only.
   - Continuity must be carried by actor message fields and actor-owned state.

3. Mailboxes are primary.
   - Task records and transcript state are not the routing backbone.
   - Mailbox entries are the canonical lifecycle objects.

4. Actor state is encapsulated.
   - `ContextChatActor` owns chat session continuity.
   - `GovernanceActor` owns approval and authorization continuity.
   - `RuntimeActor` owns multi-turn eval continuity and runtime result history.
   - `EditorActor` owns pending mutation and apply continuity.

5. Replies are actor messages.
   - Capability completion should return through actor outboxes and inboxes, not ad hoc direct return paths.

6. Failure handling is actor-native.
   - retries
   - restart strategy
   - dead-letter routing
   - explicit failure replies

## Required Actor-System Semantics

1. Frontend/backend interaction is asynchronous by default.
   - Treat cross-boundary communication as `tell`, not `ask`, unless an explicit exception is documented.
   - UI surfaces project actor replies; they do not synchronously drive capability execution.

2. Each actor is a standalone serial processor.
   - one inbox
   - one message processed at a time
   - message fully handled before the next message is consumed
   - all downstream work issued by actor address, never by direct pointer/reference

3. Actor addressing is actor-system owned.
   - the actor system is the root actor
   - it owns the actor registry and address directory
   - actor lookup, singleton resolution, and pool routing are actor-system responsibilities

4. Allocation strategy is first-class.
   - actors may be `singleton`
   - actors may be `pool`
   - pooled actors share an inbox contract plus a consumption strategy
   - pool policy must be explicit, for example:
     - `:round-robin`
     - `:competing-consumers`
     - `:affinity-by-session`
     - `:affinity-by-scope`
   - thread usage should prefer pooled worker execution rather than one OS thread per actor instance
   - mailbox seriality still applies even when actors execute on a shared thread pool

### Current Threading Posture

The desired concurrency model is now explicit and partly implemented:

- actors do not permanently own threads
- logical singleton actors still execute serially per actor identity
- pooled SBCL workers lease a message while it is executing
- that worker returns to the pool when no mailbox work is being processed for that job

The remaining work is extending this runner uniformly across all capability paths, not just governed desktop-task execution.

5. Actors fail fast and escalate upward.
   - a failed actor must not be trusted to recover itself
   - it sends failure state and diagnostic context to its parent
   - the parent decides:
     - restart
     - replace
     - quarantine
     - dead-letter
     - escalate further

6. Workflow logic is the inter-actor sequence.
   - business behavior emerges from message flow across specialized actors
   - sequence diagrams are therefore part of the executable architecture, not only documentation
   - each actor should stay small:
     - mutate its own state
     - call the kernel
     - call the prescribed LLM
     - send messages to other actors

## Current Gap From This Target

The current implementation is closest to this target in:

- message envelope shape
- actor-flow read models
- mailbox persistence
- governance/editor routing

It is still weakest in:

- actor-local behavior loops
- primary mailbox-driven execution
- runtime actor autonomy
- supervision semantics
- reply/outbox-first result handling

## Immediate Next Step

The next implementation cut should be:

1. make `RuntimeActor` a first-class actor peer to `EditorActor`
2. make chat-triggered runtime eval produce primary runtime mailbox messages
3. make runtime results return through a runtime outbox / reply channel
4. keep the kernel as the execution and governance authority under that actor flow

## Maturity Benchmark

Use Akka as the reference maturity model for actor-system semantics, while preserving SBCL/kernel-specific implementation choices.

For implementation details and concrete open-source reference behavior, use Apache Pekko as the practical companion reference:

- [Pekko documentation](https://pekko.apache.org)
- [Pekko source](https://github.com/apache/pekko)

Akka is the comparison point for:

1. address-based actor messaging
2. serial mailbox processing
3. explicit supervision trees
4. singleton vs pooled/router allocation
5. failure escalation to parent actors
6. mailbox-first execution rather than central orchestration
7. observable message flow and actor lifecycle

The goal is not JVM parity. The goal is semantic parity in the parts that define a robust actor system.

### Current Maturity Against That Benchmark

1. Message envelope maturity: high
   - sender / receiver / reply-to / originator / correlation ids are strong

2. Registry and addressing maturity: medium-high
   - actor-system root exists
   - actor definitions now carry parent, allocation, supervision, and execution policy

3. Mailbox read-model maturity: medium-high
   - inbox/outbox/state views exist
   - actor-flow visibility exists
   - explicit mailbox transitions exist in some flows

4. Mailbox-first execution maturity: low-medium
   - too much execution still derives from task-record orchestration
   - dequeue / handle / reply / ack / fail is not yet the universal execution model

5. Supervision maturity: medium
   - supervision metadata exists
   - failure policy is modeled
   - parent-owned executable recovery semantics are still incomplete

6. Pool/runtime execution maturity: medium
   - allocation strategy and pooled worker execution are modeled
   - shared-inbox pool behavior is described
   - live pool execution semantics are not yet broadly exercised

7. Runtime actor maturity: low-medium
   - inbox/outbox/runtime-state now exist
   - live cross-turn continuity still exposes hybrid behavior

8. UX observability maturity: medium
   - actor-flow is visible
   - the actor-system panel is now specified
   - the full live panel is not yet implemented

### Maturity Gate For “Robust Actor System”

Do not call the system robust until all of the following are true:

1. Every actor consumes from an inbox as the primary execution contract.
2. Every failure becomes a supervision event owned by the parent actor.
3. Every actor reply is emitted through outbox/reply state, not ad hoc return paths.
4. Pool semantics are executable, not only declared in metadata.
5. The actor-system panel renders the live hierarchy and workflow graph from running actor state.
