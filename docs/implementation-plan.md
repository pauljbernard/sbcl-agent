# SBCL Agent Implementation Plan

## Objective

Implement a Codex-like CLI for SBCL whose user interface, internal protocol, tool layer, and execution model are entirely Common Lisp.

This plan translates the architecture in `docs/architecture.md` into an incremental build sequence with explicit deliverables, verification criteria, and dependency order.

## Working Definition of Done

The project is considered minimally viable when a user can:

- start the CLI in SBCL
- enter normal Lisp forms and receive evaluated results
- enter agent commands as Lisp forms such as `(ask ...)` and `(tool ...)`
- have the assistant inspect workspace files through Lisp-registered tools
- receive assistant responses as structured Lisp-backed events
- approve or reject assistant-proposed execution and file mutation
- persist and reload session history as readable s-expressions
- run a base test suite that validates runtime startup, command dispatch, and one end-to-end agent workflow

## Delivery Strategy

Build the system in six phases.

1. Stabilize the runtime foundation.
2. Introduce a Lisp-native command shell.
3. Add stateful agent/session infrastructure.
4. Add structured tools and policy-gated execution.
5. Add a real model provider boundary.
6. Close the loop with self-hosting agent workflows.

Each phase should leave the repository in a runnable state with tests.

## Phase 0. Foundation Cleanup

### Goal

Make the current scaffold reflect the new repo root and prepare the source tree for modular growth.

### Tasks

- Align naming so the repo path, system name, and runtime branding are coherent.
- Create missing source directories from the architecture layout.
- Separate CLI entrypoint concerns from provider and REPL concerns.
- Remove accidental references to the old nested `sbcl/` location.
- Add a `docs/implementation-plan.md` reference from `README.md`.

### Deliverables

- corrected `README.md`
- `docs/implementation-plan.md`
- updated source layout skeleton under `src/`

### Exit Criteria

- `./bin/run-tests` still passes
- `./bin/sbcl-agent doctor` still runs
- the repo layout described in `README.md` matches disk state

## Phase 1. Lisp-Native Shell

### Goal

Replace the current line-oriented mock chat loop with a real Lisp-native command shell.

### Scope

The shell must read Lisp forms directly, distinguish agent commands from ordinary evaluation, and print results in a predictable way.

### Tasks

- Add `src/shell.lisp` for the top-level interactive shell.
- Add `src/commands.lisp` for command normalization.
- Introduce a `sbcl-agent-user` package for interactive evaluation.
- Implement a reader loop that supports:
  - complete form reading
  - multiline forms
  - EOF handling
  - graceful runtime errors
- Normalize shell inputs into one of:
  - `:eval`
  - `:ask`
  - `:plan`
  - `:tool`
  - `:patch`
  - `:session`
  - `:help`
- Replace the current string-based `chat` interaction with form-driven dispatch.

### Suggested Interface Surface

```lisp
(ask "Summarize the system.")
(plan "Implement tool registry.")
(tool :fs/read :path "src/main.lisp")
(+ 100 203)
```

### Tests

- shell accepts and evaluates `(+ 100 203)`
- shell dispatches `(help)` without entering agent mode
- shell normalizes `(ask "x")` into an ask command
- malformed forms return a readable error instead of crashing the process

### Exit Criteria

- the CLI can run in pure Lisp mode and agent command mode from the same shell
- no string-only command parsing remains on the critical path

## Phase 2. Session and Event Runtime

### Goal

Introduce persistent internal state so the agent behaves like a continuous Lisp image instead of stateless command execution.

### Tasks

- Add `src/session.lisp` with `agent-session` lifecycle helpers.
- Add `src/events.lisp` with event structures and append logic.
- Track:
  - current cwd
  - current package
  - transcript history
  - plan state
  - tool policy
  - provider selection
  - evaluation history
- Persist event logs as readable s-expressions.
- Add commands:
  - `(session/save)`
  - `(session/load path)`
  - `(session/reset)`
  - `(describe-session)`

### Storage Format

Use plain s-expression persistence first. Avoid binary persistence until the shape stabilizes.

Suggested file model:

- `var/sessions/<session-id>.sexp`
- `var/events/<session-id>.sexp`

### Tests

- session creation returns a valid session object
- saving and loading a session preserves transcript and cwd
- event append order is stable and timestamped
- reset clears ephemeral state without corrupting persisted history

### Exit Criteria

- the shell operates against an explicit session object
- agent interactions are replayable from stored events

## Phase 3. Tool Registry and Workspace Tools

### Goal

Make tools first-class Lisp capabilities instead of ad hoc functions.

### Tasks

- Add `src/tools/registry.lisp`
- Add `src/tools/fs.lisp`
- Add `src/tools/process.lisp`
- Add `src/tools/session.lisp`
- Register core tools:
  - `:fs/read`
  - `:fs/list`
  - `:fs/write`
  - `:fs/patch`
  - `:proc/run`
  - `:session/save`
- Add metadata for each tool:
  - id
  - documentation
  - arg schema
  - policy class
  - implementation function
- Implement `(describe-tool ...)` and `(list-tools)`.

### Design Constraint

Tool invocation must remain native Lisp:

```lisp
(tool :fs/read :path "src/provider.lisp")
```

The registry should normalize that request into an internal command object and dispatch it without stringly typed glue.

### Tests

- reading a file through `:fs/read` returns contents
- listing tools returns registered ids and docs
- invalid tool args fail with readable diagnostics
- `:proc/run` captures stdout, stderr, and exit code

### Exit Criteria

- the shell can invoke tools directly
- the future agent runtime can request tools through the same registry

## Phase 4. Policy-Gated Evaluation and Mutation

### Goal

Support assistant-generated forms and file mutations without collapsing the boundary between suggestion and execution.

### Tasks

- Add `src/eval/runtime.lisp`
- Add `src/eval/validator.lisp`
- Add `src/eval/packages.lisp`
- Add `src/patch/protocol.lisp`
- Add `src/patch/apply.lisp`
- Separate user evaluation from assistant-generated evaluation.
- Add a trust model for operations:
  - `:safe-read`
  - `:workspace-write`
  - `:process-run`
  - `:network`
  - `:eval-generated`
  - `:git-push`
- Implement approval prompts for restricted operations.
- Represent patches as Lisp data and apply them through the tool layer.

### Required Runtime Behavior

The system must support flows like:

1. assistant proposes a patch object
2. runtime renders it for inspection
3. user approves
4. patch applies through workspace tools
5. result is logged as an event

### Tests

- validator rejects prohibited assistant-generated forms
- assistant-generated evaluation requires approval when policy demands it
- patch application updates files correctly
- rejected operations do not mutate state

### Exit Criteria

- assistant actions are structured, inspectable, and policy-bound
- file mutation no longer depends on free-form raw shell editing

## Phase 5. Provider Protocol and Real Model Adapter

### Goal

Replace the mock-only provider with a real model boundary that speaks Lisp-friendly request and response structures.

### Tasks

- Split provider code into:
  - `src/provider/protocol.lisp`
  - `src/provider/mock.lisp`
  - `src/provider/openai-compatible.lisp`
- Define request and response structures.
- Implement serialization from session state to provider messages.
- Add support for a response envelope containing:
  - assistant message text
  - structured actions
  - optional plan updates
  - optional patch proposals
- Add streaming support if feasible, but only after non-streaming is stable.

### Design Rule

Provider code may communicate with an external API, but the rest of the system should only see Lisp structures.

### Tests

- mock provider still passes deterministic tests
- provider protocol encodes command and transcript state correctly
- response decoder handles text-only and action-bearing outputs
- configuration failure paths are clear and non-destructive

### Exit Criteria

- the system can run with `mock` and one real provider backend
- provider-specific logic is isolated from shell, tool, and eval code

## Phase 6. Agent Loop and Self-Hosting Workflow

### Goal

Close the loop so the assistant can inspect, plan, modify, test, and explain within the same CL runtime.

### Tasks

- Add agent orchestration around the provider boundary.
- Implement ask/plan/run-task execution flows.
- Let the agent emit structured action batches such as:
  - tool reads
  - patch proposals
  - process runs
  - final messages
- Add plan state transitions and visible progress events.
- Add session-aware helpers for common development tasks.

### Example Target Flow

```lisp
(ask "Add an fs/read tool test and run the suite.")
```

Expected runtime behavior:

1. session context is serialized
2. provider returns a Lisp action envelope
3. runtime executes allowed tool reads
4. assistant proposes patch data
5. runtime requests approval for mutation
6. patch applies
7. runtime executes tests after approval
8. final answer is printed as structured output plus readable summary

### Tests

- one end-to-end ask workflow using mock provider fixtures
- tool reads followed by patch proposal and user approval
- process run event captured in transcript
- final answer emitted after action completion

### Exit Criteria

- the system supports a real Codex-like development loop inside SBCL
- the agent runtime can operate entirely through CL forms and CL data

## Phase 7. Hardening and Developer Ergonomics

### Goal

Improve reliability and make the environment practical for daily use.

### Tasks

- add better pretty-printing for events and responses
- add configurable session directories
- add shell history support
- add command aliases or macros for common workflows
- add structured error objects rather than untyped condition text where appropriate
- add test coverage for edge cases around malformed input and interrupted execution
- add optional git helpers through the tool layer

### Tests

- condition handling remains readable under failure
- shell can resume after a failed command
- session persistence survives restart

### Exit Criteria

- the system is stable enough to use as its own implementation assistant

## Source Tree Target

By the end of Phase 6, the source tree should approximately look like this:

```text
src/
├── package.lisp
├── main.lisp
├── shell.lisp
├── commands.lisp
├── session.lisp
├── events.lisp
├── provider/
│   ├── protocol.lisp
│   ├── mock.lisp
│   └── openai-compatible.lisp
├── tools/
│   ├── registry.lisp
│   ├── fs.lisp
│   ├── process.lisp
│   ├── git.lisp
│   └── session.lisp
├── eval/
│   ├── runtime.lisp
│   ├── validator.lisp
│   └── packages.lisp
├── patch/
│   ├── protocol.lisp
│   └── apply.lisp
└── ui/
    ├── printer.lisp
    └── repl.lisp
```

## Testing Strategy

The test suite should grow in layers.

### Layer 1. Environment Tests

Validate that SBCL starts, systems load, and base runtime assertions pass.

### Layer 2. Unit Tests

Validate command normalization, session state, event logging, tool dispatch, and validators.

### Layer 3. Integration Tests

Validate shell dispatch, provider decoding, file operations, and process execution.

### Layer 4. Scenario Tests

Validate an end-to-end agent loop with deterministic mock provider responses.

## Dependency Order

Build in this order to avoid repainting the architecture later:

1. shell and command model
2. session and event runtime
3. tool registry
4. evaluation and patch protocol
5. provider protocol
6. full agent loop
7. hardening and ergonomics

This order matters because the provider protocol is downstream of the command model and session model, not upstream.

## Risks and Mitigations

### Risk: overusing raw `eval`

Mitigation:
- centralize evaluation in `src/eval/runtime.lisp`
- distinguish user eval from assistant eval from the beginning

### Risk: opaque provider output

Mitigation:
- require normalized response envelopes
- keep provider parsing isolated in the provider layer

### Risk: state corruption in one live image

Mitigation:
- separate packages for user, system, tools, and generated code
- log every mutation and evaluation event

### Risk: architecture drift into shell scripting

Mitigation:
- keep tool invocation and command dispatch Lisp-native
- avoid string-only protocols except at the provider edge

## Immediate Next Actions

1. Implement Phase 0 by updating the docs index in `README.md` to include this plan.
2. Start Phase 1 by introducing `src/shell.lisp` and `src/commands.lisp`.
3. Add tests for direct Lisp form evaluation and ask-command normalization.
4. Refactor the current `repl.lisp` so it becomes a compatibility layer or is replaced cleanly.

## Summary

This plan intentionally builds the agent from the inside out:

- first establish a Lisp-native shell
- then add persistent session state
- then formalize tools and policy
- then add a provider boundary
- then complete the full agent loop

That sequence preserves the project’s central premise: Common Lisp is not just the implementation language, it is the interface, protocol, execution substrate, and self-hosting medium.
