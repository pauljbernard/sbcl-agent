---
layout: default
title: Common Lisp Language Reference
hero_title: Common Lisp Language Reference
hero_text: A reference-oriented Common Lisp section for sbcl-agent readers, organized by language area rather than as a short introductory guide.
eyebrow: CL Reference
permalink: /common-lisp-guide.html
description: Common Lisp reference landing page for sbcl-agent.
---
## Intent

This section is the Common Lisp reference set for `sbcl-agent`. It is intended to be materially closer in ambition to a language reference than to a beginner's primer.

It is still written in the voice of this repository:

- practical rather than encyclopedic for its own sake
- grounded in code and shell usage you will actually see here
- broad enough to support serious reading of the codebase

The reference is organized by topic so readers can move directly to the language subsystem they need.

## Reference Map

<div class="card-grid">
  <a class="card" href="{{ '/cl-syntax-and-evaluation.html' | relative_url }}">
    <div class="card-title">Syntax and Evaluation</div>
    <p>Forms, symbols, quoting, reader syntax, special operators, macros, and the basic evaluation model.</p>
  </a>
  <a class="card" href="{{ '/cl-bindings-functions-macros.html' | relative_url }}">
    <div class="card-title">Bindings, Functions, and Macros</div>
    <p>Lexical and dynamic bindings, lambda lists, multiple values, local functions, closures, and macro-writing fundamentals.</p>
  </a>
  <a class="card" href="{{ '/cl-data-and-control-flow.html' | relative_url }}">
    <div class="card-title">Data and Control Flow</div>
    <p>Conditionals, sequencing, iteration, non-local control, generalized assignment, and common structured-data patterns.</p>
  </a>
  <a class="card" href="{{ '/cl-collections-and-types.html' | relative_url }}">
    <div class="card-title">Collections and Types</div>
    <p>Lists, conses, sequences, arrays, strings, hash tables, structures, type predicates, and declarations.</p>
  </a>
  <a class="card" href="{{ '/cl-objects-and-metaobject-protocols.html' | relative_url }}">
    <div class="card-title">Objects and Generic Functions</div>
    <p>CLOS classes, generic functions, methods, slot options, method combination, and where object dispatch matters in the repo.</p>
  </a>
  <a class="card" href="{{ '/cl-packages-reader-and-printer.html' | relative_url }}">
    <div class="card-title">Packages, Reader, and Printer</div>
    <p>Namespaces, package-qualified symbols, readtable behavior, printed representations, and REPL-facing language mechanics.</p>
  </a>
  <a class="card" href="{{ '/cl-conditions-streams-and-files.html' | relative_url }}">
    <div class="card-title">Conditions, Streams, and Files</div>
    <p>Error signaling, handlers, restarts, stream abstractions, pathnames, file I/O, and formatted output.</p>
  </a>
  <a class="card" href="{{ '/cl-compilation-and-runtime.html' | relative_url }}">
    <div class="card-title">Compilation and Runtime</div>
    <p>Compilation, loading, ASDF, runtime images, optimization declarations, and why incremental loading matters here.</p>
  </a>
</div>

## Suggested Reading Order

If you are new to Common Lisp, read in this order:

1. [Syntax and Evaluation]({{ '/cl-syntax-and-evaluation.html' | relative_url }})
2. [Bindings, Functions, and Macros]({{ '/cl-bindings-functions-macros.html' | relative_url }})
3. [Data and Control Flow]({{ '/cl-data-and-control-flow.html' | relative_url }})
4. [Collections and Types]({{ '/cl-collections-and-types.html' | relative_url }})
5. [Packages, Reader, and Printer]({{ '/cl-packages-reader-and-printer.html' | relative_url }})
6. [Conditions, Streams, and Files]({{ '/cl-conditions-streams-and-files.html' | relative_url }})
7. [Objects and Generic Functions]({{ '/cl-objects-and-metaobject-protocols.html' | relative_url }})
8. [Compilation and Runtime]({{ '/cl-compilation-and-runtime.html' | relative_url }})

## What This Section Covers

This reference set is meant to help you understand:

- how code is represented and evaluated
- how bindings, functions, and macros interact
- how Common Lisp expresses control flow and data transformation
- how collections, types, structures, classes, and generic functions fit together
- how packages, streams, pathnames, compilation, and the runtime image shape real systems

## What Matters Most For sbcl-agent

In this repository, the highest-value Common Lisp concepts are:

- forms and evaluation
- quoting and code-as-data
- keyword arguments and property lists
- packages and package-qualified names
- structures, classes, generic functions, and methods
- conditions and stream I/O
- ASDF loading and live-image runtime behavior

Those are the concepts that most strongly shape the shell, provider boundary, conversation runtime, and workflow-governed engineering model.

## Local Cross-Links

The most relevant companion docs are:

- [Common Lisp as a Runtime]({{ '/common-lisp-runtime.html' | relative_url }})
- [Architecture and Design]({{ '/architecture.html' | relative_url }})
- [User Guide]({{ '/user-guide.html' | relative_url }})

For direct code reading, start with:

1. `src/package.lisp`
2. `src/commands.lisp`
3. `src/shell.lisp`
4. `src/provider-protocol.lisp`
5. `src/conversation.lisp`
