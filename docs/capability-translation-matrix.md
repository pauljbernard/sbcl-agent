---
layout: default
title: Capability Translation Matrix
hero_title: Capability Translation Matrix
hero_text: The project should preserve the enduring powers of classic Common Lisp tooling while discarding their legacy architectural metaphors.
eyebrow: Design Filter
permalink: /capability-translation-matrix.html
description: Mapping legacy Common Lisp tool capabilities into agentic environment primitives.
---
## Purpose

This document exists to prevent the project from drifting into legacy IDE parity as its architectural goal.

The right question is not:

- how do we rebuild SLIME, SLY, Lem, LispWorks, Allegro, or Portacle?

The right question is:

- what enduring powers did those environments provide?
- what is the better form of those powers inside a live, image-native, conversational, multi-actor environment?

The design rule is:

- preserve the capabilities
- discard the metaphors

## Legacy Tooling Families

The reference set includes:

- Portacle
- SLIME
- SLY
- Lem
- LispWorks
- Allegro

These systems differ significantly in form and quality, but they cluster around the same enduring functions.

## Capability Classes

### Must Preserve

These are the powers from classic Lisp tooling that remain fundamental:

- inspect runtime state
- evaluate forms in context
- redefine functions and classes incrementally
- navigate symbol, package, caller, and method relationships
- observe conditions, stack state, restarts, and dynamic bindings
- reconcile source and image
- maintain fast feedback loops

### Must Transform

These functions still matter, but they should take different forms in an agentic environment:

- REPL becomes structured execution plus conversation
- debugger becomes incident and recovery workflow
- editor navigation becomes semantic graph navigation
- compilation becomes continuous validation pipeline
- project or session becomes persistent environment
- manual inspection becomes shared human-agent reasoning over runtime state

### Must Not Inherit Blindly

These legacy assumptions should be actively resisted:

- file buffer as primary truth
- human-only control model
- one foreground task at a time
- debugging only after failure
- opaque tooling state
- editor-centric architecture
- reproducing panes, windows, menus, or mode lines merely because older tools had them

## Translation Matrix

| Legacy function | Preserve / Transform / Discard | Environment-native form |
| --- | --- | --- |
| REPL / listener | Transform | Governed execution substrate plus direct eval channel and conversational control |
| Debugger | Transform | Runtime incident workspace with restart orchestration, checkpointing, approval, and repair workflow |
| Inspector | Transform | Queryable object and runtime graph with structural and conversational traversal |
| Jump to definition / source browser | Transform | Semantic environment graph spanning source, image, artifacts, work-items, and contradictions |
| Compiler notes panel | Transform | Continuous validation and mutation feedback stream tied to operations |
| Project or session model | Transform | Persistent Environment object containing runtimes, threads, agents, artifacts, work-items, policy, and history |
| Incremental redefinition | Preserve | Governed live mutation of runtime definitions with checkpoints and reconciliation |
| Symbolic introspection | Preserve | First-class package, symbol, method, caller, and binding inspection services |
| Runtime condition handling | Preserve | First-class incident, restart, and state inspection services |
| Editor panes and buffer chrome | Discard as architecture | Optional compatibility layer only, never the architectural center |
| Mode-line or shortcut parity | Optional compatibility layer | UI affordances if useful, but not design drivers |
| Environment extensibility | Preserve and extend | Environment-native plugin, tool, and agent protocol |

## Concrete Translation Principles

### REPL

The REPL should not disappear, but it should no longer be the only legitimate live control surface.

The translated form is:

- a direct execution channel for the operator
- a governed execution substrate for agents
- a substrate that can be invoked directly, structurally, or conversationally

### Debugging

The debugger should not remain only an after-the-fact condition inspector.

The translated form is:

- a runtime incident workspace
- a place where state can be captured
- a place where repairs can be proposed
- a workflow where mutation can be gated and validated

### Inspection

The inspector should not be reduced to an object pretty-printer.

The translated form is:

- a queryable runtime model
- a structural view for humans
- a conversational and symbolic substrate for agents

### Navigation

Navigation should not stop at files and line numbers.

The translated form is:

- movement across source definitions
- live image definitions
- artifacts
- work-items
- validations
- reconciliation records
- conversation references

### Environment Model

The project should no longer treat “project,” “session,” or “editor workspace” as the primary container.

The translated form is:

- Environment as the top-level world
- Runtime, Thread, Agent, Artifact, Work-Item, Policy, and Reconciliation Record as native entities

## Design Questions This Matrix Enables

Once this translation is explicit, weaker questions fall away:

- where does the inspector pane go?
- how closely do we mimic SLIME shortcuts?
- should we reproduce a classic debugger window?

Better questions replace them:

- how should runtime objects be represented so both humans and agents can operate on them?
- what is the best way to expose source-image divergence?
- how should a runtime condition become a recoverable workflow artifact?
- when should a runtime mutation require a checkpoint or work-item?
- how should symbolic knowledge be shared across REPL, conversation, and agents?

## Practical Rule

Every major feature proposal should be tested against one question:

- does this preserve an essential Lisp capability in a better form, or is it just recreating a familiar surface?

If the answer is “familiar surface,” it should not drive the architecture.
