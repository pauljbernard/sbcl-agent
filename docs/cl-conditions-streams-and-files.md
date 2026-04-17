---
layout: default
title: Common Lisp Conditions, Streams, and Files
hero_title: Conditions, Streams, and Files
hero_text: Error signaling, handlers, restarts, stream abstractions, pathnames, file I/O, and formatted output in Common Lisp.
eyebrow: CL Reference
permalink: /cl-conditions-streams-and-files.html
description: Common Lisp conditions, streams, and files reference for sbcl-agent.
---
## Conditions

Common Lisp has a condition system rather than only a narrow exception model.

Basic signaling functions:

- `error`
- `warn`
- `signal`
- `cerror`

Example:

```lisp
(error "Something went wrong")
```

## Handlers

Useful handling forms:

- `handler-case`
- `handler-bind`
- `ignore-errors`

Example:

```lisp
(handler-case
    (dangerous-call)
  (error (e)
    (format nil "failed: ~A" e)))
```

## Restarts

The condition system can separate signaling from recovery. Restarts provide named recovery paths and are one of Common Lisp's distinctive runtime features.

This repo does not yet lean on restart-heavy design everywhere, but understanding that the language supports it is important.

## Streams

Streams are the main I/O abstraction.

Important dynamic variables:

- `*standard-input*`
- `*standard-output*`
- `*error-output*`
- `*trace-output*`

## `format`

`format` is central to Common Lisp output.

Examples:

```lisp
(format t "Hello, ~A~%" "world")
(format nil "~A-~D" "task" 3)
(format t "Status: ~S~%" '(:ok t))
```

## Files and Pathnames

Common Lisp has pathname objects as a first-class abstraction.

Useful functions:

- `merge-pathnames`
- `truename`
- `pathname-directory`
- `make-pathname`

Example:

```lisp
(merge-pathnames #P"docs/" *default-pathname-defaults*)
```

## File I/O

Typical pattern:

```lisp
(with-open-file (stream "notes.txt" :direction :input)
  (read-line stream))
```

`with-open-file` ensures cleanup and is preferred over ad hoc open/close sequencing.

## Why This Matters In sbcl-agent

These topics matter directly in:

- CLI output
- shell rendering
- docs tooling
- patch and filesystem helpers
- configuration and provider bootstrap logic
