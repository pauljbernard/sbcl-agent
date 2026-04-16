---
layout: default
title: Documentation
hero_title: A Common Lisp Agent That Uses the Runtime as Part of the Substrate
hero_text: sbcl-agent is not just a Codex-style CLI rewritten in Common Lisp. It is an image-native engineering environment on SBCL that treats source truth, live image truth, and workflow truth as separate first-class domains.
eyebrow: Docs Home
permalink: /
description: Documentation landing page for sbcl-agent.
---

<div class="callout"><strong>North star:</strong> build a governed, transactional, image-native agent engineering environment that can inspect and mutate the same running system it is reasoning about while preserving reproducibility, rollback, provenance, and operator trust.</div>

## Documentation Paths

<div class="card-grid">
  <a class="card" href="{{ '/why-sbcl-agent.html' | relative_url }}">
    <div class="card-title">Why sbcl-agent Exists</div>
    <p>Why this project was created, how it differs from other agent systems, where the value comes from, and which risks must be controlled.</p>
  </a>
  <a class="card" href="{{ '/architecture.html' | relative_url }}">
    <div class="card-title">Architecture and Design</div>
    <p>The three-truth model, transaction workflow, work-item design, validation split, safety model, and module map.</p>
  </a>
  <a class="card" href="{{ '/user-guide.html' | relative_url }}">
    <div class="card-title">User Guide</div>
    <p>How to run the CLI, use the shell, configure providers, work with approvals, and navigate the current operator workflow.</p>
  </a>
  <a class="card" href="{{ '/common-lisp-runtime.html' | relative_url }}">
    <div class="card-title">Common Lisp as a Runtime</div>
    <p>Why Common Lisp and SBCL are strategically interesting for agents, and what engineering tradeoffs come with that power.</p>
  </a>
  <a class="card" href="{{ '/common-lisp-guide.html' | relative_url }}">
    <div class="card-title">Common Lisp Language Guide</div>
    <p>A practical language introduction for readers who need to understand the codebase and shell without becoming Lisp experts first.</p>
  </a>
  <a class="card" href="{{ '/implementation-plan.html' | relative_url }}">
    <div class="card-title">Implementation Plan</div>
    <p>The staged delivery program for checkpointing, rollback, validation, skills, orchestration, and hardening.</p>
  </a>
</div>

## What This System Is

`sbcl-agent` is a Common Lisp and SBCL-native agent environment with:

- a CL-native CLI and interactive shell
- a mock provider and an OpenAI-compatible provider
- streamed responses and staged assistant actions
- session persistence, tasks, workers, and capability-gated tools
- transactional work-items with checkpoints, provenance, replay grouping, image-only outcomes, and reconciliation records

## What Makes It Different

Most developer agents focus on source changes plus isolated execution. `sbcl-agent` works from three explicit truths:

- source truth: files, diffs, tests, and persistent artifacts
- image truth: the live SBCL image, loaded definitions, object identity, package state, threads, caches, and runtime resources
- workflow truth: the durable record of what the agent believed, changed, validated, and concluded

The design therefore centers one question that ordinary file-oriented agents can often avoid:

1. What changed in source?
2. What changed in the running image?
3. What evidence links the two?

## Recommended Reading Order

If you are new to the project, read in this order:

1. [Why sbcl-agent Exists]({{ '/why-sbcl-agent.html' | relative_url }})
2. [Architecture and Design]({{ '/architecture.html' | relative_url }})
3. [User Guide]({{ '/user-guide.html' | relative_url }})
4. [Common Lisp as an Agent Runtime]({{ '/common-lisp-runtime.html' | relative_url }})

If you are new to Common Lisp, read [Common Lisp Language Guide]({{ '/common-lisp-guide.html' | relative_url }}) before going deep into the runtime internals.
