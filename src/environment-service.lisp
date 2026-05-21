(in-package #:sbcl-agent)

(defparameter +environment-desktop-preferences-key+ :desktop-preferences)
(defparameter +environment-agent-constitution-key+ :agent-constitution)
(defparameter *environment-provider-state-lock*
  (sb-thread:make-mutex :name "sbcl-agent-environment-provider-state"))

(defparameter +desktop-preferences-legacy-key-map+
  '((:THEMEPREFERENCE . :THEME-PREFERENCE)
    (:DESKTOPSURFACEVIEW . :DESKTOP-SURFACE-VIEW)
    (:TOOLTIPSCALEPERCENT . :TOOLTIP-SCALE-PERCENT)
    (:CONTROLICONSCALEPERCENT . :CONTROL-ICON-SCALE-PERCENT)
    (:DOCKICONSCALEPERCENT . :DOCK-ICON-SCALE-PERCENT)
    (:CONVERSATIONTEXTSCALEPERCENT . :CONVERSATION-TEXT-SCALE-PERCENT)
    (:LISPCODEVIEW . :LISP-CODE-VIEW)
    (:PARENDEPTHCOLORS . :PAREN-DEPTH-COLORS)
    (:LASTWORKSPACE . :LAST-WORKSPACE)
    (:SIDEBARPINNED . :SIDEBAR-PINNED)
    (:SIDEBARWIDTH . :SIDEBAR-WIDTH)
    (:SIDEBARACTIVEPANELID . :SIDEBAR-ACTIVE-PANEL-ID)
    (:SIDEBARDOCKEDPANELIDS . :SIDEBAR-DOCKED-PANEL-IDS)
    (:CANVASPINNED . :CANVAS-PINNED)
    (:INSPECTORPINNED . :INSPECTOR-PINNED)
    (:INSPECTORWIDTH . :INSPECTOR-WIDTH)
    (:INSPECTORACTIVEPANELID . :INSPECTOR-ACTIVE-PANEL-ID)
    (:INSPECTORDOCKEDPANELIDS . :INSPECTOR-DOCKED-PANEL-IDS)
    (:CURRENTPROJECTID . :CURRENT-PROJECT-ID)
    (:SELECTEDCONVERSATIONTHREADBYPROJECT . :SELECTED-CONVERSATION-THREAD-BY-PROJECT)
    (:CONVERSATIONDRAFT . :CONVERSATION-DRAFT)
    (:REPLSESSIONSBYPROJECT . :REPL-SESSIONS-BY-PROJECT)
    (:CURRENTREPLSESSIONIDBYPROJECT . :CURRENT-REPL-SESSION-ID-BY-PROJECT)
    (:EDITORBUFFERSBYPROJECT . :EDITOR-BUFFERS-BY-PROJECT)
    (:SELECTEDEDITORBUFFERIDBYPROJECT . :SELECTED-EDITOR-BUFFER-ID-BY-PROJECT)
    (:WORKSPACEPACKAGEBYPROJECT . :WORKSPACE-PACKAGE-BY-PROJECT)
    (:WORKSPACEDRAFTBYPROJECT . :WORKSPACE-DRAFT-BY-PROJECT)
    (:WORKSPACERESULTBYPROJECT . :WORKSPACE-RESULT-BY-PROJECT)
    (:WORKSPACEHISTORYBYPROJECT . :WORKSPACE-HISTORY-BY-PROJECT)
    (:RUNTIMESUMMARY . :RUNTIME-SUMMARY)
    (:RUNTIMEID . :RUNTIME-ID)
    (:BUFFERID . :BUFFER-ID)
    (:PACKAGENAME . :PACKAGE-NAME)
    (:DRAFTFORM . :DRAFT-FORM)
    (:LASTSUMMARY . :LAST-SUMMARY)
    (:BASELINEDRAFT . :BASELINE-DRAFT)))

(defun environment-remove-metadata-key (plist key)
  (cond
    ((null plist) '())
    ((eq (first plist) key)
     (environment-remove-metadata-key (cddr plist) key))
    (t
     (list* (first plist)
            (second plist)
            (environment-remove-metadata-key (cddr plist) key)))))

(defun environment-metadata-value (environment key &optional default)
  (if (and (listp (environment-metadata environment))
           (member key (environment-metadata environment)))
      (getf (environment-metadata environment) key)
      default))

(defun set-environment-metadata-value (environment key value)
  (let ((metadata (environment-remove-metadata-key
                   (copy-list (or (environment-metadata environment) '()))
                   key)))
    (when value
      (setf metadata (append metadata (list key value))))
    (setf (environment-metadata environment) metadata)))

(defun environment-provider-state-snapshot (environment)
  (let ((active-environment (ensure-environment environment)))
    (sb-thread:with-mutex (*environment-provider-state-lock*)
      (list :provider-profiles
            (copy-tree (or (environment-metadata-value active-environment
                                                       :provider-profiles)
                           '()))
            :active-provider-profile
            (environment-metadata-value active-environment
                                        :active-provider-profile)
            :provider-routing-mode
            (environment-metadata-value active-environment
                                        :provider-routing-mode)
            :last-provider-route
            (copy-tree (environment-metadata-value active-environment
                                                   :last-provider-route))))))

(defun replace-environment-provider-state (environment state)
  (let ((active-environment (ensure-environment environment)))
    (sb-thread:with-mutex (*environment-provider-state-lock*)
      (set-environment-metadata-value active-environment
                                      :provider-profiles
                                      (copy-tree (getf state :provider-profiles)))
      (set-environment-metadata-value active-environment
                                      :active-provider-profile
                                      (getf state :active-provider-profile))
      (set-environment-metadata-value active-environment
                                      :provider-routing-mode
                                      (getf state :provider-routing-mode))
      (set-environment-metadata-value active-environment
                                      :last-provider-route
                                      (copy-tree (getf state :last-provider-route))))))

(defun default-agent-constitution ()
  (list :id :sbcl-agent
        :version 2
        :charter-version 1
        :identity "SBCL Agent"
        :system-role :self-hosted-agentic-coding-agent
        :purpose "Operate as a governed, introspective, self-hosted coding agent."
        :mission "Deliver grounded planning, implementation, validation, and recovery while preserving environment integrity and operator trust."
        :governance-posture :actor-runtime-mediated
        :operating-principles
        '("Prefer authoritative environment state over inferred assumptions."
          "Route public execution through actor and runtime authority boundaries."
          "Keep planning evidence-backed, uncertainty-aware, and minimally sufficient."
          "Treat governance, validation, and recovery obligations as first-class constraints."
          "Improve the system only within explicit safety and policy boundaries.")
        :goals
        '("Understand the live system state before mutating it."
          "Respect project constitutions and environment governance."
          "Produce robust plans, safe changes, and verifiable outcomes."
          "Remain legible, inspectable, and recoverable across sessions.")
        :objectives
        '("Maintain a truthful self-model across sessions."
          "Use introspective state as the grounding substrate for planning and execution."
          "Select minimally sufficient context for reasoning, mutation, and validation."
          "Preserve governed recovery and auditability under failure or interruption.")
        :optimization-priorities
        '(:truthfulness
          :governance-integrity
          :recovery
          :validation
          :context-efficiency
          :operator-legibility)
        :constraints
        '("Do not treat prose alone as execution."
          "Do not bypass actor or kernel authority for public read/write control paths."
          "Do not assume context is complete when authoritative evidence is missing or conflicting."
          "Do not prioritize convenience over recovery, validation, or governance integrity.")
        :hard-invariants
        '("presentation-tier-ingress-is-actor-mediated"
          "actor-public-execution-is-kernel-mediated"
          "authoritative-environment-state-outranks-speculation"
          "governed-mutation-requires-policy-compatible-execution"
          "recovery-and-validation-obligations-remain-visible-in-planning")
        :self-improvement-boundaries
        '("Do not self-modify architecture or policy posture without explicit operator intent."
          "Do not widen capability authority from inferred convenience."
          "Do not suppress uncertainty, conflict, or recovery evidence to simplify planning.")))

(defun merged-agent-constitution (constitution)
  (let ((merged (copy-tree (default-agent-constitution))))
    (loop for tail on (or constitution '()) by #'cddr
          do (setf (getf merged (first tail)) (copy-tree (second tail))))
    merged))

(defun environment-agent-constitution (&optional environment)
  (merged-agent-constitution
   (environment-metadata-value (ensure-environment environment)
                               +environment-agent-constitution-key+)))

(defun set-environment-agent-constitution (environment constitution)
  (set-environment-metadata-value (ensure-environment environment)
                                  +environment-agent-constitution-key+
                                  (merged-agent-constitution constitution)))

(defun canonical-desktop-preferences-key (key)
  (or (cdr (assoc key +desktop-preferences-legacy-key-map+))
      key))

(defun desktop-preferences-property-list-p (value)
  (and (listp value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             for key = (first tail)
             always (keywordp key))))

(defun canonicalize-desktop-preferences-value (value)
  (cond
    ((desktop-preferences-property-list-p value)
     (let ((result '()))
       (loop for tail on value by #'cddr
             for key = (canonical-desktop-preferences-key (first tail))
             for val = (canonicalize-desktop-preferences-value (second tail))
             do (setf (getf result key) val))
       result))
    ((listp value)
     (mapcar #'canonicalize-desktop-preferences-value value))
    (t
     value)))

(defun environment-desktop-preferences (&optional environment)
  (copy-tree
   (canonicalize-desktop-preferences-value
    (or (environment-metadata-value (ensure-environment environment)
                                    +environment-desktop-preferences-key+)
        '()))))

(defun set-environment-desktop-preferences (environment preferences)
  (set-environment-metadata-value (ensure-environment environment)
                                  +environment-desktop-preferences-key+
                                  (copy-tree
                                   (canonicalize-desktop-preferences-value preferences))))

(defun query-environment-desktop-preferences-service (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (make-service-query-response :environment
                                 :desktop-preferences
                                 (environment-desktop-preferences active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-desktop-preferences-v1
                                                                  :environment active-environment))))

(defun ambient-session-compatible-with-environment-p (session environment)
  (and session
       environment
       (eq (session-bound-environment session) environment)))

(defun environment-control-bound-session (environment)
  (or (environment-session environment)
      (let ((session (and (boundp '*current-session*)
                          *current-session*)))
        (and (ambient-session-compatible-with-environment-p session environment)
             session))
      (error "Environment control requires a session bound to the target environment.")))

(defun make-environment-control-actor-address (environment)
  (let ((session (environment-control-bound-session environment)))
    (make-standard-actor-address :environment
                                 :scope (agent-session-id session))))

(defun actorize-environment-command-response (response
                                              &key actor-execution-job-id
                                                governance-authority
                                                policy-id
                                                approval-required-p
                                                approval-granted-p)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id)
        (when governance-authority
          (setf (getf metadata :governance-authority) governance-authority))
        (when policy-id
          (setf (getf metadata :policy-id) policy-id))
        (setf (getf metadata :approval-required-p) (and approval-required-p t)
              (getf metadata :approval-granted-p) (and approval-granted-p t)
              (getf response :metadata) metadata)
        (when (keyword-plist-p data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id)
            (when governance-authority
              (setf (getf updated-data :governance-authority) governance-authority))
            (when policy-id
              (setf (getf updated-data :policy-id) policy-id))
            (setf (getf updated-data :approval-required-p) (and approval-required-p t)
                  (getf updated-data :approval-granted-p) (and approval-granted-p t)
                  (getf response :data) updated-data)))
        response)
      response))

(defun actorize-environment-query-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (keyword-plist-p data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun command-environment-desktop-preferences-query-service (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request active-environment
                                       :desktop-preferences-query
                                       :environment/preferences-read
                                       :payload '())
     (lambda ()
       (query-environment-desktop-preferences-service active-environment))
     :environment/preferences-read
     :desktop-preferences-query)))

(defun command-environment-provider-query-service (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request active-environment
                                       :provider-query
                                       :environment/provider
                                       :payload '())
     (lambda ()
       (query-environment-provider-service active-environment))
     :environment/provider
     :provider-query)))

(defun command-environment-summary-query-service (&optional environment
                                                   &key (include-alignment-state-p t)
                                                        (include-reconciliation-decision-p t))
  (let ((active-environment (ensure-environment environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request
      active-environment
      :summary-query
     :environment/summary
     :payload (list :include-alignment-state-p include-alignment-state-p
                     :include-reconciliation-decision-p include-reconciliation-decision-p))
     (lambda ()
       (query-environment-summary-service
        active-environment
        :include-alignment-state-p include-alignment-state-p
        :include-reconciliation-decision-p include-reconciliation-decision-p))
     :environment/summary
     :summary-query)))

(defun command-environment-status-query-service (&optional environment
                                                  &key (include-alignment-state-p t)
                                                       (include-reconciliation-decision-p t))
  (let ((active-environment (ensure-environment environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request
      active-environment
      :status-query
     :environment/status
     :payload (list :include-alignment-state-p include-alignment-state-p
                     :include-reconciliation-decision-p include-reconciliation-decision-p))
     (lambda ()
       (query-environment-status-service
        active-environment
        :include-alignment-state-p include-alignment-state-p
        :include-reconciliation-decision-p include-reconciliation-decision-p))
     :environment/status
     :status-query)))

(defun environment-control-session (environment)
  (environment-control-bound-session environment))

(defun make-environment-control-request (environment action capability
                                         &key payload metadata)
  (let ((session (environment-control-session environment)))
    (make-governed-desktop-task-request
     :requester :context-chat
     :target :environment
     :operation action
     :capability capability
     :payload payload
     :metadata (append (list :session-id (agent-session-id session)
                             :environment-id (environment-id environment)
                             :actor-slice :environment-control-v1)
                       metadata))))

(defun call-with-environment-actor (environment request thunk capability action)
  (let* ((active-environment (ensure-environment environment))
         (session (environment-control-session active-environment))
         (actor-address (make-environment-control-actor-address active-environment)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-environment-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :governance
               :target :environment
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata (list :environment-id (environment-id active-environment))))))

(defun call-with-environment-governed-command-actor (environment request thunk capability action
                                                     &key metadata policy-id approval-required-p)
  (let* ((active-environment (ensure-environment environment))
         (session (environment-control-session active-environment))
         (actor-address (make-environment-control-actor-address active-environment))
         (actor-context (make-actor-execution-context
                         :actor-id (actor-address-id actor-address)
                         :capability capability
                         :authority :governed-environment
                         :policy-id policy-id
                         :target :environment
                         :operation action
                         :request-id (desktop-task-request-id request)
                         :approval-required-p approval-required-p
                         :metadata (append (list :environment-id (environment-id active-environment))
                                           metadata)))
         (approval-granted-p (and approval-required-p
                                  policy-id
                                  (ignore-errors (policy-approved-p session policy-id)))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (when (fboundp 'update-current-actor-execution-context)
         (update-current-actor-execution-context actor-context :replace-p t))
       (when (and approval-required-p policy-id)
         (ensure-policy-approved session policy-id))
       (actorize-environment-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)
        :governance-authority :actor-runtime
        :policy-id policy-id
        :approval-required-p approval-required-p
        :approval-granted-p approval-granted-p))
     :context actor-context)))

(defun call-with-environment-query-actor (environment request thunk capability action)
  (let* ((active-environment (ensure-environment environment))
         (session (environment-control-session active-environment))
         (actor-address (make-environment-control-actor-address active-environment)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-environment-query-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :governance
               :target :environment
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata (list :environment-id (environment-id active-environment))))))

(defun perform-environment-set-desktop-preferences-service (preferences &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (set-environment-desktop-preferences active-environment preferences)
    (make-service-command-response :environment
                                   :set-desktop-preferences
                                   (environment-desktop-preferences active-environment)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-desktop-preferences-v1
                                                                    :environment active-environment))))

(defun command-environment-set-desktop-preferences-service (preferences &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (register-service-command-response
     (call-with-environment-governed-command-actor
      active-environment
      (make-environment-control-request active-environment
                                        :set-desktop-preferences
                                        :environment/preferences
                                        :payload (list :preferences preferences))
      (lambda ()
        (perform-environment-set-desktop-preferences-service preferences active-environment))
      :environment/preferences
      :set-desktop-preferences
      :metadata (list :preferences preferences))
     :session (environment-control-session active-environment)
     :intention "Set desktop preferences."
     :capability :environment/preferences
     :authority :environment)))

(defun normalize-provider-profile-name (name)
  (or (normalize-config-string name) "default"))

(defun plist-key-present-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (first tail) key)))

(defun normalize-provider-profile-keyword (value)
  (cond
    ((keywordp value) value)
    ((stringp value)
     (intern (string-upcase (string-trim '(#\Space #\Tab #\Newline #\Return) value))
             "KEYWORD"))
    (t nil)))

(defun unwrap-provider-profile-option-value (value)
  (if (and (consp value)
           (eq (first value) 'quote)
           (= (length value) 2))
      (second value)
      value))

(defun normalize-provider-profile-keywords (value)
  (let* ((unwrapped (unwrap-provider-profile-option-value value))
         (values (cond
                   ((null unwrapped) '())
                   ((listp unwrapped) unwrapped)
                   (t (list unwrapped)))))
    (remove nil
            (mapcar #'normalize-provider-profile-keyword values))))

(defun canonicalize-provider-profile (profile)
  (normalize-provider-profile (getf profile :name)
                              (list :provider (getf profile :provider)
                                    :model (getf profile :model)
                                    :fast-model (getf profile :fast-model)
                                    :api-base (getf profile :api-base)
                                    :api-key (getf profile :api-key)
                                    :intents (getf profile :intents)
                                    :latency-tier (getf profile :latency-tier)
                                    :review-bias (getf profile :review-bias)
                                    :execution-bias (getf profile :execution-bias)
                                    :locality (getf profile :locality))))

(defun normalize-provider-profile (name options)
  (let* ((provider (or (normalize-config-string (getf options :provider))
                       "openai-compatible")))
    (list :name (normalize-provider-profile-name name)
          :provider provider
          :model (or (normalize-config-string (getf options :model))
                     (provider-default-model provider))
          :fast-model (or (normalize-config-string (getf options :fast-model))
                          (provider-default-fast-model provider))
          :api-base (normalize-config-string (getf options :api-base))
          :api-key (normalize-config-string (getf options :api-key))
          :intents (normalize-provider-profile-keywords (getf options :intents))
          :latency-tier (or (normalize-provider-profile-keyword
                             (unwrap-provider-profile-option-value (getf options :latency-tier)))
                            :balanced)
          :review-bias (or (normalize-provider-profile-keyword
                            (unwrap-provider-profile-option-value (getf options :review-bias)))
                           :neutral)
          :execution-bias (or (normalize-provider-profile-keyword
                               (unwrap-provider-profile-option-value (getf options :execution-bias)))
                              :balanced)
          :locality (or (normalize-provider-profile-keyword
                         (unwrap-provider-profile-option-value (getf options :locality)))
                        (if (member provider
                                    '("lm-studio" "lmstudio" "local-openai-compatible")
                                    :test #'string-equal)
                            :local
                            :network)))))

(defun environment-provider-profiles (&optional environment)
  (mapcar #'canonicalize-provider-profile
          (or (getf (environment-provider-state-snapshot environment)
                    :provider-profiles)
              '())))

(defun environment-provider-working-directory (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (storage-root (environment-storage-root active-environment)))
    (namestring
     (uiop:ensure-directory-pathname
      (or storage-root
          (namestring (getcwd)))))))

(defun default-environment-provider-profile (&optional environment)
  (let* ((working-directory (environment-provider-working-directory environment))
         (api-key (resolve-provider-api-key "openai-compatible" working-directory)))
    (list :name "default"
          :provider "openai-compatible"
          :model (provider-default-model "openai-compatible")
          :fast-model (provider-default-fast-model "openai-compatible")
          :api-base (provider-default-api-base "openai-compatible")
          :api-key api-key
          :intents '()
          :latency-tier :balanced
          :review-bias :neutral
          :execution-bias :balanced
          :locality :network)))

(defun effective-environment-provider-profiles (&optional environment)
  (let ((profiles (environment-provider-profiles environment)))
    (if profiles
        profiles
        (list (default-environment-provider-profile environment)))))

(defun environment-active-provider-profile-name (&optional environment)
  (or (getf (environment-provider-state-snapshot environment)
            :active-provider-profile)
      "default"))

(defun environment-find-provider-profile (environment profile-name)
  (find (normalize-provider-profile-name profile-name)
        (effective-environment-provider-profiles environment)
        :key (lambda (profile) (getf profile :name))
        :test #'string=))

(defun provider-profile-resolved-api-key (profile &optional environment)
  (let* ((normalized (canonicalize-provider-profile profile))
         (provider (getf normalized :provider))
         (working-directory (environment-provider-working-directory environment))
         (legacy-api-key (normalize-config-string (getf normalized :api-key))))
    (or (resolve-provider-api-key provider working-directory)
        legacy-api-key)))

(defun provider-profile-public-view (profile &optional environment)
  (let ((public (copy-list (canonicalize-provider-profile profile))))
    (setf (getf public :api-key-present-p)
          (not (null (provider-profile-resolved-api-key profile environment))))
    (remf public :api-key)
    public))

(defun environment-provider-profile-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (provider-state (environment-provider-state-snapshot active-environment))
         (profiles (effective-environment-provider-profiles active-environment))
         (public-profiles (mapcar (lambda (profile)
                                    (provider-profile-public-view profile active-environment))
                                  profiles))
         (active-name (environment-active-provider-profile-name active-environment))
         (active-profile (let ((raw-profile (environment-find-provider-profile active-environment active-name)))
                           (and raw-profile
                                (provider-profile-public-view raw-profile active-environment))))
         (routing-mode (or (getf provider-state :provider-routing-mode) :auto))
         (last-route (getf provider-state :last-provider-route)))
    (list :active-profile-name active-name
          :profile-count (length public-profiles)
          :profiles public-profiles
          :active-profile active-profile
          :routing-mode routing-mode
          :routing-policy (list :mode routing-mode
                                :available-modes '(:auto :manual)
                                :profile-count (length public-profiles)
                                :last-route-present-p (and last-route t))
          :last-route last-route)))

(defun ensure-environment-provider-profile (&key environment config (profile-name "default"))
  (let* ((active-environment (ensure-environment environment))
         (provider-state (environment-provider-state-snapshot active-environment))
         (normalized (normalize-provider-profile
                      profile-name
                      (list :provider (config-provider config)
                            :model (config-model config)
                            :fast-model (config-fast-model config)
                            :api-base (config-api-base config))))
         (profiles (remove (getf normalized :name)
                           (or (getf provider-state :provider-profiles) '())
                           :key (lambda (profile) (getf profile :name))
                           :test #'string=)))
    (setf (getf provider-state :provider-profiles)
          (append profiles (list normalized)))
    (unless (getf provider-state :active-provider-profile)
      (setf (getf provider-state :active-provider-profile)
            (getf normalized :name)))
    (replace-environment-provider-state active-environment provider-state)
    normalized))

(defun provider-profile-provider (profile)
  (string-downcase (or (getf profile :provider) "")))

(defun provider-profile-local-p (profile)
  (member (provider-profile-provider profile)
          '("lm-studio" "lmstudio" "local-openai-compatible")
          :test #'string=))

(defun provider-profile-anthropic-p (profile)
  (string= (provider-profile-provider profile) "anthropic"))

(defun provider-profile-openai-compatible-p (profile)
  (member (provider-profile-provider profile)
          '("openai" "openai-compatible" "gemini" "google"
            "google-openai-compatible" "gemini-openai-compatible"
            "meta-compatible" "meta-openai-compatible")
          :test #'string=))

(defun provider-profile-intents (profile)
  (or (getf profile :intents) '()))

(defun provider-profile-intent-p (profile intent)
  (member intent (provider-profile-intents profile) :test #'eq))

(defun provider-profile-latency-tier (profile)
  (or (getf profile :latency-tier) :balanced))

(defun provider-profile-review-bias (profile)
  (or (getf profile :review-bias) :neutral))

(defun provider-profile-execution-bias (profile)
  (or (getf profile :execution-bias) :balanced))

(defun provider-profile-locality (profile)
  (or (getf profile :locality)
      (if (provider-profile-local-p profile) :local :network)))

(defun quick-request-p (prompt)
  (some (lambda (needle)
          (search needle prompt :test #'char-equal))
        '("quick" "fast" "brief" "simple" "short" "ping")))

(defun local-request-p (prompt)
  (some (lambda (needle)
          (search needle prompt :test #'char-equal))
        '("local" "offline" "lm studio" "lm-studio" "localhost")))

(defun code-execution-request-p (prompt)
  (some (lambda (needle)
          (search needle prompt :test #'char-equal))
        '("implement" "fix" "patch" "write code" "edit" "refactor" "change code")))

(defun best-provider-profile-match (profiles predicate &optional fallback)
  (or (find-if predicate profiles)
      fallback
      (first profiles)))

(defun provider-routing-mode (&optional environment)
  (or (getf (environment-provider-state-snapshot environment)
            :provider-routing-mode)
      :auto))

(defun normalize-provider-routing-mode (mode)
  (let ((normalized (normalize-provider-profile-keyword mode)))
    (unless (member normalized '(:auto :manual) :test #'eq)
      (error "Unsupported provider routing mode ~S" mode))
    normalized))

(defun build-routing-cognition-context (session prompt)
  (when session
    (let* ((bundle (build-provider-context-bundle session
                                                  :prompt prompt
                                                  :operator-mode :conversation))
           (dossier (and bundle
                         (provider-context-bundle-retrieval-dossier bundle)))
           (cognition (and bundle
                           (provider-context-bundle-cognition-bundle bundle))))
      (list :intent (and dossier (getf dossier :intent))
            :retrieval-dossier dossier
            :cognition-bundle cognition
            :execution-strategy (and cognition
                                     (cognition-bundle-execution-strategy cognition))
            :validation-strategy (and cognition
                                      (cognition-bundle-validation-strategy cognition))
            :validation-plan (and cognition
                                  (cognition-bundle-validation-plan cognition))))))

(defun environment-routing-governance-summary (&optional environment)
  (let* ((status (environment-status (ensure-environment environment)))
         (blocked-work (or (getf status :blocked-work) '()))
         (incidents (or (getf status :incidents) '()))
         (operator-posture (or (getf status :operator-posture) '())))
    (list :blocked-count (or (getf blocked-work :count) 0)
          :approval-count (or (getf blocked-work :approval-count) 0)
          :cold-validation-count (or (getf blocked-work :cold-validation-count) 0)
          :pending-validation-count (or (getf blocked-work :pending-validation-count) 0)
          :operator-review-count (or (getf blocked-work :operator-review-count) 0)
          :open-incident-count (or (getf incidents :open-count) 0)
          :incident-count (or (getf incidents :count) 0)
          :blocked-posture-count (or (getf operator-posture :blocked-count) 0)
          :quarantined-count (or (getf operator-posture :quarantined-count) 0))))

(defun governance-heavy-environment-p (summary)
  (or (> (or (getf summary :open-incident-count) 0) 0)
      (> (or (getf summary :blocked-count) 0) 0)
      (> (or (getf summary :quarantined-count) 0) 0)))

(defun validation-heavy-environment-p (summary)
  (or (> (or (getf summary :cold-validation-count) 0) 0)
      (> (or (getf summary :pending-validation-count) 0) 0)
      (> (or (getf summary :operator-review-count) 0) 0)))

(defun provider-profile-governance-review-p (profile)
  (or (provider-profile-intent-p profile :incident-review)
      (provider-profile-intent-p profile :governance-review)
      (provider-profile-intent-p profile :validation-review)
      (eq (provider-profile-review-bias profile) :deep)))

(defun provider-routing-reasons-for-profile (profile prompt governance-summary
                                                     intent-category mutation-likely-p
                                                     execution-strategy validation-strategy
                                                     validation-plan active-profile)
  (let ((reasons '()))
    (when (and active-profile
               (string= (getf profile :name) (getf active-profile :name)))
      (push :active-profile reasons))
    (when (local-request-p prompt)
      (when (or (eq (provider-profile-locality profile) :local)
                (provider-profile-intent-p profile :local-development))
        (push :local-request-fit reasons)))
    (when (deep-request-p prompt)
      (when (or (provider-profile-intent-p profile :architecture-review)
                (provider-profile-intent-p profile :deep-reasoning)
                (eq (provider-profile-review-bias profile) :deep)
                (provider-profile-anthropic-p profile))
        (push :deep-request-fit reasons)))
    (when (quick-request-p prompt)
      (when (or (eq (provider-profile-latency-tier profile) :fast)
                (provider-profile-intent-p profile :quick-turn)
                (eq (provider-profile-locality profile) :local)
                (provider-profile-openai-compatible-p profile))
        (push :quick-request-fit reasons)))
    (when (code-execution-request-p prompt)
      (when (or (provider-profile-intent-p profile :code-execution)
                (provider-profile-intent-p profile :implementation)
                (eq (provider-profile-execution-bias profile) :high)
                (eq (provider-profile-locality profile) :local))
        (push :code-execution-fit reasons)))
    (when (member intent-category '(:workflow-supervision :incident-follow-up) :test #'eq)
      (when (provider-profile-governance-review-p profile)
        (push :cognition-governance-intent-fit reasons)))
    (when (and validation-plan
               (> (or (getf validation-plan :work-item-count) 0) 0))
      (when (provider-profile-governance-review-p profile)
        (push :cognition-validation-plan-fit reasons)))
    (when (and validation-strategy
               (eq (getf validation-strategy :mode) :required))
      (when (provider-profile-governance-review-p profile)
        (push :cognition-required-validation-fit reasons)))
    (when (and (validation-heavy-environment-p governance-summary)
               (code-execution-request-p prompt))
      (when (provider-profile-governance-review-p profile)
        (push :validation-governance-fit reasons)))
    (when (and (governance-heavy-environment-p governance-summary)
               (code-execution-request-p prompt))
      (when (provider-profile-governance-review-p profile)
        (push :incident-governance-fit reasons)))
    (when (and mutation-likely-p
               execution-strategy
               (member (getf execution-strategy :mode)
                       '(:mutation-ready :inspection-first)
                       :test #'eq))
      (when (or (provider-profile-intent-p profile :code-execution)
                (provider-profile-intent-p profile :implementation)
                (eq (provider-profile-execution-bias profile) :high)
                (eq (provider-profile-locality profile) :local))
        (push :cognition-mutation-ready-fit reasons)))
    (nreverse reasons)))

(defun provider-routing-score (reasons)
  (reduce #'+
          (mapcar (lambda (reason)
                    (case reason
                      ((:cognition-validation-plan-fit
                        :cognition-required-validation-fit
                        :validation-governance-fit
                        :incident-governance-fit
                        :cognition-governance-intent-fit)
                       10)
                      ((:cognition-mutation-ready-fit :deep-request-fit :code-execution-fit)
                       6)
                      ((:local-request-fit :quick-request-fit)
                       4)
                      (:active-profile 1)
                      (otherwise 0)))
                  reasons)
          :initial-value 0))

(defun provider-routing-primary-reason (candidate-rankings active-profile)
  (let* ((winner (first candidate-rankings))
         (reasons (or (getf winner :reasons) '()))
         (selected-name (getf winner :profile-name)))
    (cond
      ((member :cognition-governance-intent-fit reasons) :cognition-governance-intent)
      ((member :cognition-validation-plan-fit reasons) :cognition-validation-plan)
      ((member :cognition-required-validation-fit reasons) :cognition-required-validation)
      ((member :validation-governance-fit reasons) :validation-governance-request)
      ((member :incident-governance-fit reasons) :incident-governance-request)
      ((member :cognition-mutation-ready-fit reasons) :cognition-mutation-ready)
      ((member :local-request-fit reasons) :local-request)
      ((member :deep-request-fit reasons) :deep-request)
      ((member :code-execution-fit reasons) :code-execution-request)
      ((member :quick-request-fit reasons) :quick-request)
      ((and active-profile
            selected-name
            (string= selected-name (getf active-profile :name)))
       :active-profile)
      (t :active-profile))))

(defun ranked-provider-profile-candidates (profiles prompt governance-summary
                                                   intent-category mutation-likely-p
                                                   execution-strategy validation-strategy
                                                   validation-plan active-profile)
  (sort
   (mapcar (lambda (profile)
             (let* ((reasons (provider-routing-reasons-for-profile profile
                                                                   prompt
                                                                   governance-summary
                                                                   intent-category
                                                                   mutation-likely-p
                                                                   execution-strategy
                                                                   validation-strategy
                                                                   validation-plan
                                                                   active-profile))
                    (score (provider-routing-score reasons)))
               (list :profile-name (getf profile :name)
                     :provider (getf profile :provider)
                     :model (getf profile :model)
                     :score score
                     :reasons reasons
                     :profile profile)))
           profiles)
   #'>
   :key (lambda (entry) (getf entry :score))))

(defun select-environment-provider-profile (prompt &key environment options session)
  (let* ((active-environment (ensure-environment environment))
         (profiles (environment-provider-profiles active-environment))
         (active-name (environment-active-provider-profile-name active-environment))
         (active-profile (environment-find-provider-profile active-environment active-name))
         (requested-profile-name (and (listp options) (getf options :provider-profile)))
         (routing-mode (provider-routing-mode active-environment))
         (governance-summary (environment-routing-governance-summary active-environment))
         (cognition-context (build-routing-cognition-context session prompt))
         (intent (and cognition-context (getf cognition-context :intent)))
         (intent-category (and intent (getf intent :category)))
         (mutation-likely-p (and intent (getf intent :mutation-likely-p)))
         (execution-strategy (and cognition-context (getf cognition-context :execution-strategy)))
         (validation-strategy (and cognition-context (getf cognition-context :validation-strategy)))
         (validation-plan (and cognition-context (getf cognition-context :validation-plan)))
         (candidate-rankings (ranked-provider-profile-candidates profiles
                                                                 prompt
                                                                 governance-summary
                                                                 intent-category
                                                                 mutation-likely-p
                                                                 execution-strategy
                                                                 validation-strategy
                                                                 validation-plan
                                                                 active-profile))
         (route
           (cond
             ((stringp requested-profile-name)
              (let ((requested (environment-find-provider-profile active-environment requested-profile-name)))
                (unless requested
                  (error "Unknown provider profile ~S" requested-profile-name))
                (list :routing-mode :explicit
                      :reason :requested-profile
                      :selected-profile requested
                      :candidate-rankings candidate-rankings)))
             ((or (eq routing-mode :manual)
                  (null profiles)
                  (= (length profiles) 1))
              (list :routing-mode routing-mode
                    :reason (if (eq routing-mode :manual) :manual-active-profile :active-profile)
                    :selected-profile (or active-profile (first profiles))
                    :candidate-rankings candidate-rankings))
             (t
              (list :routing-mode :auto
                    :reason (provider-routing-primary-reason candidate-rankings active-profile)
                    :selected-profile (or (getf (first candidate-rankings) :profile)
                                          active-profile
                                          (first profiles))
                    :candidate-rankings candidate-rankings)))))
    (append route
            (list :intent-category intent-category
                  :mutation-likely-p mutation-likely-p
                  :validation-mode (and validation-strategy
                                        (getf validation-strategy :mode))
                  :execution-mode (and execution-strategy
                                       (getf execution-strategy :mode))))))

(defun record-environment-provider-route (route &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (provider-state (environment-provider-state-snapshot active-environment))
         (profile (getf route :selected-profile))
         (summary (list :routing-mode (getf route :routing-mode)
                        :reason (getf route :reason)
                        :selected-profile-name (and profile (getf profile :name))
                        :selected-provider (and profile (getf profile :provider))
                        :selected-model (and profile (getf profile :model))
                        :candidate-rankings (mapcar (lambda (entry)
                                                      (list :profile-name (getf entry :profile-name)
                                                            :provider (getf entry :provider)
                                                            :model (getf entry :model)
                                                            :score (getf entry :score)
                                                            :reasons (getf entry :reasons)))
                                                    (or (getf route :candidate-rankings) '()))
                        :intent-category (getf route :intent-category)
                        :mutation-likely-p (getf route :mutation-likely-p)
                        :validation-mode (getf route :validation-mode)
                        :execution-mode (getf route :execution-mode))))
    (setf (getf provider-state :last-provider-route) summary)
    (replace-environment-provider-state active-environment provider-state)
    summary))

(defun provider-profile->config (profile &optional base-config)
  (let* ((normalized (canonicalize-provider-profile profile))
         (working-directory (or (and base-config (config-working-directory base-config))
                                (and (boundp '*current-environment*)
                                     *current-environment*
                                     (environment-provider-working-directory *current-environment*))
                                (namestring (uiop:ensure-directory-pathname (getcwd)))))
         (provider (getf normalized :provider))
         (api-key (or (resolve-provider-api-key provider working-directory)
                      (normalize-config-string (getf normalized :api-key)))))
    (make-config
     :provider provider
     :model (or (getf normalized :model)
                (and base-config (config-model base-config))
                (provider-default-model provider))
     :fast-model (or (getf normalized :fast-model)
                     (and base-config (config-fast-model base-config))
                     (provider-default-fast-model provider))
     :api-base (or (getf normalized :api-base)
                   (and base-config (config-api-base base-config))
                   (provider-default-api-base provider))
     :api-key api-key
     :api-key-present-p (not (null api-key))
     :retrieval-ranking-mode (or (and base-config
                                      (config-retrieval-ranking-mode base-config))
                                 :auto)
     :working-directory working-directory)))

(defun provider-from-profile (profile &optional (base-config (load-config)))
  (make-provider (provider-profile->config profile base-config)))

(defun query-environment-provider-service (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (make-service-query-response :environment
                                 :provider
                                 (environment-provider-profile-summary active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-provider-v1
                                                                  :environment active-environment))))

(defun query-environment-provider-route-service (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (provider-summary (environment-provider-profile-summary active-environment)))
    (make-service-query-response :environment
                                 :provider-route
                                 (list :routing-mode (getf provider-summary :routing-mode)
                                       :routing-policy (getf provider-summary :routing-policy)
                                       :last-route (getf provider-summary :last-route)
                                       :active-profile-name (getf provider-summary :active-profile-name)
                                       :active-profile (getf provider-summary :active-profile)
                                       :profile-count (getf provider-summary :profile-count))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-provider-route-v1
                                                                  :environment active-environment))))

(defun query-environment-provider-preview-service (prompt &key environment session options)
  (let* ((active-environment (ensure-environment environment))
         (route (select-environment-provider-profile prompt
                                                     :environment active-environment
                                                     :session session
                                                     :options options))
         (profile (getf route :selected-profile))
         (provider-summary (environment-provider-profile-summary active-environment)))
    (make-service-query-response :environment
                                 :provider-preview
                                 (list :prompt prompt
                                       :routing-mode (getf route :routing-mode)
                                       :routing-policy (getf provider-summary :routing-policy)
                                       :reason (getf route :reason)
                                       :selected-profile-name (and profile (getf profile :name))
                                       :selected-provider (and profile (getf profile :provider))
                                       :selected-model (and profile (getf profile :model))
                                       :candidate-rankings (mapcar (lambda (entry)
                                                                     (list :profile-name (getf entry :profile-name)
                                                                           :provider (getf entry :provider)
                                                                           :model (getf entry :model)
                                                                           :score (getf entry :score)
                                                                           :reasons (getf entry :reasons)))
                                                                   (or (getf route :candidate-rankings) '()))
                                       :intent-category (getf route :intent-category)
                                       :mutation-likely-p (getf route :mutation-likely-p)
                                       :validation-mode (getf route :validation-mode)
                                       :execution-mode (getf route :execution-mode))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-provider-preview-v1
                                                                  :environment active-environment))))

(defun perform-environment-provider-configure-service (profile-name options
                                                                    &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (provider-state (environment-provider-state-snapshot active-environment))
         (existing (environment-find-provider-profile active-environment profile-name))
         (resolved-options
           (if (plist-key-present-p options :clear-api-key)
               (append options (list :api-key nil))
               options))
         (normalized (normalize-provider-profile profile-name resolved-options))
         (working-directory (environment-provider-working-directory active-environment))
         (provider-name (getf normalized :provider))
         (explicit-api-key-p (plist-key-present-p resolved-options :api-key))
         (clear-api-key-p (plist-key-present-p resolved-options :clear-api-key))
         (legacy-api-key (and existing
                              (normalize-config-string (getf existing :api-key))))
         (resolved-api-key
           (cond
             (clear-api-key-p nil)
             (explicit-api-key-p (normalize-config-string (getf resolved-options :api-key)))
             (t legacy-api-key)))
         (sanitized (copy-list normalized))
         (profiles (remove (getf normalized :name)
                           (or (getf provider-state :provider-profiles) '())
                           :key (lambda (profile) (getf profile :name))
                           :test #'string=)))
    (cond
      (clear-api-key-p
       (remove-provider-api-key-file working-directory provider-name))
      (resolved-api-key
       (write-provider-api-key-file working-directory provider-name resolved-api-key)))
    (remf sanitized :api-key)
    (setf (getf provider-state :provider-profiles)
          (append profiles (list sanitized)))
    (unless (getf provider-state :active-provider-profile)
      (setf (getf provider-state :active-provider-profile)
            (getf sanitized :name)))
    (replace-environment-provider-state active-environment provider-state)
    (when (fboundp 'notify-provider-request-snapshot-environment-change)
      (notify-provider-request-snapshot-environment-change
       active-environment
       :reason :provider-configure
       :family :environment
       :domains '(:policy :environment)))
    (make-service-command-response :environment
                                   :provider-configure
                                   (environment-provider-profile-summary active-environment)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-provider-command-v1
                                                                    :environment active-environment))))

(defun command-environment-provider-configure-service (profile-name options
                                                                    &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (register-service-command-response
     (call-with-environment-governed-command-actor
      active-environment
      (make-environment-control-request active-environment
                                        :provider-configure
                                        :environment/provider-admin
                                        :payload (list :profile-name profile-name
                                                       :options options)
                                        :metadata (list :profile-name
                                                        (normalize-provider-profile-name profile-name)))
      (lambda ()
        (perform-environment-provider-configure-service profile-name options active-environment))
      :environment/provider-admin
      :provider-configure
      :metadata (list :profile-name (normalize-provider-profile-name profile-name)))
     :session (environment-control-session active-environment)
     :intention (format nil "Configure provider profile ~A." profile-name)
     :capability :environment/provider-configure
     :authority :environment)))

(defun perform-environment-provider-use-service (profile-name &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (provider-state (environment-provider-state-snapshot active-environment))
         (profile (environment-find-provider-profile active-environment profile-name)))
    (unless profile
      (error "Unknown provider profile ~S" profile-name))
    (setf (getf provider-state :active-provider-profile)
          (getf profile :name))
    (replace-environment-provider-state active-environment provider-state)
    (when (fboundp 'notify-provider-request-snapshot-environment-change)
      (notify-provider-request-snapshot-environment-change
       active-environment
       :reason :provider-use
       :family :environment
       :domains '(:policy :environment)))
    (make-service-command-response :environment
                                   :provider-use
                                   (environment-provider-profile-summary active-environment)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-provider-command-v1
                                                                    :environment active-environment))))

(defun command-environment-provider-use-service (profile-name &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (register-service-command-response
     (call-with-environment-governed-command-actor
      active-environment
      (make-environment-control-request active-environment
                                        :provider-use
                                        :environment/provider-admin
                                        :payload (list :profile-name profile-name)
                                        :metadata (list :profile-name
                                                        (normalize-provider-profile-name profile-name)))
      (lambda ()
        (perform-environment-provider-use-service profile-name active-environment))
      :environment/provider-admin
      :provider-use
      :metadata (list :profile-name (normalize-provider-profile-name profile-name)))
     :session (environment-control-session active-environment)
     :intention (format nil "Use provider profile ~A." profile-name)
     :capability :environment/provider-use
     :authority :environment)))

(defun perform-environment-provider-routing-service (&optional mode environment)
  (let* ((active-environment (ensure-environment environment))
         (provider-state (environment-provider-state-snapshot active-environment)))
    (when mode
      (setf (getf provider-state :provider-routing-mode)
            (normalize-provider-routing-mode mode))
      (replace-environment-provider-state active-environment provider-state)
      (when (fboundp 'notify-provider-request-snapshot-environment-change)
        (notify-provider-request-snapshot-environment-change
         active-environment
         :reason :provider-routing
         :family :environment
         :domains '(:policy :environment))))
    (make-service-command-response :environment
                                   :provider-routing
                                   (environment-provider-profile-summary active-environment)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-provider-routing-command-v1
                                                                    :environment active-environment))))

(defun command-environment-provider-routing-service (&optional mode environment)
  (let ((active-environment (ensure-environment environment)))
    (register-service-command-response
     (call-with-environment-governed-command-actor
      active-environment
      (make-environment-control-request active-environment
                                        :provider-routing
                                        :environment/provider-admin
                                        :payload (list :mode mode)
                                        :metadata (when mode
                                                    (list :mode (normalize-provider-routing-mode mode))))
      (lambda ()
        (perform-environment-provider-routing-service mode active-environment))
      :environment/provider-admin
      :provider-routing
      :metadata (when mode
                  (list :mode (normalize-provider-routing-mode mode))))
     :session (environment-control-session active-environment)
     :intention "Update provider routing."
     :capability :environment/provider-routing
     :authority :environment)))

(defun query-environment-summary-service (&optional environment
                                            &key
                                              (include-alignment-state-p t)
                                              (include-reconciliation-decision-p t))
  (let ((active-environment (ensure-environment environment)))
    (make-service-query-response :environment
                                 :summary
                                 (environment-summary active-environment
                                                      :include-alignment-state-p include-alignment-state-p
                                                      :include-reconciliation-decision-p include-reconciliation-decision-p)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-summary-v1
                                                                  :environment active-environment))))

(defun blocked-work-item-summary-p (summary)
  (or (member (getf summary :status)
              '(:awaiting-approval :quarantined :awaiting-cold-validation
                :failed :rolled-back)
              :test #'eq)
      (member (getf summary :why)
              '(:approval-required :cold-validation-required
                :pending-validation :operator-review-required)
              :test #'eq)))

(defun approval-work-item-summary-p (summary)
  (or (eq (getf summary :status) :awaiting-approval)
      (eq (getf summary :why) :approval-required)))

(defun compact-work-item-surface-summary (session summary &optional environment)
  (let* ((work-item-id (or (getf summary :id)
                           (getf summary :work-item-id)))
         (work-item (and session
                         work-item-id
                         (find-work-item session work-item-id)))
         (title (or (getf summary :goal)
                    (and work-item (work-item-goal work-item))
                    "Governed work item"))
         (status (or (getf summary :status)
                     (and work-item (work-item-status work-item))
                     :blocked))
         (handles (execution-handle-summaries-by-target :work-item-id
                                                        work-item-id
                                                        environment))
         (surface (or (primary-execution-surface-summary session
                                                         handles
                                                         :environment environment)
                      (list :surface-id (format nil "surface-work-item-~A" work-item-id)
                            :surface-kind "governed-work"
                            :attention-rank 1
                            :execution-id nil
                            :title title
                            :status status
                            :object-kind "work-item"
                            :work-item-id work-item-id
                            :primary-execution-handle (first handles)))))
    (append (compact-execution-surface-summary surface)
            (when work-item
              (list :corrective-context (work-item-corrective-context work-item))))))

(defun compact-work-item-surfaces-data (session summaries filter &optional environment)
  (let* ((items (mapcar (lambda (summary)
                          (compact-work-item-surface-summary session summary environment))
                        summaries))
         (top-surface (first items)))
    (list :count (length items)
          :top-surface top-surface
          :items items
          :filter filter)))

(defun query-environment-status-service (&optional environment
                                           &key
                                             (include-alignment-state-p t)
                                             (include-reconciliation-decision-p t))
  (let* ((active-environment (ensure-environment environment))
         (session (environment-session active-environment))
         (base-status (environment-status active-environment
                                          :include-alignment-state-p include-alignment-state-p
                                          :include-reconciliation-decision-p include-reconciliation-decision-p))
         (execution-surfaces (and session
                                  (service-response-data
                                   (query-execution-surfaces-service
                                    session
                                    :environment active-environment))))
         (blocked-work-items (remove-if-not #'blocked-work-item-summary-p
                                            (or (getf (getf base-status :blocked-work) :items)
                                                '())))
         (approval-work-items (remove-if-not #'approval-work-item-summary-p
                                             blocked-work-items))
         (status-data (append base-status
                              (list :execution-surfaces
                                    (and execution-surfaces
                                         (compact-execution-surfaces-data
                                          execution-surfaces))
                                    :blocked-work-surfaces
                                    (compact-work-item-surfaces-data
                                     session
                                     blocked-work-items
                                     '(:queue :blocked-work)
                                     active-environment)
                                    :approval-surfaces
                                    (compact-work-item-surfaces-data
                                     session
                                     approval-work-items
                                     '(:queue :approvals)
                                     active-environment)))))
    (make-service-query-response :environment
                                 :status
                                 status-data
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-status-v1
                                                                  :environment active-environment))))

(defun query-environment-events-service (&key tail environment)
  (let* ((active-environment (ensure-environment environment))
         (events (environment-event-log-snapshot active-environment))
         (tail-count (normalize-tail-count tail))
         (start (max 0 (- (length events) tail-count))))
    (make-service-query-response :environment
                                 :events
                                 (list :environment-id (environment-id active-environment)
                                       :event-count (length events)
                                       :events (subseq events start))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-events-v1
                                                                  :environment active-environment))))

(defun command-environment-events-query-service (&key tail environment)
  (let ((active-environment (ensure-environment environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request
      active-environment
      :events-query
      :environment/events
      :payload (list :tail tail))
     (lambda ()
       (query-environment-events-service :tail tail
                                         :environment active-environment))
     :environment/events
     :events-query)))

(defun command-environment-event-stream-query-service (&key environment after-cursor limit family visibility)
  (let ((active-environment (ensure-environment environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request
      active-environment
      :event-stream-query
      :environment/event-stream
     :payload (list :after-cursor after-cursor
                     :limit limit
                     :family family
                     :visibility visibility))
     (lambda ()
       (query-service-event-stream :environment active-environment
                                   :after-cursor after-cursor
                                   :limit limit
                                   :family family
                                   :visibility visibility))
     :environment/event-stream
     :event-stream-query)))

(defun perform-environment-save-service (path &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (make-service-command-response :environment
                                   :save
                                   (progn
                                     (save-environment active-environment path)
                                     (list :saved path
                                           :summary (environment-summary active-environment)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-command-v1
                                                                    :environment active-environment))))

(defun command-environment-save-service (path &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (register-service-command-response
     (call-with-environment-governed-command-actor
      active-environment
      (make-environment-control-request active-environment
                                        :save
                                        :environment/checkpoint
                                        :payload (list :path path)
                                        :metadata (list :path path))
      (lambda ()
        (perform-environment-save-service path active-environment))
      :environment/checkpoint
      :save
      :metadata (list :path path))
     :session (environment-control-session active-environment)
     :intention (format nil "Save environment to ~A." path)
     :capability :environment/save
     :authority :environment)))

(defun perform-environment-load-service (path)
  (let ((environment (load-environment path)))
    (make-service-command-response :environment
                                   :load
                                   (list :loaded path
                                         :summary (environment-summary environment)
                                         :session (environment-session environment))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-command-v1
                                                                    :environment environment))))

(defun command-environment-load-service (path)
  (let* ((session (or *current-session*
                      (error "Environment load requires a current session.")))
         (active-environment (service-active-environment :session session)))
    (register-service-command-response
     (call-with-environment-governed-command-actor
      active-environment
      (make-environment-control-request active-environment
                                        :load
                                        :environment/checkpoint
                                        :payload (list :path path)
                                        :metadata (list :path path))
      (lambda ()
        (perform-environment-load-service path))
      :environment/checkpoint
      :load
      :metadata (list :path path))
     :session session
     :intention (format nil "Load environment from ~A." path)
     :capability :environment/load
     :authority :environment)))
