(in-package #:sbcl-agent)

(defun query-intent-list-service (session)
  (let* ((environment (or (session-bound-environment session)
                          (ensure-environment)))
         (current-id (current-intent-id environment)))
    (make-service-query-response
     :intent
     :list
     (list :current-intent-id current-id
           :intents (mapcar #'intent-record-summary (list-intent-records session)))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :intent-list-v1
                                      :session session))))

(defun query-intent-detail-service (session intent-id)
  (let* ((environment (or (session-bound-environment session)
                          (ensure-environment)))
         (intent (or (find-intent-record session intent-id)
                     (error "Unknown intent ~A" intent-id))))
    (make-service-query-response
     :intent
     :detail
     (intent-record-detail intent
                           :currentp (string= intent-id
                                              (or (current-intent-id environment) "")))
     :metadata (make-service-metadata :authority :environment
                                      :read-model :intent-detail-v1
                                      :session session))))

(defun command-intent-create-service (session &key description scope constraints
                                              expected-behaviors non-goals priority
                                              (version 1) (status :active)
                                              linked-runtime-objects
                                              linked-source-artifacts
                                              linked-event-ids
                                              linked-mutation-ids
                                              metadata)
  (let ((intent (create-intent-record session
                                      :description description
                                      :scope scope
                                      :constraints constraints
                                      :expected-behaviors expected-behaviors
                                      :non-goals non-goals
                                      :priority priority
                                      :version version
                                      :status status
                                      :linked-runtime-objects linked-runtime-objects
                                      :linked-source-artifacts linked-source-artifacts
                                      :linked-event-ids linked-event-ids
                                      :linked-mutation-ids linked-mutation-ids
                                      :metadata metadata)))
    (make-service-command-response
     :intent
     :create
     (intent-record-detail intent :currentp t)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :intent-command-v1
                                      :session session))))

(defun command-intent-update-service (session intent-id &key description scope constraints
                                              expected-behaviors non-goals priority
                                              version status linked-runtime-objects
                                              linked-source-artifacts linked-event-ids
                                              linked-mutation-ids metadata)
  (let* ((before (or (find-intent-record session intent-id)
                     (error "Unknown intent ~A" intent-id)))
         (updated (update-intent-record
                   session
                   intent-id
                   (lambda (intent)
                     (build-intent-record
                      :id (intent-record-id intent)
                      :description (or description (intent-record-description intent))
                      :scope (or scope (intent-record-scope intent))
                      :constraints (or constraints (intent-record-constraints intent))
                      :expected-behaviors (or expected-behaviors
                                              (intent-record-expected-behaviors intent))
                      :non-goals (or non-goals (intent-record-non-goals intent))
                      :priority (or priority (intent-record-priority intent))
                      :version (or version (1+ (or (intent-record-version intent) 0)))
                      :status (or status (intent-record-status intent))
                      :linked-runtime-objects (or linked-runtime-objects
                                                  (intent-record-linked-runtime-objects intent))
                      :linked-source-artifacts (or linked-source-artifacts
                                                   (intent-record-linked-source-artifacts intent))
                      :linked-event-ids (or linked-event-ids
                                            (intent-record-linked-event-ids intent))
                      :linked-mutation-ids (or linked-mutation-ids
                                               (intent-record-linked-mutation-ids intent))
                      :metadata (or metadata (intent-record-metadata intent)))))))
    (make-service-command-response
     :intent
     :update
     (append (intent-record-detail updated
                                   :currentp (string= (intent-record-id updated)
                                                      (or (current-intent-id (session-bound-environment session))
                                                          "")))
             (list :diff (intent-record-diff before updated)))
     :metadata (make-service-metadata :authority :environment
                                      :command-model :intent-command-v1
                                      :session session))))

(defun command-intent-select-service (session intent-id)
  (let* ((selected (select-intent-record session intent-id)))
    (make-service-command-response
     :intent
     :select
     (intent-record-detail selected :currentp t)
     :metadata (make-service-metadata :authority :environment
                                      :command-model :intent-command-v1
                                      :session session))))
