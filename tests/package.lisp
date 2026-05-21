(defpackage #:sbcl-agent/tests
  (:use #:cl)
  (:export #:run-all-tests
           #:run-actor-system-regressions
           #:run-actor-system-performance-benchmarks
           #:run-concurrency-regressions
           #:run-concurrency-performance-benchmarks
           #:run-performance-benchmarks
           #:run-internal-evaluations))

(in-package #:sbcl-agent/tests)
