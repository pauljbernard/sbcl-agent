# tutor-codex

`tutor-codex` is an SBCL-native Codex-style CLI written in Common Lisp. The command-line entrypoints, the interactive shell, the session model, the tool interface, and the runtime orchestration are all implemented in CL so the system stays "turtles all the way down".

## What It Does

The current runtime provides:

- a Common Lisp CLI targeting Steel Bank Common Lisp (SBCL)
- CL-native executable entrypoints in `bin/`
- an interactive Lisp shell for agent-style workflows
- a provider abstraction with a working mock provider and an OpenAI-compatible adapter
- streamed assistant responses
- staged assistant actions that require explicit execution
- session state, transcript logging, and session persistence
- a capability policy model for controlled operations
- sandbox-backed process and git execution
- queued tasks and background worker threads
- CL-native workspace, docs, session, process, patch, and git tools

## Requirements

- SBCL
- Git, if you want to use the git workflow tools
- A POSIX-like shell environment for the helper entrypoints in `bin/`

The project is developed and tested against SBCL. Other Common Lisp runtimes are not a current target.

## Repository Layout

```text
sbcl-agent/
├── tutor-codex.asd
├── README.md
├── docs/
│   ├── architecture.md
│   └── implementation-plan.md
├── bin/
│   ├── run-tests
│   ├── sandbox-runner
│   └── tutor-codex
├── src/
│   ├── package.lisp
│   ├── config.lisp
│   ├── json.lisp
│   ├── provider-protocol.lisp
│   ├── provider-mock.lisp
│   ├── provider-openai.lisp
│   ├── commands.lisp
│   ├── events.lisp
│   ├── policy.lisp
│   ├── session.lisp
│   ├── sandbox.lisp
│   ├── tools-registry.lisp
│   ├── tools-fs.lisp
│   ├── tools-session.lisp
│   ├── tools-docs.lisp
│   ├── tools-process.lisp
│   ├── tools-git.lisp
│   ├── patch.lisp
│   ├── tasks.lisp
│   ├── shell.lisp
│   ├── repl.lisp
│   └── main.lisp
└── tests/
    ├── package.lisp
    └── smoke.lisp
```

## Quick Start

From the repository root:

```bash
./bin/tutor-codex doctor
./bin/tutor-codex chat
./bin/run-tests
```

Top-level CLI commands:

- `./bin/tutor-codex help`
- `./bin/tutor-codex doctor`
- `./bin/tutor-codex chat`
- `./bin/tutor-codex exec <cmd...>`
- `./bin/run-tests`

## Runtime Configuration

Environment variables:

- `TUTOR_CODEX_PROVIDER`: provider backend, defaults to `mock`
- `TUTOR_CODEX_MODEL`: logical model name, defaults to `gpt-5`
- `TUTOR_CODEX_API_BASE`: base URL for the OpenAI-compatible provider
- `OPENAI_API_KEY`: API key for the OpenAI-compatible provider

If no provider configuration is supplied, the runtime uses the mock provider. That is the easiest way to validate the environment and exercise the shell without external dependencies.

## Doctor Command

`./bin/tutor-codex doctor` reports the current runtime state, including:

- runtime and provider selection
- working directory
- current shell package
- session id and event counts
- queued task and active worker counts
- approved capability grants
- available sandbox profiles
- whether git tools are registered
- whether API base and API key are configured

Use `doctor` first if startup behavior looks wrong.

## Interactive Common Lisp Shell

Start the shell with:

```bash
./bin/tutor-codex chat
```

Inside `chat`, the primary interface is Common Lisp. Any form that is not recognized as a shell command is evaluated in the `TUTOR-CODEX-USER` package.

Basic examples:

```lisp
(+ 100 203)
(plan "implement a new tool")
(ask "please read src/main.lisp")
(ask "please read src/main.lisp" :stream t)
(ask "please read src/main.lisp" :enqueue t)
(describe-session)
```

### Shell Commands

Available shell commands:

- `(help)`
- `(ask "prompt")`
- `(ask "prompt" :stream t)`
- `(ask "prompt" :enqueue t)`
- `(execute-actions)`
- `(plan "goal")`
- `(enqueue-task '(tool ...))`
- `(list-tasks)`
- `(describe-task "task-id")`
- `(monitor-task "task-id")`
- `(run-next-task)`
- `(start-worker)`
- `(stop-worker "worker-id")`
- `(list-workers)`
- `(describe-worker "worker-id")`
- `(approve :policy-name)`
- `(tool :tool-id ...)`
- `(patch '((:write "path" "content")))`
- `(session/save "path")`
- `(session/load "path")`
- `(session/reset)`
- `(describe-session)`

### Normal Lisp Evaluation

You can use the shell as a regular Lisp REPL for local computation:

```lisp
(defparameter *x* 42)
(* *x* 2)
(mapcar #'1+ '(1 2 3))
```

## Provider Behavior

The provider boundary returns CL data structures rather than opaque text blobs.

Current provider modes:

- `mock`: local mock responses for smoke tests and environment validation
- `openai-compatible`: structured provider adapter using `TUTOR_CODEX_API_BASE` and `OPENAI_API_KEY`

The shell supports both non-streaming and streaming asks. Streaming asks emit provider events during response assembly and still return a final assistant response object.

## Assistant Actions

Assistant responses can include staged actions. Actions are not executed implicitly.

Typical flow:

```lisp
(ask "please read src/main.lisp")
(execute-actions)
```

This makes side effects explicit and keeps the runtime control surface in Lisp.

## Capability Policies

Potentially stateful or risky operations are guarded by capability policies.

Current capability policies:

- `:safe-read`: implicit read-only operations inside the current workspace
- `:process-run`: local process execution
- `:git-read`: read-only git operations
- `:git-write`: git mutations such as add, commit, and branch changes
- `:workspace-write`: patch-based file writes

Grant a capability for the current session with:

```lisp
(approve :process-run)
(approve :git-read)
(approve :git-write)
(approve :workspace-write)
```

The session summary includes both the legacy approved-policy view and the richer capability grant summaries.

## Tool Interface

Tools are invoked as Common Lisp forms through `(tool ...)`.

### Workspace Tools

- `:fs/read`
- `:fs/list`

Examples:

```lisp
(tool :fs/read :path "src/main.lisp")
(tool :fs/list :path "src")
```

### Session Tools

- `:session/summary`
- `:session/events`

Examples:

```lisp
(tool :session/summary)
(tool :session/events :tail 10)
```

### Documentation Tools

- `:docs/read`
- `:docs/list`

Examples:

```lisp
(tool :docs/read :path "architecture.md")
(tool :docs/list)
```

These are constrained to the repository `docs/` tree.

### Process Tool

- `:proc/run`

Example:

```lisp
(approve :process-run)
(tool :proc/run :argv '("/bin/echo" "hello"))
```

Process execution is sandbox-backed and returns stdout, stderr, exit code, and sandbox metadata.

### Git Tools

- `:git/status`
- `:git/diff`
- `:git/add`
- `:git/commit`
- `:git/branch`

Examples:

```lisp
(approve :git-read)
(tool :git/status)
(tool :git/diff)

(approve :git-write)
(tool :git/add :paths '("README.md"))
(tool :git/commit :message "Document README")
(tool :git/branch :name "feature/readme" :checkout t)
```

Git commands run through the sandbox process path rather than in-process stubs.

## Patch Workflow

Patch application is represented as Common Lisp data.

Example:

```lisp
(approve :workspace-write)
(patch '((:write "notes.txt" "hello from Common Lisp")))
```

Current patch support is intentionally narrow: `:write` operations within the active session workspace.

## Tasks And Workers

The runtime supports queued work and background processing.

### Queue A Task

```lisp
(enqueue-task '(tool :fs/read :path "src/main.lisp"))
(list-tasks)
(run-next-task)
```

### Queue An Ask

```lisp
(ask "please read src/main.lisp" :enqueue t)
(list-tasks)
(run-next-task)
```

### Run Background Workers

```lisp
(start-worker)
(list-workers)
(describe-worker "worker-id")
(stop-worker "worker-id")
```

### Inspect Task Progress

```lisp
(describe-task "task-id")
(monitor-task "task-id")
```

Queued asks record streamed provider progress, task lifecycle events, and final assistant results.

## Session Persistence

Sessions can be written to and loaded from s-expression files.

Examples:

```lisp
(session/save "/tmp/tutor-codex-session.sexp")
(session/load "/tmp/tutor-codex-session.sexp")
(session/reset)
```

Persisted session state includes transcript, plan, events, capability grants, tasks, and worker metadata suitable for restoring the logical session state.

## Testing

Run the full smoke suite with:

```bash
./bin/run-tests
```

The suite covers:

- SBCL runtime smoke validation
- provider decoding and streaming
- shell command dispatch
- staged assistant actions
- task queues and workers
- session save/load flows
- session and docs tools
- sandboxed process and git tools
- capability policy enforcement
- patch approval and path safety

The first test validates that SBCL can start, load the system, and execute a basic assertion, so environment failures are caught immediately.

## Architecture And Design Docs

Project design documents:

- [docs/architecture.md](docs/architecture.md)
- [docs/implementation-plan.md](docs/implementation-plan.md)

The architecture target is a self-contained Common Lisp agent runtime in which Lisp is both the user interface and the execution substrate.

## Current Limitations

The runtime is still early-stage. Current known limitations include:

- the OpenAI-compatible provider path is not yet the primary tested workflow
- sandboxing is stronger than simple in-process gating, but still not a full external isolation system
- patch operations currently support only `:write`
- task orchestration is queue-based, not yet dependency-graph-based
- the CLI remains intentionally small, with most behavior exposed through the Lisp shell

## Development Notes

All executable surfaces in the repository are intended to remain Common Lisp. If you add new runtime entrypoints, they should preserve the CL-native model rather than introducing non-Lisp control scripts.
