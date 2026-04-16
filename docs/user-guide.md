---
layout: default
title: User Guide
hero_title: User Guide
hero_text: The operator surface is intentionally direct: an SBCL-native CLI, a Common Lisp shell, explicit capability approval, structured tools, and staged actions rather than hidden side effects.
eyebrow: Operators
permalink: /user-guide.html
description: Detailed user guide for sbcl-agent.
---
## What You Can Do Today

`sbcl-agent` already supports a practical local workflow:

- inspect environment and configuration with `doctor`
- use an interactive Common Lisp shell with `chat`
- evaluate normal Lisp forms inside the shell
- ask a provider for responses, including streaming mode
- stage assistant-proposed actions before executing them
- run structured tools for files, docs, session state, processes, patches, and git
- create and inspect work-items and workflow records through the shell and tools
- run queued tasks and background workers

## Installation Expectations

The project currently assumes:

- SBCL is installed
- you can run the `bin/` scripts from a POSIX-like shell
- git is installed if you want git-backed workflows

From the repository root, the basic verification path is:

```bash
./bin/sbcl-agent doctor
./bin/run-tests
```

## Runtime Configuration

Configuration is currently environment-driven with one local-file fallback for the API key and automatic provider selection based on whether a key is available.

### Environment variables

- `TUTOR_CODEX_PROVIDER`: provider backend override; when unset, the runtime selects `openai-compatible` if an API key is available and otherwise falls back to `mock`
- `TUTOR_CODEX_MODEL`: logical model name, defaults to `gpt-5`
- `TUTOR_CODEX_API_BASE`: base URL for the OpenAI-compatible provider
- `OPENAI_API_KEY`: API key for the OpenAI-compatible provider

### API key fallback file

If `OPENAI_API_KEY` is unset, the runtime falls back to `openai-api-key.key` in the current working directory.

That lets you keep the key in a local file in the project root while avoiding shell-history leakage. `.key` files are ignored by git.

## CLI Commands

### `./bin/sbcl-agent help`

Shows the available top-level commands.

### `./bin/sbcl-agent doctor`

Prints the current runtime state, including provider selection, session metadata, capability state, worker counts, operator status buckets, validator replay groups, image reconciliations, and API-key presence.

Use this first when startup behavior looks wrong.

### `./bin/sbcl-agent chat`

Starts the interactive shell.

### `./bin/sbcl-agent exec <cmd...>`

Runs an external command via the CLI surface.

### `./bin/run-tests`

Runs the SBCL test suite.

## Interactive Shell Basics

The shell is Common Lisp. Recognized forms are treated as shell commands. Everything else is evaluated as normal Lisp in the `SBCL-AGENT-USER` package.

### Example shell session

```lisp
(+ 100 203)
(plan "investigate provider flow")
(ask "please read src/main.lisp")
(execute-actions)
(describe-session)
```

### Examples of normal Lisp use

```lisp
(defparameter *files* '("src/main.lisp" "src/shell.lisp"))
(mapcar #'length *files*)
(remove-if-not #'oddp '(1 2 3 4 5))
```

## Shell Commands

### Querying and planning

- `(help)`
- `(plan "goal")`
- `(describe-session)`

### Asking the provider

- `(ask "prompt")`
- `(ask "prompt" :stream t)`
- `(ask "prompt" :enqueue t)`

### Assistant actions

- `(execute-actions)`

Assistant actions are staged first. They do not run implicitly.

### Tasks and workers

- `(enqueue-task '(tool ...))`
- `(list-tasks)`
- `(describe-task "task-id")`
- `(monitor-task "task-id")`
- `(run-next-task)`
- `(start-worker)`
- `(stop-worker "worker-id")`
- `(list-workers)`
- `(describe-worker "worker-id")`

### Session persistence

- `(session/save "path")`
- `(session/load "path")`
- `(session/reset)`

### Approvals and tools

- `(approve :process-run)`
- `(approve :git-read)`
- `(approve :git-write)`
- `(approve :workspace-write)`
- `(tool :tool-id ...)`
- `(patch '((:write "path" "content")))`

### Work-item and operator visibility

- `(why-waiting "work-id")`
- `(list-replay-groups)`
- `(list-image-reconciliations)`
- `(replay-validator-task "work-id" "validator-id" :status :passed)`
- `(replay-validator-set "work-id" "replay-id" :status :passed :statuses '(:live :partial :cold :passed))`
- `(reconcile-image-only-source "work-id" "summary")`

## Provider Modes

### Mock provider

The mock provider is the default. Use it for:

- smoke tests
- development without network dependency
- shell behavior verification
- deterministic local validation

### OpenAI-compatible provider

Use `TUTOR_CODEX_PROVIDER=openai-compatible` or `openai` to activate the network-backed provider.

Typical configuration:

```bash
export TUTOR_CODEX_PROVIDER=openai-compatible
export TUTOR_CODEX_MODEL=gpt-5
export TUTOR_CODEX_API_BASE=https://api.openai.com/v1
export OPENAI_API_KEY=... 
./bin/sbcl-agent chat
```

Or place the key in `openai-api-key.key` in the repository root and omit the environment variable.

## Tool Families

### Filesystem tools

Examples:

```lisp
(tool :fs/read :path "src/main.lisp")
(tool :fs/list :path "src")
```

### Docs tools

Use these to read project documentation through the tool layer rather than direct shelling.

### Session tools

Examples:

```lisp
(tool :session/summary)
(tool :session/events)
(tool :session/operator-status)
(tool :session/replay-groups)
(tool :session/image-reconciliations)
```

### Process tools

Process execution is capability-gated and should be explicitly approved when needed.

### Git tools

Git reads and writes are exposed through CL-native tools, with write paths gated separately from reads.

## Capability Model

`sbcl-agent` does not silently execute risky operations. The current capability model makes these actions explicit.

Main capability families today:

- `:safe-read`
- `:process-run`
- `:git-read`
- `:git-write`
- `:workspace-write`

A typical session grants only what it needs.

## Recommended First Workflow

1. Run `./bin/sbcl-agent doctor`.
2. Run `./bin/run-tests`.
3. Start `./bin/sbcl-agent chat`.
4. Evaluate `(+ 100 203)` to verify Lisp evaluation works.
5. Use `(ask "please summarize src/main.lisp")`.
6. Inspect the session with `(describe-session)`.
7. Approve only the capabilities you need before stateful operations.

## Operational Caveats

- Live-image success is not the same as cold-start reproducibility.
- The architecture already models this distinction, but not every desired safety mechanism is at full maturity yet.
- Prefer explicit validation after meaningful mutation.
- Treat image-only results as provisional until reconciled back to durable source truth.

For the design rationale behind those cautions, read [Why sbcl-agent Exists]({{ '/why-sbcl-agent.html' | relative_url }}) and [Architecture and Design]({{ '/architecture.html' | relative_url }}).
