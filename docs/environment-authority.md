---
layout: default
title: Environment Authority
hero_title: Environment Authority
hero_text: The environment is the durable authority of the runtime. Session state remains an operator-facing compatibility surface.
eyebrow: Architecture
permalink: /environment-authority.html
description: Authority and ownership rules for environment-backed state in sbcl-agent.
---
## Purpose

This note defines the state-authority rule for the current architecture.

That rule is simple:

- `environment` is the authoritative durable state container
- `agent-session` is a compatibility and operator interaction facade
- presentation surfaces should prefer environment-backed views
- compatibility-session state exists to preserve shell ergonomics during the transition, not to remain a co-equal source of truth forever

This note exists so contributors do not need to infer authority rules from scattered tests or fallback helpers.

## Authority Rule

When an environment is bound, environment-backed state is the default truth for:

- runtime state
- conversation state
- workflow and work-item state
- artifact indexing and summaries
- task and worker monitoring
- policy posture
- event evidence and operator posture summaries
- system identity and purpose through `agent-constitution`
- environment capability and dependency posture through `capability-inventory`
- explicit context-chat project targeting that defines the current project frame of reference

Session-backed state may still be used in two cases:

1. No environment is currently bound.
2. Request-local or shell-local compatibility context has not been normalized into the environment snapshot for that path yet.

Outside those cases, session values should be treated as compatibility views or temporary transport, not as the durable authority.

## What The Session Still Owns

The session remains useful and should stay explicit about that role.

It currently provides:

- shell-facing interaction state
- compatibility with the legacy command surface
- transient operator context
- request-local transcript and execution flow while work is being normalized into the environment

The session may still carry transient prompt-local interpretation state, but it should not become the long-term home of:

- system-level constitution
- environment capability readiness
- explicit project targeting
- governed workflow continuation posture

That is a real responsibility, but it is no longer the architectural center.

## Read Rules

Contributors should follow these read rules:

1. If an environment is bound and the requested domain already exists there, read from the environment.
2. If a compatibility fallback is required, use it narrowly and document why the fallback still exists.
3. Do not assemble competing summaries from both environment and session unless the function is explicitly a reconciliation or migration helper.

The practical goal is to prevent summary drift and duplicated state assembly.

## Write Rules

Mutation paths should follow these write rules:

1. Durable state changes must terminate in environment-backed structures.
2. Session mutation helpers should either write through to the environment immediately or exist only as compatibility adapters around environment-owned mutation.
3. New features should not introduce fresh durable state that lives only on `agent-session`.

That rule now applies directly to context engineering. If a feature affects the environment frame of reference for planning or execution, it should write through into environment-backed structures first. Examples include:

- updating the active provider profile or routing mode
- changing explicit Context Chat project targeting
- persisting the system-level agent constitution
- recording environment capability readiness or dependency anomalies

This lets the shell remain stable while architectural ownership continues to move in one direction.

## Compatibility Rule

Compatibility is additive, not architectural.

That means:

- keep shell commands working
- keep session save/load compatibility where needed
- keep compatibility payloads small and explicit at the persistence boundary
- do not let compatibility helpers become the easiest place to add new domain logic

If a new feature naturally belongs to runtime, conversation, workflow, artifact, incident, or policy state, it should be modeled in the environment-first domain path first.

## Public Interface Implication

This authority rule also defines how future services and UX should be built.

Public service interfaces should consume:

- environment-backed read models
- governed mutation commands
- policy and approval state derived from the environment
- environment-scoped context and authority state
- planner-facing project and capability posture

They should not couple themselves directly to compatibility-session internals.

## Acceptance Test For New Architecture Work

A contributor should be able to answer these questions clearly for any new feature:

1. Which environment domain owns the durable state?
2. What compatibility behavior still depends on the session?
3. Where does write-through into environment state happen?
4. Which summaries or service DTOs expose the result?

If those answers are unclear, the design is still too session-shaped.
