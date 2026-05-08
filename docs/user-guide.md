---
layout: default
title: User Guide
hero_title: User Guide
hero_text: "The operator surface stays direct: an SBCL-native CLI, a Common Lisp shell, explicit approvals, structured tools, and a growing Environment model in which REPL, conversation, artifacts, and workflow coexist."
eyebrow: Operators
permalink: /user-guide.html
description: Detailed user guide for sbcl-agent.
---
## Reading Position

If you are new to the project, read [Getting Started]({{ '/getting-started.html' | relative_url }}) first.

This page is the detailed operator reference. It assumes you already understand why the system exists and how the basic thread-and-turn workflow starts.

## What You Can Do Today

`sbcl-agent` currently supports several styles of interaction inside one environment:

- REPL-style operation, where you type Lisp forms or shell commands and get results immediately
- conversation-style operation, where you work in durable threads and turns using `(say ...)`
- workflow-style operation, where governed work-items, validations, approvals, and reconciliations remain visible and inspectable

The current `Surface` desktop host that sits on top of these capabilities looks like this:

<img src="{{ '/Desktop.jpg' | relative_url }}" alt="Surface desktop snapshot" style="display:block;max-width:100%;height:auto;margin:1rem auto;" />

These styles share the same provider, tool, session, policy, task, workflow, and execution-kernel layers. They should now be understood as coexisting modes inside one implemented Environment architecture rather than as separate products.

## Installation Expectations

The current project assumes:

- SBCL is installed
- you can run the scripts in `bin/` from a POSIX-like shell
- git is installed if you want git-backed workflows

Basic verification from the repository root:

```bash
./bin/sbcl-agent doctor
./bin/run-tests
./bin/run-evals
```

## Runtime Configuration

Environment variables:

- `TUTOR_CODEX_PROVIDER`: provider override; if unset, the runtime chooses `openai-compatible` when an OpenAI-style key is available, `anthropic` when only an Anthropic key is available, and otherwise falls back to `mock`
- `TUTOR_CODEX_MODEL`: primary model name, defaults to `gpt-5`
- `TUTOR_CODEX_FAST_MODEL`: low-latency model name used for lighter asks, defaults to `gpt-4.1-mini`
- `TUTOR_CODEX_API_BASE`: base URL for OpenAI-compatible and local-compatible providers
- `OPENAI_API_KEY`: API key for the OpenAI-compatible provider family
- `ANTHROPIC_API_KEY`: API key for the Anthropic provider family

If `OPENAI_API_KEY` is unset, the runtime falls back to `openai-api-key.key` in the current working directory. If `ANTHROPIC_API_KEY` is unset, it falls back to `anthropic-api-key.key` in the current working directory.

## Top-Level CLI Commands

### `./bin/sbcl-agent help`

Prints the available commands and basic usage.

### `./bin/sbcl-agent doctor`

Prints runtime diagnostics, including provider selection, working directory, shell package, session metadata, pending assistant actions, tasks, work-items, worker counts, approved policies, replay groups, reconciliation counts, and API-key presence.

### `./bin/sbcl-agent chat`

Starts the interactive Common Lisp shell.

This is also how you enter the conversational layer. There is no separate conversation daemon or separate conversation CLI entrypoint. You start `chat`, then use thread commands plus `(say ...)` inside that shell.

### `./bin/sbcl-agent chat -i`

Starts the shell with interactive streaming enabled by default for `(ask ...)`. This preserves the original streamed-ask operator flow while keeping all of the newer thread and turn commands available.

### `./bin/sbcl-agent exec <cmd...>`

Runs an external command through the CLI surface.

### `./bin/sbcl-agent provider <subcommand>`

Runs the non-shell provider control surface as JSON service envelopes.

Important subcommands:

- `show`: list configured provider profiles, the active profile, and routing policy
- `route`: inspect the last recorded provider-route decision
- `preview --prompt "..."`: preview which profile would handle a prompt and why, without mutating the recorded last route
- `routing --mode auto|manual`: switch provider routing policy
- `configure --profile ... --provider ... --model ...`: add or update a provider profile
- `use --profile ...`: activate a configured profile

### `./bin/sbcl-agent rgp <subcommand>`

Runs the RGP governed-runtime bridge.

Important subcommands:

- `bind`: connect an RGP request and agent-session to a durable `sbcl-agent` environment
- `show`: inspect the current RGP binding and governed runtime summary
- `export`: emit a JSON snapshot with binding, environment, thread, turn, approvals, and artifacts
- `artifacts`: list importable runtime artifacts for RGP
- `approvals`: list pending governed approval checkpoints
- `approve`: approve a governed checkpoint in the external runtime
- `resume`: resume a governed work-item in the external runtime

### `./bin/run-tests`

Runs the test suite.

### `./bin/run-coverage`

Runs the test suite with coverage collection.

### `./bin/run-evals`

Runs the current evaluation suite used to check retrieval, routing, and broader agent behavior against repository scenarios.

## Interactive Shell Basics

The shell is Common Lisp. Recognized forms are treated as shell commands. Everything else is evaluated as normal Lisp in the `SBCL-AGENT-USER` package.

Shell entry is now environment-first in presentation. When `chat` starts, the shell prints the active environment id, active thread and runtime, blocked governed work count, and open incident count before it prints the compatibility session id. That keeps the operator oriented around the environment as the primary world object while preserving the legacy session handle.

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

The startup sequence is:

1. Run `./bin/sbcl-agent chat`.
2. Create or select a thread.
3. Use `(say ...)` in that thread.

Minimal first-run example:

```bash
./bin/sbcl-agent chat
```

Then, inside the shell:

```lisp
(thread/new :title "first conversation")
(say "Summarize the current architecture." :stream t)
```

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

- `(environment/status)`
- `(runtime/find-definition "symbol")`
- `(runtime/callers "symbol")`
- `(runtime/methods "generic-function")`
- `(runtime/source-image-divergence "symbol")`
- `(turn/status)`
- `(turn/status "turn-id")`
- `(turn/resume)`
- `(turn/resume "turn-id")`
- `(incident/list)`
- `(incident/show "incident-id")`
- `(review/mutation)`
- `(review/mutation "turn-id")`

`turn/status` now reports the current turn state with message, operation, artifact, and incident counts plus the active assistant message and approval summary when relevant.

`environment/status` is the default orientation surface. It answers, in one command, which environment, thread, and runtime are active, what work is blocked, how many incidents are open, and whether approvals, cold validations, or operator review are currently outstanding.

That orientation is now environment-first in a stricter sense: the command derives active thread and turn context from persisted Environment conversation state, so it remains accurate immediately after environment load without depending on a fresh compatibility-session resync.

`environment/load` now also renders as an environment-first operation in the shell. The result output shows the loaded environment id, compatibility session id, and operator posture summary so a restored environment is legible before the next command is issued.

Provider orientation is also now environment-backed. Use:

- `(provider/show)`
- `(provider/list)`
- `(provider/use "profile")`
- `(provider/configure "profile" :provider "name" :model "name" ...)`
- `(provider/routing :auto)`
- `(provider/routing :manual)`
- `(provider/route)`

These commands let the operator inspect and steer the same provider-profile and routing model that `sbcl-agent-ux` and any other client can consume through the non-shell CLI or service boundary.

The non-shell equivalents are:

- `./bin/sbcl-agent provider show`
- `./bin/sbcl-agent provider route`
- `./bin/sbcl-agent provider preview --prompt "..."`
- `./bin/sbcl-agent provider routing --mode auto|manual`
- `./bin/sbcl-agent provider configure --profile ... --provider ... --model ...`
- `./bin/sbcl-agent provider use --profile ...`

Those commands exist so provider control is not trapped behind shell-only forms when desktop and service clients need the same behavior.

If a turn pauses for approval, `turn/status` tells you why and `turn/resume` continues it after the relevant approval or staged-action execution step is satisfied. A resumed turn may also trigger a provider follow-up run so the turn can finish with a fresh assistant message instead of stopping at raw action execution.

If a governed runtime action fails, the system now records a durable incident linked to the turn, operation, and any bound work-item. Use `(incident/list)` to find recent failures and `(incident/show "incident-id")` to inspect the condition text plus the linked thread, turn, operation, work-item, and workflow context when those links exist. `incident/show` also includes compact recovery and wait guidance, so the operator can see whether a linked turn is resumable, whether the runtime was interrupted, and what next action the bound work-item is waiting on.

`incident/show` now behaves more like a recovery workspace than a plain failure record. In addition to the linked failure graph, it exposes runtime context such as the active package, recent runtime history, checkpoint and observation counts, and a structured recovery plan. When an incident has actionable follow-through, the system also records a recovery-plan artifact so the remediation path becomes durable evidence rather than an implicit suggestion.

`review/mutation` is the mutation-closure surface. It consolidates the turn, mutation operations, artifacts, work-item governance, wait reason, evidence, and incident linkage into one view so the operator can see what changed and what closes the loop next without jumping across multiple commands.

The runtime navigation commands deepen the symbolic side of the environment without introducing editor-centric metaphors. `runtime/find-definition` searches workspace source for defining forms and relates them to the live image, `runtime/callers` finds source-level caller sites, `runtime/methods` exposes generic-function methods in the image, and `runtime/source-image-divergence` makes source-only, runtime-only, and potentially drifted symbols explicit.

Artifact evidence is now less path-dependent. Validation, reconciliation, incident, runtime, and recovery-plan artifacts all contribute to the session and environment evidence summaries, so environment-level inspection is no longer limited to one aggregate artifact count. This makes non-conversational validation and reconciliation work visible in the same governed evidence stream as turn-bound actions.

Provider-facing summaries now follow the same rule. When a provider request is built from an Environment snapshot, the request summaries prefer the Environment-owned runtime, thread, plan, artifact, and policy view instead of quietly re-reading those values from a possibly drifted live session object.

Top-level status commands also surface incident pressure directly:

- `(describe-session)` includes incident totals and open-incident counts alongside operator status.
- `(environment/show)` includes environment-level incident counts and the current operator incident posture.
- `(environment/events :tail 20)` shows recent projected environment events with environment-scoped metadata.

Validation and reconciliation outcomes now also generate conversational artifacts when they are tied to a thread-bound work-item. That means replayed validator results and image-only reconciliation steps show up in the same artifact stream as patches, runtime reloads, and incidents.

## Governed External Runtime Flow

The RGP bridge makes `sbcl-agent` usable as a stateful governed runtime rather than only as a model-backed assistant shell.

Typical flow:

1. RGP binds a request and agent session to an Environment with `./bin/sbcl-agent rgp bind`.
2. RGP inspects governed runtime state with `show`, `export`, `approvals`, or `artifacts`.
3. When a runtime work-item blocks on approval, RGP uses `approve` or `resume`.
4. `sbcl-agent` preserves Environment, thread, turn, operation, artifact, and work-item state locally while RGP reconciles the governance view externally.

This matters because RGP needs sessionful runtime semantics. It is not only asking for a response. It is governing a durable external runtime that can accumulate local execution state, approvals, incidents, and artifacts across turns.

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

If the work is governed mutation rather than a simple approval pause, use `(review/mutation)` before or after the resume step to inspect closure state, evidence, and any remaining cold-validation or operator-review obligations.

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

On load, the runtime now normalizes stale in-flight execution:

- persisted operations that were still `:running` are marked `:interrupted`
- turns that were still `:running` at save time are marked `:interrupted`
- turn recovery summaries expose interrupted-operation counts separately from resumable approval-gated operations

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

### Other supported provider families

The current runtime also supports:

- Anthropic
- Google and Gemini-compatible profiles
- Meta-compatible profiles
- LM Studio and other local-compatible profiles

In practice, those are usually managed through provider profiles rather than only through process-wide environment variables.

Typical Anthropic configuration:

```bash
export TUTOR_CODEX_PROVIDER=anthropic
export TUTOR_CODEX_MODEL=claude-sonnet-4-20250514
export ANTHROPIC_API_KEY=...
./bin/sbcl-agent chat
```

For local and OpenAI-compatible transports, `TUTOR_CODEX_API_BASE` points the runtime at the target endpoint. That includes OpenAI-style gateways, LM Studio, and other local-compatible deployments.

### Provider profiles and routing

The provider layer is now environment-native rather than only process-configured.

You can:

- configure multiple named profiles
- mark one profile active
- let the runtime auto-route across profiles
- force manual routing
- preview a route for a prompt before execution

The router now uses more than prompt text alone. It can factor in:

- prompt shape such as deep review, quick-turn, local-development, or code-execution intent
- governance posture such as incidents, blocked work, or pending validation
- cognition context such as mutation likelihood, validation strategy, and execution strategy
- provider-profile metadata such as latency, review bias, execution bias, and locality

That means provider selection is part of the governed runtime, not only startup configuration.

The provider profile layer is also how the presentation tier should interact with model choice. A UX can expose profile creation, route preview, active-profile switching, and routing policy toggles without embedding shell-specific command strings.

### Retrieval and cognition in the default loop

The current agent path does not rely only on recent transcript plus a generic prompt summary anymore.

Before provider invocation, the runtime can now assemble:

- a retrieval intent
- a retrieval plan
- an environment dossier
- a cognition bundle
- reasoning and planning briefs
- prior-outcome reuse and self-improvement context
- execution and validation strategy

Those structures shape both provider routing and turn execution. They are part of the current behavior, not only future design notes.

## Recommended First Operator Flow

1. Run `./bin/sbcl-agent doctor`.
2. Run `./bin/run-tests`.
3. Run `./bin/run-evals`.
4. Start `./bin/sbcl-agent chat`.
5. Evaluate a simple Lisp form such as `(+ 100 203)`.
6. Inspect provider state with `(provider/show)` or `./bin/sbcl-agent provider show`.
7. Create a thread with `(thread/new :title "first session")`.
8. Run `(say "Summarize the current architecture." :stream t)`.
9. Inspect the result with `(turn/status)` and `(thread/show)`.
10. Grant only the capabilities you actually need before stateful operations.

## Operational Caveats

- A successful warm-image interaction is not the same thing as a durable source-backed fix.
- Governed runtime mutations can now stop in `:awaiting-cold-validation` even after the warm image reports success.
- `why-waiting` and session wait summaries distinguish generic pending validation from colder validation that is still required for durable closure.
- Conversation state, runtime state, and workflow state are related but not interchangeable.
- Use approvals deliberately. The architecture is designed to make mutating operations visible, not implicit.
- Treat image-only outcomes as provisional until they are reconciled back to source truth and workflow evidence.

For the rationale behind these constraints, read [Why sbcl-agent Exists]({{ '/why-sbcl-agent.html' | relative_url }}) and [Architecture and Design]({{ '/architecture.html' | relative_url }}).
