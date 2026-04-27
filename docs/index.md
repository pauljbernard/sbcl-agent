---
layout: default
title: Documentation
hero_title: Documentation Front Door
hero_text: Start with the problem, then the capability shift, then the model, then the implementation. sbcl-agent is easiest to understand in that order.
eyebrow: Docs Home
permalink: /
description: Documentation landing page for sbcl-agent.
---

<div class="callout"><strong>Current status:</strong> sbcl-agent is now a real SBCL-native shell, environment-centered runtime, governed workflow substrate, retrieval-and-cognition loop, execution-kernel refactor, compatibility-execution host, and service-backed provider/router surface. It is still evolving, but it is materially beyond a shell-plus-tools prototype and is now visibly moving toward the IntentOS execution-kernel target.</div>

<div class="quick-links">
  <a class="quick-link" href="{{ '/problem.html' | relative_url }}"><strong>The Problem</strong>Understand why the old model worked, why it now constrains understanding, and why this project exists.</a>
  <a class="quick-link" href="{{ '/application-domains.html' | relative_url }}"><strong>Application Domains</strong>See where governed, runtime-aware causality becomes necessary rather than optional.</a>
  <a class="quick-link" href="{{ '/foundation.html' | relative_url }}"><strong>Foundation</strong>Learn the three-truth model and the environment-first framing.</a>
  <a class="quick-link" href="{{ '/getting-started.html' | relative_url }}"><strong>Getting Started</strong>Run the shell, create a thread, and execute a first turn.</a>
  <a class="quick-link" href="{{ '/architecture.html' | relative_url }}"><strong>Architecture</strong>Map the conceptual model onto the code that exists today.</a>
  <a class="quick-link" href="{{ '/safety-and-risk.html' | relative_url }}"><strong>Safety and Risk</strong>Read the system's strengths, weaknesses, and governance model directly.</a>
</div>

## Recommended Reading Order

If you are new to the project, read in this order:

1. [The Problem]({{ '/problem.html' | relative_url }})
2. [Application Domains]({{ '/application-domains.html' | relative_url }})
3. [Foundation]({{ '/foundation.html' | relative_url }})
4. [Core Entities]({{ '/core-entities.html' | relative_url }})
5. [Mutation Model]({{ '/mutation-model.html' | relative_url }})
6. [Architecture and Design]({{ '/architecture.html' | relative_url }})
7. [Getting Started]({{ '/getting-started.html' | relative_url }})
8. [User Guide]({{ '/user-guide.html' | relative_url }})
9. [Safety and Risk]({{ '/safety-and-risk.html' | relative_url }})

Then use the roadmap and transition documents as forward-looking context rather than entry points.

## Documentation Layers

<div class="card-grid">
  <a class="card" href="{{ '/problem.html' | relative_url }}">
    <div class="card-title">The Problem</div>
    <p>The rationale for the project in terms of changing constraints, runtime understanding, and the limits of current SDLC and agent models.</p>
  </a>
  <a class="card" href="{{ '/application-domains.html' | relative_url }}">
    <div class="card-title">Application Domains</div>
    <p>Why governed environments such as finance, intelligence, and regulated enterprise work expose the need for intrinsic causality and evidence.</p>
  </a>
  <a class="card" href="{{ '/foundation.html' | relative_url }}">
    <div class="card-title">Foundation</div>
    <p>What sbcl-agent is, what it is not, and how source truth, image truth, and workflow truth fit together.</p>
  </a>
  <a class="card" href="{{ '/core-entities.html' | relative_url }}">
    <div class="card-title">Core Entities</div>
    <p>The environment, runtime, thread, turn, operation, artifact, work-item, workflow record, agent, policy, and incident model.</p>
  </a>
  <a class="card" href="{{ '/mutation-model.html' | relative_url }}">
    <div class="card-title">Mutation Model</div>
    <p>The lifecycle for governed change: inspect, plan, checkpoint, mutate, observe, validate, reconcile, and close or quarantine.</p>
  </a>
  <a class="card" href="{{ '/why-sbcl-agent.html' | relative_url }}">
    <div class="card-title">Why sbcl-agent Exists</div>
    <p>An additional positioning and differentiation document that captures the project's broader thesis and the legacy-tooling trap it is avoiding.</p>
  </a>
  <a class="card" href="{{ '/objectives.html' | relative_url }}">
    <div class="card-title">Objectives</div>
    <p>The product, architecture, and operational goals that define success for the current implementation and the next stage.</p>
  </a>
  <a class="card" href="{{ '/architecture.html' | relative_url }}">
    <div class="card-title">Architecture and Design</div>
    <p>The current code structure, ownership boundaries, environment transition, and how the implemented runtime maps onto the conceptual model.</p>
  </a>
  <a class="card" href="{{ '/getting-started.html' | relative_url }}">
    <div class="card-title">Getting Started</div>
    <p>The shortest path to running the system and completing a first thread-based interaction.</p>
  </a>
  <a class="card" href="{{ '/user-guide.html' | relative_url }}">
    <div class="card-title">User Guide</div>
    <p>The detailed operator reference for the CLI, Lisp shell, conversation flow, approvals, incidents, and environment inspection.</p>
  </a>
  <a class="card" href="{{ '/safety-and-risk.html' | relative_url }}">
    <div class="card-title">Safety and Risk</div>
    <p>The system's explicit risk categories, safety principles, governance model, and honest current limitations.</p>
  </a>
  <a class="card" href="{{ '/implementation-plan.html' | relative_url }}">
    <div class="card-title">Implementation Plan</div>
    <p>The delivery roadmap for moving from the current implementation toward the fuller environment-centered architecture.</p>
  </a>
  <a class="card" href="{{ '/user-journey-gap-matrix.html' | relative_url }}">
    <div class="card-title">User Journey Gap Matrix</div>
    <p>A formal analysis of operator journeys against the project’s stated objectives, current implementation, and architectural gaps.</p>
  </a>
  <a class="card" href="{{ '/user-journey-implementation-backlog.html' | relative_url }}">
    <div class="card-title">User Journey Backlog</div>
    <p>A prioritized backlog of epics, file targets, acceptance criteria, and iteration order derived from the journey analysis.</p>
  </a>
  <a class="card" href="{{ '/testing-coverage-analysis.html' | relative_url }}">
    <div class="card-title">Testing Coverage Analysis</div>
    <p>A measured assessment of unit coverage, functional coverage, user-story coverage, and current performance-testing gaps.</p>
  </a>
  <a class="card" href="{{ '/roadmap/engineering-parity-plan.html' | relative_url }}">
    <div class="card-title">Engineering Parity Plan</div>
    <p>The concrete program for pushing sbcl-agent toward parity or advantage against leading software engineering agents through internal evaluation, memory, orchestration, UX hardening, and reflective improvement.</p>
  </a>
  <a class="card" href="{{ '/conversation-architecture.html' | relative_url }}">
    <div class="card-title">Conversation Runtime</div>
    <p>The thread, message, turn, operation, and artifact model, now treated as one subsystem within the larger Environment architecture.</p>
  </a>
  <a class="card" href="{{ '/roadmap/vision.html' | relative_url }}">
    <div class="card-title">Vision</div>
    <p>The forward-looking positioning statement for the environment-first direction. Useful after the problem and foundation docs.</p>
  </a>
  <a class="card" href="{{ '/roadmap/environment-model.html' | relative_url }}">
    <div class="card-title">Environment Model</div>
    <p>The deeper roadmap document for the environment model and its long-term structural implications.</p>
  </a>
  <a class="card" href="{{ '/capability-translation-matrix.html' | relative_url }}">
    <div class="card-title">Capability Translation Matrix</div>
    <p>A design filter that maps legacy Lisp tool powers into agentic environment primitives so the project preserves capabilities without rebuilding a legacy IDE.</p>
  </a>
  <a class="card" href="{{ '/roadmap/codex-execution-plan.html' | relative_url }}">
    <div class="card-title">Codex Execution Plan</div>
    <p>A detailed, repository-specific implementation plan with phases, files, tests, and acceptance criteria for building the vision on top of the current codebase.</p>
  </a>
  <a class="card" href="{{ '/streaming-event-model.html' | relative_url }}">
    <div class="card-title">Streaming Event Model</div>
    <p>The event-native streaming contract that separates visible assistant text from runtime execution and workflow evidence.</p>
  </a>
  <a class="card" href="{{ '/kernel-invariants.html' | relative_url }}">
    <div class="card-title">Kernel Invariants</div>
    <p>The execution-kernel doctrine, three-function API, execution-handle model, and non-bypassable governance rules for IntentOS-oriented refactoring.</p>
  </a>
  <a class="card" href="{{ '/intentos-constitution.html' | relative_url }}">
    <div class="card-title">IntentOS Constitution</div>
    <p>The governing product and architecture rules for evolving the current runtime and UX into a minimal, governed execution-kernel operating system.</p>
  </a>
  <a class="card" href="{{ '/intentos-requirements.html' | relative_url }}">
    <div class="card-title">IntentOS Requirements</div>
    <p>The consolidated kernel, governance, UX, compatibility, and platform requirements for the transition to IntentOS.</p>
  </a>
  <a class="card" href="{{ '/intentos-feature-specifications.html' | relative_url }}">
    <div class="card-title">IntentOS Feature Specs</div>
    <p>The required specification discipline for new features so they reinforce the kernel model, governance model, and shell model.</p>
  </a>
  <a class="card" href="{{ '/ux-design-system.html' | relative_url }}">
    <div class="card-title">UX Design System</div>
    <p>The structural UX model for evolving sbcl-agent-ux from an application interface into a shell over governed executions.</p>
  </a>
  <a class="card" href="{{ '/ux-style-guide.html' | relative_url }}">
    <div class="card-title">UX Style Guide</div>
    <p>The visual and interaction style rules that should reinforce inspectability, governance, and execution-centered interaction.</p>
  </a>
  <a class="card" href="{{ '/operator-journeys.html' | relative_url }}">
    <div class="card-title">Operator Journeys</div>
    <p>The canonical operator journeys that should drive refactoring order, shell behavior, and execution-surface design.</p>
  </a>
  <a class="card" href="{{ '/validation-strategy.html' | relative_url }}">
    <div class="card-title">Validation Strategy</div>
    <p>The architecture-level validation plan for proving kernel invariants, execution handles, shell coherence, and compatibility containment.</p>
  </a>
  <a class="card" href="{{ '/agentos-current-state-gap-analysis.html' | relative_url }}">
    <div class="card-title">Current-State Gap Analysis</div>
    <p>A current-state assessment of what sbcl-agent already is, what it is not yet, and the structural gaps between a governed runtime and an operating system.</p>
  </a>
  <a class="card" href="{{ '/agentos-target-state-architecture.html' | relative_url }}">
    <div class="card-title">IntentOS Target Architecture</div>
    <p>The compressed target model: a governed execution kernel built around invoke, inspect, control, execution handles, compatibility, UX, and platform layers.</p>
  </a>
  <a class="card" href="{{ '/agentos-implementation-plan.html' | relative_url }}">
    <div class="card-title">IntentOS Implementation Plan</div>
    <p>The phased refactoring plan for moving from the current governed runtime toward a minimal, governed execution-kernel operating system.</p>
  </a>
  <a class="card" href="{{ '/rgp-sbcl-agent-event-contract.html' | relative_url }}">
    <div class="card-title">RGP-sbcl-agent Event Contract</div>
    <p>The federated event envelope and event-family contract between global orchestration in RGP and local execution truth in sbcl-agent.</p>
  </a>
  <a class="card" href="{{ '/evidence-profiles-and-visibility-rules.html' | relative_url }}">
    <div class="card-title">Evidence Profiles and Visibility Rules</div>
    <p>The node-side publication, disclosure, and evidence posture rules for employee-operated and contractor-operated execution.</p>
  </a>
  <a class="card" href="{{ '/migration-plan-thread-runtime.html' | relative_url }}">
    <div class="card-title">Migration Plan</div>
    <p>The compatibility-preserving path from flat session-plus-ask behavior to thread-based conversation orchestration.</p>
  </a>
  <a class="card" href="{{ '/common-lisp-runtime.html' | relative_url }}">
    <div class="card-title">Common Lisp as a Runtime</div>
    <p>Why SBCL and Common Lisp are useful here, and what engineering discipline is required to use that power safely.</p>
  </a>
  <a class="card" href="{{ '/common-lisp-guide.html' | relative_url }}">
    <div class="card-title">Common Lisp Reference</div>
    <p>A multi-page language-reference section covering syntax, bindings, control flow, collections, objects, packages, I/O, and runtime behavior.</p>
  </a>
</div>

## What the System Supports Now

`sbcl-agent` currently combines:

- an SBCL-native CLI and Common Lisp shell
- direct Lisp evaluation in the live runtime
- multi-vendor providers spanning mock, OpenAI-compatible, Anthropic, Google/Gemini-compatible, Meta-compatible, and LM Studio/local-compatible backends
- provider profiles, routing policies, prompt-aware route preview, and service-backed provider selection
- canonical provider event normalization for streaming
- a concrete Environment object with save/load and projected environment events
- retrieval dossiers, reasoning/planning briefs, validation strategies, and prior-outcome reuse in the default turn path
- persistent threads, messages, turns, operations, and artifacts
- runtime inspection, eval, reload, and history commands with policy gates
- first-class incident recording, operator summaries, and environment event inspection
- direct Lisp control, conversation, and governed workflow as coexisting interaction modes
- approval-gated actions, turn resume, session persistence, tasks, and workers
- work-items, workflow records, validator replay groups, and image-to-source reconciliation paths
- stable public service interfaces and non-shell JSON CLI surfaces for future UX integration
- kernel-facing `invoke`, `inspect`, and `control` seams with execution handles becoming first-class operator references
- execution surfaces, workspace, governance queue, object browser, and inspector shell models
- a hostable desktop contract for `sbcl-agent-ux` through `desktop/show`, `desktop/action`, and `desktop/restore`
- compatibility execution tracking and lifecycle posture for hosted process-style capabilities
- developer-platform manifests and `.aop` package lifecycle flows including export, validation, import, activation, install, and applied-profile inspection

## Strengths

The current implementation is strongest where the code and the documentation now agree:

- it is genuinely SBCL-native rather than a wrapper hiding critical logic elsewhere
- it gives operators direct access to the runtime they are reasoning about
- it preserves explicit governance concepts such as approvals, incidents, work-items, and workflow records
- it already supports durable conversational turns instead of one-shot prompt/response behavior
- it now has a real execution-kernel seam rather than only service-local mutation rules
- it now has a thin-host desktop direction instead of requiring a future UX to reconstruct navigation from raw service fragments

## Weaknesses

The current implementation is also honestly transitional:

- some compatibility-session structure still exists alongside the stronger environment model
- the environment-native agent model is not yet fully realized
- cold validation, rollback, and artifact coverage are real but not yet complete across every path
- some older documents remain deeper and more roadmap-heavy than a new reader should start with
- the developer platform is now real, but not yet a complete external SDK, simulation, and distribution ecosystem

## Current Architectural Rule

The codebase is still organized around one ownership rule:

- conversation owns interaction state
- runtime owns execution state
- workflow owns engineering governance

That rule keeps the system from collapsing chat history, live runtime state, and engineering evidence into one undifferentiated session blob. The new roadmap extends this by placing those domains inside a larger Environment object rather than treating thread or shell state as the architectural center.

The newer compression rule now sits alongside it:

- execution is being normalized under `invoke`
- execution-backed reads are being normalized under `inspect`
- intervention is being normalized under `control`

## Why the Reading Order Matters

Readers should not have to infer the story from roadmap material.

The intended journey is:

1. understand the problem
2. understand where the problem matters most
3. understand the model
4. understand the implemented architecture
5. learn how to operate the system
6. understand the risks and the forward plan
