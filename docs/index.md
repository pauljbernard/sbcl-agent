---
layout: default
title: Documentation
hero_title: A Persistent, Image-Native Lisp Environment
hero_text: sbcl-agent is being reframed as a programmable symbolic environment in which runtimes, conversations, agents, artifacts, and workflow records coexist inside one governed SBCL-native world.
eyebrow: Docs Home
permalink: /
description: Documentation landing page for sbcl-agent.
---

<div class="callout"><strong>North star:</strong> build a persistent, image-native, agentic Common Lisp environment in which humans and governed agents collaboratively inspect, execute, validate, and evolve software inside a living symbolic world.</div>

<div class="quick-links">
  <a class="quick-link" href="{{ '/objectives.html' | relative_url }}"><strong>Objectives</strong>Read the product and architecture objectives first.</a>
  <a class="quick-link" href="{{ '/user-guide.html' | relative_url }}"><strong>Operator Guide</strong>Jump straight to the current CLI and shell workflow.</a>
  <a class="quick-link" href="{{ '/roadmap/vision.html' | relative_url }}"><strong>Vision</strong>Read the new positioning and environment-first direction.</a>
  <a class="quick-link" href="{{ '/capability-translation-matrix.html' | relative_url }}"><strong>Capability Matrix</strong>See how legacy Lisp tool functions should be preserved, transformed, or discarded.</a>
  <a class="quick-link" href="{{ '/roadmap/codex-execution-plan.html' | relative_url }}"><strong>Execution Plan</strong>Read the concrete phased plan for implementing the vision in this repository.</a>
  <a class="quick-link" href="{{ '/implementation-plan.html' | relative_url }}"><strong>Roadmap</strong>See what is implemented now and what remains.</a>
</div>

## Documentation Paths

<div class="card-grid">
  <a class="card" href="{{ '/why-sbcl-agent.html' | relative_url }}">
    <div class="card-title">Why sbcl-agent Exists</div>
    <p>Project rationale, the three-truth model, and why a live SBCL image changes the design space for agent systems.</p>
  </a>
  <a class="card" href="{{ '/objectives.html' | relative_url }}">
    <div class="card-title">Objectives</div>
    <p>The concrete product, architecture, and operational goals that define success for the project.</p>
  </a>
  <a class="card" href="{{ '/architecture.html' | relative_url }}">
    <div class="card-title">Architecture and Design</div>
    <p>The current architecture, the new Environment-first framing, ownership boundaries, and how the implemented runtime maps into that direction.</p>
  </a>
  <a class="card" href="{{ '/user-guide.html' | relative_url }}">
    <div class="card-title">User Guide</div>
    <p>How to run the CLI, use the Lisp shell, work with threads and turns, approve operations, and inspect governed state.</p>
  </a>
  <a class="card" href="{{ '/implementation-plan.html' | relative_url }}">
    <div class="card-title">Implementation Plan</div>
    <p>The execution program for moving from a shell-plus-session model toward an Environment-centered symbolic system.</p>
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
  <a class="card" href="{{ '/conversation-architecture.html' | relative_url }}">
    <div class="card-title">Conversation Runtime</div>
    <p>The thread, message, turn, operation, and artifact model, now treated as one subsystem within the larger Environment architecture.</p>
  </a>
  <a class="card" href="{{ '/roadmap/vision.html' | relative_url }}">
    <div class="card-title">Vision</div>
    <p>The positioning statement that explains why the project should no longer be framed as an IDE or an agent shell with more features.</p>
  </a>
  <a class="card" href="{{ '/roadmap/environment-model.html' | relative_url }}">
    <div class="card-title">Environment Model</div>
    <p>The Environment object, its laws, native entities, and the structural implications for the next stage of the architecture.</p>
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

## What The System Supports Now

`sbcl-agent` currently combines:

- an SBCL-native CLI and Common Lisp shell
- direct Lisp evaluation in the live runtime
- mock and OpenAI-compatible providers
- canonical provider event normalization for streaming
- a concrete Environment object with save/load and projected environment events
- persistent threads, messages, turns, operations, and artifacts
- runtime inspection, eval, reload, and history commands with policy gates
- first-class incident recording, operator summaries, and environment event inspection
- direct Lisp control, conversation, and governed workflow as coexisting interaction modes
- approval-gated actions, turn resume, session persistence, tasks, and workers
- work-items, workflow records, validator replay groups, and image-to-source reconciliation paths

## Current Rule

The current implementation is still organized around one ownership rule:

- conversation owns interaction state
- runtime owns execution state
- workflow owns engineering governance

That rule keeps the system from collapsing chat history, live runtime state, and engineering evidence into one undifferentiated session blob. The new roadmap extends this by placing those domains inside a larger Environment object rather than treating thread or shell state as the architectural center.

## What Makes sbcl-agent Different

Most agent CLIs treat the running process as disposable infrastructure. `sbcl-agent` treats the live SBCL image as part of the engineering substrate, and the new vision goes further: the runtime, conversation threads, agents, artifacts, and work-items are all being treated as native entities of one living environment.

That leads to a stricter success question:

1. What changed in source?
2. What changed in the running image?
3. What evidence links the two?

## Recommended Reading Order

If you are new to the project, read in this order:

1. [Why sbcl-agent Exists]({{ '/why-sbcl-agent.html' | relative_url }})
2. [Objectives]({{ '/objectives.html' | relative_url }})
3. [Architecture and Design]({{ '/architecture.html' | relative_url }})
4. [User Guide]({{ '/user-guide.html' | relative_url }})
5. [Implementation Plan]({{ '/implementation-plan.html' | relative_url }})

Then read the environment-and-runtime set:

1. [Vision]({{ '/roadmap/vision.html' | relative_url }})
2. [Environment Model]({{ '/roadmap/environment-model.html' | relative_url }})
3. [Capability Translation Matrix]({{ '/capability-translation-matrix.html' | relative_url }})
4. [Codex Execution Plan]({{ '/roadmap/codex-execution-plan.html' | relative_url }})
5. [Conversation Runtime]({{ '/conversation-architecture.html' | relative_url }})
6. [Streaming Event Model]({{ '/streaming-event-model.html' | relative_url }})
7. [Thread Runtime Migration Plan]({{ '/migration-plan-thread-runtime.html' | relative_url }})

If you are new to Common Lisp, read [Common Lisp Language Reference]({{ '/common-lisp-guide.html' | relative_url }}) before diving into the runtime internals.
