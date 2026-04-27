(in-package #:sbcl-agent)

(defun tool-proc-run (session &key argv)
  (declare (ignore session argv))
  (error ":proc/run must execute through the sandbox isolation layer"))

(defun tool-proc-spawn (session &key argv)
  (declare (ignore session argv))
  (error ":proc/spawn must execute through the compatibility isolation layer"))

(register-tool :proc/run
               "Run a local process and capture stdout, stderr, and exit code."
               :process-run
               #'tool-proc-run
               :isolation-profile :process-run
               :compatibility-kind :host-process)

(register-tool :proc/spawn
               "Spawn a local process as a governed compatibility execution."
               :process-run
               #'tool-proc-spawn
               :isolation-profile :process-run
               :compatibility-kind :host-process)
