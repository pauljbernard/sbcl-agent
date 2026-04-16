# tutor-codex

`tutor-codex` is a greenfield Common Lisp project targeting SBCL. The aim is to build the equivalent of a Codex-style CLI in idiomatic Common Lisp, with a strong bias toward small composable modules instead of a monolithic script.

## Current scope

This repository currently provides:

- an ASDF system for SBCL
- CL-native executable entrypoints in `bin/`
- a CLI entrypoint with `chat`, `exec`, `doctor`, and `help`
- a runtime config loader from environment variables
- a Lisp shell that accepts both ordinary forms and agent commands
- a provider abstraction with a working mock provider and an OpenAI-compatible adapter
- session state, event logging, and s-expression persistence
- a first-class tool registry for workspace reads and process execution
- policy-gated approval flows for process execution and patch application
- staged assistant actions that require explicit `(execute-actions)` execution
- an architecture document for the CL-native "turtles all the way down" design

It does not yet provide:

- streaming responses
- sandbox isolation beyond in-process policy gating
- richer agent orchestration such as task queues and background workers
- native git workflow tools

## Layout

```text
sbcl-agent/
├── tutor-codex.asd
├── README.md
├── docs/
│   ├── architecture.md
│   └── implementation-plan.md
├── bin/
│   ├── run-tests
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
│   ├── session.lisp
│   ├── tools-registry.lisp
│   ├── tools-fs.lisp
│   ├── tools-process.lisp
│   ├── patch.lisp
│   ├── shell.lisp
│   ├── repl.lisp
│   └── main.lisp
└── tests/
    ├── package.lisp
    └── smoke.lisp
```

## Run

From this directory:

```bash
./bin/tutor-codex doctor
```

Examples:

```bash
./bin/tutor-codex doctor
./bin/tutor-codex exec pwd
./bin/tutor-codex chat
./bin/run-tests
```

Inside `chat`, the primary interface is Common Lisp:

```lisp
(+ 100 203)
(ask "please read src/main.lisp")
(execute-actions)
(tool :fs/read :path "src/main.lisp")
(describe-session)
```

## Test

Run the base test suite with:

```bash
./bin/run-tests
```

The first test is a runtime smoke test. It starts SBCL, loads the `tutor-codex` system, and validates a basic assertion so the suite can immediately catch a broken Lisp environment before higher-level behavior tests are added.

## Architecture

The architectural target for this project is documented in [docs/architecture.md](docs/architecture.md). The core idea is that the assistant interface, protocol, tools, and execution model are all Common Lisp, with SBCL acting as the live runtime image. The execution roadmap is documented in [docs/implementation-plan.md](docs/implementation-plan.md). The repo entrypoints in `bin/` are also executable Common Lisp scripts so the runnable surface stays CL-native.

## Environment

- `TUTOR_CODEX_PROVIDER`: provider backend, defaults to `mock`
- `TUTOR_CODEX_MODEL`: logical model name, defaults to `gpt-5`
- `TUTOR_CODEX_API_BASE`: reserved for future HTTP provider integration
- `OPENAI_API_KEY`: reserved for future OpenAI-compatible provider integration

## Next build steps

1. Add streaming support to the OpenAI-compatible provider path.
2. Expand the tool registry with git, session, and documentation tools.
3. Replace ad hoc approval state with a more formal capability policy model.
4. Teach the provider boundary to emit richer CL-native plans and patch objects.
