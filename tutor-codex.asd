(asdf:defsystem "tutor-codex"
  :description "An SBCL-native CLI foundation for a Codex-like terminal assistant."
  :author "OpenAI Codex"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on ()
  :components ((:file "src/package")
               (:file "src/config")
               (:file "src/json")
               (:file "src/provider-protocol")
               (:file "src/provider-mock")
               (:file "src/provider-openai")
               (:file "src/commands")
               (:file "src/events")
               (:file "src/policy")
               (:file "src/session")
               (:file "src/sandbox")
               (:file "src/tools-registry")
               (:file "src/tools-fs")
               (:file "src/tools-session")
               (:file "src/tools-docs")
               (:file "src/tools-process")
               (:file "src/tools-git")
               (:file "src/patch")
               (:file "src/tasks")
               (:file "src/shell")
               (:file "src/repl")
               (:file "src/main"))
  :in-order-to ((asdf:test-op (asdf:test-op "tutor-codex/tests"))))

(asdf:defsystem "tutor-codex/tests"
  :description "Base test suite for tutor-codex."
  :author "OpenAI Codex"
  :license "MIT"
  :depends-on ("tutor-codex")
  :serial t
  :components ((:file "tests/package")
               (:file "tests/smoke"))
  :perform (asdf:test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call :tutor-codex/tests :run-all-tests)))
