---
layout: default
title: Common Lisp Language Guide
hero_title: Common Lisp Language Guide
hero_text: A practical introduction to reading and using the language that powers sbcl-agent, focused on forms, evaluation, packages, keyword arguments, and the shell command style used in this repo.
eyebrow: Language Guide
permalink: /common-lisp-guide.html
description: Practical Common Lisp language guide for sbcl-agent readers.
---
## Purpose

This guide is for readers who want to understand the language used throughout `sbcl-agent` without wading through a full language textbook first. It focuses on the pieces of Common Lisp you need to read the codebase and interact with the shell.

## The Basic Mental Model

Common Lisp code is written as forms. The most common form is a list enclosed in parentheses.

```lisp
(+ 1 2 3)
```

This means:

- call the function `+`
- pass the arguments `1`, `2`, and `3`

The first element in a list is usually an operator. The remaining elements are its arguments.

## Data Types You Will See Constantly

### Numbers

```lisp
42
3.14
```

### Strings

```lisp
"hello"
```

### Symbols

Symbols are names used for variables, functions, keywords, and more.

```lisp
foo
some-variable
:workspace-write
```

Keywords are symbols in the `KEYWORD` package and evaluate to themselves. They are commonly used for named options and status markers.

### Lists

```lisp
'(1 2 3)
'(ask "hello")
```

A quoted list is treated as data rather than evaluated as code.

## Evaluation

By default, Lisp evaluates forms.

```lisp
(+ 100 203)
```

returns `303`.

If you want to refer to a list or symbol as data, quote it.

```lisp
'(+ 100 203)
'hello
```

## Variables

### Local variables with `let`

```lisp
(let ((x 10)
      (y 20))
  (+ x y))
```

### Global parameters with `defparameter`

```lisp
(defparameter *threshold* 5)
```

By convention, dynamically scoped special variables are often named with surrounding `*earmuffs*`.

## Defining Functions

```lisp
(defun double (x)
  (* 2 x))
```

Call it like this:

```lisp
(double 21)
```

## Conditionals

### `if`

```lisp
(if (> 5 3)
    "yes"
    "no")
```

### `cond`

```lisp
(cond
  ((< x 0) :negative)
  ((= x 0) :zero)
  (t :positive))
```

`cond` is a multi-branch conditional. `t` acts like a default true case.

## Sequencing

Use `progn` to evaluate multiple forms in order and return the last result.

```lisp
(progn
  (print "start")
  (+ 1 2))
```

Many constructs already allow multiple body forms, so `progn` is often implicit.

## Working With Lists

### `list`

```lisp
(list 1 2 3)
```

### `first`, `rest`, `car`, `cdr`

```lisp
(first '(10 20 30))
(rest '(10 20 30))
```

### Mapping

```lisp
(mapcar #'1+ '(1 2 3))
```

`#'` refers to a function object.

## Property Lists

You will see property-list style data in this codebase.

```lisp
(list :provider "mock" :model "gpt-5")
```

Access values with `getf`.

```lisp
(getf '(:provider "mock" :model "gpt-5") :provider)
```

## Structures and Classes

The project uses both structures and CLOS classes.

### Structures

A structure is a lightweight record type.

```lisp
(defstruct user
  name
  role)
```

### Classes

A class supports a more extensible object model.

```lisp
(defclass provider () ())
```

## Generic Functions and Methods

Common Lisp's object system supports generic functions.

```lisp
(defgeneric provider-name (provider))

(defmethod provider-name ((provider my-provider))
  "my-provider")
```

This is a core pattern in `sbcl-agent`, especially around providers.

## Packages

Packages are namespaces.

The main system package in this repo is `SBCL-AGENT`. The shell evaluates ordinary user forms in `SBCL-AGENT-USER`.

A file often starts with:

```lisp
(in-package #:sbcl-agent)
```

The `#:` syntax creates an uninterned symbol for package designators in source.

## Keywords and Named Arguments

Functions can accept keyword arguments.

```lisp
(defun greet (name &key loud)
  (if loud
      (string-upcase name)
      name))
```

Call it like this:

```lisp
(greet "paul" :loud t)
```

This style is used throughout the shell command interface.

## Reading sbcl-agent Forms

These examples should make more sense now.

### Ask the provider

```lisp
(ask "please read src/main.lisp")
```

### Ask in streaming mode

```lisp
(ask "please read src/main.lisp" :stream t)
```

### Approve a capability

```lisp
(approve :workspace-write)
```

### Invoke a tool

```lisp
(tool :fs/read :path "src/main.lisp")
```

### Apply a patch request

```lisp
(patch '((:write "notes.txt" "hello")))
```

Notice that the argument to `patch` is quoted because it is data describing an edit, not code to execute directly.

## Macros

Macros transform code before evaluation. They are one of Lisp's signature features, but you do not need deep macro knowledge to start using this project.

It is enough to know that some constructs which look like function calls are actually special language forms or macros.

Examples include:

- `defun`
- `let`
- `cond`
- `when`
- `unless`

## Error Handling

Common Lisp uses a condition system.

In this repo you will often see `error` used for simple failure signaling in tests and runtime checks.

```lisp
(error "Something went wrong")
```

More advanced condition and restart patterns can be added later as the runtime grows more sophisticated.

## Practical Advice For New Readers

- Read forms from left to right.
- Check whether a form is code or quoted data.
- Treat keywords like named labels.
- Expect functions to return rich Lisp data rather than JSON strings when inside the runtime.
- Remember that the shell is a Lisp interface, not a separate command language.

## Minimal REPL Starter Set

If you want five forms to experiment with first, use these:

```lisp
(+ 1 2 3)
(let ((x 10)) (* x 2))
(mapcar #'1+ '(1 2 3))
(getf '(:provider "mock" :model "gpt-5") :model)
(tool :session/summary)
```

That is enough to start reading the repo and using the shell effectively.
