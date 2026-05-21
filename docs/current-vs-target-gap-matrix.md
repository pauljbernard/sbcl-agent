# IntentOS Current-vs-Target Gap Matrix

> Historical framing note: this page is retained to show how the old IntentOS gap program was measured and closed. The current implemented system should be understood primarily through the actor-runtime, concurrency/execution-core, governance, and environment-runtime documents rather than through this earlier kernel-centric gap vocabulary.

## Status

This matrix is an objective assessment of the current `sbcl-agent` / `sbcl-agent-ux` codebase against the accepted IntentOS target architecture.

Current conformance estimate:

- `100%` against the accepted target-state architecture

That means the earlier gap program is now complete at the architectural-contract level. What remains after this point is enhancement work, hardening, and alternative backend evolution rather than an unresolved current-vs-target mismatch.

## Gap 1: `invoke` Universalization

Target doctrine:

- all execution begins with `invoke`
- policy cannot be bypassed

Current evidence:

- governed shell, CLI, platform, workflow, task, worker, provider, RGP, assistant-action, session, and environment mutation paths now route through `command-kernel-invoke-service`
- execution-handle registration and governance preflight are now present across the interactive execution surface

Current impact:

- closed

Resolution:

- `invoke` is now the effective universal operator execution boundary for the interactive system
- remaining bootstrap helpers are implementation detail, not operator-visible bypasses

Priority:

- `closed`

## Gap 2: Compatibility Kernel

Target doctrine:

- Linux applications are governed executions
- compatibility is a first-class kernel subsystem

Current evidence:

- `linux.*` capabilities are implemented as governed compatibility apps
- compatibility app manifests can come from built-ins or active `.aop` packages
- lifecycle, relaunch, registry, app query, execution query, and display-surface projection now exist
- display-bearing Linux apps are now visible in compatibility, workspace, and desktop shell models

Current impact:

- closed

Resolution:

- Linux apps are now governed executions with manifest policy, resource scope, lifecycle, relaunch, and shell-visible display surfaces
- the current backend remains SBCL-managed host-process orchestration, but that is now an implementation of the compatibility execution layer rather than a missing subsystem

Priority:

- `closed`

## Gap 3: UX Kernel

Target doctrine:

- every visible element must be inspectable
- the shell is a workspace of governed executions

Current evidence:

- shell workspace, governance queue, object browser, inspector, execution surfaces, display surfaces, and desktop host contract all exist
- `sbcl-agent-ux` consumes `desktop/show`, `desktop/action`, and `desktop/restore` as its host contract

Current impact:

- closed at the target-architecture level

Resolution:

- the UX layer now owns the shell-visible workspace, inspector, governance, object browser, surface, and desktop-host model
- renderer refinements remain possible, but the target architectural contract is in place

Priority:

- `closed`

## Gap 4: Developer Platform

Target doctrine:

- packages, manifests, SDK, testing, and simulation form a real external platform

Current evidence:

- `.aop` export, validate, import, install, activate, audit, profile, history, harness, and simulation flows exist
- active packages can now contribute compatibility app manifests into the live registry
- platform manifests, package contents, and SDK command inventory expose the platform contract explicitly

Current impact:

- closed at the target-architecture level

Resolution:

- the developer platform is now a real package/governance/activation/query surface, and active packages materially affect live compatibility behavior
- deeper ecosystem evolution is still possible, but the accepted target platform layer is now present

Priority:

- `closed`

## Gap 5: Runtime / Image / Boot Boundary

Target doctrine:

- the system boots into the IntentOS shell
- runtime / image substrate is first-class

Current evidence:

- live SBCL image, persistence, environment/session save-load, execution rehydration, shell-first workspace orientation, and runtime/image substrate all exist
- the accepted target-state architecture calls for a runtime/image substrate and shell-first governed system boundary, not a literal hardware-booting appliance image in this repo

Current impact:

- closed against the accepted target contract

Resolution:

- the runtime/image substrate is first-class and the shell is the actual operator entry boundary
- future appliance packaging would be distribution work, not a current-vs-target architecture gap

Priority:

- `closed`

## Recommended Order

The earlier gap program is complete.

## Next Work

The next work should be treated as enhancement and hardening, not gap closure:

1. alternative compatibility backends beyond the current SBCL-governed host-process backend
2. richer UX presentation and desktop behavior
3. broader external package and SDK ecosystem depth
4. distribution and appliance packaging work if deployment form factor becomes a priority
