(in-package #:sbcl-agent)

(defun runtime-service-summary-data (session)
  (let* ((environment (session-bound-environment session))
         (runtime-domain (and environment
                              (environment-runtime-domain-summary environment)))
         (package-view (tool-runtime-current-package session))
         (systems-view (tool-runtime-list-loaded-systems session))
         (package-management (sbcl-agent.bootstrap:package-management-state)))
    (list :runtime-id (or (and runtime-domain
                               (getf runtime-domain :active-runtime-id))
                          (default-runtime-id))
          :package (getf package-view :package)
          :package-details package-view
          :loaded-system-count (getf systems-view :system-count)
          :loaded-systems (getf systems-view :systems)
          :package-management package-management
          :runtime-domain runtime-domain)))

(defun query-runtime-summary-service (session)
  (make-service-query-response :runtime
                               :summary
                               (runtime-service-summary-data session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-summary-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-describe-symbol-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :describe-symbol
                               (tool-runtime-describe-symbol session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-describe-symbol-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-inspect-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :inspect
                               (tool-runtime-inspect-symbol session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-inspect-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-object-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :object
                               (tool-runtime-object-symbol session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-object-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-condition-service (session incident-id)
  (let ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown incident ~A" incident-id))
    (make-service-query-response :runtime
                                 :condition
                                 (list :tool :runtime/condition
                                       :incident-id (incident-id incident)
                                       :kind (incident-kind incident)
                                       :status (incident-status incident)
                                       :condition (incident-condition-string incident)
                                       :condition-summary (incident-condition-summary incident)
                                       :condition-detail (incident-condition-detail incident)
                                       :runtime-context (incident-runtime-context session incident))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :runtime-condition-v1
                                                                  :session session
                                                                  :runtime-id (default-runtime-id)
                                                                  :incident-id incident-id))))

(defun query-runtime-restarts-service (session incident-id)
  (let ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown incident ~A" incident-id))
    (let ((restart-suggestions (incident-restart-suggestions incident)))
      (make-service-query-response :runtime
                                   :restarts
                                   (list :tool :runtime/restarts
                                         :incident-id (incident-id incident)
                                         :kind (incident-kind incident)
                                         :status (incident-status incident)
                                         :restart-count (length restart-suggestions)
                                         :restart-suggestions restart-suggestions
                                         :recommended-actions
                                         (remove-if-not (lambda (action)
                                                          (eq (getf action :type) :consider-restart))
                                                        (incident-recommended-actions session incident))
                                         :runtime-context (incident-runtime-context session incident))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :read-model :runtime-restarts-v1
                                                                    :session session
                                                                    :runtime-id (default-runtime-id)
                                                                    :incident-id incident-id)))))

(defun query-runtime-find-definition-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :find-definition
                               (tool-runtime-find-definition session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-find-definition-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-callers-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :callers
                               (tool-runtime-callers session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-callers-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-methods-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :methods
                               (tool-runtime-methods session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-methods-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-source-image-divergence-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :source-image-divergence
                               (tool-runtime-source-image-divergence session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-source-image-divergence-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-history-service (session &key tail)
  (make-service-query-response :runtime
                               :history
                               (tool-runtime-history session :tail tail)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-history-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun command-runtime-set-package-service (session package-name)
  (kernelize-service-command-response
   (make-service-command-response :runtime
                                  :set-package
                                  (tool-runtime-set-package session :package package-name)
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :runtime-command-v1
                                                                   :session session
                                                                   :runtime-id (default-runtime-id)
                                                                   :policy-id :runtime-package-switch))
   :session session
   :intention (format nil "Set the active runtime package to ~A." package-name)
   :capability :runtime/set-package
   :authority :runtime))

(defun command-runtime-eval-service (session form-or-source &key package mutating recovery-launch)
  (kernelize-service-command-response
   (make-service-command-response :runtime
                                  :eval
                                  (tool-runtime-eval session
                                                     :form form-or-source
                                                     :package package
                                                     :mutating mutating
                                                     :recovery-launch recovery-launch)
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :runtime-command-v1
                                                                   :session session
                                                                   :runtime-id (default-runtime-id)
                                                                   :policy-id (runtime-eval-policy-id mutating)))
   :session session
   :intention (format nil "Evaluate ~A in the live runtime.~@[ Package: ~A.~]" form-or-source package)
   :capability :runtime/eval
   :authority (if mutating :governed-runtime :runtime)
   :constraints (list :mutating mutating :package package)))

(defun command-runtime-reload-file-service (session path)
  (kernelize-service-command-response
   (make-service-command-response :runtime
                                  :reload-file
                                  (tool-runtime-reload-file session :path path)
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :runtime-command-v1
                                                                   :session session
                                                                   :runtime-id (default-runtime-id)
                                                                   :policy-id :runtime-reload))
   :session session
   :intention (format nil "Reload ~A into the live runtime." path)
   :capability :runtime/reload-file
   :authority :governed-runtime))
