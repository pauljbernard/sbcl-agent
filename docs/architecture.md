# SBCL Agent Architecture

## Goal

Build a Codex-like CLI whose public interface, internal protocol, tool model, and execution substrate are all Common Lisp. The user interacts with the system by entering Common Lisp forms. The assistant responds with Common Lisp forms, plans, explanations, and executable artifacts that can run in the same SBCL image.

This is a self-contained Lisp environment:

- the CLI is Common Lisp
- the command protocol is Common Lisp
- tool calls are Common Lisp
- plans are Common Lisp data
- patches are Common Lisp data
- execution happens in the same Common Lisp runtime

The intended mental model is "turtles all the way down": the assistant is a Lisp-native development environment, not a text shell with Lisp bolted onto it.

## Design Principles

1. The primary interface is data, not string parsing.
2. Every assistant action should be representable as an s-expression.
3. The model should generate structured Lisp forms whenever possible.
4. Evaluation must be explicit, inspectable, and constrained by policy.
5. The runtime image is the platform, so session state is first-class.
6. Tooling should feel like extending a Lisp environment, not RPC glue.

## Core User Experience

The user starts `sbcl-agent` and remains inside an interactive SBCL-backed agent shell.

Examples of the desired interaction style:

```lisp
(ask "Summarize the current system architecture.")

(plan "Add OpenAI-compatible chat provider support.")

(run-task
  :goal "Add a smoke test for config loading"
  :approve t)

(tool :fs/read :path "src/main.lisp")

(eval-form
  '(defun hello () "hi"))
```

The CLI should also support raw Lisp input:

```lisp
(+ 100 203)
```

The environment distinguishes between:

- plain Lisp evaluation
- agent requests
- tool invocations
- code mutation operations
- session and memory operations

These should all still look like ordinary Lisp forms from the user perspective.

## Top-Level Architecture

```text
┌────────────────────────────────────────────────────────────┐
│                        User / REPL                         │
│  Reads CL forms, prints CL values, explanations, results  │
└────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────┐
│                    Command Dispatcher                      │
│  Classifies forms: eval, ask, plan, tool, patch, session  │
└────────────────────────────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
┌────────────────┐ ┌────────────────┐ ┌─────────────────────┐
│ Agent Runtime  │ │ Tool Runtime   │ │ Lisp Eval Runtime   │
│ prompt/session │ │ registry/policy│ │ compile/load/eval   │
└────────────────┘ └────────────────┘ └─────────────────────┘
          │                │                │
          └────────────────┼────────────────┘
                           ▼
┌────────────────────────────────────────────────────────────┐
│                    State + Event Log                       │
│ transcript, plans, approvals, patches, forms, outputs     │
└────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────┐
│              Model Adapter / Provider Boundary             │
│ serializes context into CL-friendly messages and decodes   │
│ model outputs into forms, actions, and annotations         │
└────────────────────────────────────────────────────────────┘
```

## Major Subsystems

### 1. CLI Shell

The shell is an SBCL-native REPL application, not a subprocess wrapper around another tool.

Responsibilities:

- read forms from standard input
- maintain prompt state
- pretty-print values and agent events
- allow multiline forms and history
- distinguish evaluator mode from agent mode

Suggested module:

```text
src/shell.lisp
```

Primary abstractions:

- `shell`
- `read-command`
- `dispatch-command`
- `print-event`

### 2. Command Model

Every user action should map to a Lisp command object or tagged form.

Two complementary approaches work well:

1. Native forms with conventional operator names:

```lisp
(ask "Implement a provider.")
(tool :fs/read :path "src/provider.lisp")
```

2. Internal normalized command records:

```lisp
(:command :ask :prompt "Implement a provider.")
(:command :tool :tool :fs/read :path "src/provider.lisp")
```

Recommendation:

- let the user write natural Lisp forms
- normalize them internally into command structures

This keeps the surface idiomatic while simplifying dispatch and logging.

### 3. Agent Runtime

The agent runtime owns the Codex-like behavior.

Responsibilities:

- maintain conversation state
- build model context from transcript and working state
- request structured completions from the model
- decode model output into Lisp actions
- manage approval checkpoints
- produce final answers, patches, tool requests, and plans

Suggested data model:

```lisp
(defstruct agent-session
  id
  cwd
  package
  transcript
  plan
  tool-policy
  model
  provider
  state)
```

The session should live in memory during a run and be serializable to disk.

### 4. Provider Boundary

The provider layer is the only part that knows how to talk to an external model.

Responsibilities:

- convert session context into provider request payloads
- define response schemas
- stream tokens or events
- decode assistant output back into Lisp structures

Critical design point:

The provider should not return opaque text only. It should aim to return a mixed structure:

```lisp
(:assistant-response
  :message "I will inspect the project first."
  :actions
  ((:tool :fs/read :path "src/main.lisp")
   (:tool :fs/read :path "src/provider.lisp")))
```

When the model cannot reliably emit structured objects directly, the provider can request a Lisp-serializable tagged block and parse it into internal action objects.

### 5. Tool Runtime

Tools are Lisp-callable capabilities registered in a central registry.

Examples:

- `:fs/read`
- `:fs/write`
- `:fs/patch`
- `:proc/run`
- `:git/status`
- `:git/commit`
- `:session/save`
- `:docs/search`

Each tool should have:

- a symbolic id
- an argument schema
- an implementation function
- a policy classification
- a result encoder

Suggested tool definition shape:

```lisp
(defstruct tool-definition
  id
  documentation
  arglist
  policy
  function)
```

Tools are invoked by the agent runtime, but tool implementations remain plain Common Lisp functions.

### 6. Evaluation Runtime

This project needs two forms of evaluation:

1. direct user evaluation
2. assistant-generated evaluation

They must not be treated as equivalent.

#### Direct User Evaluation

If the user types:

```lisp
(+ 100 203)
```

the form may be evaluated directly in the active package and returned normally.

#### Assistant-Generated Evaluation

If the assistant proposes code, evaluation should be explicit and policy-governed.

Recommended flow:

1. assistant emits a form
2. runtime validates the form shape
3. runtime asks for approval if policy requires it
4. runtime evaluates or compiles it in a controlled package
5. runtime records the result in the event log

This avoids hidden execution while preserving the Lisp-native experience.

### 7. Patch and Mutation Engine

A Codex-like tool must modify files, not only evaluate ephemeral forms.

Represent file edits as Lisp data:

```lisp
(:patch
  (:update "src/main.lisp"
   ((:replace "(defun old ...)" "(defun new ...)")))
  (:add "src/provider/openai.lisp"
   "(in-package #:sbcl-agent) ..."))
```

Recommended approach:

- keep patch intent as structured Lisp
- apply filesystem writes through the tool runtime
- optionally render unified diff for human review

This allows the model to think in terms of AST-ish mutation while still interoperating with file-based workflows.

### 8. Transcript and Event Log

A self-hosted Lisp agent should treat its internal history as data.

Persist:

- user commands
- normalized command objects
- assistant messages
- tool calls and results
- approvals
- patches
- evaluation results
- errors

Suggested representation:

```lisp
(defstruct event
  timestamp
  kind
  payload)
```

Persist these as readable s-expressions on disk so the system can reload prior context without custom binary formats.

### 9. Memory and Workspace Model

The agent should be aware of:

- current working directory
- current package
- loaded ASDF systems
- open files
- active plan
- session memory

This is where the Lisp-native design is stronger than a shell clone. Because the runtime is an image, the system can expose live environment state directly:

```lisp
(current-package)
(loaded-systems)
(session-plan)
(workspace-files)
```

## Interface Design

## User-Facing Special Forms

The CLI should provide a small standard vocabulary.

### Conversation

```lisp
(ask "Explain the current design.")
(chat "Refactor the provider layer.")
(plan "Add structured tool dispatch.")
```

### Tooling

```lisp
(tool :fs/read :path "src/main.lisp")
(tool :proc/run :argv '("sbcl" "--version"))
(tool :git/status)
```

### Evaluation

```lisp
(eval-form '(+ 1 2))
(compile-form '(defun x () 42))
```

### Mutation

```lisp
(patch
  '((:update "README.md"
      ((:append "New architecture notes")))))
```

### Session

```lisp
(session/save)
(session/load "last-session.sexp")
(session/reset)
```

### Introspection

```lisp
(help)
(describe-tool :fs/read)
(describe-session)
```

These are interface forms, not necessarily raw CL special operators. They can be ordinary functions or macros dispatched by the shell.

## Execution Semantics

The runtime must know what namespace code runs in.

Recommendation:

- user commands execute in `#:sbcl-agent-user`
- system internals live in `#:sbcl-agent`
- generated code can be staged in `#:sbcl-agent.generated`
- tool implementations live in `#:sbcl-agent.tools`

This package separation matters. It prevents accidental pollution of the core runtime and allows generated artifacts to be inspected, reloaded, or discarded.

## Safety Model

Because the assistant can emit executable Lisp, policy must be explicit.

### Trust Levels

Suggested execution classes:

- `:safe-read`
- `:workspace-write`
- `:process-run`
- `:network`
- `:eval-generated`
- `:git-push`

Every tool and assistant action should declare one of these classes.

### Approval Policy

Recommended defaults:

- direct user eval: allowed
- file reads: allowed
- local workspace writes: approval optional
- subprocesses: approval required
- network access: approval required
- assistant-generated eval: approval required

### Form Validation

Before evaluating assistant-generated forms:

- reject reader-eval tricks
- disallow package mutation by default
- disallow `sb-ext:*posix-argv*` mutation and global image mutation unless approved
- validate target package
- validate referenced functions if in restricted mode

Do not rely on string filters. Parse forms and inspect them as Lisp objects.

## Why CL-First Matters

The main architectural advantage of this design is that the model can emit the same language that the system understands natively.

That produces a tighter loop:

1. user asks in Lisp
2. runtime normalizes request into Lisp data
3. provider asks model for Lisp-native actions
4. assistant emits Lisp data or Lisp code
5. runtime validates and executes Lisp in the same image
6. result comes back as Lisp values

This removes impedance mismatch between:

- command protocol and implementation language
- tool schema and execution language
- generated code and host runtime

## Recommended Module Layout

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

## Example End-to-End Flow

User input:

```lisp
(ask "Add a doctor command that shows package and session information.")
```

Internal normalized command:

```lisp
(:command :ask
  :prompt "Add a doctor command that shows package and session information.")
```

Provider response:

```lisp
(:assistant-response
  :message "I will inspect the current command and config modules first."
  :actions
  ((:tool :fs/read :path "src/main.lisp")
   (:tool :fs/read :path "src/config.lisp")))
```

Later assistant patch proposal:

```lisp
(:assistant-response
  :message "I have prepared a patch."
  :actions
  ((:patch
     (:update "src/main.lisp"
      ((:replace "..." "..."))))
   (:tool :proc/run :argv '("./bin/run-tests"))))
```

At each step, the runtime can render human-readable text while still treating the interaction as executable Lisp data.

## Implementation Phases

### Phase 1. Lisp-Native Shell

- multiline reader
- command normalization
- plain evaluation mode
- mock provider

### Phase 2. Structured Agent Runtime

- session objects
- event log
- command/action protocol
- tool registry

### Phase 3. Controlled Execution

- generated-form validator
- approval model
- subprocess and filesystem tools
- patch engine

### Phase 4. Real Provider

- OpenAI-compatible chat provider
- response decoding
- streaming events
- retry and error handling

### Phase 5. Self-Hosting Workflow

- generated Lisp patches
- assistant-authored test updates
- session persistence
- reusable command macros and agent libraries

## Non-Goals for the First Iteration

- full editor integration
- distributed agents
- graphical UI
- image snapshot portability across Lisp implementations
- arbitrary sandbox security guarantees inside one SBCL image

SBCL is the target runtime, so the first design should lean into SBCL strengths rather than prematurely abstracting for every Common Lisp implementation.

## Summary

The system should be designed as a Lisp machine for agentic development:

- the interface is Lisp
- the protocol is Lisp
- the tool layer is Lisp
- the memory model is Lisp
- the generated artifacts are Lisp
- the execution environment is Lisp

That is the correct architecture if the goal is not merely "a CLI written in Lisp" but "a Codex-like assistant whose entire operational model is native Common Lisp."
