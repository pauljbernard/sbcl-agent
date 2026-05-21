(in-package #:sbcl-agent/tests)

(defun focused-actor-system-regression-tests ()
  (list (list "actor-registry-foundation-test"
              #'actor-registry-foundation-test)
        (list "actor-thread-pool-captures-governed-execution-context-test"
              #'actor-thread-pool-captures-governed-execution-context-test)
        (list "actor-thread-pool-enforces-governance-inside-actor-test"
              #'actor-thread-pool-enforces-governance-inside-actor-test)
        (list "actor-thread-pool-prepares-resolution-inside-actor-test"
              #'actor-thread-pool-prepares-resolution-inside-actor-test)
        (list "focused-actor-thread-pool-serializes-per-actor-test"
              #'focused-actor-thread-pool-serializes-per-actor-test)
        (list "focused-actor-max-concurrency-test"
              #'focused-actor-max-concurrency-test)
        (list "focused-actor-runtime-queue-drain-test"
              #'focused-actor-runtime-queue-drain-test)
        (list "actor-system-panel-query-test"
              #'actor-system-panel-query-test)
        (list "workflow-events-carry-actor-origin-metadata-test"
              #'workflow-events-carry-actor-origin-metadata-test)
        (list "actor-system-panel-persists-through-environment-save-load-test"
              #'actor-system-panel-persists-through-environment-save-load-test)
        (list "actor-supervision-action-application-test"
              #'actor-supervision-action-application-test)
        (list "actor-supervision-restart-child-test"
              #'actor-supervision-restart-child-test)
        (list "actor-supervision-resume-from-checkpoint-test"
              #'actor-supervision-resume-from-checkpoint-test)
        (list "actor-supervision-recommended-workflow-recovery-test"
              #'actor-supervision-recommended-workflow-recovery-test)
        (list "direct-conversation-runtime-definition-actor-state-test"
              #'direct-conversation-runtime-definition-actor-state-test)
        (list "runtime-actor-state-persists-through-environment-save-load-test"
              #'runtime-actor-state-persists-through-environment-save-load-test)))

(defun run-focused-actor-system-test-case (name thunk)
  (funcall thunk)
  (format t "PASS ~A~%" name))

(defun run-actor-system-regressions ()
  (dolist (case (focused-actor-system-regression-tests))
    (run-focused-actor-system-test-case (first case) (second case))))
