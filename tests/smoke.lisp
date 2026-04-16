(in-package #:tutor-codex/tests)

(defun assert-true (condition message)
  (unless condition
    (error "Test failed: ~A" message)))

(defun runtime-smoke-test ()
  (let ((config (tutor-codex::load-config))
        (provider (tutor-codex::make-provider (tutor-codex::load-config))))
    (assert-true (typep config 'tutor-codex::config)
                 "load-config should return a tutor-codex config struct")
    (assert-true (string= (tutor-codex::provider-name provider) "mock")
                 "default provider should be mock")
    (assert-true (search "SBCL scaffold"
                         (tutor-codex::send-prompt provider "ping"))
                 "mock provider should return the scaffold smoke-test marker")))

(defun run-all-tests ()
  (format t "Running tutor-codex test suite...~%")
  (runtime-smoke-test)
  (format t "PASS runtime-smoke-test~%")
  (format t "All tests passed.~%")
  t)
