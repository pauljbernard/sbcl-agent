# Manual End-to-End SDLC Test Plan

## Purpose

Validate the full governed software-development journey inside the environment from project definition through implementation, testing, monitoring, persistence, recovery, and operational review.

This plan is written for a human operator validating that the shell, the SBCL agent backend, and the persistent environment model work together as one coherent system.

## Primary Goal

Prove that a project can move through this path without leaving the environment:

1. Create project
2. Define requirements
3. Define feature scope and user journey
4. Define architecture and non-functional expectations
5. Create and execute governed work
6. Implement changes
7. Run tests and evaluate quality gates
8. Inspect runtime and operational evidence
9. Save and reload the environment image
10. Confirm state, traceability, and operational posture survive reload

## Success Criteria

The journey passes if all of the following are true:

- project records are authorable and retrievable
- traceability links are visible and coherent
- governed work can be created and executed
- code changes can be made and inspected
- test evidence is produced and reflected in project quality gates
- monitoring and operational evidence can be inspected
- the environment can be saved, exited, reopened, and resumed from the saved image
- persisted state remains coherent across the UX and the SBCL backend

## Recommended Test Project

Use one small but concrete feature so the journey stays bounded.

Suggested scenario:

- Project name: `SDLC Journey Validation`
- Feature: `Conversation Draft Recovery`
- Goal: persist and restore conversation draft text and related shell state across environment image save/load

This scenario is appropriate because it touches:

- requirements
- project governance
- editor/workspace mutation
- testing
- quality gates
- persistence
- recovery

## Preconditions

Before starting:

- the Electron shell launches successfully
- the live SBCL backend is available
- the environment image chooser is functioning
- the current codebase is in a known testable state
- the shell is able to run tests and show monitoring surfaces

## Evidence To Capture

For each major section, capture:

- screenshots of the relevant surface
- exact saved image name used
- any failing or blocked state
- test output summaries
- quality gate posture
- trace sections from Projects, Work, and Incidents
- monitoring evidence used for operational review

## Test Phases

## Phase 1: Startup And Environment Selection

### Steps

1. Launch the shell.
2. Confirm the startup image chooser appears when saved images exist.
3. Select an existing named image, or create/open a dedicated image for this run.
4. Record the chosen image name.

### Expected Results

- the startup chooser is visible
- selecting an image opens the shell normally
- the chosen image becomes the active work image

## Phase 2: Project Creation And Governance Setup

### Steps

1. Open the `Projects` surface.
2. Create a new project named `SDLC Journey Validation`.
3. Add a constitution describing the product goal and governance expectations.
4. Add at least two requirements.
   - one functional
   - one non-functional
5. Add one feature specification tied to those requirements.
6. Add one user journey describing how the feature is experienced.
7. Add one architecture decision.
8. Add one source root binding.

### Expected Results

- the project appears in the project registry
- the project detail surface shows:
  - constitution
  - requirements
  - feature specifications
  - user journeys
  - architecture decisions
  - source roots
- project detail shows a trace section with non-zero links

### Evidence

- screenshot of the new project detail
- screenshot of the trace section

## Phase 3: Quality Gate Definition

### Steps

1. Add at least one project quality gate.
2. Configure it to require:
   - linked work item presence
   - required testing harness
   - coverage presence
   - recovery readiness
3. Observe the initial gate status before work and testing are complete.

### Expected Results

- the gate appears in the `Projects` surface
- the gate is initially `blocked` or not fully ready
- the blocked reasons are understandable from the displayed criteria/evidence

### Evidence

- screenshot of the quality gates section before work completion

## Phase 4: Work Creation And Traceability

### Steps

1. Open the `Work` surface.
2. Create or trigger governed work corresponding to the feature.
3. Confirm the work item is linked back to the project.
4. If an incident or workflow record is produced during the flow, inspect it.
5. Verify trace visibility from:
   - `Projects`
   - `Work`
   - `Incidents` if applicable

### Expected Results

- the work item appears in the work registry
- the project shows linked work
- the trace graph shows project-to-work linkage
- if a workflow record exists, it is represented in the trace neighborhood

### Evidence

- screenshot of work detail
- screenshot of project trace section after work creation

## Phase 5: Implementation

### Steps

1. Open the `Editor` surface.
2. Create or select a buffer for the target change.
3. Make a small, testable implementation change.
4. Use `Changed Forms` to verify the edit is recognized semantically.
5. Use `Definitions` or `Find Definitions` if needed to navigate related code.
6. Use `Browser` to inspect related source or runtime entities if appropriate.

### Expected Results

- the edit is visible in `Text`
- changed forms are listed in `Changed Forms`
- editor state remains coherent
- the environment supports navigation between editor and browser surfaces

### Evidence

- screenshot of `Editor > Changed Forms`
- screenshot of any relevant Browser/Source inspection

## Phase 6: Test Execution And Quality Evaluation

### Steps

1. Run the appropriate test harness for the change.
2. Confirm test results are produced.
3. If possible, also produce coverage evidence.
4. Return to `Projects` and review the quality gate section again.
5. Confirm gate posture updates based on the new evidence.

### Expected Results

- test harness execution succeeds or produces explicit failures
- test results are available as evidence
- quality gate posture changes accordingly
- if thresholds are met, the gate moves toward `ready`
- if thresholds are not met, the gate clearly remains `blocked`

### Evidence

- test output summary
- screenshot of quality gates after test execution

## Phase 7: Monitoring And Operational Review

### Steps

1. Open `Browser > Console`.
2. Open `Browser > Diagnostics`.
3. Open `Processes`, `Performance`, and `Host I/O` as relevant.
4. Confirm the runtime and host surfaces expose meaningful post-change evidence.
5. Inspect whether any new incidents, warnings, or anomalies are present.

### Expected Results

- console and diagnostics surfaces are navigable
- telemetry and operational evidence are available
- the operator can assess whether the environment is healthy after the change
- if issues exist, they are visible and governable

### Evidence

- screenshot of console or diagnostics evidence relevant to the change
- note any new incident or warning

## Phase 8: Persistence And Image Lifecycle

### Steps

1. Make sure the environment contains meaningful transient state:
   - project selected
   - conversation draft text
   - editor buffer content
   - workspace draft if relevant
2. Trigger the exit flow from the shell footer icon or window close.
3. Choose `Save Current`.
4. Relaunch the shell.
5. Reopen the same saved image.
6. Confirm the previously entered state is restored.
7. Repeat with `Save As New` using a distinct image name.
8. Repeat once more with `Discard` and verify no new image is created.

### Expected Results

- exit dialog appears consistently from both entry points
- `Save Current` preserves environment state into the current image
- `Save As New` creates a second named image
- `Discard` exits without creating a new saved image
- restored image state includes:
  - project state
  - conversation history
  - conversation draft
  - editor/workspace state
  - environment-backed configuration state

### Evidence

- screenshot of startup chooser with saved images
- screenshot of restored project/editor/conversation state

## Phase 9: Recovery Posture

### Steps

1. After reload, inspect the environment summary and relevant operational surfaces.
2. Confirm recovery posture is visible and does not falsely claim unrecoverable host state was fully restored.
3. Review any recovery or degraded-state indicators if present.

### Expected Results

- the environment resumes honestly
- if any runtime obligations remain manual or degraded, that is visible
- quality gates that depend on recovery readiness reflect the real posture

### Evidence

- screenshot or notes of recovery posture

## Phase 10: Traceability Closure Review

### Steps

1. Return to the `Projects` surface.
2. Inspect the trace section.
3. Verify you can identify the chain across:
   - project
   - requirement
   - feature spec
   - user journey
   - architecture decision
   - work item
   - testing evidence
   - incident or runtime evidence where applicable
4. Record any missing links.

### Expected Results

- the trace graph is coherent enough to explain how intent became implementation and evidence
- missing trace links, if any, are obvious and actionable

## Pass/Fail Decision

Mark the run as:

- `Pass`
  if the entire lifecycle can be completed and resumed with coherent evidence
- `Pass With Gaps`
  if the core lifecycle works but traceability, quality gates, or operational visibility are incomplete
- `Fail`
  if the lifecycle breaks in a way that prevents governed completion or reliable recovery

## Defect Logging Guidance

When defects are found, log them under one of these categories:

- `Requirements/Projects`
- `Traceability`
- `Editor/Development`
- `Testing/Quality Gates`
- `Monitoring/Diagnostics`
- `Persistence/Image Lifecycle`
- `Recovery`
- `UX/Usability`

For each defect capture:

- step number
- observed behavior
- expected behavior
- severity
- screenshot or log reference

## Recommended Follow-Up Variants

After the happy-path run passes, execute these variants:

1. `Blocked Quality Gate Variant`
- skip coverage or fail a test intentionally
- confirm the project remains blocked

2. `Incident Variant`
- trigger a governed deferral or runtime incident
- confirm incident visibility and trace linkage

3. `Recovery Variant`
- save an image with meaningful shell state
- reload and confirm recovery posture remains truthful

4. `Multi-Image Variant`
- create multiple saved images
- confirm chooser behavior and image identity remain stable

## Final Operator Checklist

- project created
- requirements entered
- feature spec entered
- user journey entered
- architecture decision entered
- quality gate created
- work item linked
- code changed
- changed forms reviewed
- tests run
- quality gates reviewed
- monitoring evidence reviewed
- image saved
- image reloaded
- traceability reviewed
- recovery posture reviewed

