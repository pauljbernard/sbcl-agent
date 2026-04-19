(in-package #:sbcl-agent)

(defun curl-json-request (url api-key body)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (let ((process (sb-ext:run-program
                    "curl"
                    (list "-sS"
                          "-X" "POST"
                          url
                          "-H" "Content-Type: application/json"
                          "-H" (format nil "Authorization: Bearer ~A" api-key)
                          "-d" body)
                    :search t
                    :input nil
                    :output stdout
                    :error stderr
                    :wait t)))
      (let ((exit-code (sb-ext:process-exit-code process))
            (stdout-string (get-output-stream-string stdout))
            (stderr-string (get-output-stream-string stderr)))
        (unless (zerop exit-code)
          (provider-transport-error "OpenAI request" exit-code stderr-string))
        stdout-string))))

(defun stream-openai-json-request (url api-key body line-handler)
  (let* ((stderr (make-string-output-stream))
         (started-at (get-internal-real-time))
         (first-line-at nil)
         (process (sb-ext:run-program
                   "curl"
                   (list "-sS"
                         "-N"
                         "-X" "POST"
                         url
                         "-H" "Content-Type: application/json"
                         "-H" (format nil "Authorization: Bearer ~A" api-key)
                         "-d" body)
                   :search t
                   :input nil
                   :output :stream
                   :error stderr
                   :wait nil))
         (output (sb-ext:process-output process)))
    (emit-provider-timing :http-started :started-at started-at)
    (unwind-protect
         (loop for line = (read-line output nil nil)
               while line
               do (progn
                    (unless first-line-at
                      (setf first-line-at (get-internal-real-time))
                      (emit-provider-timing :first-line
                                            :started-at started-at
                                            :first-line-at first-line-at
                                            :elapsed-seconds (/ (- first-line-at started-at)
                                                                internal-time-units-per-second)))
                    (funcall line-handler line))
               finally
                  (progn
                    (close output)
                    (sb-ext:process-wait process)
                    (let ((completed-at (get-internal-real-time))
                          (exit-code (sb-ext:process-exit-code process))
                          (stderr-string (get-output-stream-string stderr)))
                      (emit-provider-timing :http-complete
                                            :started-at started-at
                                            :first-line-at first-line-at
                                            :completed-at completed-at
                                            :elapsed-seconds (/ (- completed-at started-at)
                                                                internal-time-units-per-second)
                                            :exit-code exit-code)
                      (unless (zerop exit-code)
                        (provider-transport-error "OpenAI streaming request" exit-code stderr-string)))))
      (when (and output (open-stream-p output))
        (close output)))))
