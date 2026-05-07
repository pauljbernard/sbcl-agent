# IntentOS – Implementation Plan

## Phase 0 — Kernel Invariants

Create:

- `docs/kernel-invariants.md`

Define:
- doctrine
- API
- lifecycle
- authority model

Acceptance:

All future work conforms to kernel rules.

## Phase 1 — Universal Invocation

Goal:

All execution flows through `invoke()`.

Tasks:
- wrap all tool and process execution
- eliminate bypass paths

Acceptance:

No execution outside `invoke`.

## Phase 2 — Execution Handle Model

Tasks:
- introduce execution object
- return `execution-id`
- attach all runtime state

Acceptance:

Everything maps to execution handles.

## Phase 3 — Governance Hardening

Tasks:
- checkpoint before mutation
- enforce authority
- block self-modification

Acceptance:

No unauthorized mutation possible.

## Phase 4 — Compatibility Kernel

Tasks:
- define Linux app manifest
- implement host-process backend
- wrap execution

Acceptance:

Linux apps are governed executions.

## Phase 5 — Surface Model

Tasks:
- define surface abstraction
- bind execution → surface

Acceptance:

All UI elements map to execution.

## Phase 6 — Surface

Tasks:
- workspace
- inspector
- object browser
- governance queue

Acceptance:

System opens into workspace, not app.

## Phase 7 — Convert Desktop App

Tasks:
- host existing Electron app

Acceptance:

`sbcl-agent-ux` is not the system authority; it is a host over the shell desktop contract.

## Phase 8 — Developer Platform

Tasks:
- manifest spec
- packaging (`.aop`)
- SDK CLI
- test harness

Acceptance:

Developers can build and run capabilities independently.

## Phase 9 — OS Image

Tasks:
- bootable VM
- SBCL runtime
- persistent state

Acceptance:

System boots directly into IntentOS shell.

## Phase 10 — Commercial Hardening

Tasks:
- security
- updates
- recovery
- crash handling
- documentation
- versioning

Acceptance:

System is stable and supportable.

## Current Implementation Status

The accepted target-state architecture is now implemented at the architectural-contract level.

Completed phases:

- Phase 0 — kernel invariants: complete
- Phase 1 — universal invocation: complete at the operator-facing architecture boundary
- Phase 2 — execution handle model: complete
- Phase 3 — governance hardening: complete at the target-architecture level
- Phase 4 — compatibility kernel: complete at the target-architecture level
- Phase 5 — surface model: complete
- Phase 6 — shell model: complete
- Phase 7 — desktop host contract: complete across `sbcl-agent` and `sbcl-agent-ux`
- Phase 8 — developer platform: complete at the target-architecture level
- Phase 9 — runtime/image substrate: complete against the accepted target contract
- Phase 10 — commercial hardening baseline: complete as an initial architecture program

That means this plan should now be read historically as the architecture program that was executed, not as a still-open gap list.

## Enhancement Milestone

The next meaningful milestones are no longer target-state milestones. They are enhancement tracks:

- richer backend realism
- deeper artifact and forensic depth
- stronger QA and evidence discipline
- broader external platform and distribution depth
- operator and UX polish

## Final Implementation Statement

The original architecture program is complete when:

- every action is an execution
- every execution is governed
- every execution is inspectable
- no execution can bypass the kernel
