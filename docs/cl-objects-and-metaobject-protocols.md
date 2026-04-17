---
layout: default
title: Common Lisp Objects and Generic Functions
hero_title: Objects and Generic Functions
hero_text: CLOS classes, generic functions, methods, and object-dispatch patterns that matter in real Common Lisp systems and extension-oriented codebases.
eyebrow: CL Reference
permalink: /cl-objects-and-metaobject-protocols.html
description: Common Lisp objects and generic functions reference for sbcl-agent.
---
## CLOS Basics

The Common Lisp Object System provides:

- classes
- instances
- generic functions
- methods
- method dispatch across argument types

## Classes

Example:

```lisp
(defclass provider ()
  ())
```

Richer example:

```lisp
(defclass person ()
  ((name :initarg :name :accessor person-name)
   (role :initarg :role :accessor person-role)))
```

## Generic Functions

A generic function defines an interface that methods implement for different argument types.

```lisp
(defgeneric provider-name (provider))
```

## Methods

```lisp
(defmethod provider-name ((provider mock-provider))
  "mock")
```

Methods can dispatch on multiple arguments, not just a single receiver.

## Method Combination

Common Lisp supports before, after, and around methods in addition to primary methods.

You do not need deep mastery of method combination to read this repo, but you should know that behavior may be assembled from more than one method body.

## Accessors and Slot Options

Slot options you will commonly see:

- `:initarg`
- `:accessor`
- `:reader`
- `:writer`
- `:initform`

These define how instances are initialized and accessed.

## Structures vs Classes

Use structures when:

- the record shape is simple
- inheritance is unnecessary
- lightweight representation is preferred

Use classes when:

- polymorphism matters
- method dispatch matters
- the design benefits from extension points

## Why This Matters In sbcl-agent

This repository uses object-style dispatch most clearly around:

- providers
- protocol boundaries
- extension-oriented helper APIs

If you can read `defclass`, `defgeneric`, and `defmethod`, you can follow the design intent in those areas.
