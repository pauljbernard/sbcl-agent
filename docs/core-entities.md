---
layout: default
title: Core Entities
hero_title: The Native Entities of the Environment
hero_text: sbcl-agent should be understood through the entities it makes durable and governable, not through editor metaphors or prompt transcripts.
eyebrow: Entities
permalink: /core-entities.html
description: Definitions for the core entities used by sbcl-agent.
---
## Why These Definitions Matter

The system becomes much easier to understand once the reader knows which objects are native to the model.

The codebase already implements many of these directly. Others are architectural categories that are partially implemented today and becoming more explicit over time.

## Environment

The top-level persistent world.

In code, the `environment` record is already real. It aggregates runtime state, conversation state, workflow state, agent state, policies, summaries, event history, and compatibility bindings.

## Runtime

The live execution substrate hosted by SBCL.

This includes loaded code, stateful objects, active work, and runtime inspection or mutation operations.

## Thread

A durable conversational container.

Threads organize messages, turns, and related artifacts so conversation is not reduced to one-shot provider responses.

## Turn

One interaction lifecycle inside a thread.

A turn links the user request, assistant response, operations, approvals, failures, and resulting artifacts.

## Operation

A concrete runtime or tool action associated with a turn.

Operations are where intent meets execution. They are the point where policy, approval, and result status become explicit.

## Artifact

A durable outcome or evidence object.

Artifacts can represent diffs, reports, validations, reconciliations, recovery plans, or other user-visible records created by turns and workflows.

## Work-Item

A governed engineering unit.

A work-item links intent, execution, waiting state, approvals, evidence, and closure conditions. Mutating work should typically pass through this layer.

## Workflow Record

The durable record of how a work-item progressed.

Workflow records capture phases, waiting reasons, approval requirements, pending validation, interventions, evidence, and conclusion state.

## Agent

A resident or semi-resident actor inside the environment.

The codebase already has agent-related state and task/worker machinery, but the full environment-native agent model is still in progress. The important idea is that agents are meant to be explicit participants, not hidden assistant behavior.

## Policy

The rules that govern what actions may occur and under what conditions.

Policy is what prevents conversation or direct runtime power from collapsing into unrestricted mutation.

## Incident

A durable record of runtime or workflow failure requiring attention.

Incidents matter because a governed system must preserve failure context and recovery state instead of treating errors as transient console noise.

## Why the Entity Model Is Important

These entities let the system answer questions that transcript-driven tools struggle to answer cleanly:

- what happened?
- what changed?
- what is blocked?
- what evidence exists?
- what still requires approval, validation, or reconciliation?

That is the practical value of the model.
