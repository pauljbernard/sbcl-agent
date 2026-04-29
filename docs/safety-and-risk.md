---
layout: default
title: Safety and Risk
hero_title: Safety and Risk Model
hero_text: sbcl-agent does not remove risk. It shifts risk from strict isolation boundaries toward governed execution that must remain observable, reversible, and reviewable.
eyebrow: Safety
permalink: /safety-and-risk.html
description: The safety model, risk categories, and governance principles behind sbcl-agent.
---
## Honest Position

`sbcl-agent` should not be sold as safe because it is powerful.

It is only safe to the extent that its power is governed explicitly.

The system does not eliminate risk. It makes risk more visible and more governable than a loosely coupled runtime-plus-transcript workflow.

## Core Risk Shift

The risk model moves from isolation-first assumptions toward governed execution.

Instead of assuming safety comes from keeping the runtime at arm's length, the project assumes useful work sometimes requires direct interaction with the runtime and therefore must be constrained through policy, approvals, evidence, and reconciliation.

## Risk Categories

### Runtime Mutation Risk

Direct eval, patches, and write-class tools can change the system incorrectly or incompletely.

### Agent Misalignment

An agent can choose the wrong action, misinterpret intent, or pursue an invalid local optimization.

### State Drift

Long-lived environments can accumulate differences between what source, runtime, and workflow each imply.

### Reproducibility Loss

A success in the warm image may fail to survive reload, restart, or source-based reconstruction.

### Prompt and Context Injection

Conversation and tool inputs can carry misleading or malicious instructions.

### Expanded Security Surface

Filesystem, process, runtime, and tool access increase the blast radius of mistakes when not controlled tightly.

## Safety Principles

The current architecture points toward these principles:

- default-deny mutation where policy requires it
- explicit capability grants
- approval-gated execution for sensitive actions
- durable audit trails through events, work-items, workflow records, and artifacts
- reconciliation between source and runtime rather than reliance on runtime success alone
- incident capture instead of silent failure loss

## Governance Model

The main governance mechanisms already present in the codebase are:

- policy gates
- approval checkpoints
- work-items
- workflow records
- incidents
- turn resume and staged-action handling
- validation and reconciliation paths

## Critical Safety Condition

The system is only safe enough for meaningful use when mutation is:

- governed
- observable
- reversible, or at least quarantinable with evidence

If one of those conditions is missing, the system becomes hard to trust.

## Current Strengths

Today the codebase already has real safety-relevant strengths:

- explicit policy and sandbox layers
- approval-aware turn orchestration
- incident recording
- workflow waiting states
- environment and workflow evidence summaries

## Current Weaknesses

The current implementation is still weak in places the docs should acknowledge honestly:

- some compatibility and persistence adapter paths still exist
- deeper cold-start validation and rollback fidelity are not complete
- operation coverage and artifact coverage are stronger than before but not yet universal
- the environment-native agent model is shallower than the runtime, workflow, and compatibility layers

The right documentation stance is not to hide these weaknesses. It is to show how the existing design addresses them and where the remaining gaps are.
