---
layout: default
title: IntentOS UX Design System
hero_title: IntentOS UX Design System
hero_text: The structural UX model for evolving sbcl-agent-ux from an application interface into a shell over governed executions.
eyebrow: UX System
permalink: /ux-design-system.html
description: Structural UX system for IntentOS-oriented desktop and shell surfaces.
---

# IntentOS UX Design System

## Purpose

This document defines the structural UX system, not just the visual style.

It exists to prevent the UX from drifting into:

- dashboard sprawl
- duplicated state
- app-local navigation that ignores system objects
- decorative inspection instead of real inspection

## Core UX Thesis

The UX is a shell over governed executions and related system objects.

It is not a set of pages over loosely connected features.

## Primary UX Objects

The UX should center:

- executions
- intentions
- capabilities
- agents
- policies
- traces
- mutations
- system images
- compatibility executions

## Structural Surfaces

### Workspace

The workspace is the active field of operation.

It should show:

- active executions
- current pressure
- current posture
- current context

### Execution Surfaces

Execution surfaces are the bridge between windows and the execution-handle model.

A surface should always answer:

- what execution is active
- what state it is in
- what can be inspected
- what can be controlled

### Inspector

The inspector is not an auxiliary panel. It is the universal object understanding surface.

If the user can select an object, the inspector should be able to show:

- identity
- status
- trace
- authority
- related objects
- available controls

### Governance Console

The governance console is where blocked, approval-gated, quarantined, or validation-gated work becomes legible and actionable.

### Object Browser

The object browser exists to navigate durable system objects, not merely content categories.

## UX Invariants

1. Every visible element must be inspectable.
2. Every action-bearing object must expose its state.
3. Every blocked state must be legible.
4. Mutation posture must never be ambiguous.
5. Structural movement and object switching must be distinct concerns.
6. Operator attention should be rankable from one coherent model.

## Current-to-Target Translation

Today:

- `sbcl-agent-ux` is still application-shaped
- some execution posture is visible
- some object switching is still workspace-owned rather than execution-owned

Target:

- the shell opens into a workspace of governed executions
- execution surfaces become first-class
- the inspector becomes universal rather than local

## Design Review Questions

Every UX change should answer:

1. What object is this surface really about?
2. What execution or object identity anchors it?
3. How is inspectability preserved?
4. How does the user intervene through control rather than hidden side paths?
5. Is this a shell behavior or an app behavior?
