---
layout: default
title: IntentOS Operator Journeys
hero_title: IntentOS Operator Journeys
hero_text: The high-value operator journeys that should shape refactoring order, shell behavior, and validation.
eyebrow: Journeys
permalink: /operator-journeys.html
description: Canonical operator journeys for the transition from sbcl-agent to IntentOS.
---

# IntentOS Operator Journeys

## Purpose

The project already has detailed journey analysis. This document provides the tighter canonical set that should guide the `IntentOS` transition.

These are the journeys the system must eventually support cleanly.

## Journey 1: Inspect the live world

The operator needs to:

- understand the current runtime state
- inspect an execution, object, incident, or artifact
- move between related objects without losing context

Success condition:

- every visible element is inspectable
- the inspector exposes real system state

## Journey 2: Begin governed work from intention

The operator starts from an intention and the system creates or routes governed execution.

Success condition:

- the execution boundary is explicit
- the resulting execution is visible, inspectable, and controllable

## Journey 3: Perform governed mutation

The operator or assistant performs a mutation that is:

- policy-aware
- checkpointed
- evidence-linked
- resumable

Success condition:

- mutation does not disappear into side effects
- source, image, and workflow truth remain linked

## Journey 4: Recover from interruption

The operator must be able to resume, quarantine, validate, or reconcile interrupted work.

Success condition:

- blocked state is explicit
- recovery controls are visible
- the execution or work object remains intelligible after interruption

## Journey 5: Supervise multiple concurrent executions

The operator needs a workspace-level view over:

- active executions
- blocked executions
- compatibility executions
- validation gates
- governance queues

Success condition:

- one shell can coordinate many live objects without collapsing into dashboard duplication

## Journey 6: Host foreign capability safely

The operator launches or supervises a compatibility-backed capability such as a Linux application.

Success condition:

- the foreign capability is still a governed execution
- its lifecycle and policy remain visible

## Journey 7: Build or install capability

A developer or operator defines a capability, packages it, validates it, and runs it.

Success condition:

- platform behavior is explicit
- the system supports capability growth without private knowledge

## Journey Prioritization

Near-term priority order:

1. inspect the live world
2. begin governed work from intention
3. perform governed mutation
4. recover from interruption
5. supervise multiple concurrent executions
6. host foreign capability safely
7. build or install capability

## Relationship to Existing Journey Analysis

Use this document as the compact governing journey set.

Use:

- [User Journey Gap Matrix]({{ '/user-journey-gap-matrix.html' | relative_url }})
- [User Journey Implementation Backlog]({{ '/user-journey-implementation-backlog.html' | relative_url }})

for deeper gap and backlog detail during execution.
