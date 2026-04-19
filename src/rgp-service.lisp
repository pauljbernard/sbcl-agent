(in-package #:sbcl-agent)

(defun command-rgp-bind-service (session &key tenant-id request-id agent-session-id integration-id projection-id environment)
  (let* ((binding (bind-environment-to-rgp session
                                           :tenant-id tenant-id
                                           :request-id request-id
                                           :agent-session-id agent-session-id
                                           :integration-id integration-id
                                           :projection-id projection-id
                                           :environment environment))
         (active-environment (ensure-environment environment)))
    (make-service-command-response :rgp
                                   :bind
                                   (list :binding (rgp-binding-summary active-environment)
                                         :governed-runtime (environment-rgp-runtime-summary active-environment)
                                         :environment-id (environment-id active-environment)
                                         :session-id (agent-session-id session)
                                         :updated-binding binding)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-command-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun query-rgp-show-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :show
                                 (environment-rgp-snapshot active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-snapshot-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-rgp-export-service (session path &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-command-response :rgp
                                   :export
                                   (export-environment-rgp-snapshot path active-environment)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-command-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun query-rgp-artifacts-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :artifacts
                                 (environment-rgp-artifact-summaries active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-artifacts-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-rgp-approvals-service (session &optional environment)
  (let ((active-environment (ensure-rgp-bound-environment session environment)))
    (make-service-query-response :rgp
                                 :approvals
                                 (environment-rgp-approval-summaries active-environment)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :rgp-approvals-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-rgp-approve-service (session work-item-id policy &key reason environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (approval-response (command-request-work-item-approval-service session
                                                                        work-item-id
                                                                        policy
                                                                        :reason reason)))
    (make-service-command-response :rgp
                                   :approve
                                   (list :binding (rgp-binding-summary active-environment)
                                         :approval (getf (service-response-data approval-response) :wait)
                                         :work-item (getf (service-response-data approval-response) :work-item)
                                         :workflow-record (getf (service-response-data approval-response) :workflow-record))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-command-v1
                                                                    :session session
                                                                    :environment active-environment
                                                                    :work-item-id work-item-id
                                                                    :policy-id policy))))

(defun command-rgp-resume-service (session work-item-id &key note environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (work-item (find-work-item session work-item-id)))
    (unless work-item
      (error "Unknown work-item ~A" work-item-id))
    (resume-work-item session work-item :note note)
    (make-service-command-response :rgp
                                   :resume
                                   (list :binding (rgp-binding-summary active-environment)
                                         :approval (work-item-wait-report session work-item)
                                         :work-item (enriched-work-item-service-detail session work-item))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :rgp-command-v1
                                                                    :session session
                                                                    :environment active-environment
                                                                    :work-item-id work-item-id))))
