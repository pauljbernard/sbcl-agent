(in-package #:sbcl-agent)

(defun actorize-shell-command-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let ((metadata (copy-list (or (getf response :metadata) '())))
            (updated-data (and (keyword-plist-p (getf response :data))
                               (copy-list (getf response :data)))))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when updated-data
          (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                (getf response :data) updated-data))
        response)
      response))

(defun make-shell-control-request (session action capability &key payload metadata)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :shell
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :shell-desktop-control-v1)
                     metadata)))

(defun call-with-shell-actor (session request thunk capability action &key metadata)
  (let ((actor-address (make-standard-actor-address :shell
                                                    :scope (agent-session-id session))))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-shell-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :environment
               :target :shell
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata metadata))))

(defun shell-focus-object-id (session &optional environment)
  (let ((focus-object-id (agent-session-shell-focus-object-id session)))
    (when focus-object-id
      (let ((active-environment (service-active-environment :session session
                                                            :environment environment
                                                            :ensure-p nil
                                                            :bind-session-p nil)))
        (when (and active-environment
                   (ignore-errors
                     (find-execution-handle focus-object-id active-environment)))
          focus-object-id)))))

(defun set-shell-focus-object-id (session object-id)
  (setf (agent-session-shell-focus-object-id session) object-id)
  object-id)

(defun maybe-set-shell-focus-object-id (session object-id)
  (when object-id
    (set-shell-focus-object-id session object-id)))

(defun valid-shell-desktop-panel-id-p (panel-id)
  (member panel-id '(:workspace :display :governance :object-browser :inspector) :test #'eq))

(defun shell-active-panel-id (session)
  (let ((panel-id (agent-session-shell-active-panel-id session)))
    (and (valid-shell-desktop-panel-id-p panel-id)
         panel-id)))

(defun set-shell-active-panel-id (session panel-id)
  (unless (valid-shell-desktop-panel-id-p panel-id)
    (error "Unknown shell desktop panel ~S" panel-id))
  (setf (agent-session-shell-active-panel-id session) panel-id)
  panel-id)

(defun shell-object-reference-title (reference)
  (or (getf reference :title)
      (getf (getf reference :execution-surface) :title)
      (let ((id (or (getf reference :id)
                    (getf reference :execution-id))))
        (and id (format nil "Object ~A" id)))))

(defun shell-surface-execution-id (surface)
  (and surface
       (or (getf surface :execution-id)
           (getf (getf surface :primary-execution-handle) :execution-id))))

(defun shell-object-reference-execution-id (reference)
  (or (shell-surface-execution-id reference)
      (shell-surface-execution-id (getf reference :execution-surface))))

(defun shell-governance-queue-item (queue-kind surface)
  (when surface
    (list :queue-kind queue-kind
          :surface surface
          :attention-rank (or (getf surface :attention-rank) 99)
          :object-kind (getf surface :object-kind)
          :execution-id (getf surface :execution-id)
          :work-item-id (getf surface :work-item-id)
          :workflow-record-id (getf surface :workflow-record-id)
          :incident-id (getf surface :incident-id)
          :thread-id (getf surface :thread-id)
          :turn-id (getf surface :turn-id)
          :title (getf surface :title)
          :status (getf surface :status)
          :corrective-context (getf surface :corrective-context))))

(defun compact-shell-governance-item (item)
  (when item
    (list :queue-kind (getf item :queue-kind)
          :attention-rank (getf item :attention-rank)
          :object-kind (getf item :object-kind)
          :execution-id (getf item :execution-id)
          :work-item-id (getf item :work-item-id)
          :workflow-record-id (getf item :workflow-record-id)
          :incident-id (getf item :incident-id)
          :thread-id (getf item :thread-id)
          :turn-id (getf item :turn-id)
          :title (getf item :title)
          :status (getf item :status)
          :corrective-context (getf item :corrective-context)
          :surface (compact-execution-surface-summary
                    (getf item :surface)))))

(defun shell-governance-item-focus-object-id (item &optional environment)
  (or (shell-object-reference-execution-id item)
      (shell-object-reference-execution-id (getf item :surface))
      (let ((handle (or (and (getf item :work-item-id)
                             (first (execution-handle-summaries-by-target :work-item-id
                                                                          (getf item :work-item-id)
                                                                          environment)))
                        (and (getf item :workflow-record-id)
                             (first (execution-handle-summaries-by-target :workflow-record-id
                                                                          (getf item :workflow-record-id)
                                                                          environment)))
                        (and (getf item :incident-id)
                             (first (execution-handle-summaries-by-target :incident-id
                                                                          (getf item :incident-id)
                                                                          environment)))
                        (and (getf item :turn-id)
                             (first (execution-handle-summaries-by-target :turn-id
                                                                          (getf item :turn-id)
                                                                          environment))))))
        (and handle
             (getf handle :execution-id)))))

(defun shell-compact-object-reference (object-kind item)
  (case object-kind
    (:execution
     (compact-execution-surface-summary item))
    (:work-item
     (list :id (getf item :id)
           :title (or (getf item :goal) "Governed work item")
           :status (getf item :status)
           :execution-surface (getf item :execution-surface)))
    (:workflow-record
     (list :id (getf item :id)
           :title (or (getf item :title)
                      (format nil "Workflow ~A" (getf item :id)))
           :status (getf item :status)
           :execution-surface (getf item :execution-surface)))
    (:incident
     (list :id (getf item :id)
           :title (or (getf item :title) "Incident")
           :status (getf item :status)
           :execution-surface (getf item :execution-surface)))
    (:task
     (list :id (getf item :id)
           :title (or (getf item :label)
                      (format nil "Task ~A" (getf item :id)))
           :status (getf item :status)
           :execution-surface (getf item :execution-surface)))
    (:worker
     (list :id (getf item :id)
           :title (or (getf item :label)
                      (format nil "Worker ~A" (getf item :id)))
           :status (if (getf item :running-p) :running :stopped)
           :execution-surface (getf item :execution-surface)))
    (:compatibility
     (list :id (getf item :execution-id)
           :title (or (getf item :title)
                      (format nil "Compatibility ~A" (getf item :execution-id)))
           :status (getf item :status)))
    (otherwise
     item)))

(defun shell-object-browser-group (object-kind items)
  (list :object-kind object-kind
        :count (length items)
        :top-item (first items)
        :items items))

(defun shell-object-browser-focus-object-id (browser)
  (let* ((top-group (getf browser :top-group))
         (top-item (and top-group
                        (getf top-group :top-item))))
    (shell-object-reference-execution-id top-item)))

(defun shell-workspace-surface-items (workspace)
  (or (getf (getf workspace :execution-surfaces) :items) '()))

(defun shell-workspace-display-items (workspace)
  (or (getf (getf workspace :display-surfaces) :entries) '()))

(defun shell-workspace-surface-index (workspace focus-object-id)
  (position focus-object-id
            (shell-workspace-surface-items workspace)
            :key #'shell-surface-execution-id
            :test #'string=))

(defun nth-shell-workspace-surface (workspace index)
  (let ((items (shell-workspace-surface-items workspace)))
    (unless (and (integerp index)
                 (<= 0 index)
                 (< index (length items)))
      (error "Shell workspace surface index ~S is out of range" index))
    (nth index items)))

(defun step-shell-workspace-surface (workspace focus-object-id direction)
  (let* ((items (shell-workspace-surface-items workspace))
         (count (length items)))
    (when (zerop count)
      (error "Shell workspace has no execution surfaces"))
    (let* ((current-index (or (shell-workspace-surface-index workspace focus-object-id)
                              0))
           (delta (ecase direction
                    (:next 1)
                    (:previous -1)))
           (next-index (mod (+ current-index delta) count)))
      (values (nth next-index items)
              next-index))))

(defun shell-workspace-display-index (workspace focus-object-id)
  (position focus-object-id
            (shell-workspace-display-items workspace)
            :key (lambda (entry) (getf entry :execution-id))
            :test #'string=))

(defun nth-shell-workspace-display (workspace index)
  (let ((items (shell-workspace-display-items workspace)))
    (unless (and (integerp index)
                 (<= 0 index)
                 (< index (length items)))
      (error "Shell workspace display index ~S is out of range" index))
    (nth index items)))

(defun shell-workspace-display-by-app-id (workspace app-id)
  (when app-id
    (find app-id
          (shell-workspace-display-items workspace)
          :key (lambda (entry) (getf entry :app-id))
          :test #'string=)))

(defun shell-current-display-surface (workspace focus-object-id)
  (or (and focus-object-id
           (find focus-object-id
                 (shell-workspace-display-items workspace)
                 :key (lambda (entry) (getf entry :execution-id))
                 :test #'string=))
      (getf (getf workspace :display-surfaces) :top-surface)))

(defun step-shell-workspace-display (workspace focus-object-id direction)
  (let* ((items (shell-workspace-display-items workspace))
         (count (length items)))
    (when (zerop count)
      (error "Shell workspace has no display surfaces"))
    (let* ((current-index (or (shell-workspace-display-index workspace focus-object-id)
                              0))
           (delta (ecase direction
                    (:next 1)
                    (:previous -1)))
           (next-index (mod (+ current-index delta) count)))
      (values (nth next-index items)
              next-index))))

(defun nth-shell-object-browser-reference (browser object-kind index)
  (let* ((group (find object-kind
                      (or (getf browser :groups) '())
                      :key (lambda (entry) (getf entry :object-kind))
                      :test #'eq))
         (items (and group (getf group :items))))
    (unless group
      (error "Shell object-browser has no group for ~S" object-kind))
    (unless (and (integerp index)
                 (<= 0 index)
                 (< index (length items)))
      (error "Shell object-browser index ~S is out of range for ~S" index object-kind))
    (nth index items)))

(defun nth-shell-governance-item (queue index)
  (let ((items (or (getf queue :items) '())))
    (unless (and (integerp index)
                 (<= 0 index)
                 (< index (length items)))
      (error "Shell governance queue index ~S is out of range" index))
    (nth index items)))

(defun select-shell-governance-item (queue index &optional environment)
  (let ((items (or (getf queue :items) '())))
    (unless (and (integerp index)
                 (<= 0 index)
                 (< index (length items)))
      (error "Shell governance queue index ~S is out of range" index))
    (loop for item in (nthcdr index items)
          for actual-index from index
          for focus-object-id = (shell-governance-item-focus-object-id item environment)
          when focus-object-id
            do (return (values item actual-index focus-object-id))
          finally (error "No focusable governance queue item exists at or after index ~S" index))))

(defun query-shell-governance-queue-service (session &key environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (session-summary (service-response-data
                           (query-session-summary-service session)))
         (incident-summaries (service-response-data
                              (query-incident-list-service session)))
         (blocked-items (mapcar (lambda (surface)
                                  (shell-governance-queue-item :blocked-work surface))
                                (or (getf (getf session-summary :blocked-work-surfaces) :items) '())))
         (approval-items (mapcar (lambda (surface)
                                   (shell-governance-queue-item :approval surface))
                                 (or (getf (getf session-summary :approval-surfaces) :items) '())))
         (incident-items (mapcar (lambda (incident)
                                   (shell-governance-queue-item :incident
                                                                (getf incident :execution-surface)))
                                 (remove-if-not (lambda (incident)
                                                  (member (getf incident :status)
                                                          '(:open :failed :awaiting-approval
                                                            :quarantined :awaiting-cold-validation)
                                                          :test #'eq))
                                                (or incident-summaries '()))))
         (items (remove nil (append approval-items blocked-items incident-items)))
         (sorted (sort items #'< :key (lambda (item)
                                        (or (getf item :attention-rank) 99)))))
    (make-service-query-response :shell
                                 :governance-queue
                                 (list :count (length sorted)
                                       :top-item (compact-shell-governance-item (first sorted))
                                       :items (mapcar #'compact-shell-governance-item sorted)
                                       :environment-id (environment-id active-environment))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :shell-governance-queue-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-shell-object-browser-service (session &key object-kind environment)
  (declare (ignore environment))
  (let* ((execution-items (or (getf (compact-execution-surfaces-data
                                     (service-response-data
                                      (query-execution-surfaces-service session)))
                                    :items)
                              '()))
         (work-item-items (mapcar (lambda (item)
                                    (shell-compact-object-reference :work-item item))
                                  (or (service-response-data
                                       (query-work-item-list-service session))
                                      '())))
         (workflow-items (mapcar (lambda (item)
                                   (shell-compact-object-reference :workflow-record item))
                                 (or (service-response-data
                                      (query-workflow-record-list-service session))
                                     '())))
         (incident-items (mapcar (lambda (item)
                                   (shell-compact-object-reference :incident item))
                                 (or (service-response-data
                                      (query-incident-list-service session))
                                     '())))
         (task-items (mapcar (lambda (item)
                               (shell-compact-object-reference :task item))
                             (or (service-response-data
                                  (query-task-list-service session))
                                 '())))
         (worker-items (mapcar (lambda (item)
                                 (shell-compact-object-reference :worker item))
                               (or (service-response-data
                                    (query-worker-list-service session))
                                   '())))
         (compatibility-items (mapcar (lambda (item)
                                        (list :id (getf item :execution-id)
                                              :title (format nil "Compatibility ~A"
                                                             (getf item :execution-id))
                                              :status (getf item :status)
                                              :execution-id (getf item :execution-id)))
                                      (or (getf (service-response-data
                                                 (query-compatibility-executions-service session))
                                                :entries)
                                          '())))
         (groups (remove nil
                         (list (and (or (null object-kind) (eq object-kind :execution))
                                    (shell-object-browser-group :execution execution-items))
                               (and (or (null object-kind) (eq object-kind :work-item))
                                    (shell-object-browser-group :work-item work-item-items))
                               (and (or (null object-kind) (eq object-kind :workflow-record))
                                    (shell-object-browser-group :workflow-record workflow-items))
                               (and (or (null object-kind) (eq object-kind :incident))
                                    (shell-object-browser-group :incident incident-items))
                               (and (or (null object-kind) (eq object-kind :task))
                                    (shell-object-browser-group :task task-items))
                               (and (or (null object-kind) (eq object-kind :worker))
                                    (shell-object-browser-group :worker worker-items))
                               (and (or (null object-kind) (eq object-kind :compatibility))
                                    (shell-object-browser-group :compatibility compatibility-items)))))
         (non-empty (remove-if (lambda (group)
                                 (zerop (getf group :count)))
                               groups)))
    (make-service-query-response :shell
                                 :object-browser
                                 (list :group-count (length non-empty)
                                       :top-group (first non-empty)
                                       :groups non-empty
                                       :focus-object-id (shell-object-browser-focus-object-id
                                                         (list :top-group (first non-empty)))
                                       :filter (list :object-kind object-kind))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :shell-object-browser-v1
                                                                  :session session))))

(defun shell-workspace-focus-object-id (session workspace &optional environment)
  (or (shell-focus-object-id session environment)
      (getf (getf (getf workspace :governance-queue) :top-item) :execution-id)
      (getf (getf workspace :top-surface) :execution-id)))

(defun shell-workspace-current-focus-summary (workspace)
  (let* ((focus-object-id (getf workspace :inspector-focus-object-id))
         (display-item (or (getf workspace :current-display-surface)
                           (and focus-object-id
                                (find focus-object-id
                                      (shell-workspace-display-items workspace)
                                      :key (lambda (entry) (getf entry :execution-id))
                                      :test #'string=))))
         (surface-item (and focus-object-id
                            (find focus-object-id
                                  (or (getf (getf workspace :execution-surfaces) :items) '())
                                  :key (lambda (entry) (getf entry :execution-id))
                                  :test #'string=)))
         (queue-item (and focus-object-id
                          (find focus-object-id
                                (or (getf (getf workspace :governance-queue) :items) '())
                                :key (lambda (entry)
                                       (or (getf entry :execution-id)
                                           (getf (getf entry :surface) :execution-id)))
                                :test #'string=)))
         (browser-match
           (and focus-object-id
                (loop for group in (or (getf (getf workspace :object-browser) :groups) '())
                      thereis
                      (loop for item in (or (getf group :items) '())
                            for index from 0
                            for execution-id = (shell-object-reference-execution-id item)
                            thereis
                            (and execution-id
                                 (string= execution-id focus-object-id)
                                 (list :group group :item item :index index)))))))
    (cond
      (display-item
       (list :focus-kind :display
             :label (or (getf display-item :title)
                        (getf display-item :app-id)
                        "Display surface")
             :status (getf display-item :status)
             :execution-id (getf display-item :execution-id)
             :app-id (getf display-item :app-id)))
      (surface-item
       (list :focus-kind :surface
             :label (or (getf surface-item :title)
                        "Execution surface")
             :status (getf surface-item :status)
             :execution-id (getf surface-item :execution-id)
             :surface-kind (getf surface-item :surface-kind)
             :object-kind (getf surface-item :object-kind)))
      (queue-item
       (list :focus-kind :governance
             :label (or (getf queue-item :title)
                        (getf (getf queue-item :surface) :title)
                        "Governance item")
             :status (or (getf queue-item :status)
                         (getf (getf queue-item :surface) :status))
             :execution-id (or (getf queue-item :execution-id)
                               (getf (getf queue-item :surface) :execution-id))
             :queue-kind (getf queue-item :queue-kind)))
      (browser-match
       (let ((group (getf browser-match :group))
             (item (getf browser-match :item)))
         (list :focus-kind :object-browser
               :label (or (shell-object-reference-title item)
                          "Browser item")
               :status (getf item :status)
               :execution-id (shell-object-reference-execution-id item)
               :object-kind (getf group :object-kind)
               :selected-index (getf browser-match :index))))
      (t nil))))

(defun shell-workspace-recommended-action (workspace)
  (let* ((focus-summary (shell-workspace-current-focus-summary workspace))
         (display-actions (getf workspace :display-actions))
         (display-entry-actions (getf workspace :display-entry-actions))
         (entry-points (shell-workspace-entry-points workspace)))
    (labels ((compact-action (label action)
               (and action
                    (list :label label
                          :action-kind (getf action :action-kind)
                          :command (getf action :command)
                          :action-id (getf action :action-id)))))
      (or (when (and focus-summary (eq (getf focus-summary :focus-kind) :display))
            (or (compact-action "Show current display" (getf display-actions :show))
                (compact-action "Open display lane" (getf display-entry-actions :open))))
          (when (and focus-summary (eq (getf focus-summary :focus-kind) :surface))
            (compact-action "Open focused surface"
                            (shell-desktop-action :open-panel
                                                  :workspace
                                                  (shell-desktop-command-string "open"
                                                                                :execution-id (getf focus-summary :execution-id))
                                                  :execution-id (getf focus-summary :execution-id))))
          (when (and focus-summary (eq (getf focus-summary :focus-kind) :governance))
            (compact-action "Open governance queue"
                            (shell-desktop-action :open-panel
                                                  :governance
                                                  "(open :governance-index 0)"
                                                  :index 0)))
          (when (and focus-summary (eq (getf focus-summary :focus-kind) :object-browser))
            (compact-action "Open object browser selection"
                            (shell-desktop-action :open-panel
                                                  :object-browser
                                                  (shell-desktop-command-string "open"
                                                                                :object-kind (getf focus-summary :object-kind)
                                                                                :object-index (or (getf focus-summary :selected-index) 0))
                                                  :object-kind (getf focus-summary :object-kind)
                                                  :index (or (getf focus-summary :selected-index) 0))))
          (let* ((top-entry (first entry-points))
                 (top-action (or (getf top-entry :action)
                                 (getf (getf top-entry :actions) :show)
                                 (getf (getf top-entry :actions) :open))))
            (compact-action "Open top workspace entry" top-action))))))

(defun shell-entry-point (entry-kind label command &key focus-object-id object-kind action actions)
  (append (list :entry-kind entry-kind
                :label label
                :command command
                :focus-object-id focus-object-id
                :object-kind object-kind)
          (when action
            (list :action action))
          (when actions
            (list :actions actions))))

(defun shell-workspace-entry-points (workspace)
  (let ((top-surface (getf workspace :top-surface))
        (top-display-surface (getf (getf workspace :display-surfaces) :top-surface))
        (top-queue-item (getf (getf workspace :governance-queue) :top-item))
        (object-browser (getf workspace :object-browser)))
    (let* ((top-group (and object-browser
                           (getf object-browser :top-group)))
           (object-kind (and top-group
                             (getf top-group :object-kind))))
      (remove nil
              (list
               (when top-surface
                 (shell-entry-point :surface
                                    "Top surface"
                                    "(open :surface-index 0)"
                                    :focus-object-id (getf top-surface :execution-id)
                                    :object-kind (getf top-surface :object-kind)
                                    :action (shell-desktop-action :open-panel
                                                                  :workspace
                                                                  "(open :surface-index 0)"
                                                                  :index 0
                                                                  :execution-id (getf top-surface :execution-id))))
               (when top-display-surface
                 (shell-entry-point
                  :display
                  "Top display surface"
                  (if (getf top-display-surface :app-id)
                      (format nil "(open :display-app-id ~S)"
                              (getf top-display-surface :app-id))
                      (format nil "(open :execution-id ~S)"
                              (getf top-display-surface :execution-id)))
                  :focus-object-id (getf top-display-surface :execution-id)
                  :object-kind :compatibility
                  :actions (append
                            (list
                             :open (shell-desktop-action :open-panel
                                                         :display
                                                         (if (getf top-display-surface :app-id)
                                                             (format nil "(open :display-app-id ~S)"
                                                                     (getf top-display-surface :app-id))
                                                             (format nil "(open :execution-id ~S)"
                                                                     (getf top-display-surface :execution-id)))
                                                         :index 0
                                                         :execution-id (getf top-display-surface :execution-id)
                                                         :app-id (getf top-display-surface :app-id))
                             :show (shell-desktop-action :show-panel
                                                         :display
                                                         (format nil "(display/show :app-id ~S)"
                                                                 (getf top-display-surface :app-id))
                                                         :index 0
                                                         :execution-id (getf top-display-surface :execution-id)
                                                         :app-id (getf top-display-surface :app-id))
                             :next (shell-desktop-action :step-panel
                                                         :display
                                                         "(display/step :next)"
                                                         :index 0
                                                         :execution-id (getf top-display-surface :execution-id)
                                                         :app-id (getf top-display-surface :app-id)
                                                         :direction :next)
                             :previous (shell-desktop-action :step-panel
                                                             :display
                                                             "(display/step :previous)"
                                                             :index 0
                                                             :execution-id (getf top-display-surface :execution-id)
                                                             :app-id (getf top-display-surface :app-id)
                                                             :direction :previous))
                            (when (member :relaunch
                                          (getf (getf top-display-surface :control-posture)
                                                :supported-actions)
                                          :test #'eq)
                              (list :relaunch (shell-desktop-action :control-panel
                                                                    :display
                                                                    (format nil "(display/control :action :relaunch :app-id ~S)"
                                                                            (getf top-display-surface :app-id))
                                                                    :index 0
                                                                    :execution-id (getf top-display-surface :execution-id)
                                                                    :app-id (getf top-display-surface :app-id)
                                                                    :control-action :relaunch)))
                            (when (member :stop
                                          (getf (getf top-display-surface :control-posture)
                                                :supported-actions)
                                          :test #'eq)
                              (list :stop (shell-desktop-action :control-panel
                                                                :display
                                                                (format nil "(display/control :action :stop :app-id ~S)"
                                                                        (getf top-display-surface :app-id))
                                                                :index 0
                                                                :execution-id (getf top-display-surface :execution-id)
                                                                :app-id (getf top-display-surface :app-id)
                                                                :control-action :stop))))))
               (when top-queue-item
                 (shell-entry-point :governance
                                    "Top governance item"
                                    "(open :governance-index 0)"
                                    :focus-object-id (getf top-queue-item :execution-id)
                                    :object-kind (getf top-queue-item :object-kind)
                                    :action (shell-desktop-action :open-panel
                                                                  :governance
                                                                  "(open :governance-index 0)"
                                                                  :index 0)))
               (when object-kind
                 (shell-entry-point :object-browser
                                    "Top object group"
                                    (format nil "(open :object-kind ~S :object-index 0)" object-kind)
                                    :focus-object-id (getf object-browser :focus-object-id)
                                    :object-kind object-kind
                                    :action (shell-desktop-action :open-panel
                                                                  :object-browser
                                                                  (format nil "(open :object-kind ~S :object-index 0)" object-kind)
                                                                  :index 0
                                                                  :object-kind object-kind))))))))

(defun shell-desktop-command-string (operator &rest arguments)
  (format nil "(~A~{ ~S~})" operator arguments))

(defun shell-desktop-action-id (action-kind panel-id &key index execution-id app-id object-kind control-action direction)
  (with-output-to-string (stream)
    (format stream "~(~A~):~(~A~)" panel-id action-kind)
    (when control-action
      (format stream ":~(~A~)" control-action))
    (when direction
      (format stream ":~(~A~)" direction))
    (when object-kind
      (format stream ":~(~A~)" object-kind))
    (when execution-id
      (format stream ":~A" execution-id))
    (when app-id
      (format stream ":~A" app-id))
    (when (integerp index)
      (format stream ":~D" index))))

(defun shell-desktop-action (action-kind panel-id command &rest params)
  (let ((index (getf params :index))
        (execution-id (getf params :execution-id))
        (app-id (getf params :app-id))
        (control-action (getf params :control-action))
        (direction (getf params :direction))
        (object-kind (or (getf params :object-kind)
                         (getf params :kind))))
    (list :action-id (shell-desktop-action-id action-kind
                                              panel-id
                                              :index index
                                              :execution-id execution-id
                                              :app-id app-id
                                              :object-kind object-kind
                                              :control-action control-action
                                              :direction direction)
          :action-kind action-kind
          :panel-id panel-id
          :command command
          :params params)))

(defun normalize-shell-desktop-restore-panel-state (panel-id panel-state)
  (let ((resolved-panel-id (or panel-id
                               (getf panel-state :panel-id))))
    (unless (keywordp resolved-panel-id)
      (error "DESKTOP/RESTORE requires :panel-id or a panel-state with :panel-id"))
    (case resolved-panel-id
      (:workspace
       (append (list :panel-id :workspace)
               (when (integerp (getf panel-state :selected-index))
                 (list :selected-index (getf panel-state :selected-index)))
               (when (getf panel-state :selected-execution-id)
                 (list :selected-execution-id (getf panel-state :selected-execution-id)))))
      (:display
       (append (list :panel-id :display)
               (when (integerp (getf panel-state :selected-index))
                 (list :selected-index (getf panel-state :selected-index)))
               (when (getf panel-state :selected-execution-id)
                 (list :selected-execution-id (getf panel-state :selected-execution-id)))
               (when (getf panel-state :selected-app-id)
                 (list :selected-app-id (getf panel-state :selected-app-id)))))
      (:governance
       (append (list :panel-id :governance)
               (when (integerp (getf panel-state :selected-index))
                 (list :selected-index (getf panel-state :selected-index)))))
      (:object-browser
       (append (list :panel-id :object-browser)
               (when (integerp (getf panel-state :selected-index))
                 (list :selected-index (getf panel-state :selected-index)))
               (when (getf panel-state :selected-kind)
                 (list :selected-kind (getf panel-state :selected-kind)))))
      (:inspector
       (append (list :panel-id :inspector)
               (when (getf panel-state :focus-object-id)
                 (list :focus-object-id (getf panel-state :focus-object-id)))))
      (otherwise
       (error "Unknown shell desktop panel ~S" resolved-panel-id)))))

(defun shell-desktop-selected-governance-item (governance-queue focus-object-id)
  (or (find focus-object-id
            (or (getf governance-queue :items) '())
            :key (lambda (item)
                   (or (getf item :execution-id)
                       (getf (getf item :surface) :execution-id)))
            :test #'string=)
      (getf governance-queue :top-item)))

(defun shell-desktop-selected-object-browser-entry (object-browser focus-object-id)
  (let ((groups (or (getf object-browser :groups) '())))
    (labels ((find-match (candidate-groups)
               (loop for group in candidate-groups
                     for object-kind = (getf group :object-kind)
                     for items = (or (getf group :items) '())
                     thereis
                     (loop for item in items
                           for item-index from 0
                           for execution-id = (shell-object-reference-execution-id item)
                           thereis
                           (and execution-id
                                focus-object-id
                                (string= execution-id focus-object-id)
                                (list :object-kind object-kind
                                      :selected-index item-index
                                      :selected-item item))))))
      (or (find-match (remove :execution
                              groups
                              :key (lambda (group) (getf group :object-kind))
                              :test #'eq))
          (find-match groups)
          (let* ((top-group (getf object-browser :top-group))
                 (object-kind (and top-group (getf top-group :object-kind)))
                 (top-item (and top-group (getf top-group :top-item))))
            (and object-kind
                 top-item
                 (list :object-kind object-kind
                       :selected-index 0
                       :selected-item top-item)))))))

(defun shell-desktop-panel-actions (panel-id &key index execution-id app-id object-kind supported-actions)
  (let* ((resolved-index (or index 0))
         (activate-command
           (shell-desktop-command-string "desktop/panel" panel-id))
         (select-command
           (case panel-id
             (:workspace
              (if execution-id
                  (shell-desktop-command-string "desktop/select"
                                                :panel :workspace
                                                :execution-id execution-id)
                  (shell-desktop-command-string "desktop/select"
                                                :panel :workspace
                                                :index resolved-index)))
             (:display
              (if execution-id
                  (shell-desktop-command-string "desktop/select"
                                                :panel :display
                                                :execution-id execution-id)
                  (if app-id
                      (shell-desktop-command-string "desktop/select"
                                                    :panel :display
                                                    :app-id app-id)
                      (shell-desktop-command-string "desktop/select"
                                                    :panel :display
                                                    :index resolved-index))))
             (:governance
              (shell-desktop-command-string "desktop/select"
                                            :panel :governance
                                            :index resolved-index))
             (:object-browser
              (shell-desktop-command-string "desktop/select"
                                            :panel :object-browser
                                            :kind object-kind
                                            :index resolved-index))
             (:inspector
              (if execution-id
                  (shell-desktop-command-string "desktop/select"
                                                :panel :inspector
                                                :execution-id execution-id)
                  (shell-desktop-command-string "desktop/select"
                                                :panel :inspector)))))
         (open-command
           (case panel-id
             (:workspace
              (if execution-id
                  (shell-desktop-command-string "open" :execution-id execution-id)
                  (shell-desktop-command-string "open" :surface-index resolved-index)))
             (:display
              (if app-id
                  (shell-desktop-command-string "open" :display-app-id app-id)
                  (if execution-id
                  (shell-desktop-command-string "open" :execution-id execution-id)
                      (shell-desktop-command-string "open" :display-index resolved-index))))
             (:governance
              (shell-desktop-command-string "open" :governance-index resolved-index))
             (:object-browser
              (shell-desktop-command-string "open"
                                            :object-kind object-kind
                                            :object-index resolved-index))
             (:inspector
              (if execution-id
                  (shell-desktop-command-string "inspector/show" execution-id)
                  (shell-desktop-command-string "inspector/show")))))
         (restore-payload
           (case panel-id
             (:workspace
              (append (list :panel-id :workspace
                            :selected-index resolved-index)
                      (when execution-id
                        (list :selected-execution-id execution-id))))
             (:display
              (append (list :panel-id :display
                            :selected-index resolved-index)
                      (when execution-id
                        (list :selected-execution-id execution-id))
                      (when app-id
                        (list :selected-app-id app-id))))
             (:governance
              (list :panel-id :governance
                    :selected-index resolved-index))
             (:object-browser
              (append (list :panel-id :object-browser
                            :selected-index resolved-index)
                      (when object-kind
                        (list :selected-kind object-kind))))
             (:inspector
              (append (list :panel-id :inspector)
                      (when execution-id
                        (list :focus-object-id execution-id))))))
         (restore-command
           (shell-desktop-command-string "desktop/restore"
                                         :panel-state
                                         restore-payload))
         (show-command
           (and (eq panel-id :display)
                (if app-id
                    (shell-desktop-command-string "display/show" :app-id app-id)
                    (if execution-id
                        (shell-desktop-command-string "display/show" execution-id)
                        (shell-desktop-command-string "display/show")))))
         (step-next-command
           (and (eq panel-id :display)
                (shell-desktop-command-string "display/step" :next)))
         (step-previous-command
           (and (eq panel-id :display)
                (shell-desktop-command-string "display/step" :previous)))
         (relaunch-command
           (and (eq panel-id :display)
                (or execution-id app-id)
                (member :relaunch supported-actions :test #'eq)
                (shell-desktop-command-string "display/control"
                                              :action :relaunch
                                              (if app-id :app-id :execution-id)
                                              (or app-id execution-id))))
         (stop-command
           (and (eq panel-id :display)
                execution-id
                (member :stop supported-actions :test #'eq)
                (shell-desktop-command-string "display/control"
                                              :action :stop
                                              :execution-id execution-id))))
    (append
     (list :activate-command activate-command
           :select-command select-command
           :open-command open-command
           :restore-command restore-command
           :activate (shell-desktop-action :activate-panel
                                           panel-id
                                           activate-command)
           :select (shell-desktop-action :select-panel
                                         panel-id
                                         select-command
                                         :index index
                                         :execution-id execution-id
                                         :app-id app-id
                                         :object-kind object-kind)
           :open (shell-desktop-action :open-panel
                                       panel-id
                                       open-command
                                       :index index
                                       :execution-id execution-id
                                       :app-id app-id
                                       :object-kind object-kind)
           :restore (shell-desktop-action :restore-panel
                                          panel-id
                                          restore-command
                                          :index index
                                          :execution-id execution-id
                                          :app-id app-id
                                          :object-kind object-kind))
     (when show-command
       (list :show-command show-command
             :show (shell-desktop-action :show-panel
                                         panel-id
                                         show-command
                                         :index index
                                         :execution-id execution-id
                                         :app-id app-id)))
     (when step-next-command
       (list :next-command step-next-command
             :next (shell-desktop-action :step-panel
                                         panel-id
                                         step-next-command
                                         :index index
                                         :execution-id execution-id
                                         :app-id app-id
                                         :direction :next)))
     (when step-previous-command
       (list :previous-command step-previous-command
             :previous (shell-desktop-action :step-panel
                                             panel-id
                                             step-previous-command
                                             :index index
                                             :execution-id execution-id
                                             :app-id app-id
                                             :direction :previous)))
     (when relaunch-command
       (list :relaunch-command relaunch-command
             :relaunch (shell-desktop-action :control-panel
                                             panel-id
                                             relaunch-command
                                             :index index
                                             :execution-id execution-id
                                             :app-id app-id
                                             :control-action :relaunch)))
     (when stop-command
       (list :stop-command stop-command
             :stop (shell-desktop-action :control-panel
                                         panel-id
                                         stop-command
                                         :index index
                                         :execution-id execution-id
                                         :app-id app-id
                                         :control-action :stop))))))

(defun shell-find-desktop-action-by-id (desktop-model action-id)
  (loop for panel-id in '(:workspace :display :governance :object-browser :inspector)
        for panel = (getf (getf desktop-model :panels) panel-id)
        for actions = (and panel (getf panel :actions))
        thereis
        (loop for action-key in '(:activate :select :open :restore :show :next :previous :relaunch :stop)
              for action = (and actions (getf actions action-key))
              thereis
              (and action
                   (string= (or (getf action :action-id) "") action-id)
                   action))))

(defun shell-desktop-panels (workspace surface-list governance-queue object-browser inspector)
  (let* ((focus-object-id (getf workspace :inspector-focus-object-id))
         (selected-surface-index (getf surface-list :focus-index))
         (selected-surface (and (integerp selected-surface-index)
                                (nth selected-surface-index
                                     (or (getf surface-list :items) '()))))
         (selected-display-index (or (shell-workspace-display-index workspace focus-object-id)
                                     0))
         (selected-display (and (> (or (getf (getf workspace :display-surfaces) :count) 0) 0)
                                (nth selected-display-index
                                     (or (getf (getf workspace :display-surfaces) :entries) '()))))
         (selected-governance-item (shell-desktop-selected-governance-item governance-queue
                                                                           focus-object-id))
         (selected-governance-index (position selected-governance-item
                                              (or (getf governance-queue :items) '())
                                              :test #'equal))
         (selected-browser-entry (shell-desktop-selected-object-browser-entry object-browser
                                                                              focus-object-id))
         (selected-browser-kind (getf selected-browser-entry :object-kind))
         (selected-browser-index (getf selected-browser-entry :selected-index))
         (selected-browser-item (getf selected-browser-entry :selected-item)))
    (list :workspace (list :panel-id :workspace
                           :count (getf (getf workspace :execution-surfaces) :count)
                           :focus-object-id focus-object-id
                           :selected-index selected-surface-index
                           :selected-execution-id (shell-surface-execution-id selected-surface)
                           :top-surface (getf workspace :top-surface)
                           :actions (shell-desktop-panel-actions :workspace
                                                                 :index selected-surface-index
                                                                 :execution-id (shell-surface-execution-id selected-surface)))
         :display (list :panel-id :display
                         :count (getf (getf workspace :display-surfaces) :count)
                         :focus-object-id (getf selected-display :execution-id)
                         :selected-index selected-display-index
                         :selected-execution-id (getf selected-display :execution-id)
                         :selected-app-id (getf selected-display :app-id)
                         :selected-window-state (getf selected-display :window-state)
                         :selected-status (getf selected-display :status)
                         :selected-display-surface-kind (getf selected-display :display-surface-kind)
                         :selected-source-package-id (getf selected-display :source-package-id)
                         :selected-controllable-p (getf (getf selected-display :control-posture) :controllable-p)
                         :selected-supported-actions (getf (getf selected-display :control-posture) :supported-actions)
                         :selected-relaunch-ready-p (not (null (member :relaunch
                                                                        (getf (getf selected-display :control-posture)
                                                                              :supported-actions)
                                                                        :test #'eq)))
                         :top-surface (getf (getf workspace :display-surfaces) :top-surface)
                         :actions (shell-desktop-panel-actions :display
                                                               :index selected-display-index
                                                               :execution-id (getf selected-display :execution-id)
                                                               :app-id (getf selected-display :app-id)
                                                               :supported-actions (getf (getf selected-display :control-posture)
                                                                                        :supported-actions)))
          :governance (list :panel-id :governance
                            :count (getf governance-queue :count)
                            :focus-object-id (or (getf selected-governance-item :execution-id)
                                                 (getf (getf selected-governance-item :surface) :execution-id))
                            :selected-index selected-governance-index
                            :selected-title (getf selected-governance-item :title)
                            :selected-queue-kind (getf selected-governance-item :queue-kind)
                            :top-item (getf governance-queue :top-item)
                            :actions (shell-desktop-panel-actions :governance
                                                                  :index selected-governance-index))
          :object-browser (list :panel-id :object-browser
                                :count (getf object-browser :group-count)
                                :focus-object-id (or (shell-object-reference-execution-id selected-browser-item)
                                                     (getf object-browser :focus-object-id))
                                :selected-kind selected-browser-kind
                                :selected-index selected-browser-index
                                :selected-title (and selected-browser-item
                                                     (shell-object-reference-title selected-browser-item))
                                :top-group (getf object-browser :top-group)
                                :actions (shell-desktop-panel-actions :object-browser
                                                                      :index selected-browser-index
                                                                      :object-kind selected-browser-kind))
          :inspector (list :panel-id :inspector
                           :focus-object-id (getf inspector :focus-object-id)
                           :object-kind (getf inspector :object-kind)
                           :resolved-via (getf inspector :resolved-via)
                           :status (getf (getf inspector :summary) :status)
                           :history-count (getf (getf inspector :summary) :history-count)
                           :recommended-action (getf inspector :recommended-action)
                           :actions (shell-desktop-panel-actions :inspector
                                                                 :execution-id (getf inspector :focus-object-id))))))

(defun shell-desktop-default-active-panel (workspace governance-queue object-browser)
  (cond
    ((> (or (getf (getf workspace :display-surfaces) :count) 0) 0) :display)
    ((getf workspace :inspector-focus-object-id) :inspector)
    ((> (or (getf governance-queue :count) 0) 0) :governance)
    ((> (or (getf object-browser :group-count) 0) 0) :object-browser)
    (t :workspace)))

(defun shell-desktop-panel-available-p (panels panel-id)
  (let ((panel (getf panels panel-id)))
    (and panel
         (case panel-id
           (:workspace (> (or (getf panel :count) 0) 0))
           (:display (> (or (getf panel :count) 0) 0))
           (:governance (> (or (getf panel :count) 0) 0))
           (:object-browser (> (or (getf panel :count) 0) 0))
           (:inspector (stringp (getf panel :focus-object-id)))
           (otherwise nil)))))

(defun shell-desktop-active-panel (session workspace governance-queue object-browser panels)
  (let ((persisted-panel-id (shell-active-panel-id session)))
    (if (and persisted-panel-id
             (shell-desktop-panel-available-p panels persisted-panel-id))
        persisted-panel-id
        (shell-desktop-default-active-panel workspace governance-queue object-browser))))

(defun shell-inspector-summary (inspection)
  (let* ((execution (getf inspection :execution))
         (inspection-data (getf inspection :inspection))
         (forensics (getf inspection :forensics))
         (control-posture (getf inspection-data :control-posture)))
    (list :focus-object-id (getf inspection :focus-object-id)
          :object-kind (getf inspection :object-kind)
          :resolved-via (getf inspection :resolved-via)
          :status (or (getf inspection-data :status)
                      (getf execution :last-observed-status)
                      (getf execution :status))
          :capability (and execution
                           (capability-name-string (getf execution :capability)))
          :history-count (getf forensics :history-count)
          :app-id (getf inspection-data :app-id)
          :supported-actions (and control-posture
                                  (getf control-posture :supported-actions)))))

(defun shell-inspector-recommended-action (inspection)
  (let* ((execution (getf inspection :execution))
         (inspection-data (getf inspection :inspection))
         (control-posture (getf inspection-data :control-posture))
         (supported-actions (and control-posture
                                 (getf control-posture :supported-actions)))
         (execution-id (and execution (getf execution :execution-id)))
         (app-id (getf inspection-data :app-id)))
    (cond
      ((and app-id (member :show supported-actions :test #'eq))
       (list :label "Show focused display"
             :action-kind :show-panel
             :command (shell-desktop-command-string "display/show" :app-id app-id)
             :action-id (shell-desktop-action-id :show-panel :inspector
                                                 :execution-id execution-id
                                                 :app-id app-id)))
      ((and app-id (member :relaunch supported-actions :test #'eq))
       (list :label "Relaunch focused display"
             :action-kind :control-panel
             :command (shell-desktop-command-string "display/control"
                                                    :action :relaunch
                                                    :app-id app-id)
             :action-id (shell-desktop-action-id :control-panel :inspector
                                                 :execution-id execution-id
                                                 :app-id app-id
                                                 :control-action :relaunch)))
      (execution-id
       (list :label "Open focused execution"
             :action-kind :open-panel
             :command (shell-desktop-command-string "open" :execution-id execution-id)
             :action-id (shell-desktop-action-id :open-panel :inspector
                                                 :execution-id execution-id)))
      (t nil))))

(defun shell-desktop-active-panel-summary (desktop-model)
  (let* ((active-panel-id (getf desktop-model :active-panel))
         (panel (getf (getf desktop-model :panels) active-panel-id)))
    (when panel
      (case active-panel-id
        (:workspace
         (list :panel-id :workspace
               :label "Workspace"
               :selected-index (getf panel :selected-index)
               :focus-object-id (getf panel :focus-object-id)
               :execution-id (getf panel :selected-execution-id)))
        (:display
         (list :panel-id :display
               :label "Display"
               :selected-index (getf panel :selected-index)
               :focus-object-id (getf panel :focus-object-id)
               :execution-id (getf panel :selected-execution-id)
               :app-id (getf panel :selected-app-id)
               :status (getf panel :selected-status)
               :display-surface-kind (getf panel :selected-display-surface-kind)))
        (:governance
         (list :panel-id :governance
               :label "Governance"
               :selected-index (getf panel :selected-index)
               :focus-object-id (getf panel :focus-object-id)
               :execution-id (getf panel :focus-object-id)
               :queue-kind (getf panel :selected-queue-kind)
               :title (getf panel :selected-title)))
        (:object-browser
         (list :panel-id :object-browser
               :label "Object browser"
               :selected-index (getf panel :selected-index)
               :focus-object-id (getf panel :focus-object-id)
               :execution-id (getf panel :focus-object-id)
               :object-kind (getf panel :selected-kind)
               :title (getf panel :selected-title)))
        (:inspector
         (list :panel-id :inspector
               :label "Inspector"
               :focus-object-id (getf panel :focus-object-id)
               :execution-id (getf panel :focus-object-id)
               :object-kind (getf panel :object-kind)
               :resolved-via (getf panel :resolved-via)
               :status (getf panel :status)
               :history-count (getf panel :history-count)))
        (otherwise nil)))))

(defun shell-desktop-recommended-action (desktop-model)
  (let* ((active-panel-id (getf desktop-model :active-panel))
         (panel (getf (getf desktop-model :panels) active-panel-id))
         (actions (and panel (getf panel :actions))))
    (labels ((compact-action (label action)
               (and action
                    (list :label label
                          :action-kind (getf action :action-kind)
                          :command (getf action :command)
                          :action-id (getf action :action-id)))))
      (case active-panel-id
        (:display
         (or (compact-action "Show selected display" (getf actions :show))
             (compact-action "Open selected display" (getf actions :open))
             (compact-action "Step display lane" (getf actions :next))))
        (:workspace
         (or (compact-action "Open selected workspace surface" (getf actions :open))
             (compact-action "Select workspace surface" (getf actions :select))))
        (:governance
         (or (compact-action "Open governance item" (getf actions :open))
             (compact-action "Select governance item" (getf actions :select))))
        (:object-browser
         (or (compact-action "Open browser selection" (getf actions :open))
             (compact-action "Select browser item" (getf actions :select))))
        (:inspector
         (or (getf panel :recommended-action)
             (compact-action "Open inspector focus" (getf actions :open))
             (compact-action "Restore inspector focus" (getf actions :restore))))
        (otherwise nil)))))

(defun query-shell-workspace-service (session &key environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (session-summary (service-response-data
                           (query-session-summary-service session)))
         (environment-status (service-response-data
                              (query-environment-status-service active-environment)))
         (surfaces (compact-execution-surfaces-data
                    (service-response-data
                     (query-execution-surfaces-service session
                                                       :environment active-environment))))
         (display-surfaces (service-response-data
                            (query-compatibility-display-surfaces-service session
                                                                          :environment active-environment)))
         (governance-queue (service-response-data
                            (query-shell-governance-queue-service session
                                                                  :environment active-environment)))
         (object-browser (service-response-data
                          (query-shell-object-browser-service session)))
         (focus-object-id (shell-workspace-focus-object-id session
                                                           (list :governance-queue governance-queue
                                                                 :top-surface (getf surfaces :top-surface))
                                                           active-environment))
         (current-display-surface (shell-current-display-surface
                                   (list :display-surfaces display-surfaces)
                                   focus-object-id))
         (current-display-index (and current-display-surface
                                     (or (shell-workspace-display-index
                                          (list :display-surfaces display-surfaces)
                                          (getf current-display-surface :execution-id))
                                         0)))
         (workspace (list :workspace-id (agent-session-id session)
                          :environment-id (environment-id active-environment)
                          :plan (getf session-summary :plan)
                          :operator-status (or (getf session-summary :operator-status)
                                               (getf environment-status :operator-status))
                          :top-surface (getf surfaces :top-surface)
                          :execution-surfaces surfaces
                          :display-surfaces display-surfaces
                          :current-display-surface current-display-surface
                          :display-actions (and current-display-surface
                                                (shell-desktop-panel-actions
                                                 :display
                                                 :index current-display-index
                                                 :execution-id (getf current-display-surface :execution-id)
                                                 :app-id (getf current-display-surface :app-id)
                                                 :supported-actions (getf (getf current-display-surface :control-posture)
                                                                          :supported-actions)))
                          :display-action-ids (and current-display-surface
                                                   (let ((actions (shell-desktop-panel-actions
                                                                   :display
                                                                   :index current-display-index
                                                                   :execution-id (getf current-display-surface :execution-id)
                                                                   :app-id (getf current-display-surface :app-id)
                                                                   :supported-actions (getf (getf current-display-surface :control-posture)
                                                                                            :supported-actions))))
                                                     (list :show (getf (getf actions :show) :action-id)
                                                           :next (getf (getf actions :next) :action-id)
                                                           :previous (getf (getf actions :previous) :action-id)
                                                           :relaunch (getf (getf actions :relaunch) :action-id)
                                                           :stop (getf (getf actions :stop) :action-id))))
                          :current-display-posture (and current-display-surface
                                                        (list :status (getf current-display-surface :status)
                                                              :display-surface-kind (getf current-display-surface :display-surface-kind)
                                                              :source-package-id (getf current-display-surface :source-package-id)
                                                              :controllable-p (getf (getf current-display-surface :control-posture)
                                                                                    :controllable-p)
                                                              :supported-actions (getf (getf current-display-surface :control-posture)
                                                                                       :supported-actions)
                                                              :relaunch-ready-p (not (null (member :relaunch
                                                                                                   (getf (getf current-display-surface :control-posture)
                                                                                                         :supported-actions)
                                                                                                   :test #'eq)))))
                          :display-entry-actions (and current-display-surface
                                                      (getf (find :display
                                                                  (shell-workspace-entry-points
                                                                   (list :top-surface (getf surfaces :top-surface)
                                                                         :display-surfaces display-surfaces
                                                                         :governance-queue governance-queue
                                                                         :object-browser object-browser))
                                                                  :key (lambda (entry)
                                                                         (getf entry :entry-kind))
                                                                  :test #'eq)
                                                            :actions))
                          :display-entry-action-ids (and current-display-surface
                                                         (let ((actions (getf (find :display
                                                                                    (shell-workspace-entry-points
                                                                                     (list :top-surface (getf surfaces :top-surface)
                                                                                           :display-surfaces display-surfaces
                                                                                           :governance-queue governance-queue
                                                                                           :object-browser object-browser))
                                                                                    :key (lambda (entry)
                                                                                           (getf entry :entry-kind))
                                                                                    :test #'eq)
                                                                              :actions)))
                                                           (list :open (getf (getf actions :open) :action-id)
                                                                 :show (getf (getf actions :show) :action-id)
                                                                 :next (getf (getf actions :next) :action-id)
                                                                 :previous (getf (getf actions :previous) :action-id)
                                                                 :relaunch (getf (getf actions :relaunch) :action-id)
                                                                 :stop (getf (getf actions :stop) :action-id))))
                          :current-focus (shell-workspace-current-focus-summary
                                          (list :execution-surfaces surfaces
                                                :display-surfaces display-surfaces
                                                :current-display-surface current-display-surface
                                                :governance-queue governance-queue
                                                :object-browser object-browser
                                                :inspector-focus-object-id focus-object-id))
                          :recommended-action (shell-workspace-recommended-action
                                               (list :execution-surfaces surfaces
                                                     :display-surfaces display-surfaces
                                                     :current-display-surface current-display-surface
                                                     :governance-queue governance-queue
                                                     :object-browser object-browser
                                                     :inspector-focus-object-id focus-object-id
                                                     :display-actions (and current-display-surface
                                                                           (shell-desktop-panel-actions
                                                                            :display
                                                                            :index current-display-index
                                                                            :execution-id (getf current-display-surface :execution-id)
                                                                            :app-id (getf current-display-surface :app-id)
                                                                            :supported-actions (getf (getf current-display-surface :control-posture)
                                                                                                     :supported-actions)))
                                                     :display-entry-actions (and current-display-surface
                                                                                 (getf (find :display
                                                                                             (shell-workspace-entry-points
                                                                                              (list :top-surface (getf surfaces :top-surface)
                                                                                                    :display-surfaces display-surfaces
                                                                                                    :governance-queue governance-queue
                                                                                                    :object-browser object-browser))
                                                                                             :key (lambda (entry)
                                                                                                    (getf entry :entry-kind))
                                                                                             :test #'eq)
                                                                                       :actions))
                                                     :top-surface (getf surfaces :top-surface)))
                          :governance-queue governance-queue
                          :object-browser object-browser
                          :inspector-focus-object-id focus-object-id)))
    (make-service-query-response :shell
                                 :workspace
                                 workspace
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :shell-workspace-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-shell-desktop-model-service (session &key environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (workspace (service-response-data
                     (query-shell-workspace-service session
                                                   :environment active-environment)))
         (surface-list (service-response-data
                        (query-shell-surface-list-service session
                                                          :environment active-environment)))
         (inspector (service-response-data
                     (query-shell-inspector-service session
                                                   nil
                                                   :environment active-environment)))
         (object-browser (getf workspace :object-browser))
         (governance-queue (getf workspace :governance-queue))
         (panels (shell-desktop-panels workspace
                                       surface-list
                                       governance-queue
                                       object-browser
                                       inspector))
         (active-panel (shell-desktop-active-panel session
                                                   workspace
                                                   governance-queue
                                                   object-browser
                                                   panels))
         (desktop-model (list :workspace-id (getf workspace :workspace-id)
                              :environment-id (getf workspace :environment-id)
                              :plan (getf workspace :plan)
                              :focus-object-id (getf workspace :inspector-focus-object-id)
                              :active-panel active-panel
                              :surface-count (getf (getf workspace :execution-surfaces) :count)
                              :display-count (getf (getf workspace :display-surfaces) :count)
                              :governance-count (getf governance-queue :count)
                              :object-group-count (getf object-browser :group-count)
                              :top-surface (getf workspace :top-surface)
                              :top-display-surface (getf (getf workspace :display-surfaces) :top-surface)
                              :top-governance-item (getf governance-queue :top-item)
                              :top-object-group (getf object-browser :top-group)
                              :entry-points (shell-workspace-entry-points workspace)
                              :panels panels
                              :active-panel-summary (shell-desktop-active-panel-summary
                                                     (list :active-panel active-panel
                                                           :panels panels))
                              :recommended-action (shell-desktop-recommended-action
                                                   (list :active-panel active-panel
                                                         :panels panels)))))
    (make-service-query-response :shell
                                 :desktop-model
                                 desktop-model
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :shell-desktop-model-v2
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-shell-desktop-model-service (session &key environment)
  (call-with-shell-actor
   session
   (make-shell-control-request session
                               :desktop-model
                               :shell/desktop-model
                               :payload '()
                               :metadata '())
   (lambda ()
     (query-shell-desktop-model-service session :environment environment))
   :shell/desktop-model
   :desktop-model))

(defun perform-shell-desktop-panel-service (session panel-id &key environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (desktop-model (service-response-data
                         (query-shell-desktop-model-service session
                                                           :environment active-environment))))
    (unless (shell-desktop-panel-available-p (getf desktop-model :panels) panel-id)
      (error "Shell desktop panel ~S is not available in the current workspace" panel-id))
    (set-shell-active-panel-id session panel-id)
    (make-service-command-response :shell
                                   :desktop-panel
                                   (list :active-panel panel-id
                                         :desktop-model (service-response-data
                                                         (query-shell-desktop-model-service
                                                          session
                                                          :environment active-environment)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :shell-desktop-panel-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun command-shell-desktop-panel-service (session panel-id &key environment)
  (call-with-shell-actor
   session
   (make-shell-control-request session
                               :desktop-panel
                               :shell/desktop-panel
                               :payload (list :panel-id panel-id)
                               :metadata (list :panel-id panel-id))
   (lambda ()
     (perform-shell-desktop-panel-service session panel-id :environment environment))
   :shell/desktop-panel
   :desktop-panel
   :metadata (list :panel-id panel-id)))

(defun perform-shell-desktop-select-service (session panel-id &key index execution-id app-id object-kind environment)
  (let ((active-environment (ensure-execution-bound-environment session environment)))
    (case panel-id
      (:workspace
       (let ((result (service-response-data
                      (command-shell-surface-select-service session
                                                            :index index
                                                            :execution-id execution-id
                                                            :environment active-environment
                                                            :source :desktop-select))))
         (set-shell-active-panel-id session :workspace)
         (make-service-command-response :shell
                                        :desktop-select
                                        (list :panel-id :workspace
                                              :selection result
                                              :desktop-model (service-response-data
                                                              (query-shell-desktop-model-service
                                                               session
                                                               :environment active-environment)))
                                         :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-desktop-select-v1
                                                                         :session session
                                                                         :environment active-environment))))
      (:display
       (let ((result (service-response-data
                      (command-shell-display-select-service session
                                                            :index index
                                                            :execution-id execution-id
                                                            :app-id app-id
                                                            :environment active-environment
                                                            :source :desktop-select))))
         (set-shell-active-panel-id session :display)
         (make-service-command-response :shell
                                        :desktop-select
                                        (list :panel-id :display
                                              :selection result
                                              :desktop-model (service-response-data
                                                              (query-shell-desktop-model-service
                                                               session
                                                               :environment active-environment)))
                                        :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-desktop-select-v1
                                                                         :session session
                                                                         :environment active-environment))))
      (:governance
       (let ((result (service-response-data
                      (command-shell-governance-select-service session
                                                               :index (or index 0)
                                                               :environment active-environment))))
         (set-shell-active-panel-id session :governance)
         (make-service-command-response :shell
                                        :desktop-select
                                        (list :panel-id :governance
                                              :selection result
                                              :desktop-model (service-response-data
                                                              (query-shell-desktop-model-service
                                                               session
                                                               :environment active-environment)))
                                        :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-desktop-select-v1
                                                                         :session session
                                                                         :environment active-environment))))
      (:object-browser
       (let* ((desktop-model (service-response-data
                              (query-shell-desktop-model-service session
                                                                :environment active-environment)))
              (resolved-object-kind (or object-kind
                                        (getf (getf (getf desktop-model :panels)
                                                    :object-browser)
                                              :selected-kind))))
         (unless resolved-object-kind
           (error "DESKTOP/SELECT object-browser requires :kind when no selected object group exists"))
         (let ((result (service-response-data
                        (command-shell-object-select-service session
                                                             resolved-object-kind
                                                             :index (or index 0)
                                                             :environment active-environment))))
           (set-shell-active-panel-id session :object-browser)
           (make-service-command-response :shell
                                          :desktop-select
                                          (list :panel-id :object-browser
                                                :object-kind resolved-object-kind
                                                :selection result
                                                :desktop-model (service-response-data
                                                                (query-shell-desktop-model-service
                                                                 session
                                                                 :environment active-environment)))
                                          :metadata (make-service-metadata :authority :environment
                                                                           :command-model :shell-desktop-select-v1
                                                                           :session session
                                                                           :environment active-environment)))))
      (:inspector
       (let ((result (if execution-id
                         (service-response-data
                          (command-shell-focus-set-service session
                                                           execution-id
                                                           :environment active-environment
                                                           :source :desktop-select))
                         (list :focus-object-id (shell-focus-object-id session active-environment)))))
         (unless (getf result :focus-object-id)
           (error "DESKTOP/SELECT inspector requires an existing focus or :execution-id"))
         (set-shell-active-panel-id session :inspector)
         (make-service-command-response :shell
                                        :desktop-select
                                        (list :panel-id :inspector
                                              :selection result
                                              :desktop-model (service-response-data
                                                              (query-shell-desktop-model-service
                                                               session
                                                               :environment active-environment)))
                                        :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-desktop-select-v1
                                                                         :session session
                                                                         :environment active-environment))))
      (otherwise
       (error "Unknown shell desktop panel ~S" panel-id)))))

(defun command-shell-desktop-select-service (session panel-id &key index execution-id app-id object-kind environment)
  (call-with-shell-actor
   session
   (make-shell-control-request session
                               :desktop-select
                               :shell/desktop-select
                               :payload (list :panel-id panel-id
                                              :index index
                                              :execution-id execution-id
                                              :app-id app-id
                                              :object-kind object-kind)
                               :metadata (list :panel-id panel-id))
   (lambda ()
     (perform-shell-desktop-select-service session
                                           panel-id
                                           :index index
                                           :execution-id execution-id
                                           :app-id app-id
                                           :object-kind object-kind
                                           :environment environment))
   :shell/desktop-select
   :desktop-select
   :metadata (list :panel-id panel-id)))

(defun perform-shell-desktop-restore-service (session &key panel-id panel-state environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (normalized-panel-state (normalize-shell-desktop-restore-panel-state panel-id panel-state))
         (resolved-panel-id (getf normalized-panel-state :panel-id)))
    (unless (keywordp resolved-panel-id)
      (error "DESKTOP/RESTORE requires :panel-id or a panel-state with :panel-id"))
    (let ((result
            (case resolved-panel-id
              (:workspace
               (if (or (getf normalized-panel-state :selected-execution-id)
                       (integerp (getf normalized-panel-state :selected-index)))
                   (service-response-data
                    (perform-shell-desktop-select-service session
                                                          :workspace
                                                          :execution-id (getf normalized-panel-state :selected-execution-id)
                                                          :index (getf normalized-panel-state :selected-index)
                                                          :environment active-environment))
                   (service-response-data
                    (perform-shell-desktop-panel-service session
                                                         :workspace
                                                         :environment active-environment))))
              (:display
               (if (or (getf normalized-panel-state :selected-execution-id)
                       (getf normalized-panel-state :selected-app-id)
                       (integerp (getf normalized-panel-state :selected-index)))
                   (service-response-data
                    (perform-shell-desktop-select-service session
                                                          :display
                                                          :execution-id (getf normalized-panel-state :selected-execution-id)
                                                          :app-id (getf normalized-panel-state :selected-app-id)
                                                          :index (getf normalized-panel-state :selected-index)
                                                          :environment active-environment))
                   (service-response-data
                    (perform-shell-desktop-panel-service session
                                                         :display
                                                         :environment active-environment))))
              (:governance
               (if (integerp (getf normalized-panel-state :selected-index))
                   (service-response-data
                    (perform-shell-desktop-select-service session
                                                          :governance
                                                          :index (getf normalized-panel-state :selected-index)
                                                          :environment active-environment))
                   (service-response-data
                    (perform-shell-desktop-panel-service session
                                                         :governance
                                                         :environment active-environment))))
              (:object-browser
               (if (or (getf normalized-panel-state :selected-kind)
                       (integerp (getf normalized-panel-state :selected-index)))
                   (service-response-data
                    (perform-shell-desktop-select-service session
                                                          :object-browser
                                                          :object-kind (getf normalized-panel-state :selected-kind)
                                                          :index (getf normalized-panel-state :selected-index)
                                                          :environment active-environment))
                   (service-response-data
                    (perform-shell-desktop-panel-service session
                                                         :object-browser
                                                         :environment active-environment))))
              (:inspector
               (if (getf normalized-panel-state :focus-object-id)
                   (service-response-data
                    (perform-shell-desktop-select-service session
                                                          :inspector
                                                          :execution-id (getf normalized-panel-state :focus-object-id)
                                                          :environment active-environment))
                   (service-response-data
                    (perform-shell-desktop-panel-service session
                                                         :inspector
                                                         :environment active-environment))))
              (otherwise
               (error "Unknown shell desktop panel ~S" resolved-panel-id)))))
      (make-service-command-response :shell
                                     :desktop-restore
                                     (list :panel-id resolved-panel-id
                                           :panel-state normalized-panel-state
                                           :result result
                                           :desktop-model (service-response-data
                                                           (query-shell-desktop-model-service
                                                            session
                                                            :environment active-environment)))
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :shell-desktop-restore-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun command-shell-desktop-restore-service (session &key panel-id panel-state environment)
  (let ((normalized-panel-state (normalize-shell-desktop-restore-panel-state panel-id panel-state)))
  (call-with-shell-actor
   session
   (make-shell-control-request session
                               :desktop-restore
                               :shell/desktop-restore
                               :payload (list :panel-id (getf normalized-panel-state :panel-id)
                                              :panel-state normalized-panel-state)
                               :metadata (list :panel-id (getf normalized-panel-state :panel-id)))
   (lambda ()
     (perform-shell-desktop-restore-service session
                                            :panel-id (getf normalized-panel-state :panel-id)
                                            :panel-state normalized-panel-state
                                            :environment environment))
   :shell/desktop-restore
   :desktop-restore
   :metadata (list :panel-id (getf normalized-panel-state :panel-id)))))

(defun perform-shell-desktop-action-service (session action &key environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (resolved-action
           (if (getf action :action-id)
               (let* ((desktop-model (service-response-data
                                      (query-shell-desktop-model-service session
                                                                        :environment active-environment)))
                      (matched-action (shell-find-desktop-action-by-id desktop-model
                                                                       (getf action :action-id))))
                 (or matched-action
                     (and (getf action :action-kind)
                          (getf action :panel-id)
                          action)
                     (error "Unknown desktop action id ~S" (getf action :action-id))))
               action))
         (action-kind (getf resolved-action :action-kind))
         (panel-id (getf resolved-action :panel-id))
         (params (getf resolved-action :params))
         (index (or (getf resolved-action :index)
                    (getf params :index)))
         (execution-id (or (getf resolved-action :execution-id)
                           (getf params :execution-id)))
         (app-id (or (getf resolved-action :app-id)
                     (getf params :app-id)))
         (control-action (or (getf resolved-action :control-action)
                             (getf params :control-action)))
         (direction (or (getf resolved-action :direction)
                        (getf params :direction)))
         (object-kind (or (getf resolved-action :object-kind)
                          (getf resolved-action :kind)
                          (getf params :object-kind)
                          (getf params :kind))))
    (unless (and action-kind panel-id)
      (error "DESKTOP/ACTION requires :action-kind and :panel-id, or a resolvable :action-id"))
    (let ((result
            (case action-kind
              (:activate-panel
               (service-response-data
                (perform-shell-desktop-panel-service session
                                                     panel-id
                                                     :environment active-environment)))
              (:select-panel
               (service-response-data
                (perform-shell-desktop-select-service session
                                                      panel-id
                                                      :index index
                                                      :execution-id execution-id
                                                      :app-id app-id
                                                      :object-kind object-kind
                                                      :environment active-environment)))
              (:restore-panel
               (service-response-data
                (perform-shell-desktop-restore-service session
                                                       :panel-id panel-id
                                                        :panel-state (append (list :panel-id panel-id)
                                                                             (when (integerp index)
                                                                               (list :selected-index index))
                                                                            (when execution-id
                                                                              (if (eq panel-id :inspector)
                                                                                  (list :focus-object-id execution-id)
                                                                                  (list :selected-execution-id execution-id)))
                                                                            (when app-id
                                                                              (and (eq panel-id :display)
                                                                                   (list :selected-app-id app-id)))
                                                                            (when object-kind
                                                                              (list :selected-kind object-kind)))
                                                       :environment active-environment)))
              (:show-panel
               (service-response-data
                (case panel-id
                  (:display
                   (query-shell-display-detail-service session
                                                       execution-id
                                                       :app-id app-id
                                                       :environment active-environment))
                  (:inspector
                   (query-shell-inspector-service session
                                                  execution-id
                                                  :environment active-environment))
                  (otherwise
                   (error "Unknown desktop show panel ~S" panel-id)))))
              (:step-panel
               (service-response-data
                (case panel-id
                  (:display
                   (command-shell-display-step-service session
                                                       (or direction :next)
                                                       :environment active-environment))
                  (otherwise
                   (error "Unknown desktop step panel ~S" panel-id)))))
              (:control-panel
               (service-response-data
                (case panel-id
                  (:display
                   (command-shell-display-control-service session
                                                          control-action
                                                          :execution-id execution-id
                                                          :app-id app-id
                                                          :environment active-environment))
                  (otherwise
                   (error "Unknown desktop control panel ~S" panel-id)))))
              (:open-panel
               (service-response-data
                (case panel-id
                  (:workspace
                   (if execution-id
                       (command-shell-open-service session
                                                   :execution-id execution-id
                                                   :environment active-environment
                                                   :source :desktop-action)
                       (command-shell-open-service session
                                                   :surface-index (or index 0)
                                                   :environment active-environment
                                                   :source :desktop-action)))
                  (:governance
                   (command-shell-open-service session
                                               :governance-index (or index 0)
                                               :environment active-environment
                                               :source :desktop-action))
                  (:object-browser
                   (command-shell-open-service session
                                               :object-kind object-kind
                                               :object-index (or index 0)
                                               :environment active-environment
                                               :source :desktop-action))
                  (:inspector
                   (if execution-id
                       (make-service-command-response :shell
                                                      :open
                                                      (list :open-via :inspector
                                                            :focus-object-id execution-id
                                                            :inspection (service-response-data
                                                                         (query-shell-inspector-service
                                                                          session
                                                                          execution-id
                                                                          :environment active-environment))
                                                            :workspace (service-response-data
                                                                        (query-shell-workspace-service
                                                                         session
                                                                         :environment active-environment)))
                                                      :metadata (make-service-metadata :authority :environment
                                                                                       :command-model :shell-open-v1
                                                                                       :session session
                                                                                       :environment active-environment))
                       (make-service-command-response :shell
                                                      :open
                                                      (list :open-via :inspector
                                                            :focus-object-id (shell-focus-object-id session active-environment)
                                                            :inspection (service-response-data
                                                                         (query-shell-inspector-service
                                                                          session
                                                                          nil
                                                                          :environment active-environment))
                                                            :workspace (service-response-data
                                                                        (query-shell-workspace-service
                                                                         session
                                                                         :environment active-environment)))
                                                      :metadata (make-service-metadata :authority :environment
                                                                                       :command-model :shell-open-v1
                                                                                       :session session
                                                                                       :environment active-environment))))
                  (otherwise
                   (error "Unknown desktop open panel ~S" panel-id)))))
              (otherwise
               (error "Unknown desktop action kind ~S" action-kind)))))
      (make-service-command-response :shell
                                     :desktop-action
                                     (list :action resolved-action
                                           :result result
                                           :desktop-model (service-response-data
                                                           (query-shell-desktop-model-service
                                                            session
                                                            :environment active-environment)))
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :shell-desktop-action-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun command-shell-desktop-action-service (session action &key environment)
  (call-with-shell-actor
   session
   (make-shell-control-request session
                               :desktop-action
                               :shell/desktop-control
                               :payload action
                               :metadata (list :panel-id (getf action :panel-id)
                                               :action-id (getf action :action-id)
                                               :action-kind (getf action :action-kind)))
   (lambda ()
     (perform-shell-desktop-action-service session action :environment environment))
   :shell/desktop-control
   :desktop-action
   :metadata (list :panel-id (getf action :panel-id)
                   :action-id (getf action :action-id)
                   :action-kind (getf action :action-kind))))

(defun query-shell-surface-list-service (session &key environment)
  (let* ((workspace (service-response-data
                     (query-shell-workspace-service session :environment environment)))
         (focus-object-id (getf workspace :inspector-focus-object-id))
         (active-environment (ensure-execution-bound-environment session environment)))
    (make-service-query-response :shell
                                 :surface-list
                                 (list :count (getf (getf workspace :execution-surfaces) :count)
                                       :top-surface (getf (getf workspace :execution-surfaces) :top-surface)
                                       :items (shell-workspace-surface-items workspace)
                                       :focus-object-id focus-object-id
                                       :focus-index (shell-workspace-surface-index workspace focus-object-id))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :shell-surface-list-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-shell-display-list-service (session &key environment)
  (let* ((workspace (service-response-data
                     (query-shell-workspace-service session :environment environment)))
         (focus-object-id (getf workspace :inspector-focus-object-id))
         (active-environment (ensure-execution-bound-environment session environment)))
    (make-service-query-response :shell
                                 :display-list
                                 (list :count (getf (getf workspace :display-surfaces) :count)
                                       :top-surface (getf (getf workspace :display-surfaces) :top-surface)
                                       :items (shell-workspace-display-items workspace)
                                       :focus-object-id focus-object-id
                                       :focus-index (shell-workspace-display-index workspace focus-object-id))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :shell-display-list-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun query-shell-display-detail-service (session &rest arguments)
  (let* ((positional-supplied-p (and arguments
                                     (or (null (first arguments))
                                         (stringp (first arguments)))))
         (execution-id (and positional-supplied-p
                            (first arguments)))
         (options (if execution-id
                      (rest arguments)
                      (if positional-supplied-p
                          (rest arguments)
                          arguments)))
         (environment (getf options :environment))
         (app-id (getf options :app-id))
         (active-environment (ensure-execution-bound-environment session environment))
         (workspace (service-response-data
                     (query-shell-workspace-service session :environment active-environment)))
         (selected-surface
           (or (and execution-id
                    (find execution-id
                          (shell-workspace-display-items workspace)
                          :key (lambda (entry) (getf entry :execution-id))
                          :test #'string=))
               (shell-workspace-display-by-app-id workspace app-id)
               (shell-current-display-surface workspace
                                              (or execution-id
                                                  (getf workspace :inspector-focus-object-id))))))
    (unless selected-surface
      (error "Shell display detail has no display surface to inspect"))
    (let ((selected-execution-id (getf selected-surface :execution-id)))
      (unless selected-execution-id
        (error "Shell display detail selected surface has no execution id"))
      (make-service-query-response :shell
                                   :display-show
                                   (list :panel-id :display
                                         :focus-object-id selected-execution-id
                                         :display-surface selected-surface
                                         :workspace workspace
                                         :inspection (service-response-data
                                                      (query-shell-inspector-service
                                                       session
                                                       selected-execution-id
                                                       :environment active-environment))
                                         :lifecycle (service-response-data
                                                     (query-compatibility-execution-detail-service
                                                      session
                                                      selected-execution-id
                                                      :environment active-environment)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :read-model :shell-display-show-v1
                                                                    :session session
                                                                    :environment active-environment)))))

(defun query-shell-inspector-service (session &rest arguments)
  (let* ((positional-supplied-p (and arguments
                                     (or (null (first arguments))
                                         (stringp (first arguments)))))
         (object-id (and positional-supplied-p
                         (first arguments)))
         (options (if object-id
                      (rest arguments)
                      (if positional-supplied-p
                          (rest arguments)
                          arguments)))
         (environment (getf options :environment))
         (active-environment (ensure-execution-bound-environment session environment))
         (workspace (service-response-data
                     (query-shell-workspace-service session :environment active-environment)))
         (focus-object-id (or object-id
                              (getf workspace :inspector-focus-object-id))))
    (if (null focus-object-id)
        (make-service-query-response :shell
                                     :inspector
                                     (list :focus-object-id nil
                                           :workspace-id (getf workspace :workspace-id)
                                           :summary nil
                                           :recommended-action nil)
                                     :metadata (make-service-metadata :authority :environment
                                                                      :read-model :shell-inspector-v1
                                                                      :session session
                                                                      :environment active-environment))
        (let* ((inspection (append (service-response-data
                                    (query-execution-detail-service session
                                                                    focus-object-id
                                                                    :environment active-environment))
                                   (list :focus-object-id focus-object-id
                                         :workspace-id (getf workspace :workspace-id))))
               (summary (shell-inspector-summary inspection))
               (recommended-action (shell-inspector-recommended-action inspection)))
          (make-service-query-response :shell
                                       :inspector
                                       (append inspection
                                               (list :summary summary
                                                     :recommended-action recommended-action))
                                       :metadata (make-service-metadata :authority :environment
                                                                        :read-model :shell-inspector-v1
                                                                        :session session
                                                                        :environment active-environment))))))

(defun command-shell-focus-set-service (session object-id &key environment source)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (handle (ensure-execution-handle object-id active-environment))
         (focus-object-id (execution-handle-execution-id handle)))
    (set-shell-focus-object-id session focus-object-id)
    (set-shell-active-panel-id session :inspector)
    (make-service-command-response :shell
                                   :focus-set
                                   (list :focus-object-id focus-object-id
                                         :source source
                                         :workspace (service-response-data
                                                     (query-shell-workspace-service
                                                      session
                                                      :environment active-environment))
                                         :inspection (service-response-data
                                                      (query-shell-inspector-service
                                                       session
                                                       focus-object-id
                                                       :environment active-environment)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :shell-focus-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun command-shell-surface-select-service (session &key index execution-id environment source)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (workspace (service-response-data
                     (query-shell-workspace-service session :environment active-environment)))
         (surface (cond
                    (execution-id
                     (or (find execution-id
                               (shell-workspace-surface-items workspace)
                               :key #'shell-surface-execution-id
                               :test #'string=)
                         (error "Unknown shell workspace surface execution ~A" execution-id)))
                    (t
                     (nth-shell-workspace-surface workspace (or index 0)))))
         (focus-object-id (shell-surface-execution-id surface)))
    (unless focus-object-id
      (error "Selected shell workspace surface has no execution focus"))
    (set-shell-focus-object-id session focus-object-id)
    (set-shell-active-panel-id session :workspace)
    (make-service-command-response :shell
                                   :surface-select
                                   (list :selected-index (or index
                                                             (shell-workspace-surface-index workspace
                                                                                            focus-object-id))
                                         :selected-surface surface
                                         :focus-object-id focus-object-id
                                         :source source
                                         :workspace (service-response-data
                                                     (query-shell-workspace-service
                                                      session
                                                      :environment active-environment)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :shell-surface-select-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun command-shell-display-select-service (session &key index execution-id app-id environment source)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (workspace (service-response-data
                     (query-shell-workspace-service session :environment active-environment)))
         (selected-surface
           (cond
             (execution-id
              (or (find execution-id
                        (shell-workspace-display-items workspace)
                        :key (lambda (entry) (getf entry :execution-id))
                        :test #'string=)
                  (error "Shell display surface ~S is not present in the current workspace" execution-id)))
             (app-id
              (or (shell-workspace-display-by-app-id workspace app-id)
                  (error "Shell display app ~S is not present in the current workspace" app-id)))
             ((integerp index)
              (nth-shell-workspace-display workspace index))
             (t
              (error "DISPLAY/SELECT requires :index, :execution-id, or :app-id"))))
         (focus-object-id (getf selected-surface :execution-id))
         (focus-index (shell-workspace-display-index workspace focus-object-id)))
    (set-shell-focus-object-id session focus-object-id)
    (set-shell-active-panel-id session :display)
    (make-service-command-response :shell
                                   :display-select
                                   (list :panel-id :display
                                         :selected-index focus-index
                                         :focus-object-id focus-object-id
                                         :source source
                                         :display-surface selected-surface
                                         :workspace (service-response-data
                                                     (query-shell-workspace-service
                                                      session
                                                      :environment active-environment)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :shell-display-select-v1
                                                                    :session session
                                                                    :environment active-environment))))

(defun command-shell-surface-step-service (session direction &key environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (workspace (service-response-data
                     (query-shell-workspace-service session :environment active-environment)))
         (focus-object-id (or (shell-focus-object-id session active-environment)
                              (getf workspace :inspector-focus-object-id))))
    (multiple-value-bind (surface selected-index)
        (step-shell-workspace-surface workspace focus-object-id direction)
      (let ((selected-focus-id (shell-surface-execution-id surface)))
        (unless selected-focus-id
          (error "Stepped shell workspace surface has no execution focus"))
        (set-shell-focus-object-id session selected-focus-id)
        (set-shell-active-panel-id session :workspace)
        (make-service-command-response :shell
                                       :surface-step
                                       (list :direction direction
                                             :selected-index selected-index
                                             :selected-surface surface
                                             :focus-object-id selected-focus-id
                                             :workspace (service-response-data
                                                         (query-shell-workspace-service
                                                          session
                                                          :environment active-environment)))
                                       :metadata (make-service-metadata :authority :environment
                                                                        :command-model :shell-surface-step-v1
                                                                       :session session
                                                                       :environment active-environment))))))

(defun command-shell-display-step-service (session direction &key environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (workspace (service-response-data
                     (query-shell-workspace-service session :environment active-environment)))
         (focus-object-id (or (shell-focus-object-id session active-environment)
                              (getf workspace :inspector-focus-object-id))))
    (multiple-value-bind (surface selected-index)
        (step-shell-workspace-display workspace focus-object-id direction)
      (let ((selected-focus-id (getf surface :execution-id)))
        (unless selected-focus-id
          (error "Stepped shell display surface has no execution focus"))
        (set-shell-focus-object-id session selected-focus-id)
        (set-shell-active-panel-id session :display)
        (make-service-command-response :shell
                                       :display-step
                                       (list :panel-id :display
                                             :direction direction
                                             :selected-index selected-index
                                             :display-surface surface
                                             :focus-object-id selected-focus-id
                                             :workspace (service-response-data
                                                         (query-shell-workspace-service
                                                          session
                                                          :environment active-environment)))
                                        :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-display-step-v1
                                                                         :session session
                                                                         :environment active-environment))))))

(defun command-shell-display-control-service (session action
                                               &key execution-id app-id reason note provider environment status)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (workspace (service-response-data
                     (query-shell-workspace-service session :environment active-environment)))
         (selected-surface
           (if execution-id
               (or (find execution-id
                         (shell-workspace-display-items workspace)
                         :key (lambda (entry) (getf entry :execution-id))
                         :test #'string=)
                   (error "Shell display surface ~S is not present in the current workspace" execution-id))
               (or (and app-id
                        (shell-workspace-display-by-app-id workspace app-id))
                   (shell-current-display-surface workspace
                                                  (or (shell-focus-object-id session active-environment)
                                                      (getf workspace :inspector-focus-object-id)))
                   (error "Shell workspace has no display surface to control"))))
         (selected-execution-id (getf selected-surface :execution-id)))
    (unless selected-execution-id
      (error "Selected shell display surface has no execution id"))
    (set-shell-focus-object-id session selected-execution-id)
    (set-shell-active-panel-id session :display)
    (let* ((control-response (command-execution-control-service session
                                                                selected-execution-id
                                                                action
                                                                :reason reason
                                                                :note note
                                                                :provider provider
                                                                :environment active-environment
                                                                :status status))
           (control-data (service-response-data control-response))
           (controlled-execution-id
             (or (getf (getf control-data :execution) :execution-id)
                 selected-execution-id))
           (post-workspace (service-response-data
                            (query-shell-workspace-service session :environment active-environment)))
           (post-surface (or (find controlled-execution-id
                                   (shell-workspace-display-items post-workspace)
                                   :key (lambda (entry) (getf entry :execution-id))
                                   :test #'string=)
                             (shell-current-display-surface post-workspace controlled-execution-id))))
      (when controlled-execution-id
        (set-shell-focus-object-id session controlled-execution-id))
      (make-service-command-response :shell
                                     :display-control
                                     (list :panel-id :display
                                           :action action
                                           :focus-object-id controlled-execution-id
                                           :display-surface post-surface
                                           :result control-data
                                           :workspace post-workspace)
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :shell-display-control-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun command-shell-open-service (session &key execution-id surface-index display-index display-app-id governance-index object-kind object-index environment source)
  (let ((active-environment (ensure-execution-bound-environment session environment)))
    (cond
      (execution-id
       (let* ((focus-response (command-shell-focus-set-service session
                                                               execution-id
                                                               :environment active-environment
                                                               :source (or source :open)))
              (focus-data (service-response-data focus-response))
              (focus-object-id (getf focus-data :focus-object-id)))
         (make-service-command-response :shell
                                        :open
                                        (list :open-via :execution
                                              :focus-object-id focus-object-id
                                              :workspace (getf focus-data :workspace)
                                              :inspection (service-response-data
                                                           (query-shell-inspector-service
                                                            session
                                                            focus-object-id
                                                            :environment active-environment)))
                                        :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-open-v1
                                                                         :session session
                                                                         :environment active-environment))))
      (surface-index
       (let* ((select-response (command-shell-surface-select-service session
                                                                     :index surface-index
                                                                     :environment active-environment
                                                                     :source (or source :open)))
              (select-data (service-response-data select-response))
              (focus-object-id (getf select-data :focus-object-id)))
         (make-service-command-response :shell
                                        :open
                                        (list :open-via :surface
                                              :focus-object-id focus-object-id
                                              :selected-index (getf select-data :selected-index)
                                              :workspace (getf select-data :workspace)
                                              :inspection (service-response-data
                                                           (query-shell-inspector-service
                                                            session
                                                            focus-object-id
                                                            :environment active-environment)))
                                        :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-open-v1
                                                                         :session session
                                                                         :environment active-environment))))
      (display-index
       (let* ((select-response (command-shell-display-select-service session
                                                                     :index display-index
                                                                     :environment active-environment
                                                                     :source (or source :open)))
              (select-data (service-response-data select-response))
              (focus-object-id (getf select-data :focus-object-id)))
         (make-service-command-response :shell
                                        :open
                                        (list :open-via :display
                                              :focus-object-id focus-object-id
                                              :workspace (getf select-data :workspace)
                                              :inspection (service-response-data
                                                           (query-shell-inspector-service
                                                            session
                                                            focus-object-id
                                                            :environment active-environment)))
                                        :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-open-v1
                                                                         :session session
                                                                         :environment active-environment))))
      (display-app-id
       (let* ((select-response (command-shell-display-select-service session
                                                                     :app-id display-app-id
                                                                     :environment active-environment
                                                                     :source (or source :open)))
              (select-data (service-response-data select-response))
              (focus-object-id (getf select-data :focus-object-id)))
         (make-service-command-response :shell
                                        :open
                                        (list :open-via :display
                                              :focus-object-id focus-object-id
                                              :workspace (getf select-data :workspace)
                                              :inspection (service-response-data
                                                           (query-shell-inspector-service
                                                            session
                                                            focus-object-id
                                                            :environment active-environment)))
                                        :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-open-v1
                                                                         :session session
                                                                         :environment active-environment))))
      (governance-index
       (let* ((select-response (command-shell-governance-select-service session
                                                                        :index governance-index
                                                                        :environment active-environment))
              (select-data (service-response-data select-response))
              (focus-object-id (getf select-data :focus-object-id)))
         (make-service-command-response :shell
                                        :open
                                        (list :open-via :governance
                                              :focus-object-id focus-object-id
                                              :selected-index (getf select-data :selected-index)
                                              :selected-item (getf select-data :selected-item)
                                              :workspace (getf select-data :workspace)
                                              :inspection (service-response-data
                                                           (query-shell-inspector-service
                                                            session
                                                            focus-object-id
                                                            :environment active-environment)))
                                        :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-open-v1
                                                                         :session session
                                                                         :environment active-environment))))
      (object-kind
       (let* ((select-response (command-shell-object-select-service session
                                                                    object-kind
                                                                    :index (or object-index 0)
                                                                    :environment active-environment))
              (select-data (service-response-data select-response))
              (focus-object-id (getf select-data :focus-object-id)))
         (make-service-command-response :shell
                                        :open
                                        (list :open-via :object-browser
                                              :focus-object-id focus-object-id
                                              :object-kind object-kind
                                              :selected-index (getf select-data :selected-index)
                                              :selected-title (getf select-data :selected-title)
                                              :workspace (getf select-data :workspace)
                                              :inspection (service-response-data
                                                           (query-shell-inspector-service
                                                            session
                                                            focus-object-id
                                                            :environment active-environment)))
                                        :metadata (make-service-metadata :authority :environment
                                                                         :command-model :shell-open-v1
                                                                         :session session
                                                                         :environment active-environment))))
      (t
       (error "Shell open requires one of :execution-id, :surface-index, :governance-index, or :object-kind")))))

(defun command-shell-governance-select-service (session &key (index 0) environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (queue (service-response-data
                 (query-shell-governance-queue-service session
                                                       :environment active-environment))))
    (multiple-value-bind (item actual-index focus-object-id)
        (select-shell-governance-item queue index active-environment)
      (set-shell-focus-object-id session focus-object-id)
      (set-shell-active-panel-id session :governance)
      (make-service-command-response :shell
                                     :governance-select
                                     (list :requested-index index
                                           :selected-index actual-index
                                           :selected-item item
                                           :focus-object-id focus-object-id
                                           :workspace (service-response-data
                                                       (query-shell-workspace-service
                                                        session
                                                        :environment active-environment)))
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :shell-governance-select-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun command-shell-object-select-service (session object-kind &key (index 0) environment)
  (let* ((active-environment (ensure-execution-bound-environment session environment))
         (browser (service-response-data
                   (query-shell-object-browser-service session
                                                      :object-kind object-kind
                                                      :environment active-environment)))
         (reference (nth-shell-object-browser-reference browser object-kind index))
         (focus-object-id (shell-object-reference-execution-id reference)))
    (unless focus-object-id
      (error "Selected object-browser entry has no execution focus"))
    (set-shell-focus-object-id session focus-object-id)
    (set-shell-active-panel-id session :object-browser)
    (make-service-command-response :shell
                                   :object-select
                                   (list :object-kind object-kind
                                         :selected-index index
                                         :selected-title (shell-object-reference-title reference)
                                         :focus-object-id focus-object-id
                                         :workspace (service-response-data
                                                     (query-shell-workspace-service
                                                      session
                                                      :environment active-environment)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :command-model :shell-object-select-v1
                                                                    :session session
                                                                    :environment active-environment))))
