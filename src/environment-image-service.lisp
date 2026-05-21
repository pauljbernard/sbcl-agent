(in-package #:sbcl-agent)

(defparameter +environment-image-registry-schema-version+ 1)
(defparameter +environment-image-id-key+ :environment-image-id)
(defparameter +environment-image-name-key+ :environment-image-name)
(defparameter +environment-image-path-key+ :environment-image-path)
(defparameter +environment-checkpoint-policy-key+ :environment-checkpoint-policy)
(defparameter +environment-runtime-manifest-key+ :environment-runtime-manifest)
(defparameter +environment-recovery-manifest-key+ :environment-recovery-manifest)
(defparameter +environment-recovery-report-key+ :environment-recovery-report)

(defstruct environment-image-record
  id
  name
  path
  created-at
  updated-at
  last-opened-at
  basis-image-id
  summary)

(defstruct environment-checkpoint-policy
  (exit-mode :prompt)
  (preserve-shell-state t)
  (warm-restart t)
  (require-confirmation-on-dirty-exit t))

(defstruct environment-runtime-manifest
  active-runtime-id
  runtime-count
  source-roots
  expected-worker-ids
  expected-compatibility-app-ids
  transport)

(defstruct environment-recovery-manifest
  restart-actions
  validation-obligations
  unresolved-incident-ids
  last-recovery-status
  last-recovery-at)

(defun environment-recovery-report (&optional environment)
  (copy-tree
   (environment-metadata-value (ensure-environment environment)
                               +environment-recovery-report-key+)))

(defun pending-worker-restart-actions (environment runtime-manifest)
  (let* ((agent-state (environment-agent-state-snapshot environment))
         (workers (or (and agent-state
                           (environment-agent-state-workers agent-state))
                      '())))
    (loop for worker-id in (environment-runtime-manifest-expected-worker-ids runtime-manifest)
          for worker = (find worker-id workers
                             :key #'worker-state-id
                             :test #'string=)
          when (or (null worker)
                   (not (worker-state-running-p worker)))
            collect (list :kind :restart-worker
                          :worker-id worker-id
                          :reason (if worker
                                      :worker-not-running
                                      :worker-missing)))))

(defun pending-compatibility-app-restart-actions (runtime-manifest)
  (loop for app-id in (environment-runtime-manifest-expected-compatibility-app-ids runtime-manifest)
        collect (list :kind :restart-compatibility-app
                      :app-id app-id
                      :reason :app-not-attached)))

(defun runtime-replay-outcomes (restart-actions)
  (loop for action in restart-actions
        collect (append action
                        (list :outcome :pending-manual-recovery
                              :recoverable-p t))))

(defun validation-obligation-outcomes (validation-obligations)
  (loop for obligation in validation-obligations
        collect (append obligation
                        (list :outcome :pending-validation
                              :recoverable-p t))))

(defun runtime-manifest-runtime-missing-p (environment runtime-manifest)
  (let ((runtime-id (environment-runtime-manifest-active-runtime-id runtime-manifest)))
    (and runtime-id
         (not (find runtime-id
                    (or (environment-runtime-set environment) '())
                    :key (lambda (runtime) (getf runtime :id))
                    :test #'string=)))))

(defun assess-environment-recovery (environment)
  (let* ((active-environment (ensure-environment environment))
         (runtime-manifest (environment-runtime-manifest-record active-environment))
         (recovery-manifest (environment-recovery-manifest-record active-environment))
         (worker-actions (pending-worker-restart-actions active-environment runtime-manifest))
         (compatibility-actions (pending-compatibility-app-restart-actions runtime-manifest))
         (runtime-missing-p (runtime-manifest-runtime-missing-p active-environment runtime-manifest))
         (restart-actions (append worker-actions
                                  compatibility-actions
                                  (and runtime-missing-p
                                       (list (list :kind :restore-runtime
                                                   :runtime-id (environment-runtime-manifest-active-runtime-id
                                                                runtime-manifest)
                                                   :reason :runtime-missing)))))
         (validation-obligations (copy-tree
                                  (environment-recovery-manifest-validation-obligations
                                   recovery-manifest)))
         (unresolved-incident-ids (copy-tree
                                   (environment-recovery-manifest-unresolved-incident-ids
                                    recovery-manifest)))
         (runtime-replay (runtime-replay-outcomes restart-actions))
         (validation-outcomes (validation-obligation-outcomes validation-obligations))
         (status (cond
                   ((or restart-actions unresolved-incident-ids) :degraded)
                   (validation-obligations :recovering)
                   (t :steady)))
         (timestamp (get-universal-time))
         (report (list :status status
                       :recovery-valid-p (eq status :steady)
                       :degraded-p (eq status :degraded)
                       :recorded-at timestamp
                       :restart-action-count (length restart-actions)
                       :worker-restart-count (length worker-actions)
                       :compatibility-app-restart-count (length compatibility-actions)
                       :runtime-missing-p runtime-missing-p
                       :manual-recovery-required-p (not (null restart-actions))
                       :runtime-replay runtime-replay
                       :validation-obligation-count (length validation-obligations)
                       :validation-outcomes validation-outcomes
                       :unresolved-incident-count (length unresolved-incident-ids)
                       :restart-actions restart-actions
                       :validation-obligations validation-obligations
                       :unresolved-incident-ids unresolved-incident-ids)))
    (setf (environment-recovery-manifest-restart-actions recovery-manifest) restart-actions
          (environment-recovery-manifest-last-recovery-status recovery-manifest) status
          (environment-recovery-manifest-last-recovery-at recovery-manifest) timestamp)
    (set-environment-metadata-value active-environment
                                    +environment-recovery-manifest-key+
                                    recovery-manifest)
    (set-environment-metadata-value active-environment
                                    +environment-recovery-report-key+
                                    report)
    report))

(defun default-environment-checkpoint-policy ()
  (make-environment-checkpoint-policy))

(defun environment-checkpoint-policy-record (&optional environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +environment-checkpoint-policy-key+)
      (default-environment-checkpoint-policy)))

(defun environment-runtime-manifest-record (&optional environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +environment-runtime-manifest-key+)
      (derive-environment-runtime-manifest environment)))

(defun environment-recovery-manifest-record (&optional environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +environment-recovery-manifest-key+)
      (derive-environment-recovery-manifest environment)))

(defun environment-image-id (&optional environment)
  (environment-metadata-value (ensure-environment environment)
                              +environment-image-id-key+))

(defun environment-image-name (&optional environment)
  (environment-metadata-value (ensure-environment environment)
                              +environment-image-name-key+))

(defun environment-image-path (&optional environment)
  (environment-metadata-value (ensure-environment environment)
                              +environment-image-path-key+))

(defun make-environment-image-id ()
  (format nil "image-~D-~D" (get-universal-time) (random 1000000)))

(defun environment-images-root (&optional environment)
  (merge-pathnames
   #P".sbcl-agent/environments/"
   (uiop:ensure-directory-pathname
    (or (and environment (environment-storage-root (ensure-environment environment)))
        (namestring (getcwd))))))

(defun environment-image-registry-path (&optional environment)
  (merge-pathnames #P"registry.sexp" (environment-images-root environment)))

(defun normalize-environment-image-name (name)
  (let* ((trimmed (string-downcase
                   (string-trim '(#\Space #\Tab #\Newline #\Return)
                                (or (and name (princ-to-string name)) ""))))
         (mapped (map 'string
                      (lambda (ch)
                        (if (or (alphanumericp ch)
                                (char= ch #\-)
                                (char= ch #\_))
                            ch
                            #\-))
                      trimmed)))
    (string-trim "-" mapped)))

(defun ensure-environment-image-name (name)
  (let ((normalized (normalize-environment-image-name name)))
    (if (> (length normalized) 0)
        normalized
        (error "Environment image name must not be empty."))))

(defun environment-image-pathname (environment image-name)
  (merge-pathnames
   (make-pathname :name (ensure-environment-image-name image-name)
                  :type "sexp")
   (environment-images-root environment)))

(defun make-empty-environment-image-registry ()
  (list :schema-version +environment-image-registry-schema-version+
        :current-image-id nil
        :images '()))

(defun load-environment-image-registry (&optional environment)
  (let ((path (environment-image-registry-path environment)))
    (if (probe-file path)
        (with-open-file (stream path :direction :input)
          (with-standard-io-syntax
            (or (read stream nil nil)
                (make-empty-environment-image-registry))))
        (make-empty-environment-image-registry))))

(defun save-environment-image-registry (registry &optional environment)
  (let ((path (environment-image-registry-path environment)))
    (ensure-directories-exist path)
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (with-standard-io-syntax
        (let ((*print-circle* t)
              (*print-pretty* t)
              (*print-readably* t))
          (write registry :stream stream))))
    path))

(defun environment-image-registry-images (registry)
  (copy-list (or (getf registry :images) '())))

(defun environment-image-registry-current-image-id (registry)
  (getf registry :current-image-id))

(defun environment-image-registry-set-current-image-id (registry image-id)
  (setf (getf registry :current-image-id) image-id)
  registry)

(defun replace-environment-image-record (records record)
  (append (remove (environment-image-record-id record)
                  records
                  :key #'environment-image-record-id
                  :test #'string=)
          (list record)))

(defun save-environment-image-record (registry record)
  (setf (getf registry :images)
        (replace-environment-image-record
         (environment-image-registry-images registry)
         record))
  registry)

(defun find-environment-image-record (registry image-id-or-name)
  (let ((needle (and image-id-or-name
                     (string-downcase (princ-to-string image-id-or-name)))))
    (find-if (lambda (record)
               (or (string= (string-downcase (environment-image-record-id record)) needle)
                   (string= (string-downcase (environment-image-record-name record)) needle)))
             (environment-image-registry-images registry))))

(defun registry-environment-image-records (registry)
  (sort (copy-list (environment-image-registry-images registry))
        #'string<
        :key #'environment-image-record-name))

(defun environment-image-record->plist (record)
  (list :image-id (environment-image-record-id record)
        :name (environment-image-record-name record)
        :path (environment-image-record-path record)
        :created-at (environment-image-record-created-at record)
        :updated-at (environment-image-record-updated-at record)
        :last-opened-at (environment-image-record-last-opened-at record)
        :basis-image-id (environment-image-record-basis-image-id record)
        :summary (environment-image-record-summary record)))

(defun environment-checkpoint-policy->plist (policy)
  (list :exit-mode (environment-checkpoint-policy-exit-mode policy)
        :preserve-shell-state (environment-checkpoint-policy-preserve-shell-state policy)
        :warm-restart (environment-checkpoint-policy-warm-restart policy)
        :require-confirmation-on-dirty-exit
        (environment-checkpoint-policy-require-confirmation-on-dirty-exit policy)))

(defun environment-runtime-manifest->plist (manifest)
  (list :active-runtime-id (environment-runtime-manifest-active-runtime-id manifest)
        :runtime-count (environment-runtime-manifest-runtime-count manifest)
        :source-roots (copy-list (environment-runtime-manifest-source-roots manifest))
        :expected-worker-ids (copy-list (environment-runtime-manifest-expected-worker-ids manifest))
        :expected-compatibility-app-ids
        (copy-list (environment-runtime-manifest-expected-compatibility-app-ids manifest))
        :transport (environment-runtime-manifest-transport manifest)))

(defun environment-recovery-manifest->plist (manifest)
  (list :restart-actions (copy-list (environment-recovery-manifest-restart-actions manifest))
        :validation-obligations
        (copy-list (environment-recovery-manifest-validation-obligations manifest))
        :unresolved-incident-ids
        (copy-list (environment-recovery-manifest-unresolved-incident-ids manifest))
        :last-recovery-status (environment-recovery-manifest-last-recovery-status manifest)
        :last-recovery-at (environment-recovery-manifest-last-recovery-at manifest)))

(defun current-environment-open-incident-ids (environment)
  (let* ((agent-state (environment-agent-state-snapshot (ensure-environment environment)))
         (incidents (or (and agent-state
                             (environment-agent-state-incidents agent-state))
                        '())))
    (loop for incident in incidents
          when (eq (incident-status incident) :open)
          collect (incident-id incident))))

(defun derive-environment-runtime-manifest (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (agent-state (environment-agent-state-snapshot active-environment))
         (workers (or (and agent-state
                           (environment-agent-state-workers agent-state))
                      '()))
         (compatibility-apps (or (environment-metadata-value active-environment :compatibility-apps)
                                 '())))
    (make-environment-runtime-manifest
     :active-runtime-id (environment-active-runtime-id active-environment)
     :runtime-count (length (or (environment-runtime-set active-environment) '()))
     :source-roots (remove nil (list (environment-storage-root active-environment)))
     :expected-worker-ids (loop for worker in workers collect (worker-state-id worker))
     :expected-compatibility-app-ids
     (loop for app in compatibility-apps
           collect (or (getf app :app-id)
                       (getf app :id)))
     :transport :sbcl-image)))

(defun derive-environment-recovery-manifest (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (make-environment-recovery-manifest
     :restart-actions
     (loop for worker-id in (environment-runtime-manifest-expected-worker-ids
                             (derive-environment-runtime-manifest active-environment))
           collect (list :kind :restart-worker :worker-id worker-id))
     :validation-obligations
     (list (list :kind :environment-summary
                 :environment-id (environment-id active-environment)))
     :unresolved-incident-ids (current-environment-open-incident-ids active-environment)
     :last-recovery-status :steady
     :last-recovery-at nil)))

(defun stamp-environment-image-metadata (environment image-id image-name image-path)
  (let* ((active-environment (ensure-environment environment))
         (runtime-manifest (derive-environment-runtime-manifest active-environment))
         (recovery-manifest (derive-environment-recovery-manifest active-environment))
         (checkpoint-policy (environment-checkpoint-policy-record active-environment)))
    (set-environment-metadata-value active-environment +environment-image-id-key+ image-id)
    (set-environment-metadata-value active-environment +environment-image-name-key+ image-name)
    (set-environment-metadata-value active-environment +environment-image-path-key+ image-path)
    (set-environment-metadata-value active-environment
                                    +environment-runtime-manifest-key+
                                    runtime-manifest)
    (set-environment-metadata-value active-environment
                                    +environment-recovery-manifest-key+
                                    recovery-manifest)
    (set-environment-metadata-value active-environment
                                    +environment-checkpoint-policy-key+
                                    checkpoint-policy)
    active-environment))

(defun environment-image-registry-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (registry (load-environment-image-registry active-environment))
         (current-image-id (or (environment-image-id active-environment)
                               (environment-image-registry-current-image-id registry)))
         (current-record (and current-image-id
                              (find-environment-image-record registry current-image-id))))
    (list :registry-path (namestring (environment-image-registry-path active-environment))
          :images-root (namestring (environment-images-root active-environment))
          :current-image-id current-image-id
          :current-image-name (and current-record
                                   (environment-image-record-name current-record))
          :images (mapcar #'environment-image-record->plist
                          (registry-environment-image-records registry))
          :checkpoint-policy
          (environment-checkpoint-policy->plist
           (environment-checkpoint-policy-record active-environment))
          :runtime-manifest
          (environment-runtime-manifest->plist
           (environment-runtime-manifest-record active-environment))
          :recovery-manifest
          (environment-recovery-manifest->plist
           (environment-recovery-manifest-record active-environment))
          :recovery-report (environment-recovery-report active-environment))))

(defun environment-image-registry-query-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (registry (load-environment-image-registry active-environment))
         (current-image-id (or (environment-image-id active-environment)
                               (environment-image-registry-current-image-id registry)))
         (current-record (and current-image-id
                              (find-environment-image-record registry current-image-id))))
    (list :registry-path (namestring (environment-image-registry-path active-environment))
          :images-root (namestring (environment-images-root active-environment))
          :current-image-id current-image-id
          :current-image-name (and current-record
                                   (environment-image-record-name current-record))
          :images (mapcar #'environment-image-record->plist
                          (registry-environment-image-records registry)))))

(defun save-environment-as-image (name &key overwrite environment basis-image-id)
  (let* ((active-environment (ensure-environment environment))
         (registry (load-environment-image-registry active-environment))
         (normalized-name (ensure-environment-image-name name))
         (existing-record (find-environment-image-record registry normalized-name))
         (record-id (if (and existing-record overwrite)
                        (environment-image-record-id existing-record)
                        (make-environment-image-id))))
    (when (and existing-record (not overwrite))
      (error "Environment image '~A' already exists." normalized-name))
    (let* ((path (or (and existing-record
                          overwrite
                          (environment-image-record-path existing-record))
                     (namestring (environment-image-pathname active-environment normalized-name))))
           (timestamp (get-universal-time))
           (record (make-environment-image-record
                    :id record-id
                    :name normalized-name
                    :path path
                    :created-at (or (and existing-record
                                         (environment-image-record-created-at existing-record))
                                    timestamp)
                    :updated-at timestamp
                    :last-opened-at timestamp
                    :basis-image-id (or basis-image-id
                                        (and existing-record
                                             (environment-image-record-basis-image-id existing-record))
                                        (environment-image-id active-environment))
                    :summary (or (getf (environment-summary active-environment) :focus-summary)
                                 "Saved SBCL environment image."))))
      (stamp-environment-image-metadata active-environment
                                        (environment-image-record-id record)
                                        normalized-name
                                        path)
      (assess-environment-recovery active-environment)
      (ensure-directories-exist path)
      (save-environment active-environment path)
      (save-environment-image-registry
       (environment-image-registry-set-current-image-id
        (save-environment-image-record registry record)
        (environment-image-record-id record))
       active-environment)
      record)))

(defun load-environment-image (image-id-or-name &optional environment)
  (let* ((registry (load-environment-image-registry environment))
         (record (find-environment-image-record registry image-id-or-name)))
    (unless record
      (error "Unknown environment image '~A'." image-id-or-name))
    (let* ((loaded-environment (load-environment (environment-image-record-path record)))
           (updated-record (copy-environment-image-record record)))
      (stamp-environment-image-metadata loaded-environment
                                        (environment-image-record-id updated-record)
                                        (environment-image-record-name updated-record)
                                        (environment-image-record-path updated-record))
      (assess-environment-recovery loaded-environment)
      (save-environment loaded-environment (environment-image-record-path updated-record))
      (setf *current-environment* loaded-environment)
      (when (compatibility-session-materialized-p
             (environment-compatibility-session loaded-environment))
        (setf *current-session* (environment-compatibility-session loaded-environment)))
      (setf (environment-image-record-last-opened-at updated-record) (get-universal-time))
      (save-environment-image-registry
       (environment-image-registry-set-current-image-id
        (save-environment-image-record registry updated-record)
        (environment-image-record-id updated-record))
       loaded-environment)
      loaded-environment)))

(defun revert-environment-to-current-image (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (image-path (environment-image-path active-environment)))
    (unless image-path
      (error "Current environment is not bound to a saved image."))
    (let ((loaded-environment (load-environment image-path)))
      (assess-environment-recovery loaded-environment)
      (save-environment loaded-environment image-path)
      (setf *current-environment* loaded-environment)
      (when (compatibility-session-materialized-p
             (environment-compatibility-session loaded-environment))
        (setf *current-session* (environment-compatibility-session loaded-environment)))
      loaded-environment)))

(defun query-environment-image-registry-service (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (make-service-query-response :environment
                                 :image-registry
                                 (environment-image-registry-query-summary active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :environment-image-registry-v1
                                                                  :environment active-environment))))

(defun command-environment-image-registry-query-service (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request active-environment
                                       :image-registry-query
                                       :environment/image-registry
                                       :payload '())
     (lambda ()
       (query-environment-image-registry-service active-environment))
     :environment/image-registry
     :image-registry-query)))

(defun perform-environment-save-image-service (name &key overwrite environment)
  (let* ((active-environment (ensure-environment environment))
         (record (save-environment-as-image name
                                            :overwrite overwrite
                                            :environment active-environment)))
    (make-service-command-response :environment
                                   :save-image
                                   (list :image (environment-image-record->plist record)
                                         :registry (environment-image-registry-summary active-environment)
                                         :summary (environment-summary active-environment))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-image-command-v1
                                                                    :environment active-environment))))

(defun command-environment-save-image-service (name &key overwrite environment)
  (let ((active-environment (ensure-environment environment)))
    (register-service-command-response
     (call-with-environment-governed-command-actor
      active-environment
      (make-environment-control-request active-environment
                                        :save-image
                                        :environment/checkpoint
                                        :payload (list :name name
                                                       :overwrite overwrite)
                                        :metadata (list :image-name name
                                                        :overwrite overwrite))
      (lambda ()
        (perform-environment-save-image-service name
                                                :overwrite overwrite
                                                :environment active-environment))
      :environment/checkpoint
      :save-image
      :metadata (list :image-name name
                      :overwrite overwrite))
     :session (environment-control-session active-environment)
     :intention (format nil "Save environment image ~A." name)
     :capability :environment/save-image
     :authority :environment)))

(defun perform-environment-load-image-service (image-id-or-name &optional environment)
  (let ((loaded-environment (load-environment-image image-id-or-name environment)))
    (when (fboundp 'notify-provider-request-snapshot-environment-change)
      (notify-provider-request-snapshot-environment-change
       loaded-environment
       :reason :load-image
       :family :environment
       :domains '(:conversation :runtime :workspace :policy :environment)))
    (make-service-command-response :environment
                                   :load-image
                                   (list :image-id (environment-image-id loaded-environment)
                                         :image-name (environment-image-name loaded-environment)
                                         :image-path (environment-image-path loaded-environment)
                                         :recovery-summary (environment-recovery-report loaded-environment)
                                         :registry (environment-image-registry-summary loaded-environment)
                                         :summary (environment-summary loaded-environment)
                                         :session (environment-compatibility-session loaded-environment))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-image-command-v1
                                                                    :environment loaded-environment))))

(defun command-environment-load-image-service (image-id-or-name &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (session (or (environment-session active-environment)
                      *current-session*
                      (error "Environment image load requires a bound session."))))
    (register-service-command-response
     (call-with-environment-governed-command-actor
      active-environment
      (make-environment-control-request active-environment
                                        :load-image
                                        :environment/checkpoint
                                        :payload (list :image-id-or-name image-id-or-name)
                                        :metadata (list :image-id-or-name image-id-or-name))
      (lambda ()
        (perform-environment-load-image-service image-id-or-name active-environment))
      :environment/checkpoint
      :load-image
      :metadata (list :image-id-or-name image-id-or-name))
     :session session
     :intention (format nil "Load environment image ~A." image-id-or-name)
     :capability :environment/load-image
     :authority :environment)))

(defun perform-environment-revert-image-service (&optional environment)
  (let ((loaded-environment (revert-environment-to-current-image environment)))
    (when (fboundp 'notify-provider-request-snapshot-environment-change)
      (notify-provider-request-snapshot-environment-change
       loaded-environment
       :reason :revert-image
       :family :environment
       :domains '(:conversation :runtime :workspace :policy :environment)))
    (make-service-command-response :environment
                                   :revert-image
                                   (list :image-id (environment-image-id loaded-environment)
                                         :image-name (environment-image-name loaded-environment)
                                         :image-path (environment-image-path loaded-environment)
                                         :recovery-summary (environment-recovery-report loaded-environment)
                                         :summary (environment-summary loaded-environment)
                                         :session (environment-compatibility-session loaded-environment))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :environment-image-command-v1
                                                                    :environment loaded-environment))))

(defun command-environment-revert-image-service (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (call-with-environment-actor
     active-environment
     (make-environment-control-request active-environment
                                       :revert-image
                                       :environment/checkpoint
                                       :payload '()
                                       :metadata '())
     (lambda ()
       (perform-environment-revert-image-service active-environment))
     :environment/checkpoint
     :revert-image)))
