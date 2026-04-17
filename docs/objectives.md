---
layout: default
title: Objectives
hero_title: Product and Architecture Objectives
hero_text: sbcl-agent is trying to become a persistent, SBCL-native engineering runtime where conversation, execution, and workflow evidence are coordinated rather than conflated.
eyebrow: Objectives
permalink: /objectives.html
description: Product objectives and success criteria for sbcl-agent.
---
## Primary Objective

Build an SBCL-native engineering runtime that can inspect and mutate the same live system it is reasoning about while preserving operator trust through explicit approvals, durable evidence, and reproducible source-backed outcomes.

## Product Objectives

### 1. Preserve a direct operator surface

The system should remain usable as:

- a Common Lisp REPL
- a shell for structured commands
- a persistent conversation runtime

The newer conversation layer should extend the operator surface, not replace the existing directness.

### 2. Make conversation first-class

Conversation should no longer be a transient stream attached to one provider response. It should be durable and inspectable through:

- threads
- messages
- turns
- operations
- artifacts

### 3. Keep execution state explicit

The running image is part of the substrate, so execution state must stay visible rather than hidden in prompt text or shell side effects.

This means:

- governed tools
- explicit operations
- policy decisions
- approvals and resume points

### 4. Preserve workflow governance

The system should not allow chat convenience to bypass engineering discipline. Mutating work must remain accountable to:

- work-items
- workflow records
- validations
- replay and reconciliation
- operator review

### 5. Exploit SBCL-native advantages

The runtime should benefit from what SBCL and Common Lisp make possible:

- direct Lisp evaluation
- live-image inspection
- incremental loading and repair
- close alignment between shell language and implementation language

## Architectural Objectives

The architectural rule is:

- conversation owns interaction state
- runtime owns execution state
- workflow owns engineering governance

That rule exists to avoid three common failures:

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

The finished system should support two coherent modes on top of one runtime:

### REPL mode

The user types Lisp forms or shell commands and gets immediate structured results.

### Conversation mode

The user works in durable threads and turns where assistant text can stream, operations can run behind the scenes, artifacts can be created, and context can persist beyond a single form evaluation.

## Delivery Objectives

Near-term success means:

- the docs describe the current runtime honestly
- the shell and docs use one consistent vocabulary
- conversation primitives are documented as implemented, not just planned
- the roadmap clearly distinguishes what is live from what is still forthcoming

Longer-term success means:

- runtime-native tools for governed image inspection and mutation
- richer artifact coverage across mutating workflows
- stronger crash recovery and resumability
- clearer workflow linkage for chat-driven engineering work

## Non-Objectives

The project is not trying to:

- reproduce Codex internals exactly
- replace Common Lisp REPL usage with chat-only workflows
- flatten source truth, image truth, and workflow truth into one transcript
- treat live-image success as sufficient proof of correctness

## Success Criteria

The project is on track when:

- operators can work directly in Lisp or in conversation without changing runtimes
- approvals and workflow evidence remain visible under mutating workloads
- threads and turns are durable enough to survive normal interruptions
- the docs, shell, and code all describe the same architecture
