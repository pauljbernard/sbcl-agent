---
layout: default
title: Documentation
hero_title: A Conversation-Native, SBCL-Backed Engineering Runtime
hero_text: sbcl-agent is an image-native Common Lisp agent environment that now supports both direct REPL workflows and persistent conversation threads on top of one governed runtime.
eyebrow: Docs Home
permalink: /
description: Documentation landing page for sbcl-agent.
---

<div class="callout"><strong>North star:</strong> build a governed, transactional, image-native engineering environment where conversation owns interaction state, runtime owns execution state, and workflow owns engineering governance.</div>

<div class="quick-links">
  <a class="quick-link" href="{{ '/objectives.html' | relative_url }}"><strong>Objectives</strong>Read the product and architecture objectives first.</a>
  <a class="quick-link" href="{{ '/user-guide.html' | relative_url }}"><strong>Operator Guide</strong>Jump straight to the current CLI and shell workflow.</a>
  <a class="quick-link" href="{{ '/conversation-architecture.html' | relative_url }}"><strong>Conversation Runtime</strong>See the thread and turn model behind the refactor.</a>
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
    <p>The current runtime architecture, ownership boundaries, data model, workflow governance, and module map.</p>
  </a>
  <a class="card" href="{{ '/user-guide.html' | relative_url }}">
    <div class="card-title">User Guide</div>
    <p>How to run the CLI, use the Lisp shell, work with threads and turns, approve operations, and inspect governed state.</p>
  </a>
  <a class="card" href="{{ '/implementation-plan.html' | relative_url }}">
    <div class="card-title">Implementation Plan</div>
    <p>The execution program, what is already implemented, and what remains to harden the conversation runtime and workflow bridge.</p>
  </a>
  <a class="card" href="{{ '/conversation-architecture.html' | relative_url }}">
    <div class="card-title">Conversation Runtime</div>
    <p>The thread, message, turn, operation, and artifact model that turns chat into a first-class runtime layer.</p>
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
- persistent threads, messages, turns, operations, and artifacts
- `ask` compatibility plus `say` for conversation-first turns
- approval-gated actions, turn resume, session persistence, tasks, and workers
- work-items, workflow records, validator replay groups, and image-to-source reconciliation paths

## Core Rule

The current refactor is organized around one ownership rule:

- conversation owns interaction state
- runtime owns execution state
- workflow owns engineering governance

That rule keeps the system from collapsing chat history, live runtime state, and engineering evidence into one undifferentiated session blob.

## What Makes sbcl-agent Different

Most agent CLIs treat the running process as disposable infrastructure. `sbcl-agent` treats the live SBCL image as part of the engineering substrate. The operator can reason in Lisp, the runtime can be inspected in Lisp, and the workflow layer records what changed in source, what changed in the image, and what evidence links the two.

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

Then read the conversation-runtime set:

1. [Conversation Runtime]({{ '/conversation-architecture.html' | relative_url }})
2. [Streaming Event Model]({{ '/streaming-event-model.html' | relative_url }})
3. [Thread Runtime Migration Plan]({{ '/migration-plan-thread-runtime.html' | relative_url }})

If you are new to Common Lisp, read [Common Lisp Language Reference]({{ '/common-lisp-guide.html' | relative_url }}) before diving into the runtime internals.
