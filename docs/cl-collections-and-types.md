---
layout: default
title: Common Lisp Collections and Types
hero_title: Collections and Types
hero_text: Lists, conses, sequences, arrays, strings, hash tables, structures, type predicates, and the practical type model used in Common Lisp programs.
eyebrow: CL Reference
permalink: /cl-collections-and-types.html
description: Common Lisp collections and types reference for sbcl-agent.
---
## Conses and Lists

Lists are made from cons cells.

### Construction

```lisp
(cons 1 '(2 3))
(list 1 2 3)
```

### Access

```lisp
(car '(10 20 30))
(cdr '(10 20 30))
(first '(10 20 30))
(rest '(10 20 30))
```

### Proper and improper lists

Proper list:

```lisp
(1 2 3)
```

Improper list:

```lisp
(1 2 . 3)
```

## Sequences

The sequence abstraction covers lists and vectors.

Useful sequence functions:

- `length`
- `elt`
- `subseq`
- `find`
- `position`
- `remove`
- `sort`

## Vectors and Arrays

Literal vector:

```lisp
#(1 2 3)
```

Array access:

```lisp
(aref #(10 20 30) 1)
```

Arrays can be multidimensional and specialized, though many everyday cases only need vectors and strings.

## Strings

Strings are arrays of characters.

Useful operations:

- `length`
- `char`
- `string=`
- `string-upcase`
- `string-downcase`
- `concatenate`

Example:

```lisp
(string-upcase "agent")
```

## Hash Tables

Create:

```lisp
(make-hash-table :test #'equal)
```

Read:

```lisp
(gethash "provider" table)
```

Write:

```lisp
(setf (gethash "provider" table) "mock")
```

`gethash` returns two values:

- the value
- whether the key was present

## Property Lists

Property lists are alternating key/value lists:

```lisp
'(:provider "mock" :model "gpt-5")
```

Access:

```lisp
(getf plist :provider)
```

They are used heavily throughout this repository because they print well and are easy to inspect in the REPL.

## Structures

`defstruct` creates lightweight record types.

Example:

```lisp
(defstruct user
  name
  role)
```

This generates constructor and accessor functions automatically.

## Type Predicates

Common type tests:

- `numberp`
- `integerp`
- `stringp`
- `symbolp`
- `listp`
- `consp`
- `hash-table-p`
- `pathnamep`
- `functionp`

General type relation:

```lisp
(typep object 'string)
```

## Declarations

Declarations can communicate type and optimization intent:

```lisp
(let ((x 10))
  (declare (type integer x))
  (+ x 1))
```

Other common declarations:

- `special`
- `ignore`
- `ignorable`
- `optimize`

## Why Types Matter Here

Common Lisp is dynamically typed, but this repository still depends on type reasoning in:

- command dispatch
- provider event normalization
- session record handling
- tool argument validation
- structured workflow metadata
