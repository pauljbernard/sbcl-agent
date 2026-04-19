(in-package #:sbcl-agent)

(defun runtime-service-summary-data (session)
  (let* ((environment (session-bound-environment session))
         (runtime-domain (and environment
                              (environment-runtime-domain-summary environment)))
         (package-view (tool-runtime-current-package session))
         (systems-view (tool-runtime-list-loaded-systems session)))
    (list :runtime-id (or (and runtime-domain
                               (getf runtime-domain :active-runtime-id))
                          (default-runtime-id))
          :package (getf package-view :package)
          :package-details package-view
          :loaded-system-count (getf systems-view :system-count)
          :loaded-systems (getf systems-view :systems)
          :runtime-domain runtime-domain)))

(defun query-runtime-summary-service (session)
  (make-service-query-response :runtime
                               :summary
                               (runtime-service-summary-data session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-summary-v1
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
  (make-service-command-response :runtime
                                 :set-package
                                 (tool-runtime-set-package session :package package-name)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :runtime-command-v1
                                                                  :session session
                                                                  :runtime-id (default-runtime-id)
                                                                  :policy-id :runtime-package-switch)))

(defun command-runtime-eval-service (session form-or-source &key package mutating)
  (make-service-command-response :runtime
                                 :eval
                                 (tool-runtime-eval session
                                                    :form form-or-source
                                                    :package package
                                                    :mutating mutating)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :runtime-command-v1
                                                                  :session session
                                                                  :runtime-id (default-runtime-id)
                                                                  :policy-id (runtime-eval-policy-id mutating))))

(defun command-runtime-reload-file-service (session path)
  (make-service-command-response :runtime
                                 :reload-file
                                 (tool-runtime-reload-file session :path path)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :runtime-command-v1
                                                                  :session session
                                                                  :runtime-id (default-runtime-id)
                                                                  :policy-id :runtime-reload)))
