---
layout: default
title: IntentOS Requirements
hero_title: IntentOS Requirements
hero_text: Product, system, UX, compatibility, and platform requirements derived from the current-state and target-state architecture documents.
eyebrow: Requirements
permalink: /intentos-requirements.html
description: Consolidated requirements for IntentOS-oriented refactoring.
---

# IntentOS Requirements

## Scope

These requirements define what must remain true as the current `sbcl-agent / sbcl-agent-ux` system sustains and extends the accepted `IntentOS` target architecture.

They are intentionally grouped by architectural concern rather than by implementation file.

## R1. Kernel Requirements

The system must provide a minimal authoritative execution-kernel surface:

- `invoke`
- `inspect`
- `control`

Requirements:

- all native governed execution must enter through `invoke`
- all governed state must be inspectable through `inspect`
- intervention paths must normalize through `control`
- no competing top-level execution API may bypass kernel rules
- the kernel must manage executions as the primary system object rather than treating process-oriented abstractions as the native core

## R2. Execution Handle Requirements

The system must normalize meaningful activity around execution handles.

Requirements:

- every governed execution must have a stable execution id
- execution ids must bind intention, capability, authority, state, and trace
- execution handles must survive inspection, pause/resume, and persistence boundaries
- the desktop must be able to render execution-derived posture from one coherent read model

## R3. Governance Requirements

Mutation must remain governed.

Requirements:

- mutating execution requires policy evaluation
- mutating execution requires checkpoints where defined by policy
- authority cannot be self-granted
- approval state must remain explicit
- rollback, quarantine, and validation paths must remain first-class

## R4. Runtime / Image Substrate Requirements

The SBCL image remains the native substrate.

Requirements:

- native kernel logic lives in SBCL
- runtime identity is explicit
- source truth, image truth, and workflow truth remain distinct
- runtime mutation evidence remains linked to the governed work record

## R5. Compatibility Requirements

Compatibility is a first-class subsystem, but not a peer authority.

Requirements:

- Linux applications are hosted as governed executions
- hosted execution has explicit filesystem, network, display, and lifecycle policy
- hosted execution remains inspectable and controllable from the native system
- compatibility cannot introduce unaudited side paths

## R6. UX Requirements

The desktop must evolve from application interface toward system shell.

Requirements:

- the workspace centers governed executions and related system objects
- execution surfaces are explicit
- the inspector is tied to real system objects
- the operator can see what is conversational, what is governed, what is blocked, and what is mutating
- every visible element must be inspectable

## R7. Platform Requirements

The system must grow into a platform, not just a codebase.

Requirements:

- capability manifests are standardized
- packaging is explicit
- simulation and test harnesses exist
- update and distribution boundaries are defined
- external capability authors can reason about the system without private architectural knowledge

## R8. Documentation Requirements

Documentation must remain architecture-bearing.

Requirements:

- current-state and target-state diagrams are maintained
- constitution, requirements, UX system, journeys, and validation strategy stay consistent
- documentation distinguishes current truth from planned truth

## R9. Validation Requirements

Validation must prove the architecture, not just feature behavior.

Requirements:

- test suites must be traceable to kernel and UX invariants
- validation must cover current-state integrity during transition
- validation must expand as kernel, shell, and compatibility layers mature

## Acceptance Discipline

No major refactor or enhancement is complete unless it can identify:

- which requirement set it advances
- which current-state deficiency it reduces
- which target-state invariant it makes more real
