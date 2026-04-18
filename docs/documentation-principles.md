---
layout: default
title: Documentation Principles
hero_title: Documentation Constitution
hero_text: The documentation should teach the problem, the capability shift, the model, the implementation, the usage, and the risk in that order.
eyebrow: Docs Rules
permalink: /documentation-principles.html
description: Principles for keeping sbcl-agent documentation coherent, honest, and aligned with the codebase.
---
## Purpose

This document defines how project documentation should be structured and maintained.

It exists to keep the docs aligned with the codebase and to stop the project from drifting back into overlapping rationale, architecture, and roadmap documents that force readers to assemble the story themselves.

## Core Rules

1. Problem first.
2. One definition per concept.
3. Separate conceptual model, implementation, usage, and roadmap.
4. Governance must be treated as intrinsic, not as a later add-on.
5. Risk must be addressed explicitly and honestly.
6. The docs must distinguish clearly between what is implemented, what is transitional, and what is planned.

## Required Narrative Order

When a document introduces a major concept, it should usually follow this sequence:

1. Problem
2. Capability shift
3. Model
4. Implementation
5. Usage
6. Risk

Not every page needs every section, but the system as a whole should preserve that order.

## Writing Rules

- Explain the system in the order a reader understands it, not in the order files were written.
- Prefer necessary complexity over decorative abstraction.
- Do not present roadmap material as shipped behavior.
- Do not duplicate definitions across multiple top-level docs when one canonical page can own the term.
- When the codebase is transitional, say so directly.

## Repository Rules

- `README.md` is the gateway, not the full explanation.
- `docs/index.md` is the structured documentation front door.
- problem and conceptual docs should come before architecture and operator docs.
- roadmap docs should be clearly marked as forward-looking and should not be the recommended first read.

## Maintenance Standard

The docs are aligned when:

- the front door matches the current runtime and code structure
- new readers can understand why the project exists before reading architecture details
- strengths and weaknesses are both visible
- operator adoption does not depend on reading the roadmap first
