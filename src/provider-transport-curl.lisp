(in-package #:sbcl-agent)

(defun temporary-curl-body-pathname ()
  (merge-pathnames
   (format nil "sbcl-agent-curl-body-~D-~A.json"
           (get-universal-time)
           (gensym "BODY-"))
   (uiop:temporary-directory)))

(defun write-curl-body-file (body)
  (let ((body-path (temporary-curl-body-pathname)))
    (ensure-directories-exist body-path)
    (with-open-file (stream body-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string body stream))
    body-path))

(defun curl-json-request-with-headers (url headers body &key (label "HTTP request"))
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream))
        (body-path (write-curl-body-file body)))
    (unwind-protect
         (let ((process (sb-ext:run-program
                         "curl"
                         (append (list "-sS"
                                       "-X" "POST"
                                       url)
                                 (loop for header in headers
                                       append (list "-H" header))
                                 (list "--data-binary"
                                       (format nil "@~A" (namestring body-path))))
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
             stdout-string))
      (when (probe-file body-path)
        (delete-file body-path)))))

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
         (body-path (write-curl-body-file body))
         (process (sb-ext:run-program
                   "curl"
                   (append (list "-sS"
                                 "-N"
                                 "-X" "POST"
                                 url)
                            (loop for header in headers
                                  append (list "-H" header))
                            (list "--data-binary"
                                  (format nil "@~A" (namestring body-path))))
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
        (close output))
      (when (probe-file body-path)
        (delete-file body-path)))))

(defun stream-openai-json-request (url api-key body line-handler)
  (stream-json-request-with-headers
   url
   (list "Content-Type: application/json"
         (format nil "Authorization: Bearer ~A" api-key))
   body
   line-handler
   :label "OpenAI streaming request"))
