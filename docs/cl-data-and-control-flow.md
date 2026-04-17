---
layout: default
title: Common Lisp Data and Control Flow
hero_title: Data and Control Flow
hero_text: Conditionals, sequencing, iteration, non-local exits, generalized places, and common structured-data idioms in real Common Lisp systems.
eyebrow: CL Reference
permalink: /cl-data-and-control-flow.html
description: Common Lisp data and control flow reference for sbcl-agent.
---
## Conditionals

### `if`

```lisp
(if (> x 0)
    :positive
    :non-positive)
```

### `when` and `unless`

```lisp
(when ready
  (start-worker))

(unless configured
  (error "Missing configuration"))
```

### `cond`

```lisp
(cond
  ((null x) :empty)
  ((numberp x) :number)
  (t :other))
```

### `case`

```lisp
(case status
  (:queued "waiting")
  (:completed "done")
  (otherwise "unknown"))
```

## Sequencing

### `progn`

```lisp
(progn
  (print "start")
  (+ 1 2))
```

Many body-bearing forms already behave like an implicit `progn`.

## Iteration

### `dolist`

```lisp
(dolist (x '(1 2 3))
  (print x))
```

### `dotimes`

```lisp
(dotimes (i 3)
  (print i))
```

### `loop`

`loop` is powerful and common.

Examples:

```lisp
(loop for x in '(1 2 3)
      collect (* x 2))
```

```lisp
(loop for (key value) on plist by #'cddr
      do (format t "~A => ~A~%" key value))
```

## Sequence-style transformation

Useful higher-order tools:

- `mapcar`
- `remove-if`
- `remove-if-not`
- `find-if`
- `reduce`
- `every`
- `some`

Examples:

```lisp
(mapcar #'1+ '(1 2 3))
(reduce #'+ '(1 2 3 4))
```

## Non-local Control Flow

Common Lisp provides explicit non-local transfer tools.

### `block` and `return-from`

```lisp
(block search
  (dolist (x '(1 2 3 4))
    (when (= x 3)
      (return-from search :found)))
  :not-found)
```

### `catch` and `throw`

```lisp
(catch 'done
  (throw 'done :finished))
```

### `unwind-protect`

```lisp
(unwind-protect
    (do-something-risky)
  (cleanup))
```

Use this when cleanup must occur even if control leaves non-locally.

## Generalized Places

`setf` works over places, not just variables.

Important place forms include:

- variables
- `car` and `cdr`
- array accessors
- hash-table entries
- structure and class accessors

Examples:

```lisp
(setf (car pair) 'updated)
(setf (gethash key table) value)
```

## Structured Data Idioms

### Property lists

Very common in `sbcl-agent`:

```lisp
(list :kind :task
      :status :queued
      :worker-id worker-id)
```

### Quoted instruction data

```lisp
(patch '((:write "notes.txt" "hello")))
```

This is data describing an action, not executable code.

### Keyword-heavy APIs

```lisp
(ask "read src/main.lisp" :stream t)
(tool :fs/read :path "src/main.lisp")
```

## Practical Reading Rule

In this codebase, control flow often hides in a small set of forms:

- `cond`
- `when`
- `unless`
- `loop`
- `return-from`
- `handler-case`
- `unwind-protect`

If you can read those confidently, large parts of the code become straightforward.
