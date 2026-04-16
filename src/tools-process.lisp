(in-package #:tutor-codex)

(defun tool-proc-run (session &key argv)
  (declare (ignore session argv))
  (error ":proc/run must execute through the sandbox isolation layer"))

(register-tool :proc/run
               "Run a local process and capture stdout, stderr, and exit code."
               :process-run
               #'tool-proc-run
               :isolation-profile :process-run)
