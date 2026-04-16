(in-package #:sbcl-agent)

(defclass openai-compatible-provider (provider)
  ((model :initarg :model :reader openai-provider-model)
   (fast-model :initarg :fast-model :reader openai-provider-fast-model)
   (api-base :initarg :api-base :reader openai-provider-api-base)
   (api-key :initarg :api-key :reader openai-provider-api-key)))

(defparameter +stream-actions-marker+ "<<<SBCL-ACTIONS>>>")
(defparameter +stream-actions-end-marker+ "<<<END-SBCL-ACTIONS>>>")
(defparameter *provider-timing-listener* nil)

(defun emit-provider-timing (phase &rest payload)
  (when *provider-timing-listener*
    (funcall *provider-timing-listener* phase payload)))

(defmethod provider-name ((provider openai-compatible-provider))
  "openai-compatible")

(defmethod provider-capabilities ((provider openai-compatible-provider))
  '(:chat :structured-response :action-proposals :network :streaming))

(defun build-openai-system-prompt ()
  (concatenate
   'string
   "You are an SBCL-based coding assistant operating inside a live Common Lisp shell. "
   "You have session context through the supplied session summary, including recent transcript entries. "
   "The operator interface is Common Lisp, and ordinary Lisp forms are evaluated directly by the host runtime when the operator enters them. "
   "You cannot create effects by prose alone. When execution or inspection is needed, return structured actions. "
   "Return only valid JSON with keys message, actions, and metadata. Actions must be an array. "
   "Supported action types are tool, patch, and eval. "
   "Use an eval action when the user wants Common Lisp code executed in the current image. The eval payload should carry the Lisp form to run. "
   "Use a tool action when you need structured tool access such as reading files or listing directories. "
   "If the user refers to earlier code or discussion, resolve that reference against recent transcript entries instead of claiming you lack memory. "
   "Do not claim the user must enable a REPL or execution tool when the request can be satisfied with an eval action in the current Lisp image. "
   "If no actions are needed, return an empty actions array."))

(defun build-openai-stream-system-prompt ()
  (concatenate
   'string
   "You are an SBCL-based coding assistant operating inside a live Common Lisp shell. "
   "Stream the operator-facing answer as plain text first. "
   "After the visible text is complete, append a newline, then the exact marker "
   +stream-actions-marker+
   ", then a JSON object with keys actions and metadata, then the exact marker "
   +stream-actions-end-marker+
   ". "
   "The visible text before the marker must not be JSON unless the user explicitly asks for JSON. "
   "The hidden JSON object after the marker must contain only actions and metadata. Actions must be an array. "
   "Supported action types are tool, patch, and eval. "
   "Use an eval action when the user wants Common Lisp code executed in the current image. "
   "If no actions are needed, emit an empty actions array. "
   "Never omit the markers in streaming mode."))

(defun build-openai-user-prompt (request)
  (format nil
          "User prompt: ~A~%~%Session summary: ~S~%~%Interpret references like 'the code you suggested' against :recent-transcript when available."
          (provider-request-prompt request)
          (provider-request-session-summary request)))

(defun deep-request-p (prompt)
  (some (lambda (needle)
          (search needle prompt :test #'char-equal))
        '("deep" "detailed" "detail" "architecture" "design" "analyze"
          "analysis" "compare" "review" "thorough" "comprehensive"
          "plan" "roadmap" "refactor" "multi-agent" "gap")))

(defun openai-request-model (provider request)
  (if (deep-request-p (provider-request-prompt request))
      (openai-provider-model provider)
      (or (openai-provider-fast-model provider)
          (openai-provider-model provider))))

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
          (error "OpenAI request failed with exit code ~D: ~A" exit-code stderr-string))
        stdout-string))))

(defun build-openai-request-body (provider request &key (stream nil) (stream-protocol nil))
  (emit-json
   (list :model (openai-request-model provider request)
         :messages (list
                    (list :role "system"
                          :content (if stream-protocol
                                       (build-openai-stream-system-prompt)
                                       (build-openai-system-prompt)))
                    (list :role "user"
                          :content (build-openai-user-prompt request)))
         :stream stream)))

(defun extract-openai-message-content (response-object)
  (let* ((choices (json-object-value response-object "choices"))
         (first-choice (first choices))
         (message (and first-choice (json-object-value first-choice "message"))))
    (or (and message (json-object-value message "content"))
        (let ((error-object (json-object-value response-object "error")))
          (if error-object
              (error "OpenAI API error: ~A" (json-object-value error-object "message"))
              (error "Could not find assistant content in OpenAI response"))))))

(defun extract-openai-stream-delta (chunk-object)
  (let* ((choices (json-object-value chunk-object "choices"))
         (first-choice (first choices))
         (delta (and first-choice (json-object-value first-choice "delta"))))
    (and delta (json-object-value delta "content"))))

(defun openai-stream-done-p (line)
  (string= line "data: [DONE]"))

(defun openai-stream-data-line-p (line)
  (and (>= (length line) 6)
       (string= "data: " line :end1 6 :end2 6)))

(defun parse-openai-stream-json-line (line)
  (parse-json (subseq line 6)))

(defun decode-openai-content-response (content model)
  (let ((decoded (decode-assistant-response-object (parse-json content))))
    (setf (assistant-response-metadata decoded)
          (append (assistant-response-metadata decoded)
                  (list :provider :openai-compatible
                        :model model)))
    decoded))

(defun decoded-action-payload-present-p (action)
  (case (assistant-action-type action)
    (:EVAL
     (let ((payload (assistant-action-payload action)))
       (or (stringp payload)
           (and (listp payload)
                (or (getf payload :FORM)
                    (getf payload :form)
                    (getf payload :CODE)
                    (getf payload :code)
                    (getf payload :EXPRESSION)
                    (getf payload :expression))))))
    (t t)))

(defun sanitized-response-actions (response)
  (remove-if-not #'decoded-action-payload-present-p
                 (assistant-response-actions response)))

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
                        (error "OpenAI streaming request failed with exit code ~D: ~A" exit-code stderr-string)))))
      (when (and output (open-stream-p output))
        (close output)))))

(defun longest-marker-overlap (text marker)
  (loop for size from (1- (length marker)) downto 1
        when (and (<= size (length text))
                  (string= marker text :end1 size :start2 (- (length text) size)))
          do (return size)
        finally (return 0)))

(defun parse-stream-visible-fragment (buffer)
  (let ((marker-position (search +stream-actions-marker+ buffer)))
    (cond
      (marker-position
       (values (subseq buffer 0 marker-position)
               (subseq buffer (+ marker-position (length +stream-actions-marker+)))
               t))
      (t
       (let* ((holdback (longest-marker-overlap buffer +stream-actions-marker+))
              (split-point (- (length buffer) holdback)))
         (values (if (plusp split-point) (subseq buffer 0 split-point) "")
                 (if (plusp holdback) (subseq buffer split-point) "")
                 nil))))))

(defun finalize-stream-response (visible-buffer action-buffer model)
  (let* ((actions-end (search +stream-actions-end-marker+ action-buffer))
         (payload-text (if actions-end
                           (subseq action-buffer 0 actions-end)
                           action-buffer))
         (trimmed-visible (string-right-trim '(#\Newline #\Return) visible-buffer))
         (trimmed-payload (string-trim '(#\Space #\Tab #\Newline #\Return) payload-text))
         (payload (if (> (length trimmed-payload) 0)
                      (parse-json trimmed-payload)
                      '(("actions" . ()) ("metadata" . ()))))
         (actions (mapcar #'decode-assistant-action (or (json-object-value payload "actions") '())))
         (metadata (json-object->keyword-plist (or (json-object-value payload "metadata") '()))))
    (make-assistant-response
     :message trimmed-visible
     :actions (remove-if-not #'decoded-action-payload-present-p actions)
     :metadata (append metadata (list :provider :openai-compatible
                                      :model model)))))

(defmethod send-request ((provider openai-compatible-provider) request)
  (unless (openai-provider-api-key provider)
    (error "OPENAI_API_KEY is required for the openai-compatible provider"))
  (let* ((url (format nil "~A/chat/completions"
                      (string-right-trim "/" (openai-provider-api-base provider))))
         (body (build-openai-request-body provider request))
         (raw-response (curl-json-request url (openai-provider-api-key provider) body))
         (outer-object (parse-json raw-response))
         (content (extract-openai-message-content outer-object)))
    (decode-openai-content-response content (openai-provider-model provider))))

(defmethod stream-request ((provider openai-compatible-provider) request event-handler)
  (unless (openai-provider-api-key provider)
    (error "OPENAI_API_KEY is required for the openai-compatible provider"))
  (let* ((url (format nil "~A/chat/completions"
                      (string-right-trim "/" (openai-provider-api-base provider))))
         (body (build-openai-request-body provider request :stream t :stream-protocol t))
         (visible-buffer "")
         (pending-visible "")
         (action-buffer "")
         (actions-section-p nil)
         (first-delta-at nil)
         (started-at (get-internal-real-time)))
    (emit-provider-timing :request-built
                          :started-at started-at
                          :body-bytes (length body)
                          :prompt-bytes (length (provider-request-prompt request)))
    (emit-provider-event event-handler :message-start nil)
    (stream-openai-json-request url
                                (openai-provider-api-key provider)
                                body
                                (lambda (line)
                                  (when (and (not (string= line ""))
                                             (openai-stream-data-line-p line)
                                             (not (openai-stream-done-p line)))
                                    (let* ((chunk-object (parse-openai-stream-json-line line))
                                           (delta (extract-openai-stream-delta chunk-object)))
                                      (when delta
                                        (unless first-delta-at
                                          (setf first-delta-at (get-internal-real-time))
                                          (emit-provider-timing :first-delta
                                                                :started-at started-at
                                                                :first-delta-at first-delta-at
                                                                :elapsed-seconds (/ (- first-delta-at started-at)
                                                                                    internal-time-units-per-second)
                                                                :delta-bytes (length delta)))
                                        (if actions-section-p
                                            (setf action-buffer (concatenate 'string action-buffer delta))
                                            (multiple-value-bind (emit-text remainder found-marker)
                                                (parse-stream-visible-fragment (concatenate 'string pending-visible delta))
                                              (when (> (length emit-text) 0)
                                                (setf visible-buffer (concatenate 'string visible-buffer emit-text))
                                                (emit-provider-event event-handler :message-delta emit-text))
                                              (if found-marker
                                                  (progn
                                                    (setf actions-section-p t
                                                          pending-visible ""
                                                          action-buffer remainder))
                                                  (setf pending-visible remainder)))))))))
    (when (and (not actions-section-p) (> (length pending-visible) 0))
      (setf visible-buffer (concatenate 'string visible-buffer pending-visible))
      (emit-provider-event event-handler :message-delta pending-visible)
      (setf pending-visible ""))
    (let ((response (finalize-stream-response visible-buffer action-buffer (openai-provider-model provider))))
      (emit-provider-timing :response-finalized
                            :started-at started-at
                            :first-delta-at first-delta-at
                            :completed-at (get-internal-real-time)
                            :message-bytes (length (assistant-response-message response))
                            :action-count (length (assistant-response-actions response)))
      (setf (assistant-response-actions response)
            (sanitized-response-actions response))
      (when (assistant-response-actions response)
        (emit-provider-event event-handler :action-proposal (assistant-response-actions response)))
      (emit-provider-event event-handler
                           :message-complete
                           (list :response response
                                 :metadata (assistant-response-metadata response)))
      response)))
