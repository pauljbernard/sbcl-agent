---
layout: default
title: Common Lisp Packages, Reader, and Printer
hero_title: Packages, Reader, and Printer
hero_text: Namespaces, package-qualified symbols, readtable behavior, printed representations, and the language mechanics that shape the REPL and source files.
eyebrow: CL Reference
permalink: /cl-packages-reader-and-printer.html
description: Common Lisp packages, reader, and printer reference for sbcl-agent.
---
## Packages

Packages are Common Lisp namespaces.

Example package form:

```lisp
(defpackage #:example
  (:use #:cl)
  (:export #:run))
```

Implementation files often begin with:

```lisp
(in-package #:sbcl-agent)
```

## Package-qualified Symbols

Common notations:

- `package:symbol` for exported symbols
- `package::symbol` for internal symbols

Examples:

```lisp
uiop:getcwd
sbcl-agent::internal-helper
```

## Repo-Relevant Packages

Important package contexts here include:

- `SBCL-AGENT`
- `SBCL-AGENT-USER`

The shell evaluates user forms in a package that is intentionally separate from the implementation package.

## The Reader

The reader converts textual source into Lisp objects.

This matters because syntax such as `'`, `#'`, `` ` ``, `,`, `#\`, and `#p` is handled before evaluation.

The reader is one reason Lisp source and Lisp data are so closely related.

## The Printer

The printer converts Lisp objects back into text.

This affects:

- REPL output
- debug visibility
- whether values print readably
- whether property lists and structures are convenient inspection formats

## Readable vs Unreadable Output

Some objects print in a way that can be read back in. Others do not.

This distinction matters in REPL-heavy systems and is one reason simple list- and plist-based summaries are often attractive.

## Why This Matters Here

In `sbcl-agent`, packages, reader behavior, and printed representations affect:

- how shell forms are entered
- how state summaries are printed
- how source files are organized
- how paths and symbols appear in logs and debug output
