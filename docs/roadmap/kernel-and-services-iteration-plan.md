---
layout: default
title: Kernel and Services Iteration Plan
hero_title: Kernel and Services Iteration Plan
hero_text: A historical two-track execution plan for consolidating the environment runtime and extracting the service boundary now used by shell and desktop clients.
eyebrow: Execution
permalink: /roadmap/kernel-and-services-iteration-plan.html
description: Iterative execution plan for kernel consolidation and public service interface extraction in sbcl-agent.
---
## Purpose

This plan is now historical program context. It revises the earlier roadmap into two coordinated tracks:

- environment/runtime consolidation
- public service interface extraction

The goal is not just architectural cleanliness. The goal is to make the governed runtime easier to maintain while creating the stable boundary now used by the shell and `sbcl-agent-ux`.

## Target Architecture

The target architecture described here has three layers:

1. environment runtime
2. public service interface layer
3. presentation adapters

The environment runtime owns durable truth and invariants.

The service layer exposes secure, stable, governed interfaces over that kernel.

The shell and desktop-host surfaces become clients of the same service contracts.

## Track A. Environment / Runtime Consolidation

Focus:

- clarify environment authority
- reduce session-centric assumptions
- tighten domain boundaries
- centralize mutation lifecycle governance
- reduce summary and orchestration drift

Primary outcomes:

- environment-first state ownership
- clearer domain modules
- one governed mutation engine
- command and shell surfaces decoupled from domain internals

## Track B. Public Service Interface Extraction

Focus:

- define stable service contracts
- separate queries from commands
- enforce policy and audit at service boundaries
- expose subscription/event surfaces for UX
- migrate shell dispatch to use the service layer

Primary outcomes:

- secure public interfaces for modern UX work
- shell as a client rather than the privileged center
- stable DTOs and event contracts for future front ends

## Iteration Rules

Every iteration should:

1. deliver a concrete repo artifact
2. leave the runtime behavior at least as testable as before
3. update this tracker with a cumulative completion percentage
4. avoid introducing new durable session-only state
5. preserve the current shell unless the iteration is explicitly about shell-to-service migration

Completion percentage is cumulative program progress across both tracks. It is intentionally approximate. The purpose is to keep execution disciplined and visible rather than to pretend to mathematical precision.

## Iteration Plan

### Iteration 1. Authority and Boundary Lock

Track A goals:

- declare environment authority formally
- document session as compatibility facade

Track B goals:

- define the public service interface boundary for shell and desktop hosts

Deliverables:

- [Environment Authority]({{ '/environment-authority.html' | relative_url }})
- [Public Service Interfaces]({{ '/public-service-interfaces.html' | relative_url }})
- this iteration plan

Acceptance criteria:

- contributors can identify durable state authority without reading tests
- contributors can identify where presentation clients should integrate without coupling to shell internals

Status:

- complete

Cumulative completion:

- 10%

### Iteration 2. Environment Module Split

Track A goals:

- split `src/environment.lisp` by responsibility into core, sync, summary, and compatibility modules
- keep behavior stable during the split

Track B goals:

- identify which environment-facing functions are already de facto public candidates

Deliverables:

- `src/environment-core.lisp`
- `src/environment-sync.lisp`
- `src/environment-summary.lisp`
- `src/environment-compatibility.lisp`
- thin compatibility bridge in `src/environment.lisp`

Acceptance criteria:

- no material behavior change
- environment responsibilities are no longer concentrated in one file
- candidate service seams are easier to see in code

Status:

- complete

Cumulative completion after iteration:

- 22%

### Iteration 3. Canonical Request Snapshot

Track A goals:

- make one request snapshot the only provider input path
- remove direct ambient session/environment assembly from providers

Track B goals:

- define the first service-facing request DTOs for provider and turn work

Deliverables:

- `src/request-snapshot.lisp`
- provider request assembly cleanup
- provider-facing DTO note or code-level request type consolidation

Acceptance criteria:

- providers consume stable request snapshots only
- shell, workers, and future services can share the same request construction path

Status:

- complete

Cumulative completion after iteration:

- 34%

### Iteration 4. Test Decomposition and Fixture Cleanup

Track A goals:

- split `tests/smoke.lisp` into domain suites
- centralize path and temp fixture helpers

Track B goals:

- ensure future service-layer work lands into domain-specific tests instead of a monolithic smoke file

Deliverables:

- domain-oriented test files
- shared fixture helpers
- reduced absolute path assumptions

Acceptance criteria:

- tests mirror runtime domains more closely
- workstation-specific path dependencies are substantially reduced

Status:

- complete

Cumulative completion after iteration:

- 46%

### Iteration 5. Provider Transport Abstraction

Track A goals:

- isolate transport from provider protocol and payload shaping

Track B goals:

- define service-safe provider error and timeout normalization

Deliverables:

- `src/provider-transport.lisp`
- `src/provider-transport-curl.lisp`
- `src/provider-openai.lisp` slimmed into protocol adapter behavior

Acceptance criteria:

- transport can be replaced without rewriting provider protocol logic
- retry, timeout, and error behavior have clearer ownership

Status:

- complete

Cumulative completion after iteration:

- 58%

### Iteration 6. Governed Mutation Engine

Track A goals:

- centralize authorize, checkpoint, execute, validate, reconcile, close/quarantine lifecycle

Track B goals:

- expose mutation commands in a way the future service layer can reuse directly

Deliverables:

- `src/mutation-engine.lisp`
- refactors in turn orchestration, workflow, work-items, and incidents to call into it

Acceptance criteria:

- one primary mutation lifecycle path exists
- approval, quarantine, and resume semantics are less duplicated

Status:

- complete

Cumulative completion after iteration:

- 70%

### Iteration 7. Public Service Contract Extraction

Track A goals:

- stabilize domain read models needed by services

Track B goals:

- add first service families and separate queries from commands

Deliverables:

- initial service modules for environment, conversation, runtime, workflow, and approval
- stable DTO/read-model boundaries

Acceptance criteria:

- shell can begin delegating through service contracts
- services enforce policy entry points consistently

Status:

- complete

Cumulative completion after iteration:

- 82%

### Iteration 8. Shell-to-Service Migration

Track A goals:

- remove remaining shell-first architectural assumptions

Track B goals:

- make the shell a client of the service layer
- define event/subscription surface needed for presentation clients

Deliverables:

- shell dispatch routed through services where appropriate
- service event/subscription contract documentation or implementation slice

Acceptance criteria:

- shell is no longer the hidden privileged center
- presentation-tier work has a clear supported integration path

Status:

- complete

Cumulative completion after iteration:

- 92%

### Iteration 9. UX-Ready Boundary Hardening

Track A goals:

- close remaining authority leaks and summary duplication

Track B goals:

- harden public interfaces for secure presentation-tier development tooling

Deliverables:

- final service-boundary cleanup
- policy, audit, and event coverage review
- updated docs describing the supported UX integration model

Acceptance criteria:

- a modern UX can be built over stable, governed public interfaces
- kernel internals can continue evolving without dragging presentation code through churn

Status:

- complete

Cumulative completion after iteration:

- 100%

## Progress Ledger

| Iteration | Focus | Status | Completion |
| --- | --- | --- | --- |
| 1 | Authority and service boundary lock | Complete | 10% |
| 2 | Environment module split | Complete | 22% |
| 3 | Canonical request snapshot | Complete | 34% |
| 4 | Test decomposition and fixture cleanup | Complete | 46% |
| 5 | Provider transport abstraction | Complete | 58% |
| 6 | Governed mutation engine | Complete | 70% |
| 7 | Public service contract extraction | Complete | 82% |
| 8 | Shell-to-service migration | Complete | 92% |
| 9 | UX-ready boundary hardening | Complete | 100% |

## Immediate Next Step

Execution tracker complete. Future work should extend the public service surface, but the kernel-to-service-to-UX boundary is now explicit and governed.

## Post-Tracker Follow-Through

The core kernel-and-services program above is complete.

Subsequent work is now in a different category:

- cross-repository integration cleanup between `sbcl-agent` and `sbcl-agent-ux`
- live-adapter contract hardening
- UX verification and expectation updates as service-backed surfaces continue replacing older shell-first assumptions
- metadata, documentation, and presentation-tier consistency work

That follow-through should be tracked separately from the core architectural program so the implementation record stays honest:

- kernel/service extraction program: complete
- current cross-repository cleanup and UX hardening pass: in progress
- current estimated completion for that follow-through pass: 99%

Open decisions intentionally held outside this tracker:

- whether to repoint the published documentation URL in `sbcl-agent-ux`

Remaining work is now primarily decision closure and release hygiene rather than architectural cleanup.
