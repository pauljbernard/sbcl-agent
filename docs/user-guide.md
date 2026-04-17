---
layout: default
title: User Guide
hero_title: User Guide
hero_text: "The operator surface stays direct: an SBCL-native CLI, a Common Lisp shell, explicit approvals, structured tools, and now a thread-and-turn conversation layer on top of the same runtime."
eyebrow: Operators
permalink: /user-guide.html
description: Detailed user guide for sbcl-agent.
---
## What You Can Do Today

`sbcl-agent` currently supports two styles of interaction on one runtime:

- REPL-style operation, where you type Lisp forms or shell commands and get results immediately
- conversation-style operation, where you work in durable threads and turns using `(say ...)`

Both styles share the same provider, tool, session, policy, task, and workflow layers.

## Installation Expectations

The current project assumes:

- SBCL is installed
- you can run the scripts in [`bin/`](/Volumes/data/development/sbcl-agent/bin) from a POSIX-like shell
- git is installed if you want git-backed workflows

Basic verification from the repository root:

```bash
./bin/sbcl-agent doctor
./bin/run-tests
```

## Runtime Configuration

Environment variables:

- `TUTOR_CODEX_PROVIDER`: provider override; if unset, the runtime chooses `openai-compatible` when an API key is available and otherwise falls back to `mock`
- `TUTOR_CODEX_MODEL`: primary model name, defaults to `gpt-5`
- `TUTOR_CODEX_FAST_MODEL`: low-latency model name used for lighter asks, defaults to `gpt-4.1-mini`
- `TUTOR_CODEX_API_BASE`: base URL for the OpenAI-compatible provider
- `OPENAI_API_KEY`: API key for the OpenAI-compatible provider

If `OPENAI_API_KEY` is unset, the runtime falls back to `openai-api-key.key` in the current working directory.

## Top-Level CLI Commands

### `./bin/sbcl-agent help`

Prints the available commands and basic usage.

### `./bin/sbcl-agent doctor`

Prints runtime diagnostics, including provider selection, working directory, shell package, session metadata, pending assistant actions, tasks, work-items, worker counts, approved policies, replay groups, reconciliation counts, and API-key presence.

### `./bin/sbcl-agent chat`

Starts the interactive Common Lisp shell.

### `./bin/sbcl-agent chat -i`

Starts the shell with interactive streaming enabled by default for `(ask ...)`. This preserves the original streamed-ask operator flow while keeping all of the newer thread and turn commands available.

### `./bin/sbcl-agent exec <cmd...>`

Runs an external command through the CLI surface.

### `./bin/run-tests`

Runs the test suite.

### `./bin/run-coverage`

Runs the test suite with coverage collection.

## Interactive Shell Basics

The shell is Common Lisp. Recognized forms are treated as shell commands. Everything else is evaluated as normal Lisp in the `SBCL-AGENT-USER` package.

Example:

```lisp
(+ 100 203)
(defparameter *files* '("src/main.lisp" "src/shell.lisp"))
(mapcar #'length *files*)
```

That means the shell is both:

- the operator control surface
- a real Lisp REPL inside the same runtime the agent is using

## Conversation Workflow

The newer conversation model adds durable threads and turns on top of the shell.

### Create or inspect threads

Available commands:

- `(thread/new :title "provider refactor")`
- `(thread/list)`
- `(thread/use "thread-id")`
- `(thread/show)`
- `(thread/show "thread-id")`

Practical pattern:

```lisp
(thread/new :title "docs refresh")
(thread/list)
(thread/show)
```

### Start a conversational turn

Use `(say ...)` to run a conversation-native turn in the current thread.

Examples:

```lisp
(say "Summarize the current event architecture.")
(say "Summarize the current event architecture." :stream t)
```

The runtime records:

- the user message
- the assistant message
- the turn
- any operation records created during the turn
- any artifacts linked to that turn

### Inspect or resume turns

Useful commands:

- `(turn/status)`
- `(turn/status "turn-id")`
- `(turn/resume)`
- `(turn/resume "turn-id")`

`turn/status` now reports the current turn state with message, operation, and artifact counts plus the active assistant message and approval summary when relevant.

If a turn pauses for approval, `turn/status` tells you why and `turn/resume` continues it after the relevant approval or staged-action execution step is satisfied. A resumed turn may also trigger a provider follow-up run so the turn can finish with a fresh assistant message instead of stopping at raw action execution.

## `ask` Versus `say`

Both commands remain valid, but they have different roles now.

### `(ask ...)`

`ask` is the compatibility surface for the original provider-query workflow.

Examples:

```lisp
(ask "Read src/main.lisp")
(ask "Read src/main.lisp" :stream t)
(ask "Read src/main.lisp" :enqueue t)
```

Use `ask` when you want the older direct query flow or when you are relying on existing scripts and habits.

Internally, `ask` now uses the same turn runner as `say`. The main difference is operator intent and presentation:

- `ask` keeps the older REPL-bridge semantics
- `say` is the clearer thread-first conversational surface
- both now persist thread, turn, operation, and assistant-message state consistently

### `(say ...)`

`say` is the conversation-first path. It binds the interaction to the current thread and turn model and is the clearest expression of the new architecture.

Use `say` when you want:

- durable conversational context
- thread-level history
- turn-level status and resume behavior
- operations and artifacts linked to the interaction

## Assistant Actions and Approvals

`sbcl-agent` does not silently execute risky work just because the model mentioned it.

### Staged assistant actions

Commands:

- `(execute-actions)`
- `(approve :policy-name)`

Assistant-proposed actions can be staged before execution. This preserves operator control and keeps shell workflows explicit.

### Capability grants

Important current capability and policy families include:

- `:safe-read`
- `:process-run`
- `:git-read`
- `:git-write`
- `:runtime-eval-safe`
- `:runtime-eval-mutate`
- `:workspace-write`

Typical approval commands:

```lisp
(approve :process-run)
(approve :git-read)
(approve :workspace-write)
```

### Approval-gated turn flow

A conversation turn can reach an awaiting-approval state when an operation needs explicit authorization. In that case:

1. inspect the turn with `(turn/status)`
2. grant the needed approval
3. resume with `(turn/resume)`

Patch turns, mutating runtime eval turns, and write-class tool turns such as `git-write` now bind more directly into workflow governance. When those governed actions appear, the turn can create a work-item, record a checkpoint, and carry approval state as part of the workflow evidence rather than only as transcript text.

## Structured Tools

Tools are explicit CL-callable operations. The shell command is:

```lisp
(tool :tool-id ...)
```

Examples:

```lisp
(tool :fs/read :path "src/main.lisp")
(tool :fs/list :path "src")
(tool :session/summary)
(tool :session/events)
```

Current tool families include:

- filesystem tools
- docs tools
- session visibility tools
- process tools
- git tools
- patch application

## Tasks and Workers

The runtime includes a queue and background worker system.

Commands:

- `(enqueue-task '(tool ...))`
- `(list-tasks)`
- `(describe-task "task-id")`
- `(cancel-task "task-id")`
- `(monitor-task "task-id")`
- `(run-next-task)`
- `(start-worker)`
- `(stop-worker "worker-id")`
- `(list-workers)`
- `(describe-worker "worker-id")`

Use these when work should be queued, monitored, or delegated to background execution rather than run inline in the current shell interaction.

## Work-Items and Workflow Records

The governed engineering layer remains separate from the chat layer.

Useful commands:

- `(list-work-items)`
- `(describe-work-item "work-id")`
- `(list-workflow-records)`
- `(describe-workflow-record "record-id")`
- `(request-work-item-approval "work-id" :workspace-write :reason "why")`
- `(quarantine-work-item "work-id" "why")`
- `(resume-work-item "work-id")`
- `(why-waiting "work-id")`

This is the layer that preserves:

- workflow evidence
- approval state
- quarantine state
- replayable validator records
- image-only and reconciliation outcomes

## Replay and Reconciliation

Commands:

- `(list-replay-groups)`
- `(list-image-reconciliations)`
- `(replay-validator-task "work-id" "validator-id" :status :passed)`
- `(replay-validator-set "work-id" "replay-id" :status :passed :statuses '(:live :partial :cold :passed))`
- `(reconcile-image-only-source "work-id" "summary")`

These commands matter because live-image success and durable source truth are not always the same thing. The runtime preserves that distinction instead of flattening it.

## Session Persistence

Commands:

- `(session/save "path")`
- `(session/load "path")`
- `(session/reset)`
- `(describe-session)`

The session layer now carries both the older runtime state and the newer thread-and-turn state. Persistence is therefore useful both for shell continuity and for recovering conversational context.

## Provider Modes

### Mock provider

Use the mock provider for:

- smoke testing
- local shell and event behavior validation
- deterministic development without network dependency

### OpenAI-compatible provider

Typical configuration:

```bash
export TUTOR_CODEX_PROVIDER=openai-compatible
export TUTOR_CODEX_MODEL=gpt-5
export TUTOR_CODEX_API_BASE=https://api.openai.com/v1
export OPENAI_API_KEY=...
./bin/sbcl-agent chat
```

You can also place the key in `openai-api-key.key` at the repository root.

## Recommended First Operator Flow

1. Run `./bin/sbcl-agent doctor`.
2. Run `./bin/run-tests`.
3. Start `./bin/sbcl-agent chat`.
4. Evaluate a simple Lisp form such as `(+ 100 203)`.
5. Create a thread with `(thread/new :title "first session")`.
6. Run `(say "Summarize the current architecture." :stream t)`.
7. Inspect the result with `(turn/status)` and `(thread/show)`.
8. Grant only the capabilities you actually need before stateful operations.

## Operational Caveats

- A successful warm-image interaction is not the same thing as a durable source-backed fix.
- Conversation state, runtime state, and workflow state are related but not interchangeable.
- Use approvals deliberately. The architecture is designed to make mutating operations visible, not implicit.
- Treat image-only outcomes as provisional until they are reconciled back to source truth and workflow evidence.

For the rationale behind these constraints, read [Why sbcl-agent Exists]({{ '/why-sbcl-agent.html' | relative_url }}) and [Architecture and Design]({{ '/architecture.html' | relative_url }}).
