---
layout: default
title: Getting Started
hero_title: Getting Started
hero_text: "Start with the real operator surface: the CLI, the Lisp shell, and the thread-based conversation flow that runs inside the same runtime."
eyebrow: Getting Started
permalink: /getting-started.html
description: Install, run, and complete a first interaction with sbcl-agent.
---
## What You Need

- SBCL
- a POSIX-like shell for the scripts in `bin/`
- git if you want git-backed tooling

## First Checks

From the repository root:

```bash
./bin/sbcl-agent doctor
./bin/run-tests
```

`doctor` is the quickest way to confirm provider selection, working directory, API-key visibility, session and environment posture, and pending governed work.

If you want to verify the current internal evaluation harness as well as the test suite, run:

```bash
./bin/run-evals
```

## Start the Shell

Launch the interactive runtime:

```bash
./bin/sbcl-agent chat
```

This is both:

- the Common Lisp shell
- the entry point into the conversation runtime

There is no separate conversation daemon.

If you want to inspect the provider surface before entering the shell, the non-interactive CLI now also supports:

```bash
./bin/sbcl-agent provider show
./bin/sbcl-agent provider preview --prompt "Summarize the current architecture"
```

## First Conversation

Inside the shell:

```lisp
(thread/new :title "first conversation")
(say "Summarize the current architecture." :stream t)
```

This creates a durable thread and runs a turn inside it. The system records the user message, assistant message, turn, any operations, and any resulting artifacts.

## Basic Orientation Commands

Useful early commands:

- `(environment/status)`
- `(thread/list)`
- `(thread/show)`
- `(turn/status)`
- `(describe-session)`
- `(provider/show)`
- `(provider/route)`

Use these to understand what environment is active, which thread is current, whether work is blocked, and what evidence exists.

## How to Think About the Current System

The current implementation is best approached as:

- a real SBCL-native shell you can use now
- a conversation runtime with durable threads and turns
- a governed execution environment with kernel, workflow, compatibility, and desktop-host layers already in place

If you want the detailed command reference, continue to [User Guide]({{ '/user-guide.html' | relative_url }}).
