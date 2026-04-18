---
layout: default
title: Mutation Model
hero_title: How Governed Change Works
hero_text: sbcl-agent treats mutation as a lifecycle that must remain observable, policy-aware, resumable, and evidence-producing.
eyebrow: Mutation
permalink: /mutation-model.html
description: The inspect-plan-checkpoint-mutate-observe-validate-reconcile model for governed change in sbcl-agent.
---
## Why a Mutation Model Exists

The project is valuable only if it can support direct runtime and source mutation without collapsing operator trust.

That requires a lifecycle stronger than “run a tool and hope.”

## Lifecycle

The intended lifecycle is:

1. Inspect
2. Plan
3. Checkpoint
4. Mutate
5. Observe
6. Validate
7. Reconcile
8. Commit or quarantine

This is not just a conceptual ideal. The current codebase already contains much of this shape through work-items, workflow records, approvals, incidents, reconciliation paths, and turn-linked operations.

## Inspect

Before mutation, the operator or agent should be able to inspect:

- source state
- runtime state
- current thread and turn context
- relevant workflow or incident context

This is one reason the environment, runtime, and conversation domains are kept explicit.

## Plan

Mutating work should have an intentional goal, not only an action.

That goal is what lets the system connect a concrete change to a work-item, workflow record, and validation burden.

## Checkpoint

Before risky mutation, the system should preserve enough state and evidence to support review, recovery, or replay.

In practice this can include:

- approval checkpoints
- staged actions
- work-item state
- workflow entries
- artifact evidence

## Mutate

Mutation may occur through:

- patches
- governed runtime evaluation
- write-class tools
- provider-assisted action execution

The important rule is that mutation should not bypass policy and workflow tracking merely because it is convenient to invoke from a conversational turn.

## Observe

Immediate runtime outcome still matters.

The system should capture:

- whether the mutation executed
- what operation records were produced
- whether an incident occurred
- what the warm runtime now shows

## Validate

Runtime success is not sufficient proof.

Validation needs to distinguish between:

- warm-image success
- colder validation that can survive restart or reconcile against source truth

The current workflow model already acknowledges this with explicit waiting states such as `:awaiting-cold-validation`.

## Reconcile

A governed runtime system must account for divergence between:

- what source says
- what the image currently contains
- what the workflow record claims

Reconciliation is the step that turns a successful live intervention into a trustworthy engineering outcome.

## Commit or Quarantine

At the end of the lifecycle, the work should either:

- close with sufficient evidence
- remain blocked pending approval or validation
- or be quarantined for operator review

This is one of the strongest distinctions between `sbcl-agent` and tool-mediated agent shells that optimize for completion messages rather than governed closure.

## Artifacts as Evidence

Artifacts are not decoration. They are part of the mutation model.

They provide durable, inspectable outputs that connect turns, operations, work-items, validations, incidents, and reconciliation steps into an evidence chain an operator can actually review.
