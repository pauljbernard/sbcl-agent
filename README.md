# tutor-codex

`tutor-codex` is a greenfield Common Lisp project targeting SBCL. The aim is to build the equivalent of a Codex-style CLI in idiomatic Common Lisp, with a strong bias toward small composable modules instead of a monolithic script.

## Current scope

This repository currently provides:

- an ASDF system for SBCL
- a CLI entrypoint with `chat`, `exec`, `doctor`, and `help`
- a runtime config loader from environment variables
- a provider abstraction with a working mock provider
- a simple REPL loop for iterative prompt/response flows

It does not yet provide:

- real model API integration
- streaming responses
- session persistence
- tool approval flows
- patch application, sandboxing, or agent orchestration

## Layout

```text
sbcl/
├── tutor-codex.asd
├── README.md
├── tests/
│   ├── package.lisp
│   └── smoke.lisp
└── src/
    ├── package.lisp
    ├── config.lisp
    ├── provider.lisp
    ├── repl.lisp
    └── main.lisp
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

## Test

Run the base test suite with:

```bash
./bin/run-tests
```

The first test is a runtime smoke test. It starts SBCL, loads the `tutor-codex` system, and validates a basic assertion so the suite can immediately catch a broken Lisp environment before higher-level behavior tests are added.

## Environment

- `TUTOR_CODEX_PROVIDER`: provider backend, defaults to `mock`
- `TUTOR_CODEX_MODEL`: logical model name, defaults to `gpt-5`
- `TUTOR_CODEX_API_BASE`: reserved for future HTTP provider integration
- `OPENAI_API_KEY`: reserved for future OpenAI-compatible provider integration

## Next build steps

1. Add a real HTTP provider adapter with streaming support.
2. Introduce conversation/session state and transcript persistence.
3. Add structured tool dispatch with allow/deny policy hooks.
4. Split the CLI into command modules once the surface area grows.
