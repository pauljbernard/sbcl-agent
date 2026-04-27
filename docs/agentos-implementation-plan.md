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

## Phase 6 — IntentOS Shell

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

The current repository is not at this final state yet, but the implementation has already materially advanced through these phases:

- Phase 0 — kernel invariants: materially established in docs and code refactor direction
- Phase 1 — universal invocation: substantially underway
- Phase 2 — execution handle model: materially implemented
- Phase 3 — governance hardening: materially implemented
- Phase 4 — compatibility kernel: first backend materially implemented
- Phase 5 — surface model: materially implemented
- Phase 6 — shell model: materially implemented
- Phase 7 — desktop host contract: materially implemented across `sbcl-agent` and `sbcl-agent-ux`
- Phase 8 — developer platform: materially started with manifest and package lifecycle work

That means this plan should now be read as a target-state program layered on top of a runtime that is already partway into the execution-kernel transition.

## Final Milestone

IntentOS Developer Preview 1.0 must demonstrate:
- bootable OS
- execution-handle model
- governed Linux app execution
- inspector-driven UX
- rollback and recovery
- non-bypassable governance

## Final Implementation Statement

The system is complete when:

- every action is an execution
- every execution is governed
- every execution is inspectable
- no execution can bypass the kernel
