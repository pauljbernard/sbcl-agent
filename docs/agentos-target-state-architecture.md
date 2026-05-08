# IntentOS – Target-State Architecture

## Core Definition

IntentOS is a minimal, governed execution kernel where every action is a governed execution derived from an intention.

It is microkernel-inspired in discipline, but it is not a traditional microkernel.

Traditional kernels center:

- processes
- memory
- files
- threads
- hardware-facing resource management

IntentOS instead centers:

- executions
- authority
- lifecycle
- trace
- governed mutation

That makes the most precise description:

- execution kernel
- or more fully: minimal, governed execution kernel

## Architecture Context Diagram

<img src="assets/intentos-target-architecture-context-diagram.png" alt="IntentOS target architecture context diagram" style="display:block;max-width:100%;height:auto;margin:1rem auto;" />

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
9. Every visible element must be inspectable.

## Kernel Category

IntentOS is closest to a microkernel in structure and to capability-based systems in authority discipline, but its true kernel object is not the process.

Its kernel object is the execution.

That means the correct mapping is:

| Traditional OS | IntentOS |
| --- | --- |
| process | execution |
| file descriptor | execution handle |
| syscall | `invoke` |
| read | `inspect` |
| write / control | `control` |
| permissions | authority |
| audit log | trace |
| transaction | governed mutation |

## Kernel API

```lisp
(invoke intention capability &key authority context constraints)
(inspect object-id)
(control execution-id action &key authority reason)
```

## Core Abstraction

Execution handle (`exec-id`)

Equivalent to a Unix file descriptor, but for governed execution.

## System Architecture

```text
IntentOS
├── Kernel
│   ├── invoke / inspect / control
│   ├── execution model
│   ├── lifecycle
│   ├── authority
│   └── trace
│
├── Governance Kernel
│   ├── policy root
│   ├── approval engine
│   ├── mutation validator
│   ├── checkpoint manager
│   └── rollback manager
│
├── Capability System
│   ├── registry
│   ├── manifests
│   └── adapters
│
├── Compatibility Kernel
│   ├── Linux app registry
│   ├── sandbox manager
│   ├── backend abstraction
│   ├── filesystem scoping
│   ├── network policy
│   ├── display bridge
│   └── lifecycle controller
│
├── Runtime / Image Substrate (SBCL)
│   ├── live image
│   ├── introspection
│   ├── persistence
│   └── checkpointing
│
├── UX Kernel
│   ├── workspace
│   ├── execution surfaces
│   ├── surface manager
│   ├── inspector
│   ├── object browser
│   └── governance console
│
└── Platform Layer
    ├── SDK
    ├── packaging (.aop)
    ├── simulation
    ├── testing
    └── distribution
```

## Compatibility Model

Linux application = governed execution

Example:

```lisp
(invoke "edit files" "linux.vscode" :authority "developer")
```

Produces an execution handle (`exec-id`).

All resources attach to that execution:
- process or container
- filesystem scope
- network policy
- UI surface
- trace

## UX Model

The workspace is a workspace of governed executions.

Primary objects:
- executions
- intentions
- capabilities
- agents
- policies
- traces
- mutations
- system images

UX principle:

Every visible element must be inspectable.

## Developer Model

- to act → `invoke`
- to understand → `inspect`
- to intervene → `control`

## Packaging Model

`.aop` (IntentOS Package)

Contains:
- capabilities
- agents
- policies
- workflows

## Final Statement

IntentOS is an execution-kernel operating system:

Every action begins as an intention, becomes a governed execution, and remains inspectable and controllable for its lifetime.
