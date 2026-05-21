(in-package #:sbcl-agent)

(defparameter +execution-doctrine-rules+
  '("Everything that happens is an execution."
    "Every execution carries intention, capability, authority, state, and trace."
    "Every execution can be inspected."
    "Every execution can be controlled."))

(defun execution-control-action-mutation-p (action)
  (member action
          '(:approve :resume :quarantine :rollback :complete-validations
            :stop :pause :revoke :acknowledge-loss :relaunch :request-approval)
          :test #'eq))

(defun call-with-execution-control-policy (mode thunk &key lock-key)
  (call-with-concurrency-core-policy mode thunk :lock-key lock-key))

(defun call-execution-read-facade (thunk &key (lock-key :execution-read))
  (call-with-execution-control-policy :concurrent-read thunk :lock-key lock-key))

(defun call-execution-control-facade (action execution-id thunk)
  (call-with-execution-control-policy
   (if (execution-control-action-mutation-p action)
       :serialized-write
       :concurrent-read)
   thunk
   :lock-key (list :execution-control action execution-id)))

(defun execution-object-kind (handle)
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

(defun execution-related-object-summaries (session handle)
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

(defun compatibility-execution-manifest-available-p (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (app-id (getf compatibility-target :app-id)))
    (and (eq (getf compatibility-target :kind) :linux-app)
         app-id
         (find-compatibility-app app-id))))

(defun compatibility-execution-terminal-p (handle)
  (member (getf handle :status) '(:completed :failed :stopped :terminated :revoked)
          :test #'eq))

(defun compatibility-execution-status (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (backend-profile-id (getf compatibility-target :backend-profile-id))
         (control-token (getf compatibility-target :control-token))
         (stored-status (or (getf compatibility-target :last-observed-status)
                            (getf compatibility-target :status)
                            (getf handle :status))))
    (or (and backend-profile-id
             control-token
             (ignore-errors
               (getf (compatibility-backend-status backend-profile-id control-token stored-status)
                     :status)))
        stored-status)))

(defun compatibility-execution-control-posture (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (backend-profile (getf compatibility-target :backend-profile))
         (backend-profile-id (getf compatibility-target :backend-profile-id))
         (control-plane-kind (getf backend-profile :control-plane-kind))
         (control-token (getf compatibility-target :control-token))
         (detached-runtime-loss-p (getf compatibility-target :detached-runtime-loss-p))
         (loss-acknowledged-p (getf compatibility-target :loss-acknowledged-p))
         (token-live-p (and backend-profile-id
                            control-token
                            (compatibility-backend-token-live-p backend-profile-id control-token)))
         (terminal-p (compatibility-execution-terminal-p handle))
         (manifest-available-p (compatibility-execution-manifest-available-p handle))
         (supported-actions
           (cond
             ((and terminal-p manifest-available-p) '(:relaunch))
             (terminal-p '())
             ((and detached-runtime-loss-p (not loss-acknowledged-p) manifest-available-p)
              '(:acknowledge-loss :relaunch))
             ((and detached-runtime-loss-p (not loss-acknowledged-p))
              '(:acknowledge-loss))
             ((and detached-runtime-loss-p loss-acknowledged-p manifest-available-p)
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
             ((and detached-runtime-loss-p loss-acknowledged-p manifest-available-p)
              "Compatibility runtime loss was acknowledged; the app can now be relaunched from its manifest.")
             ((and detached-runtime-loss-p loss-acknowledged-p)
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

(defun inspect-execution-handle (session handle)
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
       (append (plist-without-key
                (plist-without-key (copy-list compatibility-execution) :status)
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

(defun ensure-execution-handle (execution-or-id &optional environment)
  (cond
    ((and (listp execution-or-id) (getf execution-or-id :execution-id))
     execution-or-id)
    ((stringp execution-or-id)
     (or (find-execution-handle execution-or-id environment)
         (error "Unknown execution ~A" execution-or-id)))
    (t
     (error "Expected an execution handle or execution id, got ~S" execution-or-id))))

(defun execution-observed-status (session handle)
  (case (execution-object-kind handle)
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

(defun observe-execution-handle-status (session execution-or-id &optional environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (handle (ensure-execution-handle execution-or-id active-environment))
         (observed-status (execution-observed-status session handle)))
    (record-execution-observed-status handle
                                      observed-status
                                      active-environment
                                      :result :observation)))

(defun execution-forensics-summary (handle)
  (list :recorded-at (getf handle :recorded-at)
        :last-observed-status (getf handle :last-observed-status)
        :last-status-change-at (getf handle :last-status-change-at)
        :last-control-action (getf handle :last-control-action)
        :last-control-at (getf handle :last-control-at)
        :history-count (+ (length (or (getf handle :lifecycle-history) '()))
                          (length (or (getf handle :control-history) '())))
        :lifecycle-history (copy-tree (or (getf handle :lifecycle-history) '()))
        :control-history (copy-tree (or (getf handle :control-history) '()))))

(defun execution-surface-kind (handle)
  (case (execution-object-kind handle)
    (:compatibility-execution "compatibility")
    (:work-item "work-item")
    (:workflow-record "workflow")
    (:incident "incident")
    (:turn "turn")
    (:thread "thread")
    (:runtime "runtime")
    (otherwise "execution")))

(defun execution-surface-title (handle related)
  (or (let ((compatibility-target (execution-handle-target-value handle :compatibility-execution)))
        (and compatibility-target
             (or (getf compatibility-target :title)
                 (getf compatibility-target :app-id))))
      (getf (getf related :work-item) :title)
      (getf (getf related :workflow-record) :title)
      (getf (getf related :incident) :summary)
      (getf (getf related :thread) :title)
      (getf (getf related :turn) :summary)
      (case (execution-object-kind handle)
        (:compatibility-execution "Compatibility execution")
        (:work-item "Work item")
        (:workflow-record "Workflow record")
        (:incident "Incident")
        (:turn "Conversation turn")
        (:runtime "Live runtime")
        (otherwise nil))
      (format nil "Execution ~A" (execution-handle-execution-id handle))))

(defun execution-surface-status (handle related)
  (case (execution-object-kind handle)
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
  (let* ((related (execution-related-object-summaries session handle))
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
          :capability (capability-name-string (getf handle :capability))
          :object-kind (string-downcase (symbol-name (execution-object-kind handle)))
          :thread-id (execution-handle-target-value handle :thread-id)
          :turn-id (execution-handle-target-value handle :turn-id)
          :work-item-id (execution-handle-target-value handle :work-item-id)
          :workflow-record-id (execution-handle-target-value handle :workflow-record-id)
          :incident-id (execution-handle-target-value handle :incident-id)
          :runtime-id (execution-handle-target-value handle :runtime-id)
          :primary-execution-handle (execution-handle-summary handle)
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
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (handle (and (find-execution-handle execution-id active-environment)
                      (observe-execution-handle-status session execution-id active-environment))))
    (when handle
      (execution-surface-summary session handle active-environment))))

(defun primary-execution-surface-summary (session execution-handles &key environment)
  (let ((execution-id (and (consp execution-handles)
                           (getf (first execution-handles) :execution-id))))
    (when execution-id
      (query-execution-surface-by-id session execution-id :environment environment))))

(defun query-execution-surfaces-service (session &key environment surface-kind)
  (call-execution-read-facade
   (lambda ()
     (let* ((active-environment (ensure-execution-bound-environment session environment))
            (handles (mapcar (lambda (handle)
                               (observe-execution-handle-status session handle active-environment))
                             (execution-registry active-environment)))
            (surfaces (remove nil
                              (mapcar (lambda (handle)
                                        (let ((surface (execution-surface-summary
                                                        session handle active-environment)))
                                          (if (or (null surface-kind)
                                                  (string= surface-kind
                                                           (getf surface :surface-kind)))
                                              surface
                                              nil)))
                                      handles)))
            (sorted (sort surfaces #'<
                          :key (lambda (surface)
                                 (or (getf surface :attention-rank) 99)))))
       (make-service-query-response :execution
                                    :surfaces
                                    (list :count (length sorted)
                                          :top-surface (first sorted)
                                          :items sorted
                                          :filter (list :surface-kind surface-kind))
                                    :metadata (make-service-metadata :authority :environment
                                                                     :read-model :execution-surfaces-v1
                                                                     :session session
                                                                     :environment active-environment))))))

(defun query-execution-detail-service (session execution-id &key environment)
  (call-execution-read-facade
   (lambda ()
     (let* ((active-environment (ensure-execution-bound-environment session environment))
            (handle (observe-execution-handle-status session execution-id active-environment))
            (object-kind (execution-object-kind handle))
            (inspection (inspect-execution-handle session handle))
            (related (execution-related-object-summaries session handle))
            (forensics (execution-forensics-summary handle)))
       (make-service-query-response :execution
                                    :detail
                                    (list :execution handle
                                          :object-kind object-kind
                                          :target (getf handle :target)
                                          :inspection inspection
                                          :forensics forensics
                                          :related related
                                          :resolved-via :execution-handle
                                          :doctrine +execution-doctrine-rules+)
                                    :metadata (make-service-metadata :authority :environment
                                                                     :read-model :execution-detail-v1
                                                                     :session session
                                                                     :environment active-environment
                                                                     :runtime-id (execution-handle-target-value handle :runtime-id)
                                                                     :thread-id (execution-handle-target-value handle :thread-id)
                                                                     :turn-id (execution-handle-target-value handle :turn-id)
                                                                     :work-item-id (execution-handle-target-value handle :work-item-id)
                                                                     :incident-id (execution-handle-target-value handle :incident-id)))))))

(defun compatibility-execution-summary (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (summary (execution-handle-summary handle)))
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
                  :argv (copy-list (or (getf compatibility-target :argv) '()))
                  :environment-id (getf compatibility-target :environment-id)
                  :runtime-id (getf compatibility-target :runtime-id)
                  :detached-runtime-loss-p (not (null (getf compatibility-target :detached-runtime-loss-p)))
                  :loss-acknowledged-p (not (null (getf compatibility-target :loss-acknowledged-p)))
                  :loss-acknowledged-at (getf compatibility-target :loss-acknowledged-at)
                  :recovery-note (getf compatibility-target :recovery-note)
                  :control-posture (compatibility-execution-control-posture handle)))))

(defun compatibility-execution-lifecycle-summary (handle)
  (let* ((compatibility-target (execution-handle-target-value handle :compatibility-execution))
         (status (compatibility-execution-status handle))
         (backend-profile-id (getf compatibility-target :backend-profile-id))
         (control-token (getf compatibility-target :control-token)))
    (list :status status
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

(defun query-compatibility-execution-detail-service (session execution-id &key environment)
  (call-execution-read-facade
   (lambda ()
     (let* ((active-environment (ensure-execution-bound-environment session environment))
            (handle (observe-execution-handle-status session execution-id active-environment))
            (compatibility-target (execution-handle-target-value handle :compatibility-execution)))
       (unless compatibility-target
         (error "Execution ~A is not a compatibility execution" execution-id))
       (make-service-query-response :compatibility
                                    :detail
                                    (list :execution (compatibility-execution-summary handle)
                                          :inspection (inspect-execution-handle session handle)
                                          :related (execution-related-object-summaries session handle)
                                          :lifecycle (compatibility-execution-lifecycle-summary handle))
                                    :metadata (make-service-metadata :authority :environment
                                                                     :read-model :compatibility-execution-detail-v1
                                                                     :session session
                                                                     :environment active-environment
                                                                     :runtime-id (execution-handle-target-value handle :runtime-id)))))))

(defun query-compatibility-executions-service (session
                                               &key environment kind backend backend-profile-id sandbox-profile app-id)
  (call-execution-read-facade
   (lambda ()
     (let* ((active-environment (ensure-execution-bound-environment session environment))
            (handles (remove-if-not
                      (lambda (handle)
                        (let ((compatibility-target (execution-handle-target-value handle :compatibility-execution)))
                          (and compatibility-target
                               (or (null kind)
                                   (eq kind (getf compatibility-target :kind)))
                               (or (null app-id)
                                   (string= app-id (getf compatibility-target :app-id)))
                               (or (null backend)
                                   (eq backend (getf compatibility-target :backend)))
                               (or (null backend-profile-id)
                                   (eq backend-profile-id
                                       (getf compatibility-target :backend-profile-id)))
                               (or (null sandbox-profile)
                                   (eq sandbox-profile
                                       (getf compatibility-target :sandbox-profile))))))
                      (mapcar (lambda (handle)
                                (observe-execution-handle-status session handle active-environment))
                              (execution-registry active-environment))))
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
                                                                     :environment active-environment))))))

(defun query-compatibility-apps-service (&key app-id session environment)
  (call-execution-read-facade
   (lambda ()
     (let* ((entries (if app-id
                         (let ((definition (find-compatibility-app app-id
                                                                   :session session
                                                                   :environment environment)))
                           (and definition
                                (list (compatibility-app-summary definition))))
                         (list-compatibility-apps :session session
                                                  :environment environment))))
       (when session
         (let* ((active-environment (ensure-execution-bound-environment session environment))
                (handles (execution-registry active-environment)))
           (setf entries
                 (mapcar (lambda (entry)
                           (let* ((matching-handles
                                    (remove-if-not
                                     (lambda (handle)
                                       (let ((compatibility-target
                                               (execution-handle-target-value
                                                handle :compatibility-execution)))
                                         (string= (or (getf compatibility-target :app-id) "")
                                                  (or (getf entry :id) ""))))
                                     handles))
                                  (summaries (mapcar #'compatibility-execution-summary
                                                     matching-handles))
                                  (sorted (sort (copy-list summaries)
                                                #'>
                                                :key (lambda (summary)
                                                       (or (getf (getf summary :execution)
                                                                 :recorded-at)
                                                           0)))))
                             (append entry
                                     (list :execution-count (length summaries)
                                           :running-count (count :running summaries
                                                                 :key (lambda (summary)
                                                                        (getf summary :status))
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
                                                                     :environment environment))))))

(defun query-compatibility-display-surfaces-service (session &key environment app-id display-surface-kind)
  (call-execution-read-facade
   (lambda ()
     (let* ((active-environment (ensure-execution-bound-environment session environment))
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
                                        (observe-execution-handle-status session handle active-environment))
                                      (execution-registry active-environment)))))
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
                                                                     :environment active-environment))))))

(defun execution-control-post-state (session handle)
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
    (list :object-kind (execution-object-kind handle)
          :target (getf handle :target)
          :inspection (inspect-execution-handle session handle)
          :related (execution-related-object-summaries session handle)
          :recovery recovery
          :resolved-via :execution-handle)))

(defun execution-control-work-item-requires-note-p (work-item)
  (let ((transaction (and work-item
                          (current-work-item-transaction work-item))))
    (or (and work-item
             (eq (work-item-status work-item) :quarantined))
        (and transaction
             (eq (mutation-transaction-rollback-status transaction) :required)))))

(defun execution-control-work-item-rollback-ready-p (work-item)
  (let ((transaction (and work-item
                          (current-work-item-transaction work-item))))
    (and work-item
         (work-item-rollback-point work-item)
         (or (eq (work-item-status work-item) :quarantined)
             (and transaction
                  (member (mutation-transaction-rollback-status transaction)
                          '(:required :captured :available)
                          :test #'eq))))))

(defun execution-control-work-item-cold-validation-ready-p (work-item)
  (and work-item
       (eq (work-item-status work-item) :awaiting-cold-validation)
       (member :cold (work-item-pending-validations work-item) :test #'eq)
       (find :cold
             (work-item-validator-tasks work-item)
             :key #'validator-task-record-kind)))

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
          (plist-put (copy-list (getf handle :target))
                     :compatibility-execution
                     updated-target))
    (store-execution-handle updated-handle environment)
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
          (plist-put (copy-list (getf handle :target))
                     :compatibility-execution
                     compatibility-target))
    (store-execution-handle updated-handle environment)
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
          (plist-put (copy-list (getf handle :target))
                     :compatibility-execution
                     compatibility-target))
    (store-execution-handle updated-handle environment)
    updated-handle))

(defun authority-grant-execution-p (handle)
  (string= (capability-name-string (getf handle :capability))
           "authority/grant"))

(defun command-execution-control-service (session execution-id action
                                          &key authority reason note provider environment status)
  (declare (ignore authority))
  (call-execution-control-facade
   action execution-id
   (lambda ()
     (let* ((active-environment (ensure-execution-bound-environment session environment))
            (handle (ensure-execution-handle execution-id active-environment))
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
                 (when (authority-grant-execution-p handle)
                   (error "Authority cannot be self-granted through execution control for ~A" execution-id))
                 (service-response-data (command-approve-policy-service session policy-id)))
                ((and (eq action :resume) turn-id)
                 (unless provider
                   (error "Execution control resume for ~A requires a provider" execution-id))
                 (let ((turn (or (find-turn session turn-id)
                                 (error "Unknown turn ~A for execution ~A" turn-id execution-id))))
                   (list :resume-kind :turn-resume
                         :result (resume-conversation-turn provider
                                                           session
                                                           turn
                                                           :source (or (getf (turn-metadata turn) :source) :say)
                                                           :operator-mode :conversation))))
                ((and (eq action :resume) work-item-id)
                 (when (and (execution-control-work-item-requires-note-p work-item)
                            (not note))
                   (error "Execution control resume for work-item ~A requires :note." work-item-id))
                 (service-response-data (command-work-item-resume-service session work-item-id :note note)))
                ((and (eq action :quarantine) work-item-id)
                 (unless reason
                   (error "Execution control quarantine for work-item ~A requires :reason." work-item-id))
                 (service-response-data (command-work-item-quarantine-service session work-item-id reason)))
                ((and (eq action :rollback) work-item-id)
                 (unless (execution-control-work-item-rollback-ready-p work-item)
                   (error "Execution control rollback for work-item ~A is not available." work-item-id))
                 (unless reason
                   (error "Execution control rollback for work-item ~A requires :reason." work-item-id))
                 (service-response-data
                  (command-work-item-rollback-service session work-item-id :reason reason :note note)))
                ((and (eq action :complete-validations) work-item-id)
                 (unless (execution-control-work-item-cold-validation-ready-p work-item)
                   (error "Execution control complete-validations for work-item ~A is not available."
                          work-item-id))
                 (service-response-data
                  (command-work-item-complete-validations-service session work-item-id
                                                                  :status (or status :passed))))
                ((and compatibility-target
                      (member action '(:stop :pause :revoke :acknowledge-loss :relaunch) :test #'eq))
                 (unless (compatibility-execution-control-ready-p handle action)
                   (error "Execution control ~A for compatibility execution ~A is not available: ~A"
                          action execution-id
                          (getf (compatibility-execution-control-posture handle) :blocked-reason)))
                 (multiple-value-bind (updated-handle compatibility-result)
                     (cond
                       ((eq action :acknowledge-loss)
                        (compatibility-execution-acknowledge-loss handle active-environment :note note))
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
                               (relaunch-session
                                 (or (getf (service-response-metadata relaunch-response) :session)
                                     (let ((data (service-response-data relaunch-response)))
                                       (and (plist-shaped-p data)
                                            (typep (getf data :session) 'agent-session)
                                            (getf data :session)))
                                     session))
                               (relaunch-environment
                                 (or (getf (service-response-metadata relaunch-response) :environment)
                                     (and relaunch-session (session-bound-environment relaunch-session))
                                     active-environment))
                               (new-execution-id (getf (service-response-metadata relaunch-response) :execution-id))
                               (new-handle (ensure-execution-handle new-execution-id relaunch-environment)))
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
                 (service-response-data
                  (command-request-work-item-approval-service session work-item-id policy-id :reason reason)))
                (t
                 (error "Unsupported execution control action ~A for ~A" action execution-id))))
            (recorded-handle
              (progn
                (setf resolved-handle
                      (record-execution-control-event resolved-handle
                                                      action
                                                      :status (getf resolved-handle :status)
                                                      :reason reason
                                                      :note note
                                                      :result (getf result :status)))
                (store-execution-handle resolved-handle active-environment)))
            (post-state (execution-control-post-state session recorded-handle)))
       (make-service-command-response :execution
                                      :control
                                      (list :execution recorded-handle
                                            :action action
                                            :result result
                                            :post-state post-state
                                            :resolved-via :execution-handle)
                                      :metadata (make-service-metadata :authority :environment
                                                                       :command-model :execution-control-v1
                                                                       :session session
                                                                       :environment active-environment
                                                                       :policy-id (execution-handle-target-value recorded-handle :policy-id)
                                                                       :thread-id (execution-handle-target-value recorded-handle :thread-id)
                                                                       :turn-id (execution-handle-target-value recorded-handle :turn-id)
                                                                       :work-item-id (execution-handle-target-value recorded-handle :work-item-id)
                                                                       :incident-id (execution-handle-target-value recorded-handle :incident-id)
                                                                       :runtime-id (execution-handle-target-value recorded-handle :runtime-id)))))))
