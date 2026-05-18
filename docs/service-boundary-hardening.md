---
layout: default
title: Service Boundary Hardening
hero_title: Service Boundary Hardening
hero_text: Public service responses now expose a consistent governance and binding metadata contract for shell, desktop, and external clients.
eyebrow: Architecture
permalink: /service-boundary-hardening.html
description: Hardening rules for service metadata, authority binding, and policy visibility in sbcl-agent.
---
## Purpose

The public service layer is only useful if clients can rely on stable metadata as well as stable payload shapes.

This hardening pass standardizes the service metadata contract.

## Metadata Rule

Every public service response should now carry metadata that answers four questions consistently:

1. What authority owns the result?
2. Which session/environment binding produced it?
3. Which read or command model version is in play?
4. Which governance identifiers matter for the operation?

## Standard Metadata Shape

Service metadata should expose:

- `:authority`
- `:binding`
- `:read-model` or `:command-model`
- `:policy-id` when mutation governance applies
- domain identifiers such as thread, turn, work-item, workflow-record, incident, runtime, or event family when relevant
- project-selection or project-authority hints when project context materially shapes the result

The `:binding` object is the key UX-facing stability point:

- `:session-id`
- `:environment-id`

That lets presentation clients associate data with the right governed runtime context without reaching into session structs.

For context-engineering and planning surfaces, the hardening rule now also requires that clients can distinguish:

- explicit project targeting vs inferred project alignment
- environment authority vs compatibility fallback
- capability readiness vs degraded or missing prerequisite posture

## Governance Rule

Command services should expose policy relevance in metadata rather than forcing UX clients to infer it from payloads.

This is especially important for:

- runtime mutation
- approval flows
- governed resumptions
- provider routing and planning context preparation
- project-aware execution and recovery paths

## Compatibility Rule

Shell-facing payloads may remain compatibility-shaped while the service response metadata becomes stricter and more uniform.

That preserves operator behavior while improving the active presentation boundary.

The practical implication is that richer clients such as `sbcl-agent-desktop` should not need to infer core execution context from prose or summary text. Service responses should already carry enough metadata to orient the client around:

- environment identity
- project frame of reference
- governance posture
- capability posture
- recovery or replay posture when a workflow command or supervised action is involved
