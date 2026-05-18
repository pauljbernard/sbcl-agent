---
layout: default
title: Service Event Contract
hero_title: Service Event Contract
hero_text: A first UX-facing event stream contract over the environment event log.
eyebrow: Architecture
permalink: /service-event-contract.html
description: Cursor-based event stream contract for presentation-tier polling and subscription in sbcl-agent.
---
## Purpose

The presentation tier needs a stable way to observe governed runtime changes without depending on shell rendering or internal event-log traversal helpers.

This document defines the first service-level event stream contract.

## Contract Shape

The event stream is a query-style service response with:

- environment id
- optional input cursor
- returned next cursor
- optional family filter
- optional visibility filter
- ordered event entries

Each event entry includes:

- cursor
- kind
- timestamp
- family
- entity id
- thread id
- turn id
- visibility
- payload
- metadata
- run id
- operation id
- work-item id
- workflow-record id when applicable
- actor id and actor-origin metadata when the event comes from actor-owned execution
- replay or recovery classification when durable continuation or recovery is involved

## Cursor Rule

The cursor is an environment-local monotonic position in the projected event log.

Clients should:

1. request the initial slice with no cursor
2. store the returned `next-cursor`
3. poll again with `after-cursor`
4. render only newly returned events

This gives current clients a polling-friendly contract now while leaving room for push subscriptions later.

## Filter Rule

The first event stream supports:

- family filtering
- visibility filtering
- bounded result limits

The current event substrate also needs to preserve richer observation semantics for serious clients. In practice that means the public stream should not flatten away:

- project linkage when the event belongs to governed project work
- supervision and incident lineage
- recovery origin
- replay class

That keeps the contract simple enough for shell, terminal UI, and web UX reuse.

## Architectural Rule

Presentation clients should consume the service event stream rather than:

- reading `environment-event-log` directly
- assuming shell-specific event formatting
- inferring approval, incident, or turn progression from transcript output

The event stream is the public UX-facing observation boundary.

For `sbcl-agent-desktop`, that matters because the desktop should be able to distinguish:

- ordinary turn progression from governed action progression
- approval waits from recovery posture
- explicit recovery or replay from normal forward execution
- actor-originated state changes from compatibility-layer summaries
