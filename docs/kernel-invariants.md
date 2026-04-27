# IntentOS Kernel Invariants

## Core Definition

IntentOS is a minimal, governed execution kernel where every action is a governed execution derived from an intention.

The kernel is not defined by process or memory management.

It is defined by execution management:

- intention
- capability
- authority
- state
- trace

## Kernel Doctrine

1. All execution begins with `invoke`.
2. Everything that happens is an execution.
3. Every execution has:
   - intention
   - capability
   - authority
   - state
   - trace
4. Every execution can be inspected.
5. Every execution can be controlled.
6. Mutations require checkpoints.
7. Authority cannot be self-granted.
8. Policy cannot be bypassed.

## Kernel API

```lisp
(invoke intention capability &key authority context constraints)
(inspect object-id)
(control execution-id action &key authority reason)
```

## Execution Handle Model

Every successful `invoke` yields an execution handle (`exec-id`).

The execution handle is the universal system reference for:
- lifecycle
- inspection
- control
- trace
- policy binding
- compatibility attachment

This is the nearest analogue to a Unix file descriptor, but for governed execution rather than file or process access.

## Kernel Category

IntentOS is:

- philosophically close to a microkernel
- conceptually close to a capability-based operating system
- behaviorally close to actor and supervision models

But its actual kernel object is the execution, so the most precise term is:

- execution kernel
- or more fully: minimal, governed execution kernel

## Authority Model

- authority is explicit
- authority is never self-granted
- mutation requires governed authority
- policy enforcement is mandatory at the kernel boundary

## Lifecycle

At minimum, an execution must be able to move through:
- invoked
- running
- awaiting-approval
- blocked
- completed
- failed
- rolled-back

## Refactoring Constraint

All future refactoring must reduce bypass paths and increase conformance to:
- `invoke`
- `inspect`
- `control`
- execution-handle ownership of lifecycle state
