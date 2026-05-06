---
layout: default
title: IntentOS Desktop Windowing Plan
hero_title: IntentOS Desktop Windowing Plan
hero_text: The implementation plan for moving from a shell-framed application host to a real multitasking desktop environment with governed, image-native surfaces.
eyebrow: UX Evolution
permalink: /desktop-windowing-implementation-plan.html
description: Concrete implementation plan for a NeXT-refined, Genera-like, image-native desktop shell for IntentOS.
---

# IntentOS Desktop Windowing Plan

## Why this plan exists

The project has already proven an important architectural point:

- `sbcl-agent` can act as a governed execution kernel
- `sbcl-agent-ux` can host governed surfaces over that kernel

But that is not yet the same thing as a real operating environment.

The current UX can still read as:

- one large desktop application
- with stronger shell semantics layered on top

rather than:

- a living desktop environment
- with multiple concurrent governed residents
- over one shared image-native operating substrate

This plan addresses that gap directly.

## Target statement

IntentOS should become:

- image-native like Genera and Smalltalk in semantic model
- refined like NeXT in visual discipline
- proactive only through explicit governance
- windowed and multitasking at the desktop level

The goal is not a prettier app shell.

The goal is a real desktop environment in which:

- the environment is the operating system
- windows are live views over governed objects and executions
- multiple surfaces can remain open concurrently
- inspection and control are shell-wide, not app-local conveniences

## What the current shell-framing work solved

The current `sbcl-agent-ux` work already established:

- a shell/app boundary
- `Control Panel` as the first hosted application
- `Listener Workbench` as a second hosted application
- shell-level proactive posture
- separation between shell surfaces and app-internal navigation

That work should be preserved.

It is a prerequisite layer, not the final desktop form.

## What is still missing

The current UX still lacks the properties that make a system feel like a real desktop:

- movable and persistent windows
- concurrent residency of multiple active tools
- explicit focus and stacking behavior
- shell-level opening, closing, and arranging of surfaces
- desktop-level multitasking rather than single-canvas replacement
- a visible distinction between:
  - the desktop itself
  - window residents inside it

## Governing design synthesis

The intended synthesis is:

- `Open Genera / Lisp Machines / Smalltalk`
  - the environment is primary
  - the image is alive
  - inspection is universal
  - tools are residents inside one symbolic world
- `NeXT`
  - calm and disciplined visual hierarchy
  - refined windowing
  - restrained chrome
  - serious, elegant multitasking presentation

The project should not become:

- a retro imitation
- a file-first IDE
- a dashboard with floating cards

## Desktop object model

The desktop shell should elevate the following first-class objects:

- `desktop`
- `surface`
- `window`
- `hosted-application`
- `execution-surface`
- `display-surface`
- `inspector-target`
- `governance-object`
- `workspace-context`

### Desktop

The desktop is the root operating context.

It owns:

- active environment binding
- shell-wide focus
- shell-wide proactive posture
- open windows
- stacking and placement
- launch and restore behavior

### Surface

A surface is a semantic view over one primary system object or execution context.

Examples:

- control-panel overview
- listener workbench
- object browser
- inspector
- governance queue
- approval detail
- incident recovery
- Linux app display surface

### Window

A window is a desktop container for one active surface.

It must have:

- stable identity
- associated surface identity
- title
- focus state
- z-order
- placement
- size
- minimized/restored posture
- closability rules

### Hosted application

A hosted application is a family of related surfaces with a coherent responsibility.

Initial hosted applications:

- `Control Panel`
- `Listener Workbench`

Future hosted applications should be introduced only when they earn distinct desktop identity and are not better represented as `Browser` domains or focused control-panel surfaces.

### Inspector target

The inspector target is shell-global.

It should be able to follow focus across windows without being trapped inside one application.

## Window model

### Core principle

The current center canvas should stop acting as the singular active work field.

Instead:

- the desktop root becomes the work field
- windows become the primary visible residents

### Required window behaviors

The shell must support:

1. open a new window for a surface
2. bring an existing window to front
3. focus a window without losing the rest of the desktop
4. move a window
5. resize a window
6. minimize a window
7. restore a window
8. close a window when policy allows it
9. reopen important shell utility windows

### Utility windows

Some windows should behave like classic utility panels:

- inspector
- governance queue
- object browser

They can be pinnable or dockable, but they must remain shell-wide, not app-private.

### Primary resident windows

Initial full windows should include:

- `Control Panel`
- `Listener Workbench`
- `Display Surface`

Then:

- future desktop residents that earn distinct application identity
- deeper governed detail windows such as work-item, approval, incident, and artifact views

## Surface lifecycle

Every surface should have explicit shell-level lifecycle:

1. launch
2. focus
3. inspect
4. suspend or minimize
5. restore
6. close or keep resident

The shell should know:

- why a surface exists
- what object or execution it belongs to
- whether it is resumable
- whether it is closable
- whether it should be restored on re-entry

## Proactive desktop model

Proactivity should not remain a summary panel inside the dominant application.

Instead the desktop should expose proactive behavior as:

- shell-level attention
- shell-level recommendations
- shell-level staged continuations
- shell-level monitors
- shell-level resumptions

These can still appear in a desktop lane or utility surface, but they must route into real windows and surfaces.

### Proactive invariants

Every proactive shell behavior must remain:

- inspectable
- attributable
- interruptible
- policy-bounded
- evidence-producing

## Migration of existing UX

### Phase 1. Preserve and contain

Keep the existing `sbcl-agent-ux` operational experience intact, but treat it explicitly as:

- `Control Panel`
- one hosted application
- one resident in the desktop

This phase is mostly complete.

### Phase 2. Introduce real window management

Build:

- shell desktop root
- window registry
- focus model
- z-order model
- placement model
- open/close/minimize/restore actions

This is the next real implementation phase.

### Phase 3. Convert current center surfaces into windows

Move:

- `Control Panel`
- `Listener Workbench`
- `Inspector`
- the consolidated `Operate` and `Browser` surfaces

from “canvas modes” into actual windows or utility windows.

### Phase 4. Make multi-residency normal

The desktop should support at least:

- `Control Panel` open
- `Listener Workbench` open
- `Inspector` open
- a governed `Display Surface` open

at the same time.

### Phase 5. Deepen resident application set

After windowing is real:

future browser-linked or platform capabilities should become true desktop residents only when they earn distinct application identity, not as placeholder shell apps.

## Suggested first implementation slices

### Slice 1. Desktop window registry

Add a shell-owned window registry with:

- window ids
- surface ids
- hosted app ids
- open/closed state
- focus state
- coordinates
- dimensions

### Slice 2. Utility-window inspector

Make the inspector a true shell utility window:

- globally available
- independently focusable
- able to follow selected objects across windows

### Slice 3. Listener workbench as an independent window

Open `Listener Workbench` as its own movable resident instead of replacing the central canvas.

### Slice 4. Control panel as a peer window

Once listener windowing works, move `Control Panel` into the same model so neither appears to own the whole desktop.

### Slice 5. Desktop arrangement primitives

Add:

- bring to front
- minimize
- restore
- tile
- reopen last surface set

## Acceptance criteria

The first true desktop-shell milestone is complete when all of the following are true:

1. The shell can show at least two concurrent primary resident windows.
2. `Control Panel` no longer visually owns the entire desktop work field.
3. `Listener Workbench` can remain open while the user also works in `Control Panel`.
4. The inspector can remain open as a shell-wide utility surface.
5. Shell-level proactivity routes into real windows, not only app-local panels.
6. Surface identity, focus, and control are visible and governable.
7. The desktop feels like a living environment with residents, not one app with extra rails.

## Validation plan

Validation for this work must include:

- renderer unit tests for desktop window state
- integration tests for open/focus/minimize/restore behavior
- Electron journey tests for:
  - opening multiple surfaces
  - switching focus
  - preserving inspector behavior across windows
- shell-contract tests proving window actions remain subordinate to governed surface identity

## Immediate next move

The next implementation step should be:

- build the shell-owned desktop window registry

That is the first change that moves the project from:

- shell-framed application host

to:

- actual desktop environment
