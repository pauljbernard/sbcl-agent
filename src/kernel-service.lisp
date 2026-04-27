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

(defun kernel-capability-policy-id (capability payload response)
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
      ((search "tool/" normalized :test #'char-equal)
       :tool-execution)
      ((member normalized '("conversation/say" "conversation/ask") :test #'string=)
       :conversation)
      (t :execution))))

(defun kernel-governance-mutation-sensitive-p (mutation-class)
  (member mutation-class
          '(:runtime-mutation :runtime-reload :runtime-package-switch :workspace-mutation :tool-execution)
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
  (let* ((policy-id (kernel-capability-policy-id capability payload response))
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
                                     (eq mutation-class :approval-request))))
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
               (not (eq (getf preflight :mutation-class) :approval-request)))
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
  (declare (ignore authority constraints))
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
       (error "Compatibility kernel support for ~A is not implemented yet" capability))
      (t
       (error "Unsupported kernel capability ~A" capability)))))
    (annotate-kernel-invoke-response response session capability payload context preflight)))

(defun kernel-execution-object-kind (handle)
  (cond
    ((execution-handle-target-value handle :compatibility-execution) :compatibility-execution)
    ((execution-handle-target-value handle :workflow-record-id) :workflow-record)
    ((execution-handle-target-value handle :incident-id) :incident)
    ((execution-handle-target-value handle :work-item-id) :work-item)
    ((execution-handle-target-value handle :turn-id) :turn)
    ((execution-handle-target-value handle :runtime-id) :runtime)
    (t :execution)))

(defun kernel-related-object-summaries (session handle)
  (let* ((thread-id (execution-handle-target-value handle :thread-id))
         (turn-id (execution-handle-target-value handle :turn-id))
         (work-item-id (execution-handle-target-value handle :work-item-id))
         (workflow-record-id (execution-handle-target-value handle :workflow-record-id))
         (incident-id (execution-handle-target-value handle :incident-id))
         (compatibility-execution (execution-handle-target-value handle :compatibility-execution))
         (runtime-id (execution-handle-target-value handle :runtime-id))
         (thread (and thread-id (find-thread session thread-id)))
         (turn (and turn-id (find-turn session turn-id)))
         (work-item (and work-item-id (find-work-item session work-item-id)))
         (workflow-record
           (or (and workflow-record-id
                    (find-workflow-record session workflow-record-id))
               (and work-item
                    (work-item-workflow-record session work-item))))
         (incident (and incident-id (find-incident session incident-id))))
    (list :thread (and thread (thread-record-summary thread))
          :turn (and turn (turn-record-summary turn))
          :work-item (and work-item (work-item-summary work-item))
          :workflow-record (and workflow-record (workflow-record-summary workflow-record))
          :incident (and incident (incident-record-summary incident))
          :compatibility-execution compatibility-execution
          :runtime (and runtime-id
                        (service-response-data (query-runtime-summary-service session))))))

(defun inspect-kernel-execution-handle (session handle)
  (let ((turn-id (execution-handle-target-value handle :turn-id))
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
      (turn-id
       (service-response-data (query-conversation-turn-detail-service session turn-id)))
      (work-item-id
       (service-response-data (query-work-item-detail-service session work-item-id)))
      (incident-id
       (service-response-data (query-incident-detail-service session incident-id)))
      (runtime-id
       (service-response-data (query-runtime-summary-service session)))
      (t
       handle))))

(defun query-kernel-inspect-service (session object-id &key environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handle (ensure-kernel-handle object-id active-environment))
         (object-kind (kernel-execution-object-kind handle))
         (inspection (inspect-kernel-execution-handle session handle))
         (related (kernel-related-object-summaries session handle)))
    (make-service-query-response :kernel
                                 :inspect
                                 (list :execution handle
                                       :object-kind object-kind
                                       :target (getf handle :target)
                                       :inspection inspection
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
         (handle (kernel-find-execution execution-id active-environment)))
    (when handle
      (execution-surface-summary session handle active-environment))))

(defun primary-execution-surface-summary (session execution-handles &key environment)
  (let ((execution-id (and (consp execution-handles)
                           (getf (first execution-handles) :execution-id))))
    (when execution-id
      (query-execution-surface-by-id session execution-id :environment environment))))

(defun query-execution-surfaces-service (session &key environment surface-kind)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handles (kernel-execution-registry active-environment))
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
                  :backend (getf compatibility-target :backend)
                  :sandbox-profile (getf compatibility-target :sandbox-profile)
                  :filesystem-scope (getf compatibility-target :filesystem-scope)
                  :network-enabled-p (getf compatibility-target :network-enabled-p)
                  :workspace-write-p (getf compatibility-target :workspace-write-p)
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
         (control-token (getf compatibility-target :control-token))
         (stored-status (getf handle :status)))
    (cond
      ((member stored-status '(:stopped :revoked :terminated) :test #'eq)
       stored-status)
      (control-token
       (compatibility-process-status control-token))
      (t
       stored-status))))

(defun compatibility-execution-terminal-p (handle)
  (member (compatibility-execution-status handle)
          '(:completed :failed :revoked :terminated :stopped)
          :test #'eq))

(defun compatibility-execution-lifecycle-summary (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (status (compatibility-execution-status handle))
         (control-token (getf compatibility-target :control-token)))
    (list :status status
          :terminal-p (compatibility-execution-terminal-p handle)
          :control-posture (compatibility-execution-control-posture handle)
          :execution-mode (getf compatibility-target :execution-mode)
          :control-token-present-p (not (null control-token))
          :control-token-live-p (and control-token
                                     (compatibility-process-token-live-p control-token))
          :registered-at (getf compatibility-target :registered-at)
          :last-observed-status (or (getf compatibility-target :last-observed-status)
                                    status)
          :last-status-change-at (getf compatibility-target :last-status-change-at)
          :last-control-action (getf compatibility-target :last-control-action)
          :last-control-at (getf compatibility-target :last-control-at)
          :detached-runtime-loss-p (not (null (getf compatibility-target :detached-runtime-loss-p)))
          :loss-acknowledged-p (not (null (getf compatibility-target :loss-acknowledged-p)))
          :loss-acknowledged-at (getf compatibility-target :loss-acknowledged-at)
          :recovery-note (getf compatibility-target :recovery-note))))

(defun compatibility-execution-control-posture (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (backend (getf compatibility-target :backend))
         (kind (getf compatibility-target :kind))
         (control-token (getf compatibility-target :control-token))
         (detached-runtime-loss-p (getf compatibility-target :detached-runtime-loss-p))
         (loss-acknowledged-p (getf compatibility-target :loss-acknowledged-p))
         (token-live-p (and control-token
                            (compatibility-process-token-live-p control-token)))
         (terminal-p (compatibility-execution-terminal-p handle))
         (supported-actions
           (cond
             (terminal-p '())
             ((and detached-runtime-loss-p
                   (not loss-acknowledged-p))
              '(:acknowledge-loss))
             ((and (eq kind :host-process)
                   (eq backend :sbcl-sandbox-worker)
                   token-live-p)
              '(:stop :revoke))
             (t '())))
         (blocked-reason
           (cond
             (terminal-p
              "Compatibility execution is already terminal.")
             ((and detached-runtime-loss-p
                   loss-acknowledged-p)
              "Compatibility runtime loss has already been acknowledged.")
             ((and (eq kind :host-process)
                   (eq backend :sbcl-sandbox-worker)
                   (getf compatibility-target :execution-mode)
                   (not token-live-p))
              "Compatibility execution is no longer attached to an active runtime control token.")
             ((and (eq kind :host-process)
                   (eq backend :sbcl-sandbox-worker))
              "Synchronous host-process compatibility executions are not yet detachable or revocable.")
             (t
              "Compatibility execution does not advertise any governed control actions."))))
    (list :controllable-p (not (null supported-actions))
          :supported-actions supported-actions
          :blocked-reason blocked-reason
          :terminal-p (not (null terminal-p)))))

(defun query-compatibility-execution-detail-service (session execution-id &key environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handle (ensure-kernel-handle execution-id active-environment))
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

(defun query-compatibility-executions-service (session &key environment kind backend sandbox-profile)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handles (remove-if-not (lambda (handle)
                                   (let ((compatibility-target (execution-handle-target-value handle :compatibility-execution)))
                                     (and compatibility-target
                                          (or (null kind)
                                              (eq kind (getf compatibility-target :kind)))
                                          (or (null backend)
                                              (eq backend (getf compatibility-target :backend)))
                                          (or (null sandbox-profile)
                                              (eq sandbox-profile
                                                  (getf compatibility-target :sandbox-profile))))))
                                 (kernel-execution-registry active-environment)))
         (summaries (mapcar #'compatibility-execution-summary handles)))
    (make-service-query-response :compatibility
                                 :executions
                                 (list :count (length summaries)
                                       :entries summaries
                                       :filters (list :kind kind
                                                      :backend backend
                                                      :sandbox-profile sandbox-profile))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :compatibility-executions-v1
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
         (control-token (getf compatibility-target :control-token))
         (result (compatibility-process-stop control-token :revoke-p (eq action :revoke)))
         (now (get-universal-time))
         (updated-target (copy-list compatibility-target))
         (updated-handle (copy-list handle)))
    (setf (getf updated-target :last-control-action) action
          (getf updated-target :last-control-at) now
          (getf updated-target :last-observed-status) (getf result :status)
          (getf updated-target :last-status-change-at) now
          (getf updated-target :detached-runtime-loss-p) nil)
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
                   (member action '(:stop :pause :revoke :acknowledge-loss) :test #'eq))
              (unless (compatibility-execution-control-ready-p handle action)
                (error "Kernel control ~A for compatibility execution ~A is not available: ~A"
                       action
                       execution-id
                       (getf (compatibility-execution-control-posture handle) :blocked-reason)))
              (multiple-value-bind (updated-handle compatibility-result)
                  (if (eq action :acknowledge-loss)
                      (compatibility-execution-acknowledge-loss handle
                                                                active-environment
                                                                :note note)
                      (compatibility-execution-apply-control handle action active-environment))
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
         (post-state (kernel-control-post-state session resolved-handle)))
    (make-service-command-response :kernel
                                   :control
                                   (list :execution resolved-handle
                                         :action action
                                         :result result
                                         :post-state post-state
                                         :resolved-via :execution-handle)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :kernel-control-v1
                                                                    :session session
                                                                    :environment active-environment
                                                                    :policy-id (execution-handle-target-value resolved-handle :policy-id)
                                                                    :thread-id (execution-handle-target-value resolved-handle :thread-id)
                                                                    :turn-id (execution-handle-target-value resolved-handle :turn-id)
                                                                    :work-item-id (execution-handle-target-value resolved-handle :work-item-id)
                                                                    :incident-id (execution-handle-target-value resolved-handle :incident-id)
                                                                    :runtime-id (execution-handle-target-value resolved-handle :runtime-id)))))

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
