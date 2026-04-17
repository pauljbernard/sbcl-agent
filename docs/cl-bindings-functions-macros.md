---
layout: default
title: Common Lisp Bindings, Functions, and Macros
hero_title: Bindings, Functions, and Macros
hero_text: Lexical and dynamic bindings, lambda lists, multiple values, closures, local functions, and the macro layer that gives Common Lisp its programmable surface syntax.
eyebrow: CL Reference
permalink: /cl-bindings-functions-macros.html
description: Common Lisp bindings, functions, and macros reference for sbcl-agent.
---
## Bindings

Common Lisp primarily uses lexical bindings by default.

### `let`

```lisp
(let ((x 10)
      (y 20))
  (+ x y))
```

### `let*`

`let*` lets later bindings depend on earlier ones:

```lisp
(let* ((x 10)
       (y (+ x 5)))
  y)
```

## Assignment

### `setq`

Assigns variables:

```lisp
(let ((x 1))
  (setq x 2)
  x)
```

### `setf`

`setf` generalizes assignment to places:

```lisp
(setf x 2)
(setf (car pair) 'new)
(setf (gethash key table) value)
```

This is one of the most important practical operators in real Common Lisp code.

## Global Definitions

Common defining forms:

- `defparameter`
- `defvar`
- `defconstant`

Examples:

```lisp
(defparameter *mode* :normal)
(defvar *cache* nil)
(defconstant +max-depth+ 5)
```

Conventions:

- `*earmuffs*` usually indicate special or dynamic variables
- `+pluses+` often indicate constants

## Dynamic Variables

Common Lisp supports dynamic scope through special variables.

Example:

```lisp
(defparameter *mode* :normal)

(let ((*mode* :debug))
  *mode*)
```

Dynamic variables are useful for ambient runtime context, but they should be used deliberately.

## Functions

### `defun`

```lisp
(defun double (x)
  (* 2 x))
```

### Lambda lists

Common Lisp lambda lists are rich.

#### Required parameters

```lisp
(defun f (x y) ...)
```

#### Optional parameters

```lisp
(defun greet (name &optional (prefix "hello"))
  (format nil "~A, ~A" prefix name))
```

#### Rest parameters

```lisp
(defun sum (&rest numbers)
  (reduce #'+ numbers :initial-value 0))
```

#### Keyword parameters

```lisp
(defun render (path &key stream pretty)
  (list :path path :stream stream :pretty pretty))
```

This style is everywhere in `sbcl-agent`.

#### Auxiliary variables

```lisp
(defun example (x &aux (y (* x 2)))
  y)
```

## Multiple Values

Functions can return multiple values directly.

Example:

```lisp
(floor 7 3)
```

This returns:

- quotient `2`
- remainder `1`

Capture them with `multiple-value-bind`:

```lisp
(multiple-value-bind (q r)
    (floor 7 3)
  (list q r))
```

Multiple values are normal, not exotic.

## Local Functions

### `flet`

Defines local functions:

```lisp
(flet ((double (x) (* 2 x)))
  (double 10))
```

### `labels`

Allows recursive local functions:

```lisp
(labels ((fact (n)
           (if (<= n 1)
               1
               (* n (fact (1- n))))))
  (fact 5))
```

## Closures

Local functions capture lexical bindings naturally:

```lisp
(let ((prefix "task-"))
  (lambda (name)
    (concatenate 'string prefix name)))
```

## Lisp-2 Namespaces

Common Lisp separates function and value namespaces.

Example:

```lisp
(let ((x 10))
  (flet ((x () 20))
    (list x (x))))
```

This is legal because the variable and local function occupy different namespaces.

## Macros

Macros transform forms before evaluation.

### Why macros matter

Macros make it possible to define new language constructs in Lisp itself.

### Simple example

```lisp
(defmacro when-positive (x &body body)
  `(when (> ,x 0)
     ,@body))
```

### Macro-reading rules

When reading a macro:

1. identify the generated shape
2. watch for repeated evaluation hazards
3. check which symbols are introduced
4. decide whether the abstraction changes control flow, binding, or data shape

### Macro-writing cautions

The main correctness risks are:

- evaluating an argument multiple times unintentionally
- accidental name capture
- hiding side effects or control flow too aggressively

## Repo-Relevant Patterns

In `sbcl-agent`, this topic matters most in:

- command lambda lists with keyword arguments
- property-list-heavy helper APIs
- local function helpers in shell/session code
- macro-based control constructs inherited from standard Common Lisp
