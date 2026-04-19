---
layout: default
title: Environment Retrieval Implementation Plan
hero_title: Environment Retrieval Implementation Plan
hero_text: Incremental plan for turning the environment into a governed retrieval substrate for the agent.
eyebrow: Execution
permalink: /roadmap/environment-retrieval-implementation-plan.html
description: Implementation roadmap for environment-native retrieval in sbcl-agent.
---
## Purpose

This plan turns the environment-retrieval architecture into an executable sequence that does not destabilize the current turn and governance runtime.

The plan assumes two constraints:

- the current provider request path must continue working during the transition
- major design decisions should be made explicitly before hardening them in code

## Target Shape

The target request path becomes:

1. prompt received
2. request intent classified
3. retrieval plan built
4. environment dossier assembled from service-native reads
5. provider request built from transcript plus dossier
6. mutations executed or staged
7. post-mutation retrieval and validation run against the same environment

## Proposed Modules

The implementation can be staged behind these modules:

- `src/retrieval-intent.lisp`
- `src/retrieval-plan.lisp`
- `src/retrieval-dossier.lisp`
- `src/retrieval-service.lisp`
- `src/retrieval-ranking.lisp`
- `src/retrieval-provider-context.lisp`

The first iterations do not need all of them, but this is the shape to grow toward.

## Iteration 1. Retrieval Architecture Lock

Goals:

- document environment retrieval as a first-class subsystem
- define the canonical dossier concept
- define open design decisions explicitly

Deliverables:

- environment retrieval architecture note
- this implementation plan

Acceptance criteria:

- contributors can distinguish compact snapshots from retrieved dossiers
- contributors know that environment retrieval must use the service layer

Status:

- complete

Cumulative completion after iteration:

- 12%

## Iteration 2. Intent And Retrieval Plan Scaffolding

Goals:

- classify incoming prompts into retrieval intent categories
- define a retrieval plan structure with domains, limits, and expansion posture

Deliverables:

- `src/retrieval-intent.lisp`
- `src/retrieval-plan.lisp`
- tests for intent classification and plan generation

Acceptance criteria:

- requests can be classified without involving provider-specific code
- retrieval planning stays deterministic and testable

Status:

- complete

Cumulative completion after iteration:

- 24%

## Iteration 3. First Dossier Over Existing Services

Goals:

- assemble a compact dossier from current service-native reads
- keep the first dossier symbolic and structural rather than semantic

Deliverables:

- `src/retrieval-dossier.lisp`
- `src/retrieval-service.lisp`
- dossier tests covering:
  - code-change requests
  - runtime-debugging requests
  - incident-follow-up requests
  - workflow/approval requests

Acceptance criteria:

- dossier assembly is built from existing services
- dossier output exposes provenance and authority metadata
- current provider request snapshots still work unchanged when dossier retrieval is disabled

Status:

- complete

Cumulative completion after iteration:

- 38%

## Iteration 4. Provider Request Integration

Goals:

- add dossier support to provider request construction
- preserve compatibility with the current provider request snapshot path

Deliverables:

- `src/retrieval-provider-context.lisp`
- provider request updates
- tests showing request-specific dossier injection

Acceptance criteria:

- provider requests can include a dossier without breaking existing flows
- compact summaries remain available as a fallback

Status:

- complete

Cumulative completion after iteration:

- 52%

## Iteration 5. Retrieval-Aware Agent Loop

Goals:

- make pre-prompt retrieval part of the default agent turn flow
- expose unresolved gaps to the model explicitly

Deliverables:

- turn orchestration integration
- execution-path tests showing retrieval before provider invocation

Acceptance criteria:

- the agent receives request-specific retrieved context before generating actions
- governance and environment state are no longer limited to static summaries in the common path

Status:

- complete

Cumulative completion after iteration:

- 66%

## Iteration 6. Post-Mutation Retrieval

Goals:

- retrieve resulting state after tool, patch, and eval actions
- support validation and follow-up reasoning against observed consequences

Deliverables:

- post-mutation dossier extension
- follow-up reasoning integration
- tests for runtime mutation, patch mutation, and validation/reconciliation follow-up

Acceptance criteria:

- post-mutation state is observable through the same retrieval substrate
- follow-up reasoning is based on observed environment consequences rather than assumption

Status:

- complete
- 80%

## Iteration 7. Semantic Ranking

Goals:

- add optional semantic ranking for vague or historical lookups
- keep symbolic and structural retrieval primary

Deliverables:

- `src/retrieval-ranking.lisp`
- ranking tests
- configuration guardrails

Acceptance criteria:

- semantic retrieval improves vague lookups without replacing explicit domain retrieval
- ranking remains explainable through provenance and ranking metadata

Status:

- complete
- 100%

## Retrieval Domains For Early Delivery

The first dossier iterations should prioritize these reads:

1. conversation thread detail
2. current turn detail
3. environment summary and status
4. runtime summary and targeted runtime detail
5. work-item list/detail
6. workflow record list/detail
7. incident list/detail
8. mutation review
9. event stream slices

That order preserves the current strengths of the system while extending the agent toward environment-native reasoning.

## Decision Gates

These gates should be resolved before implementation crosses them.

### Gate A. Mid-Turn Expansion

Decision:

- allow only pre-prompt retrieval in the first release
- or allow the agent to request additional dossier expansion during a turn

Recommendation:

- start with pre-prompt retrieval only

Reason:

- it is easier to test and keeps the first implementation legible

### Gate B. Semantic Search Timing

Decision:

- add semantic ranking immediately
- or delay it until symbolic and structural retrieval are stable

Recommendation:

- delay semantic ranking

Reason:

- the current environment already has enough structured state to deliver a strong first version without embeddings

### Gate C. Dossier Shape

Decision:

- introduce a first-class dossier object now
- or extend the existing provider request snapshot ad hoc

Recommendation:

- introduce a first-class dossier object

Reason:

- otherwise retrieval will collapse back into summary proliferation

### Gate D. Automatic Post-Mutation Follow-Up

Decision:

- always run post-mutation retrieval
- or limit it to mutation classes that affect governance and runtime state materially

Recommendation:

- limit it initially to patch, mutating eval, reload, and governed tool writes

Reason:

- it preserves signal while avoiding needless overhead on every benign read action

## Test Strategy

The first retrieval test layers should cover:

- retrieval intent classification
- dossier assembly from environment-bound service reads
- provider request integration with dossier payloads
- pre-mutation and post-mutation retrieval flow
- authority and provenance metadata presence
- fallback behavior when no environment is bound

## Immediate Next Step

The next implementation move should be narrow:

1. approve or adjust the decision-gate recommendations
2. implement intent classification and retrieval-plan scaffolding
3. build the first compact dossier from existing service reads

That keeps the architecture legible and prevents the retrieval track from becoming another summary-only layer.
