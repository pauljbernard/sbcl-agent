(in-package #:sbcl-agent)

(defun package-management-service-working-directory (session)
  (or (agent-session-cwd session)
      (namestring (getcwd))))

(defun make-package-management-actor-address (session)
  (make-standard-actor-address :package-management
                               :scope (agent-session-id session)))

(defun actorize-package-management-command-response (response &key actor-execution-job-id)
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

(defun make-package-management-request (session action capability &key payload metadata)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :package-management
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :package-management-control-v1)
                     metadata)))

(defun call-with-package-management-actor (session request thunk capability action &key metadata)
  (let ((actor-address (make-package-management-actor-address session)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-package-management-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :governance
               :target :package-management
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata metadata))))

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

(defun command-package-management-summary-query-service (session)
  (call-with-package-management-actor
   session
   (make-package-management-request session
                                    :summary
                                    :package-management/summary)
   (lambda ()
     (command-kernel-invoke-service
      session
      "Read package-management summary for the current workspace."
      "package-management/summary"
      :authority :environment))
   :package-management/summary
   :summary))

(defun perform-package-management-install-quicklisp-service (session system-name)
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

(defun command-package-management-install-quicklisp-service (session system-name)
  (call-with-package-management-actor
   session
   (make-package-management-request session
                                    :install-quicklisp
                                    :package-management/install-quicklisp
                                    :payload (list :system-name system-name))
   (lambda ()
     (perform-package-management-install-quicklisp-service session system-name))
   :package-management/install-quicklisp
   :install-quicklisp
   :metadata (list :system-name system-name)))

(defun perform-package-management-run-qlot-service (session arguments)
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

(defun command-package-management-run-qlot-service (session arguments)
  (call-with-package-management-actor
   session
   (make-package-management-request session
                                    :run-qlot
                                    :package-management/run-qlot
                                    :payload (list :arguments arguments))
   (lambda ()
     (perform-package-management-run-qlot-service session arguments))
   :package-management/run-qlot
   :run-qlot
   :metadata (list :arguments arguments)))

(defun perform-package-management-add-source-registry-entry-service (session path)
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

(defun command-package-management-add-source-registry-entry-service (session path)
  (call-with-package-management-actor
   session
   (make-package-management-request session
                                    :add-source-registry-entry
                                    :package-management/edit-source-registry
                                    :payload (list :path path))
   (lambda ()
     (perform-package-management-add-source-registry-entry-service session path))
   :package-management/edit-source-registry
   :add-source-registry-entry
   :metadata (list :path path)))

(defun perform-package-management-update-source-registry-entry-service (session old-path new-path)
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

(defun command-package-management-update-source-registry-entry-service (session old-path new-path)
  (call-with-package-management-actor
   session
   (make-package-management-request session
                                    :update-source-registry-entry
                                    :package-management/edit-source-registry
                                    :payload (list :old-path old-path
                                                   :new-path new-path))
   (lambda ()
     (perform-package-management-update-source-registry-entry-service session old-path new-path))
   :package-management/edit-source-registry
   :update-source-registry-entry
   :metadata (list :old-path old-path
                   :new-path new-path)))

(defun perform-package-management-remove-source-registry-entry-service (session path)
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

(defun command-package-management-remove-source-registry-entry-service (session path)
  (call-with-package-management-actor
   session
   (make-package-management-request session
                                    :remove-source-registry-entry
                                    :package-management/edit-source-registry
                                    :payload (list :path path))
   (lambda ()
     (perform-package-management-remove-source-registry-entry-service session path))
   :package-management/edit-source-registry
   :remove-source-registry-entry
   :metadata (list :path path)))

(defun perform-package-management-add-local-project-service (session path &key name)
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

(defun command-package-management-add-local-project-service (session path &key name)
  (call-with-package-management-actor
   session
   (make-package-management-request session
                                    :add-local-project
                                    :package-management/manage-local-projects
                                    :payload (list :path path
                                                   :name name))
   (lambda ()
     (perform-package-management-add-local-project-service session path :name name))
   :package-management/manage-local-projects
   :add-local-project
   :metadata (list :path path
                   :name name)))

(defun perform-package-management-remove-local-project-service (session name)
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

(defun command-package-management-remove-local-project-service (session name)
  (call-with-package-management-actor
   session
   (make-package-management-request session
                                    :remove-local-project
                                    :package-management/manage-local-projects
                                    :payload (list :name name))
   (lambda ()
     (perform-package-management-remove-local-project-service session name))
   :package-management/manage-local-projects
   :remove-local-project
   :metadata (list :name name)))
