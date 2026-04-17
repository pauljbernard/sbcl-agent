---
layout: default
title: Common Lisp Syntax and Evaluation
hero_title: Syntax and Evaluation
hero_text: The core rules for reading Common Lisp forms, including symbols, quoting, reader syntax, special operators, and macro expansion.
eyebrow: CL Reference
permalink: /cl-syntax-and-evaluation.html
description: Common Lisp syntax and evaluation reference for sbcl-agent.
---
## Forms

Common Lisp source is read as Lisp objects called forms. A form is either:

- an atom such as a symbol, string, number, or character
- a list, usually written in parentheses

Examples:

```lisp
42
"hello"
foo
(+ 1 2)
```

The first task when reading Common Lisp is deciding whether a list is:

- ordinary code
- data
- a macro use
- a special operator form

## Symbols

Symbols are the most important named objects in the language. They can designate:

- variables
- functions
- macros
- classes
- types
- conditions
- package exports
- property-list keys

Examples:

```lisp
provider
run-say-turn
t
nil
:stream
```

### Keywords

Keywords are self-evaluating symbols in the `KEYWORD` package:

```lisp
:stream
:queued
:workspace-write
```

They are heavily used for named arguments and structured payloads throughout `sbcl-agent`.

## Evaluation Basics

The ordinary evaluation model is:

1. atoms may evaluate as themselves or as variable lookups
2. lists normally mean function calls
3. special operators and macros define exceptions to the ordinary rule

### Self-evaluating objects

These normally evaluate to themselves:

- numbers
- strings
- characters
- keywords

Examples:

```lisp
42
"hello"
#\A
:ready
```

### Variable evaluation

A non-keyword symbol in value position is treated as a variable reference:

```lisp
(let ((x 10))
  x)
```

### Function-call evaluation

The normal list rule is:

- evaluate the operator
- evaluate each argument
- call the function

Example:

```lisp
(+ (* 2 3) 4)
```

## Quote and Function

### Quoting data

Use quote to prevent evaluation:

```lisp
'hello
'(+ 1 2)
'(:status :queued)
```

Without quote, `(+ 1 2)` is a computation. With quote, it is a list.

### Function designators

`#'name` is shorthand for `(function name)`:

```lisp
(mapcar #'1+ '(1 2 3))
```

That yields a function object, not the symbol itself.

## Backquote

Backquote is used for templated list construction:

```lisp
(let ((name "world"))
  `(hello ,name))
```

This is fundamental to macro writing and any code that emits Lisp forms.

Useful markers inside backquote:

- `,x` inserts one evaluated value
- `,@xs` splices a list of evaluated values

## Reader Syntax

The reader turns characters into Lisp objects. Some syntax is reader-level rather than function-level.

Important examples:

- `'form`
- `#'name`
- `` `form ``
- `,x`
- `,@xs`
- `#\a`
- `#p"/tmp/file"`

These are not just textual conveniences. They affect the objects produced before evaluation begins.

## Special Operators

Special operators define the core evaluation rules of the language. They are not ordinary functions.

Important examples:

- `quote`
- `if`
- `progn`
- `let`
- `let*`
- `setq`
- `block`
- `return-from`
- `catch`
- `throw`
- `tagbody`
- `go`
- `function`
- `unwind-protect`

Why this matters:

- ordinary functions evaluate all arguments before the call
- special operators control evaluation in non-standard ways

## Macros

Macros transform source forms before ordinary evaluation.

Examples of common macros:

- `when`
- `unless`
- `cond`
- `loop`
- `dotimes`
- `dolist`
- `with-open-file`

Macro expansion is part of the language model. When reading macro-heavy code, ask:

1. what does this expand into?
2. what is evaluated immediately?
3. what remains as runtime code?

## Truth and `nil`

Common Lisp uses:

- `nil` for false
- anything else for true

`t` is the conventional canonical true value.

Important fact:

- `nil` is also the empty list

This dual role is foundational in the language.

## Evaluation Questions To Ask While Reading Code

When you encounter a form, ask:

1. Is it code or quoted data?
2. Is the leading symbol a function, macro, or special operator?
3. Does it return one value or multiple values?
4. Does it construct data, cause control transfer, or mutate a place?
5. Is the visible syntax reader-level shorthand for something deeper?

Those questions eliminate much of the mystery in real Common Lisp code.
