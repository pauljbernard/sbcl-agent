(in-package #:sbcl-agent)

(defun query-session-summary-service (session)
  (make-service-query-response :session
                               :summary
                               (session-summary session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :session-summary-v1
                                                                :session session)))

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
