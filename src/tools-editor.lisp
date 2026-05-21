(in-package #:sbcl-agent)

(defun make-workspace-command-actor-address (session)
  (make-standard-actor-address :editor
                               :scope (agent-session-id session)))

(defun actorize-workspace-command-response (response
                                            &key actor-execution-job-id
                                              governance-authority
                                              policy-id
                                              approval-required-p
                                              approval-granted-p)
  (if (listp response)
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (when actor-execution-job-id
          (setf (getf metadata :actor-execution-job-id) actor-execution-job-id))
        (when governance-authority
          (setf (getf metadata :governance-authority) governance-authority))
        (when policy-id
          (setf (getf metadata :policy-id) policy-id))
        (setf (getf metadata :approval-required-p) (and approval-required-p t)
              (getf metadata :approval-granted-p) (and approval-granted-p t)
              (getf response :metadata) metadata)
        (when (keyword-plist-p data)
          (let ((updated-data (copy-list data)))
            (when actor-execution-job-id
              (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id))
            (when governance-authority
              (setf (getf updated-data :governance-authority) governance-authority))
            (when policy-id
              (setf (getf updated-data :policy-id) policy-id))
            (setf (getf updated-data :approval-required-p) (and approval-required-p t)
                  (getf updated-data :approval-granted-p) (and approval-granted-p t)
                  (getf response :data) updated-data)))
        response)
      response))

(defun make-workspace-command-request (session action capability &key payload metadata)
  (make-governed-desktop-task-request
   :requester :editor
   :target :editor
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :workspace-command-v1)
                     metadata)))

(defun workspace-command-approval-required-p (policy-id)
  (let ((policy (and policy-id
                     (ignore-errors (ensure-capability-policy policy-id)))))
    (and policy
         (not (eq (capability-policy-default-grant-mode policy) :implicit)))))

(defun current-workspace-actor-context ()
  (let* ((job (and (fboundp 'current-actor-execution-job)
                   (current-actor-execution-job))))
    (and job (actor-execution-job-context job))))

(defun workspace-self-modification-targets (capability payload)
  (let ((normalized (capability-name-string capability)))
    (cond
      ((string= normalized "workspace/patch")
       (let ((targets '()))
         (dolist (operation payload (nreverse targets))
           (when (and (consp operation)
                      (eq (first operation) :write)
                      (self-modification-pathname-p (second operation)))
             (push (second operation) targets)))))
      ((string= normalized "workspace/promote-patch")
       (let* ((entries (or (and (listp payload) (getf payload :verified-patch))
                           (and (listp payload) (getf payload :VERIFIED-PATCH))
                           '()))
              (targets '()))
         (dolist (entry entries (nreverse targets))
           (let ((path (and (listp entry) (getf entry :path))))
             (when (and path
                        (self-modification-pathname-p path))
               (push path targets))))))
      (t nil))))

(defun ensure-workspace-governance-checkpoint (session work-item capability)
  (when (and work-item
             (not (latest-work-item-checkpoint-id work-item)))
    (append-work-item-checkpoint
     session
     work-item
     :validation-baseline (list :workspace-checkpointed-p t
                                :capability capability
                                :policy-id :workspace-write
                                :mutation-class :workspace-mutation
                                :work-item-id (work-item-id work-item)))))

(defun enforce-workspace-governed-actor-execution (session capability payload actor-context
                                                   &key policy-id approval-required-p)
  (let* ((work-item-id (and actor-context
                            (actor-execution-context-work-item-id actor-context)))
         (work-item (and work-item-id
                         (find-work-item session work-item-id)))
         (self-modification-targets (workspace-self-modification-targets capability payload))
         (approved-p (and policy-id
                          (ignore-errors (policy-approved-p session policy-id))))
         (mutation-block-reasons
           (and work-item
                (let ((reasons (work-item-mutation-block-reasons work-item)))
                  (if approved-p
                      (remove :awaiting-approval reasons :test #'eq)
                      reasons)))))
    (when (and self-modification-targets
               (null work-item))
      (error "Workspace mutation blocked for self-modifying change without governed work-item binding: ~S"
             self-modification-targets))
    (when mutation-block-reasons
      (error "Workspace mutation blocked in current recovery posture: ~S"
             mutation-block-reasons))
    (when (and approval-required-p policy-id)
      (ensure-policy-approved session policy-id))
    (when work-item
      (ensure-workspace-governance-checkpoint session work-item capability))))

(defun call-with-workspace-command-actor (session request thunk capability action
                                          &key metadata payload policy-id approval-required-p)
  (let* ((actor-address (make-workspace-command-actor-address session))
         (actor-context (make-actor-execution-context
                         :actor-id (actor-address-id actor-address)
                         :capability capability
                         :authority :workspace-write
                         :policy-id policy-id
                         :target :editor
                         :operation action
                         :request-id (desktop-task-request-id request)
                         :approval-required-p approval-required-p
                         :metadata metadata))
         (approval-granted-p (and approval-required-p
                                  policy-id
                                  (ignore-errors (policy-approved-p session policy-id)))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (when (fboundp 'update-current-actor-execution-context)
         (update-current-actor-execution-context actor-context :replace-p t))
       (enforce-workspace-governed-actor-execution
        session capability payload actor-context
        :policy-id policy-id
        :approval-required-p approval-required-p)
       (actorize-workspace-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)
        :governance-authority :actor-runtime
        :policy-id policy-id
        :approval-required-p approval-required-p
        :approval-granted-p approval-granted-p))
     :context actor-context)))

(defun perform-editor-append-text (session &key text scope-id buffer-id package-name pending-action-id)
  (unless text
    (error "EDITOR/APPEND-TEXT requires :text"))
  (let ((thread-id (and (boundp '*runtime-governance-thread*)
                        *runtime-governance-thread*
                        (thread-id *runtime-governance-thread*)))
        (turn-id (and (boundp '*runtime-governance-turn*)
                      *runtime-governance-turn*
                      (turn-id *runtime-governance-turn*))))
    (append-session-event session
                          :editor-buffer-updated
                          (list :mode "append"
                                :text text
                                :scope-id scope-id
                                :buffer-id buffer-id
                                :package-name package-name
                                :pending-action-id pending-action-id
                                :summary "Appended text to the active editor buffer.")
                          :family :assistant
                          :thread-id thread-id
                          :turn-id turn-id)
    (list :mode "append"
          :text text
          :scope-id scope-id
          :buffer-id buffer-id
          :package-name package-name
          :pending-action-id pending-action-id
          :receiver-actor :editor
          :receiver-state :completed
          :summary "Appended text to the active editor buffer.")))

(defun command-editor-append-text-service (session &key text scope-id buffer-id package-name pending-action-id)
  (let* ((thread (and (boundp '*runtime-governance-thread*)
                      *runtime-governance-thread*))
         (turn (and (boundp '*runtime-governance-turn*)
                    *runtime-governance-turn*))
         (policy-id :workspace-write)
         (payload (list :text text
                        :scope-id scope-id
                        :buffer-id buffer-id
                        :package-name package-name
                        :pending-action-id pending-action-id))
         (request (make-workspace-command-request session
                                                  :append-text
                                                  :editor/append-text
                                                  :payload payload
                                                  :metadata (append (when scope-id
                                                                      (list :scope-id scope-id))
                                                                    (when buffer-id
                                                                      (list :buffer-id buffer-id))
                                                                    (when package-name
                                                                      (list :package-name package-name))
                                                                    (when pending-action-id
                                                                      (list :pending-action-id pending-action-id))))))
    (register-service-command-response
     (call-with-workspace-command-actor
      session
      request
      (lambda ()
        (make-service-command-response
         :editor
         :append-text
         (perform-editor-append-text session
                                     :text text
                                     :scope-id scope-id
                                     :buffer-id buffer-id
                                     :package-name package-name
                                     :pending-action-id pending-action-id)
         :metadata (make-service-metadata :authority :environment
                                          :command-model :editor-mutation-v1
                                          :session session
                                          :thread-id (and thread (thread-id thread))
                                          :turn-id (and turn (turn-id turn))
                                          :policy-id policy-id)))
      :editor/append-text
      :append-text
      :metadata (append (when scope-id
                          (list :scope-id scope-id))
                        (when buffer-id
                          (list :buffer-id buffer-id))
                        (when package-name
                          (list :package-name package-name))
                        (when pending-action-id
                          (list :pending-action-id pending-action-id)))
      :payload payload
      :policy-id policy-id
      :approval-required-p (workspace-command-approval-required-p policy-id))
     :session session
     :intention "Append governed text to the active editor buffer."
     :capability :editor/append-text
     :authority :workspace-write
     :context (append (when thread
                        (list :thread-id (thread-id thread)))
                      (when turn
                        (list :turn-id (turn-id turn)))
                      (when scope-id
                        (list :scope-id scope-id))
                      (when buffer-id
                        (list :buffer-id buffer-id))
                      (when package-name
                        (list :package-name package-name))
                      (when pending-action-id
                        (list :pending-action-id pending-action-id))))))

(defun tool-editor-append-text (session &key text scope-id buffer-id package-name pending-action-id)
  (service-response-data
   (command-editor-append-text-service session
                                       :text text
                                       :scope-id scope-id
                                       :buffer-id buffer-id
                                       :package-name package-name
                                       :pending-action-id pending-action-id)))

(register-tool :editor/append-text
               "Append text to the active editor buffer shown in the Surface editor panel."
               :workspace-write
               #'tool-editor-append-text)
