---
layout: default
title: Engineering Parity Plan
hero_title: Engineering Parity Plan
hero_text: A concrete program for pushing sbcl-agent to parity or advantage against leading software engineering agents by fully exploiting its introspectable environment.
eyebrow: Roadmap
permalink: /roadmap/engineering-parity-plan.html
description: Phased execution plan for turning sbcl-agent into a top-tier software engineering agent with internal evaluation, memory, orchestration, and self-improvement.
---
## Reading Position

This document is an execution roadmap, not an introduction.

Read [Problem]({{ '/problem.html' | relative_url }}), [Foundation]({{ '/foundation.html' | relative_url }}), [Architecture]({{ '/architecture.html' | relative_url }}), and [Objectives]({{ '/objectives.html' | relative_url }}) first.

## Program Goal

The goal of this program is explicit:

`sbcl-agent` should fully exploit its introspectable environment and become honestly comparable to or stronger than leading software engineering agents in serious engineering use.

This means the system must be able to:

- retrieve and prioritize the most relevant environment context
- reuse prior outcomes, playbooks, and repo-specific operating knowledge
- decompose and execute long-horizon work under governance
- coordinate parallel work with shared state and controlled merge behavior
- validate, recover, and reconcile reliably
- expose its reasoning, agenda, and risks clearly to operators and UX
- learn from its own failures and propose system improvements

## Governing Rules

These rules are program-level constraints:

1. Environment authority remains primary over compatibility session state.
2. The shell remains first-class even as service and UX surfaces mature.
3. Service and UX surfaces must not bypass policy, validation, or workflow evidence.
4. New cognition capabilities must become both visible and, where appropriate, enforceable.
5. Major capability claims must be backed by repeatable internal evaluation.
6. Fundamental architectural choices require operator review before implementation.

## Workstreams

The program is organized into seven workstreams.

### A. Internal Evaluation and QA Harness

Goal:

- build the internal truth system that measures actual software engineering quality rather than relying on intuition

Deliverables:

- repeatable task families for repo Q&A, bug fixing, refactors, test repair, runtime debugging, governed mutation, recovery, long-horizon tasks, and parallel work
- standardized scoring for success, time-to-verified-change, regression rate, retries, validation completeness, and recovery behavior
- durable evaluation reports that become input to later self-improvement

### B. Durable Memory and Playbooks

Goal:

- move from similar-turn recall to durable organizational knowledge

Deliverables:

- repo-specific playbooks
- recurring-failure memory
- reusable execution recipes
- strategy memory keyed by task class, repo area, runtime surface, and governance path

### C. Long-Horizon Execution Control

Goal:

- make multi-step engineering work stable, resumable, and steerable

Deliverables:

- explicit task decomposition
- compaction across long runs
- plan-health monitoring
- mid-flight steering
- durable resume semantics across longer horizons

### D. Parallel Agent Orchestration

Goal:

- coordinate multiple workers with shared environment state and explicit boundaries

Deliverables:

- task graphs
- delegation boundaries
- merge and review policy
- failure containment
- supervisor-level orchestration views

### E. Service Tier and UX Hardening

Goal:

- expose the environment runtime, execution services, and actor/governance state cleanly to presentation-tier tooling and modern operator UX

Deliverables:

- stable public service interfaces
- views for agenda, validations, incidents, worker state, and evidence
- shell parity for every important service-tier action

### F. Comparative Workflow Polish

Goal:

- close the practical workflow gap with leading software agents

Deliverables:

- faster repo onboarding
- better code review support
- better long-run supervision
- stronger status surfaces
- better default instruction ingestion and project preferences

### G. Self-Improvement and Reflective Engineering

Goal:

- let the system learn from its own experiences and propose ways to improve itself

Deliverables:

- task retrospectives
- clustered failure patterns
- structured improvement opportunities
- governed adoption of proposed improvements

## Phases

### Phase 1. Internal Truth System

Goal:

- make internal QA a credible proxy for external comparative evidence

Required outcomes:

- evaluation task families exist in-repo
- evaluation runs produce durable reports
- failures are categorized in a structured way
- the program has a baseline before deeper capability changes land

Acceptance criteria:

- one repo command produces an evaluation report
- benchmark families are documented and versioned
- later phases can add scenarios without changing the harness shape

### Phase 2. Memory and Playbooks

Goal:

- make prior work actively reusable instead of merely retrievable

Acceptance criteria:

- the system can identify repo-specific preferred execution and validation patterns
- repeated tasks improve through memory reuse
- playbooks are durable environment objects rather than prompt fragments

### Phase 3. Long-Horizon Control

Goal:

- make the action agenda authoritative for multi-step execution

Acceptance criteria:

- long tasks can pause, resume, and re-plan cleanly
- drift and retry loops are detected
- operators can steer without losing task continuity

### Phase 4. Parallel Orchestration

Goal:

- turn worker abstractions into real coordinated engineering execution

Acceptance criteria:

- parallel tasks have explicit ownership and merge policy
- shared environment state remains coherent
- worker failures are isolated and legible

### Phase 5. Service and UX Exposure

Goal:

- expose the environment runtime and execution-service capabilities through secure public service interfaces and operator-grade UX

Acceptance criteria:

- UX can inspect and control agenda, validations, incidents, workers, and evidence
- every major UX action maps to a shell/service capability
- service interfaces remain governance-safe

### Phase 6. Reflective Improvement Loop

Goal:

- let the system observe, classify, and propose improvements to itself

Acceptance criteria:

- task retrospectives are durable
- recurring failure patterns are clustered
- improvement proposals become work-items or operator-reviewed backlog entries

## Decision Gates

The following are fundamental architectural choices and require explicit operator review before implementation:

1. memory model
   Example: indexed records vs graph memory vs hybrid
2. orchestration model
   Example: supervisor/worker vs hierarchical planners vs peer coordination
3. public service model
   Example: domain APIs vs generic bus vs hybrid facade
4. playbook execution semantics
   Example: advisory templates vs executable recipes
5. UX control philosophy
   Example: dashboard-first vs task-first vs power-console-first

## Readiness Standard For The Final Claim

The program is ready to support an affirmative comparative claim only when all of these are true:

- the introspectable environment is fully exploited by default cognition
- retrieval focus, memory, validation planning, and action agendas shape behavior automatically
- long-horizon work is stable and resumable
- parallel execution is first-class and governed
- UX and service surfaces are operator-grade
- self-improvement proposals are generated from real experience
- internal evaluation results across the core task families are strong enough to make the parity claim technically serious

## Current Program Status

Status at program start:

- architecture and cognition loop have advanced materially
- enforcement of the action agenda is now present
- action agenda visibility has reached turn and follow-up result surfaces
- internal performance benchmarking exists
- broad software engineering evaluation is now a first-class harness, with the remaining work centered on deeper breadth, trending, and comparative rigor

This document begins the next phase of work from that starting point.
