---
layout: default
title: User Journey Gap Matrix
hero_title: User Journey Gap Matrix
hero_text: A formal mapping from intended operator journeys to current implementation, architectural alignment, friction points, and recommended next steps.
eyebrow: Product
permalink: /user-journey-gap-matrix.html
description: User-journey analysis of sbcl-agent against its stated architecture and objectives.
---

## Purpose

This document evaluates the codebase from the perspective of the user journeys implied by the project objectives and vision.

It is not a feature list. It is a design filter.

Each journey is evaluated against:

- the stated objectives in [Objectives]({{ '/objectives.html' | relative_url }})
- the implemented operator surface in [User Guide]({{ '/user-guide.html' | relative_url }})
- the current conversation and environment architecture

The aim is to answer one question clearly:

Does the implemented system let a user inhabit the kind of environment the project claims it is building?

## Summary Judgment

The current implementation already succeeds as:

- a Lisp-native REPL
- a governed conversation runtime
- a workflow-aware engineering shell

It is still improving in one main area:

- making the environment feel like the unquestioned center of every operator and agent journey, not just the correct underlying architecture

That means the project has crossed the threshold from tool to environment structurally and operationally. The remaining work is product feel, operator smoothness, and breadth of habitat-like interaction.

## Matrix

| Journey | Objective Alignment | Current Implementation Status | Main Friction / Gap | Recommended Next Step |
| --- | --- | --- | --- | --- |
| Environment entry and orientation | Strongly aligned with “build an environment, not just a tool” and “preserve a direct operator surface” | Strong | Environment-first shell entry and `environment/status` now orient around environment, thread, runtime, posture, blocked work, and incidents, but the overall experience is still terminal-command heavy | Continue refining environment-native operator flows so the world model feels primary without requiring command literacy |
| Direct Lisp / REPL work | Strongly aligned with “preserve a direct operator surface” and “exploit SBCL-native advantages” | Strong | Runtime introspection is useful but not yet rich enough to feel like a full symbolic environment service | Expand semantic runtime introspection and navigation tools while keeping raw Lisp directness intact |
| Conversation-native inspection | Strongly aligned with “make conversation native, but not total” | Strong | Structurally sound, but still command-heavy and not yet fully environmental in feel | Improve thread and turn overview surfaces so the user can stay oriented without manual command chaining |
| Governed mutation with approvals | Strongly aligned with “preserve workflow governance,” “keep execution state explicit,” and “treat artifacts and work-items as native entities” | Strong | Correct and trustworthy, but still somewhat architecture-dependent from the operator perspective | Add a single mutation-review surface that explains what changed, what is blocked, and what action closes the loop |
| Failure, incident, and recovery handling | Strongly aligned with operator trust, durable evidence, and interruption survival | Strong | Compact incident workspace exists, but deeper runtime incident handling is still missing | Expand incidents into richer runtime workspaces with restart-oriented recovery flow and deeper state capture |
| Persistence and resumability | Strongly aligned with persistence, trust, and environment continuity | Strong | Compatibility-session persistence has been reduced to an adapter, but the compatibility bridge still exists as a meaningful internal layer | Continue shrinking session-first assumptions until environment-native APIs can carry more of the shell and provider surface directly |
| Artifact and evidence review | Strongly aligned with artifact-first and governance-first goals | Moderate to strong | Artifact surfacing is best in thread-bound paths and less uniform elsewhere | Broaden artifact emission so validation, reconciliation, and governed outcomes are uniformly visible across all mutating paths |
| Runtime introspection and live-image navigation | Strongly aligned with the vision’s preservation of classic Lisp powers | Moderate | The user can act in the live image, but symbolic navigation is still thinner than the long-term vision implies | Build a capability layer for richer package, symbol, method, object, and source/image navigation |
| Environment-as-habitat experience | Strongly aligned with the roadmap vision and environment-first architecture | Moderate to strong | Environment identity, events, posture, artifacts, workflow, and provider context are now real operational primitives, but the interaction style is still more command-and-summary than habitat-like | Build richer environment-native overviews, runtime workspaces, and actor-oriented flows on top of the now-stable environment core |
| Agent / multi-actor participation | Strongly aligned with the long-term vision | Roadmap-only | No resident governed actor model is present yet | Delay full agent-mode work until environment identity and operator world-model are stronger, then add explicit actor identity, scope, and subscriptions |

## Detailed Notes By Journey

### 1. Environment Entry And Orientation

Current strength:

- the project has a clear top-level CLI
- `doctor` provides meaningful runtime and governance diagnostics
- shell entry is direct and workable

Current enhancement focus:

- the user now arrives into a legible environment state
- the remaining gap is less orientation and more depth of environment-native flow

Design implication:

- orientation should shift from command discovery to world-state discovery

### 2. Direct Lisp / REPL Work

Current strength:

- the shell is real Common Lisp
- direct evaluation remains intact
- the newer architecture extends the REPL rather than replacing it

Current enhancement focus:

- semantic runtime guidance is still limited relative to the vision
- the project preserves the REPL but still has room to translate more classic Lisp environment powers into environment-native services

### 3. Conversation-Native Inspection

Current strength:

- conversation is durable and inspectable through threads, turns, operations, and artifacts
- `ask` and `say` now share one turn runner

Current enhancement focus:

- the user still needs to know which inspection command to issue next
- the system is structurally conversation-native but not yet fluid enough to feel like conversational habitation

### 4. Governed Mutation

Current strength:

- this is the most successful journey in the whole system
- approvals, work-items, checkpoints, validation state, and cold-validation semantics are real, not cosmetic

Current enhancement focus:

- the journey is more rigorous than intuitive
- the architecture preserves trust, but the operator still needs better synthesized guidance during closure

### 5. Failure / Incident / Recovery

Current strength:

- incidents are durable
- failure is linked to turn, operation, work-item, and workflow
- interrupted in-flight state is normalized honestly on reload

Current enhancement focus:

- incident handling is good as evidence but still shallow as a runtime debugging experience
- restart-oriented workflows and deeper runtime inspection are still missing

### 6. Persistence / Resume / Long-Lived World

Current strength:

- the system already behaves more like an environment than a disposable CLI here
- thread, artifact, workflow, and interruption state survive restarts

Current enhancement focus:

- persistence is implemented and now largely environment-centered, but the compatibility bridge still shapes some internal flows

### 7. Artifact-Evidence Review

Current strength:

- artifacts now represent more than file outputs
- incidents, validations, reconciliations, and runtime operations can surface as evidence

Current enhancement focus:

- artifact generation is still somewhat path-dependent
- the evidence story is strongest when conversation and workflow are already tightly bound

### 8. Environment-As-Habitat

Current strength:

- the codebase now contains enough native entities to justify the vision
- environment, runtime, thread, operation, artifact, and work-item all exist in real form

Current enhancement focus:

- the operator still usually experiences the system through shell-era command metaphors
- the world model is documented more strongly than it is felt

### 9. Agent / Multi-Actor Participation

Current strength:

- the architectural direction is clear enough that future agent work can be designed coherently

Current enhancement focus:

- there is no true resident actor journey yet
- that is acceptable for now, but it should remain explicitly roadmap-only until the environment center of gravity is stronger

## Prioritized Implementation Sequence

The journeys suggest the following implementation order.

### Priority 1. Make Environment State The Default Orientation Surface

Deliver one operator view that answers:

1. where am I
2. what thread is active
3. what runtime is active
4. what work is blocked
5. what incidents exist
6. what approvals or validations are outstanding

### Priority 2. Collapse Governance Inspection Into One Closure Surface

The user should not have to manually compose:

- `turn/status`
- `incident/show`
- work-item wait state
- session/operator summary

to understand what to do next.

### Priority 3. Expand Symbolic Runtime Navigation

This is the highest-value way to preserve classic Lisp tool power without drifting into IDE imitation.

Target areas:

- symbol description
- definition lookup
- package navigation
- method and caller relationships
- source/image divergence inspection

### Priority 4. Deepen Incident Handling Into Runtime Recovery Workspaces

Target areas:

- richer failure context capture
- restart suggestions
- recovery plan artifacts
- tighter linkage between incident and governed remediation

### Priority 5. Broaden Uniform Artifact Surfacing

Target areas:

- non-thread-bound validations
- reconciliation outcomes
- environment-level evidence objects
- richer mutation summary artifacts

### Priority 6. Add Agent Mode Only After The World Model Is Stronger

Do not center agent participation until:

- environment identity is clearer
- operator trust surfaces are tighter
- conversation, runtime, and workflow boundaries feel coherent to the user

## Practical Conclusion

The project already delivers a strong journey for direct Lisp work, governed conversation, and evidence-preserving mutation. That is enough to validate the core architectural direction.

The next phase should not chase more feature breadth first. It should make the existing world more coherent from the user’s point of view.

The concrete execution backlog derived from this matrix now lives in [User Journey Implementation Backlog]({{ '/user-journey-implementation-backlog.html' | relative_url }}).

The central design problem now is not:

- what new capability can be added

It is:

- how to make the environment itself feel like the primary thing the user is inhabiting

That is the key transition from “good governed shell” to “real symbolic habitat.”
