# sbcl-agent / sbcl-agent-ux – Current-State Gap Analysis

## Current-State Architecture Diagram

![sbcl-agent / sbcl-agent-ux current-state architecture diagram](assets/sbcl-agent-current-state-architecture-diagram.png)

## Executive Summary

The current system consists of:

```text
sbcl-agent
  → governed agent runtime
  → SBCL image-based execution
  → mutation, approval, and trace mechanisms

sbcl-agent-ux
  → Electron-based UX
  → application-level interface
```

This represents a highly advanced agent runtime, but not yet an operating system.

The primary gap is not capability. It is the absence of:
- a minimal kernel contract
- a unified execution abstraction
- a compatibility subsystem at OS-grade rigor
- a system-level UX
- a developer platform

## Gap 1: Absence of Minimal Kernel Contract

Current system exposes multiple top-level primitives:

- intention
- agent
- capability
- authority
- execution
- mutation
- trace
- policy
- approval

These are not compressed into a single invariant execution model.

Missing:
- single execution abstraction
- single invocation path
- strict lifecycle model
- non-bypassable kernel boundary

Impact:
- model complexity increases with features
- no stable mental model for developers
- governance inconsistencies emerge

## Gap 2: Linux Compatibility Is Not a Kernel

Current Linux and tool execution is effectively:

```text
process execution
```

Required:

```text
compatibility kernel
```

Missing:
- Linux application manifest model
- sandbox abstraction (process/container/microVM)
- filesystem scoping
- network policy enforcement
- display mediation
- inspector integration
- lifecycle governance

Impact:

Without this, the system collapses into `Linux + agent wrapper`.

## Gap 3: UX Is Application-Level, Not System-Level

Current UX:

```text
sbcl-agent-ux (Electron application)
```

Required:

```text
IntentOS Shell (system interface)
```

Missing:
- workspace model
- execution surface model
- inspector-first UX
- governance visibility
- object browser
- system image awareness

Impact:
- system remains tool-like instead of OS-like
- no unified user interaction model

## Gap 4: No Developer Platform

The system lacks a consumable platform model.

Missing:
- SDK
- capability manifest standard
- packaging format
- testing harness
- simulation environment
- distribution model
- update and versioning strategy

Impact:
- no ecosystem formation
- no external adoption
- no commercial viability

## Final Gap Statement

The system does not lack sophistication.

It lacks compression, invariants, and a formal operating system boundary.
