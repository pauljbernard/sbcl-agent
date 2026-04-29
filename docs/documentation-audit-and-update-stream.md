# Documentation Audit And Update Stream

## Purpose

This document is the working audit for bringing the GitHub Pages documentation up to the current `sbcl-agent` and `sbcl-agent-ux` state after the execution-kernel, compatibility-kernel, desktop-host, platform, QA, and stabilization refactors.

It is intentionally file-by-file so the documentation stream can be executed and reviewed in bounded passes instead of through one vague “docs refresh.”

## Audit Status

Legend:

- `current`: substantially aligned with the codebase
- `refresh`: useful, but needs wording or structural updates
- `rewrite`: materially stale and should be rewritten around the current architecture
- `infra`: documentation build/publishing infrastructure issue

## Progress Snapshot

Completed:

- front door and core narrative refresh
- architecture, objective, validation, and IntentOS program refresh
- operator, service-boundary, retrieval, QA, and UX refresh
- roadmap and journey-plan reframing
- docs publishing script/workflow update away from tracked Gemfile state
- markdown link consistency sweep

Remaining:

- local GitHub Pages build verification once Jekyll dependencies are available in the local environment
- lower-priority consistency checks on reference/background pages

## High-Priority Infrastructure

| File | Status | Issue | Required Action |
| --- | --- | --- | --- |
| `.github/workflows/docs.yml` | `infra` | Still expects tracked `Gemfile` / Bundler workflow after those files were intentionally removed from the repo. | Replace Bundler/Gemfile dependency with a repo-supported docs build path. |
| `bin/install-docs-deps` | `infra` | Assumes `bundle install` from a tracked Gemfile. | Update to install docs dependencies without relying on tracked Gemfile state. |
| `bin/build-docs` | `infra` | Uses `bundle check` / `bundle exec`. | Switch to the new docs dependency model. |
| `bin/serve-docs` | `infra` | Uses `bundle check` / `bundle exec`. | Switch to the new docs dependency model. |

## Front Door And Core Narrative

| File | Status | Issue | Required Action |
| --- | --- | --- | --- |
| `README.md` | `current` | Core positioning and docs publishing guidance refreshed. | Light consistency validation only. |
| `docs/index.md` | `rewrite` | Front door still frames the system as mainly “moving toward” the target and contains at least one stale link (`roadmap/environment-model`). | Recast as current-state front door, fix stale links, and align strengths/weaknesses with current reality. |
| `docs/problem.md` | `current` | Thesis page, likely still sound. | Light validation only. |
| `docs/application-domains.md` | `current` | Domain framing is likely still sound. | Light validation only. |
| `docs/foundation.md` | `refresh` | Still frames the environment object and architecture as not yet fully established. | Update from “becoming” to “implemented, with remaining enhancement work.” |
| `docs/why-sbcl-agent.md` | `refresh` | Directional language is mostly fine, but some “moving toward” language should be tightened. | Refresh narrative to distinguish completed architecture from future enhancement. |
| `docs/objectives.md` | `refresh` | Delivery objectives are current, but some longer-term items should be split into “achieved architecture” vs “next enhancement.” | Update objective attainment framing. |

## Architecture And Kernel Documents

| File | Status | Issue | Required Action |
| --- | --- | --- | --- |
| `docs/architecture.md` | `rewrite` | Large sections still describe the execution kernel, environment model, and service boundary as transitional rather than present. | Rewrite around the current architecture with explicit “implemented” vs “enhancement” sections. |
| `docs/core-entities.md` | `refresh` | Likely needs alignment with execution handles, display surfaces, and desktop actions. | Validate and refresh entity summaries. |
| `docs/mutation-model.md` | `refresh` | Should reflect current checkpoint, cold-validation, reconciliation, and forensic depth posture. | Refresh workflow lifecycle descriptions. |
| `docs/conversation-architecture.md` | `refresh` | Still says some operation families are not yet fully surfaced. | Update conversation/runtime/workflow integration claims. |
| `docs/kernel-invariants.md` | `current` | Doctrine page likely still correct. | Validate against current implementation, small edits only if needed. |
| `docs/public-service-interfaces.md` | `current` | Reframed around the active service boundary and live host integration. | Light consistency validation only. |
| `docs/service-boundary-hardening.md` | `refresh` | Likely accurate in principle, but may overstate future-tense boundary work. | Tighten to current service-contract reality. |
| `docs/service-event-contract.md` | `current` | Event contract wording aligned to current clients. | Light consistency validation only. |
| `docs/streaming-event-model.md` | `refresh` | Needs verification against current canonical event envelope and evidence posture. | Validate and refresh. |
| `docs/environment-retrieval-architecture.md` | `refresh` | Contains future-UX and not-yet language. | Align retrieval, cognition, and service reads with current environment-native state. |
| `docs/environment-authority.md` | `refresh` | May still describe authority normalization gaps that are now closed or narrower. | Validate and refresh. |

## IntentOS And Gap-Analysis Documents

| File | Status | Issue | Required Action |
| --- | --- | --- | --- |
| `docs/agentos-target-state-architecture.md` | `current` | Target contract page is still useful. | Keep as target architecture reference; validate terminology only. |
| `docs/current-vs-target-gap-matrix.md` | `current` | Already updated to “closed.” | Keep and cross-link more prominently. |
| `docs/agentos-current-state-gap-analysis.md` | `rewrite` | Still describes missing kernel, compatibility, UX, and platform layers that are now implemented. | Rewrite as a current-state architecture assessment, not an open-gap page. |
| `docs/agentos-implementation-plan.md` | `current` | Rewritten as completed architecture program plus next enhancement tracks. | Light consistency validation only. |
| `docs/intentos-constitution.md` | `current` | Likely still valid. | Validate only. |
| `docs/intentos-requirements.md` | `refresh` | Should distinguish satisfied requirements from future enhancements. | Add attainment status or align language. |
| `docs/intentos-feature-specifications.md` | `current` | Governance/spec discipline likely still valid. | Validate only. |
| `docs/validation-strategy.md` | `refresh` | Still framed as transition validation rather than validation of a now-achieved target architecture plus hardening. | Reframe around sustaining invariants and backend evolution. |

## Operator And Usage Documents

| File | Status | Issue | Required Action |
| --- | --- | --- | --- |
| `docs/getting-started.md` | `refresh` | Still says the system is moving toward a fuller environment-native architecture. | Tighten quick-start framing to the current system. |
| `docs/user-guide.md` | `refresh` | Contains future-UX wording and likely misses newer display/desktop/operator flows. | Refresh command and operator posture guidance. |
| `docs/operator-journeys.md` | `refresh` | Likely needs alignment with display lane, workspace summaries, and execution-surface UX. | Validate and refresh. |
| `docs/safety-and-risk.md` | `refresh` | Risk statements need to distinguish unresolved risk from already-completed architecture. | Refresh strengths, limits, and current maturity. |
| `docs/evidence-profiles-and-visibility-rules.md` | `current` | Likely still valid as policy/evidence doctrine. | Validate only. |
| `docs/rgp-sbcl-agent-event-contract.md` | `refresh` | Should be checked against the current event envelope and RGP bridge flows. | Validate and refresh. |

## QA, Testing, And Hardening Documents

| File | Status | Issue | Required Action |
| --- | --- | --- | --- |
| `docs/testing-coverage-analysis.md` | `refresh` | Now stale after the new categorized test program, focused harnesses, evidence index, and QA expansion. | Refresh to current test-program structure and known remaining gaps. |

## UX Documents

| File | Status | Issue | Required Action |
| --- | --- | --- | --- |
| `docs/ux-design-system.md` | `refresh` | Needs validation against the now-current desktop host contract, display lane, and app-id-based action semantics. | Refresh to current `sbcl-agent`/`sbcl-agent-ux` contract. |
| `docs/ux-style-guide.md` | `current` | Likely still useful, but should be checked against the newer display-first lane. | Validate only. |

## Roadmap Documents

| File | Status | Issue | Required Action |
| --- | --- | --- | --- |
| `docs/implementation-plan.md` | `refresh` | Already partly updated, but still mixes achieved and in-flight items. | Tighten status language and point to enhancement work. |
| `docs/roadmap/vision.md` | `refresh` | Vision is still conceptually useful, but should be clearly labeled as origin-story/forward-looking. | Light refresh. |
| `docs/roadmap/visionp2.md` | `refresh` | Same as above, and should be linked correctly from the docs front door. | Light refresh and fix references. |
| `docs/roadmap/codex-execution-plan.md` | `refresh` | Some sections are explicitly historical now. | Mark completed sections clearly. |
| `docs/roadmap/engineering-parity-plan.md` | `refresh` | Needs validation against the now-expanded QA program. | Refresh status and next gaps. |
| `docs/roadmap/kernel-and-services-iteration-plan.md` | `refresh` | Contains future-UX extraction wording that is partly completed. | Refresh status framing. |
| `docs/roadmap/environment-retrieval-implementation-plan.md` | `refresh` | Needs validation against current retrieval/cognition implementation. | Refresh status. |

## Common Lisp Reference Pages

These are lower-risk for architectural drift and should be checked after the architecture/operator pages:

- `docs/common-lisp-guide.md`
- `docs/common-lisp-runtime.md`
- `docs/cl-*.md`

Status:

- `current` to `refresh`, depending on whether they reference repository-specific examples that have drifted

## Update Order

1. Fix docs publishing/build path so GitHub Pages can reliably rebuild.
2. Refresh the front door and core narrative:
   - `README.md`
   - `docs/index.md`
   - `docs/foundation.md`
   - `docs/getting-started.md`
3. Refresh core architecture/kernel pages:
   - `docs/architecture.md`
   - `docs/objectives.md`
   - `docs/public-service-interfaces.md`
   - `docs/validation-strategy.md`
4. Rewrite stale IntentOS transition pages:
   - `docs/agentos-current-state-gap-analysis.md`
   - `docs/agentos-implementation-plan.md`
5. Refresh operator, UX, QA, and roadmap pages.

## Stream Status

- current iteration focus:
  - final consistency sweep and local build verification
- next iteration focus:
  - residual low-priority cleanup only if inconsistencies remain
