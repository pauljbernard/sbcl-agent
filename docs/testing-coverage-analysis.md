---
layout: default
title: Testing Coverage Analysis
hero_title: Testing Coverage Analysis
hero_text: Current assessment of unit coverage, functional coverage, user-story coverage, and performance coverage in sbcl-agent.
eyebrow: Quality
permalink: /testing-coverage-analysis.html
description: Measured testing and coverage assessment for sbcl-agent.
---

## Scope

This document summarizes the current quality posture of the repository across four dimensions:

- unit-style coverage
- functional workflow coverage
- user-story coverage against the documented objectives
- performance test coverage

The measurements in this document come from the current local test and coverage tooling:

- `./bin/run-tests`
- `./bin/run-coverage`
- `./bin/run-performance`

The timing notes below come from a current local baseline run of:

```bash
env time -p ./bin/run-tests
```

Observed wall-clock baseline on this machine:

- `real 7.34`
- `user 3.62`
- `sys 3.25`

## Current Test Architecture

The repository still relies heavily on `tests/smoke.lisp` as the largest single test file, but the test program is no longer just one undifferentiated smoke harness.

The current test program now includes:

- a categorized catalog in `tests/test-runner.lisp`
- focused category execution through `./bin/run-test-category`
- named harnesses through `./bin/run-test-harness`
- JSON and Markdown result reporting
- evidence-index generation for the current test program
- the broader suite in `tests/smoke.lisp`, `tests/service-contracts.lisp`, `tests/retrieval.lisp`, `tests/evals.lisp`, and support files

The smoke suite still contains a large mixed body of tests covering:

- helper and parser tests
- command normalization tests
- provider contract tests
- shell command tests
- workflow and work-item tests
- persistence and recovery tests
- incident and runtime governance tests
- tool integration tests

This gives the project broad behavioral coverage. The remaining limitation is not a total lack of structure, but that the deepest test inventory still lives in large Lisp files rather than in a fully decomposed directory-per-layer layout.

## Measured Coverage

The current `sb-cover` run reports:

- overall expression coverage: `14495 / 15958` = `90.8%`
- overall branch coverage: `688 / 866` = `79.4%`

That is a strong overall result for a workflow-heavy Common Lisp codebase, but it is not uniformly strong across all files.

### Strongly Covered Areas

The best-covered modules are the ones that now carry the main conversation, runtime, and workflow behavior:

- `src/workflow.lisp`: `99.7%` expression, `87.5%` branch
- `src/provider-protocol.lisp`: `96.8%` expression, `84.6%` branch
- `src/commands.lisp`: `96.2%` expression, `97.4%` branch
- `src/environment.lisp`: `94.9%` expression, `62.5%` branch
- `src/provider-openai.lisp`: `95.1%` expression, `69.0%` branch
- `src/session.lisp`: `95.1%` expression, `68.0%` branch
- `src/conversation.lisp`: `94.2%` expression, `81.0%` branch
- `src/turn-orchestrator.lisp`: `94.0%` expression, `93.8%` branch
- `src/work-items.lisp`: `89.9%` expression, `82.9%` branch
- `src/tools-runtime.lisp`: `91.4%` expression, `80.8%` branch

These are the right places to be strong. They represent the live architectural center of gravity.

### Weaker Areas

The lower-coverage files fall into two different categories.

Category one: thin wrappers or registration modules that are exercised mostly indirectly:

- `src/tools-process.lisp`: `27.3%` expression
- `src/tools-git.lisp`: `29.4%` expression
- `src/package.lisp`: `0.0%` expression
- `src/repl.lisp`: `75.0%` expression

Category two: real behavior surfaces that still deserve more direct test attention:

- `src/policy.lisp`: `45.0%` expression
- `src/tools-session.lisp`: `72.9%` expression, `83.3%` branch
- `src/shell.lisp`: `81.1%` expression, `65.8%` branch
- `src/tools-docs.lisp`: `84.8%` expression
- `src/json.lisp`: `87.4%` expression, `86.8%` branch

The key distinction is this: low coverage in `tools-git.lisp` is not as alarming as low coverage in `shell.lisp` or `policy.lisp`. The former is mostly a registration and isolation boundary; the latter two represent real decision-making and operator-facing behavior.

### Branch Coverage Weak Spots

The main branch-coverage gaps are:

- `src/environment-store.lisp`: `50.0%`
- `src/patch.lisp`: `50.0%`
- `src/tasks.lisp`: `50.0%`
- `src/config.lisp`: `60.0%`
- `src/incidents.lisp`: `61.1%`
- `src/environment.lisp`: `62.5%`
- `src/shell.lisp`: `65.8%`
- `src/session.lisp`: `68.0%`
- `src/provider-openai.lisp`: `69.0%`

Those numbers do not mean those modules are weak overall, but they do indicate that several alternate or failure paths are still exercised less thoroughly than the mainline logic.

## Unit Coverage Assessment

### Current Strengths

The suite does contain a substantial amount of unit-style coverage already. In practice, these tests concentrate on:

- parsers and serializers
- command normalization
- provider request construction
- tool registry behavior
- session summary helpers
- validation and reconciliation helper logic
- recovery summaries and wait-reason calculation

That is why files like `commands.lisp`, `provider-protocol.lisp`, and many helper-heavy portions of `conversation.lisp`, `session.lisp`, and `workflow.lisp` score well.

### Current Weaknesses

The unit layer is still under-structured relative to the newer program wrapper.

- There is no fully separate unit-test file tree.
- Many unit-style tests are still mixed into the larger smoke suite rather than fully isolated.
- Thin boundary files are covered mostly as a side effect of functional flows.
- Some policy and shell branches are only covered indirectly, which makes failures harder to localize.

### Assessment

Unit coverage quality is good in aggregate, and the categorized runner/reporting layer makes it easier to reason about than before. The remaining issue is that the underlying test inventory is still not decomposed as cleanly as the reporting layer now is.

## Functional Coverage Assessment

Functional coverage is the strongest part of the current quality posture.

The suite directly exercises:

- `ask` and `say`
- streaming provider behavior
- staged assistant actions
- approval-gated patch, git, and runtime operations
- turn resume and provider follow-up
- work-item creation, checkpointing, validation, and quarantine
- incident creation, inspection, and recovery linkage
- session and environment persistence
- runtime eval and runtime reload governance
- shell command rendering and command dispatch
- artifact persistence and path safety

This is not superficial “can it start” coverage. It is real behavior coverage across the conversation-runtime-workflow boundary.

### Assessment

Functional coverage of the implemented architecture is strong and is currently the best-tested dimension of the system.

## User-Story Coverage Assessment

The product objectives in [Objectives]({{ '/objectives.html' | relative_url }}) imply a set of operator stories. The table below maps those stories to current coverage.

| User story | Current coverage | Assessment |
| --- | --- | --- |
| Work directly in a REPL or shell without losing Lisp-native control | `repl-alias-test`, `shell-eval-test`, command normalization tests | Strong |
| Work in durable conversation turns instead of one-shot prompts | `ask-dispatch-test`, `say-dispatch-test`, thread and turn shell tests, turn status tests | Strong |
| Approve or deny governed mutations instead of letting chat bypass policy | patch approval, git approval, runtime approval, work-item approval tests | Strong |
| Resume interrupted or approval-gated work with durable evidence | `turn-resume-*` tests, interruption recovery tests, wait-summary tests | Strong |
| Inspect incidents and understand what failed | incident recording tests, `incident/show` linkage tests, summary tests | Strong |
| Keep artifacts and workflow evidence visible through mutating work | artifact persistence, runtime reload artifact tests, validation and reconciliation artifact tests | Moderate to strong |
| Reconcile image-only work back to source truth | reconciliation shell tests and image-only outcome tests | Strong |
| Persist sessions and environments across restarts | session save/load, environment persistence, tail rebuild, interruption normalization | Strong |
| Use agentic or resident actor workflows | not yet implemented as a first-class actor system | Not applicable yet |
| Treat the environment as a computational habitat rather than only a shell | indirectly covered through environment, thread, work-item, and artifact tests | Moderate |

### Assessment

Coverage is strongest for the stories that are already implemented and operator-visible today. Coverage is weaker for stories that exist mainly in the roadmap rather than in live code, especially the resident-agent model and the full environment-as-habitat semantics.

## Performance Coverage Assessment

This is the weakest part of the current quality posture.

### What Exists Today

- a manually runnable end-to-end baseline via `env time -p ./bin/run-tests`
- a dedicated performance runner via `./bin/run-performance`
- optional environment-variable budgets for the first benchmark set:
  - `SBCL_AGENT_PERF_MAX_SAY_MS`
  - `SBCL_AGENT_PERF_MAX_THREAD_DETAIL_MS`
  - `SBCL_AGENT_PERF_MAX_TURN_DETAIL_MS`
- a persisted benchmark report at `tmp/performance/latest.sexp`
- larger benchmark workloads for detail rendering and persistence scaling
- CI enforcement via `.github/workflows/ci.yml`
- a smoke suite whose total runtime is currently acceptable on this machine

### What Does Not Exist Yet

- no regression thresholds in CI for suite runtime
- no throughput benchmarks for streaming turns
- no concurrency benchmarks for worker pools or multi-thread workloads

### Assessment

Performance coverage is no longer purely informal. The repository now has a dedicated benchmark runner, larger benchmark workloads, persisted reports, and CI-enforced latency budgets for the first benchmark set. It still lacks concurrency coverage, streaming throughput coverage, and richer workload realism.

## Reliability Notes

During this assessment, the test harness exposed two stability issues:

1. temp test repositories and temp config directories were not safe under concurrent multi-process runs because they were being named from coarse timestamps plus default RNG state
2. some tests remain effectively serial because the suite mutates process-level state and shared globals

The temp-directory collision issue has been hardened in the current test file by switching several helpers to `mktemp`-backed directory creation. The broader lesson remains:

- the current suite is reliable in serial execution
- the current suite is still best treated as serial, even though orchestration and temp-path stability are materially better than before

## Overall Quality Judgment

Current quality is high for correctness of implemented behavior and moderate for test architecture maturity.

The main positive conclusions are:

- implemented core workflows are well covered
- the most important architectural modules have strong expression coverage
- real operator stories around conversation, runtime governance, persistence, incidents, and workflow evidence are tested directly

The main gaps are:

- shell and policy still need stronger direct branch coverage
- the reporting and harness layer is clearer than before, but unit and functional tests are still not fully separated in file structure
- wrapper modules look weaker in coverage reports because they are tested mostly indirectly
- performance coverage still needs richer workload breadth
- the suite is still best treated as serial, not parallel

## Recommended Next Steps

### Priority 1

Continue decomposing the current smoke-heavy inventory into explicit layers:

- `tests/unit/*.lisp`
- `tests/functional/*.lisp`
- `tests/recovery/*.lisp`
- `tests/performance/*.lisp`

### Priority 2

Add explicit quality gates:

- expression coverage floor, for example `>= 90%`
- branch coverage floor, for example `>= 80%`
- file-specific floors for `shell.lisp`, `policy.lisp`, `session.lisp`, and `tools-runtime.lisp`

### Priority 3

Add a real performance harness with machine-readable output for:

- `say` turn latency with mock provider
- `turn/detail` and `thread/detail` on medium and large sessions
- session save/load timing
- environment save/load timing
- streaming-turn throughput

### Priority 4

Add a maintained user-story traceability matrix that links:

- documented objective
- user story
- implementation surface
- test names

That would make coverage claims auditable rather than mostly inferred from test naming.
