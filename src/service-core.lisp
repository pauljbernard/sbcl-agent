(in-package #:sbcl-agent)

(defparameter +service-contract-version+ 1)

(defun service-bound-environment-id (&key session environment)
  (let ((active-environment (or environment
                                (and session (session-bound-environment session))
                                (and (boundp '*current-environment*) *current-environment*))))
    (and active-environment
         (environment-id active-environment))))

(defun make-service-metadata (&key authority read-model command-model session environment
                                policy-id thread-id turn-id work-item-id workflow-record-id
                                incident-id runtime-id event-family visibility)
  (let ((session-id (and session (agent-session-id session)))
        (environment-id (service-bound-environment-id :session session :environment environment)))
    (list :authority authority
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
