(in-package #:tutor-codex)

(defun tool-proc-run (session &key argv)
  (declare (ignore session))
  (unless (and (listp argv) argv)
    (error ":proc/run requires non-empty :argv"))
  (let* ((stdout (make-string-output-stream))
         (stderr (make-string-output-stream))
         (process (sb-ext:run-program (first argv)
                                      (rest argv)
                                      :search t
                                      :input nil
                                      :output stdout
                                      :error stderr
                                      :wait t)))
    (list :tool :proc/run
          :argv argv
          :stdout (get-output-stream-string stdout)
          :stderr (get-output-stream-string stderr)
          :exit-code (sb-ext:process-exit-code process))))

(register-tool :proc/run
               "Run a local process and capture stdout, stderr, and exit code."
               :process-run
               #'tool-proc-run)
