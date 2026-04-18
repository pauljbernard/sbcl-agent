---
layout: default
title: Codex Execution Plan
hero_title: Codex Execution Plan
hero_text: A detailed, implementation-oriented plan for transforming the current codebase into the Environment-centered system described by the roadmap vision.
eyebrow: Execution
permalink: /roadmap/codex-execution-plan.html
description: Detailed phased implementation plan for Codex to execute against the current sbcl-agent codebase.
---
## Purpose

This document is not a vision statement. It is an execution plan.

Its job is to translate the new roadmap direction into a sequence of concrete implementation passes that a coding agent can execute against the current repository without losing architectural discipline.

The plan assumes the current codebase already provides:

- an SBCL-native CLI and shell
- provider abstraction and streaming normalization
- threads, turns, operations, and artifacts
- work-items, workflow records, replay, checkpoints, and reconciliation
- approval-aware mutation flows
- session persistence

The plan began from a point where the Environment architecture did not yet exist in code. That is no longer true: the repository now has a concrete Environment object, save/load support, projected environment events, and environment-oriented shell commands. The remaining work is to deepen and normalize that architecture rather than introduce it from scratch.

## Execution Rules

Every implementation iteration should follow these rules:

1. Preserve the direct Lisp shell and current command surface unless a change is explicitly part of a compatibility migration.
2. Keep orchestration logic in Common Lisp, not in prompt tricks.
3. Preserve capabilities from classic Lisp tooling, but do not let editor-centric metaphors drive architecture.
4. Route all meaningful mutation through operation records, policy checks, and workflow evidence.
5. Treat conversation as one subsystem of the Environment, not the top-level architecture.
6. Prefer additive compatibility layers over destructive rewrites until the Environment object is stable.
7. Ship each phase with tests, documentation updates, and explicit acceptance criteria.

## Current Architectural Starting Point

The current code is organized around a transitional composition root in [`src/session.lisp`](/Volumes/data/development/sbcl-agent/src/session.lisp), plus conversation and workflow subsystems:

- [`src/session.lisp`](/Volumes/data/development/sbcl-agent/src/session.lisp)
- [`src/conversation.lisp`](/Volumes/data/development/sbcl-agent/src/conversation.lisp)
- [`src/turn-orchestrator.lisp`](/Volumes/data/development/sbcl-agent/src/turn-orchestrator.lisp)
- [`src/provider-protocol.lisp`](/Volumes/data/development/sbcl-agent/src/provider-protocol.lisp)
- [`src/shell.lisp`](/Volumes/data/development/sbcl-agent/src/shell.lisp)
- [`src/work-items.lisp`](/Volumes/data/development/sbcl-agent/src/work-items.lisp)
- [`src/workflow.lisp`](/Volumes/data/development/sbcl-agent/src/workflow.lisp)
- [`src/tasks.lisp`](/Volumes/data/development/sbcl-agent/src/tasks.lisp)

The Environment now exists in code. The biggest structural gap is that it is still partly a compatibility composition root rather than the unquestioned primary truth container for:

- runtimes
- threads
- agents
- artifact graph
- work-item graph
- policy engine
- event bus
- persistence and recovery

## Workstreams

The plan is organized into six workstreams that can be executed incrementally but should be kept conceptually separate.

### Workstream A. Environment Core

Goal:

- introduce the Environment as the real top-level architectural object

### Workstream B. Runtime and Symbolic Services

Goal:

- preserve and extend the enduring powers of classic Lisp environments in environment-native form

### Workstream C. Conversation and Agent Participation

Goal:

- keep threads and turns strong, but relocate them inside the larger Environment model

### Workstream D. Artifact and Knowledge Graph

Goal:

- make artifacts, relationships, and symbolic navigation first-class

### Workstream E. Workflow, Validation, and Recovery

Goal:

- make governed engineering behavior durable and trustworthy under mutation, interruption, and recovery

### Workstream F. Operator Surfaces

Goal:

- keep the shell direct while exposing the new Environment semantics coherently

## Phase Plan

## Phase 1: Introduce the Environment Object

### Goal

Create a concrete Environment object and make it the new composition root without breaking the existing shell.

### Files to Add

- `src/environment.lisp`
- `src/environment-store.lisp`

### Files to Modify

- [`src/session.lisp`](/Volumes/data/development/sbcl-agent/src/session.lisp)
- [`src/main.lisp`](/Volumes/data/development/sbcl-agent/src/main.lisp)
- [`src/shell.lisp`](/Volumes/data/development/sbcl-agent/src/shell.lisp)
- [`sbcl-agent.asd`](/Volumes/data/development/sbcl-agent/sbcl-agent.asd)

### Environment Object Requirements

The initial `environment` struct or class should own references to:

- environment id
- schema version
- storage root
- runtime set
- active runtime id
- thread set
- active thread id
- artifact index or graph
- work-item graph root
- workflow records
- agent registry
- policy engine state
- event bus or event log root
- environment summaries and memory
- compatibility session bridge

### Compatibility Strategy

Do not delete `agent-session` yet.

Instead:

- make `agent-session` a compatibility component owned by the Environment
- move shell startup to create or load an Environment first
- let existing shell commands continue to operate through the current session APIs until they are migrated

### Acceptance Criteria

- shell startup creates an Environment
- session summary can report environment id and active runtime/thread
- save/load persists the Environment container
- existing shell commands still work
- test suite remains green

### Tests to Add

- `environment-creation-test`
- `environment-persistence-test`
- `environment-shell-bootstrap-test`

## Phase 2: Separate Environment Domains Internally

### Goal

Break the current mixed session state into explicit domain groupings under the Environment.

### Files to Add

- `src/runtime-state.lisp`
- `src/conversation-state.lisp`
- `src/workflow-state.lisp`
- optional `src/agent-state.lisp`

### Files to Modify

- [`src/session.lisp`](/Volumes/data/development/sbcl-agent/src/session.lisp)
- [`src/conversation.lisp`](/Volumes/data/development/sbcl-agent/src/conversation.lisp)
- [`src/work-items.lisp`](/Volumes/data/development/sbcl-agent/src/work-items.lisp)
- [`src/workflow.lisp`](/Volumes/data/development/sbcl-agent/src/workflow.lisp)

### Domain Split

Move toward explicit internal state buckets:

- conversation state: threads, messages, turns, conversational summaries
- runtime state: runtimes, packages, loaded systems, eval history, resources, runtime observations
- workflow state: work-items, workflow records, checkpoints, validations, reconciliation, approvals
- agent state: identities, roles, subscriptions, memory, capability scope

### Acceptance Criteria

- Environment exposes inspection APIs per domain
- internal code stops treating `agent-session` as the primary truth container
- persistence format clearly nests domain state under the Environment

### Tests to Add

- `environment-domain-summary-test`
- `environment-load-domain-rebuild-test`

## Phase 3: Runtime Service Layer

### Goal

Translate the enduring powers of legacy Lisp tooling into explicit environment-native runtime services.

### Files to Add

- `src/runtime-services.lisp`
- `src/tools-runtime.lisp`
- optional `src/symbol-graph.lisp`

### Capabilities to Implement

- inspect runtime state
- evaluate forms in context
- macroexpand in context
- inspect symbol definitions
- inspect packages and loaded systems
- find callers and references where feasible
- inspect object state structurally
- reload or reconcile runtime definitions deliberately

### Policy Surface

Define explicit policies for:

- `:runtime-read`
- `:runtime-eval-safe`
- `:runtime-eval-mutate`
- `:runtime-reload`
- `:runtime-debug`
- `:runtime-reconcile`

### Command Surface

Add environment-native command forms such as:

- `(runtime/current)`
- `(runtime/list)`
- `(runtime/use "runtime-id")`
- `(runtime/summary)`
- `(runtime/eval '(...))`
- `(runtime/inspect 'symbol-or-object)`
- `(runtime/find-definition 'symbol)`
- `(runtime/find-callers 'symbol)`

### Acceptance Criteria

- direct runtime services work without bypassing policy
- mutating runtime services create operation records
- risky runtime mutations can create or attach work-items

### Tests to Add

- `runtime-summary-command-test`
- `runtime-read-policy-test`
- `runtime-mutating-eval-governance-test`
- `runtime-find-definition-test`

## Phase 4: Runtime Incident and Recovery Workflow

### Goal

Transform debugger-like functionality into governed runtime incident workflows rather than keeping it as ad hoc inspection.

### Files to Add

- `src/incidents.lisp`
- optional `src/restarts.lisp`

### Core Model

Introduce an `incident` record with:

- incident id
- originating runtime
- condition summary
- stack or frame summary
- restart options
- linked thread id
- linked work-item id
- linked artifact ids
- status

### Behavior

When meaningful runtime failures occur:

- capture them as incident records
- emit environment events
- allow conversational and direct shell inspection
- allow approved repair or restart actions
- attach artifacts and workflow evidence

### Acceptance Criteria

- a runtime condition can be represented as a durable incident
- incidents can be inspected after the fact
- repair actions are governed and recorded

### Tests to Add

- `runtime-incident-capture-test`
- `incident-work-item-linkage-test`
- `incident-repair-approval-test`

## Phase 5: Artifact Graph

### Goal

Move from a flat artifact list toward an artifact graph with explicit relationships.

### Files to Add

- `src/artifact-graph.lisp`

### Files to Modify

- [`src/conversation.lisp`](/Volumes/data/development/sbcl-agent/src/conversation.lisp)
- [`src/work-items.lisp`](/Volumes/data/development/sbcl-agent/src/work-items.lisp)
- [`src/workflow.lisp`](/Volumes/data/development/sbcl-agent/src/workflow.lisp)

### Relationship Types

At minimum, support links such as:

- operation produced artifact
- turn references artifact
- work-item references artifact
- artifact supersedes artifact
- artifact validates artifact
- artifact reconciles artifact
- artifact derived from source path
- artifact derived from runtime observation

### Artifact Expansion

Ensure artifacts exist for:

- file writes
- diffs
- patches
- plans
- validation results
- checkpoints
- reconciliation results
- runtime incidents
- runtime observation summaries

### Acceptance Criteria

- artifacts are queryable by relationship
- artifact lineage is inspectable
- artifact creation becomes consistent across mutation flows

### Tests to Add

- `artifact-graph-linkage-test`
- `artifact-lineage-test`
- `validation-artifact-linkage-test`

## Phase 6: Semantic Navigation Layer

### Goal

Replace “source browser” thinking with environment graph navigation across source, image, artifacts, and work-items.

### Files to Add

- `src/navigation.lisp`
- optional `src/knowledge-graph.lisp`

### Features

Implement environment queries such as:

- source definition to runtime definition
- symbol to callers
- symbol to artifacts
- source path to work-items
- work-item to turns
- artifact to operations
- runtime object or package to incident history

### Shell/API Surface

Potential commands:

- `(nav/symbol 'foo)`
- `(nav/file "src/x.lisp")`
- `(nav/work-item "work-id")`
- `(nav/artifact "artifact-id")`

### Acceptance Criteria

- navigation can cross domain boundaries
- results are expressed in environment-native entities rather than file-only locations

### Tests to Add

- `symbol-navigation-test`
- `work-item-to-artifact-navigation-test`
- `source-runtime-linkage-navigation-test`

## Phase 7: Agent Registry and Resident Actors

### Goal

Introduce agents as explicit environment inhabitants rather than hidden provider behavior.

### Files to Add

- `src/agents.lisp`
- `src/agent-registry.lisp`
- optional `src/agent-memory.lisp`

### Initial Agent Model

Each agent should carry:

- agent id
- role
- policy scope
- subscriptions
- status
- working context or memory summary
- allowed runtime or thread scope

### Minimal First Agents

Start with simple environment-native agent roles:

- planner
- validator
- reconciler
- runtime observer

These do not need autonomous execution at first. They can begin as explicit typed actors invoked by commands and events.

### Acceptance Criteria

- environment can register and inspect agents
- agents can subscribe to event families
- agents operate under explicit policy scope

### Tests to Add

- `agent-registry-test`
- `agent-policy-scope-test`
- `agent-event-subscription-test`

## Phase 8: Validation Pipeline and Cold Evidence

### Goal

Make validation and evidence generation more automatic so warm-image success does not masquerade as durable success.

### Files to Modify

- [`src/work-items.lisp`](/Volumes/data/development/sbcl-agent/src/work-items.lisp)
- [`src/workflow.lisp`](/Volumes/data/development/sbcl-agent/src/workflow.lisp)
- [`src/turn-orchestrator.lisp`](/Volumes/data/development/sbcl-agent/src/turn-orchestrator.lisp)

### Requirements

- governed mutation turns automatically create validation plans
- live validation and cold validation stay distinct
- closure decisions depend on validation state
- reconciliation remains explicit when source and image diverge

### Status Model

Introduce or formalize statuses such as:

- `:awaiting-live-validation`
- `:awaiting-cold-validation`
- `:awaiting-reconciliation`
- `:committed`
- `:image-only`
- `:quarantined`

### Acceptance Criteria

- mutation turns do not appear fully complete on warm-image evidence alone
- status views expose live versus cold evidence separately

### Tests to Add

- `governed-turn-live-vs-cold-validation-test`
- `work-item-closure-gating-test`
- `reconciliation-required-status-test`

## Phase 9: Environment Event Bus

### Goal

Make the event bus explicitly environment-scoped and rich enough for agents, UI, recovery, and observability.

### Files to Add

- optional `src/environment-events.lisp`

### Event Families

Ensure explicit event families for:

- environment
- runtime
- conversation
- operation
- artifact
- workflow
- incident
- agent

### Acceptance Criteria

- all major entities emit environment-scoped events
- event payloads include environment id and related entity ids
- event consumers no longer need to infer architecture from ad hoc payloads

### Tests to Add

- `environment-event-envelope-test`
- `agent-subscription-event-test`

## Phase 10: Operator Surfaces

### Goal

Expose the Environment model coherently through the shell without sacrificing directness.

### Files to Modify

- [`src/shell.lisp`](/Volumes/data/development/sbcl-agent/src/shell.lisp)
- [`src/commands.lisp`](/Volumes/data/development/sbcl-agent/src/commands.lisp)

### Commands to Add

- `(environment/show)`
- `(environment/save)`
- `(environment/load "path")`
- `(runtime/list)`
- `(agent/list)`
- `(artifact/graph)`
- `(incident/list)`
- `(nav/...)`

### Rendering Goals

- environment summary at top level
- current runtime and current thread visible
- blocked approvals and pending validations visible
- incidents and image/source divergence visible
- artifacts and work-items navigable from the shell

### Acceptance Criteria

- shell feels like an operator interface to one living environment
- existing REPL and command workflows remain intact

### Tests to Add

- `environment-shell-summary-test`
- `agent-list-command-test`
- `incident-list-command-test`

## Phase 11: Recovery and Checkpointing

### Goal

Make the Environment durable under interruption.

### Requirements

- persist environment schema and version
- persist active runtimes, threads, artifacts, work-items, and agents
- mark incomplete turns and operations
- restore resumable state on load
- preserve incident and validation evidence

### Acceptance Criteria

- environment can survive restart with meaningful state intact
- incomplete work remains inspectable and resumable

### Tests to Add

- `environment-recovery-test`
- `interrupted-turn-recovery-test`
- `interrupted-validation-recovery-test`

## Codex Iteration Protocol

Each implementation pass should use the following cycle:

1. Read the relevant roadmap and architecture docs.
2. Inspect the current files in scope.
3. Update docs first if terminology or behavior changes.
4. Implement the smallest coherent vertical slice for the phase.
5. Add or extend tests for that slice.
6. Run the relevant test suite.
7. Summarize what was completed, what remains, and any architectural drift observed.

## Recommended Execution Order

This is the recommended order of actual implementation:

1. Phase 1: Environment object
2. Phase 2: internal domain separation
3. Phase 9: environment event bus
4. Phase 3: runtime service layer
5. Phase 4: incident and recovery workflow
6. Phase 5: artifact graph
7. Phase 6: semantic navigation
8. Phase 7: agent registry
9. Phase 8: validation and cold evidence
10. Phase 10: operator surfaces
11. Phase 11: recovery and checkpointing

This order matters because:

- the Environment must exist before too many new features deepen the old session-centered shape
- runtime services and incidents are the most direct translation of classic Lisp tooling powers
- artifact graph and navigation depend on stable entity ownership
- agents should arrive only after events, policy, and entity structure are sound

## Definition of Done for the Vision Pivot

The environment-first pivot can be considered materially implemented when all of the following are true:

- the code has a real Environment object
- runtime, conversation, workflow, artifact, and agent domains are explicit inside it
- legacy Lisp tooling powers are available as environment-native services
- conversation is one strong subsystem, not the architectural center
- agents are explicit residents rather than hidden helper behavior
- artifacts and work-items are linked through a graph rather than only flat lists
- validation and reconciliation are environment-visible and status-bearing
- shell interaction reflects the Environment model without losing direct Lisp control

At that point the project will no longer be a shell growing sideways. It will have crossed into the architecture described by the vision.
