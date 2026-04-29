---
layout: default
title: Objectives
hero_title: Product and Architecture Objectives
hero_text: sbcl-agent is trying to become a persistent, image-native, agentic Common Lisp environment where runtimes, conversations, artifacts, and governance all live inside one symbolic world.
eyebrow: Objectives
permalink: /objectives.html
description: Product objectives and success criteria for sbcl-agent.
---
## Reading Position

This document is best read after [The Problem]({{ '/problem.html' | relative_url }}) and [Foundation]({{ '/foundation.html' | relative_url }}).

Those documents explain why the project exists and what conceptual model it is using. This document defines what success should look like given that model.

For the transition from current system to target system, this document should now be read with:

- [sbcl-agent / sbcl-agent-ux Current-State Gap Analysis]({{ '/agentos-current-state-gap-analysis.html' | relative_url }})
- [IntentOS Target-State Architecture]({{ '/agentos-target-state-architecture.html' | relative_url }})
- [IntentOS Constitution]({{ '/intentos-constitution.html' | relative_url }})
- [IntentOS Requirements]({{ '/intentos-requirements.html' | relative_url }})

Both architecture documents include the accepted context diagrams directly, and the docs front page now exposes those diagrams side by side.

## Primary Objective

Build a persistent, image-native, agentic Common Lisp environment that can inspect and mutate the same live system it is reasoning about while preserving operator trust through explicit approvals, durable evidence, and reproducible source-backed outcomes.

## Product Objectives

### 1. Build an Environment, not just a tool

The system should be understood and designed as a persistent symbolic environment rather than as a shell with features or an IDE clone.

That means the architecture should have room for:

- runtimes
- threads
- agents
- artifacts
- work-items
- policies
- histories

### 2. Preserve a direct operator surface

The environment should remain usable as:

- a Common Lisp REPL
- a shell for structured commands
- a persistent conversation runtime

The newer conversation layer should extend the operator surface, not replace the existing directness.

### 3. Make conversation native, but not total

Conversation should no longer be a transient stream attached to one provider response. It should be a durable native medium of interaction, but it should not be mistaken for the whole architecture. It should remain inspectable through:

- threads
- messages
- turns
- operations
- artifacts

### 4. Keep execution state explicit

The running image is part of the substrate, so execution state must stay visible rather than hidden in prompt text or shell side effects.

This means:

- governed tools
- explicit operations
- policy decisions
- approvals and resume points

### 5. Preserve workflow governance

The system should not allow chat convenience to bypass engineering discipline. Mutating work must remain accountable to:

- work-items
- workflow records
- validations
- replay and reconciliation
- operator review

### 6. Treat artifacts and work-items as native entities

The system should not reduce meaningful outcomes to transcript text or shell side effects. Artifacts and work-items should be addressable, durable, and linked to the runtime and interaction history.

### 7. Exploit SBCL-native advantages

The runtime should benefit from what SBCL and Common Lisp make possible:

- direct Lisp evaluation
- live-image inspection
- incremental loading and repair
- close alignment between shell language and implementation language

## Architectural Objectives

The current ownership rule is:

- conversation owns interaction state
- runtime owns execution state
- workflow owns engineering governance

That rule still matters, but it is no longer the whole architectural story. The next stage should place those domains inside an Environment object that becomes the top-level architectural container.

The current refactor adds a second architectural objective that now needs to be stated explicitly:

- compress execution under `invoke`
- compress reads under `inspect`
- compress intervention under `control`
- make execution handles and execution surfaces the primary operator references

The rule exists to avoid three common failures:

- interaction history becoming an accidental runtime database
- runtime behavior being defined by prompts instead of code
- chat workflows bypassing workflow evidence

## Operational Objectives

The runtime should let an operator answer these questions clearly after meaningful work:

1. What changed in source?
2. What changed in the running image?
3. What evidence links the two?
4. What still needs approval, validation, reconciliation, or rollback?

## Interaction Objectives

The finished system should support multiple coherent modes inside one environment:

### REPL mode

The user types Lisp forms or shell commands and gets immediate structured results.

### Conversation mode

The user works in durable threads and turns where assistant text can stream, operations can run behind the scenes, artifacts can be created, and context can persist beyond a single form evaluation.

### Agent mode

Resident or background agents participate as governed actors with explicit identity, scope, capabilities, and event subscriptions.

### Workflow mode

Work-items, validations, checkpoints, approvals, and reconciliations operate as environment-native engineering behaviors rather than as external paperwork.

## Delivery Objectives

Near-term success means:

- the docs describe the current runtime honestly
- the docs describe the current execution-kernel transition honestly
- the docs explain the problem before the architecture
- the shell and docs use one consistent vocabulary
- conversation primitives are documented as implemented, not just planned
- `sbcl-agent-ux` is described as a host over shell and desktop contracts rather than as an unrelated client
- the current platform/package lifecycle is described as implemented work rather than only as future intent
- strengths and weaknesses are stated explicitly
- the roadmap clearly distinguishes what is live from what is still forthcoming

Longer-term success means:

- a concrete Environment object in the codebase
- a non-bypassable execution-kernel boundary
- runtime-native tools for governed image inspection and mutation
- a first-class shell over execution surfaces
- compatibility-backed hosted executions treated as governed executions rather than raw process launches
- a consumable developer platform with package, profile, and SDK semantics
- richer artifact coverage across mutating workflows
- stronger crash recovery and resumability
- clearer workflow linkage for conversational and agent-driven engineering work

## Current Objective Attainment

Against the accepted target architecture, the repository now satisfies the core objective set:

- the `Environment` object is real
- the execution-kernel boundary is real
- governed compatibility execution is real
- the shell and desktop host model are real
- the developer platform is real

What remains after this point is not unresolved target architecture. It is:

- deeper ecosystem and platform breadth
- stronger alternate backend realism
- broader artifact and recovery depth
- more operator polish and QA evidence

## Non-Objectives

The project is not trying to:

- reproduce Codex internals exactly
- reproduce a conventional IDE surface as the architectural goal
- replace Common Lisp REPL usage with chat-only workflows
- flatten source truth, image truth, and workflow truth into one transcript
- treat live-image success as sufficient proof of correctness

## Success Criteria

The project is on track when:

- operators can work directly in Lisp, in conversation, or through governed agents without changing environments
- approvals and workflow evidence remain visible under mutating workloads
- threads, artifacts, and governed work survive normal interruptions
- the docs, shell, and code all describe the same architecture
- a new reader can understand why the system exists before reading roadmap material
