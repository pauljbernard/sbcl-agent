(in-package #:sbcl-agent)

(defclass openai-compatible-provider (provider)
  ((provider-id :initarg :provider-id :initform "openai-compatible" :reader openai-provider-id)
   (model :initarg :model :reader openai-provider-model)
   (fast-model :initarg :fast-model :reader openai-provider-fast-model)
   (api-base :initarg :api-base :reader openai-provider-api-base)
   (api-key :initarg :api-key :reader openai-provider-api-key)))

(defclass anthropic-provider (provider)
  ((model :initarg :model :reader anthropic-provider-model)
   (fast-model :initarg :fast-model :reader anthropic-provider-fast-model)
   (api-base :initarg :api-base :reader anthropic-provider-api-base)
   (api-key :initarg :api-key :reader anthropic-provider-api-key)))

(defparameter +stream-actions-marker+ "<<<SBCL-ACTIONS>>>")
(defparameter +stream-actions-end-marker+ "<<<END-SBCL-ACTIONS>>>")

(defparameter +attachment-text-content-limit+ 40000)

(defmethod provider-name ((provider openai-compatible-provider))
  (openai-provider-id provider))

(defmethod provider-capabilities ((provider openai-compatible-provider))
  '(:chat :structured-response :action-proposals :network :streaming))

(defmethod provider-name ((provider anthropic-provider))
  "anthropic")

(defmethod provider-capabilities ((provider anthropic-provider))
  '(:chat :structured-response :action-proposals :network))

(defun governance-blocker-kind-p (entry)
  (member (getf entry :kind)
          '(:blocked :quarantined :awaiting-cold-validation)
          :test #'eq))

(defun governance-conservative-posture-p (request)
  (let ((reasoning-brief (provider-request-reasoning-brief request)))
    (or (> (or (getf (provider-request-runtime-summary request) :open-incident-count) 0)
           0)
        (find-if #'governance-blocker-kind-p
                 (getf reasoning-brief :blockers))
        (getf reasoning-brief :validation-obligations))))

(defun build-openai-governance-directives (request)
  (let ((reasoning-brief (provider-request-reasoning-brief request)))
    (if (governance-conservative-posture-p request)
        (format nil
                "Governance directives: The environment is not currently mutation-clean. Do not propose new governed mutation actions unless the user explicitly asks to override that posture. Prefer read-only inspection, incident review, approval follow-through, validation, reconciliation, or a concrete explanation of what remains blocked. Open incident count: ~D. Hard blockers: ~S. Pending validation obligations: ~S."
                (or (getf (provider-request-runtime-summary request) :open-incident-count) 0)
                (remove-if-not #'governance-blocker-kind-p
                               (or (getf reasoning-brief :blockers) '()))
                (or (getf reasoning-brief :validation-obligations) '()))
        "Governance directives: The environment appears mutation-ready. If you propose a governed mutation, keep it evidence-backed, minimal, and aligned with the planning brief.")))

(defun build-openai-system-prompt ()
  (concatenate
   'string
   "You are an SBCL-based coding assistant operating inside a live Common Lisp shell. "
   "You have structured conversation, runtime, workspace, and policy context through the supplied request object. "
   "The operator interface is Common Lisp, and ordinary Lisp forms are evaluated directly by the host runtime when the operator enters them. "
   "You cannot create effects by prose alone. When execution or inspection is needed, return structured actions. "
   "Return only valid JSON with keys message, actions, and metadata. Actions must be an array. "
   "Supported action types are tool, patch, and eval. "
   "Use an eval action when the user wants Common Lisp code executed in the current image. The eval payload should carry the Lisp form to run. "
   "Use a tool action when you need structured tool access such as reading files or listing directories. "
   "If you need to return a file-like result in the conversation itself, place it under metadata.attachments as an array of attachment objects. "
   "Each attachment object may contain name, media_type, kind, summary, text_content, and data_url. "
   "Use kind=image with a data_url for inline-renderable images. Use kind=text with text_content for text artifacts such as SVG, Markdown, or JSON. "
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
   "If you need to return a file-like result in the conversation itself, place it under metadata.attachments in the post-marker JSON object. "
   "Each attachment object may contain name, media_type, kind, summary, text_content, and data_url. "
   "Use kind=image with a data_url for inline-renderable images. Use kind=text with text_content for text artifacts such as SVG, Markdown, or JSON. "
   "If no actions are needed, emit an empty actions array. "
   "Never omit the markers in streaming mode."))

(defun build-openai-user-prompt-text (request)
  (format nil
          "User prompt: ~A~%~%Operator mode: ~S~%Stream requested: ~S~%~%Conversation context:~%Thread: ~S~%Turn: ~S~%~%Environment context: ~S~%~%Runtime summary: ~S~%~%Workspace summary: ~S~%~%Policy summary: ~S~%~%Retrieved environment dossier: ~S~%~%Canonical cognition bundle: ~S~%~%Reasoning brief: ~S~%~%Planning brief: ~S~%~%Outcome brief: ~S~%~%Session summary: ~S~%~%~A~%~%Treat dossier ranking metadata as advisory prioritization, not as a replacement for the explicit domain payloads. Treat the canonical cognition bundle as the default reasoning loop for this request, including retrieval focus, prior-outcome reuse, execution strategy, validation strategy, and the derived action agenda. When the cognition bundle carries a retrieval focus plan, prioritize those domains first when deciding what evidence matters most for the current request. When the cognition bundle carries a validation plan, treat it as the concrete validation agenda for this request and prefer completing that agenda over proposing fresh governed mutations. When the cognition bundle carries an action agenda, treat it as the ordered list of next steps for this request unless current evidence clearly invalidates one of those steps. Reuse similar prior successes when they fit the current evidence, and explicitly avoid repeating similar prior failures when the cognition bundle surfaces avoidance guidance. Use the reasoning brief to distinguish environment-backed facts, blockers, validation obligations, and uncertainties from assumptions. Use the planning brief as the default execution outline unless the evidence clearly requires deviation. When an outcome brief is present, compare expected phases against observed consequences before concluding success. Interpret references like 'the code you suggested' against the structured conversation context, retrieved dossier, environment refs, and :recent-transcript when available."
          (provider-request-prompt request)
          (provider-request-operator-mode request)
          (provider-request-stream-p request)
          (provider-request-thread-context request)
          (provider-request-turn-context request)
          (provider-request-environment-context request)
          (provider-request-runtime-summary request)
          (provider-request-workspace-summary request)
          (provider-request-policy-summary request)
          (provider-request-retrieval-dossier request)
          (provider-request-cognition-bundle request)
          (provider-request-reasoning-brief request)
          (provider-request-planning-brief request)
          (provider-request-outcome-brief request)
          (provider-request-session-summary request)
          (build-openai-governance-directives request)))

(defun build-openai-user-prompt (request)
  "Compatibility wrapper for tests and callers that still use the older helper name."
  (build-openai-user-prompt-text request))

(defun provider-request-attachment-text (attachment)
  (let ((text-content (getf attachment :text-content)))
    (when text-content
      (if (> (length text-content) +attachment-text-content-limit+)
          (concatenate 'string
                       (subseq text-content 0 +attachment-text-content-limit+)
                       "\n\n[attachment truncated]")
          text-content))))

(defun provider-request-image-attachment-p (attachment)
  (and (eq (getf attachment :kind) :image)
       (stringp (getf attachment :data-url))
       (search "data:" (getf attachment :data-url) :test #'char-equal)))

(defun build-openai-user-message-content (request)
  (let ((attachments (or (provider-request-attachments request) '())))
    (if (null attachments)
        (build-openai-user-prompt-text request)
        (append
         (list (list :type "text"
                     :text (build-openai-user-prompt-text request)))
         (mapcan (lambda (attachment)
                   (let ((name (or (getf attachment :name) "attachment"))
                         (media-type (or (getf attachment :media-type) "application/octet-stream"))
                         (summary (or (getf attachment :summary) "Attachment")))
                     (cond
                       ((provider-request-image-attachment-p attachment)
                        (list (list :type "text"
                                    :text (format nil "Attached image: ~A (~A). ~A"
                                                  name media-type summary))
                              (list :type "image_url"
                                    :image_url (list :url (getf attachment :data-url)))))
                       ((provider-request-attachment-text attachment)
                        (list (list :type "text"
                                    :text (format nil "Attached file: ~A (~A). ~A~%~%~A"
                                                  name
                                                  media-type
                                                  summary
                                                  (provider-request-attachment-text attachment)))))
                       (t
                        (list (list :type "text"
                                    :text (format nil "Attached file: ~A (~A). ~A"
                                                  name media-type summary)))))))
                 attachments)))))

(defun parse-data-url-payload (data-url)
  (when (and (stringp data-url)
             (search "data:" data-url :test #'char-equal)
             (search ";base64," data-url :test #'char-equal))
    (let* ((prefix-end (search ";base64," data-url :test #'char-equal))
           (media-type (subseq data-url 5 prefix-end))
           (payload-start (+ prefix-end (length ";base64,"))))
      (values media-type (subseq data-url payload-start)))))

(defun build-anthropic-user-message-content (request)
  (let ((attachments (or (provider-request-attachments request) '())))
    (append
     (list (list :type "text"
                 :text (build-openai-user-prompt-text request)))
     (mapcan (lambda (attachment)
               (let ((name (or (getf attachment :name) "attachment"))
                     (media-type (or (getf attachment :media-type) "application/octet-stream"))
                     (summary (or (getf attachment :summary) "Attachment")))
                 (cond
                   ((provider-request-image-attachment-p attachment)
                    (multiple-value-bind (parsed-media-type base64-data)
                        (parse-data-url-payload (getf attachment :data-url))
                      (if (and parsed-media-type base64-data)
                          (list (list :type "text"
                                      :text (format nil "Attached image: ~A (~A). ~A"
                                                    name parsed-media-type summary))
                                (list :type "image"
                                      :source (list :type "base64"
                                                    :media_type parsed-media-type
                                                    :data base64-data)))
                          (list (list :type "text"
                                      :text (format nil "Attached image: ~A (~A). ~A"
                                                    name media-type summary))))))
                   ((provider-request-attachment-text attachment)
                    (list (list :type "text"
                                :text (format nil "Attached file: ~A (~A). ~A~%~%~A"
                                              name
                                              media-type
                                              summary
                                              (provider-request-attachment-text attachment)))))
                   (t
                    (list (list :type "text"
                                :text (format nil "Attached file: ~A (~A). ~A"
                                              name media-type summary)))))))
             attachments))))

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

(defun anthropic-request-model (provider request)
  (if (deep-request-p (provider-request-prompt request))
      (anthropic-provider-model provider)
      (or (anthropic-provider-fast-model provider)
          (anthropic-provider-model provider))))

(defun build-openai-request-body (provider request &key (stream nil) (stream-protocol nil))
  (emit-json
   (list :model (openai-request-model provider request)
         :messages (list
                    (list :role "system"
                          :content (if stream-protocol
                                       (build-openai-stream-system-prompt)
                                       (build-openai-system-prompt)))
                    (list :role "user"
                          :content (build-openai-user-message-content request)))
         :stream stream)))

(defun build-anthropic-request-body (provider request)
  (emit-json
   (list :model (anthropic-request-model provider request)
         :max_tokens 4096
         :system (build-openai-system-prompt)
         :messages (list
                    (list :role "user"
                          :content (build-anthropic-user-message-content request))))))

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

(defun extract-anthropic-message-content (response-object)
  (let ((content (json-object-value response-object "content")))
    (or (and content
             (apply #'concatenate 'string
                    (remove nil
                            (mapcar (lambda (entry)
                                      (and (string= (or (json-object-value entry "type") "") "text")
                                           (or (json-object-value entry "text") "")))
                                    content))))
        (let ((error-object (json-object-value response-object "error")))
          (if error-object
              (error "Anthropic API error: ~A" (or (json-object-value error-object "message")
                                                   error-object))
              (error "Could not find assistant content in Anthropic response"))))))

(defun decode-anthropic-content-response (content model)
  (make-assistant-response
   :message content
   :actions '()
   :metadata (list :provider :anthropic
                   :model model)))

(defun openai-compatible-provider-headers (provider)
  (append (list "Content-Type: application/json")
          (if (openai-provider-api-key provider)
              (list (format nil "Authorization: Bearer ~A"
                            (openai-provider-api-key provider)))
              '())))

(defmethod send-request ((provider openai-compatible-provider) request)
  (unless (or (openai-provider-api-key provider)
              (member (provider-name provider)
                      '("lm-studio" "lmstudio" "local-openai-compatible")
                      :test #'string=))
    (error "API key is required for provider ~A" (provider-name provider)))
  (let* ((url (format nil "~A/chat/completions"
                      (string-right-trim "/" (openai-provider-api-base provider))))
         (body (build-openai-request-body provider request))
         (raw-response (curl-json-request-with-headers
                        url
                        (openai-compatible-provider-headers provider)
                        body
                        :label (format nil "~A request" (provider-name provider))))
         (outer-object (parse-json raw-response))
         (content (extract-openai-message-content outer-object)))
    (decode-openai-content-response content (openai-provider-model provider))))

(defmethod send-request ((provider anthropic-provider) request)
  (unless (anthropic-provider-api-key provider)
    (error "ANTHROPIC_API_KEY is required for the anthropic provider"))
  (let* ((url (format nil "~A/v1/messages"
                      (string-right-trim "/" (anthropic-provider-api-base provider))))
         (body (build-anthropic-request-body provider request))
         (raw-response (curl-json-request-with-headers
                        url
                        (list "content-type: application/json"
                              (format nil "x-api-key: ~A" (anthropic-provider-api-key provider))
                              "anthropic-version: 2023-06-01")
                        body
                        :label "Anthropic request"))
         (outer-object (parse-json raw-response))
         (content (extract-anthropic-message-content outer-object)))
    (decode-anthropic-content-response content (anthropic-provider-model provider))))

(defmethod stream-request ((provider openai-compatible-provider) request event-handler)
  (unless (or (openai-provider-api-key provider)
              (member (provider-name provider)
                      '("lm-studio" "lmstudio" "local-openai-compatible")
                      :test #'string=))
    (error "API key is required for provider ~A" (provider-name provider)))
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
    (stream-json-request-with-headers url
                                      (openai-compatible-provider-headers provider)
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
                                                        (setf pending-visible remainder))))))))
                                      :label (format nil "~A streaming request" (provider-name provider)))
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
