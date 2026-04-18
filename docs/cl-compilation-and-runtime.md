---
layout: default
title: Common Lisp Compilation and Runtime
hero_title: Compilation and Runtime
hero_text: Compilation, loading, ASDF, runtime images, optimization declarations, and why incremental loading matters in an SBCL-native engineering environment.
eyebrow: CL Reference
permalink: /cl-compilation-and-runtime.html
description: Common Lisp compilation and runtime reference for sbcl-agent.
---
## Compilation and Loading

Common Lisp distinguishes:

- reading source
- macroexpansion
- compilation
- loading compiled output
- loading source directly

This separation matters more than many readers expect.

## Core Functions

Important building blocks include:

- `compile`
- `compile-file`
- `load`

## ASDF

This repository uses ASDF as its system construction and loading mechanism.

Example:

```lisp
(asdf:operate 'asdf:load-op :sbcl-agent)
```

From `sbcl-agent.asd`, the system is assembled from serially loaded source files under `src/` and `tests/`.

## Optimization Declarations

Common Lisp supports declarations such as:

- `type`
- `special`
- `ignore`
- `ignorable`
- `optimize`

Example:

```lisp
(declare (optimize (speed 3) (safety 1)))
```

In this codebase, some test and coverage tooling uses declarations that influence compilation behavior directly.

## Runtime Images

An SBCL image is not just a passive process. It contains:

- loaded definitions
- objects and identity
- packages and symbols
- threads and resources
- dynamic runtime state

That is why `sbcl-agent` treats the live runtime as part of the engineering substrate rather than as disposable execution plumbing.

## Incremental Loading

A Lisp system can load new definitions into a running image without restarting the entire world.

This is a major advantage, but it also creates discipline requirements:

- warm-image success can differ from cold-start success
- source truth and image truth can drift
- reproducibility needs explicit care

Those constraints are central to the overall architecture of this repository.

## Why This Matters Here

This topic is directly tied to:

- the SBCL-native shell model
- the conversation runtime living inside the same process
- provider and tool development loops
- validation and reconciliation concepts in the architecture docs
