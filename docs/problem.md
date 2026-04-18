---
layout: default
title: The Problem
hero_title: The Problem Before the System
hero_text: sbcl-agent exists because the dominant software-delivery model optimizes for isolation and reproducibility, but increasingly struggles to preserve direct understanding of a live system under change.
eyebrow: Problem
permalink: /problem.html
description: Why the current SDLC model exists, where it succeeds, where it now breaks down, and why sbcl-agent was created.
---
## The Short Version

`sbcl-agent` was not created because software teams need another chat interface.

It was created because the standard model of software work increasingly forces operators to reconstruct system behavior indirectly from files, logs, tests, and tickets even when the most important truth is in the running system itself.

The problem is not primarily inefficiency. The problem is lack of direct system understanding.

## Why the SDLC Exists

The conventional SDLC was a rational response to real constraints.

Historically, most systems had three hard properties:

- runtime state was opaque or expensive to inspect
- mutation of a live system was risky and hard to govern
- feedback loops were delayed, so teams needed staged controls around change

Those constraints produced sensible engineering norms:

- separate source from runtime
- separate development from operation
- use tests, logs, and review as proxies for behavior
- prefer build-and-deploy cycles over in-place understanding

## What That Model Solved

That model solved real problems well.

It gave teams:

- isolation, so one experiment did not casually corrupt the whole system
- stability, so production behavior did not depend on invisible interactive state
- reproducibility, so a source revision and build pipeline could stand in for the system's truth
- organizational scalability, because teams could coordinate through artifacts instead of shared live state

That is why the current SDLC should be treated as correct for its time rather than as a mistake.

## What Changed

Several constraints that shaped the SDLC have changed materially.

Today it is more viable to build systems where:

- runtime introspection is practical
- stateful agents can reason continuously instead of only per request
- compute and tooling make near-immediate validation possible
- execution, observation, and governance can happen in one environment instead of across disconnected systems

For Common Lisp and SBCL specifically, the change is sharper because the running image is inspectable and mutable in ways that most mainstream toolchains still treat as exceptional.

## Why the Old Model Now Limits Understanding

The conventional model separates:

- source truth
- runtime truth
- workflow truth

That separation remains useful, but it creates systemic blind spots when the system is complex, stateful, and actively changing.

Typical failure modes are:

- source says one thing while the warm runtime is doing another
- logs and tests become proxies for causality instead of causality itself
- a fix appears correct because of hidden image state, not because the system is actually reconciled
- human and agent decisions are recorded in disconnected places with weak linkage to execution

In other words, the model encourages reconstruction after the fact rather than direct understanding during the work.

## Why Current Agent Systems Plateau

Most current agent systems inherit the same limitation.

They usually operate on:

- files, not the live runtime
- tool outputs, not native system state
- episodic prompts, not continuous causality

That gives them reach, but it also caps their depth. They can manipulate representations of the system while remaining outside the system's actual operational substrate.

They rely on tools to approximate state. They do not inhabit state directly.

## Why Governed Environments Expose the Limitation

In lightly governed work, reconstruction can be tolerated. In governed environments, it becomes a structural weakness.

These environments need:

- traceable causality
- explicit approvals
- durable evidence
- reproducibility across source and runtime
- clear accountability for machine and human actions

A model that depends on “we can infer what happened later” is increasingly inadequate there.

## Why a New Model Becomes Necessary

Once direct runtime understanding becomes possible, a better question appears:

How do you let humans and agents work inside a live system without giving up governance, evidence, or reproducibility?

That is the design space `sbcl-agent` is exploring.

It is not trying to discard source control, tests, or workflow discipline. It is trying to unify them with runtime-native understanding instead of treating the runtime as something that can only be approached indirectly.

## The Role of sbcl-agent

`sbcl-agent` implements a model where:

- the live SBCL image is first-class
- conversation is durable but not architecturally total
- workflow records, approvals, incidents, and artifacts are explicit
- source truth, image truth, and workflow truth remain separate but linked

That is the core thesis of the project:

The next step after source-first tooling and tool-mediated agents is a governed environment where interaction, execution, and evidence can coexist in one system.
