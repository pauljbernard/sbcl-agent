---
layout: default
title: Evidence Profiles and Visibility Rules
hero_title: Evidence Profiles and Visibility Rules
hero_text: Federated nodes must support bounded disclosure while still emitting enough evidence for governance, trust, and compensation.
eyebrow: Architecture
permalink: /evidence-profiles-and-visibility-rules.html
description: Evidence-profile and visibility rules for employee-operated and contractor-operated sbcl-agent nodes.
---
## Purpose

This document locks the evidence and visibility rules for federated node operation.

The node must be able to operate under different trust and commercial conditions without changing its core runtime model.

## Core Rule

Evidence emission and visibility are explicit policy dimensions.

They must not be left to ad hoc client behavior or inferred from operator goodwill.

## Evidence Profiles

The first required evidence profiles are:

- `minimal`
- `standard`
- `high-assurance`

### Minimal

The node emits:

- status progression
- core identifiers
- limited incident or failure summaries

This profile is suitable only where policy and trust allow a reduced evidence burden.

### Standard

The node emits:

- status progression
- artifacts or artifact summaries
- checkpoint summaries
- approval and incident linkage
- validation summaries where relevant

This profile should be the normal default for governed work.

### High-assurance

The node emits:

- status progression
- artifacts and checkpoint summaries
- validation and reconciliation summaries
- stronger incident and recovery evidence
- usage telemetry relevant to governance or compensation
- deliverable and acceptance evidence where relevant

This profile is suitable for higher-risk, lower-trust, or compensable work.

## Visibility Profiles

Visibility defines how much of the local node is exposed beyond the machine.

The first rule is that visibility should prefer structured evidence over direct raw machine access.

Visibility policy should govern:

- whether raw local paths are exposed
- whether environment-root identity is exposed
- whether runtime/package detail is exposed
- whether raw artifact content or only summaries are exposed
- whether detailed usage telemetry is exposed

## Operating-Model Implications

### Employee mode

Employee operation may allow:

- broader visibility
- lighter evidence in lower-risk situations
- more direct governance controls

### Contractor mode

Contractor operation should prefer:

- bounded disclosure
- structured evidence over direct introspection
- stronger evidence profiles
- explicit policy-governed redaction when contractually permitted

## Desktop Rule

`sbcl-agent-ux` should expose evidence posture and publication posture through service DTOs.

It should not infer evidence sufficiency by scraping unrelated payloads.

The desktop should help the operator understand:

- which evidence profile is active
- which visibility profile is active
- what still needs to be published
- what remains blocked by policy or approval

## Event Rule

When federated events are published, the event metadata should make evidence and visibility posture explicit through:

- `evidence-profile`
- `visibility-profile`
- related trust and compensation metadata where relevant

## Phase 1 Lock

The implementation must treat evidence profile and visibility profile as first-class policy inputs to publication behavior.
