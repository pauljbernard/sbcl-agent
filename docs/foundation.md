---
layout: default
title: Foundation
hero_title: Conceptual Foundation
hero_text: "The project makes sense when it is understood as a governed environment built around three linked truths: source, image, and workflow."
eyebrow: Foundation
permalink: /foundation.html
description: What sbcl-agent is, what it is not, and the conceptual model that anchors the implementation.
---
## What the System Is

`sbcl-agent` is a persistent, SBCL-native engineering environment.

Today, that environment is implemented as a real Common Lisp runtime with:

- a CLI and REPL-oriented shell
- direct runtime inspection and evaluation
- durable conversation objects such as threads, turns, operations, and artifacts
- governed workflow records, work-items, approvals, incidents, and reconciliation paths
- an explicit `environment` object that is becoming the primary container for those domains

## What the System Is Not

It is not best understood as:

- a chatbot with tools
- a thin wrapper around an LLM API
- a conventional IDE recreated in Lisp
- a finished production platform with all environment-native services already complete

The codebase is mature enough to demonstrate the model and support real operator flows. It is not yet at the endpoint implied by the roadmap.

## Runtime as Substrate

The live SBCL image is part of the engineering substrate, not disposable infrastructure.

That matters because the runtime holds truths that source files alone do not:

- loaded definitions
- package and symbol state
- object identity
- worker and thread activity
- dynamic bindings
- warm caches and other live resources

This is the main reason `sbcl-agent` can justify an environment-first architecture instead of a file-first agent architecture.

## The Three Truths

The project is organized around three linked truth domains.

### Source Truth

Source truth is the durable, reproducible file-backed world:

- source files
- diffs and patches
- tests
- generated durable artifacts
- git state

### Image Truth

Image truth is the live runtime world:

- loaded code
- heap state
- symbol and package state
- active workers and threads
- runtime resources

### Workflow Truth

Workflow truth is the governed engineering record:

- work-items
- workflow records
- approvals
- validation results
- incidents
- reconciliation artifacts

These truths should not be collapsed into one another. They should be related explicitly.

## Governance as an Intrinsic Property

Governance is not an optional wrapper around the system.

The architecture assumes that useful runtime mutation must be:

- observable
- policy-mediated
- approval-aware where necessary
- linked to evidence
- reconcilable back to durable source truth

That is why workflow records, incidents, approvals, and artifacts exist as native concepts in the codebase rather than as external documentation concerns.

## Current Maturity

The present system should be understood as:

- implemented enough to operate as a real shell, provider runtime, conversation runtime, and governed workflow substrate
- architecturally transitional because `agent-session` compatibility still exists alongside the stronger `environment` model
- directionally clear about the move from session-centered composition toward environment-centered composition

That maturity level should shape how the docs speak about the project: concrete about what exists, explicit about what is transitional, and careful not to present roadmap material as already delivered.
