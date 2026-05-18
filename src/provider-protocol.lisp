(in-package #:sbcl-agent)

(declaim (special *current-environment*))

(defclass provider () ())

(defstruct provider-request
  prompt
  attachments
  session-summary
  thread-context
  turn-context
  environment-context
  surface-context
  surface-actions
  runtime-summary
  workspace-summary
  policy-summary
  retrieval-dossier
  cognition-bundle
  reasoning-brief
  planning-brief
  planning-context-packet
  outcome-brief
  operator-mode
  stream-p)

(defstruct assistant-action
  type
  payload)

(defstruct provider-event
  family
  type
  canonical-type
  legacy-type
  run-id
  operation-id
  entity-id
  thread-id
  turn-id
  visibility
  metadata
  payload)

(defstruct assistant-response
  message
  actions
  metadata)

(defgeneric provider-name (provider))
(defgeneric provider-capabilities (provider))
(defgeneric send-request (provider request))
(defgeneric stream-request (provider request event-handler))

(defun provider-turn-followup-p (provider)
  (member :turn-followup (provider-capabilities provider)))

(defun legacy-provider-event-type->canonical-type (type)
  (case type
    (:message-start :run-started)
    (:message-delta :text-delta)
    (:action-proposal :tool-intent)
    (:message-complete :text-complete)
    (otherwise type)))

(defun provider-event-effective-type (event)
  (or (provider-event-canonical-type event)
      (legacy-provider-event-type->canonical-type (provider-event-type event))))

(defun provider-text-delta-event-p (event)
  (eq (provider-event-effective-type event) :text-delta))

(defun provider-action-intent-event-p (event)
  (eq (provider-event-effective-type event) :tool-intent))

(defun provider-text-complete-event-p (event)
  (eq (provider-event-effective-type event) :text-complete))

(defun provider-summary-content (content &key (limit 240))
  (labels ((truncate-string (text)
             (if (> (length text) limit)
                 (concatenate 'string (subseq text 0 limit) "...")
                 text)))
    (cond
      ((stringp content)
       (truncate-string content))
      ((null content)
       "")
      (t
       content))))

(defun provider-transcript-entry (entry)
  (list :role (getf entry :role)
        :content (provider-summary-content (getf entry :content))))

(defun assistant-response->string (response)
  (assistant-response-message response))

(defun send-prompt (provider prompt &optional session &key thread turn (operator-mode :repl-bridge))
  (send-request provider
                (make-provider-request-from-session prompt
                                                   session
                                                   :thread thread
                                                   :turn turn
                                                   :operator-mode operator-mode
                                                   :stream-p nil)))

(defun send-provider-request (provider request)
  (send-request provider request))

(defun emit-provider-event (event-handler type payload
                          &key family canonical-type run-id operation-id entity-id thread-id turn-id
                            (visibility :user) metadata)
  (funcall event-handler
           (make-provider-event :family (or family :provider)
                                :type type
                                :canonical-type (or canonical-type
                                                    (legacy-provider-event-type->canonical-type type))
                                :legacy-type type
                                :run-id run-id
                                :operation-id operation-id
                                :entity-id entity-id
                                :thread-id thread-id
                                :turn-id turn-id
                                :visibility visibility
                                :metadata metadata
                                :payload payload)))

(defun stream-response->assistant-response (events)
  (let ((message-fragments '())
        (actions '())
        (metadata '()))
    (dolist (event events)
      (case (provider-event-effective-type event)
        (:text-delta
         (push (provider-event-payload event) message-fragments))
        (:tool-intent
         (let ((payload (provider-event-payload event)))
           (setf actions (append actions
                                 (if (listp payload) payload (list payload))))))
        (:text-complete
         (let ((payload (provider-event-payload event)))
           (when (and (listp payload) (getf payload :metadata))
             (setf metadata (getf payload :metadata)))))))
    (make-assistant-response
     :message (apply #'concatenate 'string (nreverse message-fragments))
     :actions actions
     :metadata metadata)))

(defun stream-prompt (provider prompt event-handler &optional session
                         &key thread turn (operator-mode :repl-bridge))
  (stream-request provider
                  (make-provider-request-from-session prompt
                                                     session
                                                     :thread thread
                                                     :turn turn
                                                     :operator-mode operator-mode
                                                     :stream-p t)
                  event-handler))

(defun stream-provider-request (provider request event-handler)
  (stream-request provider request event-handler))

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
    ((json-object-p value)
     (json-object->keyword-plist value))
    ((listp value)
     (mapcar #'normalize-json-derived-value value))
    (t
     value)))

(defun normalize-tool-id-value (value)
  (cond
    ((keywordp value) value)
    ((stringp value)
     (let ((normalized (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
       (when (> (length normalized) 0)
         (intern (string-upcase (if (char= (char normalized 0) #\:)
                                    (subseq normalized 1)
                                    normalized))
                 :keyword))))
    (t value)))

(defun json-object-p (value)
  (and (listp value)
       (every (lambda (entry)
                (and (consp entry)
                     (stringp (car entry))))
              value)))

(defun camel-json-key->hyphenated-string (key)
  (with-output-to-string (stream)
    (loop for index from 0 below (length key)
          for char = (char key index)
          for previous = (and (> index 0) (char key (1- index)))
          for next = (and (< (1+ index) (length key)) (char key (1+ index)))
          do (cond
               ((char= char #\_)
                (write-char #\- stream))
               ((and (upper-case-p char)
                     (> index 0)
                     (or (and previous
                              (or (lower-case-p previous)
                                  (digit-char-p previous)))
                         (and previous
                              next
                              (upper-case-p previous)
                              (lower-case-p next))))
                (write-char #\- stream)
                (write-char char stream))
               (t
                (write-char char stream))))))

(defun json-key->keyword (key)
  (intern (string-upcase (camel-json-key->hyphenated-string key)) :keyword))

(defun json-object->keyword-plist (object)
  (loop for (key . value) in object
        append (list (json-key->keyword key)
                     (normalize-json-derived-value value))))

(defun decode-assistant-action (object)
  (let ((payload (or (json-object-value object "payload")
                     (remove nil
                             (append (let ((tool-id (or (json-object-value object "tool-id")
                                                        (json-object-value object "tool_id")
                                                        (json-object-value object "toolId"))))
                                       (when tool-id
                                         (list (cons "toolId" tool-id))))
                                     (let ((arguments (json-object-value object "arguments")))
                                       (when arguments
                                         (list (cons "arguments" arguments))))
                                     (let ((mode (json-object-value object "mode")))
                                       (when mode
                                         (list (cons "mode" mode))))
                                     (let ((expression (json-object-value object "expression")))
                                       (when expression
                                         (list (cons "expression" expression)))))))))
    (let ((normalized-payload (if (json-object-p payload)
                                  (json-object->keyword-plist payload)
                                  (normalize-json-derived-value payload))))
      (when (listp normalized-payload)
        (let ((tool-id (or (getf normalized-payload :TOOL-ID)
                           (getf normalized-payload :TOOL_ID)
                           (getf normalized-payload :tool-id)
                           (getf normalized-payload :tool_id))))
          (when tool-id
            (let ((normalized-tool-id (normalize-tool-id-value tool-id)))
              (when normalized-tool-id
                (setf (getf normalized-payload :TOOL-ID) normalized-tool-id
                      (getf normalized-payload :tool-id) normalized-tool-id
                      (getf normalized-payload :TOOL_ID) normalized-tool-id
                      (getf normalized-payload :tool_id) normalized-tool-id))))))
      (make-assistant-action
       :type (normalize-action-type (json-object-value object "type"))
       :payload normalized-payload))))

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

(defun mutating-eval-action-p (action)
  (and (eq (assistant-action-type action) :eval)
       (let ((payload (assistant-action-payload action)))
         (and (listp payload)
              (or (getf payload :MUTATING)
                  (getf payload :mutating)
                  (eq (getf payload :MODE) :mutate)
                  (eq (getf payload :mode) :mutate))))))

(defun execute-assistant-action (action session &key thread turn operation)
  (let ((*runtime-governance-thread* thread)
        (*runtime-governance-turn* turn)
        (*runtime-governance-operation* operation))
    (declare (special *runtime-governance-thread*
                      *runtime-governance-turn*
                      *runtime-governance-operation*))
    (case (assistant-action-type action)
      (:TOOL
       (let* ((payload (assistant-action-payload action))
              (tool-id (or (getf payload :TOOL-ID)
                           (getf payload :TOOL_ID)))
              (arguments (or (getf payload :ARGUMENTS)
                             (getf payload :arguments))))
         (unless (keywordp tool-id)
           (error "Assistant tool action requires keyword tool id, got ~S" tool-id))
         (service-response-data
          (command-kernel-invoke-service session
                                         (format nil "Execute staged assistant tool action ~A." tool-id)
                                         (kernel-tool-capability-id tool-id)
                                         :payload (list* :tool-id tool-id (or arguments '()))
                                         :context (list :thread-id (and thread (thread-id thread))
                                                        :turn-id (and turn (turn-id turn))
                                                        :operation operation)))))
      (:PATCH
       (service-response-data
        (command-kernel-invoke-service session
                                       "Execute a staged assistant patch action."
                                       :workspace/patch
                                       :payload (assistant-action-payload action)
                                       :context (list :thread-id (and thread (thread-id thread))
                                                      :turn-id (and turn (turn-id turn))
                                                      :operation operation))))
      (:EVAL
       (let ((payload (assistant-action-payload action)))
         (service-response-data
          (command-kernel-invoke-service session
                                         "Execute a staged assistant runtime eval action."
                                         :runtime/eval
                                         :payload (list :form (parse-eval-action-form payload)
                                                        :mutating (mutating-eval-action-p action))
                                         :context (list :thread-id (and thread (thread-id thread))
                                                        :turn-id (and turn (turn-id turn))
                                                        :operation operation)))))
      (t
       (error "Unsupported assistant action type ~S" (assistant-action-type action))))))

(defun execute-assistant-action-list (actions session &key thread turn operation)
  (let ((results
          (mapcar (lambda (action)
                    (list :action action
                          :result (execute-assistant-action action
                                                           session
                                                           :thread thread
                                                           :turn turn
                                                           :operation operation)))
                  actions)))
    (append-session-event session :assistant-actions-executed results)
    results))

(defun execute-assistant-actions (response session)
  (execute-assistant-action-list (assistant-response-actions response) session))

(defmethod stream-request ((provider provider) request event-handler)
  (emit-provider-timing :request-built)
  (let ((response (send-request provider request)))
    (emit-provider-event event-handler :message-start nil)
    (emit-provider-timing :first-delta)
    (emit-provider-event event-handler :message-delta (assistant-response-message response))
    (when (assistant-response-actions response)
      (emit-provider-event event-handler :action-proposal (assistant-response-actions response)))
    (emit-provider-timing :response-finalized)
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
      ((string= provider-name "anthropic")
       (make-instance 'anthropic-provider
                      :model (config-model config)
                      :fast-model (config-fast-model config)
                      :api-base (or (config-api-base config) "https://api.anthropic.com")
                      :api-key (config-api-key config)))
      ((or (string= provider-name "openai")
           (string= provider-name "openai-compatible")
           (string= provider-name "google")
           (string= provider-name "gemini")
           (string= provider-name "google-openai-compatible")
           (string= provider-name "gemini-openai-compatible")
           (string= provider-name "lm-studio")
           (string= provider-name "lmstudio")
           (string= provider-name "local-openai-compatible")
           (string= provider-name "meta-compatible")
           (string= provider-name "meta-openai-compatible"))
       (make-instance 'openai-compatible-provider
                      :provider-id provider-name
                      :model (config-model config)
                      :fast-model (config-fast-model config)
                      :api-base (or (config-api-base config)
                                    (provider-default-api-base provider-name)
                                    "https://api.openai.com/v1")
                      :api-key (config-api-key config)))
      (t
       (error "Unsupported provider ~S. Supported providers: mock, openai-compatible, anthropic, gemini/google, lm-studio, meta-compatible"
              (config-provider config))))))
