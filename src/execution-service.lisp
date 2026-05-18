(in-package #:sbcl-agent)

(defparameter *conversation-execution-debug-log-path*
  #P"/private/tmp/sbcl-agent-conversation-execution-debug.log")

(defun append-conversation-execution-debug-log (stage &rest fields)
  (ignore-errors
    (with-open-file (out *conversation-execution-debug-log-path*
                         :direction :output
                         :if-exists :append
                         :if-does-not-exist :create)
      (format out "~&stage=~A" stage)
      (loop for (key value) on fields by #'cddr
            do (format out " ~A=~S" key value))
      (terpri out))))

(defparameter *stream-event-listener* nil)
(defparameter *default-ask-streaming* nil)

(declaim (special *runtime-governance-thread*
                  *runtime-governance-turn*
                  *runtime-governance-operation*))

(defun plist-value (plist indicator &optional default)
  (if (and (listp plist) (member indicator plist))
      (getf plist indicator)
      default))

(defun option-present-p (plist key)
  (and (listp plist)
       (member key plist)))

(defun remove-plist-key (plist key)
  (cond
    ((null plist) '())
    ((eq (first plist) key)
     (remove-plist-key (cddr plist) key))
    (t
     (list* (first plist)
            (second plist)
            (remove-plist-key (cddr plist) key)))))

(defun immediate-assistant-action-p (action)
  (case (assistant-action-type action)
    (:eval
     (not (mutating-eval-action-p action)))
    (:tool
     (let ((policy-id (assistant-action-policy-id action)))
       (and policy-id
            (not (assistant-action-requires-approval-p action))
            (not (governed-assistant-action-p action)))))
    (t nil)))

(defun split-assistant-actions (actions)
  (let ((immediate '())
        (staged '()))
    (dolist (action actions)
      (if (immediate-assistant-action-p action)
          (push action immediate)
          (push action staged)))
    (values (nreverse immediate) (nreverse staged))))

(defun calculator-focused-surface-context-p (surface-context)
  (let ((calculator (and (listp surface-context)
                         (getf surface-context :calculator))))
    (and (listp calculator)
         (getf calculator :focused))))

(defun editor-focused-surface-context-p (surface-context)
  (let ((editor (and (listp surface-context)
                     (getf surface-context :editor))))
    (and (listp editor)
         (or (getf editor :focused)
             (getf editor :visible)))))

(defun prompt-contains-any-p (prompt needles)
  (some (lambda (needle)
          (search needle prompt :test #'char-equal))
        needles))

(defun digit-char-string-p (value)
  (and (stringp value)
       (= (length value) 1)
       (digit-char-p (char value 0))))

(defun extract-calculator-single-token (prompt)
  (let ((text (string-downcase (or prompt ""))))
    (when (and (search "calculator" text :test #'char=)
               (prompt-contains-any-p text '("press" "select" "enter" "type" "key" "button")))
      (or (loop for char across text
                when (digit-char-p char)
                  return (string char))
          (when (search "plus" text :test #'char=) "+")
          (when (search "minus" text :test #'char=) "-")
          (when (or (search "times" text :test #'char=)
                    (search "multiply" text :test #'char=))
            "*")
          (when (or (search "divide" text :test #'char=)
                    (search "over" text :test #'char=))
            "/")))))

(defun replace-all-substrings (text old new)
  (with-output-to-string (out)
    (loop with old-length = (length old)
          for start = 0 then (+ position old-length)
          for position = (search old text :start2 start :test #'char-equal)
          do (if position
                 (progn
                   (write-string text out :start start :end position)
                   (write-string new out))
                 (progn
                   (write-string text out :start start)
                   (loop-finish))))))

(defun extract-first-inline-code-snippet (prompt)
  (let* ((text (or prompt ""))
         (triple-start (search "```" text :test #'char=)))
    (when triple-start
      (let ((triple-end (search "```" text :start2 (+ triple-start 3) :test #'char=)))
        (when triple-end
          (return-from extract-first-inline-code-snippet
            (string-trim '(#\Space #\Tab #\Newline)
                         (subseq text (+ triple-start 3) triple-end))))))
    (let ((single-start (position #\` text)))
      (when single-start
        (let ((single-end (position #\` text :start (1+ single-start))))
          (when single-end
            (string-trim '(#\Space #\Tab #\Newline)
                         (subseq text (1+ single-start) single-end))))))))

(defun extract-first-parenthesized-form (prompt)
  (let* ((text (or prompt ""))
         (start (position #\( text)))
    (when start
      (loop with depth = 0
            for index from start below (length text)
            for char = (char text index)
            do (cond
                 ((char= char #\()
                  (incf depth))
                 ((char= char #\))
                  (decf depth)
                  (when (<= depth 0)
                    (return (subseq text start (1+ index))))))
            finally (return nil)))))

(defun editor-control-request-p (prompt)
  (let ((text (string-downcase (or prompt ""))))
    (and (or (search "editor" text :test #'char=)
             (search "edit surface" text :test #'char=)
             (search "editor surface" text :test #'char=))
         (prompt-contains-any-p text '("add" "append" "insert" "put")))))

(defun implied-editor-append-request-p (prompt)
  (let ((text (string-downcase (or prompt ""))))
    (and (prompt-contains-any-p text '("add" "append" "insert" "put"))
         (or (extract-first-inline-code-snippet prompt)
             (extract-first-parenthesized-form prompt)
             (search "code:" text :test #'char=)))))

(defun extract-editor-append-text (prompt)
  (or (extract-first-inline-code-snippet prompt)
      (extract-first-parenthesized-form prompt)
      (let* ((text (or prompt ""))
             (lower (string-downcase text))
             (code-index (search "code:" lower :test #'char=)))
        (when code-index
          (let* ((start (+ code-index (length "code:")))
                 (tail (string-trim '(#\Space #\Tab #\Newline) (subseq text start)))
                 (tail-lower (string-downcase tail))
                 (end (or (search " to the editor" tail-lower :test #'char=)
                          (search " into the editor" tail-lower :test #'char=)
                          (search " in the editor" tail-lower :test #'char=)
                          (search " editor surface" tail-lower :test #'char=)
                          (length tail))))
            (string-trim '(#\Space #\Tab #\Newline #\" #\')
                         (subseq tail 0 end)))))))

(defun normalize-calculator-expression-text (prompt)
  (let ((text (string-downcase (or prompt ""))))
    (dolist (pair '(("multiplied by" . "*")
                    ("times" . "*")
                    ("plus" . "+")
                    ("minus" . "-")
                    ("divided by" . "/")
                    ("divide by" . "/")
                    ("over" . "/")
                    ("open paren" . "(")
                    ("close paren" . ")")))
      (setf text (replace-all-substrings text (car pair) (cdr pair))))
    text))

(defun extract-calculator-expression (prompt)
  (let* ((text (normalize-calculator-expression-text prompt))
         (chars
           (loop for char across text
                 when (or (digit-char-p char)
                          (member char '(#\+ #\- #\* #\/ #\( #\) #\.)))
                   collect char into kept
                 when (and kept
                           (or (char= char #\Space)
                               (char= char #\Tab)
                               (char= char #\Newline)))
                   collect #\Space into kept
                 finally (return kept)))
         (raw (string-trim " " (coerce chars 'string))))
    (when (and (> (length raw) 0)
               (some #'digit-char-p raw)
               (or (prompt-contains-any-p text '("evaluate" "calculate" "compute"))
                   (find-if (lambda (char)
                              (member char '(#\+ #\- #\* #\/) :test #'char=))
                            raw)))
      (replace-all-substrings raw " " ""))))

(defun calculator-expression-request-p (prompt)
  (let ((text (string-downcase (or prompt ""))))
    (and (search "calculator" text :test #'char=)
         (or (prompt-contains-any-p text '("evaluate" "calculate" "compute"))
             (find-if (lambda (char)
                        (member char '(#\+ #\- #\* #\/ #\( #\)) :test #'char=))
                      text)
             (prompt-contains-any-p text '("times" "plus" "minus" "divide" "multiplied"))))))

(defun plan-calculator-evaluate-expression-request (prompt surface-context surface-actions)
  (when (calculator-focused-surface-context-p surface-context)
    (let ((expression (extract-calculator-expression prompt)))
      (when (and (calculator-expression-request-p prompt)
                 expression
                 (> (length expression) 0))
        (list (make-governed-desktop-task-request
               :requester :context-chat
               :target :calculator
               :operation :evaluate-expression
               :capability :calculator-control
               :payload (list :expression expression)
               :surface-context surface-context
               :surface-actions surface-actions
               :metadata (list :prompt prompt
                               :actor-slice :context-chat-calculator-v1)))))))

(defun plan-calculator-append-token-request (prompt surface-context surface-actions)
  (when (calculator-focused-surface-context-p surface-context)
    (let ((token (extract-calculator-single-token prompt)))
      (when (and token (= (length token) 1))
        (list (make-governed-desktop-task-request
               :requester :context-chat
               :target :calculator
               :operation :append-token
               :capability :calculator-control
               :payload (list :token token)
               :surface-context surface-context
               :surface-actions surface-actions
               :metadata (list :prompt prompt
                               :actor-slice :context-chat-calculator-v1)))))))

(defun plan-editor-append-text-request (prompt surface-context surface-actions)
  (when (and (editor-focused-surface-context-p surface-context)
             (or (editor-control-request-p prompt)
                 (implied-editor-append-request-p prompt)))
    (let ((text (extract-editor-append-text prompt)))
      (when (and text (> (length text) 0))
        (let* ((editor-context (and (listp surface-context)
                                    (getf surface-context :editor)))
               (scope-id (and (listp editor-context)
                              (or (getf editor-context :scope-id)
                                  (getf editor-context :scopeId)
                                  (getf editor-context :SCOPE-ID)
                                  (getf editor-context :SCOPEID))))
               (buffer-id (and (listp editor-context)
                               (or (getf editor-context :buffer-id)
                                   (getf editor-context :bufferId)
                                   (getf editor-context :BUFFER-ID)
                                   (getf editor-context :BUFFERID))))
               (pending-action-id (make-pending-action-id :editor)))
          (list (make-governed-desktop-task-request
                 :requester :context-chat
                 :target :editor
                 :operation :append-text
                 :capability :workspace-write
                 :payload (list :text text)
                 :surface-context surface-context
                 :surface-actions surface-actions
                 :metadata (append (list :prompt prompt
                                         :actor-slice :context-chat-editor-v1
                                         :pending-action-id pending-action-id)
                                   (when scope-id
                                     (list :receiver-scope scope-id
                                           :scope-id scope-id))
                                   (when buffer-id
                                     (list :buffer-id buffer-id))))))))))

(defun compatibility-assistant-actions-for-desktop-task-request (request)
  (let ((target (desktop-task-request-target request))
        (operation (desktop-task-request-operation request))
        (payload (desktop-task-request-payload request)))
    (cond
      ((and (eq target :calculator)
            (eq operation :evaluate-expression))
       (let ((expression (getf payload :expression)))
         (when expression
           (list (make-assistant-action
                  :type :tool
                  :payload (list :tool-id :calculator/set-expression
                                 :arguments (list :expression expression)))
                 (make-assistant-action
                  :type :tool
                  :payload (list :tool-id :calculator/evaluate
                                 :arguments (list :expression expression)))))))
      ((and (eq target :calculator)
            (eq operation :append-token))
       (let ((token (getf payload :token)))
         (when token
           (list (make-assistant-action
                  :type :tool
                  :payload (list :tool-id :calculator/append-token
                                 :arguments (list :token token)))))))
      ((and (eq target :editor)
            (eq operation :append-text))
       (let ((text (getf payload :text)))
         (when text
           (list (make-assistant-action
                  :type :tool
                  :payload (list :tool-id :editor/append-text
                                 :arguments (list :text text)))))))
      ((and (eq target :workspace)
            (eq operation :apply-patch))
       (let ((operations (cond
                           ((option-present-p payload :operations)
                            (getf payload :operations))
                           ((option-present-p payload :OPERATIONS)
                            (getf payload :OPERATIONS))
                           (t payload))))
         (when (listp operations)
           (list (make-assistant-action
                  :type :patch
                  :payload operations)))))
      (t nil))))

(defun compatibility-response-actions-from-governed-desktop-task-requests (prompt surface-context)
  (mapcan #'compatibility-assistant-actions-for-desktop-task-request
          (plan-governed-desktop-task-requests prompt surface-context nil)))

(defun effective-response-actions (response prompt surface-context session)
  (let ((actions (assistant-response-actions response)))
    (or actions
        (let ((fallback (compatibility-response-actions-from-governed-desktop-task-requests
                         prompt
                         surface-context)))
          (when fallback
            (append-session-event session
                                  :assistant-action-fallback-synthesized
                                  (list :prompt prompt
                                        :source :desktop-task-protocol
                                        :action-count (length fallback)
                                        :actions fallback)
                                  :family :assistant
                                  :visibility :operator))
          fallback)
        '())))

(defun calculator-action-expression (action)
  (let* ((payload (assistant-action-payload action))
         (arguments (or (getf payload :arguments)
                        (getf payload :ARGUMENTS))))
    (or (and (listp arguments) (getf arguments :expression))
        (and (listp arguments) (getf arguments :EXPRESSION)))))

(defun calculator-action-token (action)
  (let* ((payload (assistant-action-payload action))
         (arguments (or (getf payload :arguments)
                        (getf payload :ARGUMENTS))))
    (or (and (listp arguments) (getf arguments :token))
        (and (listp arguments) (getf arguments :TOKEN)))))

(defun direct-calculator-assistant-message (actions results)
  (let* ((first-action (first actions))
         (last-result (and results (getf (first (last results)) :result)))
         (latest-result-summary (and (listp last-result) (getf last-result :summary)))
         (latest-display-value (and (listp last-result) (getf last-result :display-value)))
         (token (and first-action (calculator-action-token first-action)))
         (expression (or (and first-action (calculator-action-expression first-action))
                         (and (> (length actions) 1)
                              (calculator-action-expression (second actions))))))
    (cond
      ((and expression latest-display-value)
       (format nil
               "Set the calculator expression to ~S and evaluated it. Result: ~A."
               expression
               latest-display-value))
      ((and expression latest-result-summary)
       (format nil
               "Set the calculator expression to ~S and evaluated it. ~A"
               expression
               latest-result-summary))
      (token
       (format nil
               "Appended the token ~S in the focused calculator expression buffer."
               token))
      (expression
       (format nil
               "Set the focused calculator expression to ~S."
               expression))
      (t
       "Updated the focused calculator."))))

(defun direct-editor-assistant-message (actions)
  (let* ((first-action (first actions))
         (payload (and first-action (assistant-action-payload first-action)))
         (arguments (and payload
                         (or (getf payload :arguments)
                             (getf payload :ARGUMENTS))))
         (text (and (listp arguments)
                    (or (getf arguments :text)
                        (getf arguments :TEXT)))))
    (if text
        (format nil "Appended ~A to the active editor buffer."
                (if (> (length text) 120)
                    (format nil "~S..." (subseq text 0 120))
                    (format nil "~S" text)))
        "Updated the active editor buffer.")))

(defun direct-runtime-assistant-message (results fallback-summary)
  (or (some (lambda (entry)
              (let ((native-result (getf entry :native-result)))
                (and (listp native-result)
                     (or (getf native-result :summary)
                         (getf native-result :SUMMARY)))))
            results)
      fallback-summary))

(defun runtime-outbox-entry-for-records (session records)
  (let ((request-ids (remove nil
                             (mapcar #'desktop-task-record-request-id records))))
    (find-if (lambda (entry)
               (let ((request-id (actor-mailbox-entry-request-id entry)))
                 (and request-id
                      (member request-id request-ids :test #'string=))))
             (actor-mailbox-entries session :runtime-outbox))))

(defun runtime-outbox-payload-for-records (session records)
  (let ((entry (runtime-outbox-entry-for-records session records)))
    (and entry (actor-mailbox-entry-payload entry))))

(defun runtime-outbox-reply-summary-for-records (session records)
  (let ((entry (runtime-outbox-entry-for-records session records)))
    (and entry (actor-mailbox-entry-summary entry))))

(defun runtime-outbox-assistant-message (session records fallback-summary)
  (let ((payload (runtime-outbox-payload-for-records session records)))
    (or (and (listp payload)
             (or (getf payload :summary)
                 (getf payload :SUMMARY)))
        fallback-summary)))

(defun runtime-actor-flow-for-records (session records)
  (let* ((session-id (or (some #'desktop-task-record-session-id records)
                         (agent-session-id session)))
         (actor-message-id
           (some (lambda (record)
                   (let ((message (desktop-task-record-actor-message record)))
                     (and message (actor-message-id message))))
                 records)))
    (service-response-data
     (query-desktop-task-actor-flow-service session
                                            :session-id session-id
                                            :actor-message-id actor-message-id
                                            :latest-only-p t))))

(defun runtime-result-output-metadata (runtime-result-payload)
  (when (listp runtime-result-payload)
    (let ((values (or (getf runtime-result-payload :values)
                      (getf runtime-result-payload :VALUES))))
      (append (when (member :result runtime-result-payload)
                (list :result (getf runtime-result-payload :result)))
              (when values
                (list :values values))
              (when (member :package runtime-result-payload)
                (list :package (getf runtime-result-payload :package)))
              (when (member :form runtime-result-payload)
                (list :form (getf runtime-result-payload :form)))))))

(defun native-desktop-task-result-summary (native-result fallback-summary)
  (or (and (listp native-result)
           (or (getf native-result :summary)
               (getf native-result :SUMMARY)))
      fallback-summary))

(defun action-result-summary-message (results fallback-summary)
  (or (some (lambda (entry)
              (let ((payload (getf entry :result)))
                (and (listp payload)
                     (or (getf payload :summary)
                         (getf payload :SUMMARY)
                         (getf payload :message)
                         (getf payload :MESSAGE)))))
            results)
      fallback-summary))

(defun desktop-task-mcp-request-envelope (manifest request resolution)
  (json-safe-value
   (list :protocol-version +desktop-task-protocol-version+
         :task (list :request-id (desktop-task-request-id request)
                     :requester (desktop-task-request-requester request)
                     :target (desktop-task-request-target request)
                     :operation (desktop-task-request-operation request)
                     :capability (or (desktop-task-request-capability request)
                                     (desktop-task-manifest-capability manifest))
                     :idempotency-key (desktop-task-request-idempotency-key request)
                     :created-at (desktop-task-request-created-at request))
         :manifest (desktop-task-manifest-summary manifest)
         :resolution (desktop-task-resolution-summary-data resolution)
         :payload (desktop-task-request-payload request)
         :surface-context (desktop-task-request-surface-context request)
         :surface-actions (desktop-task-request-surface-actions request)
         :metadata (desktop-task-request-metadata request))))

(defun desktop-task-mcp-environment (config)
  (let ((path (ignore-errors (getenv "PATH")))
        (home (ignore-errors (getenv "HOME"))))
    (append
     (remove nil (list (and path (format nil "PATH=~A" path))
                       (and home (format nil "HOME=~A" home))))
     (loop for entry in (or (mcp-server-config-environment-variables config) '())
           for key = (cond
                       ((consp entry) (car entry))
                       ((and (listp entry) (>= (length entry) 2)) (first entry))
                       (t nil))
           for value = (cond
                         ((consp entry) (cdr entry))
                         ((and (listp entry) (>= (length entry) 2)) (second entry))
                         (t nil))
           when key
             collect (format nil "~A=~A" key (or value ""))))))

(defun desktop-task-mcp-body-pathname ()
  (merge-pathnames
   (format nil "sbcl-agent-mcp-body-~D-~A.json"
           (get-universal-time)
           (gensym "MCP-BODY-"))
   (uiop:temporary-directory)))

(defun write-desktop-task-mcp-body-file (body)
  (let ((body-path (desktop-task-mcp-body-pathname)))
    (ensure-directories-exist body-path)
    (with-open-file (stream body-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string body stream))
    body-path))

(defun normalize-mcp-desktop-task-response (response fallback-summary)
  (let* ((decoded (cond
                    ((stringp response)
                     (ignore-errors (parse-json response)))
                    (t response)))
         (normalized (cond
                       ((json-object-p decoded)
                        (json-object->keyword-plist decoded))
                       ((listp decoded) decoded)
                       (t '())))
         (result (let ((payload (or (getf normalized :result)
                                    (getf normalized :RESULT))))
                   (cond
                     ((json-object-p payload)
                      (json-object->keyword-plist payload))
                     (t payload))))
         (metadata (let ((payload (or (getf normalized :metadata)
                                      (getf normalized :METADATA))))
                     (cond
                       ((json-object-p payload)
                        (json-object->keyword-plist payload))
                       ((listp payload) payload)
                       (t '()))))
         (action-results (copy-list
                          (or (getf normalized :action-results)
                              (getf normalized :ACTION-RESULTS)
                              '())))
         (status (or (getf normalized :status)
                     (getf normalized :STATUS)
                     :completed))
         (summary (or (getf normalized :summary)
                      (getf normalized :SUMMARY)
                      (and (listp result)
                           (or (getf result :summary)
                               (getf result :SUMMARY)
                               (getf result :message)
                               (getf result :MESSAGE)))
                      fallback-summary)))
    (list :status status
          :summary summary
          :result result
          :metadata metadata
          :action-results action-results)))

(defun invoke-stdio-mcp-server-config (config body)
  (unless (mcp-server-config-command config)
    (error "MCP stdio server ~A is missing :command."
           (mcp-server-config-id config)))
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream))
        (body-path (write-desktop-task-mcp-body-file body)))
    (unwind-protect
         (with-open-file (input body-path :direction :input)
           (let ((process (sb-ext:run-program
                           (mcp-server-config-command config)
                           (copy-list (or (mcp-server-config-arguments config) '()))
                           :search t
                           :input input
                           :output stdout
                           :error stderr
                           :wait t
                           :directory (mcp-server-config-working-directory config)
                           :environment (desktop-task-mcp-environment config))))
             (let ((exit-code (sb-ext:process-exit-code process))
                   (stdout-string (get-output-stream-string stdout))
                   (stderr-string (get-output-stream-string stderr)))
               (unless (zerop exit-code)
                 (error "MCP stdio server ~A exited with code ~D: ~A"
                        (mcp-server-config-id config)
                        exit-code
                        stderr-string))
               stdout-string)))
      (when (probe-file body-path)
        (delete-file body-path)))))

(defun invoke-http-mcp-server-config (config body)
  (unless (mcp-server-config-endpoint config)
    (error "MCP HTTP server ~A is missing :endpoint."
           (mcp-server-config-id config)))
  (curl-json-request-with-headers
   (mcp-server-config-endpoint config)
   (list "Content-Type: application/json")
   body
   :label (format nil "MCP HTTP request (~A)" (mcp-server-config-id config))))

(defun invoke-internal-desktop-task-backend (manifest request resolution session)
  (declare (ignore manifest request))
  (let ((actions (copy-list (desktop-task-resolution-actions resolution))))
    (cond
      ((null actions)
       (list :summary (desktop-task-resolution-summary resolution)
             :action-results '()))
      ((some #'assistant-action-requires-approval-p actions)
       (error "Internal desktop task backend invocation requires approval before execution for ~S/~S."
              (desktop-task-resolution-target resolution)
              (desktop-task-resolution-operation resolution)))
      (t
       (let ((results (execute-assistant-action-list actions session)))
         (list :summary (action-result-summary-message results
                                                      (desktop-task-resolution-summary resolution))
               :action-results results))))))

(defun invoke-mcp-desktop-task-backend (manifest request resolution session)
  (let* ((server-id (desktop-task-manifest-backend-ref manifest))
         (environment (and session (session-bound-environment session)))
         (config (and (stringp server-id)
                      (find-desktop-task-mcp-server-config server-id environment))))
    (unless config
      (error "Unknown MCP server config ~S for desktop task ~S/~S."
             server-id
             (desktop-task-request-target request)
             (desktop-task-request-operation request)))
    (unless (mcp-server-config-enabled-p config)
      (error "MCP server ~A is disabled."
             (mcp-server-config-id config)))
    (let* ((body (emit-json
                  (desktop-task-mcp-request-envelope manifest request resolution)))
           (raw-response
             (case (mcp-server-config-transport config)
               (:stdio
                (invoke-stdio-mcp-server-config config body))
               (:http
                (invoke-http-mcp-server-config config body))
               (otherwise
                (error "Unsupported MCP transport ~S for server ~A."
                       (mcp-server-config-transport config)
                       (mcp-server-config-id config))))))
      (normalize-mcp-desktop-task-response raw-response
                                           (desktop-task-resolution-summary resolution)))))

(register-desktop-task-backend-invoker :internal
                                       #'invoke-internal-desktop-task-backend)

(register-desktop-task-backend-invoker :mcp
                                       #'invoke-mcp-desktop-task-backend)

(defun resolve-calculator-desktop-task-request (request session)
  (declare (ignore session))
  (let* ((operation (desktop-task-request-operation request))
         (payload (desktop-task-request-payload request)))
    (case operation
      (:evaluate-expression
       (let ((expression (getf payload :expression)))
         (make-desktop-task-resolution-native
          request
          (format nil "Evaluate ~A in the calculator." expression)
          (lambda (active-session)
            (service-response-data
             (command-calculator-evaluate-service active-session expression)))
          :metadata (list :expression expression
                          :receiver-actor :calculator
                          :receiver-mode :actor-server
                          :actor-slice :context-chat-calculator-v1))))
      (:append-token
       (let ((token (getf payload :token)))
         (make-desktop-task-resolution-native
          request
          (format nil "Append token ~A in the calculator." token)
          (lambda (active-session)
            (service-response-data
             (command-calculator-append-token-service active-session token)))
          :metadata (list :token token
                          :receiver-actor :calculator
                          :receiver-mode :actor-server
                          :actor-slice :context-chat-calculator-v1))))
      (otherwise
       (error "Unsupported calculator desktop task operation ~S" operation)))))

(defun resolve-editor-desktop-task-request (request session)
  (declare (ignore session))
  (let* ((operation (desktop-task-request-operation request))
         (payload (desktop-task-request-payload request))
         (surface-context (desktop-task-request-surface-context request))
         (editor-context (and (listp surface-context)
                              (getf surface-context :editor))))
    (case operation
      (:append-text
       (let ((text (getf payload :text))
             (pending-action-id (or (getf (desktop-task-request-metadata request) :pending-action-id)
                                    (getf (desktop-task-request-metadata request) :PENDING-ACTION-ID)))
             (scope-id (or (and (listp editor-context)
                                (or (getf editor-context :scope-id)
                                    (getf editor-context :scopeId)
                                    (getf editor-context :SCOPE-ID)
                                    (getf editor-context :SCOPEID)))
                           nil))
             (buffer-id (or (and (listp editor-context)
                                 (or (getf editor-context :buffer-id)
                                     (getf editor-context :bufferId)
                                     (getf editor-context :BUFFER-ID)
                                     (getf editor-context :BUFFERID)))
                            nil))
             (package-name (or (and (listp editor-context)
                                    (or (getf editor-context :package-name)
                                        (getf editor-context :packageName)
                                        (getf editor-context :PACKAGE-NAME)
                                        (getf editor-context :PACKAGENAME)))
                               nil)))
         (make-desktop-task-resolution-native
          request
          "Append text to the active editor buffer."
          (lambda (active-session)
            (let* ((response (command-kernel-invoke-service active-session
                                                            "Append governed text to the active editor buffer."
                                                            :editor/append-text
                                                            :authority :governed-desktop-task
                                                            :context (append (when pending-action-id
                                                                               (list :pending-action-id pending-action-id))
                                                                             (when scope-id
                                                                               (list :scope-id scope-id))
                                                                             (when buffer-id
                                                                               (list :buffer-id buffer-id))
                                                                             (when package-name
                                                                               (list :package-name package-name)))
                                                            :payload (append (list :text text)
                                                                             (when scope-id
                                                                               (list :scope-id scope-id))
                                                                             (when buffer-id
                                                                               (list :buffer-id buffer-id))
                                                                             (when package-name
                                                                               (list :package-name package-name))
                                                                             (when pending-action-id
                                                                               (list :pending-action-id pending-action-id)))))
                   (command-result (service-response-data response))
                   (kernel-metadata (service-response-metadata response))
                   (execution-id (getf kernel-metadata :execution-id)))
              (append command-result
                      (list :kernel-execution-id execution-id
                            :kernel-governance-preflight
                            (getf kernel-metadata :governance-preflight)))))
          :metadata (append (list :text text)
                            '(:receiver-actor :editor
                              :receiver-mode :actor-server
                              :actor-slice :context-chat-editor-v1)
                            (when pending-action-id (list :pending-action-id pending-action-id))
                            (when scope-id (list :scope-id scope-id))
                            (when buffer-id (list :buffer-id buffer-id))
                            (when package-name (list :package-name package-name))))))
      (otherwise
       (error "Unsupported editor desktop task operation ~S" operation)))))

(defun resolve-runtime-desktop-task-request (request session)
  (declare (ignore session))
  (let* ((operation (desktop-task-request-operation request))
         (payload (desktop-task-request-payload request))
         (request-metadata (desktop-task-request-metadata request)))
    (case operation
      (:evaluate-form
       (let ((form (getf payload :form))
             (package-name (or (getf payload :package)
                               (getf payload :PACKAGE)
                               (getf payload :package-name)
                               (getf payload :PACKAGE-NAME)))
             (reason (or (getf payload :reason)
                         (getf payload :REASON)
                         :direct-form)))
         (make-desktop-task-resolution-native
          request
          (format nil "Evaluate ~A in the active runtime." form)
          (lambda (active-session)
            (let* ((response (command-kernel-invoke-service active-session
                                                            (format nil "Evaluate ~A in the live runtime." form)
                                                            :runtime/eval
                                                            :authority :governed-desktop-task
                                                            :context (append (when (or (getf request-metadata :thread-id)
                                                                                       (getf request-metadata :THREAD-ID))
                                                                               (list :thread-id (or (getf request-metadata :thread-id)
                                                                                                    (getf request-metadata :THREAD-ID))))
                                                                             (when (or (getf request-metadata :turn-id)
                                                                                       (getf request-metadata :TURN-ID))
                                                                               (list :turn-id (or (getf request-metadata :turn-id)
                                                                                                  (getf request-metadata :TURN-ID)))))
                                                            :payload (append (list :form form)
                                                                             (when package-name
                                                                               (list :package package-name)))))
                   (command-result (service-response-data response))
                   (kernel-metadata (service-response-metadata response))
                   (summary (runtime-eval-assistant-message command-result reason))
                   (execution-id (getf kernel-metadata :execution-id)))
              (append command-result
                      (list :summary summary
                            :kernel-execution-id execution-id
                            :kernel-governance-preflight
                            (getf kernel-metadata :governance-preflight)))))
          :metadata (append (list :form form
                                  :reason reason
                                  :receiver-actor :runtime
                                  :receiver-mode :actor-server
                                  :actor-slice :context-chat-runtime-v1)
                            (when package-name
                              (list :package-name package-name))
                            (when (fboundp 'default-runtime-id)
                              (list :runtime-id (default-runtime-id)))))))
      (:reload-file
       (let ((path (or (getf payload :path)
                       (getf payload :PATH))))
         (unless path
           (error "Runtime reload desktop task requires a path payload."))
         (make-desktop-task-resolution-native
          request
          (format nil "Reload ~A into the active runtime." path)
          (lambda (active-session)
            (let* ((response (command-kernel-invoke-service active-session
                                                            (format nil "Reload ~A into the live runtime." path)
                                                            :runtime/reload-file
                                                            :authority :governed-desktop-task
                                                            :context (append (when (or (getf request-metadata :thread-id)
                                                                                       (getf request-metadata :THREAD-ID))
                                                                               (list :thread-id (or (getf request-metadata :thread-id)
                                                                                                    (getf request-metadata :THREAD-ID))))
                                                                             (when (or (getf request-metadata :turn-id)
                                                                                       (getf request-metadata :TURN-ID))
                                                                               (list :turn-id (or (getf request-metadata :turn-id)
                                                                                                  (getf request-metadata :TURN-ID)))))
                                                            :payload (list :path path)))
                   (command-result (service-response-data response))
                   (kernel-metadata (service-response-metadata response))
                   (execution-id (getf kernel-metadata :execution-id)))
              (append command-result
                      (list :kernel-execution-id execution-id
                            :kernel-governance-preflight
                            (getf kernel-metadata :governance-preflight)))))
          :metadata (append (list :path path
                                  :receiver-actor :runtime
                                  :receiver-mode :actor-server
                                  :actor-slice :context-chat-runtime-v1)
                            (when (fboundp 'default-runtime-id)
                              (list :runtime-id (default-runtime-id)))))))
      (otherwise
       (error "Unsupported runtime desktop task operation ~S" operation)))))

(defun workspace-patch-summary (results)
  (let ((count (length (or results '()))))
    (cond
      ((= count 1)
       "Applied a governed workspace patch to 1 file.")
      ((> count 1)
       (format nil "Applied a governed workspace patch to ~D files." count))
      (t
       "Applied a governed workspace patch."))))

(defun resolve-workspace-desktop-task-request (request session)
  (declare (ignore session))
  (let* ((operation (desktop-task-request-operation request))
         (payload (desktop-task-request-payload request))
         (request-metadata (desktop-task-request-metadata request)))
    (case operation
      (:apply-patch
       (let ((operations (cond
                           ((option-present-p payload :operations)
                            (getf payload :operations))
                           ((option-present-p payload :OPERATIONS)
                            (getf payload :OPERATIONS))
                           (t payload))))
         (unless (listp operations)
           (error "Workspace patch desktop task requires a list of operations, got ~S" operations))
         (make-desktop-task-resolution-native
          request
          "Apply a governed workspace patch."
          (lambda (active-session)
            (let* ((response (command-kernel-invoke-service active-session
                                                            "Apply a governed workspace patch."
                                                            :workspace/patch
                                                            :authority :governed-desktop-task
                                                            :context (append (when (or (getf request-metadata :thread-id)
                                                                                       (getf request-metadata :THREAD-ID))
                                                                               (list :thread-id (or (getf request-metadata :thread-id)
                                                                                                    (getf request-metadata :THREAD-ID))))
                                                                             (when (or (getf request-metadata :turn-id)
                                                                                       (getf request-metadata :TURN-ID))
                                                                               (list :turn-id (or (getf request-metadata :turn-id)
                                                                                                  (getf request-metadata :TURN-ID)))))
                                                            :payload operations))
                   (patch-result (service-response-data response))
                   (results (or (getf patch-result :patch) '()))
                   (kernel-metadata (service-response-metadata response))
                   (execution-id (getf kernel-metadata :execution-id)))
              (append patch-result
                      (list :summary (workspace-patch-summary results)
                            :kernel-execution-id execution-id
                            :kernel-governance-preflight
                            (getf kernel-metadata :governance-preflight)))))
          :metadata (list :operation-count (length operations)
                          :receiver-actor :workspace
                          :receiver-mode :actor-server
                          :actor-slice :context-chat-workspace-v1))))
      (otherwise
       (error "Unsupported workspace desktop task operation ~S" operation)))))

(register-desktop-task-operation
 :calculator
 :evaluate-expression
 #'resolve-calculator-desktop-task-request
 :capability :calculator-control
 :description "Evaluate a calculator expression in the active calculator surface."
 :request-schema '(:expression string)
 :result-schema '(:display-value string :summary string)
 :approval-policy :implicit
 :execution-mode :synchronous
 :retry-policy '(:max-attempts 1 :retryable-p nil)
 :backend-kind :internal
 :backend-ref :calculator-surface
 :tags '(:surface :calculator :expression))

(register-desktop-task-planner
 :calculator
 :evaluate-expression
 #'plan-calculator-evaluate-expression-request)

(register-desktop-task-operation
 :calculator
 :append-token
 #'resolve-calculator-desktop-task-request
 :capability :calculator-control
 :description "Append a token into the active calculator expression."
 :request-schema '(:token string)
 :result-schema '(:summary string)
 :approval-policy :implicit
 :execution-mode :synchronous
 :retry-policy '(:max-attempts 1 :retryable-p nil)
 :backend-kind :internal
 :backend-ref :calculator-surface
 :tags '(:surface :calculator :token))

(register-desktop-task-planner
 :calculator
 :append-token
 #'plan-calculator-append-token-request)

(register-desktop-task-operation
 :editor
 :append-text
 #'resolve-editor-desktop-task-request
 :capability :workspace-write
 :description "Append text to the active editor buffer."
 :request-schema '(:text string)
 :result-schema '(:summary string)
 :approval-policy :explicit
 :execution-mode :synchronous
 :retry-policy '(:max-attempts 1 :retryable-p nil)
 :backend-kind :internal
 :backend-ref :editor-surface
 :tags '(:surface :editor :write))

(register-desktop-task-planner
 :editor
 :append-text
 #'plan-editor-append-text-request)

(register-desktop-task-operation
 :runtime
 :evaluate-form
 #'resolve-runtime-desktop-task-request
 :capability :runtime-eval-safe
 :description "Evaluate a Common Lisp form in the active runtime package."
 :request-schema '(:form string :package-name string :reason keyword)
 :result-schema '(:summary string :result t :values list)
 :approval-policy :implicit
 :execution-mode :synchronous
 :retry-policy '(:max-attempts 1 :retryable-p nil)
 :backend-kind :internal
 :backend-ref :runtime-primary
 :tags '(:runtime :eval :actor))

(register-desktop-task-operation
 :runtime
 :reload-file
 #'resolve-runtime-desktop-task-request
 :capability :runtime-reload
 :description "Reload a workspace file into the active runtime."
 :request-schema '(:path string)
 :result-schema '(:summary string :path string)
 :approval-policy :explicit
 :execution-mode :synchronous
 :retry-policy '(:max-attempts 1 :retryable-p nil)
 :backend-kind :internal
 :backend-ref :runtime-primary
 :tags '(:runtime :reload :actor))

(register-desktop-task-operation
 :workspace
 :apply-patch
 #'resolve-workspace-desktop-task-request
 :capability :workspace-write
 :description "Apply a governed patch to one or more workspace files."
 :request-schema '(:operations list)
 :result-schema '(:summary string :patch list)
 :approval-policy :explicit
 :execution-mode :synchronous
 :retry-policy '(:max-attempts 1 :retryable-p nil)
 :backend-kind :internal
 :backend-ref :workspace-surface
 :tags '(:surface :workspace :patch :write))

(defun desktop-task-executor-kind (requests)
  (let ((targets (remove-duplicates (mapcar #'desktop-task-request-target requests) :test #'eq)))
    (cond
      ((and (= (length targets) 1) (eq (first targets) :calculator)) :calculator)
      ((and (= (length targets) 1) (eq (first targets) :runtime)) :runtime)
      ((and (= (length targets) 1)
            (member (first targets) '(:editor :workspace) :test #'eq))
       :workspace)
      (t :desktop-task))))

(defun desktop-task-executor-name (requests)
  (let ((targets (remove-duplicates (mapcar #'desktop-task-request-target requests) :test #'eq)))
    (cond
      ((and (= (length targets) 1) (eq (first targets) :calculator))
       "conversation-desktop-task-calculator")
      ((and (= (length targets) 1) (eq (first targets) :runtime))
       "conversation-runtime-eval")
      ((and (= (length targets) 1)
            (member (first targets) '(:editor :workspace) :test #'eq))
       "conversation-desktop-task-editor")
      (t
       "conversation-desktop-task"))))

(defun desktop-task-executor-policy-decision (requests)
  (let ((capability (or (some #'desktop-task-request-capability requests) :safe-read)))
    (mutation-policy-decision-summary
     capability
     :decision :allowed
     :reason "Conversation prompt was recognized as a governed desktop task request.")))

(defun direct-desktop-task-assistant-message (requests actions results)
  (let ((targets (remove-duplicates (mapcar #'desktop-task-request-target requests) :test #'eq)))
    (cond
      ((and results
            (getf (first results) :invocation-error))
       (or (getf (getf (first results) :invocation-error) :summary)
           (getf (getf (first results) :invocation-error) :error)
           "The requested desktop task failed."))
      ((and (= (length targets) 1) (eq (first targets) :calculator))
       (or (and results
                (native-desktop-task-result-summary
                 (getf (first results) :native-result)
                 nil))
           (and results
                (desktop-task-invocation-result-summary
                 (getf (first results) :invocation-result)
                 nil))
           (direct-calculator-assistant-message actions results)))
      ((and (= (length targets) 1) (eq (first targets) :editor))
       (or (and results
                (native-desktop-task-result-summary
                 (getf (first results) :native-result)
                 nil))
           (and results
                (desktop-task-invocation-result-summary
                 (getf (first results) :invocation-result)
                 nil))
           (direct-editor-assistant-message actions)))
      ((and (= (length targets) 1) (eq (first targets) :runtime))
       (or (and results
                (native-desktop-task-result-summary
                 (getf (first results) :native-result)
                 nil))
           (and results
                (desktop-task-invocation-result-summary
                 (getf (first results) :invocation-result)
                 nil))
           (direct-runtime-assistant-message results
                                            "Evaluated the requested runtime form.")))
      ((and (= (length targets) 1) (eq (first targets) :workspace))
       (or (and results
                (native-desktop-task-result-summary
                 (getf (first results) :native-result)
                 nil))
           (and results
                (desktop-task-invocation-result-summary
                 (getf (first results) :invocation-result)
                 nil))
           "Applied the governed workspace patch."))
      (t
       "Completed the requested desktop task."))))

(defun direct-desktop-task-assistant-message-from-records (requests records actions results)
  (let ((targets (remove-duplicates (mapcar #'desktop-task-request-target requests) :test #'eq)))
    (cond
      ((some (lambda (record)
               (member (desktop-task-record-status record)
                       '(:failed :retryable-failure)
                       :test #'eq))
             records)
       (or (some #'desktop-task-record-result-summary-text records)
           "The requested desktop task failed."))
      ((some (lambda (record)
               (eq (desktop-task-record-status record) :awaiting-approval))
             records)
       (or (some #'desktop-task-record-result-summary-text records)
           "Awaiting approval before execution."))
      ((and (= (length records) 1)
            (= (length targets) 1)
            (member (first targets) '(:calculator :editor) :test #'eq))
       (or (desktop-task-record-result-summary-text (first records))
           (direct-desktop-task-assistant-message requests actions results)))
      ((= (length records) 1)
       (or (desktop-task-record-result-summary-text (first records))
           "Completed the requested desktop task."))
      (t
       (format nil "Completed ~D desktop tasks." (length records))))))

(defun desktop-task-record-policy-ids (records)
  (remove-duplicates
   (remove nil (mapcar #'desktop-task-record-policy-id records))
   :test #'eq))

(defun desktop-task-record-approval-ids (records)
  (remove-duplicates
   (remove nil (mapcar #'desktop-task-record-approval-id records))
   :test #'string=))

(defun desktop-task-record-actor-message-ids (records)
  (remove-duplicates
   (remove nil
           (mapcar (lambda (record)
                     (let ((message (desktop-task-record-actor-message record)))
                       (and message
                            (actor-message-id message))))
                   records))
   :test #'string=))

(defun desktop-task-record-pending-action-ids (records)
  (remove-duplicates
   (remove nil (mapcar #'desktop-task-record-pending-action-id records))
   :test #'string=))

(defun desktop-task-request-approval-ids (requests)
  (remove-duplicates
   (remove nil
           (mapcar (lambda (request)
                     (let ((metadata (desktop-task-request-metadata request))
                           (message (desktop-task-request-actor-message request)))
                       (or (and (listp metadata)
                                (getf metadata :approval-id))
                           (and message
                                (actor-message-approval-id message)))))
                   requests))
   :test #'string=))

(defun desktop-task-request-actor-message-ids (requests)
  (remove-duplicates
   (remove nil
           (mapcar (lambda (request)
                     (let ((message (desktop-task-request-actor-message request)))
                       (and message
                            (actor-message-id message))))
                   requests))
   :test #'string=))

(defun desktop-task-request-pending-action-ids (requests)
  (remove-duplicates
   (remove nil
           (mapcar (lambda (request)
                     (let ((metadata (desktop-task-request-metadata request))
                           (message (desktop-task-request-actor-message request)))
                       (or (and (listp metadata)
                                (getf metadata :pending-action-id))
                           (and message
                                (actor-message-pending-action-id message)))))
                   requests))
   :test #'string=))

(defun governed-desktop-task-approval-context (session thread turn requests records policy-ids)
  (let* ((pending-approval
           (ignore-errors
             (service-response-data
              (query-desktop-task-pending-approval-service session))))
         (approval-ids
           (or (desktop-task-request-approval-ids requests)
               (desktop-task-record-approval-ids records)
               (and (listp pending-approval)
                    (getf pending-approval :approval-ids))))
         (actor-message-ids
           (or (desktop-task-request-actor-message-ids requests)
               (desktop-task-record-actor-message-ids records)
               (and (listp pending-approval)
                    (getf pending-approval :actor-message-ids))))
         (pending-action-ids
           (or (desktop-task-request-pending-action-ids requests)
               (desktop-task-record-pending-action-ids records)
               (and (listp pending-approval)
                    (getf pending-approval :pending-action-ids)))))
    (list :session-id (agent-session-id session)
          :thread-id (or (and (listp pending-approval)
                              (getf pending-approval :thread-id))
                         (and thread (thread-id thread)))
          :turn-id (or (and (listp pending-approval)
                            (getf pending-approval :turn-id))
                       (and turn (turn-id turn)))
          :approval-id (first approval-ids)
          :approval-ids approval-ids
          :actor-message-id (first actor-message-ids)
          :actor-message-ids actor-message-ids
          :pending-action-id (first pending-action-ids)
          :pending-action-ids pending-action-ids
          :policy-id (first policy-ids)
          :policy-ids policy-ids
          :record-ids (mapcar #'desktop-task-record-id records)
          :resume-command :resume-work-item)))

(defun calculator-control-actions-p (actions)
  (and actions
       (every (lambda (action)
                (and (eq (assistant-action-type action) :tool)
                     (let* ((payload (assistant-action-payload action))
                            (tool-id (or (getf payload :tool-id)
                                         (getf payload :TOOL-ID))))
                       (member tool-id
                               '(:calculator/append-token
                                 :calculator/set-expression
                                 :calculator/evaluate
                                 :calculator/clear
                                 :calculator/backspace
                                 :calculator/set-mode
                                 :calculator/set-base
                                 :calculator/set-word-size
                                 :calculator/set-angle-unit)
                               :test #'eq))))
              actions)))

(defun append-conversation-calculator-control-event (session thread turn prompt actions results
                                                     &key source auto-routed-p direct-calculator-p)
  (append-session-event session
                        :conversation-calculator-control
                        (list :prompt prompt
                              :action-count (length actions)
                              :actions actions
                              :result-count (length results))
                        :family :calculator
                        :thread-id (thread-id thread)
                        :turn-id (turn-id turn)
                        :visibility :operator
                        :metadata (append (when direct-calculator-p
                                            (list :direct-calculator-p t))
                                          (when auto-routed-p
                                            (list :auto-routed-p t))
                                          (when source
                                            (list :source source)))))

(defun run-direct-conversation-desktop-task-requests (session prompt requests
                                                       &key (source :say) (operator-mode :conversation)
                                                         surface-context surface-actions)
  (let* ((thread (current-thread session)))
    (append-transcript-entry session :user prompt)
    (emit-conversation-progress (conversation-progress-phase source :started)
                                (list :prompt prompt
                                      :stream-p nil
                                      :thread-id (thread-id thread)
                                      :auto-routed-p t
                                      :desktop-task-p t
                                      :request-count (length requests)))
    (let* ((request-manifests
             (mapcar (lambda (desktop-task-request)
                       (or (find-desktop-task-manifest (desktop-task-request-target desktop-task-request)
                                                      (desktop-task-request-operation desktop-task-request))
                           (error "No desktop task manifest is registered for ~S/~S"
                                  (desktop-task-request-target desktop-task-request)
                                  (desktop-task-request-operation desktop-task-request))))
                     requests))
           (requests
             (loop for desktop-task-request in requests
                   for manifest in request-manifests
                   collect (ensure-governed-desktop-task-request-state
                            desktop-task-request
                            :session-id (agent-session-id session)
                            :manifest manifest)))
           (request-summaries (mapcar #'desktop-task-request-summary requests))
           (user-message (create-message session thread :user prompt
                                         :metadata (list :source source
                                                         :auto-routed-p t
                                                         :desktop-task-p t
                                                         :surface-context surface-context
                                                         :surface-actions surface-actions
                                                         :desktop-task-requests request-summaries)))
           (turn (start-turn session thread user-message
                             :metadata (list :source source
                                             :streamed-p nil
                                             :auto-routed-p t
                                             :desktop-task-p t
                                             :surface-context surface-context
                                             :surface-actions surface-actions
                                             :desktop-task-requests request-summaries)))
           (request (prepare-direct-conversation-request session
                                                        prompt
                                                        thread
                                                        turn
                                                        source
                                                        operator-mode
                                                        :surface-context surface-context
                                                        :surface-actions surface-actions))
           (manifest-summaries (mapcar #'desktop-task-manifest-summary request-manifests))
           (plan-binding
             (multiple-value-list (maybe-create-desktop-task-plan session requests)))
           (plan-id (first plan-binding))
           (plan-step-id (second plan-binding))
           (_plan-assigned
             (when (and plan-id plan-step-id)
               (command-assign-plan-step-service
                session
                plan-id
                plan-step-id
                :capability-query (list :id "workspace-write"
                                        :actor-role :editor
                                        :mutation-class :workspace-mutation
                                        :approval-required-p t))))
           (desktop-task-records
             (loop for desktop-task-request in requests
                   for manifest in request-manifests
                   collect (register-desktop-task-record
                           session
                           (make-desktop-task-record-for-request
                            desktop-task-request
                            manifest
                            :session-id (agent-session-id session)
                            :thread-id (thread-id thread)
                            :turn-id (turn-id turn)
                            :metadata (list :source source
                                            :auto-routed-p t
                                            :surface-context surface-context
                                            :surface-actions surface-actions
                                            :plan-id plan-id
                                            :plan-step-id plan-step-id)))))
           (resolved-requests (mapcar (lambda (desktop-task-request)
                                        (resolve-governed-desktop-task-request desktop-task-request session))
                                      requests))
           (resolution-summaries (mapcar #'desktop-task-resolution-summary-data resolved-requests))
           (desktop-task-bindings
             (loop for resolution in resolved-requests
                   for task-record in desktop-task-records
                   collect (list :record-id (desktop-task-record-id task-record)
                                 :request-id (desktop-task-resolution-request-id resolution)
                                 :target (desktop-task-resolution-target resolution)
                                 :operation (desktop-task-resolution-operation resolution)
                                 :actions (copy-list (desktop-task-resolution-actions resolution)))))
           (actions (mapcan (lambda (entry)
                              (copy-list (desktop-task-resolution-actions entry)))
                            resolved-requests))
           (operation (start-operation session
                                       thread
                                       turn
                                       (desktop-task-executor-kind requests)
                                       (desktop-task-executor-name requests)
                                       (list :prompt prompt
                                             :request-count (length requests)
                                             :plan-id plan-id
                                             :plan-step-id plan-step-id
                                             :requests request-summaries
                                             :manifests manifest-summaries
                                             :resolutions resolution-summaries
                                             :actions actions)
                                       :policy-decision
                                 (desktop-task-executor-policy-decision requests)
                                       :metadata (list :source source
                                                       :auto-routed-p t
                                                       :desktop-task-p t
                                                       :plan-id plan-id
                                                       :plan-step-id plan-step-id
                                                       :desktop-task-requests request-summaries
                                                       :desktop-task-manifests manifest-summaries
                                                       :desktop-task-resolutions resolution-summaries
                                                       :retrieval-summary
                                                       (provider-request-retrieval-summary request)
                                                       :cognition-summary
                                                       (provider-request-cognition-summary request)
                                                       :reasoning-summary
                                                       (provider-request-reasoning-summary request)
                                                       :planning-summary
                                                       (provider-request-planning-summary request))))
           (approval-required-p
             (some #'identity
                   (mapcar #'desktop-task-request-approval-required-p
                           requests
                           request-manifests
                           resolved-requests)))
           (staged-actions (if approval-required-p actions '()))
           (immediate-actions (if approval-required-p '() actions))
           (invocation-results
             (loop for desktop-task-request in requests
                   for manifest in request-manifests
                   for resolution in resolved-requests
                   collect (handler-case
                               (let* ((response
                                        (command-desktop-task-invoke-service
                                         session
                                         :request desktop-task-request
                                         :manifest manifest
                                         :resolution resolution
                                         :register-record-p nil
                                         :thread-id (thread-id thread)
                                         :turn-id (turn-id turn)
                                         :conversation-operation-id
                                         (and operation
                                              (operation-id operation))))
                                      (data (service-response-data response))
                                      (result (getf data :result))
                                      (task-record (getf data :task-record)))
                                 (list :request-id (desktop-task-resolution-request-id resolution)
                                       :response response
                                       :result result
                                       :task-record task-record
                                       :native-result (and (desktop-task-resolution-executor resolution)
                                                           result)))
                             (error (condition)
                               (list :request-id (desktop-task-resolution-request-id resolution)
                                     :invocation-error
                                     (list :summary "Desktop task invocation failed."
                                           :error (princ-to-string condition)
                                           :failure-classification :execution))))))
           (immediate-results
             (if approval-required-p
                 '()
                 (mapcan (lambda (entry)
                           (if (getf entry :invocation-error)
                               '()
                               (desktop-task-invocation-action-results
                                (getf entry :result))))
                         invocation-results)))
           (desktop-task-results
             (loop for resolution in resolved-requests
                   for task-record in desktop-task-records
                   for invocation in invocation-results
                   collect
                       (make-desktop-task-result
                        :request-id (desktop-task-resolution-request-id resolution)
                        :target (desktop-task-resolution-target resolution)
                        :operation (desktop-task-resolution-operation resolution)
                        :status (cond
                                  ((and invocation (getf invocation :invocation-error)) :failed)
                                  ((eq (desktop-task-record-status task-record) :awaiting-approval)
                                   :awaiting-approval)
                                  (t :completed))
                        :summary (or (and invocation
                                          (getf invocation :invocation-error)
                                          (or (getf (getf invocation :invocation-error) :summary)
                                              (getf (getf invocation :invocation-error) :error)))
                                     (desktop-task-record-result-summary-text task-record)
                                     (native-desktop-task-result-summary
                                      (and invocation (getf invocation :native-result))
                                      (desktop-task-resolution-summary resolution)))
                        :action-results (if (eq (desktop-task-record-status task-record)
                                                :awaiting-approval)
                                            '()
                                            (append (if (and invocation
                                                             (getf invocation :invocation-error))
                                                        (list (list :request-id (getf invocation :request-id)
                                                                    :error (getf invocation :invocation-error)))
                                                        (copy-list (or (and invocation
                                                                            (desktop-task-invocation-action-results
                                                                             (getf invocation :result)))
                                                                       '())))
                                                    (if (and invocation
                                                             (not (getf invocation :invocation-error))
                                                             (getf invocation :native-result))
                                                        (list (list :request-id (getf invocation :request-id)
                                                                    :native-result (getf invocation :native-result)))
                                                        '())))
                        :metadata (append (desktop-task-resolution-metadata resolution)
                                          (list :approval-required-p
                                                (eq (desktop-task-record-status task-record)
                                                    :awaiting-approval)
                                                :invocation-failed-p (not (null (and invocation
                                                                                    (getf invocation :invocation-error))))
                                                :task-record-id (desktop-task-record-id task-record))))))
           (action-report (list :immediate-actions immediate-actions
                                :immediate-results immediate-results
                                :staged-actions staged-actions
                                :deferred-actions '()
                                :action-assessments '()))
           (approval-policy-ids (if approval-required-p
                                    (or (assistant-action-policy-ids staged-actions)
                                        (desktop-task-record-policy-ids desktop-task-records))
                                    '()))
           (_staged (if staged-actions
                        (stage-pending-actions session staged-actions)
                        (clear-pending-actions session)))
           (primary-native-result (and (= (length invocation-results) 1)
                                       (getf (first invocation-results) :native-result)))
           (runtime-outbox-payload
             (and (eq (desktop-task-executor-kind requests) :runtime)
                  (runtime-outbox-payload-for-records session
                                                     desktop-task-records)))
           (runtime-reply
             (and (eq (desktop-task-executor-kind requests) :runtime)
                  (runtime-outbox-reply-summary-for-records session
                                                           desktop-task-records)))
           (runtime-actor-flow
             (and (eq (desktop-task-executor-kind requests) :runtime)
                  (runtime-actor-flow-for-records session
                                                 desktop-task-records)))
           (assistant-content
             (if approval-required-p
                 (approval-required-assistant-message approval-policy-ids)
                 (or (and runtime-outbox-payload
                          (or (getf runtime-outbox-payload :summary)
                              (getf runtime-outbox-payload :SUMMARY)))
                     (direct-desktop-task-assistant-message-from-records
                      requests
                      desktop-task-records
                      (append immediate-actions staged-actions)
                      invocation-results))))
           (completed-operation (complete-operation session
                                                   thread
                                                   turn
                                                   operation
                                                   (append (list :message assistant-content
                                                                 :stream-event-count 0
                                                                 :staged-action-count (length staged-actions)
                                                                 :deferred-action-count 0
                                                                 :immediate-action-count (length immediate-actions))
                                                           (when runtime-actor-flow
                                                             (list :actor-flow runtime-actor-flow))
                                                           (when (eq (desktop-task-executor-kind requests) :runtime)
                                                             (runtime-result-output-metadata
                                                              (or runtime-outbox-payload
                                                                  primary-native-result))))
                                                   :status :completed
                                                   :metadata (list :auto-routed-p t
                                                                   :desktop-task-p t
                                                                   :model-response-p nil)))
           (action-operations (record-assistant-action-operations session
                                                                 thread
                                                                 turn
                                                                 action-report
                                                                 :desktop-task-records desktop-task-records
                                                                 :desktop-task-bindings desktop-task-bindings))
           (assistant-message (create-message session thread :assistant assistant-content
                                              :content-type :text
                                              :metadata (list :source source
                                                              :streamed-p nil
                                                              :auto-routed-p t
                                                              :desktop-task-p t
                                                              :plan-id plan-id
                                                              :plan-step-id plan-step-id
                                                              :desktop-task-record-ids (mapcar #'desktop-task-record-id desktop-task-records)
                                                              :operation-id (operation-id completed-operation))))
           (_records-linked
             (dolist (task-record desktop-task-records)
               (update-desktop-task-record
                session
                task-record
                :metadata (list :conversation-operation-id (operation-id completed-operation)
                                :plan-id plan-id
                                :plan-step-id plan-step-id
                                :assistant-message-id (message-id assistant-message)))))
           (task-record-summaries (mapcar #'desktop-task-record-summary desktop-task-records))
           (canonical-task-results (mapcar #'desktop-task-record-canonical-result-summary
                                           desktop-task-records))
           (response (make-assistant-response
                      :message assistant-content
                      :actions actions
                      :metadata (list :source source
                                      :desktop-task-p t
                                      :auto-routed-p t
                                      :plan-id plan-id
                                      :plan-step-id plan-step-id
                                      :desktop-task-records task-record-summaries
                                      :desktop-task-results canonical-task-results
                                      :runtime-reply runtime-reply
                                      :actor-flow runtime-actor-flow)))
           (_plan-awaiting-approval
             (when (and approval-required-p plan-id plan-step-id)
               (let ((plan (session-active-plan session)))
                 (when (and plan (string= (plan-record-id plan) plan-id))
                   (let* ((workflow-record (ensure-plan-workflow-record session plan))
                          (approval-context
                            (governed-desktop-task-approval-context session
                                                                    thread
                                                                    turn
                                                                    requests
                                                                    desktop-task-records
                                                                    approval-policy-ids)))
                     (mark-workflow-record-awaiting-approval
                      session
                      workflow-record
                      (first approval-policy-ids)
                      :reason "Governed editor mutation requires approval.")
                     (update-workflow-record-next-action
                      workflow-record
                      (append (or (workflow-record-next-action workflow-record) '())
                              (list :approval-id (getf approval-context :approval-id)
                                    :approval-ids (getf approval-context :approval-ids)
                                    :actor-message-id (getf approval-context :actor-message-id)
                                    :actor-message-ids (getf approval-context :actor-message-ids)
                                    :pending-action-id (getf approval-context :pending-action-id)
                                    :pending-action-ids (getf approval-context :pending-action-ids)
                                    :session-id (getf approval-context :session-id)
                                    :thread-id (getf approval-context :thread-id)
                                    :turn-id (getf approval-context :turn-id)
                                    :record-ids (getf approval-context :record-ids)))
                      :session session)
                     (update-workflow-record-resume-payload
                      workflow-record
                      (append (or (workflow-record-resume-payload workflow-record) '())
                              (list :approval-id (getf approval-context :approval-id)
                                    :approval-ids (getf approval-context :approval-ids)
                                    :actor-message-id (getf approval-context :actor-message-id)
                                    :actor-message-ids (getf approval-context :actor-message-ids)
                                    :pending-action-id (getf approval-context :pending-action-id)
                                    :pending-action-ids (getf approval-context :pending-action-ids)
                                    :session-id (getf approval-context :session-id)
                                    :thread-id (getf approval-context :thread-id)
                                    :turn-id (getf approval-context :turn-id)
                                    :record-ids (getf approval-context :record-ids)
                                    :policy-id (getf approval-context :policy-id)
                                    :policy-ids (getf approval-context :policy-ids)))
                      :session session))
                   (update-plan-status plan :awaiting-approval
                                       :result-summary "Awaiting approval before execution.")
                   (update-plan-step-status (find-plan-step plan plan-step-id)
                                            :assigned
                                            :result-summary "Awaiting approval before execution."
                                            :verification-status :pending)))))
           (completed-turn (complete-turn session
                                          thread
                                          turn
                                          assistant-message
                                          :status (if approval-required-p
                                                      :awaiting-approval
                                                      (turn-status-from-action-operations action-operations))
                                          :metadata (list :stream-event-count 0
                                                         :operation-id (operation-id completed-operation)
                                                         :action-operation-ids (mapcar #'operation-id action-operations)
                                                         :auto-routed-p t
                                                         :desktop-task-p t
                                                         :desktop-task-requests request-summaries
                                                         :desktop-task-manifests manifest-summaries
                                                         :desktop-task-resolutions resolution-summaries
                                                         :desktop-task-records task-record-summaries
                                                         :desktop-task-results canonical-task-results
                                                         :runtime-reply runtime-reply
                                                         :actor-flow runtime-actor-flow))))
      (dolist (desktop-task-request requests)
        (append-session-event session
                              :desktop-task-request
                              (desktop-task-request-summary desktop-task-request)
                              :family :assistant
                              :thread-id (thread-id thread)
                              :turn-id (turn-id completed-turn)
                              :visibility :operator))
      (dolist (task-record desktop-task-records)
        (append-session-event session
                              :desktop-task-record
                              (desktop-task-record-summary task-record)
                              :family :assistant
                              :entity-id (desktop-task-record-id task-record)
                              :thread-id (thread-id thread)
                              :turn-id (turn-id completed-turn)
                              :visibility :operator))
      (dolist (desktop-task-result desktop-task-results)
        (append-session-event session
                              :desktop-task-result
                              (desktop-task-record-canonical-result-summary
                               (find (desktop-task-result-request-id desktop-task-result)
                                     desktop-task-records
                                     :key #'desktop-task-record-request-id
                                     :test #'string=))
                              :family :assistant
                              :thread-id (thread-id thread)
                              :turn-id (turn-id completed-turn)
                              :visibility :operator))
      (append-transcript-entry session :assistant assistant-content)
      (append-session-event session
                            :assistant-response
                            response
                            :family :assistant
                            :thread-id (thread-id thread)
                            :turn-id (turn-id completed-turn)
                            :visibility :operator)
      (when (eq (desktop-task-executor-kind requests) :calculator)
        (append-conversation-calculator-control-event session
                                                      thread
                                                      completed-turn
                                                      prompt
                                                      actions
                                                      immediate-results
                                                      :source source
                                                      :auto-routed-p t
                                                      :direct-calculator-p t))
      (record-turn-memory-entry session
                                thread
                                completed-turn
                                request
                                prompt
                                assistant-content
                                :defer-inference-p t)
      (emit-conversation-progress (conversation-progress-phase source :response)
                                  (list :message assistant-content
                                        :staged-action-count (length staged-actions)
                                        :deferred-action-count 0
                                        :retrieval-summary (provider-request-retrieval-summary request)
                                        :cognition-summary (provider-request-cognition-summary request)
                                        :action-agenda-summary (provider-request-action-agenda-summary request)
                                        :reasoning-summary (provider-request-reasoning-summary request)
                                        :planning-summary (provider-request-planning-summary request)
                                        :immediate-action-count (length immediate-actions)
                                        :stream-event-count 0
                                        :thread-id (thread-id thread)
                                        :turn-id (turn-id completed-turn)
                                        :auto-routed-p t
                                        :desktop-task-p t
                                        :desktop-task-records task-record-summaries
                                        :desktop-task-results canonical-task-results
                                        :actor-flow runtime-actor-flow
                                        :request-count (length requests)))
      (make-say-turn-result thread
                            user-message
                            assistant-message
                            completed-turn
                            response
                            action-report
                            :streamed-p nil
                            :stream-event-count 0
                            :action-results immediate-results
                            :retrieval-summary (provider-request-retrieval-summary request)
                            :cognition-summary (provider-request-cognition-summary request)
                            :action-agenda-summary (provider-request-action-agenda-summary request)
                            :reasoning-summary (provider-request-reasoning-summary request)
                            :planning-summary (provider-request-planning-summary request)))))

(defun prepare-direct-conversation-request (session prompt thread turn source operator-mode
                                            &key surface-context surface-actions)
  (let ((request (build-turn-provider-request session
                                              prompt
                                              thread
                                              turn
                                              operator-mode
                                              nil
                                              :surface-context surface-context
                                              :surface-actions surface-actions)))
    (record-turn-retrieval-dossier session thread turn request source)
    (record-turn-reasoning-brief session thread turn request source)
    (record-turn-planning-brief session thread turn request source)
    (record-turn-cognition-bundle session thread turn request source)
    request))

(defun governed-mutation-blocked-p (session reasoning-brief)
  (or (find-if (lambda (entry)
                 (member (getf entry :kind)
                         '(:blocked :quarantined :awaiting-cold-validation)
                         :test #'eq))
               (getf reasoning-brief :blockers))
      (getf reasoning-brief :validation-obligations)
      (> (or (getf (provider-session-summary session) :open-incident-count) 0)
         0)))

(defun cognition-strategy-defers-governed-mutations-p (cognition-bundle &key retrieval-dossier)
  (let ((execution-strategy (and cognition-bundle
                                 (cognition-bundle-execution-strategy cognition-bundle)))
        (validation-strategy (and cognition-bundle
                                  (cognition-bundle-validation-strategy cognition-bundle)))
        (action-agenda (and cognition-bundle
                            (cognition-bundle-action-agenda cognition-bundle)))
        (outcome-brief (and cognition-bundle
                            (cognition-bundle-outcome-brief cognition-bundle)))
        (post-mutation-p (eq (and retrieval-dossier
                                  (if (typep retrieval-dossier 'retrieval-dossier)
                                      (retrieval-dossier-phase retrieval-dossier)
                                      (getf retrieval-dossier :phase)))
                             :post-mutation)))
    (or (member (getf (getf action-agenda :primary-step) :kind)
                '(:resolve-blockers :collect-evidence :run-validations)
                :test #'eq)
        (eq (getf execution-strategy :next-step) :collect-evidence)
        (and (eq (getf validation-strategy :mode) :required)
             (eq (getf validation-strategy :next-step) :run-required-validations))
        (and post-mutation-p
             (member (getf outcome-brief :recommended-next-step)
                     '(:validate :resolve-blockers)
                     :test #'eq)))))

(defun project-governance-intent-p (retrieval-dossier)
  (let* ((intent (if (typep retrieval-dossier 'retrieval-dossier)
                     (retrieval-dossier-intent retrieval-dossier)
                     (getf retrieval-dossier :intent)))
         (intent-category (if (typep intent 'retrieval-intent)
                              (retrieval-intent-category intent)
                              (getf intent :category))))
    (eq intent-category :project-governance)))

(defun partition-governed-staged-actions (actions &key project-governance-intent-p)
  (let ((allowed '())
        (deferred '()))
    (dolist (action actions)
      (if (and (governed-assistant-action-p action)
               (not (and project-governance-intent-p
                         (eq (assistant-action-policy-id action) :project-governance-write))))
          (push action deferred)
          (push action allowed)))
    (values (nreverse allowed) (nreverse deferred))))

(defun retrieval-ranking-top-labels (retrieval-dossier)
  (let ((ranking (if (typep retrieval-dossier 'retrieval-dossier)
                     (retrieval-dossier-ranking retrieval-dossier)
                     (getf retrieval-dossier :ranking))))
  (mapcar (lambda (entry) (getf entry :label))
          (or (getf ranking :top-candidates) '()))))

(defun governed-action-grounding-domains (action)
  (let ((policy-id (assistant-action-policy-id action)))
    (case (assistant-action-type action)
      (:patch '(:workspace :artifact :workflow))
      (:eval (if (mutating-eval-action-p action)
                 '(:runtime :workflow :incident :artifact)
                 '(:runtime)))
      (:tool (case policy-id
               ((:workspace-write :git-write) '(:workspace :artifact :workflow))
               (:project-governance-write '(:project :trace :workflow))
               ((:process-run :runtime-reload) '(:runtime :workflow :incident :artifact))
               (otherwise '(:workspace :runtime :workflow))))
      (otherwise '()))))

(defun assess-assistant-action-grounding (action retrieval-dossier)
  (let* ((intent (if (typep retrieval-dossier 'retrieval-dossier)
                     (retrieval-dossier-intent retrieval-dossier)
                     (getf retrieval-dossier :intent)))
         (intent-category (if (typep intent 'retrieval-intent)
                              (retrieval-intent-category intent)
                              (getf intent :category)))
         (mutation-likely-p (if (typep intent 'retrieval-intent)
                                (retrieval-intent-mutation-likely-p intent)
                                (getf intent :mutation-likely-p)))
         (relevant-domains (governed-action-grounding-domains action))
         (top-labels (retrieval-ranking-top-labels retrieval-dossier))
         (matched-labels (intersection relevant-domains top-labels :test #'eq))
         (score (+ (if mutation-likely-p 2 0)
                   (if matched-labels 2 0)
                   (if (member intent-category '(:code-change :runtime-mutation :runtime-debugging
                                                :project-governance)
                               :test #'eq)
                       1
                       0)))
         (weakly-grounded-p
           (case (assistant-action-type action)
             (:patch
              (and (not mutation-likely-p)
                   (not (member intent-category '(:code-change) :test #'eq))
                   (not (member :workspace matched-labels :test #'eq))))
             (:eval
              (if (mutating-eval-action-p action)
                  (and (not mutation-likely-p)
                       (not (member intent-category '(:runtime-mutation :runtime-debugging) :test #'eq))
                       (not (member :runtime matched-labels :test #'eq)))
                  nil))
             (:tool
              (if (governed-assistant-action-p action)
                  (and (not mutation-likely-p)
                       (not (eq intent-category :project-governance))
                       (null matched-labels))
                  nil))
             (otherwise
              (< score 2)))))
    (list :action action
          :relevant-domains relevant-domains
          :matched-top-labels matched-labels
          :grounding-score score
          :weakly-grounded-p weakly-grounded-p
          :reason (if weakly-grounded-p
                      "Governed mutation proposal is weakly grounded in the retrieved context for this request."
                      "Governed mutation proposal is grounded in the retrieved context for this request."))))

(defun action-assessment-for (action assessments)
  (find action assessments :key (lambda (entry) (getf entry :action)) :test #'eq))

(defun partition-weakly-grounded-governed-actions (actions retrieval-dossier)
  (let ((allowed '())
        (deferred '())
        (assessments '()))
    (dolist (action actions)
      (let ((assessment (if (governed-assistant-action-p action)
                            (assess-assistant-action-grounding action retrieval-dossier)
                            (list :action action
                                  :grounding-score 3
                                  :weakly-grounded-p nil
                                  :reason "Read-oriented action does not require governed grounding checks."))))
        (push assessment assessments)
        (if (and (governed-assistant-action-p action)
                 (getf assessment :weakly-grounded-p))
            (push action deferred)
            (push action allowed))))
    (values (nreverse allowed) (nreverse deferred) (nreverse assessments))))

(defun process-response-actions (response session &key reasoning-brief retrieval-dossier cognition-bundle prompt surface-context)
  (multiple-value-bind (immediate staged)
      (split-assistant-actions (effective-response-actions response prompt surface-context session))
    (multiple-value-bind (staged-actions deferred-actions assessments)
        (partition-weakly-grounded-governed-actions staged retrieval-dossier)
      (let ((project-governance-intent-p (project-governance-intent-p retrieval-dossier)))
      (multiple-value-bind (strategy-allowed strategy-deferred-actions)
          (if (cognition-strategy-defers-governed-mutations-p cognition-bundle
                                                              :retrieval-dossier retrieval-dossier)
              (partition-governed-staged-actions staged-actions
                                                 :project-governance-intent-p project-governance-intent-p)
              (values staged-actions '()))
        (multiple-value-bind (final-staged-actions blocker-deferred-actions)
            (if (governed-mutation-blocked-p session reasoning-brief)
                (partition-governed-staged-actions strategy-allowed
                                                   :project-governance-intent-p project-governance-intent-p)
                (values strategy-allowed '()))
        (let* ((deferred-actions (append deferred-actions
                                         strategy-deferred-actions
                                         blocker-deferred-actions))
               (immediate-results (when immediate
                                    (execute-assistant-action-list immediate session))))
          (if final-staged-actions
              (stage-pending-actions session final-staged-actions)
              (clear-pending-actions session))
          (when blocker-deferred-actions
            (append-session-event session
                                  :governed-mutations-deferred
                                  (list :count (length blocker-deferred-actions)
                                        :actions blocker-deferred-actions
                                        :reasoning-brief reasoning-brief)
                                  :family :assistant
                                  :visibility :operator))
          (when strategy-deferred-actions
            (append-session-event session
                                  :strategy-governed-mutations-deferred
                                  (list :count (length strategy-deferred-actions)
                                        :actions strategy-deferred-actions
                                        :post-mutation-p
                                        (eq (and retrieval-dossier
                                                 (if (typep retrieval-dossier 'retrieval-dossier)
                                                     (retrieval-dossier-phase retrieval-dossier)
                                                     (getf retrieval-dossier :phase)))
                                            :post-mutation)
                                        :execution-strategy
                                        (and cognition-bundle
                                             (cognition-bundle-execution-strategy cognition-bundle))
                                        :validation-strategy
                                        (and cognition-bundle
                                             (cognition-bundle-validation-strategy cognition-bundle))
                                        :action-agenda
                                        (and cognition-bundle
                                             (cognition-bundle-action-agenda cognition-bundle))
                                        :outcome-brief
                                        (and cognition-bundle
                                             (cognition-bundle-outcome-brief cognition-bundle)))
                                  :family :assistant
                                  :visibility :operator))
          (let ((weakly-grounded-actions
                  (remove-if-not (lambda (entry) (getf entry :weakly-grounded-p))
                                 assessments)))
            (when weakly-grounded-actions
              (append-session-event session
                                    :weakly-grounded-mutations-deferred
                                    (list :count (length weakly-grounded-actions)
                                          :assessments weakly-grounded-actions
                                          :ranking (and retrieval-dossier
                                                        (if (typep retrieval-dossier 'retrieval-dossier)
                                                            (retrieval-dossier-ranking retrieval-dossier)
                                                            (getf retrieval-dossier :ranking))))
                                    :family :assistant
                                    :visibility :operator)))
          (list :immediate-actions immediate
                :immediate-results immediate-results
                :staged-actions final-staged-actions
                :deferred-actions deferred-actions
                :action-assessments assessments))))))))

(defun handle-provider-stream-event (session event events
                                   &key thread-id turn-id run-id operation-id)
  (let* ((resolved-thread-id (or thread-id
                                 (provider-event-thread-id event)))
         (resolved-turn-id (or turn-id
                               (provider-event-turn-id event)))
         (resolved-run-id (or run-id
                              (provider-event-run-id event)))
         (resolved-operation-id (or operation-id
                                    (provider-event-operation-id event)))
         (metadata (merge-event-metadata
                    (list :canonical-type (provider-event-effective-type event)
                          :legacy-type (provider-event-legacy-type event)
                          :provider-family (provider-event-family event))
                    (provider-event-metadata event))))
    (append-session-event session
                          :provider-stream
                          event
                          :family :provider
                          :entity-id (or (provider-event-entity-id event)
                                         resolved-run-id
                                         resolved-operation-id)
                          :thread-id resolved-thread-id
                          :turn-id resolved-turn-id
                          :visibility (provider-event-visibility event)
                          :metadata metadata
                          :run-id resolved-run-id
                          :operation-id resolved-operation-id)
    (when *task-progress-callback*
      (funcall *task-progress-callback* :provider-stream event))
    (when *stream-event-listener*
      (funcall *stream-event-listener* event))
    (append events (list event))))

(defun execution-task-form (source prompt options)
  (cons source (cons prompt (remove-plist-key options :enqueue))))

(defun ask-task-form (prompt options)
  (execution-task-form 'ask prompt options))

(defun trim-conversation-prompt (prompt)
  (string-trim '(#\Space #\Tab #\Newline #\Return) (or prompt "")))

(defun explicit-runtime-eval-form-prompt (prompt)
  (let ((trimmed (trim-conversation-prompt prompt)))
    (when (and (> (length trimmed) 0)
               (char= (char trimmed 0) #\()
               (ignore-errors (parse-runtime-forms trimmed)))
      trimmed)))

(defun implied-runtime-eval-form-prompt (prompt)
  (let* ((text (or prompt ""))
         (lower (string-downcase text))
         (form (extract-first-parenthesized-form text)))
    (when (and form
               (ignore-errors (parse-runtime-forms form))
               (prompt-contains-any-p
                lower
                '("evaluate"
                  "eval"
                  "execute"
                  "run"
                  "define"
                  "defun"
                  "provide me the result"
                  "show me the result")))
      form)))

(defun affirmative-runtime-eval-confirmation-p (prompt)
  (member (string-downcase (trim-conversation-prompt prompt))
          '("y"
            "yes"
            "yes."
            "yes please"
            "please do"
            "go ahead"
            "do it"
            "run it"
            "evaluate it"
            "evaluate that"
            "execute it"
            "execute that")
          :test #'string=))

(defun affirmative-approval-confirmation-p (prompt)
  (affirmative-runtime-eval-confirmation-p prompt))

(defun assistant-runtime-eval-offer-p (content)
  (let ((text (string-downcase (or content ""))))
    (or (search "would you like me to evaluate" text :test #'char=)
        (search "would you like me to execute" text :test #'char=)
        (search "evaluate this expression directly" text :test #'char=)
        (search "evaluate this directly" text :test #'char=))))

(defun pending-thread-runtime-eval-confirmation-form (session &optional thread)
  (let* ((active-thread (or thread (current-thread session)))
         (last-turn (most-recent-thread-turn session (thread-id active-thread)))
         (user-message (and last-turn
                            (find-message session (turn-user-message-id last-turn))))
         (assistant-message (and last-turn
                                 (find-message session (turn-assistant-message-id last-turn))))
         (form (and user-message
                    (explicit-runtime-eval-form-prompt (message-content user-message)))))
    (when (and form
               assistant-message
               (assistant-runtime-eval-offer-p (message-content assistant-message)))
      form)))

(defun resolve-conversation-runtime-eval-form (session prompt)
  (or (let ((form (explicit-runtime-eval-form-prompt prompt)))
        (when form
          (append-conversation-execution-debug-log
           :runtime-eval-resolution
           :reason :direct-form
           :form form
           :prompt prompt))
        (and form
             (list :form form
                   :reason :direct-form)))
      (let ((form (implied-runtime-eval-form-prompt prompt)))
        (when form
          (append-conversation-execution-debug-log
           :runtime-eval-resolution
           :reason :implied-form
           :form form
           :prompt prompt))
        (and form
             (list :form form
                   :reason :implied-form)))
      (let ((form (and (affirmative-runtime-eval-confirmation-p prompt)
                       (pending-thread-runtime-eval-confirmation-form session))))
        (when form
          (append-conversation-execution-debug-log
           :runtime-eval-resolution
           :reason :confirmed-prior-form
           :form form
           :prompt prompt))
        (and form
             (list :form form
                   :reason :confirmed-prior-form)))))

(defun pending-thread-approval-turn (session &optional thread)
  (let* ((active-thread (or thread (current-thread session)))
         (last-turn (and active-thread
                         (most-recent-thread-turn session (thread-id active-thread)))))
    (when (and last-turn
               (eq (turn-status last-turn) :awaiting-approval)
               (or (turn-pending-action-operations session last-turn)
                   (desktop-task-records-awaiting-approval-for-turn session
                                                                    (turn-id last-turn))))
      last-turn)))

(defun pending-session-approval-turn (session)
  (loop for turn in (reverse (agent-session-turns session))
        when (and (eq (turn-status turn) :awaiting-approval)
                  (or (turn-pending-action-operations session turn)
                      (desktop-task-records-awaiting-approval-for-turn session
                                                                       (turn-id turn))))
          do (return turn)))

(defun resolve-conversation-pending-approval-context (session prompt)
  (and (affirmative-approval-confirmation-p prompt)
       (or (let* ((pending-approval
                    (service-response-data
                     (query-desktop-task-pending-approval-service session)))
                  (records (getf pending-approval :records))
                  (turn-id (getf pending-approval :turn-id))
                  (turn (and turn-id
                             (find-turn session turn-id))))
             (when (or records turn
                       (getf pending-approval :approval-ids)
                       (getf pending-approval :actor-message-ids))
               (append (copy-list pending-approval)
                       (list :turn turn
                             :records records))))
           (let* ((thread (current-thread session))
                  (turns (and thread
                              (reverse (list-thread-turns session (thread-id thread))))))
             (loop for turn in turns
                   for work-item-id = (turn-bound-work-item-id turn)
                   for work-item = (and work-item-id
                                        (find-work-item session work-item-id))
                   for wait-report = (and work-item
                                          (work-item-wait-report session work-item))
                   for policy-ids = (and work-item
                                         (or (remove-duplicates
                                              (remove nil
                                                      (mapcar (lambda (requirement)
                                                                (getf requirement :policy))
                                                              (getf wait-report :approval-requirements)))
                                              :test #'eq)
                                             (pending-approval-policy-ids-for-turn session turn)))
                   when (and work-item
                             (eq (getf wait-report :why) :approval-required))
                     do (return (list :thread-id (thread-id thread)
                                      :turn turn
                                      :turn-id (turn-id turn)
                                      :work-item-id work-item-id
                                      :policy-ids policy-ids
                                      :wait-report wait-report)))))))

(defun pending-approval-policy-ids (operations)
  (remove-duplicates
   (remove nil
           (mapcar (lambda (operation)
                     (let* ((decision (operation-policy-decision operation))
                            (policy-id (and (listp decision)
                                            (getf decision :policy-id))))
                       policy-id))
                   operations))
   :test #'eq))

(defun pending-approval-policy-ids-for-turn (session turn)
  (remove-duplicates
   (append (pending-approval-policy-ids (turn-pending-action-operations session turn))
           (desktop-task-record-policy-ids
            (desktop-task-records-awaiting-approval-for-turn session (turn-id turn))))
   :test #'eq))

(defun assistant-action-policy-ids (actions)
  (remove-duplicates
   (remove nil (mapcar #'assistant-action-policy-id actions))
   :test #'eq))

(defun approval-required-assistant-message (policy-ids)
  (if policy-ids
      (format nil
              "This action requires approval before I can change the editor. Reply \"yes\" to approve ~{~S~^, ~} and I will continue."
              policy-ids)
      "This action requires approval before I can continue. Reply \"yes\" to approve and continue."))

(defun resumed-action-result-summary (result)
  (let ((action-results (getf result :action-results)))
    (or
     (some (lambda (entry)
             (let ((payload (getf entry :result)))
               (and (listp payload)
                    (or (getf payload :summary)
                        (getf payload :message)))))
           action-results)
     (let ((followup (getf result :followup)))
       (or (and (listp followup)
                (let ((response (getf followup :response)))
                  (and (listp response)
                       (getf response :message))))
           "Approved and completed the requested action.")))))

(defun runtime-eval-assistant-message (tool-result reason)
  (let* ((form (getf tool-result :form))
         (package (getf tool-result :package))
         (values (or (getf tool-result :values) '())))
    (format nil "~A in ~A. Result: ~S.~@[ Values: ~S.~]"
            (if (eq reason :confirmed-prior-form)
                "Evaluated the previously requested form"
                (format nil "Evaluated ~A" form))
            package
            (first values)
            (and (rest values) values))))

(defun make-runtime-evaluate-desktop-task-request (session prompt form reason
                                                   surface-context surface-actions)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :runtime
   :operation :evaluate-form
   :capability :runtime-eval-safe
   :payload (list :form form
                  :package-name (agent-session-package session)
                  :reason reason)
   :surface-context surface-context
   :surface-actions surface-actions
   :metadata (append (list :prompt prompt
                           :actor-slice :context-chat-runtime-v1
                           :reason reason)
                     (when (agent-session-package session)
                       (list :package-name (agent-session-package session)))
                     (when (fboundp 'default-runtime-id)
                       (list :runtime-id (default-runtime-id))))))

(defun direct-runtime-eval-plan-goal (form reason)
  (format nil "Execute direct runtime evaluation (~A): ~A"
          (or reason :prompt)
          form))

(defun create-direct-runtime-eval-plan (session form reason)
  (let* ((capability-query (list :id "runtime/eval"
                                 :mutation-class :runtime-mutation))
         (step-payload (list :goal (format nil "Evaluate runtime form ~A" form)
                             :kind :execute
                             :capability-query capability-query))
         (response
           (command-create-plan-service
            session
            (direct-runtime-eval-plan-goal form reason)
            :scope (list :domain :runtime
                         :package (agent-session-package session)
                         :reason reason)
            :selected-capabilities '("runtime/eval")
            :verification-policy (list :kind :runtime-eval
                                       :required-p t)
            :steps (list step-payload)))
         (plan-data (service-response-data response))
         (plan-id (getf plan-data :id))
         (step-id (getf (first (getf plan-data :steps)) :id)))
    (values plan-id step-id plan-data)))

(defun governed-desktop-task-plan-goal (request)
  (let* ((payload (desktop-task-request-payload request))
         (operation (desktop-task-request-operation request))
         (summary
           (case operation
             (:append-text
              (format nil "Append text into the active editor buffer: ~A"
                      (or (getf payload :text)
                          "editor append")))
             (otherwise
              (format nil "Execute governed desktop task ~A/~A"
                      (desktop-task-request-target request)
                      operation)))))
    (format nil "Apply governed workspace mutation: ~A" summary)))

(defun desktop-task-plan-capability-query (request manifest)
  (let ((capability (or (and manifest
                             (desktop-task-manifest-capability manifest))
                        (desktop-task-request-capability request)
                        :workspace-write)))
    (list :id (string-downcase (string capability))
          :actor-role (desktop-task-request-target request)
          :mutation-class :workspace-mutation
          :approval-required-p t)))

(defun desktop-task-plan-step-goal (request)
  (let* ((payload (desktop-task-request-payload request))
         (operation (desktop-task-request-operation request)))
    (case operation
      (:append-text
       (format nil "Append ~A into the active editor buffer"
               (or (getf payload :text)
                   "text")))
      (otherwise
       (format nil "Execute governed desktop task ~A/~A"
               (desktop-task-request-target request)
               operation)))))

(defun create-governed-desktop-task-plan (session request)
  (let* ((manifest (find-desktop-task-manifest (desktop-task-request-target request)
                                               (desktop-task-request-operation request)))
         (surface-context (desktop-task-request-surface-context request))
         (editor-context (and (listp surface-context)
                              (getf surface-context :editor)))
         (capability-query (desktop-task-plan-capability-query request manifest))
         (step-payload (list :goal (desktop-task-plan-step-goal request)
                             :kind :execute
                             :capability-query capability-query))
         (response
           (command-create-plan-service
            session
            (governed-desktop-task-plan-goal request)
            :scope (append (list :domain :workspace
                                 :surface (desktop-task-request-target request)
                                 :target (desktop-task-request-target request)
                                 :operation (desktop-task-request-operation request))
                           (when (and (listp editor-context)
                                      (or (getf editor-context :scope-id)
                                          (getf editor-context :scopeId)))
                             (list :scope-id (or (getf editor-context :scope-id)
                                                 (getf editor-context :scopeId))))
                           (when (and (listp editor-context)
                                      (or (getf editor-context :buffer-id)
                                          (getf editor-context :bufferId)))
                             (list :buffer-id (or (getf editor-context :buffer-id)
                                                  (getf editor-context :bufferId)))))
            :selected-capabilities (list (getf capability-query :id))
            :verification-policy (list :kind :governed-workspace-mutation
                                       :required-p t)
            :steps (list step-payload)))
         (plan-data (service-response-data response))
         (plan-id (getf plan-data :id))
         (step-id (getf (first (getf plan-data :steps)) :id)))
    (values plan-id step-id plan-data)))

(defun maybe-create-desktop-task-plan (session requests)
  (when (= (length requests) 1)
    (let* ((request (first requests))
           (manifest (find-desktop-task-manifest (desktop-task-request-target request)
                                                 (desktop-task-request-operation request))))
      (when (and manifest
                 (eq (desktop-task-manifest-approval-policy manifest) :explicit)
                 (eq (desktop-task-manifest-capability manifest) :workspace-write))
        (create-governed-desktop-task-plan session request)))))

(defun governed-desktop-task-record-for-summary (session record-summary)
  (or (and (getf record-summary :id)
           (find-desktop-task-record session (getf record-summary :id)))
      (and (getf record-summary :request-id)
           (find-desktop-task-record-by-request-id session
                                                   (getf record-summary :request-id)))))

(defun governed-desktop-task-records-for-summaries (session task-record-summaries)
  (remove nil
          (mapcar (lambda (record-summary)
                    (governed-desktop-task-record-for-summary session record-summary))
                  task-record-summaries)))

(defun governed-desktop-task-observation-summary (record)
  (case (desktop-task-record-target record)
    (:editor
     (editor-pending-mutation-summary record))
    (otherwise
     (desktop-task-record-summary record))))

(defun governed-desktop-task-reconciliation-status (entry)
  (let ((target (getf entry :target)))
    (cond ((and (eq target :editor)
                (eq (getf entry :status) :completed)
                (eq (getf entry :approval-status) :approved)
                (eq (getf entry :governance-status) :completed)
                (getf entry :scope-id)
                (getf entry :buffer-id))
           :observed)
          ((and (eq (getf entry :status) :completed)
                (eq (getf entry :approval-status) :approved)
                (eq (getf entry :governance-status) :completed)
                (getf entry :request-id)
                (getf entry :target)
                (getf entry :operation))
           :observed)
          ((and (eq (getf entry :status) :completed)
                (eq (getf entry :approval-status) :approved))
           :partial)
          (t
           :missing))))

(defun governed-desktop-task-verification-evidence (record assistant-content)
  (let* ((entry (governed-desktop-task-observation-summary record))
         (record-metadata (desktop-task-record-metadata record))
         (reconciliation-status
           (governed-desktop-task-reconciliation-status entry)))
    (list :kind :governed-workspace-mutation-verification
          :status (if (eq reconciliation-status :missing) :failed :verified)
          :summary assistant-content
          :reconciliation-status reconciliation-status
          :record-observed-p t
          :session-id (getf entry :session-id)
          :approval-id (getf entry :approval-id)
          :actor-execution-job-id (getf record-metadata :actor-execution-job-id)
          :target (getf entry :target)
          :operation (getf entry :operation)
          :capability (desktop-task-record-capability record)
          :task-record-id (getf entry :record-id)
          :request-id (getf entry :request-id)
          :actor-message-id (getf entry :actor-message-id)
          :pending-action-id (getf entry :pending-action-id)
          :scope-id (getf entry :scope-id)
          :buffer-id (getf entry :buffer-id)
          :package-name (getf entry :package-name)
          :target-observed-p (not (null (getf entry :target)))
          :operation-observed-p (not (null (getf entry :operation)))
          :scope-observed-p (not (null (getf entry :scope-id)))
          :buffer-observed-p (not (null (getf entry :buffer-id)))
          :package-observed-p (not (null (getf entry :package-name)))
          :governance-status (getf entry :governance-status)
          :approval-status (getf entry :approval-status)
          :created-at (getf entry :created-at)
          :approved-at (getf entry :approved-at)
          :completed-at (getf entry :completed-at))))

(defun finalize-governed-desktop-task-plan-from-record-summaries (session task-record-summaries assistant-content)
  (let* ((records (governed-desktop-task-records-for-summaries session
                                                               task-record-summaries))
         (record (first records))
         (metadata (and record (desktop-task-record-metadata record)))
         (plan-id (and (listp metadata) (getf metadata :plan-id)))
         (plan-step-id (and (listp metadata) (getf metadata :plan-step-id)))
         (actor-execution-job-id
           (and (listp metadata) (getf metadata :actor-execution-job-id))))
    (when (and plan-id plan-step-id)
      (if (every (lambda (entry)
                   (eq (desktop-task-record-status entry) :completed))
                 records)
          (command-complete-plan-step-service
           session
           plan-id
           plan-step-id
           :result-summary assistant-content
           :execution-id actor-execution-job-id
           :verification-status :verified
           :evidence (governed-desktop-task-verification-evidence record assistant-content))
          (command-fail-plan-step-service
           session
           plan-id
           plan-step-id
           :result-summary assistant-content
           :execution-id actor-execution-job-id
           :verification-status :failed
            :evidence (list :kind :governed-workspace-mutation-verification
                            :status :failed
                            :summary assistant-content
                            :actor-execution-job-id actor-execution-job-id
                            :task-record-summaries
                            (mapcar #'governed-desktop-task-observation-summary
                                    records)))))))

(defun runtime-eval-post-state-evidence (session package-name)
  (let ((runtime-summary
          (ignore-errors
            (service-response-data (query-runtime-summary-service session)))))
    (list :runtime-summary
          (and (listp runtime-summary)
               (list :runtime-id (getf runtime-summary :runtime-id)
                     :package (getf runtime-summary :package)
                     :loaded-system-count (getf runtime-summary :loaded-system-count)))
          :package package-name)))

(defun runtime-defined-symbol-post-state (session symbol-name package-name)
  (let ((runtime-post-state
          (runtime-eval-post-state-evidence session package-name))
        (describe-symbol
          (ignore-errors
            (service-response-data
             (query-runtime-describe-symbol-service session symbol-name :package package-name))))
        (source-image-divergence
          (ignore-errors
            (service-response-data
             (query-runtime-source-image-divergence-service session symbol-name
                                                            :package package-name)))))
    (list :runtime-summary (getf runtime-post-state :runtime-summary)
          :package package-name
          :describe-symbol describe-symbol
          :source-image-divergence source-image-divergence)))

(defun verify-direct-runtime-eval-result (session form tool-result)
  (let* ((package-name (agent-session-package session))
         (resolved-package (and package-name
                                (resolve-runtime-package-designator package-name)))
         (resolved-forms (and resolved-package
                              (ignore-errors
                                (parse-runtime-forms form :package resolved-package))))
         (defined-name (and resolved-forms
                            (runtime-eval-defined-name resolved-forms))))
    (cond
      ((null resolved-package)
       (values :verification-unavailable
               (list :kind :runtime-eval-verification
                     :status :verification-unavailable
                     :reason :unknown-package
                     :package package-name
                     :post-state (runtime-eval-post-state-evidence session package-name))))
      (defined-name
       (multiple-value-bind (symbol status)
           (find-symbol (symbol-name defined-name) resolved-package)
         (declare (ignore status))
         (let ((post-state
                 (runtime-defined-symbol-post-state session
                                                    (symbol-name defined-name)
                                                    (package-name resolved-package))))
           (if (and symbol (fboundp symbol))
               (values :verified
                       (list :kind :runtime-eval-verification
                             :status :verified
                             :package (package-name resolved-package)
                             :defined-name (symbol-name defined-name)
                             :post-state post-state))
               (values :failed
                       (list :kind :runtime-eval-verification
                             :status :failed
                             :package (package-name resolved-package)
                             :defined-name (symbol-name defined-name)
                             :reason :missing-function-binding
                             :post-state post-state))))))
      (t
       (let ((post-state
               (runtime-eval-post-state-evidence session
                                                 (package-name resolved-package))))
         (values :verified
                 (list :kind :runtime-eval-verification
                       :status :verified
                       :package (package-name resolved-package)
                       :result (getf tool-result :result)
                       :post-state post-state)))))))

(defun run-direct-conversation-runtime-eval (session prompt form reason
                                              &key (source :say) (operator-mode :conversation)
                                                surface-context surface-actions)
  (let* ((thread (current-thread session)))
    (append-transcript-entry session :user prompt)
    (emit-conversation-progress (conversation-progress-phase source :started)
                                (list :prompt prompt
                                      :stream-p nil
                                      :thread-id (thread-id thread)
                                      :auto-routed-p t
                                      :direct-runtime-eval-p t))
    (multiple-value-bind (plan-id plan-step-id plan-data)
        (create-direct-runtime-eval-plan session form reason)
      (declare (ignore plan-data))
      (command-assign-plan-step-service
       session
       plan-id
       plan-step-id
       :capability-query (list :id "runtime/eval"
                               :mutation-class :runtime-mutation))
      (let* ((user-message (create-message session thread :user prompt
                                           :metadata (list :source source
                                                           :auto-routed-p t
                                                           :direct-runtime-eval-p t
                                                           :direct-runtime-eval-reason reason
                                                           :plan-id plan-id
                                                           :plan-step-id plan-step-id)))
             (turn (start-turn session thread user-message
                               :metadata (list :source source
                                               :streamed-p nil
                                               :auto-routed-p t
                                               :direct-runtime-eval-p t
                                               :direct-runtime-eval-reason reason
                                               :plan-id plan-id
                                               :plan-step-id plan-step-id
                                               :surface-context surface-context
                                               :surface-actions surface-actions)))
             (request (prepare-direct-conversation-request session
                                                           prompt
                                                           thread
                                                           turn
                                                           source
                                                           operator-mode
                                                           :surface-context surface-context
                                                           :surface-actions surface-actions))
             (operation (start-operation session
                                         thread
                                         turn
                                         :runtime
                                         "conversation-runtime-eval"
                                         (list :prompt prompt
                                               :form form
                                               :reason reason
                                               :plan-id plan-id
                                               :plan-step-id plan-step-id)
                                         :policy-decision
                                         (mutation-policy-decision-summary
                                          :runtime-eval-safe
                                          :decision :allowed
                                          :reason "Conversation prompt was recognized as a direct runtime evaluation request.")
                                         :metadata (list :source source
                                                         :auto-routed-p t
                                                         :direct-runtime-eval-p t
                                                         :direct-runtime-eval-reason reason
                                                         :plan-id plan-id
                                                         :plan-step-id plan-step-id))))
        (handler-case
            (let* ((tool-result
                     (let ((*runtime-governance-thread* thread)
                           (*runtime-governance-turn* turn)
                           (*runtime-governance-operation* operation))
                       (tool-runtime-eval session :form form)))
                   (completed-operation
                     (complete-operation session
                                         thread
                                         turn
                                         operation
                                         tool-result
                                         :status :completed
                                         :metadata (list :auto-routed-p t
                                                         :direct-runtime-eval-p t
                                                         :direct-runtime-eval-reason reason)))
                   (assistant-content (runtime-eval-assistant-message tool-result reason))
                   (response (make-assistant-response
                              :message assistant-content
                              :actions '()
                              :metadata (list :source source
                                              :direct-runtime-eval-p t
                                              :direct-runtime-eval-reason reason
                                              :auto-routed-p t)))
                   (assistant-message
                     (create-message session thread :assistant assistant-content
                                     :content-type :text
                                     :metadata (list :source source
                                                     :streamed-p nil
                                                     :auto-routed-p t
                                                     :direct-runtime-eval-p t
                                                     :direct-runtime-eval-reason reason
                                                     :plan-id plan-id
                                                     :plan-step-id plan-step-id
                                                     :operation-id (operation-id completed-operation))))
                   (completed-turn
                     (complete-turn session
                                    thread
                                    turn
                                    assistant-message
                                    :status :completed
                                    :metadata (list :stream-event-count 0
                                                    :operation-id (operation-id completed-operation)
                                                    :auto-routed-p t
                                                    :direct-runtime-eval-p t
                                                    :plan-id plan-id
                                                    :plan-step-id plan-step-id
                                                    :direct-runtime-eval-reason reason))))
              (multiple-value-bind (verification-status verification-evidence)
                  (verify-direct-runtime-eval-result session form tool-result)
                (command-complete-plan-step-service
                 session
                 plan-id
                 plan-step-id
                 :result-summary assistant-content
                 :execution-id (operation-id completed-operation)
                 :verification-status verification-status
                 :evidence verification-evidence))
              (append-transcript-entry session :assistant assistant-content)
              (append-session-event session
                                    :assistant-response
                                    response
                                    :family :assistant
                                    :thread-id (thread-id thread)
                                    :turn-id (turn-id completed-turn)
                                    :visibility :operator)
              (append-session-event session
                                    :conversation-runtime-eval
                                    (list :form form
                                          :reason reason
                                          :result (first (getf tool-result :values))
                                          :values (getf tool-result :values))
                                    :family :runtime
                                    :entity-id (operation-id completed-operation)
                                    :thread-id (thread-id thread)
                                    :turn-id (turn-id completed-turn)
                                    :visibility :operator
                                    :metadata (list :source source
                                                    :direct-runtime-eval-p t
                                                    :plan-id plan-id
                                                    :plan-step-id plan-step-id
                                                    :direct-runtime-eval-reason reason))
              (record-turn-memory-entry session
                                        thread
                                        completed-turn
                                        request
                                        prompt
                                        assistant-content)
              (emit-conversation-progress (conversation-progress-phase source :response)
                                          (list :message assistant-content
                                                :staged-action-count 0
                                                :deferred-action-count 0
                                                :retrieval-summary (provider-request-retrieval-summary request)
                                                :cognition-summary (provider-request-cognition-summary request)
                                                :action-agenda-summary (provider-request-action-agenda-summary request)
                                                :reasoning-summary (provider-request-reasoning-summary request)
                                                :planning-summary (provider-request-planning-summary request)
                                                :outcome-summary (provider-request-outcome-summary request)
                                                :immediate-action-count 1
                                                :stream-event-count 0
                                                :thread-id (thread-id thread)
                                                :turn-id (turn-id completed-turn)
                                                :auto-routed-p t
                                                :direct-runtime-eval-p t))
              (append (list :response response
                            :staged-action-count 0
                            :deferred-action-count 0
                            :immediate-action-count 1
                            :action-results (list tool-result)
                            :streamed-p nil
                            :stream-event-count 0
                            :direct-runtime-eval-p t
                            :direct-runtime-eval-reason reason
                            :runtime-result tool-result
                            :retrieval-summary (provider-request-retrieval-summary request)
                            :cognition-summary (provider-request-cognition-summary request)
                            :action-agenda-summary (provider-request-action-agenda-summary request)
                            :reasoning-summary (provider-request-reasoning-summary request)
                            :planning-summary (provider-request-planning-summary request)
                            :outcome-summary (provider-request-outcome-summary request))
                      (conversation-turn-summary thread
                                                 user-message
                                                 assistant-message
                                                 completed-turn)))
          (error (condition)
            (command-fail-plan-step-service
             session
             plan-id
             plan-step-id
             :result-summary (princ-to-string condition)
             :verification-status :failed
             :evidence (list :kind :runtime-eval-verification
                             :status :failed
                             :reason :execution-error
                             :message (princ-to-string condition)
                             :form form))
            (error condition)))))))

(defun command-invoke-tool-service (session tool-id tool-args &key thread turn operation)
  (let* ((base-compatibility-target (tool-compatibility-target tool-id session tool-args))
         (result (let ((*runtime-governance-thread* thread)
                       (*runtime-governance-turn* turn)
                       (*runtime-governance-operation* operation))
                   (declare (special *runtime-governance-thread*
                                     *runtime-governance-turn*
                                     *runtime-governance-operation*))
                   (apply #'invoke-tool tool-id session tool-args)))
         (compatibility-target
           (and base-compatibility-target
                (append (copy-list base-compatibility-target)
                        (when (getf result :backend-implementation)
                          (list :backend-implementation (getf result :backend-implementation)))
                        (when (getf result :window-state)
                          (list :window-state (getf result :window-state)))
                        (when (getf result :bridge-session-id)
                          (list :bridge-session-id (getf result :bridge-session-id)))
                        (when (member :bridge-attached-p result)
                          (list :bridge-attached-p (getf result :bridge-attached-p)))
                        (when (getf result :recovery-note)
                          (list :recovery-note (getf result :recovery-note)))
                        (when (getf result :control-token)
                          (list :control-token (getf result :control-token)))
                        (when (getf result :pid)
                          (list :pid (getf result :pid)))
                        (when (getf result :registered-at)
                          (list :registered-at (getf result :registered-at)))
                        (when (getf result :status)
                          (list :status (getf result :status)
                                :last-observed-status (getf result :status)
                                :last-status-change-at (get-universal-time)))
                        (when (eq tool-id :proc/spawn)
                          (list :execution-mode :detached)))))
         (payload (if compatibility-target
                      (append (copy-list result)
                              (list :compatibility-target compatibility-target))
                      result)))
    (kernelize-service-command-response
     (make-service-command-response :execution
                                    :tool
                                    payload
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :tool-execution-v1
                                                                     :session session
                                                                     :thread-id (and thread (thread-id thread))
                                                                     :turn-id (and turn (turn-id turn))))
   :session session
   :intention (format nil "Invoke tool ~A." tool-id)
   :capability (kernel-tool-capability-id tool-id)
   :authority :environment
   :context (list :thread-id (and thread (thread-id thread))
                  :turn-id (and turn (turn-id turn))
                  :tool-arguments tool-args))))

(defun command-invoke-compatibility-app-service (session app-id app-args &key thread turn operation)
  (let* ((definition (or (find-compatibility-app app-id
                                                 :session session
                                                 :environment (session-bound-environment session))
                         (error "Unknown compatibility app ~S" app-id)))
         (backend-profile-id (compatibility-app-definition-backend-profile-id definition))
         (argv (compatibility-app-command-argv app-id app-args
                                               :session session
                                               :environment (session-bound-environment session)))
         (base-target (compatibility-app-target app-id session app-args
                                                :environment (session-bound-environment session)))
         (result (let ((*runtime-governance-thread* thread)
                       (*runtime-governance-turn* turn)
                       (*runtime-governance-operation* operation))
                   (declare (special *runtime-governance-thread*
                                     *runtime-governance-turn*
                                     *runtime-governance-operation*))
                   (compatibility-backend-launch backend-profile-id
                                                session
                                                argv
                                                :display-surface-kind
                                                (compatibility-app-definition-display-surface-kind
                                                 definition))))
         (compatibility-target
           (append (copy-list base-target)
                   (when (getf result :backend-implementation)
                     (list :backend-implementation (getf result :backend-implementation)))
                   (when (getf result :window-state)
                     (list :window-state (getf result :window-state)))
                   (when (getf result :bridge-session-id)
                     (list :bridge-session-id (getf result :bridge-session-id)))
                   (when (member :bridge-attached-p result)
                     (list :bridge-attached-p (getf result :bridge-attached-p)))
                   (when (getf result :recovery-note)
                     (list :recovery-note (getf result :recovery-note)))
                   (when (getf result :control-token)
                     (list :control-token (getf result :control-token)))
                   (when (getf result :pid)
                     (list :pid (getf result :pid)))
                   (when (getf result :registered-at)
                     (list :registered-at (getf result :registered-at)))
                   (when (getf result :status)
                          (list :status (getf result :status)
                                :last-observed-status (getf result :status)
                                :last-status-change-at (get-universal-time)))))
         (payload (append (copy-list result)
                          (list :app-id app-id
                                :compatibility-target compatibility-target))))
    (kernelize-service-command-response
     (make-service-command-response :execution
                                    :compatibility-app
                                    payload
                                    :metadata (make-service-metadata :authority :environment
                                                                     :command-model :compatibility-app-execution-v1
                                                                     :session session
                                                                     :thread-id (and thread (thread-id thread))
                                                                     :turn-id (and turn (turn-id turn))))
     :session session
     :intention (format nil "Invoke compatibility app ~A." app-id)
     :capability app-id
     :authority :environment
     :context (list :thread-id (and thread (thread-id thread))
                    :turn-id (and turn (turn-id turn))
                    :app-arguments app-args))))

(defun command-apply-patch-service (session operations &key thread turn operation)
  (kernelize-service-command-response
   (make-service-command-response :execution
                                  :patch
                                  (apply-patch-operations session
                                                          operations
                                                          :thread thread
                                                          :turn turn
                                                          :operation operation)
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :patch-execution-v1
                                                                   :session session
                                                                   :thread-id (and thread (thread-id thread))
                                                                   :turn-id (and turn (turn-id turn))))
   :session session
   :intention "Apply a governed patch to the workspace."
   :capability :workspace/patch
   :authority :workspace-write
   :context (list :thread-id (and thread (thread-id thread))
                  :turn-id (and turn (turn-id turn))
                  :operation operation)))

(defun actorized-service-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (listp data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun perform-conversation-execution-service (session provider prompt options
                                                &key (source :say) (operator-mode :conversation))
  (append-conversation-execution-debug-log
   :entry
   :prompt prompt
   :source source
   :operator-mode operator-mode
   :current-thread-id (ignore-errors (thread-id (current-thread session))))
  (let* ((active-environment (or (session-bound-environment session)
                                 (ensure-environment)))
         (enqueue-p (plist-value options :enqueue nil)))
    (unless (eq (environment-compatibility-session active-environment) session)
      (bind-session-to-environment session active-environment))
    (if enqueue-p
        (let* ((task-form (execution-task-form source prompt options))
               (command (normalize-form-command task-form))
               (task (enqueue-task session command :payload task-form)))
          (kernelize-service-command-response
           (make-service-command-response :execution
                                          source
                                          (list :queued-task (task-summary task)
                                                :enqueued-p t)
                                          :metadata (make-service-metadata :authority :environment
                                                                           :command-model :conversation-execution-v1
                                                                           :session session))
           :session session
           :intention prompt
           :capability (ecase source
                         (:ask :conversation/ask)
                         (:say :conversation/say))
           :authority operator-mode
           :context (list :enqueue-p t :operator-mode operator-mode)))
        (let* ((surface-context (plist-value options :surface-context nil))
               (surface-actions (plist-value options :surface-actions nil))
               (pending-approval-context (resolve-conversation-pending-approval-context session prompt))
               (direct-runtime-eval (resolve-conversation-runtime-eval-form session prompt)))
          (append-conversation-execution-debug-log
           :branch-selection
           :prompt prompt
           :pending-approval-p (not (null pending-approval-context))
           :direct-runtime-eval-p (not (null direct-runtime-eval)))
          (cond
            (pending-approval-context
             (let* ((session-id (or (getf pending-approval-context :session-id)
                                    (agent-session-id session)))
                    (pending-thread-id (getf pending-approval-context :thread-id))
                    (approval-id (first (or (getf pending-approval-context :approval-ids)
                                            '())))
                    (generic-work-item-id (getf pending-approval-context :work-item-id))
                    (policy-ids (or (getf pending-approval-context :policy-ids)
                                    '()))
                    (actor-message-ids (getf pending-approval-context :actor-message-ids))
                    (receiver-roles (getf pending-approval-context :receiver-roles))
                    (thread (or (and pending-thread-id
                                     (find-thread session pending-thread-id))
                                (and (getf pending-approval-context :turn)
                                     (find-thread session
                                                  (turn-thread-id
                                                   (getf pending-approval-context :turn))))
                                (current-thread session)
                                (error "Approval confirmation requires an active presentation thread.")))
                    (_approval-required
                      (unless (or approval-id generic-work-item-id)
                        (error "No governed approval is currently pending. The approval prompt likely expired from local UI state before confirmation completed.")))
                    (confirmation-message (create-message session
                                                          thread
                                                          :user
                                                          prompt
                                                          :metadata (list :source source
                                                                          :approval-confirmation-p t
                                                                          :session-id session-id
                                                                          :approval-id approval-id
                                                                          :work-item-id generic-work-item-id
                                                                          :policy-ids policy-ids
                                                                          :actor-message-ids actor-message-ids
                                                                          :receiver-roles receiver-roles)))
                    (turn (start-turn session
                                      thread
                                      confirmation-message
                                      :metadata (list :source source
                                                      :streamed-p nil
                                                      :approval-confirmation-p t
                                                      :session-id session-id
                                                      :approval-id approval-id
                                                      :work-item-id generic-work-item-id
                                                      :policy-ids policy-ids
                                                      :actor-message-ids actor-message-ids
                                                      :receiver-roles receiver-roles)))
                    (approval-result
                      (if approval-id
                          (service-response-data
                           (command-desktop-task-approve-approval-service
                            session
                            provider
                            approval-id
                            :session-id session-id
                            :source source
                            :operator-mode operator-mode))
                          (progn
                            (unless policy-ids
                              (error "Pending governed work-item ~A does not expose approval policies."
                                     generic-work-item-id))
                            (dolist (policy-id policy-ids)
                              (approve-policy session policy-id))
                            (multiple-value-bind (resume-result resume-kind)
                                (execute-command
                                 (normalize-form-command
                                  (list 'turn/resume
                                        (or (and (getf pending-approval-context :turn)
                                                 (turn-id (getf pending-approval-context :turn)))
                                            (getf pending-approval-context :turn-id))))
                                 provider
                                 session)
                              (declare (ignore resume-kind))
                              (list :summary (or (getf resume-result :summary)
                                                 "Approved and resumed governed work.")
                                    :result resume-result)))))
                    (canonical-task-results
                      (or (getf approval-result :desktop-task-results)
                          '()))
                    (task-record-summaries
                      (or (getf approval-result :task-record-summaries)
                          '()))
                    (assistant-content
                      (or (getf approval-result :assistant-message)
                          (getf approval-result :summary)
                          "Approved and completed the requested action."))
                    (response (make-assistant-response
                               :message assistant-content
                               :actions '()
                               :metadata (append (list :source source
                                                       :approval-confirmation-p t
                                                       :session-id session-id
                                                       :approval-id approval-id
                                                       :work-item-id generic-work-item-id
                                                       :policy-ids policy-ids
                                                       :actor-message-ids actor-message-ids
                                                       :receiver-roles receiver-roles)
                                                 (when canonical-task-results
                                                   (list :desktop-task-results canonical-task-results))
                                                 (when task-record-summaries
                                                   (list :task-record-summaries task-record-summaries)))))
                    (assistant-message (create-message session
                                                       thread
                                                       :assistant
                                                       assistant-content
                                                       :content-type :text
                                                       :metadata (list :source source
                                                                       :streamed-p nil
                                                                       :approval-confirmation-p t
                                                                       :session-id session-id
                                                                       :approval-id approval-id
                                                                       :work-item-id generic-work-item-id
                                                                       :policy-ids policy-ids
                                                                       :actor-message-ids actor-message-ids
                                                                       :receiver-roles receiver-roles
                                                                       :desktop-task-results canonical-task-results
                                                                       :task-record-summaries task-record-summaries)))
                    (completed-turn (complete-turn session
                                                  thread
                                                  turn
                                                  assistant-message
                                                  :status :completed
                                                  :metadata (list :stream-event-count 0
                                                                  :approval-confirmation-p t
                                                                  :session-id session-id
                                                                  :approval-id approval-id
                                                                  :work-item-id generic-work-item-id
                                                                  :policy-ids policy-ids
                                                                  :actor-message-ids actor-message-ids
                                                                  :receiver-roles receiver-roles)))
                    (empty-action-report
                      (list :staged-actions '()
                            :deferred-actions '()
                            :immediate-actions '()))
                    (response-payload
                      (append (make-say-turn-result thread
                                                    confirmation-message
                                                    assistant-message
                                                    completed-turn
                                                    response
                                                    empty-action-report
                                                    :streamed-p nil
                                                    :stream-event-count 0)
                              (list :session-id session-id
                                    :approval-id approval-id
                                    :work-item-id generic-work-item-id)
                              (when canonical-task-results
                                (list :desktop-task-results canonical-task-results))
                              (when task-record-summaries
                                (list :task-record-summaries task-record-summaries)))))
               (finalize-governed-desktop-task-plan-from-record-summaries
                session
                task-record-summaries
                assistant-content)
               (append-transcript-entry session :user prompt)
               (append-transcript-entry session :assistant assistant-content)
               (append-session-event session
                                     :assistant-response
                                     response
                                     :family :assistant
                                     :thread-id (thread-id thread)
                                     :turn-id (turn-id completed-turn)
                                     :visibility :operator)
               (kernelize-service-command-response
                (make-service-command-response :execution
                                               source
                                               response-payload
                                               :metadata (make-service-metadata :authority :environment
                                                                                :command-model :conversation-execution-v1
                                                                                :session session
                                                                                :thread-id (thread-id thread)
                                                                                :turn-id (turn-id completed-turn)))
                :session session
                :intention prompt
                :capability (ecase source
                              (:ask :conversation/ask)
                              (:say :conversation/say))
                :authority operator-mode
                :constraints (list :approval-confirmation-p t))))
            (direct-runtime-eval
             (append-conversation-execution-debug-log
              :direct-runtime-eval-before-request
              :prompt prompt
              :reason (getf direct-runtime-eval :reason)
              :form (getf direct-runtime-eval :form))
             (let* ((runtime-request
                      (make-runtime-evaluate-desktop-task-request
                       session
                       prompt
                       (getf direct-runtime-eval :form)
                       (getf direct-runtime-eval :reason)
                       surface-context
                       surface-actions))
                    (base-result
                      (run-direct-conversation-desktop-task-requests session
                                                                     prompt
                                                                     (list runtime-request)
                                                                     :source source
                                                                     :operator-mode operator-mode
                                                                     :surface-context surface-context
                                                                     :surface-actions surface-actions))
                    (result (append
                             base-result
                             (list :direct-runtime-eval-p t
                                   :direct-runtime-eval-reason
                                   (getf direct-runtime-eval :reason)
                                   :runtime-result
                                   (let ((results (getf base-result :desktop-task-results)))
                                     (and (listp results)
                                          (first results)))))))
               (append-conversation-execution-debug-log
                :direct-runtime-eval-after-request
                :prompt prompt
                :reason (getf direct-runtime-eval :reason)
                :thread-id (getf (getf result :thread) :id)
                :turn-id (getf (getf result :turn) :id))
               (kernelize-service-command-response
                (make-service-command-response :execution
                                               source
                                               result
                                               :metadata (make-service-metadata :authority :environment
                                                                                :command-model :conversation-execution-v1
                                                                                :session session
                                                                                :thread-id (getf (getf result :thread) :id)
                                                                                :turn-id (getf (getf result :turn) :id)
                                                                                :runtime-id (default-runtime-id)
                                                                                :policy-id :runtime-eval-safe))
                :session session
                :intention prompt
                :capability :runtime/eval
                :authority operator-mode
                :constraints (list :direct-runtime-eval-p t :policy-id :runtime-eval-safe))))
            (t
             (let* ((stream-p (or (and (option-present-p options :stream)
                                       (plist-value options :stream nil))
                                  *default-ask-streaming*
                                  (not (null *task-progress-callback*))))
                    (attachments (plist-value options :attachments nil))
                    (direct-desktop-task-requests
                      (plan-governed-desktop-task-requests
                       prompt
                       surface-context
                       surface-actions))
                    (result
                      (if direct-desktop-task-requests
                          (run-direct-conversation-desktop-task-requests session
                                                                         prompt
                                                                         direct-desktop-task-requests
                                                                         :source source
                                                                         :operator-mode operator-mode
                                                                         :surface-context surface-context
                                                                         :surface-actions surface-actions)
                          (run-conversation-turn provider
                                                 session
                                                 prompt
                                                 :stream-p stream-p
                                                 :attachments attachments
                                                 :surface-context surface-context
                                                 :surface-actions surface-actions
                                                 :source source
                                                 :operator-mode operator-mode))))
               (kernelize-service-command-response
                (make-service-command-response :execution
                                               source
                                               result
                                               :metadata (make-service-metadata :authority :environment
                                                                                :command-model :conversation-execution-v1
                                                                                :session session
                                                                                :thread-id (getf (getf result :thread) :id)
                                                                                :turn-id (getf (getf result :turn) :id)))
                :session session
                :intention prompt
                :capability (ecase source
                              (:ask :conversation/ask)
                              (:say :conversation/say))
                :authority operator-mode
                :context (append (list :stream-p stream-p
                                       :operator-mode operator-mode)
                                 (when direct-desktop-task-requests
                                   (list :desktop-task-p t
                                         :task-count (length direct-desktop-task-requests)
                                         :task-targets (remove-duplicates
                                                        (mapcar #'desktop-task-request-target
                                                                direct-desktop-task-requests)
                                                        :test #'eq))))))))))))

(defun command-conversation-execution-service (session provider prompt options
                                                &key (source :say) (operator-mode :conversation))
  (let* ((active-thread (ignore-errors (current-thread session)))
         (actor-address (make-standard-actor-address :context-chat
                                                     :scope (agent-session-id session)))
         (request
           (make-governed-desktop-task-request
            :requester :context-chat
            :target :context-chat
            :operation source
            :capability (ecase source
                          (:ask :conversation/ask)
                          (:say :conversation/say))
            :payload (list :prompt prompt
                           :options options
                           :source source
                           :operator-mode operator-mode)
            :metadata (append (list :prompt prompt
                                    :session-id (agent-session-id session)
                                    :actor-slice :context-chat-conversation-v1
                                    :operator-mode operator-mode)
                              (when active-thread
                                (list :thread-id (thread-id active-thread)))))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorized-service-response
        (perform-conversation-execution-service session
                                                provider
                                                prompt
                                                options
                                                :source source
                                                :operator-mode operator-mode)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability (desktop-task-request-capability request)
               :target :context-chat
               :operation source
               :request-id (desktop-task-request-id request)
               :thread-id (and active-thread (thread-id active-thread))))))

(defun command-execute-assistant-action-service (session action &key thread turn operation)
  (kernelize-service-command-response
   (make-service-command-response :execution
                                  :assistant-action
                                  (execute-assistant-action action
                                                           session
                                                           :thread thread
                                                           :turn turn
                                                           :operation operation)
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :assistant-action-execution-v1
                                                                   :session session
                                                                   :thread-id (and thread (thread-id thread))
                                                                   :turn-id (and turn (turn-id turn))))
   :session session
   :intention "Execute a staged assistant action."
   :capability :assistant/action
   :authority :environment
   :context (list :thread-id (and thread (thread-id thread))
                  :turn-id (and turn (turn-id turn))
                  :operation operation)))

(defun command-execute-pending-actions-service (session &key thread turn operation)
  (let ((actions (agent-session-pending-actions session)))
    (unless actions
      (error "No pending assistant actions are staged in the current session"))
    (let ((results (execute-assistant-action-list actions
                                                  session
                                                  :thread thread
                                                  :turn turn
                                                  :operation operation)))
      (clear-pending-actions session)
      (kernelize-service-command-response
       (make-service-command-response :execution
                                      :pending-actions
                                      results
                                      :metadata (make-service-metadata :authority :environment
                                                                       :command-model :assistant-action-execution-v1
                                                                       :session session
                                                                       :thread-id (and thread (thread-id thread))
                                                                       :turn-id (and turn (turn-id turn))))
       :session session
       :intention "Execute all currently staged pending actions."
       :capability :assistant/pending-actions
       :authority :environment
       :context (list :thread-id (and thread (thread-id thread))
                      :turn-id (and turn (turn-id turn))
                      :operation operation)))))
