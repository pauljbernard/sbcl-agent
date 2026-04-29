(in-package #:sbcl-agent)

(defparameter +kernel-doctrine-rules+
  '("Nothing happens except through invoke."
    "Everything that happens is an execution."
    "Every execution carries intention, capability, authority, state, and trace."
    "Every execution can be inspected."
    "Every execution can be controlled."
    "Mutations require checkpoints."
    "Authority cannot be self-granted."
    "Policy cannot be bypassed."))

(defun kernel-capability-name (capability)
  (typecase capability
    (keyword (string-downcase (symbol-name capability)))
    (symbol (string-downcase (symbol-name capability)))
    (string capability)
    (t (princ-to-string capability))))

(defun execution-handle-execution-id (handle)
  (getf handle :execution-id))

(defun execution-handle-target-value (handle key)
  (getf (getf handle :target) key))

(defun ensure-kernel-handle (execution-or-id &optional environment)
  (cond
    ((and (listp execution-or-id) (getf execution-or-id :execution-id))
     execution-or-id)
    ((stringp execution-or-id)
     (or (kernel-find-execution execution-or-id environment)
         (error "Unknown kernel execution ~A" execution-or-id)))
    (t
     (error "Expected a kernel execution handle or execution id, got ~S" execution-or-id))))

(defun kernel-observed-status (session handle)
  (case (kernel-execution-object-kind handle)
    (:compatibility-execution
     (compatibility-execution-status handle))
    (:work-item
     (let ((work-item-id (execution-handle-target-value handle :work-item-id)))
       (and work-item-id
            (let ((work-item (find-work-item session work-item-id)))
              (and work-item
                   (work-item-status work-item))))))
    (:workflow-record
     (let ((record-id (execution-handle-target-value handle :workflow-record-id)))
       (and record-id
            (let ((record (find-workflow-record session record-id)))
              (and record
                   (workflow-record-status record))))))
    (:incident
     (let ((incident-id (execution-handle-target-value handle :incident-id)))
       (and incident-id
            (let ((incident (find-incident session incident-id)))
              (and incident
                   (incident-status incident))))))
    (:turn
     (let ((turn-id (execution-handle-target-value handle :turn-id)))
       (and turn-id
            (let ((turn (find-turn session turn-id)))
              (and turn
                   (turn-status turn))))))
    (:thread
     (let ((thread-id (execution-handle-target-value handle :thread-id)))
       (and thread-id
            (let ((thread (find-thread session thread-id)))
              (and thread
                   (thread-status thread))))))
    (:task
     (let ((task-id (execution-handle-target-value handle :task-id)))
       (and task-id
            (let ((task (find-task session task-id)))
              (and task
                   (task-status task))))))
    (:worker
     (let ((worker-id (execution-handle-target-value handle :worker-id)))
       (and worker-id
            (let ((worker (find-worker session worker-id)))
              (and worker
                   (if (worker-state-running-p worker) :running :stopped))))))
    (:runtime
     (or (getf (service-response-data (query-runtime-summary-service session)) :status)
         (getf handle :status)))
    (otherwise
     (getf handle :status))))

(defun observe-kernel-handle-status (session execution-or-id &optional environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handle (ensure-kernel-handle execution-or-id active-environment))
         (observed-status (kernel-observed-status session handle)))
    (kernel-record-observed-status handle
                                   observed-status
                                   active-environment
                                   :result :observation)))

(defun kernel-invoke-tool-capability (session intention capability payload)
  (declare (ignore intention))
  (let ((tool-id (or (getf payload :tool-id)
                     (let ((name (kernel-capability-name capability)))
                       (when (search "tool/" name :test #'char-equal)
                         (intern (string-upcase (subseq name (length "tool/"))) "KEYWORD"))))))
    (unless tool-id
      (error "Kernel invoke for ~A requires a :tool-id payload entry" capability))
    (command-invoke-tool-service session tool-id (kernel-plist-without-key payload :tool-id))))

(defun kernel-context-thread (session context)
  (or (getf context :thread)
      (let ((thread-id (getf context :thread-id)))
        (and thread-id
             (find-thread session thread-id)))))

(defun kernel-context-turn (session context)
  (or (getf context :turn)
      (let ((turn-id (getf context :turn-id)))
        (and turn-id
             (find-turn session turn-id)))))

(defun kernel-context-operation (context)
  (getf context :operation))

(defun kernel-capability-policy-id (session capability payload response)
  (or (and response
           (getf (service-response-metadata response) :policy-id))
      (and (listp payload)
           (ignore-errors (getf payload :policy)))
      (case (typecase capability
              (keyword capability)
              (symbol capability)
              (t nil))
        (:runtime/eval (runtime-eval-policy-id (and (listp payload)
                                                    (ignore-errors (getf payload :mutating)))))
        (:runtime/reload-file :runtime-reload)
        (:runtime/set-package :runtime-package-switch)
        (:workspace/patch :workspace-write)
        (otherwise nil))
      (let ((normalized (kernel-capability-name capability)))
        (cond
          ((and (stringp capability)
                (find-compatibility-app capability
                                        :session session
                                        :environment (and session
                                                          (session-bound-environment session))))
           (compatibility-app-definition-policy-id
            (find-compatibility-app capability
                                    :session session
                                    :environment (and session
                                                      (session-bound-environment session)))))
          ((string= normalized "workflow/request-approval")
           (and (listp payload)
                (ignore-errors (getf payload :policy))))
          ((search "tool/" normalized :test #'char-equal)
           (let* ((tool-id (or (and (listp payload)
                                    (ignore-errors (getf payload :tool-id)))
                               (intern (string-upcase (subseq normalized (length "tool/"))) "KEYWORD")))
                  (tool-description (and tool-id (ignore-errors (describe-tool tool-id)))))
             (and (listp tool-description)
                  (getf tool-description :policy))))
          (t nil)))))

(defun kernel-governance-mutation-class (capability payload)
  (let ((normalized (kernel-capability-name capability)))
    (cond
      ((string= normalized "runtime/eval")
       (if (and (listp payload)
                (ignore-errors (getf payload :mutating)))
           :runtime-mutation
           :runtime-read))
      ((string= normalized "runtime/reload-file") :runtime-reload)
      ((string= normalized "runtime/set-package") :runtime-package-switch)
      ((string= normalized "workspace/patch") :workspace-mutation)
      ((string= normalized "workflow/request-approval") :approval-request)
      ((string= normalized "rgp/approve") :approval-request)
      ((string= normalized "authority/grant") :authority-grant)
      ((member normalized
               '("assistant/action" "assistant/pending-actions")
               :test #'string=)
       :execution)
      ((member normalized
               '("environment/provider-configure"
                 "environment/provider-use"
                 "environment/provider-routing"
                 "rgp/bind"
                 "rgp/export")
               :test #'string=)
       :environment-mutation)
      ((member normalized
               '("rgp/resume")
               :test #'string=)
       :workflow-mutation)
      ((member normalized
               '("workflow/steer-plan"
                 "workflow/replay-validator-task"
                 "workflow/replay-validator-set"
                 "workflow/reconcile-image-only-source")
               :test #'string=)
       :workflow-mutation)
      ((search "tool/" normalized :test #'char-equal)
       :tool-execution)
      ((member normalized '("conversation/say" "conversation/ask") :test #'string=)
       :conversation)
      (t :execution))))

(defun kernel-governance-mutation-sensitive-p (mutation-class)
  (member mutation-class
          '(:runtime-mutation :runtime-reload :runtime-package-switch :workspace-mutation :workflow-mutation :environment-mutation :tool-execution)
          :test #'eq))

(defun kernel-string-prefix-p (prefix string)
  (and prefix
       string
       (<= (length prefix) (length string))
       (string-equal prefix string :end2 (length prefix))))

(defun kernel-self-modification-pathname-p (path)
  (let* ((namestring-path (and path (namestring (pathname path))))
         (normalized (and namestring-path
                          (substitute #\/ #\\ namestring-path))))
    (and normalized
         (or (search "/src/" normalized :test #'char-equal)
             (search "/tests/" normalized :test #'char-equal)
             (search "/docs/" normalized :test #'char-equal)
             (search "/sbcl-agent.asd" normalized :test #'char-equal)
             (kernel-string-prefix-p "src/" normalized)
             (kernel-string-prefix-p "tests/" normalized)
             (kernel-string-prefix-p "docs/" normalized)
             (string= normalized "sbcl-agent.asd")))))

(defun kernel-self-modifying-package-p (package-name)
  (and package-name
       (or (string-equal package-name "SBCL-AGENT")
           (search "SBCL-AGENT/" package-name :test #'char-equal))))

(defun kernel-self-modification-targets (session capability payload)
  (let ((normalized (kernel-capability-name capability)))
    (cond
      ((string= normalized "workspace/patch")
       (let ((targets '()))
         (dolist (operation payload (nreverse targets))
           (when (and (consp operation)
                      (eq (first operation) :write)
                      (kernel-self-modification-pathname-p (second operation)))
             (push (second operation) targets)))))
      ((string= normalized "runtime/reload-file")
       (let ((path (and (listp payload) (getf payload :path))))
         (when (kernel-self-modification-pathname-p path)
           (list path))))
      ((string= normalized "runtime/eval")
       (let ((package-name (or (and (listp payload) (getf payload :package))
                               (agent-session-package session))))
         (when (kernel-self-modifying-package-p package-name)
           (list package-name))))
      (t nil))))

(defun kernel-context-work-item (session context)
  (or (getf context :work-item)
      (let ((work-item-id (getf context :work-item-id)))
        (and work-item-id
             (find-work-item session work-item-id)))
      (let ((turn (kernel-context-turn session context)))
        (and turn
             (let ((bound-id (getf (turn-metadata turn) :work-item-id)))
               (and bound-id
                    (find-work-item session bound-id)))))))

(defun kernel-governance-preflight (session capability payload context response)
  (let* ((policy-id (kernel-capability-policy-id session capability payload response))
         (mutation-class (kernel-governance-mutation-class capability payload))
         (work-item (kernel-context-work-item session context))
         (mutation-block-reasons (and work-item
                                      (kernel-governance-mutation-sensitive-p mutation-class)
                                      (work-item-mutation-block-reasons work-item)))
         (self-modification-targets (and (kernel-governance-mutation-sensitive-p mutation-class)
                                         (kernel-self-modification-targets session capability payload)))
         (checkpoint-id (and work-item
                             (latest-work-item-checkpoint-id work-item)))
         (policy (and policy-id
                      (ignore-errors (ensure-capability-policy policy-id))))
         (approval-required-p (and policy
                                   (not (eq (capability-policy-default-grant-mode policy) :implicit))))
         (approval-granted-p (and policy-id
                                  (ignore-errors (policy-approved-p session policy-id))))
         (checkpoint-required-p (member mutation-class
                                       '(:runtime-mutation :runtime-reload :workspace-mutation)
                                       :test #'eq))
         (governance-sensitive-p (or approval-required-p checkpoint-required-p
                                     (member mutation-class '(:approval-request :authority-grant) :test #'eq))))
    (list :governance-sensitive-p (not (null governance-sensitive-p))
          :mutation-class mutation-class
          :mutation-allowed-p (null mutation-block-reasons)
          :mutation-block-reasons mutation-block-reasons
          :self-modification-p (not (null self-modification-targets))
          :self-modification-targets self-modification-targets
          :policy-id policy-id
          :approval-required-p (not (null approval-required-p))
          :approval-granted-p (not (null approval-granted-p))
          :checkpoint-required-p (not (null checkpoint-required-p))
          :checkpoint-present-p (not (null checkpoint-id))
          :checkpoint-id checkpoint-id
          :work-item-id (and work-item (work-item-id work-item)))))

(defun ensure-kernel-governance-checkpoint (session capability payload context)
  (let* ((preflight (kernel-governance-preflight session capability payload context nil))
         (work-item-id (getf preflight :work-item-id))
         (work-item (and work-item-id
                         (find-work-item session work-item-id))))
    (when (and work-item
               (getf preflight :checkpoint-required-p)
               (not (getf preflight :checkpoint-present-p)))
      (append-work-item-checkpoint
       session
       work-item
       :validation-baseline (list :kernel-checkpointed-p t
                                  :capability capability
                                  :policy-id (getf preflight :policy-id)
                                  :mutation-class (getf preflight :mutation-class)
                                  :work-item-id work-item-id))))
  (kernel-governance-preflight session capability payload context nil))

(defun enforce-kernel-governance-preflight (session capability payload context)
  (let ((preflight (kernel-governance-preflight session capability payload context nil)))
    (when (and (getf preflight :self-modification-p)
               (not (getf preflight :work-item-id)))
      (error "Kernel invoke blocked for self-modifying mutation without governed work-item binding: ~S"
             (getf preflight :self-modification-targets)))
    (when (and (kernel-governance-mutation-sensitive-p (getf preflight :mutation-class))
               (not (getf preflight :mutation-allowed-p)))
      (error "Kernel invoke blocked for governed mutation in current recovery posture: ~S"
             (getf preflight :mutation-block-reasons)))
    (when (and (getf preflight :approval-required-p)
               (not (getf preflight :approval-granted-p))
               (not (member (getf preflight :mutation-class)
                            '(:approval-request :authority-grant)
                            :test #'eq)))
      (ensure-policy-approved session (getf preflight :policy-id)))
    (ensure-kernel-governance-checkpoint session capability payload context)))

(defun annotate-kernel-invoke-response (response session capability payload context &optional preflight)
  (let* ((metadata (copy-list (or (service-response-metadata response) '())))
         (resolved-preflight (or preflight
                                 (kernel-governance-preflight session capability payload context response))))
    (setf (getf response :metadata)
          (kernel-plist-put metadata :governance-preflight resolved-preflight))
    response))

(defun command-kernel-invoke-service (session intention capability
                                       &key authority context constraints provider options payload environment)
  (ensure-kernel-bound-environment session environment)
  (let* ((normalized (kernel-capability-name capability))
         (thread (kernel-context-thread session context))
         (turn (kernel-context-turn session context))
         (operation (kernel-context-operation context))
         (preflight (enforce-kernel-governance-preflight session capability payload context))
         (response
           (cond
      ((or (string= normalized "conversation/say")
           (string= normalized "conversation/ask"))
       (unless provider
         (error "Kernel invoke for ~A requires a provider" capability))
       (command-conversation-execution-service session
                                              provider
                                              intention
                                              (or options '())
                                              :source (if (string= normalized "conversation/ask") :ask :say)
                                              :operator-mode :conversation))
      ((string= normalized "runtime/eval")
       (let ((*runtime-governance-thread* thread)
             (*runtime-governance-turn* turn)
             (*runtime-governance-operation* operation))
         (declare (special *runtime-governance-thread*
                           *runtime-governance-turn*
                           *runtime-governance-operation*))
         (command-runtime-eval-service session
                                       (or (getf payload :form)
                                           intention)
                                       :package (getf payload :package)
                                       :mutating (getf payload :mutating))))
      ((string= normalized "runtime/reload-file")
       (let ((*runtime-governance-thread* thread)
             (*runtime-governance-turn* turn)
             (*runtime-governance-operation* operation))
         (declare (special *runtime-governance-thread*
                           *runtime-governance-turn*
                           *runtime-governance-operation*))
         (command-runtime-reload-file-service session
                                              (or (getf payload :path)
                                                  (error "Kernel invoke for runtime/reload-file requires :path")))))
      ((string= normalized "runtime/set-package")
       (command-runtime-set-package-service session
                                            (or (getf payload :package)
                                                (error "Kernel invoke for runtime/set-package requires :package"))))
      ((string= normalized "workspace/patch")
       (command-apply-patch-service session
                                    (or payload
                                        (error "Kernel invoke for workspace/patch requires patch operations"))
                                    :thread thread
                                    :turn turn
                                    :operation operation))
      ((string= normalized "workflow/request-approval")
       (command-request-work-item-approval-service session
                                                   (or (getf payload :work-item-id)
                                                       (error "Kernel invoke for workflow/request-approval requires :work-item-id"))
                                                   (or (getf payload :policy)
                                                       (error "Kernel invoke for workflow/request-approval requires :policy"))
                                                   :reason (getf payload :reason)))
      ((string= normalized "environment/provider-configure")
       (command-environment-provider-configure-service
        (or (getf payload :profile-name)
            (error "Kernel invoke for environment/provider-configure requires :profile-name"))
        (or (getf payload :options)
            (error "Kernel invoke for environment/provider-configure requires :options"))
        (session-bound-environment session)))
      ((string= normalized "environment/provider-use")
       (command-environment-provider-use-service
        (or (getf payload :profile-name)
            (error "Kernel invoke for environment/provider-use requires :profile-name"))
        (session-bound-environment session)))
      ((string= normalized "environment/provider-routing")
       (command-environment-provider-routing-service
        (getf payload :mode)
        (session-bound-environment session)))
      ((string= normalized "session/save")
       (command-session-save-service session
                                     (or (getf payload :path)
                                         (error "Kernel invoke for session/save requires :path"))))
      ((string= normalized "session/load")
       (command-session-load-service
        (or (getf payload :path)
            (error "Kernel invoke for session/load requires :path"))))
      ((string= normalized "environment/save")
       (command-environment-save-service
        (or (getf payload :path)
            (error "Kernel invoke for environment/save requires :path"))
        (session-bound-environment session)))
      ((string= normalized "environment/load")
       (command-environment-load-service
        (or (getf payload :path)
            (error "Kernel invoke for environment/load requires :path"))))
      ((string= normalized "conversation/create-thread")
       (command-conversation-create-thread-service session
                                                  :title (getf payload :title)
                                                  :summary (getf payload :summary)
                                                  :metadata (getf payload :metadata)))
      ((string= normalized "conversation/use-thread")
       (command-conversation-use-thread-service
        session
        (or (getf payload :thread-id)
            (error "Kernel invoke for conversation/use-thread requires :thread-id"))))
      ((string= normalized "authority/grant")
       (command-approve-policy-service
        session
        (or (getf payload :policy)
            (error "Kernel invoke for authority/grant requires :policy"))))
      ((string= normalized "assistant/action")
       (command-execute-assistant-action-service
        session
        (or (getf payload :action)
            (error "Kernel invoke for assistant/action requires :action"))
        :thread thread
        :turn turn
        :operation operation))
      ((string= normalized "assistant/pending-actions")
       (command-execute-pending-actions-service session
                                                :thread thread
                                                :turn turn
                                                :operation operation))
      ((string= normalized "rgp/bind")
       (apply #'command-rgp-bind-service
              session
              (append (list :environment (session-bound-environment session))
                      (copy-list (or payload '())))))
      ((string= normalized "rgp/export")
       (command-rgp-export-service session
                                   (or (getf payload :path)
                                       (error "Kernel invoke for rgp/export requires :path"))
                                   (session-bound-environment session)))
      ((string= normalized "rgp/approve")
       (command-rgp-approve-service session
                                    (or (getf payload :work-item-id)
                                        (error "Kernel invoke for rgp/approve requires :work-item-id"))
                                    (or (getf payload :policy)
                                        (error "Kernel invoke for rgp/approve requires :policy"))
                                    :reason (getf payload :reason)
                                    :environment (session-bound-environment session)))
      ((string= normalized "rgp/resume")
       (command-rgp-resume-service session
                                   (or (getf payload :work-item-id)
                                       (error "Kernel invoke for rgp/resume requires :work-item-id"))
                                   :note (getf payload :note)
                                   :environment (session-bound-environment session)))
      ((string= normalized "task/enqueue")
       (let* ((form (or (getf payload :form)
                        (error "Kernel invoke for task/enqueue requires :form")))
              (command (or (getf payload :command)
                           (normalize-form-command form)))
              (priority (or (getf payload :priority) 0)))
         (command-task-enqueue-service session form command priority)))
      ((string= normalized "task/cancel")
       (command-task-cancel-service session
                                    (or (getf payload :task-id)
                                        (error "Kernel invoke for task/cancel requires :task-id"))))
      ((string= normalized "task/run-next")
       (command-task-run-next-service session
                                      (or provider
                                          (error "Kernel invoke for task/run-next requires a provider"))))
      ((string= normalized "worker/start")
       (command-worker-start-service session
                                     (or provider
                                         (error "Kernel invoke for worker/start requires a provider"))))
      ((string= normalized "worker/stop")
       (command-worker-stop-service session
                                    (or (getf payload :worker-id)
                                        (error "Kernel invoke for worker/stop requires :worker-id"))))
      ((string= normalized "workflow/steer-plan")
       (command-work-item-steer-service session
                                        (or (getf payload :work-item-id)
                                            (error "Kernel invoke for workflow/steer-plan requires :work-item-id"))
                                        :phase (or (getf payload :phase)
                                                   (error "Kernel invoke for workflow/steer-plan requires :phase"))
                                        :next-step (or (getf payload :next-step)
                                                       (error "Kernel invoke for workflow/steer-plan requires :next-step"))
                                        :note (getf payload :note)))
      ((string= normalized "workflow/replay-validator-task")
       (command-replay-validator-task-service session
                                              (or (getf payload :work-item-id)
                                                  (error "Kernel invoke for workflow/replay-validator-task requires :work-item-id"))
                                              (or (getf payload :validator-task-id)
                                                  (error "Kernel invoke for workflow/replay-validator-task requires :validator-task-id"))
                                              :status (or (getf payload :status) :passed)))
      ((string= normalized "workflow/replay-validator-set")
       (command-replay-validator-set-service session
                                             (or (getf payload :work-item-id)
                                                 (error "Kernel invoke for workflow/replay-validator-set requires :work-item-id"))
                                             (or (getf payload :replay-id)
                                                 (error "Kernel invoke for workflow/replay-validator-set requires :replay-id"))
                                             :status (or (getf payload :status) :passed)
                                             :statuses (getf payload :statuses)))
      ((string= normalized "workflow/reconcile-image-only-source")
       (command-reconcile-image-only-source-service session
                                                    (or (getf payload :work-item-id)
                                                        (error "Kernel invoke for workflow/reconcile-image-only-source requires :work-item-id"))
                                                    (or (getf payload :summary)
                                                        (error "Kernel invoke for workflow/reconcile-image-only-source requires :summary"))))
      ((string= normalized "platform/package")
       (apply #'command-platform-package-service
              (or (getf payload :output-path)
                  (getf payload :output)
                  (error "Kernel invoke for platform/package requires :output-path"))
              (append (list :package-id (getf payload :package-id)
                            :package-version (getf payload :package-version)
                            :title (getf payload :title)
                            :publisher (getf payload :publisher)
                            :build-system (getf payload :build-system)
                            :source-repository (getf payload :source-repository)
                            :build-kind (getf payload :build-kind)
                            :release-status (getf payload :release-status)
                            :replacement-package-id (getf payload :replacement-package-id)
                            :rollback-strategy (getf payload :rollback-strategy)
                            :failure-mode (getf payload :failure-mode)
                            :recovery-runbook (getf payload :recovery-runbook)
                            :capability-ids (getf payload :capabilities)
                            :environment (session-bound-environment session)
                            :session session)
                      (when (and (listp payload)
                                 (member :backup-required payload :test #'eq))
                        (list :backup-required-p (getf payload :backup-required)))
                      (when (and (listp payload)
                                 (member :attested-p payload :test #'eq))
                        (list :attested-p (getf payload :attested-p))))))
      ((string= normalized "platform/import-package")
       (command-platform-import-package-service
        (or (getf payload :path)
            (error "Kernel invoke for platform/import-package requires :path"))
        :allow-downgrade-p (getf payload :allow-downgrade)
        :allow-deprecated-p (getf payload :allow-deprecated)
        :allow-manual-recovery-p (getf payload :allow-manual-recovery)
        :allow-untrusted-p (getf payload :allow-untrusted)
        :environment (session-bound-environment session)
        :session session))
      ((string= normalized "platform/activate-package")
       (command-platform-activate-package-service
        (or (getf payload :package-id)
            (error "Kernel invoke for platform/activate-package requires :package-id"))
        :environment (session-bound-environment session)
        :session session))
      ((string= normalized "platform/deactivate-package")
       (command-platform-deactivate-package-service
        (or (getf payload :package-id)
            (error "Kernel invoke for platform/deactivate-package requires :package-id"))
        :environment (session-bound-environment session)
        :session session))
      ((string= normalized "platform/install-package")
       (command-platform-install-package-service
        (or (getf payload :path)
            (error "Kernel invoke for platform/install-package requires :path"))
        :allow-downgrade-p (getf payload :allow-downgrade)
        :allow-deprecated-p (getf payload :allow-deprecated)
        :allow-manual-recovery-p (getf payload :allow-manual-recovery)
        :allow-untrusted-p (getf payload :allow-untrusted)
        :environment (session-bound-environment session)
        :session session))
      ((string= normalized "platform/run-harness")
       (command-platform-run-harness-service
        :harness-id (or (getf payload :harness-id) :internal-evaluations)
        :environment (session-bound-environment session)
        :session session))
      ((or (search "tool/" normalized :test #'char-equal)
           (getf payload :tool-id))
       (let ((*runtime-governance-thread* thread)
             (*runtime-governance-turn* turn)
             (*runtime-governance-operation* operation))
         (declare (special *runtime-governance-thread*
                           *runtime-governance-turn*
                           *runtime-governance-operation*))
         (command-invoke-tool-service session
                                      (or (getf payload :tool-id)
                                          (let ((name (kernel-capability-name capability)))
                                            (when (search "tool/" name :test #'char-equal)
                                              (intern (string-upcase (subseq name (length "tool/"))) "KEYWORD"))))
                                      (kernel-plist-without-key payload :tool-id)
                                      :thread thread
                                      :turn turn
                                      :operation operation)))
      ((search "linux." normalized :test #'char-equal)
       (command-invoke-compatibility-app-service session
                                                 normalized
                                                 payload
                                                 :thread thread
                                                 :turn turn
                                                 :operation operation))
      (t
       (error "Unsupported kernel capability ~A" capability))))
         (kernel-session (or (getf (service-response-metadata response) :session)
                             (let ((data (service-response-data response)))
                               (and (plist-shaped-p data)
                                    (typep (getf data :session) 'agent-session)
                                    (getf data :session)))
                             session))
         (kernel-environment (or (getf (service-response-metadata response) :environment)
                                 (and kernel-session
                                      (session-bound-environment kernel-session))
                                 (session-bound-environment session)))
         (kernelized-response
           (if (getf (service-response-metadata response) :execution-id)
               response
               (kernelize-service-command-response response
                                                  :session kernel-session
                                                  :environment kernel-environment
                                                  :intention intention
                                                  :capability capability
                                                  :authority authority
                                                  :context context
                                                  :constraints constraints))))
    (annotate-kernel-invoke-response kernelized-response session capability payload context preflight)))

(defun kernel-execution-object-kind (handle)
  (cond
    ((execution-handle-target-value handle :compatibility-execution) :compatibility-execution)
    ((execution-handle-target-value handle :platform-package-id) :platform-package)
    ((execution-handle-target-value handle :turn-id) :turn)
    ((execution-handle-target-value handle :thread-id) :thread)
    ((execution-handle-target-value handle :task-id) :task)
    ((execution-handle-target-value handle :worker-id) :worker)
    ((execution-handle-target-value handle :workflow-record-id) :workflow-record)
    ((execution-handle-target-value handle :incident-id) :incident)
    ((execution-handle-target-value handle :work-item-id) :work-item)
    ((execution-handle-target-value handle :runtime-id) :runtime)
    (t :execution)))

(defun kernel-related-object-summaries (session handle)
  (let* ((thread-id (execution-handle-target-value handle :thread-id))
         (turn-id (execution-handle-target-value handle :turn-id))
         (task-id (execution-handle-target-value handle :task-id))
         (worker-id (execution-handle-target-value handle :worker-id))
         (work-item-id (execution-handle-target-value handle :work-item-id))
         (workflow-record-id (execution-handle-target-value handle :workflow-record-id))
         (incident-id (execution-handle-target-value handle :incident-id))
         (compatibility-execution (execution-handle-target-value handle :compatibility-execution))
         (runtime-id (execution-handle-target-value handle :runtime-id))
         (thread (and thread-id (find-thread session thread-id)))
         (turn (and turn-id (find-turn session turn-id)))
         (task (and task-id (find-task session task-id)))
         (worker (and worker-id (find-worker session worker-id)))
         (work-item (and work-item-id (find-work-item session work-item-id)))
         (workflow-record
           (or (and workflow-record-id
                    (find-workflow-record session workflow-record-id))
               (and work-item
                    (work-item-workflow-record session work-item))))
         (incident (and incident-id (find-incident session incident-id))))
    (list :thread (and thread (thread-record-summary thread))
          :turn (and turn (turn-record-summary turn))
          :task (and task (task-summary task))
          :worker (and worker (worker-summary worker))
          :work-item (and work-item (work-item-summary work-item))
          :workflow-record (and workflow-record (workflow-record-summary workflow-record))
          :incident (and incident (incident-record-summary incident))
          :compatibility-execution compatibility-execution
          :runtime (and runtime-id
                        (service-response-data (query-runtime-summary-service session))))))

(defun inspect-kernel-execution-handle (session handle)
  (let ((thread-id (execution-handle-target-value handle :thread-id))
        (turn-id (execution-handle-target-value handle :turn-id))
        (task-id (execution-handle-target-value handle :task-id))
        (worker-id (execution-handle-target-value handle :worker-id))
        (work-item-id (execution-handle-target-value handle :work-item-id))
        (workflow-record-id (execution-handle-target-value handle :workflow-record-id))
        (incident-id (execution-handle-target-value handle :incident-id))
        (compatibility-execution (execution-handle-target-value handle :compatibility-execution))
        (runtime-id (execution-handle-target-value handle :runtime-id)))
    (cond
      (compatibility-execution
       (append (kernel-plist-without-key
                (kernel-plist-without-key (copy-list compatibility-execution) :status)
                :control-posture)
               (list :status (compatibility-execution-status handle)
                     :control-posture (compatibility-execution-control-posture handle))))
      (workflow-record-id
       (service-response-data (query-workflow-record-detail-service session workflow-record-id)))
      (thread-id
       (service-response-data (query-conversation-thread-detail-service session thread-id)))
      (turn-id
       (service-response-data (query-conversation-turn-detail-service session turn-id)))
      (task-id
       (service-response-data (query-task-detail-service session task-id)))
      (worker-id
       (service-response-data (query-worker-detail-service session worker-id)))
      (work-item-id
       (service-response-data (query-work-item-detail-service session work-item-id)))
      (incident-id
       (service-response-data (query-incident-detail-service session incident-id)))
      (runtime-id
       (service-response-data (query-runtime-summary-service session)))
      (t
       handle))))

(defun kernel-execution-forensics-summary (handle)
  (list :recorded-at (getf handle :recorded-at)
        :last-observed-status (getf handle :last-observed-status)
        :last-status-change-at (getf handle :last-status-change-at)
        :last-control-action (getf handle :last-control-action)
        :last-control-at (getf handle :last-control-at)
        :history-count (+ (length (or (getf handle :lifecycle-history) '()))
                          (length (or (getf handle :control-history) '())))
        :lifecycle-history (copy-tree (or (getf handle :lifecycle-history) '()))
        :control-history (copy-tree (or (getf handle :control-history) '()))))

(defun query-kernel-inspect-service (session object-id &key environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handle (observe-kernel-handle-status session object-id active-environment))
         (object-kind (kernel-execution-object-kind handle))
         (inspection (inspect-kernel-execution-handle session handle))
         (related (kernel-related-object-summaries session handle))
         (forensics (kernel-execution-forensics-summary handle)))
    (make-service-query-response :kernel
                                 :inspect
                                 (list :execution handle
                                       :object-kind object-kind
                                       :target (getf handle :target)
                                       :inspection inspection
                                       :forensics forensics
                                       :related related
                                       :resolved-via :execution-handle
                                       :doctrine +kernel-doctrine-rules+)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :kernel-inspect-v1
                                                                  :session session
                                                                  :environment active-environment
                                                                  :runtime-id (execution-handle-target-value handle :runtime-id)
                                                                  :thread-id (execution-handle-target-value handle :thread-id)
                                                                  :turn-id (execution-handle-target-value handle :turn-id)
                                                                  :work-item-id (execution-handle-target-value handle :work-item-id)
                                                                  :incident-id (execution-handle-target-value handle :incident-id)))))

(defun execution-surface-kind (handle)
  (case (kernel-execution-object-kind handle)
    (:compatibility-execution "compatibility")
    (:work-item "governed-work")
    (:workflow-record "workflow")
    (:incident "incident")
    (:turn "conversation")
    (:runtime "runtime")
    (otherwise "execution")))

(defun execution-surface-title (handle related)
  (let ((object-kind (kernel-execution-object-kind handle))
        (compatibility-target (execution-handle-target-value handle :compatibility-execution)))
    (or
     (case object-kind
       (:compatibility-execution
        (let ((argv (getf compatibility-target :argv)))
          (if argv
              (format nil "Hosted compatibility execution: ~{~A~^ ~}" argv)
              "Hosted compatibility execution")))
       (:work-item
        (or (getf (getf related :work-item) :goal)
            "Governed work item"))
       (:workflow-record
        (or (getf (getf related :workflow-record) :goal)
            "Workflow record"))
       (:incident
        (or (getf (getf related :incident) :title)
            "Incident"))
       (:turn
        (or (getf (getf related :thread) :title)
            "Conversation turn"))
       (:runtime
        "Live runtime")
       (otherwise nil))
     (format nil "Execution ~A" (execution-handle-execution-id handle)))))

(defun execution-surface-status (handle related)
  (case (kernel-execution-object-kind handle)
    (:compatibility-execution (compatibility-execution-status handle))
    (:work-item (getf (getf related :work-item) :status))
    (:workflow-record (getf (getf related :workflow-record) :status))
    (:incident (getf (getf related :incident) :status))
    (:turn (getf (getf related :turn) :status))
    (otherwise (getf handle :status))))

(defun execution-surface-attention-rank (handle related)
  (let* ((status (execution-surface-status handle related))
         (compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (detached-runtime-loss-p (and compatibility-target
                                       (getf compatibility-target :detached-runtime-loss-p)))
         (loss-acknowledged-p (and compatibility-target
                                   (getf compatibility-target :loss-acknowledged-p))))
    (cond
      ((and detached-runtime-loss-p (not loss-acknowledged-p)) 0)
      ((member status '(:awaiting-approval :quarantined :open :failed :awaiting-cold-validation)
               :test #'eq)
       1)
      ((member status '(:running :in-progress :blocked :interrupted) :test #'eq)
       3)
      (t 5))))

(defun execution-surface-summary (session handle &optional environment)
  (declare (ignore environment))
  (let* ((related (kernel-related-object-summaries session handle))
         (status (execution-surface-status handle related))
         (kind (execution-surface-kind handle))
         (compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (control-posture (and compatibility-target
                               (compatibility-execution-control-posture handle))))
    (list :surface-id (format nil "surface-~A" (execution-handle-execution-id handle))
          :surface-kind kind
          :attention-rank (execution-surface-attention-rank handle related)
          :execution-id (execution-handle-execution-id handle)
          :title (execution-surface-title handle related)
          :status status
          :capability (kernel-capability-name (getf handle :capability))
          :object-kind (string-downcase (symbol-name (kernel-execution-object-kind handle)))
          :thread-id (execution-handle-target-value handle :thread-id)
          :turn-id (execution-handle-target-value handle :turn-id)
          :work-item-id (execution-handle-target-value handle :work-item-id)
          :workflow-record-id (execution-handle-target-value handle :workflow-record-id)
          :incident-id (execution-handle-target-value handle :incident-id)
          :runtime-id (execution-handle-target-value handle :runtime-id)
          :primary-execution-handle (kernel-execution-summary handle)
          :control-posture control-posture
          :related related)))

(defun compact-execution-surface-summary (surface)
  (when surface
    (list :surface-id (getf surface :surface-id)
          :surface-kind (getf surface :surface-kind)
          :attention-rank (getf surface :attention-rank)
          :execution-id (getf surface :execution-id)
          :title (getf surface :title)
          :status (getf surface :status)
          :capability (getf surface :capability)
          :object-kind (getf surface :object-kind)
          :thread-id (getf surface :thread-id)
          :turn-id (getf surface :turn-id)
          :work-item-id (getf surface :work-item-id)
          :workflow-record-id (getf surface :workflow-record-id)
          :incident-id (getf surface :incident-id)
          :runtime-id (getf surface :runtime-id)
          :primary-execution-handle (getf surface :primary-execution-handle)
          :control-posture (getf surface :control-posture))))

(defun compact-execution-surfaces-data (surfaces-data)
  (when surfaces-data
    (list :count (getf surfaces-data :count)
          :top-surface (compact-execution-surface-summary
                        (getf surfaces-data :top-surface))
          :items (mapcar #'compact-execution-surface-summary
                         (or (getf surfaces-data :items) '()))
          :filter (getf surfaces-data :filter))))

(defun query-execution-surface-by-id (session execution-id &key environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handle (and (kernel-find-execution execution-id active-environment)
                      (observe-kernel-handle-status session execution-id active-environment))))
    (when handle
      (execution-surface-summary session handle active-environment))))

(defun primary-execution-surface-summary (session execution-handles &key environment)
  (let ((execution-id (and (consp execution-handles)
                           (getf (first execution-handles) :execution-id))))
    (when execution-id
      (query-execution-surface-by-id session execution-id :environment environment))))

(defun query-execution-surfaces-service (session &key environment surface-kind)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handles (mapcar (lambda (handle)
                            (observe-kernel-handle-status session handle active-environment))
                          (kernel-execution-registry active-environment)))
         (surfaces (remove nil
                           (mapcar (lambda (handle)
                                     (let ((surface (execution-surface-summary session handle active-environment)))
                                       (if (or (null surface-kind)
                                               (string= surface-kind
                                                        (getf surface :surface-kind)))
                                           surface
                                           nil)))
                                   handles)))
         (sorted (sort surfaces #'< :key (lambda (surface)
                                           (or (getf surface :attention-rank) 99)))))
    (make-service-query-response :kernel
                                 :surfaces
                                 (list :count (length sorted)
                                       :top-surface (first sorted)
                                       :items sorted
                                       :filter (list :surface-kind surface-kind))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :execution-surfaces-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun compatibility-execution-summary (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (summary (kernel-execution-summary handle)))
    (setf (getf summary :status) (compatibility-execution-status handle))
    (append summary
            (list :compatibility compatibility-target
                  :kind (getf compatibility-target :kind)
                  :app-id (getf compatibility-target :app-id)
                  :title (getf compatibility-target :title)
                  :source-package-id (getf compatibility-target :source-package-id)
                  :policy-id (getf compatibility-target :policy-id)
                  :launch-tool-id (getf compatibility-target :launch-tool-id)
                  :backend (getf compatibility-target :backend)
                  :backend-adapter-id (getf compatibility-target :backend-adapter-id)
                  :backend-implementation (getf compatibility-target :backend-implementation)
                  :backend-profile-id (getf compatibility-target :backend-profile-id)
                  :backend-profile (getf compatibility-target :backend-profile)
                  :bridge-session-id (getf compatibility-target :bridge-session-id)
                  :bridge-attached-p (not (null (getf compatibility-target :bridge-attached-p)))
                  :sandbox-profile (getf compatibility-target :sandbox-profile)
                  :filesystem-scope (getf compatibility-target :filesystem-scope)
                  :filesystem-scope-kind (getf compatibility-target :filesystem-scope-kind)
                  :network-enabled-p (getf compatibility-target :network-enabled-p)
                  :network-policy (getf compatibility-target :network-policy)
                  :workspace-write-p (getf compatibility-target :workspace-write-p)
                  :display-surface-kind (getf compatibility-target :display-surface-kind)
                  :window-state (getf compatibility-target :window-state)
                  :sandbox-network-enabled-p (getf compatibility-target :sandbox-network-enabled-p)
                  :sandbox-workspace-write-p (getf compatibility-target :sandbox-workspace-write-p)
                  :registered-at (getf compatibility-target :registered-at)
                  :last-observed-status (or (getf compatibility-target :last-observed-status)
                                            (compatibility-execution-status handle))
                  :last-status-change-at (getf compatibility-target :last-status-change-at)
                  :last-control-action (getf compatibility-target :last-control-action)
                  :last-control-at (getf compatibility-target :last-control-at)
                  :detached-runtime-loss-p (not (null (getf compatibility-target :detached-runtime-loss-p)))
                  :loss-acknowledged-p (not (null (getf compatibility-target :loss-acknowledged-p)))
                  :loss-acknowledged-at (getf compatibility-target :loss-acknowledged-at)
                  :recovery-note (getf compatibility-target :recovery-note)
                  :control-posture (compatibility-execution-control-posture handle)))))

(defun compatibility-execution-status (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (backend-profile-id (getf compatibility-target :backend-profile-id))
         (control-token (getf compatibility-target :control-token))
         (stored-status (getf handle :status)))
    (cond
      ((member stored-status '(:stopped :revoked :terminated) :test #'eq)
       stored-status)
      (control-token
       (compatibility-backend-status backend-profile-id control-token stored-status))
      (t
       stored-status))))

(defun compatibility-execution-terminal-p (handle)
  (member (compatibility-execution-status handle)
          '(:completed :failed :revoked :terminated :stopped)
          :test #'eq))

(defun compatibility-execution-lifecycle-summary (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (status (compatibility-execution-status handle))
         (backend-profile-id (getf compatibility-target :backend-profile-id))
         (control-token (getf compatibility-target :control-token)))
    (list :status status
          :terminal-p (compatibility-execution-terminal-p handle)
          :control-posture (compatibility-execution-control-posture handle)
          :execution-mode (getf compatibility-target :execution-mode)
          :control-token-present-p (not (null control-token))
          :control-token-live-p (and control-token
                                     (compatibility-backend-token-live-p backend-profile-id
                                                                         control-token))
          :backend-adapter-id (getf compatibility-target :backend-adapter-id)
          :backend-implementation (getf compatibility-target :backend-implementation)
          :bridge-session-id (getf compatibility-target :bridge-session-id)
          :bridge-attached-p (not (null (getf compatibility-target :bridge-attached-p)))
          :registered-at (getf compatibility-target :registered-at)
          :last-observed-status (or (getf compatibility-target :last-observed-status)
                                    status)
          :last-status-change-at (getf compatibility-target :last-status-change-at)
          :last-control-action (getf compatibility-target :last-control-action)
          :last-control-at (getf compatibility-target :last-control-at)
          :detached-runtime-loss-p (not (null (getf compatibility-target :detached-runtime-loss-p)))
          :loss-acknowledged-p (not (null (getf compatibility-target :loss-acknowledged-p)))
          :loss-acknowledged-at (getf compatibility-target :loss-acknowledged-at)
          :recovery-note (getf compatibility-target :recovery-note)
          :relaunch-ready-p (member :relaunch
                                    (getf (compatibility-execution-control-posture handle)
                                          :supported-actions))
          :relaunch-app-id (getf compatibility-target :app-id)
          :relaunch-execution-id (getf compatibility-target :relaunch-execution-id))))

(defun compatibility-display-surface-summary (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (display-surface-kind (getf compatibility-target :display-surface-kind)))
    (when (and compatibility-target
               (not (eq display-surface-kind :headless)))
      (let ((execution-id (execution-handle-execution-id handle))
            (status (compatibility-execution-status handle))
            (control-posture (compatibility-execution-control-posture handle)))
        (list :display-id (format nil "display-~A" execution-id)
              :execution-id execution-id
              :app-id (getf compatibility-target :app-id)
              :title (or (getf compatibility-target :title)
                         (getf compatibility-target :app-id)
                         (format nil "Display ~A" execution-id))
              :display-surface-kind display-surface-kind
              :status status
              :window-state (or (getf compatibility-target :window-state)
                                (if (member status '(:running :in-progress) :test #'eq)
                                    :visible
                                    :closed))
              :source-package-id (getf compatibility-target :source-package-id)
              :bridge-session-id (getf compatibility-target :bridge-session-id)
              :bridge-attached-p (not (null (getf compatibility-target :bridge-attached-p)))
              :control-posture control-posture
              :compatibility (compatibility-execution-summary handle))))))

(defun compatibility-execution-manifest-available-p (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (app-id (getf compatibility-target :app-id)))
    (and (eq (getf compatibility-target :kind) :linux-app)
         app-id
         (find-compatibility-app app-id))))

(defun compatibility-execution-control-posture (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (backend-profile (getf compatibility-target :backend-profile))
         (backend-profile-id (getf compatibility-target :backend-profile-id))
         (control-plane-kind (getf backend-profile :control-plane-kind))
         (control-token (getf compatibility-target :control-token))
         (detached-runtime-loss-p (getf compatibility-target :detached-runtime-loss-p))
         (loss-acknowledged-p (getf compatibility-target :loss-acknowledged-p))
         (token-live-p (compatibility-backend-token-live-p backend-profile-id control-token))
         (terminal-p (compatibility-execution-terminal-p handle))
         (manifest-available-p (compatibility-execution-manifest-available-p handle))
         (supported-actions
           (cond
             ((and terminal-p manifest-available-p)
              '(:relaunch))
             (terminal-p '())
             ((and detached-runtime-loss-p
                   (not loss-acknowledged-p)
                   manifest-available-p)
              '(:acknowledge-loss :relaunch))
             ((and detached-runtime-loss-p
                   (not loss-acknowledged-p))
              '(:acknowledge-loss))
             ((and detached-runtime-loss-p
                   loss-acknowledged-p
                   manifest-available-p)
              '(:relaunch))
             ((and (member control-plane-kind '(:process-token :runtime-token :desktop-session) :test #'eq)
                   token-live-p)
              '(:stop :revoke))
             (t '())))
         (blocked-reason
           (cond
             ((and terminal-p manifest-available-p)
              "Compatibility execution is terminal but can be relaunched from its manifest.")
             (terminal-p
              "Compatibility execution is already terminal.")
             ((and detached-runtime-loss-p
                   loss-acknowledged-p
                   manifest-available-p)
              "Compatibility runtime loss was acknowledged; the app can now be relaunched from its manifest.")
             ((and detached-runtime-loss-p
                   loss-acknowledged-p)
              "Compatibility runtime loss has already been acknowledged.")
             ((and (member control-plane-kind '(:process-token :runtime-token :desktop-session) :test #'eq)
                   (getf compatibility-target :execution-mode)
                   (not token-live-p))
              (if (eq control-plane-kind :desktop-session)
                  "Compatibility execution is no longer attached to an active desktop bridge session."
                  "Compatibility execution is no longer attached to an active runtime control token."))
             ((member control-plane-kind '(:none nil) :test #'eq)
              "Compatibility execution uses a synchronous backend without detachable governed control.")
             (t
              "Compatibility execution does not advertise any governed control actions."))))
    (list :controllable-p (not (null supported-actions))
          :supported-actions supported-actions
          :blocked-reason blocked-reason
          :terminal-p (not (null terminal-p)))))

(defun query-compatibility-execution-detail-service (session execution-id &key environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handle (observe-kernel-handle-status session execution-id active-environment))
         (compatibility-target (execution-handle-target-value handle :compatibility-execution)))
    (unless compatibility-target
      (error "Kernel execution ~A is not a compatibility execution" execution-id))
    (make-service-query-response :compatibility
                                 :detail
                                 (list :execution (compatibility-execution-summary handle)
                                       :inspection (inspect-kernel-execution-handle session handle)
                                       :related (kernel-related-object-summaries session handle)
                                       :lifecycle (compatibility-execution-lifecycle-summary handle))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :compatibility-execution-detail-v1
                                                                  :session session
                                                                  :environment active-environment
                                                                  :runtime-id (execution-handle-target-value handle :runtime-id)))))

(defun query-compatibility-executions-service (session
                                               &key environment kind backend backend-profile-id sandbox-profile app-id)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handles (remove-if-not (lambda (handle)
                                   (let ((compatibility-target (execution-handle-target-value handle :compatibility-execution)))
                                     (and compatibility-target
                                          (or (null kind)
                                              (eq kind (getf compatibility-target :kind)))
                                          (or (null app-id)
                                              (string= app-id
                                                       (getf compatibility-target :app-id)))
                                          (or (null backend)
                                              (eq backend (getf compatibility-target :backend)))
                                          (or (null backend-profile-id)
                                              (eq backend-profile-id
                                                  (getf compatibility-target :backend-profile-id)))
                                          (or (null sandbox-profile)
                                              (eq sandbox-profile
                                                  (getf compatibility-target :sandbox-profile))))))
                                 (mapcar (lambda (handle)
                                           (observe-kernel-handle-status session handle active-environment))
                                         (kernel-execution-registry active-environment))))
         (summaries (mapcar #'compatibility-execution-summary handles)))
    (make-service-query-response :compatibility
                                 :executions
                                 (list :count (length summaries)
                                       :entries summaries
                                       :filters (list :kind kind
                                                      :app-id app-id
                                                      :backend backend
                                                      :backend-profile-id backend-profile-id
                                                      :sandbox-profile sandbox-profile))
                                  :metadata (make-service-metadata :authority :environment
                                                                   :read-model :compatibility-executions-v1
                                                                   :session session
                                                                   :environment active-environment))))

(defun query-compatibility-apps-service (&key app-id session environment)
  (let* ((entries (if app-id
                      (let ((definition (find-compatibility-app app-id
                                                                :session session
                                                                :environment environment)))
                        (and definition
                             (list (compatibility-app-summary definition))))
                      (list-compatibility-apps :session session
                                               :environment environment))))
    (when session
      (let* ((active-environment (ensure-kernel-bound-environment session environment))
             (handles (kernel-execution-registry active-environment)))
        (setf entries
              (mapcar (lambda (entry)
                        (let* ((matching-handles
                                 (remove-if-not
                                  (lambda (handle)
                                    (let ((compatibility-target
                                            (execution-handle-target-value handle :compatibility-execution)))
                                      (string= (or (getf compatibility-target :app-id) "")
                                               (or (getf entry :id) ""))))
                                  handles))
                               (summaries (mapcar #'compatibility-execution-summary matching-handles))
                               (sorted (sort (copy-list summaries)
                                             #'>
                                             :key (lambda (summary)
                                                    (or (getf (getf summary :execution) :recorded-at) 0)))))
                          (append entry
                                  (list :execution-count (length summaries)
                                        :running-count (count :running summaries
                                                              :key (lambda (summary) (getf summary :status))
                                                              :test #'eq)
                                        :recent-executions sorted
                                        :top-execution (first sorted)))))
                      (or entries '())))))
    (make-service-query-response :compatibility
                                 :apps
                                 (list :count (length (or entries '()))
                                       :entries (or entries '())
                                       :selected-app-id app-id)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :compatibility-apps-v1
                                                                 :session session
                                                                 :environment environment))))

(defun query-compatibility-display-surfaces-service (session &key environment app-id display-surface-kind)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (entries
           (remove nil
                   (mapcar (lambda (handle)
                             (let* ((compatibility-target
                                      (execution-handle-target-value handle :compatibility-execution))
                                    (entry (and compatibility-target
                                                (compatibility-display-surface-summary handle))))
                               (when (and entry
                                          (or (null app-id)
                                              (string= app-id (getf entry :app-id)))
                                          (or (null display-surface-kind)
                                              (eq display-surface-kind
                                                  (getf entry :display-surface-kind))))
                                 entry)))
                           (mapcar (lambda (handle)
                                     (observe-kernel-handle-status session handle active-environment))
                                   (kernel-execution-registry active-environment)))))
         (sorted (sort entries #'<
                       :key (lambda (entry)
                              (case (getf entry :window-state)
                                (:visible 0)
                                (:background 1)
                                (otherwise 5))))))
    (make-service-query-response :compatibility
                                 :display-surfaces
                                 (list :count (length sorted)
                                       :top-surface (first sorted)
                                       :entries sorted
                                       :filters (list :app-id app-id
                                                      :display-surface-kind display-surface-kind))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :compatibility-display-surfaces-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun kernel-control-post-state (session handle)
  (let* ((work-item-id (execution-handle-target-value handle :work-item-id))
         (work-item (and work-item-id
                         (find-work-item session work-item-id)))
         (transaction (and work-item
                           (current-work-item-transaction work-item)))
         (recovery
           (and work-item
                (list :work-item-status (work-item-status work-item)
                      :rollback-status (and transaction
                                            (mutation-transaction-rollback-status transaction))
                      :quarantine-status (and transaction
                                              (mutation-transaction-quarantine-status transaction))
                      :rollback-point (work-item-rollback-point work-item)
                      :resume-payload (work-item-resume-payload work-item)
                      :next-action (work-item-next-action work-item)))))
    (list :object-kind (kernel-execution-object-kind handle)
          :target (getf handle :target)
          :inspection (inspect-kernel-execution-handle session handle)
          :related (kernel-related-object-summaries session handle)
          :recovery recovery
          :resolved-via :execution-handle)))

(defun compatibility-execution-control-ready-p (handle action)
  (member action
          (getf (compatibility-execution-control-posture handle) :supported-actions)
          :test #'eq))

(defun compatibility-execution-apply-control (handle action environment)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (backend-profile-id (getf compatibility-target :backend-profile-id))
         (control-token (getf compatibility-target :control-token))
         (result (compatibility-backend-stop backend-profile-id
                                             control-token
                                             :revoke-p (eq action :revoke)))
         (now (get-universal-time))
         (updated-target (copy-list compatibility-target))
         (updated-handle (copy-list handle)))
    (setf (getf updated-target :last-control-action) action
          (getf updated-target :last-control-at) now
          (getf updated-target :last-observed-status) (getf result :status)
          (getf updated-target :last-status-change-at) now
          (getf updated-target :detached-runtime-loss-p) nil
          (getf updated-target :bridge-session-id) (or (getf result :bridge-session-id)
                                                       (getf updated-target :bridge-session-id))
          (getf updated-target :bridge-attached-p) (getf result :bridge-attached-p)
          (getf updated-target :recovery-note) (or (getf result :recovery-note)
                                                   (getf updated-target :recovery-note))
          (getf updated-target :window-state) :closed)
    (setf (getf updated-handle :status) (getf result :status))
    (setf (getf updated-handle :target)
          (kernel-plist-put (copy-list (getf handle :target))
                            :compatibility-execution
                            updated-target))
    (store-kernel-execution-handle updated-handle environment)
    (values updated-handle result)))

(defun compatibility-execution-acknowledge-loss (handle environment &key note)
  (let* ((compatibility-target (copy-list (execution-handle-target-value handle :compatibility-execution)))
         (now (get-universal-time))
         (updated-handle (copy-list handle)))
    (setf (getf compatibility-target :loss-acknowledged-p) t
          (getf compatibility-target :loss-acknowledged-at) now
          (getf compatibility-target :recovery-note) note
          (getf compatibility-target :last-control-action) :acknowledge-loss
          (getf compatibility-target :last-control-at) now)
    (setf (getf updated-handle :target)
          (kernel-plist-put (copy-list (getf handle :target))
                            :compatibility-execution
                            compatibility-target))
    (store-kernel-execution-handle updated-handle environment)
    (values updated-handle
            (list :status :accepted
                  :compatibility-action :acknowledge-loss
                  :loss-acknowledged-p t
                  :loss-acknowledged-at now
                  :recovery-note note))))

(defun compatibility-execution-relaunch-arguments (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (app-id (getf compatibility-target :app-id))
         (definition (and app-id
                          (find-compatibility-app app-id)))
         (stored-argv (copy-list (or (getf compatibility-target :argv) '()))))
    (unless definition
      (error "Compatibility execution ~A cannot be relaunched because its manifest is unavailable."
             (execution-handle-execution-id handle)))
    (let ((prefix (append (list (compatibility-app-definition-executable definition))
                          (copy-list (compatibility-app-definition-default-arguments definition)))))
      (if (and (<= (length prefix) (length stored-argv))
               (equal prefix (subseq stored-argv 0 (length prefix))))
          (subseq stored-argv (length prefix))
          stored-argv))))

(defun compatibility-execution-mark-relaunched (handle environment new-execution-id)
  (let* ((compatibility-target (copy-list (execution-handle-target-value handle :compatibility-execution)))
         (updated-handle (copy-list handle))
         (now (get-universal-time)))
    (setf (getf compatibility-target :last-control-action) :relaunch
          (getf compatibility-target :last-control-at) now
          (getf compatibility-target :relaunch-execution-id) new-execution-id)
    (setf (getf updated-handle :target)
          (kernel-plist-put (copy-list (getf handle :target))
                            :compatibility-execution
                            compatibility-target))
    (store-kernel-execution-handle updated-handle environment)
    updated-handle))

(defun authority-grant-kernel-execution-p (handle)
  (string= (kernel-capability-name (getf handle :capability))
           "authority/grant"))

(defun kernel-control-work-item-requires-note-p (work-item)
  (let ((transaction (and work-item
                          (current-work-item-transaction work-item))))
    (or (and work-item
             (eq (work-item-status work-item) :quarantined))
        (and transaction
             (eq (mutation-transaction-rollback-status transaction) :required)))))

(defun kernel-control-work-item-rollback-ready-p (work-item)
  (let ((transaction (and work-item
                          (current-work-item-transaction work-item))))
    (and work-item
         (work-item-rollback-point work-item)
         (or (eq (work-item-status work-item) :quarantined)
             (and transaction
                  (member (mutation-transaction-rollback-status transaction)
                          '(:required :captured :available)
                          :test #'eq))))))

(defun kernel-control-work-item-cold-validation-ready-p (work-item)
  (and work-item
       (eq (work-item-status work-item) :awaiting-cold-validation)
       (member :cold (work-item-pending-validations work-item) :test #'eq)
       (find :cold
             (work-item-validator-tasks work-item)
             :key #'validator-task-record-kind)))

(defun command-kernel-control-service (session execution-id action
                                        &key authority reason note provider environment status)
  (declare (ignore authority))
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handle (ensure-kernel-handle execution-id active-environment))
         (resolved-handle handle)
         (policy-id (execution-handle-target-value handle :policy-id))
         (turn-id (execution-handle-target-value handle :turn-id))
         (work-item-id (execution-handle-target-value handle :work-item-id))
         (compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (work-item (and work-item-id
                         (find-work-item session work-item-id)))
         (result
           (cond
             ((and (eq action :approve) policy-id)
              (when (authority-grant-kernel-execution-p handle)
                (error "Authority cannot be self-granted through kernel control for ~A" execution-id))
              (service-response-data (command-approve-policy-service session policy-id)))
             ((and (eq action :resume) turn-id)
              (unless provider
                (error "Kernel control resume for ~A requires a provider" execution-id))
             (let ((turn (or (find-turn session turn-id)
                              (error "Unknown turn ~A for kernel execution ~A"
                                     turn-id
                                     execution-id))))
                (list :resume-kind :turn-resume
                      :result (resume-conversation-turn provider
                                                        session
                                                        turn
                                                        :source (or (getf (turn-metadata turn) :source)
                                                                    :say)
                                                        :operator-mode :conversation))))
             ((and (eq action :resume) work-item-id)
              (when (and (kernel-control-work-item-requires-note-p work-item)
                         (not note))
                (error "Kernel control resume for work-item ~A requires :note in the current recovery posture."
                       work-item-id))
              (service-response-data (command-work-item-resume-service session work-item-id :note note)))
             ((and (eq action :quarantine) work-item-id)
              (unless reason
                (error "Kernel control quarantine for work-item ~A requires :reason."
                       work-item-id))
              (service-response-data (command-work-item-quarantine-service session
                                                                          work-item-id
                                                                          reason)))
             ((and (eq action :rollback) work-item-id)
              (unless (kernel-control-work-item-rollback-ready-p work-item)
                (error "Kernel control rollback for work-item ~A is not available in the current recovery posture."
                       work-item-id))
              (unless reason
                (error "Kernel control rollback for work-item ~A requires :reason."
                       work-item-id))
              (service-response-data (command-work-item-rollback-service session
                                                                        work-item-id
                                                                        :reason reason
                                                                        :note note)))
             ((and (eq action :complete-validations) work-item-id)
              (unless (kernel-control-work-item-cold-validation-ready-p work-item)
                (error "Kernel control complete-validations for work-item ~A is not available in the current validation posture."
                       work-item-id))
             (service-response-data (command-work-item-complete-validations-service session
                                                                                    work-item-id
                                                                                    :status (or status :passed))))
             ((and compatibility-target
                   (member action '(:stop :pause :revoke :acknowledge-loss :relaunch) :test #'eq))
              (unless (compatibility-execution-control-ready-p handle action)
                (error "Kernel control ~A for compatibility execution ~A is not available: ~A"
                       action
                       execution-id
                       (getf (compatibility-execution-control-posture handle) :blocked-reason)))
              (multiple-value-bind (updated-handle compatibility-result)
                  (cond
                    ((eq action :acknowledge-loss)
                     (compatibility-execution-acknowledge-loss handle
                                                               active-environment
                                                               :note note))
                    ((eq action :relaunch)
                     (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
                            (app-id (or (getf compatibility-target :app-id)
                                        (error "Compatibility execution ~A has no app manifest id to relaunch."
                                               execution-id)))
                            (arguments (compatibility-execution-relaunch-arguments handle))
                            (relaunch-response
                              (command-invoke-compatibility-app-service session
                                                                        app-id
                                                                        (list :arguments arguments)))
                            (new-execution-id (getf (service-response-metadata relaunch-response)
                                                    :execution-id))
                            (new-handle (ensure-kernel-handle new-execution-id active-environment)))
                       (compatibility-execution-mark-relaunched handle active-environment new-execution-id)
                       (values new-handle
                               (list :status :accepted
                                     :compatibility-action :relaunch
                                     :previous-execution-id execution-id
                                     :new-execution-id new-execution-id
                                     :app-id app-id))))
                    (t
                     (compatibility-execution-apply-control handle action active-environment)))
                (setf resolved-handle updated-handle)
                (list :compatibility-action action
                      :status :accepted
                      :compatibility-result compatibility-result)))
             ((and (eq action :request-approval) work-item-id policy-id)
              (service-response-data (command-request-work-item-approval-service session
                                                                                 work-item-id
                                                                                 policy-id
                                                                                 :reason reason)))
             (t
              (error "Unsupported kernel control action ~A for ~A" action execution-id))))
         (recorded-handle (progn
                            (setf resolved-handle
                                  (kernel-record-control-event resolved-handle
                                                               action
                                                               :status (getf resolved-handle :status)
                                                               :reason reason
                                                               :note note
                                                               :result (getf result :status)))
                            (store-kernel-execution-handle resolved-handle active-environment)))
         (post-state (kernel-control-post-state session recorded-handle)))
    (make-service-command-response :kernel
                                   :control
                                   (list :execution recorded-handle
                                         :action action
                                         :result result
                                         :post-state post-state
                                         :resolved-via :execution-handle)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :kernel-control-v1
                                                                    :session session
                                                                    :environment active-environment
                                                                    :policy-id (execution-handle-target-value recorded-handle :policy-id)
                                                                    :thread-id (execution-handle-target-value recorded-handle :thread-id)
                                                                    :turn-id (execution-handle-target-value recorded-handle :turn-id)
                                                                    :work-item-id (execution-handle-target-value recorded-handle :work-item-id)
                                                                    :incident-id (execution-handle-target-value recorded-handle :incident-id)
                                                                    :runtime-id (execution-handle-target-value recorded-handle :runtime-id)))))

(defun kernel-invoke (session intention capability &key authority context constraints provider options payload environment)
  (service-response-data
   (command-kernel-invoke-service session
                                  intention
                                  capability
                                  :authority authority
                                  :context context
                                  :constraints constraints
                                  :provider provider
                                  :options options
                                  :payload payload
                                  :environment environment)))

(defun kernel-inspect (session object-id &key environment)
  (service-response-data
   (query-kernel-inspect-service session object-id :environment environment)))

(defun kernel-control (session execution-id action &key authority reason note provider environment status)
  (service-response-data
   (command-kernel-control-service session
                                   execution-id
                                   action
                                   :authority authority
                                   :reason reason
                                   :note note
                                   :provider provider
                                   :environment environment
                                   :status status)))
