# sbcl-agent

`sbcl-agent` is an SBCL-native agent runtime and CLI written in Common Lisp. It started as a Codex-style shell, but the codebase is now evolving into a conversation-native engineering environment with three explicit truth domains:

- source truth: files, diffs, tests, and durable artifacts
- image truth: the live SBCL image, loaded definitions, packages, objects, threads, and runtime resources
- workflow truth: the governed record of plans, mutations, approvals, validations, checkpoints, and reconciliation

The architectural goal is not to clone Codex literally. The goal is to provide Codex-class engineering usefulness on top of an SBCL-native substrate that can inspect and mutate the same running system it is reasoning about.

## Documentation

The primary docs live in [`docs/`](/Volumes/data/development/sbcl-agent/docs).

Start with:

- [`docs/index.md`](/Volumes/data/development/sbcl-agent/docs/index.md)
- [`docs/objectives.md`](/Volumes/data/development/sbcl-agent/docs/objectives.md)
- [`docs/why-sbcl-agent.md`](/Volumes/data/development/sbcl-agent/docs/why-sbcl-agent.md)
- [`docs/architecture.md`](/Volumes/data/development/sbcl-agent/docs/architecture.md)
- [`docs/user-guide.md`](/Volumes/data/development/sbcl-agent/docs/user-guide.md)
- [`docs/implementation-plan.md`](/Volumes/data/development/sbcl-agent/docs/implementation-plan.md)

Conversation-runtime design and migration docs:

- [`docs/conversation-architecture.md`](/Volumes/data/development/sbcl-agent/docs/conversation-architecture.md)
- [`docs/streaming-event-model.md`](/Volumes/data/development/sbcl-agent/docs/streaming-event-model.md)
- [`docs/migration-plan-thread-runtime.md`](/Volumes/data/development/sbcl-agent/docs/migration-plan-thread-runtime.md)

Background docs:

- [`docs/common-lisp-runtime.md`](/Volumes/data/development/sbcl-agent/docs/common-lisp-runtime.md)
- [`docs/common-lisp-guide.md`](/Volumes/data/development/sbcl-agent/docs/common-lisp-guide.md)

## What It Does Today

The current runtime already provides:

- an SBCL-native CLI and interactive Common Lisp shell
- direct Lisp evaluation in the same environment that hosts the agent
- a provider boundary with mock and OpenAI-compatible backends
- streamed responses through a canonical provider-event layer
- conversation primitives: threads, messages, turns, operations, and artifacts
- `ask` compatibility plus `say` as the conversation-first turn entrypoint
- persisted session state with thread-aware shell workflows
- staged assistant actions, approval-gated turn resume, and explicit capability grants
- structured tools for files, docs, session visibility, processes, git, and patches
- queued tasks and background workers
- governed work-items, workflow records, validator replay groups, image-only outcomes, and reconciliation records

## Design Rule

The refactor direction is organized around one rule:

- conversation owns interaction state
- runtime owns execution state
- workflow owns engineering governance

That rule fits the codebase's existing strengths instead of replacing them. The shell stays Lisp-native, the runtime stays image-native, and workflow records remain authoritative for governed engineering work.

## Requirements

- SBCL
- a POSIX-like shell environment for the helper scripts in [`bin/`](/Volumes/data/development/sbcl-agent/bin)
- git if you want git-backed tooling and workflows

The project is developed and tested against SBCL. Other Common Lisp implementations are not current targets.

## Repository Layout

```text
sbcl-agent/
├── sbcl-agent.asd
├── README.md
├── bin/
│   ├── run-coverage
│   ├── run-tests
│   ├── sandbox-runner
│   └── sbcl-agent
├── docs/
│   ├── architecture.md
│   ├── conversation-architecture.md
│   ├── implementation-plan.md
│   ├── migration-plan-thread-runtime.md
│   ├── streaming-event-model.md
│   └── user-guide.md
├── src/
│   ├── commands.lisp
│   ├── config.lisp
│   ├── conversation.lisp
│   ├── events.lisp
│   ├── main.lisp
│   ├── patch.lisp
│   ├── policy.lisp
│   ├── provider-mock.lisp
│   ├── provider-openai.lisp
│   ├── provider-protocol.lisp
│   ├── sandbox.lisp
│   ├── session.lisp
│   ├── shell.lisp
│   ├── tasks.lisp
│   ├── tools-*.lisp
│   ├── turn-orchestrator.lisp
│   ├── work-items.lisp
│   └── workflow.lisp
└── tests/
    ├── package.lisp
    └── smoke.lisp
```

## Quick Start

From the repository root:

```bash
./bin/sbcl-agent doctor
./bin/sbcl-agent chat
./bin/sbcl-agent chat -i
./bin/run-tests
```

Top-level CLI commands:

- `./bin/sbcl-agent help`
- `./bin/sbcl-agent doctor`
- `./bin/sbcl-agent chat`
- `./bin/sbcl-agent chat -i`
- `./bin/sbcl-agent exec <cmd...>`
- `./bin/run-tests`
- `./bin/run-coverage`
- `./bin/build-docs`
- `./bin/serve-docs`

`chat -i` enables interactive streaming by default for `(ask ...)` calls while preserving the normal Lisp shell behavior.

## Shell Model

Inside `chat`, recognized forms are treated as shell commands. Everything else is evaluated as normal Lisp in the `SBCL-AGENT-USER` package.

Core interaction paths:

- direct Lisp evaluation for local reasoning and runtime inspection
- `(ask ...)` for compatibility with the original streamed ask workflow
- `(say ...)` for thread-based conversational turns
- thread commands for creating, listing, switching, and inspecting conversations
- turn commands for status inspection and approval-gated resume
- tools, tasks, workers, work-items, replay, and reconciliation commands

Example session:

```lisp
(+ 100 203)
(thread/new :title "provider refactor")
(say "Summarize the current provider and event architecture." :stream t)
(turn/status)
(describe-session)
```

## Runtime Configuration

Environment variables:

- `TUTOR_CODEX_PROVIDER`: provider backend override; when unset, the runtime chooses `openai-compatible` if an API key is available and otherwise falls back to `mock`
- `TUTOR_CODEX_MODEL`: primary model name, defaults to `gpt-5`
- `TUTOR_CODEX_FAST_MODEL`: low-latency model name for ordinary asks, defaults to `gpt-4.1-mini`
- `TUTOR_CODEX_API_BASE`: base URL for the OpenAI-compatible provider
- `OPENAI_API_KEY`: API key for the OpenAI-compatible provider

If `OPENAI_API_KEY` is unset, `sbcl-agent` falls back to `openai-api-key.key` in the current working directory and trims trailing whitespace.

## Doctor Command

`./bin/sbcl-agent doctor` reports the current runtime state, including:

- provider and model selection
- working directory and shell package
- session id and event counts
- pending assistant actions
- queued tasks and active workers
- approved policies and capability grants
- work-item, replay-group, and image-reconciliation counts
- operator status buckets
- sandbox profiles
- API base and API key presence

Use `doctor` first when startup or configuration looks wrong.

## Testing

The test suite is run through the project scripts:

```bash
./bin/run-tests
./bin/run-coverage
```

The mock provider is the fastest way to validate shell, event, and orchestration behavior without external network dependencies.

## Docs Publishing

The docs site is now meant to be generated from the Markdown sources in [`docs/`](/Volumes/data/development/sbcl-agent/docs) through Jekyll rather than maintained as checked-in rendered HTML.

Local workflows:

```bash
bundle install
./bin/build-docs
./bin/serve-docs
```

The generated site is written to `docs/_site/` and is ignored by git. GitHub Pages deployment is defined in [docs.yml](/Volumes/data/development/sbcl-agent/.github/workflows/docs.yml).
