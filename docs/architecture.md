---
layout: default
title: Architecture and Design
hero_title: Architecture and Design
hero_text: The design goal is not implementation parity with Codex. The goal is a transactional, image-native engineering environment that leverages SBCL while preserving safety, evidence, and reproducibility.
eyebrow: Architecture
permalink: /architecture.html
description: Detailed design and architecture for sbcl-agent.
---
## System Objective

Build a governed, transactional, image-native agent engineering environment that can inspect and mutate the same running system it is reasoning about, while preserving reproducibility, rollback, provenance, and operator trust.

This architecture deliberately uses Codex-like systems as an external benchmark for usefulness, not as an implementation blueprint.

## Architectural Principles

### Three explicit truths

The system models what the project often calls the three truths: three distinct but connected truth domains.

#### Source truth

Source truth covers the checked-in and file-based world:

- source files
- diffs and patches
- tests and fixtures
- generated persistent artifacts
- git state and reproducible build inputs

#### Image truth

Image truth covers the live SBCL image:

- loaded definitions
- symbol and package state
- heap objects and object identity
- dynamic bindings
- caches and memoized values
- active threads and workers
- open resources and runtime handles

#### Workflow truth

Workflow truth covers the durable record of engineering activity:

- work-items
- plans and hypotheses
- introspection evidence
- mutation intents
- runtime observations
- validations
- approvals and interventions
- rollback and quarantine status
- final conclusions

Every meaningful task should answer:

- what changed in source?
- what changed in image?
- what evidence links the two?

### Transactional live-image workflow

The core loop is:

1. inspect source and image
2. plan bounded mutations
3. checkpoint the relevant state
4. mutate source and image deliberately
5. observe runtime effects
6. validate in-image
7. validate from cold state
8. reconcile differences
9. commit, roll back, or quarantine

This is stricter than a basic analyze-plan-execute-validate loop because the live image can both help and mislead.

## Runtime Layers

### CLI and entrypoints

The operator-facing executables in `bin/` launch the SBCL runtime, load the system, and dispatch into the Common Lisp main entrypoint.

Primary commands today:

- `doctor`
- `chat`
- `exec`
- `help`
- `run-tests`

### Shell and command normalization

The interactive shell is implemented in Common Lisp and accepts both:

- shell commands such as `(ask ...)`, `(plan ...)`, and `(tool ...)`
- ordinary Lisp forms for direct evaluation

Command normalization turns recognized forms into structured command records while leaving unrecognized forms available for normal Lisp evaluation.

### Provider boundary

The provider layer abstracts model interaction and returns structured Common Lisp data, not raw untyped text.

Current providers:

- mock provider for local verification and deterministic smoke tests
- OpenAI-compatible provider for external model-backed responses

The provider contract also supports streaming by emitting structured provider events.

### Session runtime

The session layer owns the operator-facing mutable runtime state:

- transcript and event log
- staged assistant actions
- plan summary
- capability grants
- queued tasks and worker metadata
- work-item and workflow record collections

Sessions can be saved and restored, which gives the shell continuity across runs.

### Tool registry

Tools are Common Lisp-callable capabilities that expose structured operations.

Current tool families include:

- filesystem tools
- docs tools
- session tools
- process tools
- git tools
- patch application

The design intent is that tools remain explicit, reviewable, and capability-gated.

### Task queue and workers

Tasks provide background execution infrastructure. Workers execute queued tasks inside the current runtime and expose status for monitoring.

In the long-term design, tasks are subordinate execution units. Work-items remain the top-level engineering unit.

### Work-items and workflow records

Work-items are the core transactional units in the system. Workflow records capture governance, approvals, state transitions, and operator-facing evidence.

Current implementation themes already present in the codebase include:

- checkpoints
- replay identifiers and validator task records
- wait-state reporting
- operator status summaries
- image-only outcomes
- source reconciliation records

## Data Model Overview

### Work-item

A work-item represents a bounded engineering effort.

Typical concerns captured by a work-item:

- goal and scope
- source snapshot and checkpoint references
- image-related observations
- planned and executed validations
- taint and provenance state
- final disposition

### Mutation transaction

A mutation transaction binds a set of source and image changes to a checkpoint and a closure outcome.

Expected closure states:

- committed to source and image
- committed to image only
- rolled back
- quarantined for operator review

### Validator task record

Validator task records track replayable validation steps, including:

- replay grouping
- validator kind
- checkpoint linkage
- status transitions
- resume and replay metadata

### Image reconciliation record

Image reconciliation records document how an image-only result was later brought back into durable source truth.

## Safety Model

### Capability gates

The current runtime uses capability grants to make stateful operations explicit. Present gates include:

- process execution
- git read and git write
- workspace writes

### Checkpointing

Before meaningful mutation, the system should record a checkpoint that ties together the relevant source baseline, image scope, and validation starting point.

The current implementation has checkpoint metadata in the work-item system. The long-term goal is higher-fidelity image capture and rollback support.

### Rollback

Rollback is a first-class architectural requirement even where implementation fidelity is still growing. The intended rollback surface includes both source and image effects.

### Quarantine

Not every task should end in a clean commit or rollback. The architecture explicitly allows unresolved work to be quarantined for operator review.

## Validation Model

### Live validation

Live validation asks whether the mutation improved the currently running image.

### Reproducibility validation

Reproducibility validation asks whether the same result can be reproduced from source in a cold start.

### Reconciliation

If live validation and cold-start validation disagree, the system should preserve that disagreement rather than flattening it into a false binary success.

## Multi-Agent Direction

The intended long-term orchestration model is role isolation rather than unconstrained task fan-out.

Planned roles:

- observer agents inspect but do not mutate
- planner agents propose transactions but do not execute them
- mutation agents operate inside narrow transaction scopes
- reviewer agents inspect diffs, image deltas, and evidence without altering active work
- a supervisor agent owns closure, escalation, and rollback decisions

This ordering matters. Strong transaction boundaries come before aggressive parallelism.

## Module Map

The current source tree maps roughly to the architecture like this:

- `config.lisp`: runtime configuration and provider bootstrap
- `provider-protocol.lisp`, `provider-mock.lisp`, `provider-openai.lisp`: model interaction boundary
- `commands.lisp`, `shell.lisp`, `repl.lisp`, `main.lisp`: operator interface and command execution
- `session.lisp`, `events.lisp`, `tasks.lisp`: session runtime, logging, queues, and workers
- `tools-*.lisp`, `tools-registry.lisp`: structured capability surface
- `policy.lisp`, `sandbox.lisp`, `patch.lisp`: execution governance and workspace mutation controls
- `work-items.lisp`, `workflow.lisp`: transactional engineering record and workflow evidence

## Architectural Gaps

The codebase already demonstrates the core design direction, but some elements remain only partially implemented.

Largest remaining gaps:

- higher-fidelity image checkpoint capture
- stronger rollback of live image changes
- more deterministic replay and provenance export
- deeper role isolation for multi-agent work
- richer cold-start validation orchestration

Those gaps are intentional roadmap items, not hidden assumptions. See [Implementation Plan]({{ '/implementation-plan.html' | relative_url }}) for delivery sequencing.
