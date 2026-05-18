---
layout: default
title: Context Engineering
hero_title: Context Engineering
hero_text: The integrated agent now receives a canonical planning packet built from environment truth, project truth, workflow truth, and retrieval evidence rather than a transcript-shaped prompt blob.
eyebrow: Planning Context
permalink: /context-engineering.html
description: Current context-engineering and planning substrate for sbcl-agent.
---

## Why This Matters

`sbcl-agent` no longer treats model context as an unstructured dump of transcript, tool output, and loose summaries.

For long-horizon planning and governed execution, the runtime now builds one canonical planning substrate that answers five questions explicitly:

1. who the system is and what it is allowed to do
2. what environment and capability surface is live right now
3. what project and workflow frame of reference should govern the request
4. what evidence is decisive rather than merely relevant
5. what uncertainty blocks safe planning or execution

## Canonical Planning Context Packet

Provider-bound planning requests now flow through a canonical `planning-context-packet` with these sections:

- `:task-frame`
- `:planner-directives`
- `:authority-state`
- `:decisive-evidence`
- `:uncertainty-and-obligations`
- `:strategy`
- `:optional-support`

This packet is built in the shared request-snapshot layer and then consumed by the provider boundary. It is not an OpenAI-only formatting trick.

## Authority State

The `authority-state` section now carries the stable and live context the agent should treat as authoritative before reaching for supporting narrative:

- `agent-constitution`
- `capability-inventory`
- project authority
- thread and turn context
- environment summary
- explicit Context Chat project targeting when present

### Agent Constitution

The system now carries a durable `agent-constitution` through the environment:

- identity
- system role
- governance posture
- objectives
- optimization priorities
- hard invariants
- self-improvement boundaries

This closes the earlier gap where the system behaved constitutionally but did not carry a first-class durable statement of identity and purpose.

### Capability Inventory

The environment also now exposes a planner-grade `capability-inventory`, including:

- readiness summary
- provider-route viability
- executable readiness
- missing prerequisites
- dependency anomalies
- package-management posture
- anomaly summaries

This gives the planner a live view of what the agent can actually do, not just what tools exist in theory.

## Project Context

Project context is no longer only inferred from prompt text or retrieved dossier fragments.

The runtime now supports:

- ambient current project selection
- retrieval-derived project alignment
- explicit Context Chat project targeting with zero, one, or many selected projects

Explicit targeting is persisted in session/environment state and can be inspected or changed from the shell and desktop-task service surface.

When project selection is ambiguous, the system now degrades confidence and promotes that ambiguity into the uncertainty layer instead of pretending the project frame is stable.

## Decisive Evidence

Retrieval still collects a broad dossier, but planning no longer starts from broad relevance alone.

The dossier now derives a `decisive-context-core` that favors:

- blockers
- validation obligations
- incidents
- recent mutation consequences
- source/runtime symbol targets
- durable intent constraints
- project constraints
- prior conversational anchors when they govern interpretation

Salience is explicitly weighted for:

- authority strength
- conflict potential
- validation criticality
- recency

## Uncertainty And Contradictions

The reasoning layer now emits structured uncertainty rather than a single loose “unknowns” bucket.

It distinguishes:

- missing authority facts
- decisive unknowns
- authority conflicts
- stale-context suspicions
- next inspection obligations

High-value contradiction classes now include:

- multi-project ambiguity
- project-readiness versus capability-posture conflicts
- project/work-item linkage gaps

Those signals are then promoted into planner directives and escalation logic.

## Strategy And Risk Shaping

The packet is not static across tasks.

It now changes shape by:

- task archetype
- risk posture
- governance burden
- validation burden

For example:

- debugging requests bias toward inspection and explanation first
- implementation requests bias toward planning, mutation, and validation
- recovery requests bias toward checkpoint-backed continuation and replay
- high-risk or low-authority contexts escalate into a more conservative planning posture automatically

## Context Chat Project Targeting

The operator can now explicitly bind the Context Chat frame of reference to projects:

```lisp
(desktop-task/set-context-chat-projects
  :project-ids '("project-a" "project-b")
  :primary-project-id "project-a")

(desktop-task/context-chat-context)
```

This is intentionally optional:

- zero selected projects is valid
- one selected project is valid
- many selected projects is valid

The distinction between `:explicit`, `:ambient`, and `:none` selection source is preserved in the planner authority state.

## Current Strength

At this point the system is strong in all five context-engineering categories needed for long-horizon planning and execution:

1. durable self-constitution
2. fully introspective operating state
3. project-specific authority and differentiation
4. live environment capability/dependency posture
5. relevance-guided retrieval and canonical planning-context packaging

The remaining work is refinement:

- deeper semantic project disambiguation
- more exhaustive contradiction classes
- broader warning cleanup and documentation upkeep
