(in-package #:tutor-codex)

(defclass openai-compatible-provider (provider)
  ((model :initarg :model :reader openai-provider-model)
   (api-base :initarg :api-base :reader openai-provider-api-base)
   (api-key :initarg :api-key :reader openai-provider-api-key)))

(defmethod provider-name ((provider openai-compatible-provider))
  "openai-compatible")

(defmethod provider-capabilities ((provider openai-compatible-provider))
  '(:chat :structured-response :action-proposals :network))

(defun build-openai-system-prompt ()
  (concatenate
   'string
   "You are an SBCL-based coding assistant. "
   "Return only valid JSON with keys message, actions, and metadata. "
   "Actions must be an array. "
   "If proposing a tool action, use {\"type\":\"tool\",\"payload\":{\"tool_id\":\":FS/READ\",\"arguments\":[\":path\",\"src/main.lisp\"]}} style payloads. "
   "If no actions are needed, return an empty actions array."))

(defun build-openai-user-prompt (request)
  (format nil
          "User prompt: ~A~%Session summary: ~S"
          (provider-request-prompt request)
          (provider-request-session-summary request)))

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

(defun build-openai-request-body (provider request)
  (emit-json
   (list :model (openai-provider-model provider)
         :messages (list
                    (list :role "system"
                          :content (build-openai-system-prompt))
                    (list :role "user"
                          :content (build-openai-user-prompt request)))
         :temperature 0.2)))

(defun extract-openai-message-content (response-object)
  (let* ((choices (json-object-value response-object "choices"))
         (first-choice (first choices))
         (message (and first-choice (json-object-value first-choice "message"))))
    (or (and message (json-object-value message "content"))
        (let ((error-object (json-object-value response-object "error")))
          (if error-object
              (error "OpenAI API error: ~A" (json-object-value error-object "message"))
              (error "Could not find assistant content in OpenAI response"))))))

(defmethod send-request ((provider openai-compatible-provider) request)
  (unless (openai-provider-api-key provider)
    (error "OPENAI_API_KEY is required for the openai-compatible provider"))
  (let* ((url (format nil "~A/chat/completions"
                      (string-right-trim "/" (openai-provider-api-base provider))))
         (body (build-openai-request-body provider request))
         (raw-response (curl-json-request url (openai-provider-api-key provider) body))
         (outer-object (parse-json raw-response))
         (content (extract-openai-message-content outer-object))
         (decoded (decode-assistant-response-object (parse-json content))))
    (setf (assistant-response-metadata decoded)
          (append (assistant-response-metadata decoded)
                  (list :provider :openai-compatible
                        :model (openai-provider-model provider))))
    decoded))
