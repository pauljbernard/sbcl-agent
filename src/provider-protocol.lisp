(in-package #:sbcl-agent)

(defclass provider () ())

(defstruct provider-request
  prompt
  session-summary)

(defstruct assistant-action
  type
  payload)

(defstruct provider-event
  type
  payload)

(defstruct assistant-response
  message
  actions
  metadata)

(defgeneric provider-name (provider))
(defgeneric provider-capabilities (provider))
(defgeneric send-request (provider request))
(defgeneric stream-request (provider request event-handler))

(defun provider-summary-content (content &key (limit 240))
  (cond
    ((stringp content)
     (if (> (length content) limit)
         (concatenate 'string (subseq content 0 limit) "...")
         content))
    (t
     content)))

(defun provider-transcript-entry (entry)
  (list :role (getf entry :role)
        :content (provider-summary-content (getf entry :content))))

(defun provider-session-summary (session)
  (list :id (agent-session-id session)
        :cwd (agent-session-cwd session)
        :package (agent-session-package session)
        :plan (agent-session-plan session)
        :approved-policies (session-approved-policies session)
        :pending-action-count (length (agent-session-pending-actions session))
        :active-worker-count (active-worker-count session)
        :transcript-count (length (agent-session-transcript session))
        :recent-transcript (mapcar #'provider-transcript-entry
                                   (recent-session-transcript session))))

(defun make-provider-request-from-session (prompt session)
  (let ((active-session (or session (ignore-errors (ensure-session)))))
    (make-provider-request :prompt prompt
                           :session-summary (when active-session
                                              (provider-session-summary active-session)))))

(defun assistant-response->string (response)
  (assistant-response-message response))

(defun send-prompt (provider prompt &optional session)
  (send-request provider (make-provider-request-from-session prompt session)))

(defun emit-provider-event (event-handler type payload)
  (funcall event-handler (make-provider-event :type type :payload payload)))

(defun stream-response->assistant-response (events)
  (let ((message-fragments '())
        (actions '())
        (metadata '()))
    (dolist (event events)
      (case (provider-event-type event)
        (:message-delta
         (push (provider-event-payload event) message-fragments))
        (:action-proposal
         (let ((payload (provider-event-payload event)))
           (setf actions (append actions
                                 (if (listp payload) payload (list payload))))))
        (:message-complete
         (let ((payload (provider-event-payload event)))
           (when (and (listp payload) (getf payload :metadata))
             (setf metadata (getf payload :metadata)))))))
    (make-assistant-response
     :message (apply #'concatenate 'string (nreverse message-fragments))
     :actions actions
     :metadata metadata)))

(defun stream-prompt (provider prompt event-handler &optional session)
  (stream-request provider
                  (make-provider-request-from-session prompt session)
                  event-handler))

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

(defun valid-assistant-action-p (action)
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
    (:TOOL
     (let ((payload (assistant-action-payload action)))
       (keywordp (or (getf payload :TOOL-ID)
                     (getf payload :tool-id)
                     (getf payload :TOOL_ID)))))
    (:PATCH t)
    (t nil)))

(defun decode-assistant-response-object (object)
  (make-assistant-response
   :message (or (json-object-value object "message") "")
   :actions (remove nil
                    (mapcar (lambda (entry)
                              (let ((action (decode-assistant-action entry)))
                                (and (valid-assistant-action-p action)
                                     action)))
                            (or (json-object-value object "actions") '())))
   :metadata (json-object->keyword-plist (or (json-object-value object "metadata") '()))))

(defun parse-eval-action-form (payload)
  (cond
    ((stringp payload)
     (read-from-string payload))
    ((listp payload)
     (let ((source (or (getf payload :FORM)
                       (getf payload :form)
                       (getf payload :CODE)
                       (getf payload :code)
                       (getf payload :EXPRESSION)
                       (getf payload :expression))))
       (if source
           (read-from-string source)
           payload)))
    (t
     payload)))

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
    (:EVAL
     (eval-user-form (parse-eval-action-form (assistant-action-payload action))))
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

(defmethod stream-request ((provider provider) request event-handler)
  (let ((response (send-request provider request)))
    (emit-provider-event event-handler :message-start nil)
    (emit-provider-event event-handler :message-delta (assistant-response-message response))
    (when (assistant-response-actions response)
      (emit-provider-event event-handler :action-proposal (assistant-response-actions response)))
    (emit-provider-event event-handler
                         :message-complete
                         (list :response response
                               :metadata (assistant-response-metadata response)))
    response))

(defun make-provider (config)
  (let ((provider-name (string-downcase (config-provider config))))
    (cond
      ((string= provider-name "mock")
       (make-instance 'mock-provider :model (config-model config)))
      ((or (string= provider-name "openai")
           (string= provider-name "openai-compatible"))
       (make-instance 'openai-compatible-provider
                      :model (config-model config)
                      :fast-model (config-fast-model config)
                      :api-base (or (config-api-base config) "https://api.openai.com/v1")
                      :api-key (config-api-key config)))
      (t
       (error "Unsupported provider ~S. Supported providers: mock, openai-compatible"
              (config-provider config))))))
