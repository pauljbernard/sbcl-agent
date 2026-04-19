(in-package #:sbcl-agent)

(defun curl-json-request-with-headers (url headers body &key (label "HTTP request"))
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (let ((process (sb-ext:run-program
                    "curl"
                    (append (list "-sS"
                                  "-X" "POST"
                                  url)
                            (loop for header in headers
                                  append (list "-H" header))
                            (list "-d" body))
                    :search t
                    :input nil
                    :output stdout
                    :error stderr
                    :wait t)))
      (let ((exit-code (sb-ext:process-exit-code process))
            (stdout-string (get-output-stream-string stdout))
            (stderr-string (get-output-stream-string stderr)))
        (unless (zerop exit-code)
          (provider-transport-error label exit-code stderr-string))
        stdout-string))))

(defun curl-json-request (url api-key body)
  (curl-json-request-with-headers
   url
   (list "Content-Type: application/json"
         (format nil "Authorization: Bearer ~A" api-key))
   body
   :label "OpenAI request"))

(defun stream-json-request-with-headers (url headers body line-handler &key (label "Streaming HTTP request"))
  (let* ((stderr (make-string-output-stream))
         (started-at (get-internal-real-time))
         (first-line-at nil)
         (process (sb-ext:run-program
                   "curl"
                   (append (list "-sS"
                                 "-N"
                                 "-X" "POST"
                                 url)
                            (loop for header in headers
                                  append (list "-H" header))
                            (list "-d" body))
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
                        (provider-transport-error label exit-code stderr-string)))))
      (when (and output (open-stream-p output))
        (close output)))))

(defun stream-openai-json-request (url api-key body line-handler)
  (stream-json-request-with-headers
   url
   (list "Content-Type: application/json"
         (format nil "Authorization: Bearer ~A" api-key))
   body
   line-handler
   :label "OpenAI streaming request"))
