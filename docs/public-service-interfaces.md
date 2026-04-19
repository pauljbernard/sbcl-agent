---
layout: default
title: Public Service Interfaces
hero_title: Public Service Interfaces
hero_text: Future UX should be built on stable, governed service contracts over the environment kernel rather than on shell internals.
eyebrow: Architecture
permalink: /public-service-interfaces.html
description: Public service interface boundary for secure presentation-tier development tooling in sbcl-agent.
---
## Purpose

The repository now needs an explicit architectural boundary between the environment kernel and future presentation tiers.

That boundary is the public service interface layer.

Its job is to make it possible to build a modern engineering UX without coupling UI code directly to:

- shell commands
- compatibility-session internals
- ad hoc summary assembly
- internal slot mutation helpers

## Architectural Rule

The system should evolve into three layers:

1. Environment kernel
2. Public service interface layer
3. Presentation adapters

The shell remains important, but it becomes one client of the service layer rather than the privileged center of the system.

## Environment Kernel

The kernel owns:

- runtime state
- conversation state
- workflow and work-item state
- artifacts and lineage
- incidents and recovery state
- tasks and workers
- policy state
- event evidence
- governed mutation lifecycle

The kernel owns invariants and durable truth.

## Public Service Interface Layer

The public service interface layer owns:

- stable read contracts
- stable mutation contracts
- authentication and authorization hooks
- policy enforcement entry points
- audit and evidence emission
- error normalization
- event/subscription surfaces for live UX updates

This is where internal architecture becomes consumable by external clients.

## Presentation Adapters

Presentation adapters should be thin.

They should render, collect user input, and subscribe to updates.

They should not be responsible for:

- reimplementing policy decisions
- reaching into internal structs
- composing ad hoc cross-domain views from private helpers
- bypassing workflow or approval semantics

Candidate adapters include:

- the current shell and REPL
- richer terminal UI
- web UI
- desktop application surfaces
- automation and remote control entrypoints

## Service Families

The first public service families should likely be:

- environment service
- conversation service
- runtime service
- retrieval service
- workflow service
- approval service
- work-item service
- incident service
- mutation-review service
- RGP service
- event service

Each service family should expose read operations and governed commands separately.

The current implementation now includes concrete service modules for:

- execution of ask/say, staged assistant actions, pending action replay, direct tool calls, and direct patch application
- environment summary, status, events, save, and load
- conversation thread list/create/use/detail and turn detail
- runtime summary, inspection reads, history, package switch, eval, and reload
- retrieval dossier assembly over existing service-native read surfaces
- workflow record list/detail
- approval grants and work-item approval requests
- work-item list/detail
- incident list/detail
- mutation review
- RGP bind/show/export/artifacts/approvals/approve/resume
- event-stream queries for UX-facing observation

The provider configuration and routing surface is now also exposed through stable service contracts:

- `query-environment-provider-service`
- `query-environment-provider-preview-service`
- `command-environment-provider-configure-service`
- `command-environment-provider-use-service`
- `command-environment-provider-routing-service`
- `query-environment-provider-route-service`

That matters for the future UX because provider selection is no longer just a shell concern. The service boundary now exposes:

- configured provider profiles
- active provider profile
- routing policy mode
- supported routing modes
- last routing decision
- prompt-aware route preview without mutating last-route state
- ranked provider candidates with routing reasons

That is important for the presentation tier because a UX should be able to let an engineer inspect and steer provider choice in real time without depending on shell-only command strings or hidden session internals.

That execution family matters because it is now the shared mutation and interaction entry surface for:

- shell `ask` and `say`
- pasted assistant actions
- direct `tool` invocations
- direct `patch` invocations
- pending-action execution and resumed turn actions

That removes one of the most important shell-first assumptions from the older design: the shell is no longer the only place where interaction and mutation semantics are assembled.

## Query And Command Split

The public interface should separate:

- queries for safe, composable inspection
- commands for governed mutation

Queries should return stable read models or DTOs.

Commands should:

- pass through policy checks
- create operation and workflow evidence
- surface approval requirements explicitly
- emit canonical events for UI refresh and audit

## Security Rule

Security should be enforced at the service boundary, not delegated to presentation code.

That includes:

- operator identity
- capability grants
- approval scope
- session and environment binding
- audit evidence
- mutation authorization

The future UX should never be trusted to enforce the real rules on its own.

## Eventing Rule

A serious UX will need live subscriptions to:

- turn progression
- operation state changes
- approval waits and approvals granted
- incident creation and recovery changes
- task and worker updates
- artifact creation
- environment posture changes

Those subscriptions should be modeled as service-level event streams over canonical domain events.

## Shell Migration Rule

The shell should migrate to this boundary rather than remain the hidden composition root.

That means:

1. shell commands normalize input
2. shell dispatch invokes public services
3. services invoke domain logic
4. shell renders service results

That migration is the proof that the service layer is real.

The shell is now substantially migrated to this boundary. Its current role is:

1. normalize forms into commands
2. call service entry points for the majority of operator-visible actions
3. preserve shell-facing payload shapes where compatibility still matters
4. render results without owning the underlying service/domain semantics

After the latest cleanup, the shell still owns a few things, but they are primarily adapter concerns:

1. form parsing and shell-specific validation messages
2. stream rendering and timing output
3. orientation/help rendering
4. REPL-specific direct Lisp evaluation

Those are acceptable shell-specific responsibilities. Governed execution semantics no longer need to live there.

Some CLI entry surfaces still need the same treatment, but the shell itself is no longer the primary privileged execution path it used to be.

## Definition Of Success

The service layer is doing its job when:

- a new UX can be built without calling private session helpers
- shell commands and future UI clients share the same governed operations
- policy and approval behavior are consistent across front ends
- internal kernel refactors do not force presentation-tier rewrites

## Hardening Note

The service boundary also needs stable governance metadata, not just stable payloads.

That means service responses should consistently expose:

- authority
- session/environment binding
- read-model or command-model identity
- policy identifiers for governed commands

See [Service Boundary Hardening]({{ '/service-boundary-hardening.html' | relative_url }}).
