(in-package #:sbcl-agent)

(declaim (special *current-environment*))

(defclass provider () ())

(defstruct provider-request
  prompt
  session-summary
  thread-context
  turn-context
  environment-context
  runtime-summary
  workspace-summary
  policy-summary
  operator-mode
  stream-p)

(defstruct provider-environment-snapshot
  environment
  environment-summary
  conversation-state
  workflow-state
  incident-summary)

(defstruct provider-context-bundle
  snapshot
  session-summary
  thread-context
  turn-context
  environment-context
  runtime-summary
  workspace-summary
  policy-summary)

(defstruct provider-request-snapshot
  session-summary
  thread-context
  turn-context
  environment-context
  runtime-summary
  workspace-summary
  policy-summary)

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

(defun provider-bound-environment (session)
  (let ((environment (and (boundp '*current-environment*)
                          *current-environment*)))
    (when (and environment
               (eq (environment-compatibility-session environment) session))
      environment)))

(defun build-provider-environment-snapshot (session)
  (let ((environment (provider-bound-environment session)))
    (when environment
      (make-provider-environment-snapshot
       :environment environment
       :environment-summary (environment-summary environment)
       :conversation-state (environment-conversation-state environment)
       :workflow-state (environment-workflow-state environment)
       :incident-summary (getf (environment-summaries environment) :incident-summary)))))

(defun ensure-provider-environment-snapshot (session snapshot)
  (or snapshot
      (build-provider-environment-snapshot session)))

(defun provider-snapshot-environment-summary-value (snapshot key)
  (and snapshot
       (getf (provider-environment-snapshot-environment-summary snapshot) key)))

(defun provider-snapshot-runtime-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :runtime-state)
             key)))

(defun provider-snapshot-conversation-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :conversation-state)
             key)))

(defun provider-snapshot-workflow-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :workflow-state)
             key)))

(defun provider-snapshot-agent-summary-value (snapshot key)
  (and snapshot
       (getf (getf (provider-environment-snapshot-environment-summary snapshot) :agent-state)
             key)))

(defun provider-snapshot-policy-state-value (snapshot key)
  (let ((environment (and snapshot
                          (provider-environment-snapshot-environment snapshot))))
    (and environment
         (getf (environment-policy-state environment) key))))

(defun provider-snapshot-open-incident-count (snapshot)
  (and snapshot
       (getf (provider-snapshot-environment-summary-value snapshot :incident-summary)
             :open-count)))

(defun provider-snapshot-operator-status-value (snapshot key)
  (and snapshot
       (getf (provider-snapshot-environment-summary-value snapshot :operator-status)
             key)))

(defun provider-session-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :id (provider-snapshot-environment-summary-value snapshot :session-id)
              :cwd (provider-snapshot-environment-summary-value snapshot :storage-root)
              :package (provider-snapshot-runtime-summary-value snapshot :package)
              :current-thread-id (provider-snapshot-environment-summary-value snapshot :active-thread-id)
              :thread-count (provider-snapshot-environment-summary-value snapshot :thread-count)
              :message-count (provider-snapshot-conversation-summary-value snapshot :message-count)
              :turn-count (provider-snapshot-conversation-summary-value snapshot :turn-count)
              :operation-count (provider-snapshot-conversation-summary-value snapshot :operation-count)
              :incident-count (provider-snapshot-environment-summary-value snapshot :incident-count)
              :open-incident-count (provider-snapshot-open-incident-count snapshot)
              :plan (provider-snapshot-environment-summary-value snapshot :plan)
              :approved-policies (provider-snapshot-policy-state-value snapshot :approved-policies)
              :pending-action-count (provider-snapshot-agent-summary-value snapshot :pending-action-count)
              :active-worker-count (provider-snapshot-agent-summary-value snapshot :active-worker-count)
              :environment-id (and environment (environment-id environment))
              :active-runtime-id (and environment (environment-active-runtime-id environment))
              :artifact-summary (provider-snapshot-environment-summary-value snapshot :artifact-summary)
              :transcript-count (length (agent-session-transcript session))
              :recent-transcript (mapcar #'provider-transcript-entry
                                         (recent-session-transcript session)))
        (list :id (agent-session-id session)
              :cwd (agent-session-cwd session)
              :package (agent-session-package session)
              :current-thread-id (agent-session-current-thread-id session)
              :thread-count (length (agent-session-threads session))
              :message-count (length (agent-session-messages session))
              :turn-count (length (agent-session-turns session))
              :operation-count (length (agent-session-operations session))
              :incident-count (length (agent-session-incidents session))
              :open-incident-count (getf (session-incident-summary session) :open-count)
              :plan (agent-session-plan session)
              :approved-policies (session-approved-policies session)
              :pending-action-count (length (agent-session-pending-actions session))
              :active-worker-count (active-worker-count session)
              :environment-id nil
              :active-runtime-id nil
              :artifact-summary (session-artifact-summary session)
              :transcript-count (length (agent-session-transcript session))
              :recent-transcript (mapcar #'provider-transcript-entry
                                         (recent-session-transcript session))))))

(defun provider-runtime-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :cwd (provider-snapshot-environment-summary-value snapshot :storage-root)
              :package (provider-snapshot-runtime-summary-value snapshot :package)
              :approved-policies (provider-snapshot-policy-state-value snapshot :approved-policies)
              :pending-action-count (provider-snapshot-agent-summary-value snapshot :pending-action-count)
              :active-worker-count (provider-snapshot-agent-summary-value snapshot :active-worker-count)
              :incident-count (provider-snapshot-environment-summary-value snapshot :incident-count)
              :open-incident-count (provider-snapshot-open-incident-count snapshot)
              :environment-id (and environment (environment-id environment))
              :active-runtime-id (and environment (environment-active-runtime-id environment)))
        (list :cwd (agent-session-cwd session)
              :package (agent-session-package session)
              :approved-policies (session-approved-policies session)
              :pending-action-count (length (agent-session-pending-actions session))
              :active-worker-count (active-worker-count session)
              :incident-count (length (agent-session-incidents session))
              :open-incident-count (getf (session-incident-summary session) :open-count)
              :environment-id nil
              :active-runtime-id nil))))

(defun provider-workspace-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :cwd (provider-snapshot-environment-summary-value snapshot :storage-root)
              :artifact-count (provider-snapshot-environment-summary-value snapshot :artifact-count)
              :artifact-summary (provider-snapshot-environment-summary-value snapshot :artifact-summary)
              :work-item-count (provider-snapshot-environment-summary-value snapshot :work-item-count)
              :workflow-record-count (provider-snapshot-workflow-summary-value snapshot :workflow-record-count)
              :incident-count (provider-snapshot-environment-summary-value snapshot :incident-count)
              :quarantined-work-item-count (provider-snapshot-operator-status-value snapshot :quarantined-count)
              :environment-id (and environment (environment-id environment)))
        (list :cwd (agent-session-cwd session)
              :artifact-count (length (agent-session-artifacts session))
              :artifact-summary (session-artifact-summary session)
              :work-item-count (length (agent-session-work-items session))
              :workflow-record-count (length (agent-session-workflow-records session))
              :incident-count (length (agent-session-incidents session))
              :quarantined-work-item-count (getf (session-operator-status session) :quarantined-count)
              :environment-id nil))))

(defun provider-policy-summary (session &optional snapshot)
  (ensure-default-thread session)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot (provider-environment-snapshot-environment snapshot))))
    (if snapshot
        (list :approved-policies (provider-snapshot-policy-state-value snapshot :approved-policies)
              :capability-grants (provider-snapshot-policy-state-value snapshot :capability-grants)
              :open-incident-count (provider-snapshot-open-incident-count snapshot)
              :environment-id (and environment (environment-id environment)))
        (list :approved-policies (session-approved-policies session)
              :capability-grants (session-capability-grants-summary session)
              :open-incident-count (getf (session-incident-summary session) :open-count)
              :environment-id nil))))

(defun provider-thread-context (session &optional thread snapshot)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (active-thread (or thread
                            (and snapshot
                                 (environment-active-thread-summary
                                  (provider-environment-snapshot-environment snapshot)))
                            (current-thread session))))
    (when active-thread
      (if (typep active-thread 'thread)
          (thread-record-summary active-thread)
          active-thread))))

(defun provider-turn-context (session &optional turn snapshot)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (active-turn (or turn
                          (and snapshot
                               (environment-active-turn-summary
                                (provider-environment-snapshot-environment snapshot)))
                          (most-recent-thread-turn session))))
    (when active-turn
      (if (typep active-turn 'turn)
          (turn-detail session (turn-id active-turn))
          active-turn))))

(defun limited-record-refs (records id-key &key (limit 5) extra-keys)
  (mapcar (lambda (record)
            (append (list :id (getf record id-key))
                    (loop for key in extra-keys
                          append (list key (getf record key)))))
          (subseq records 0 (min limit (length records)))))

(defun provider-work-item-refs (work-items &key (limit 5))
  (limited-record-refs (mapcar #'work-item-summary work-items)
                       :id
                       :limit limit
                       :extra-keys '(:status :goal :closure-decision)))

(defun provider-environment-context (session &optional snapshot)
  (let* ((snapshot (ensure-provider-environment-snapshot session snapshot))
         (environment (and snapshot
                          (provider-environment-snapshot-environment snapshot))))
    (when environment
      (let* ((conversation-state (provider-environment-snapshot-conversation-state snapshot))
             (workflow-state (provider-environment-snapshot-workflow-state snapshot))
             (conversation-summary (and conversation-state
                                        (environment-conversation-state-summaries conversation-state)))
             (workflow-summary (and workflow-state
                                    (environment-workflow-state-summaries workflow-state)))
             (threads (and conversation-state
                           (environment-conversation-state-threads conversation-state)))
             (artifacts (and conversation-state
                             (environment-conversation-state-artifacts conversation-state)))
             (work-items (and workflow-state
                              (environment-workflow-state-work-items workflow-state)))
             (incidents (provider-environment-snapshot-incident-summary snapshot)))
        (list :environment-id (environment-id environment)
              :active-runtime-id (environment-active-runtime-id environment)
              :active-thread-id (environment-active-thread-id environment)
              :thread-count (getf conversation-summary :thread-count)
              :artifact-count (getf conversation-summary :artifact-count)
              :work-item-count (getf workflow-summary :work-item-count)
              :reconciliation-count (getf workflow-summary :reconciliation-count)
              :open-incident-count (getf incidents :open-count)
              :thread-refs (limited-record-refs threads :id :extra-keys '(:title :status))
              :artifact-refs (limited-record-refs artifacts :id :extra-keys '(:kind :title :turn-id))
              :work-item-refs (provider-work-item-refs work-items)
              :recent-incident-refs (limited-record-refs (or (getf incidents :recent) '())
                                                         :id
                                                         :extra-keys '(:kind :status :turn-id)))))))

(defun build-provider-context-bundle (session &key thread turn)
  (ensure-default-thread session)
  (let* ((snapshot (build-provider-environment-snapshot session))
         (thread-context (provider-thread-context session thread snapshot))
         (turn-context (provider-turn-context session turn snapshot)))
    (make-provider-context-bundle
     :snapshot snapshot
     :session-summary (provider-session-summary session snapshot)
     :thread-context thread-context
     :turn-context turn-context
     :environment-context (provider-environment-context session snapshot)
     :runtime-summary (provider-runtime-summary session snapshot)
     :workspace-summary (provider-workspace-summary session snapshot)
     :policy-summary (provider-policy-summary session snapshot))))

(defun provider-context-bundle->request-snapshot (bundle)
  (when bundle
    (make-provider-request-snapshot
     :session-summary (provider-context-bundle-session-summary bundle)
     :thread-context (provider-context-bundle-thread-context bundle)
     :turn-context (provider-context-bundle-turn-context bundle)
     :environment-context (provider-context-bundle-environment-context bundle)
     :runtime-summary (provider-context-bundle-runtime-summary bundle)
     :workspace-summary (provider-context-bundle-workspace-summary bundle)
     :policy-summary (provider-context-bundle-policy-summary bundle))))

(defun make-provider-request-from-session (prompt session
                                          &key thread turn
                                            (operator-mode :repl-bridge)
                                            stream-p)
  (let ((active-session (or session (ignore-errors (ensure-session)))))
    (let* ((bundle (and active-session
                        (build-provider-context-bundle active-session
                                                       :thread thread
                                                       :turn turn)))
           (request-snapshot (provider-context-bundle->request-snapshot bundle)))
      (make-provider-request :prompt prompt
                             :session-summary (and request-snapshot
                                                   (provider-request-snapshot-session-summary request-snapshot))
                             :thread-context (and request-snapshot
                                                  (provider-request-snapshot-thread-context request-snapshot))
                             :turn-context (and request-snapshot
                                                (provider-request-snapshot-turn-context request-snapshot))
                             :environment-context (and request-snapshot
                                                      (provider-request-snapshot-environment-context request-snapshot))
                             :runtime-summary (and request-snapshot
                                                   (provider-request-snapshot-runtime-summary request-snapshot))
                             :workspace-summary (and request-snapshot
                                                     (provider-request-snapshot-workspace-summary request-snapshot))
                             :policy-summary (and request-snapshot
                                                  (provider-request-snapshot-policy-summary request-snapshot))
                             :operator-mode operator-mode
                             :stream-p stream-p))))

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

(defun mutating-eval-action-p (action)
  (and (eq (assistant-action-type action) :eval)
       (let ((payload (assistant-action-payload action)))
         (and (listp payload)
              (or (getf payload :MUTATING)
                  (getf payload :mutating)
                  (eq (getf payload :MODE) :mutate)
                  (eq (getf payload :mode) :mutate))))))

(defun execute-assistant-action (action session &key thread turn operation)
  (case (assistant-action-type action)
    (:TOOL
     (let* ((payload (assistant-action-payload action))
            (tool-id (or (getf payload :TOOL-ID)
                         (getf payload :TOOL_ID)))
            (arguments (or (getf payload :ARGUMENTS)
                           (getf payload :arguments)))
            (*runtime-governance-thread* thread)
            (*runtime-governance-turn* turn)
            (*runtime-governance-operation* operation))
       (declare (special *runtime-governance-thread*
                         *runtime-governance-turn*
                         *runtime-governance-operation*))
       (unless (keywordp tool-id)
         (error "Assistant tool action requires keyword tool id, got ~S" tool-id))
       (apply #'invoke-tool tool-id session (or arguments '()))))
    (:PATCH
     (apply-patch-operations session
                             (assistant-action-payload action)
                             :thread thread
                             :turn turn
                             :operation operation))
    (:EVAL
     (let* ((payload (assistant-action-payload action))
            (*runtime-governance-thread* thread)
            (*runtime-governance-turn* turn)
            (*runtime-governance-operation* operation))
       (declare (special *runtime-governance-thread*
                         *runtime-governance-turn*
                         *runtime-governance-operation*))
       (tool-runtime-eval session
                          :form (parse-eval-action-form payload)
                          :mutating (mutating-eval-action-p action))))
    (t
     (error "Unsupported assistant action type ~S" (assistant-action-type action)))))

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
