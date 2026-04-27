(in-package #:sbcl-agent)

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

(defun normalize-provider-profile-name (name)
  (or (normalize-config-string name) "default"))

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
                                    :intents (getf profile :intents)
                                    :latency-tier (getf profile :latency-tier)
                                    :review-bias (getf profile :review-bias)
                                    :execution-bias (getf profile :execution-bias)
                                    :locality (getf profile :locality))))

(defun normalize-provider-profile (name options)
  (let* ((provider (or (normalize-config-string (getf options :provider)) "mock")))
    (list :name (normalize-provider-profile-name name)
          :provider provider
          :model (or (normalize-config-string (getf options :model))
                     (provider-default-model provider))
          :fast-model (or (normalize-config-string (getf options :fast-model))
                          (provider-default-fast-model provider))
          :api-base (normalize-config-string (getf options :api-base))
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
          (or (environment-metadata-value (ensure-environment environment)
                                          :provider-profiles)
              '())))

(defun environment-active-provider-profile-name (&optional environment)
  (environment-metadata-value (ensure-environment environment)
                              :active-provider-profile
                              "default"))

(defun environment-find-provider-profile (environment profile-name)
  (find (normalize-provider-profile-name profile-name)
        (environment-provider-profiles environment)
        :key (lambda (profile) (getf profile :name))
        :test #'string=))

(defun environment-provider-profile-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (profiles (environment-provider-profiles active-environment))
         (active-name (environment-active-provider-profile-name active-environment))
         (active-profile (environment-find-provider-profile active-environment active-name))
         (routing-mode (or (environment-metadata-value active-environment :provider-routing-mode)
                           :auto))
         (last-route (environment-metadata-value active-environment :last-provider-route)))
    (list :active-profile-name active-name
          :profile-count (length profiles)
          :profiles profiles
          :active-profile active-profile
          :routing-mode routing-mode
          :routing-policy (list :mode routing-mode
                                :available-modes '(:auto :manual)
                                :profile-count (length profiles)
                                :last-route-present-p (and last-route t))
          :last-route last-route)))

(defun ensure-environment-provider-profile (&key environment config (profile-name "default"))
  (let* ((active-environment (ensure-environment environment))
         (normalized (normalize-provider-profile
                      profile-name
                      (list :provider (config-provider config)
                            :model (config-model config)
                            :fast-model (config-fast-model config)
                            :api-base (config-api-base config))))
         (profiles (remove (getf normalized :name)
                           (environment-provider-profiles active-environment)
                           :key (lambda (profile) (getf profile :name))
                           :test #'string=)))
    (set-environment-metadata-value active-environment
                                    :provider-profiles
                                    (append profiles (list normalized)))
    (unless (environment-metadata-value active-environment :active-provider-profile)
      (set-environment-metadata-value active-environment
                                      :active-provider-profile
                                      (getf normalized :name)))
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
  (or (environment-metadata-value (ensure-environment environment)
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
    (set-environment-metadata-value active-environment :last-provider-route summary)
    summary))

(defun provider-profile->config (profile &optional (base-config (load-config)))
  (let ((normalized (canonicalize-provider-profile profile)))
    (config-with-overrides base-config
                           :provider (getf normalized :provider)
                           :model (getf normalized :model)
                           :fast-model (getf normalized :fast-model)
                           :api-base (getf normalized :api-base))))

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

(defun command-environment-provider-configure-service (profile-name options
                                                                    &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (normalized (normalize-provider-profile profile-name options))
         (profiles (remove (getf normalized :name)
                           (environment-provider-profiles active-environment)
                           :key (lambda (profile) (getf profile :name))
                           :test #'string=)))
    (set-environment-metadata-value active-environment
                                    :provider-profiles
                                    (append profiles (list normalized)))
    (unless (environment-metadata-value active-environment :active-provider-profile)
      (set-environment-metadata-value active-environment
                                      :active-provider-profile
                                      (getf normalized :name)))
    (make-service-command-response :environment
                                   :provider-configure
                                   (environment-provider-profile-summary active-environment)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-provider-command-v1
                                                                    :environment active-environment))))

(defun command-environment-provider-use-service (profile-name &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (profile (environment-find-provider-profile active-environment profile-name)))
    (unless profile
      (error "Unknown provider profile ~S" profile-name))
    (set-environment-metadata-value active-environment
                                    :active-provider-profile
                                    (getf profile :name))
    (make-service-command-response :environment
                                   :provider-use
                                   (environment-provider-profile-summary active-environment)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-provider-command-v1
                                                                    :environment active-environment))))

(defun command-environment-provider-routing-service (&optional mode environment)
  (let ((active-environment (ensure-environment environment)))
    (when mode
      (set-environment-metadata-value active-environment
                                      :provider-routing-mode
                                      (normalize-provider-routing-mode mode)))
    (make-service-command-response :environment
                                   :provider-routing
                                   (environment-provider-profile-summary active-environment)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-provider-routing-command-v1
                                                                    :environment active-environment))))

(defun query-environment-summary-service (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (make-service-query-response :environment
                                 :summary
                                 (environment-summary active-environment)
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
         (handles (kernel-execution-summaries-by-target :work-item-id
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
    (compact-execution-surface-summary surface)))

(defun compact-work-item-surfaces-data (session summaries filter &optional environment)
  (let* ((items (mapcar (lambda (summary)
                          (compact-work-item-surface-summary session summary environment))
                        summaries))
         (top-surface (first items)))
    (list :count (length items)
          :top-surface top-surface
          :items items
          :filter filter)))

(defun query-environment-status-service (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (session (environment-session active-environment))
         (base-status (environment-status active-environment))
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
         (events (environment-event-log active-environment))
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

(defun command-environment-save-service (path &optional environment)
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

(defun command-environment-load-service (path)
  (let ((environment (load-environment path)))
    (make-service-command-response :environment
                                   :load
                                   (list :loaded path
                                         :summary (environment-summary environment)
                                         :session (environment-session environment))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-command-v1
                                                                    :environment environment))))
