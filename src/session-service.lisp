(in-package #:sbcl-agent)

(defun query-session-summary-service (session)
  (let* ((summary (session-summary session))
         (blocked-work-items (remove-if-not #'blocked-work-item-summary-p
                                            (or (getf (getf summary :wait-summary) :blocked-work-items)
                                                '())))
         (approval-work-items (remove-if-not #'approval-work-item-summary-p
                                             blocked-work-items)))
    (make-service-query-response :session
                                 :summary
                                 (append summary
                                         (list :execution-surfaces
                                               (compact-execution-surfaces-data
                                                (service-response-data
                                                 (query-execution-surfaces-service session)))
                                               :blocked-work-surfaces
                                               (compact-work-item-surfaces-data
                                                session
                                                blocked-work-items
                                                '(:queue :blocked-work)
                                                (session-bound-environment session))
                                               :approval-surfaces
                                               (compact-work-item-surfaces-data
                                                session
                                                approval-work-items
                                                '(:queue :approvals)
                                                (session-bound-environment session))))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :session-summary-v1
                                                                  :session session))))

(defun command-session-save-service (session path)
  (make-service-command-response :session
                                 :save
                                 (progn
                                   (save-session session path)
                                   (list :saved path
                                         :summary (session-summary session)))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :session-command-v1
                                                                  :session session)))

(defun command-session-load-service (path)
  (let ((session (load-session path)))
    (make-service-command-response :session
                                   :load
                                   (list :loaded path
                                         :summary (session-summary session)
                                         :session session)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :session-command-v1
                                                                    :session session))))
