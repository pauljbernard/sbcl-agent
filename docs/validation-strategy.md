---
layout: default
title: IntentOS Validation Strategy
hero_title: IntentOS Validation Strategy
hero_text: Validation must prove the architecture, not just the behavior of isolated features.
eyebrow: Validation
permalink: /validation-strategy.html
description: Validation strategy for the transition from sbcl-agent to IntentOS.
---

# IntentOS Validation Strategy

## Purpose

This strategy defines how the project should validate and sustain the now-implemented IntentOS target architecture in `sbcl-agent` and `sbcl-agent-ux`, while guiding enhancement work that deepens backend realism, forensic depth, UX coherence, and platform confidence.

## Validation Thesis

Validation must prove five things:

1. execution and governance invariants are real
2. execution handles are the true system abstraction
3. governance remains non-bypassable
4. the shell reflects real system objects
5. compatibility remains subordinate to the native runtime model

## Validation Layers

### 1. Current-State Integrity

Protect what is already true.

Examples:

- governed mutation flow
- runtime/image evidence
- approval and resume behavior
- environment persistence
- desktop posture rendering

### 2. Execution Invariant Validation

Prove:

- execution begins through `invoke`
- every governed execution is inspectable
- every governed execution is controllable
- policy and authority are not bypassed

### 3. Execution-Handle Validation

Prove:

- execution ids are durable and meaningful
- state, authority, and trace remain attached
- read models and shell surfaces can rely on them

### 4. UX / Shell Validation

Prove:

- visible state corresponds to real objects
- inspection surfaces expose real state
- blocked and mutating posture are explicit
- execution surfaces are coherent

### 5. Compatibility Validation

As compatibility work arrives, prove:

- foreign runtimes are hosted as governed executions
- filesystem, network, display, and lifecycle policy are attached
- inspect and control still work through the native system

### 6. Platform Validation

As platform work arrives, prove:

- manifests are valid
- packages are valid, importable, activatable, and installable
- applied active-package profiles are coherent
- simulation and test harnesses are usable
- version/update behavior is coherent

## Required Validation Artifacts

For each major phase, maintain:

- requirement mapping
- acceptance criteria
- targeted tests
- regression tests
- full-suite status

## Current Validation Entry Points

The current repository should be validated through a layered set of entrypoints rather than one monolithic suite:

- baseline runtime health:
  - `./bin/sbcl-agent doctor`
- broader backend regression:
  - `./bin/run-tests`
  - `./bin/run-coverage`
- dedicated concurrency validation:
  - `./bin/run-concurrency-regression`
  - `./bin/run-concurrency-performance`
- dedicated actor-system validation:
  - `./bin/run-actor-system-regression`
  - `./bin/run-actor-system-performance`

These commands now represent the most honest validation shape of the implemented architecture: broad smoke and service coverage for the whole runtime, then focused regression and performance coverage for the concurrency substrate and the actor runtime itself.

## Current Baseline Snapshot

Latest local validation snapshot recorded during this documentation rebaseline on `2026-05-20`:

- `doctor`: passed
- concurrency regression: passed
- actor-system regression: passed
- actor-system performance: passed
- concurrency performance: failed one enforced default budget
  - `MIXED-LOAD-ACTOR-DISPATCH-LATENCY`
  - observed average: `1.04 ms`
  - configured default budget: `1.00 ms`

That is the correct current posture to document: the dedicated validation program is real and broad, but it is not uniformly green.

## Review Standard

A change is not validated merely because the UI looks correct or a single command works.

It is validated when:

- the relevant invariant is identified
- the relevant system object is explicit
- the relevant test layers are run
- the result is reported honestly

## Immediate Priority

The next validation work should track:

1. current-state behavioral integrity and full-suite stability
2. execution and governance invariant sustainment
3. backend-realism and compatibility containment
4. shell / desktop / UX contract coherence
5. platform and QA evidence governance

That order preserves a green architecture while tightening the confidence model around it.
