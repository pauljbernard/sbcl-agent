---
layout: default
title: IntentOS Feature Specification Discipline
hero_title: IntentOS Feature Specification Discipline
hero_text: A common structure for specifying new work so features do not outrun the kernel model, UX model, or governance model.
eyebrow: Feature Specs
permalink: /intentos-feature-specifications.html
description: Feature specification format for IntentOS-oriented work.
---

# IntentOS Feature Specification Discipline

## Why this exists

The project is now at risk of building locally useful features that do not strengthen the transition from:

- current governed runtime and desktop app

to:

- execution-handle operating system

Every substantial feature should therefore be specified against the architecture, not only against user-visible behavior.

## Required Spec Sections

### 1. Problem

State the operator or system problem being solved.

### 2. Current-State Context

Explain how the feature fits the current `sbcl-agent / sbcl-agent-ux` architecture.

### 3. Target-State Alignment

Explain how the feature advances the `IntentOS` target architecture.

### 4. Primary Objects

Specify which first-class objects are involved:

- execution
- capability
- authority
- trace
- policy
- artifact
- work-item
- runtime
- surface

### 5. Kernel Boundary

State explicitly:

- what is invoked
- what is inspected
- what is controlled

### 6. Governance Model

Specify:

- whether mutation is possible
- what approvals or checkpoints apply
- what evidence and trace are required

### 6A. Proactive Authority Model

If the feature can observe, recommend, stage, resume, recover, or act proactively, specify:

- what level of proactive behavior is allowed:
  - observe
  - suggest
  - stage
  - request approval
  - act within existing authority
- what object or execution represents that proactive behavior
- how the operator can inspect, interrupt, defer, or deny it
- what evidence and rationale it must surface

### 7. UX Surface Model

Specify:

- where the feature appears
- what surface it belongs to
- what object the inspector should show
- how the user understands status and intervention
- how proactive posture is exposed without hiding it as silent automation

### 8. Compatibility Impact

If the feature touches tools, Linux apps, browsers, or foreign runtimes, explain how it remains subordinate to the native governed model.

### 9. Validation Plan

Specify:

- invariant tests
- service/state tests
- UX tests
- end-to-end tests

### 10. Acceptance Criteria

Acceptance criteria must include both:

- user-visible outcome
- architecture-visible outcome

## Required Review Questions

Every feature spec should answer:

1. Does this strengthen the kernel model or bypass it?
2. Does this create a real execution object or hide work in side effects?
3. Does this improve inspectability and control, or weaken them?
4. Does this reinforce the shell as a system shell?
5. Does this preserve the SBCL image substrate as the native authority?
6. If this feature is proactive, is that proactivity governed, attributable, and interruptible?

## Disallowed Spec Patterns

Feature specs are incomplete if they are framed only as:

- screen changes
- command changes
- endpoint changes
- workflow tweaks

without identifying their kernel, object, and governance implications.
