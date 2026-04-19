---
layout: default
title: Environment Retrieval Architecture
hero_title: Environment Retrieval Architecture
hero_text: The environment should be a governed retrieval substrate for the agent, not only a place where actions execute.
eyebrow: Architecture
permalink: /environment-retrieval-architecture.html
description: Architecture note for environment-native retrieval in sbcl-agent.
---
## Purpose

`sbcl-agent` already has a richer runtime and governance model than a normal chat-plus-tools shell.

The core shift described by this note is now partially implemented. The agent no longer consumes only a compact request snapshot; it can already operate over the environment as a governed retrieval plane.

This note now describes both the implemented first pass and the remaining architectural move:

- the environment becomes searchable context for the agent
- retrieval becomes a governed subsystem rather than ad hoc prompt stuffing
- the agent and future UX both use the same service-native read surface

## Current State

This architecture note began as a forward-looking proposal. The repository has since implemented a meaningful first version of it.

The current provider request path already carries structured context:

- session summary
- thread context
- turn context
- environment context
- runtime summary
- workspace summary
- policy summary
- retrieval intent and retrieval plan
- retrieval dossier
- cognition bundle
- prior-outcome reuse
- reasoning, planning, execution, and validation briefs

That is materially better than a plain transcript prompt.

It is now materially closer to environment-native retrieval than the original note described.

Today the model can receive:

- recent transcript and active turn context
- query-specific retrieval dossiers assembled over service-native read surfaces
- governance and operator posture
- prior outcomes, playbook reuse, and self-improvement guidance
- post-mutation retrieval in the same environment

The remaining gap is not “retrieval does not exist.” The remaining gap is hardening recall, ranking quality, mid-turn expansion policy, and eval-grade proof that the retrieval-and-cognition loop is consistently superior.

## Architectural Rule

The environment should not be only the place where mutations execute.

It should also become the primary memory and retrieval substrate for agent reasoning.

The provider path has already moved from:

1. prompt
2. compact summaries
3. transcript tail

to:

1. prompt
2. transcript and active turn history
3. retrieved environment dossier
4. policy and operator posture
5. explicit affordances for more governed reads and mutations

## Not Plain RAG

This system should not treat the environment as a flat document corpus.

A normal RAG system retrieves text chunks.

`sbcl-agent` needs governed hybrid retrieval across:

- conversation state
- runtime state
- workflow and work-item state
- incident and recovery state
- artifact and evidence state
- event history
- source and workspace state
- policy and operator posture

That is why the correct model is not plain semantic search.

It is typed, governed environment retrieval.

The current implementation is still stronger in symbolic and structural retrieval than in semantic ranking depth. That is an intentional bias toward precision while the retrieval substrate hardens.

## Retrieval Domains

The retrieval layer should support at least these families.

### Conversation Retrieval

- current thread detail
- related thread summaries
- prior turns
- pending assistant actions
- prior assistant proposals and results

### Runtime Retrieval

- runtime summary
- package state
- loaded systems
- symbol detail
- callers
- methods
- source/image divergence
- eval history

### Workflow Retrieval

- work-item detail
- workflow record detail
- wait reasons
- pending validations
- resume payloads
- quarantine state

### Incident Retrieval

- incident detail
- open incidents
- recent incidents
- linked recovery guidance
- operator interventions

### Artifact Retrieval

- mutation evidence
- runtime artifacts
- validation artifacts
- reconciliation artifacts
- thread and turn artifact lineage

### Environment/Event Retrieval

- environment summary and status
- event stream slices
- recent state transitions
- binding and authority posture

### Source/Workspace Retrieval

- file content
- repository status and diffs
- patch lineage
- source references linked to environment records

## Retrieval Modes

The system should use three retrieval modes together.

### 1. Symbolic Retrieval

Use exact lookups for:

- ids
- file paths
- package names
- symbol names
- runtime identifiers
- work-item identifiers
- workflow record identifiers
- artifact identifiers

### 2. Structural Retrieval

Use graph and state adjacency for:

- current thread
- active turn
- active work-item
- linked workflow record
- artifacts linked to a turn or operation
- incidents linked to a work-item or turn
- recent events for an entity

### 3. Semantic Retrieval

Use ranking over textual summaries and evidence for:

- vague historical questions
- concept-level searches
- finding similar past incidents
- locating relevant prior turns or artifacts

Semantic retrieval is useful here, but it should refine domain-aware retrieval rather than replace it.

## Retrieval Dossier

Retrieved context should be assembled into an explicit dossier object before provider invocation.

The current dossier shape should include:

- request intent
- retrieval plan
- retrieved conversation context
- retrieved runtime context
- retrieved workflow context
- retrieved incident context
- retrieved artifact context
- retrieved source/workspace context
- policy and operator posture
- unresolved gaps
- ranking and provenance metadata

The dossier matters because the model should be able to reason about:

- what it was shown
- why it was shown
- how fresh it is
- what remains uncertain

## Staged Retrieval

Retrieval should be staged rather than maximal.

### Stage 1. Intent Classification

Classify the request into one or more modes such as:

- code change
- architecture question
- runtime debugging
- incident follow-up
- approval or recovery work
- validation or reconciliation
- historical recall

### Stage 2. Retrieval Planning

Build a domain retrieval plan:

- which domains matter
- what top-k limits apply
- whether live runtime inspection is needed
- whether governance state is mandatory
- whether source/workspace reads are needed

### Stage 3. First-Pass Dossier

Fetch a compact first-pass dossier sufficient for straightforward cases.

### Stage 4. Expansion

If uncertainty remains, deepen retrieval before mutation or final answer generation.

The implemented path already covers the first-pass dossier and targeted post-mutation refresh. More aggressive mid-turn expansion remains an area for further hardening.

This prevents flooding the model with irrelevant state on every turn.

## Governance Rule

Retrieval results are not just content. They are governed context.

Each retrieved item should carry metadata such as:

- domain
- authority
- environment id
- runtime id when relevant
- freshness
- linkage to related entities
- ranking reason
- policy sensitivity when relevant

That allows the model to reason over provenance instead of receiving anonymous blobs.

## Service-Layer Implication

The retrieval layer should be built over the public service interface, not over private struct access.

That keeps the agent and the UX aligned around the same read boundary.

The first retrieval implementation did exactly that: it composes existing read services rather than inventing a second private read path. That decision should remain in force as retrieval depth increases.

## Agent Loop Implication

The agent loop has already evolved from:

1. receive prompt
2. receive snapshot
3. answer or propose actions

to:

1. receive prompt
2. classify request
3. retrieve environment dossier
4. answer or propose actions
5. execute or stage mutations
6. retrieve post-mutation state
7. validate and reconcile using the same environment

That is how the environment becomes both the reasoning substrate and the execution substrate.

Today the remaining gap is not the existence of this loop, but its maturity:

- deeper relevance ranking
- stronger prior-outcome reuse
- more deliberate playbook selection
- clearer proof that the loop improves execution quality across difficult software tasks

## Immediate Design Constraint

The implementation should not try to expose the entire environment in one prompt.

The retrieval system should:

- stay compact by default
- prefer typed references and summaries
- expand only when the task requires it
- preserve explicit provenance

## Success Criteria

Environment retrieval is working when:

- the agent can answer environment-specific questions with less prompt hand-holding
- the agent can find relevant prior work, incidents, and artifacts before mutating
- the agent can validate and explain mutations against the same environment it reasoned over
- the provider prompt becomes request-specific rather than a generic summary bundle
- the UX and agent both rely on the same service-native read surface

## Open Design Decisions

Several of the original decisions have now moved from open design to implemented first pass. The remaining open decisions are the ones that still affect maturity and quality:

1. Should retrieval remain mostly provider-preprompt, or should the agent be allowed to request deeper dossier expansion mid-turn more aggressively?
2. How far should semantic ranking go beyond the current symbolic and structural bias before it starts hurting precision?
3. How should retrieval, cognition, and prior-outcome reuse be exposed to future UX surfaces without leaking internal implementation details?
4. How much automatic post-mutation retrieval should happen before follow-up reasoning becomes too expensive or redundant?
