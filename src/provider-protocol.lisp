(in-package #:tutor-codex)

(defclass provider () ())

(defstruct provider-request
  prompt
  session-summary)

(defstruct assistant-action
  type
  payload)

(defstruct assistant-response
  message
  actions
  metadata)

(defgeneric provider-name (provider))
(defgeneric provider-capabilities (provider))
(defgeneric send-request (provider request))

(defun make-provider-request-from-session (prompt session)
  (let ((active-session (or session (ignore-errors (ensure-session)))))
    (make-provider-request :prompt prompt
                           :session-summary (when active-session
                                              (session-summary active-session)))))

(defun assistant-response->string (response)
  (assistant-response-message response))

(defun send-prompt (provider prompt &optional session)
  (send-request provider (make-provider-request-from-session prompt session)))

(defun normalize-action-type (value)
  (cond
    ((keywordp value) value)
    ((stringp value) (intern (string-upcase value) :keyword))
    (t (error "Unsupported action type ~S" value))))

(defun normalize-json-derived-value (value)
  (cond
    ((and (stringp value)
          (> (length value) 0)
          (char= (char value 0) #\:))
     (intern (string-upcase (subseq value 1)) :keyword))
    ((and (listp value) (every #'consp value))
     (json-object->keyword-plist value))
    ((listp value)
     (mapcar #'normalize-json-derived-value value))
    (t
     value)))

(defun json-key->keyword (key)
  (intern (string-upcase (substitute #\- #\_ key)) :keyword))

(defun json-object->keyword-plist (object)
  (loop for (key . value) in object
        append (list (json-key->keyword key)
                     (normalize-json-derived-value value))))

(defun decode-assistant-action (object)
  (let ((payload (json-object-value object "payload")))
    (make-assistant-action
     :type (normalize-action-type (json-object-value object "type"))
     :payload (if (and (listp payload) (every #'consp payload))
                  (json-object->keyword-plist payload)
                  (normalize-json-derived-value payload)))))

(defun decode-assistant-response-object (object)
  (make-assistant-response
   :message (or (json-object-value object "message") "")
   :actions (mapcar #'decode-assistant-action
                    (or (json-object-value object "actions") '()))
   :metadata (json-object->keyword-plist (or (json-object-value object "metadata") '()))))

(defun execute-assistant-action (action session)
  (case (assistant-action-type action)
    (:TOOL
     (let* ((payload (assistant-action-payload action))
            (tool-id (or (getf payload :TOOL-ID)
                         (getf payload :TOOL_ID)))
            (arguments (or (getf payload :ARGUMENTS)
                           (getf payload :arguments))))
       (unless (keywordp tool-id)
         (error "Assistant tool action requires keyword tool id, got ~S" tool-id))
       (apply #'invoke-tool tool-id session (or arguments '()))))
    (:PATCH
     (apply-patch-operations session (assistant-action-payload action)))
    (t
     (error "Unsupported assistant action type ~S" (assistant-action-type action)))))

(defun execute-assistant-action-list (actions session)
  (let ((results
          (mapcar (lambda (action)
                    (list :action action
                          :result (execute-assistant-action action session)))
                  actions)))
    (append-session-event session :assistant-actions-executed results)
    results))

(defun execute-assistant-actions (response session)
  (execute-assistant-action-list (assistant-response-actions response) session))

(defun make-provider (config)
  (let ((provider-name (string-downcase (config-provider config))))
    (cond
      ((string= provider-name "mock")
       (make-instance 'mock-provider :model (config-model config)))
      ((or (string= provider-name "openai")
           (string= provider-name "openai-compatible"))
       (make-instance 'openai-compatible-provider
                      :model (config-model config)
                      :api-base (or (config-api-base config) "https://api.openai.com/v1")
                      :api-key (config-api-key config)))
      (t
       (error "Unsupported provider ~S. Supported providers: mock, openai-compatible"
              (config-provider config))))))
