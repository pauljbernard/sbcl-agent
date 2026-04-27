---
layout: default
title: RGP-sbcl-agent Event Contract
hero_title: RGP-sbcl-agent Event Contract
hero_text: Canonical event envelope and event families for federated orchestration between RGP and sbcl-agent.
eyebrow: Architecture
permalink: /rgp-sbcl-agent-event-contract.html
description: Shared event contract for employee-operated and contractor-operated node orchestration.
---
## Purpose

This document locks the shared event contract between `RGP` and `sbcl-agent` for the federated operating model.

The contract must support both employee-operated and contractor-operated nodes without creating separate transport or orchestration models.

## Architectural Rule

The event contract is common across both operating modes.

Mode-specific behavior is carried in policy and commercial metadata, not in separate event transports.

## Envelope Shape

Every federated event envelope should support these canonical fields when relevant:

- `event-id`
- `event-type`
- `event-version`
- `occurred-at`
- `producer`
- `correlation-id`
- `causation-id`
- `tenant-id`
- `operator-id`
- `agent-id`
- `assignment-id`
- `work-id`
- `employment-model`
- `trust-tier`
- `visibility-profile`
- `evidence-profile`
- `compensation-profile`
- `payload`

## Authority Rule

The envelope does not erase the dual authority model.

`RGP` emits and records events for:

- global assignment lifecycle
- global lease coordination
- policy and approval decisions
- compensation and payment lifecycle

`sbcl-agent` emits and records events for:

- local acceptance and clarification actions
- local execution facts
- local evidence and artifact publication
- local usage telemetry
- local publication backlog and retry outcomes

## Core Inbound Events To sbcl-agent

The first required inbound families are:

- `assignment.created`
- `assignment.terms_updated`
- `assignment.acceptance_confirmed`
- `lease.granted`
- `lease.recovered`
- `payment.authorized`
- `payment.disputed`

These are global-orchestration events emitted by `RGP` and consumed by `sbcl-agent`.

## Core Outbound Events From sbcl-agent

The first required outbound families are:

- `assignment.accepted`
- `assignment.rejected`
- `assignment.clarification_requested`
- `execution.fact_published`
- `artifact.published`
- `checkpoint.published`
- `incident.reported`
- `usage.reported`
- `billing.milestone_reached`
- `deliverable.submitted`
- `acceptance.requested`

These are node-originated facts emitted by `sbcl-agent` and consumed by `RGP`.

## Employment Model Rule

The same event family may carry different policy expectations based on `employment-model`.

Examples:

- `assignment.created` for a contractor usually implies explicit acceptance is required
- `usage.reported` for a contractor usually participates in compensation logic
- `artifact.published` may require a stronger evidence profile for contractor work than for employee work

The event family does not change. The interpretation changes through policy.

## Visibility Rule

The contract must support bounded disclosure.

That means:

- a node may emit structured evidence instead of raw machine access
- visibility decisions must be explicit in event metadata
- contractor mode must not imply invasive remote introspection by default

## Delivery Rule

Delivery semantics should assume:

- at-least-once delivery
- replay safety
- idempotent consumers
- durable cursoring on the `RGP` side
- durable publication backlog on the `sbcl-agent` side

## Desktop Boundary Rule

`sbcl-agent-ux` should not consume this contract directly from `RGP`.

The desktop consumes local service DTOs from `sbcl-agent`, and `sbcl-agent` is responsible for presenting:

- local assignment status
- local publication status
- local evidence posture
- local usage summaries
- local node mode and trust posture

This preserves the node as a coherent local appliance rather than a split-brain UI client.
