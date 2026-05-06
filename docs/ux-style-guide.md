---
layout: default
title: IntentOS UX Style Guide
hero_title: IntentOS UX Style Guide
hero_text: The visual and interaction style rules that should reinforce the system model rather than distract from it.
eyebrow: UX Style
permalink: /ux-style-guide.html
description: Visual and interaction style guide for IntentOS-oriented UX work.
---

# IntentOS UX Style Guide

## Purpose

The visual system should reinforce:

- governance
- inspectability
- operational confidence
- execution-centered interaction

It should not read like a generic enterprise dashboard or a conventional IDE clone.

## Tone

The product should feel:

- deliberate
- technical
- inspectable
- calm under load
- operational rather than decorative

## Typography

Typography should distinguish:

- object identity
- execution posture
- governance state
- supporting explanation

Avoid flattening all information into one visual weight.

## Visual Hierarchy

Primary:

- current execution or current object
- status or pressure requiring attention
- next available action

Secondary:

- explanation
- related objects
- historical trace

Tertiary:

- counts
- aggregate metrics
- supporting summaries

## Color Semantics

Color should encode state, not theme preference.

Suggested semantic directions:

- blue: active context / focus
- amber: gated, blocked, or cautionary posture
- red: failure, quarantine, or urgent intervention
- green: completed or validated posture
- neutral graphite tones: structure, trace, and background

## Interaction Style

The interaction model should be:

- inspector-first
- direct
- keyboard-capable
- explicit about mutation and approval state

Avoid hidden state transitions or clever shorthand that obscures system truth.

## Tab Style Pattern

When a surface uses tabs, they must look unambiguously like tabs.

Required visual signals:

- a dedicated tab rail rather than plain inline text
- a distinct active tab state
- a visible relationship between the active tab and the panel it controls
- lower visual emphasis for inactive tabs without making them ambiguous

Preferred treatment:

- a grounded horizontal tab rail
- a raised or connected active tab
- one contained panel directly beneath the selected tab

Avoid:

- plain text labels that read like filters or buttons
- pills that do not visually connect to the controlled panel
- nested panel headers that duplicate the selected tab label without adding new meaning

## Scroll And Resize Style

For tabbed editor-like surfaces:

- the outer surface should visually own resize
- the active work object should visually own scroll
- wrapper panels should not expose their own incidental scrollbars
- inner fields should not expose resize handles when the outer resident already provides resizing

The user should feel that they are resizing one instrument, not fighting multiple nested panels.

## Content Style

Prefer:

- explicit nouns for system objects
- action labels that describe real interventions
- short operational summaries

Avoid:

- vague “AI assistant” phrasing where a concrete system object exists
- faux conversational labels for governed actions
- decorative status language that hides blockers

## Style Review Questions

1. Does the visual treatment strengthen or weaken object identity?
2. Can the user tell what is active, blocked, or mutable?
3. Does the hierarchy reveal the execution model?
4. Does the style help the shell feel like a system, not a web dashboard?
