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
- workflow service
- artifact service
- incident service
- task service
- approval service

Each service family should expose read operations and governed commands separately.

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

## Definition Of Success

The service layer is doing its job when:

- a new UX can be built without calling private session helpers
- shell commands and future UI clients share the same governed operations
- policy and approval behavior are consistent across front ends
- internal kernel refactors do not force presentation-tier rewrites
