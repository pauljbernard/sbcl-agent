(in-package #:sbcl-agent)

(defun package-management-service-working-directory (session)
  (or (agent-session-cwd session)
      (namestring (getcwd))))

(defun query-package-management-summary-service (session)
  (let ((working-directory (package-management-service-working-directory session)))
    (make-service-query-response
     :package-management
     :summary
     (sbcl-agent.bootstrap:package-management-summary
      :project-dir working-directory
      :working-directory working-directory)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :package-management-summary-v1
                                      :session session
                                      :runtime-id (default-runtime-id)))))

(defun command-package-management-install-quicklisp-service (session system-name)
  (let ((working-directory (package-management-service-working-directory session)))
    (kernelize-service-command-response
     (make-service-command-response
      :package-management
      :install-quicklisp
      (sbcl-agent.bootstrap:install-quicklisp-system
       system-name
       :project-dir working-directory
       :working-directory working-directory)
      :metadata (make-service-metadata :authority :environment
                                       :command-model :package-management-command-v1
                                       :session session
                                       :runtime-id (default-runtime-id)
                                       :policy-id :package-management-install-quicklisp))
     :session session
     :intention (format nil "Install or load Quicklisp system ~A." system-name)
     :capability :package-management/install-quicklisp
     :authority :governed-runtime)))

(defun command-package-management-run-qlot-service (session arguments)
  (let ((working-directory (package-management-service-working-directory session)))
    (kernelize-service-command-response
     (make-service-command-response
      :package-management
      :run-qlot
      (sbcl-agent.bootstrap:run-qlot-command
       arguments
       :project-dir working-directory
       :working-directory working-directory)
      :metadata (make-service-metadata :authority :environment
                                       :command-model :package-management-command-v1
                                       :session session
                                       :runtime-id (default-runtime-id)
                                       :policy-id :package-management-run-qlot))
     :session session
     :intention (format nil "Run qlot with arguments ~S." arguments)
     :capability :package-management/run-qlot
     :authority :governed-runtime)))

(defun command-package-management-add-source-registry-entry-service (session path)
  (let ((working-directory (package-management-service-working-directory session)))
    (kernelize-service-command-response
     (make-service-command-response
      :package-management
      :add-source-registry-entry
      (sbcl-agent.bootstrap:add-source-registry-entry
       path
       :project-dir working-directory
       :working-directory working-directory)
      :metadata (make-service-metadata :authority :environment
                                       :command-model :package-management-command-v1
                                       :session session
                                       :runtime-id (default-runtime-id)
                                       :policy-id :workspace-write))
     :session session
     :intention (format nil "Add source registry entry ~A." path)
     :capability :package-management/edit-source-registry
     :authority :environment)))

(defun command-package-management-update-source-registry-entry-service (session old-path new-path)
  (let ((working-directory (package-management-service-working-directory session)))
    (kernelize-service-command-response
     (make-service-command-response
      :package-management
      :update-source-registry-entry
      (sbcl-agent.bootstrap:update-source-registry-entry
       old-path
       new-path
       :project-dir working-directory
       :working-directory working-directory)
      :metadata (make-service-metadata :authority :environment
                                       :command-model :package-management-command-v1
                                       :session session
                                       :runtime-id (default-runtime-id)
                                       :policy-id :workspace-write))
     :session session
     :intention (format nil "Update source registry entry ~A to ~A." old-path new-path)
     :capability :package-management/edit-source-registry
     :authority :environment)))

(defun command-package-management-remove-source-registry-entry-service (session path)
  (let ((working-directory (package-management-service-working-directory session)))
    (kernelize-service-command-response
     (make-service-command-response
      :package-management
      :remove-source-registry-entry
      (sbcl-agent.bootstrap:remove-source-registry-entry
       path
       :project-dir working-directory
       :working-directory working-directory)
      :metadata (make-service-metadata :authority :environment
                                       :command-model :package-management-command-v1
                                       :session session
                                       :runtime-id (default-runtime-id)
                                       :policy-id :workspace-write))
     :session session
     :intention (format nil "Remove source registry entry ~A." path)
     :capability :package-management/edit-source-registry
     :authority :environment)))

(defun command-package-management-add-local-project-service (session path &key name)
  (let ((working-directory (package-management-service-working-directory session)))
    (kernelize-service-command-response
     (make-service-command-response
      :package-management
      :add-local-project
      (sbcl-agent.bootstrap:add-local-project
       path
       :name name
       :project-dir working-directory
       :working-directory working-directory)
      :metadata (make-service-metadata :authority :environment
                                       :command-model :package-management-command-v1
                                       :session session
                                       :runtime-id (default-runtime-id)
                                       :policy-id :workspace-write))
     :session session
     :intention (format nil "Add local project ~A." (or name path))
     :capability :package-management/manage-local-projects
     :authority :environment)))

(defun command-package-management-remove-local-project-service (session name)
  (let ((working-directory (package-management-service-working-directory session)))
    (kernelize-service-command-response
     (make-service-command-response
      :package-management
      :remove-local-project
      (sbcl-agent.bootstrap:remove-local-project
       name
       :project-dir working-directory
       :working-directory working-directory)
      :metadata (make-service-metadata :authority :environment
                                       :command-model :package-management-command-v1
                                       :session session
                                       :runtime-id (default-runtime-id)
                                       :policy-id :workspace-write))
     :session session
     :intention (format nil "Remove local project ~A." name)
     :capability :package-management/manage-local-projects
     :authority :environment)))
