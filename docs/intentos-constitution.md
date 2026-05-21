---
layout: default
title: IntentOS Constitution
hero_title: IntentOS Constitution
hero_text: The governing product and architecture rules that keep the current runtime, the transition plan, and the target operating system aligned.
eyebrow: Constitution
permalink: /intentos-constitution.html
description: Foundational product and architecture constitution for the transition from sbcl-agent to IntentOS.
---

# IntentOS Constitution

> Historical note: this page preserves the governing doctrine of the IntentOS transition program. The current implemented system now realizes those constraints through a shared concurrency/execution substrate, actor-owned governance and effect handling, and a self-hosted introspective environment runtime rather than through a standalone kernel tier.

## Purpose

This constitution defines the non-negotiable rules for evolving the current `sbcl-agent / sbcl-agent-ux` system into `IntentOS`.

It exists to prevent three kinds of drift:

- feature growth without execution-boundary compression
- desktop UX growth without a system model
- compatibility growth that bypasses governance

## Governing Principle

IntentOS is not a desktop application that happens to contain an agent runtime.

IntentOS is a governed execution-centric operating environment built out of an image-native agent runtime.

It is microkernel-inspired in discipline, but its primary object is the governed execution rather than the process.

That means:

- the live SBCL image remains the native execution and governance substrate
- governed execution remains the primary semantic primitive
- compatibility layers remain subordinate to the native runtime model
- UX remains a shell over inspectable system objects, not a generic app shell
- the operating environment may act proactively, but only through governed, inspectable execution

## Constitutional Rules

### 1. Governed execution comes first

Every meaningful system action must be representable as a governed execution with:

- intention
- capability
- authority
- state
- trace

### 2. Native authority remains in the SBCL runtime

Execution logic, governance, execution records, lifecycle state, trace, and policy remain owned by the SBCL image substrate.

Foreign runtimes may be hosted, but they do not become independent system authorities.

### 2A. IntentOS is proactive, not merely reactive

Traditional operating systems largely wait for explicit user commands and then react.

IntentOS may also:

- observe continuously
- prepare continuations
- stage next actions
- recommend interventions
- initiate governed recovery or resumption

But proactivity is only constitutional when it remains:

- policy-bounded
- attributable
- inspectable
- interruptible
- trace-producing
- authority-limited

### 3. No bypass paths

Execution convenience cannot bypass:

- policy
- approval
- checkpointing
- trace
- inspectability
- control

### 4. The shell is a system shell, not an application shell

The UX must evolve toward a workspace of governed executions and related system objects.

The desktop cannot remain a feature dashboard over ad hoc state.

### 5. Compatibility is subordinate

Linux apps, tools, browsers, containers, and external runtimes are hosted capabilities.

They may execute outside SBCL physically, but they remain governed by SBCL semantically.

### 6. Every visible element must be inspectable

This is both a UX invariant and a system invariant.

If the user can see it, the system must be able to identify it as an object with inspectable state.

### 6A. Every proactive move must also be inspectable

Proactive system behavior cannot hide in background convenience.

If the system:

- recommends
- stages
- resumes
- monitors
- recovers
- intervenes

then that behavior must appear as a governed system object or execution with visible rationale and control posture.

### 7. Current state and target state must both be documented honestly

The system must always preserve:

- a truthful current-state description
- a truthful target-state description
- a visible gap model between them

### 8. Validation is architectural, not cosmetic

Testing must prove:

- execution and governance invariants
- execution-handle ownership
- governance integrity
- shell/object coherence
- compatibility containment

## Transition Rule

During transition, the repo must support two truths at once:

- the current system is still `sbcl-agent / sbcl-agent-ux`
- the direction of travel is `IntentOS`

Refactors should move the implementation toward the target model without lying about what is already complete.

## Immediate Implication

Every future feature, UX surface, capability adapter, and external integration should answer:

1. What execution object does this create or operate on?
2. What execution or governance boundary owns it?
3. How is it inspected?
4. How is it controlled?
5. How does it preserve governance?
