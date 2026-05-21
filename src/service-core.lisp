(in-package #:sbcl-agent)

(defparameter +service-contract-version+ 1)

(defun keyword-plist-p (value)
  (and (listp value)
       (loop for tail on value by #'cddr
             always (and (consp tail)
                         (keywordp (first tail))))))

(defun ensure-service-session-environment (session)
  (or (and session
           (agent-session-bound-environment session))
      (and session
           (bind-session-to-environment
            session
            (make-default-environment :session session
                                      :storage-root (agent-session-cwd session))))))

(defun service-active-environment (&key session environment (ensure-p t) (bind-session-p t))
  (let* ((resolved (or environment
                       (and session
                            (ensure-service-session-environment session))
                       (and (boundp '*current-environment*) *current-environment*)
                       (and ensure-p (ensure-environment)))))
    (when (and resolved
               ensure-p)
      (setf resolved (ensure-environment resolved)))
    (when (and resolved
               session
               bind-session-p
               (fboundp 'bind-session-to-environment)
               (not (eq (environment-compatibility-session resolved) session)))
      (bind-session-to-environment session resolved))
    resolved))

(defun service-authority-source (&key session environment)
  (let ((active-environment (service-active-environment :session session
                                                        :environment environment
                                                        :ensure-p nil
                                                        :bind-session-p nil)))
    (if active-environment
        :environment
        :session-compatibility)))

(defun service-bound-environment-id (&key session environment)
  (let ((active-environment (service-active-environment :session session
                                                        :environment environment
                                                        :ensure-p nil
                                                        :bind-session-p nil)))
    (and active-environment
         (environment-id active-environment))))

(defun make-service-metadata (&key authority read-model command-model session environment
                                policy-id thread-id turn-id work-item-id workflow-record-id
                                incident-id runtime-id event-family visibility)
  (let ((session-id (and session (agent-session-id session)))
        (environment-id (service-bound-environment-id :session session :environment environment))
        (authority-source (service-authority-source :session session :environment environment)))
    (list :authority authority
          :authority-source authority-source
          :binding (list :session-id session-id
                         :environment-id environment-id)
          :read-model read-model
          :command-model command-model
          :policy-id policy-id
          :session-id session-id
          :environment-id environment-id
          :thread-id thread-id
          :turn-id turn-id
          :work-item-id work-item-id
          :workflow-record-id workflow-record-id
          :incident-id incident-id
          :runtime-id runtime-id
          :event-family event-family
          :visibility visibility)))

(defun make-service-response (domain operation kind data &key (status :ok) metadata)
  (list :contract-version +service-contract-version+
        :domain domain
        :operation operation
        :kind kind
        :status status
        :data data
        :metadata metadata))

(defun make-service-query-response (domain operation data &key metadata)
  (make-service-response domain operation :query data :metadata metadata))

(defun make-service-command-response (domain operation data &key metadata)
  (make-service-response domain operation :command data :metadata metadata))

(defun service-response-metadata (response)
  (getf response :metadata))

(defun service-response-data (response)
  (getf response :data))
