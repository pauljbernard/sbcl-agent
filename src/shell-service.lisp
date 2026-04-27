(in-package #:sbcl-agent)

(defun shell-focus-object-id (session &optional environment)
  (let ((focus-object-id (agent-session-shell-focus-object-id session)))
    (when focus-object-id
      (let ((active-environment (or environment
                                    (session-bound-environment session))))
        (when (and active-environment
                   (ignore-errors
                     (kernel-find-execution focus-object-id active-environment)))
          focus-object-id)))))

(defun set-shell-focus-object-id (session object-id)
  (setf (agent-session-shell-focus-object-id session) object-id)
  object-id)

(defun maybe-set-shell-focus-object-id (session object-id)
  (when object-id
    (set-shell-focus-object-id session object-id)))

(defun valid-shell-desktop-panel-id-p (panel-id)
  (member panel-id '(:workspace :governance :object-browser :inspector) :test #'eq))

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
          :status (getf surface :status))))

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
          :surface (compact-execution-surface-summary
                    (getf item :surface)))))

(defun shell-governance-item-focus-object-id (item &optional environment)
  (or (shell-object-reference-execution-id item)
      (shell-object-reference-execution-id (getf item :surface))
      (let ((handle (or (and (getf item :work-item-id)
                             (first (kernel-execution-summaries-by-target :work-item-id
                                                                          (getf item :work-item-id)
                                                                          environment)))
                        (and (getf item :workflow-record-id)
                             (first (kernel-execution-summaries-by-target :workflow-record-id
                                                                          (getf item :workflow-record-id)
                                                                          environment)))
                        (and (getf item :incident-id)
                             (first (kernel-execution-summaries-by-target :incident-id
                                                                          (getf item :incident-id)
                                                                          environment)))
                        (and (getf item :turn-id)
                             (first (kernel-execution-summaries-by-target :turn-id
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
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
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

(defun shell-entry-point (entry-kind label command &key focus-object-id object-kind)
  (list :entry-kind entry-kind
        :label label
        :command command
        :focus-object-id focus-object-id
        :object-kind object-kind))

(defun shell-workspace-entry-points (workspace)
  (remove nil
          (list (let ((top-surface (getf workspace :top-surface)))
                  (when top-surface
                    (shell-entry-point :surface
                                       "Top surface"
                                       "(open :surface-index 0)"
                                       :focus-object-id (getf top-surface :execution-id)
                                       :object-kind (getf top-surface :object-kind))))
                (let ((top-queue-item (getf (getf workspace :governance-queue) :top-item)))
                  (when top-queue-item
                    (shell-entry-point :governance
                                       "Top governance item"
                                       "(open :governance-index 0)"
                                       :focus-object-id (getf top-queue-item :execution-id)
                                       :object-kind (getf top-queue-item :object-kind))))
                (let* ((object-browser (getf workspace :object-browser))
                       (top-group (and object-browser
                                       (getf object-browser :top-group)))
                       (object-kind (and top-group
                                         (getf top-group :object-kind))))
                  (when object-kind
                    (shell-entry-point :object-browser
                                       "Top object group"
                                       (format nil "(open :object-kind ~S :object-index 0)" object-kind)
                                       :focus-object-id (getf object-browser :focus-object-id)
                                       :object-kind object-kind))))))

(defun shell-desktop-command-string (operator &rest arguments)
  (format nil "(~A~{ ~S~})" operator arguments))

(defun shell-desktop-action-id (action-kind panel-id &key index execution-id object-kind)
  (with-output-to-string (stream)
    (format stream "~(~A~):~(~A~)" panel-id action-kind)
    (when object-kind
      (format stream ":~(~A~)" object-kind))
    (when execution-id
      (format stream ":~A" execution-id))
    (when (integerp index)
      (format stream ":~D" index))))

(defun shell-desktop-action (action-kind panel-id command &rest params)
  (let ((index (getf params :index))
        (execution-id (getf params :execution-id))
        (object-kind (or (getf params :object-kind)
                         (getf params :kind))))
    (list :action-id (shell-desktop-action-id action-kind
                                              panel-id
                                              :index index
                                              :execution-id execution-id
                                              :object-kind object-kind)
          :action-kind action-kind
          :panel-id panel-id
          :command command
          :params params)))

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

(defun shell-desktop-panel-actions (panel-id &key index execution-id object-kind)
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
                                         restore-payload)))
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
                                        :object-kind object-kind)
          :open (shell-desktop-action :open-panel
                                      panel-id
                                      open-command
                                      :index index
                                      :execution-id execution-id
                                      :object-kind object-kind)
          :restore (shell-desktop-action :restore-panel
                                         panel-id
                                         restore-command
                                         :index index
                                         :execution-id execution-id
                                         :object-kind object-kind))))

(defun shell-find-desktop-action-by-id (desktop-model action-id)
  (loop for panel-id in '(:workspace :governance :object-browser :inspector)
        for panel = (getf (getf desktop-model :panels) panel-id)
        for actions = (and panel (getf panel :actions))
        thereis
        (loop for action-key in '(:activate :select :open :restore)
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
                           :actions (shell-desktop-panel-actions :inspector
                                                                 :execution-id (getf inspector :focus-object-id))))))

(defun shell-desktop-default-active-panel (workspace governance-queue object-browser)
  (cond
    ((getf workspace :inspector-focus-object-id) :inspector)
    ((> (or (getf governance-queue :count) 0) 0) :governance)
    ((> (or (getf object-browser :group-count) 0) 0) :object-browser)
    (t :workspace)))

(defun shell-desktop-panel-available-p (panels panel-id)
  (let ((panel (getf panels panel-id)))
    (and panel
         (case panel-id
           (:workspace (> (or (getf panel :count) 0) 0))
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

(defun query-shell-workspace-service (session &key environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (session-summary (service-response-data
                           (query-session-summary-service session)))
         (environment-status (service-response-data
                              (query-environment-status-service active-environment)))
         (surfaces (compact-execution-surfaces-data
                    (service-response-data
                     (query-execution-surfaces-service session
                                                       :environment active-environment))))
         (governance-queue (service-response-data
                            (query-shell-governance-queue-service session
                                                                  :environment active-environment)))
         (object-browser (service-response-data
                          (query-shell-object-browser-service session)))
         (focus-object-id (shell-workspace-focus-object-id session
                                                           (list :governance-queue governance-queue
                                                                 :top-surface (getf surfaces :top-surface))
                                                           active-environment))
         (workspace (list :workspace-id (agent-session-id session)
                          :environment-id (environment-id active-environment)
                          :plan (getf session-summary :plan)
                          :operator-status (or (getf session-summary :operator-status)
                                               (getf environment-status :operator-status))
                          :top-surface (getf surfaces :top-surface)
                          :execution-surfaces surfaces
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
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
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
         (desktop-model (list :workspace-id (getf workspace :workspace-id)
                              :environment-id (getf workspace :environment-id)
                              :plan (getf workspace :plan)
                              :focus-object-id (getf workspace :inspector-focus-object-id)
                              :active-panel (shell-desktop-active-panel session
                                                                        workspace
                                                                        governance-queue
                                                                        object-browser
                                                                        panels)
                              :surface-count (getf (getf workspace :execution-surfaces) :count)
                              :governance-count (getf governance-queue :count)
                              :object-group-count (getf object-browser :group-count)
                              :top-surface (getf workspace :top-surface)
                              :top-governance-item (getf governance-queue :top-item)
                              :top-object-group (getf object-browser :top-group)
                              :entry-points (shell-workspace-entry-points workspace)
                              :panels panels
                              :workspace workspace
                              :surface-list surface-list
                              :inspector inspector)))
    (make-service-query-response :shell
                                 :desktop-model
                                 desktop-model
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :shell-desktop-model-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-shell-desktop-panel-service (session panel-id &key environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
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

(defun command-shell-desktop-select-service (session panel-id &key index execution-id object-kind environment)
  (let ((active-environment (ensure-kernel-bound-environment session environment)))
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

(defun command-shell-desktop-restore-service (session &key panel-id panel-state environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (resolved-panel-id (or panel-id
                                (getf panel-state :panel-id))))
    (unless (keywordp resolved-panel-id)
      (error "DESKTOP/RESTORE requires :panel-id or a panel-state with :panel-id"))
    (let ((result
            (case resolved-panel-id
              (:workspace
               (if (or (getf panel-state :selected-execution-id)
                       (integerp (getf panel-state :selected-index)))
                   (service-response-data
                    (command-shell-desktop-select-service session
                                                          :workspace
                                                          :execution-id (getf panel-state :selected-execution-id)
                                                          :index (getf panel-state :selected-index)
                                                          :environment active-environment))
                   (service-response-data
                    (command-shell-desktop-panel-service session
                                                         :workspace
                                                         :environment active-environment))))
              (:governance
               (if (integerp (getf panel-state :selected-index))
                   (service-response-data
                    (command-shell-desktop-select-service session
                                                          :governance
                                                          :index (getf panel-state :selected-index)
                                                          :environment active-environment))
                   (service-response-data
                    (command-shell-desktop-panel-service session
                                                         :governance
                                                         :environment active-environment))))
              (:object-browser
               (if (or (getf panel-state :selected-kind)
                       (integerp (getf panel-state :selected-index)))
                   (service-response-data
                    (command-shell-desktop-select-service session
                                                          :object-browser
                                                          :object-kind (getf panel-state :selected-kind)
                                                          :index (getf panel-state :selected-index)
                                                          :environment active-environment))
                   (service-response-data
                    (command-shell-desktop-panel-service session
                                                         :object-browser
                                                         :environment active-environment))))
              (:inspector
               (if (getf panel-state :focus-object-id)
                   (service-response-data
                    (command-shell-desktop-select-service session
                                                          :inspector
                                                          :execution-id (getf panel-state :focus-object-id)
                                                          :environment active-environment))
                   (service-response-data
                    (command-shell-desktop-panel-service session
                                                         :inspector
                                                         :environment active-environment))))
              (otherwise
               (error "Unknown shell desktop panel ~S" resolved-panel-id)))))
      (make-service-command-response :shell
                                     :desktop-restore
                                     (list :panel-id resolved-panel-id
                                           :panel-state panel-state
                                           :result result
                                           :desktop-model (service-response-data
                                                           (query-shell-desktop-model-service
                                                            session
                                                            :environment active-environment)))
                                     :metadata (make-service-metadata :authority :environment
                                                                      :command-model :shell-desktop-restore-v1
                                                                      :session session
                                                                      :environment active-environment)))))

(defun command-shell-desktop-action-service (session action &key environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (resolved-action
           (if (getf action :action-id)
               (let* ((desktop-model (service-response-data
                                      (query-shell-desktop-model-service session
                                                                        :environment active-environment)))
                      (matched-action (shell-find-desktop-action-by-id desktop-model
                                                                       (getf action :action-id))))
                 (or matched-action
                     (error "Unknown desktop action id ~S" (getf action :action-id))))
               action))
         (action-kind (getf resolved-action :action-kind))
         (panel-id (getf resolved-action :panel-id))
         (index (getf resolved-action :index))
         (execution-id (getf resolved-action :execution-id))
         (object-kind (or (getf resolved-action :object-kind)
                          (getf resolved-action :kind))))
    (unless (and action-kind panel-id)
      (error "DESKTOP/ACTION requires :action-kind and :panel-id, or a resolvable :action-id"))
    (let ((result
            (case action-kind
              (:activate-panel
               (service-response-data
                (command-shell-desktop-panel-service session
                                                     panel-id
                                                     :environment active-environment)))
              (:select-panel
               (service-response-data
                (command-shell-desktop-select-service session
                                                      panel-id
                                                      :index index
                                                      :execution-id execution-id
                                                      :object-kind object-kind
                                                      :environment active-environment)))
              (:restore-panel
               (service-response-data
                (command-shell-desktop-restore-service session
                                                       :panel-id panel-id
                                                       :panel-state (append (list :panel-id panel-id)
                                                                            (when (integerp index)
                                                                              (list :selected-index index))
                                                                            (when execution-id
                                                                              (if (eq panel-id :inspector)
                                                                                  (list :focus-object-id execution-id)
                                                                                  (list :selected-execution-id execution-id)))
                                                                            (when object-kind
                                                                              (list :selected-kind object-kind)))
                                                       :environment active-environment)))
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

(defun query-shell-surface-list-service (session &key environment)
  (let* ((workspace (service-response-data
                     (query-shell-workspace-service session :environment environment)))
         (focus-object-id (getf workspace :inspector-focus-object-id)))
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
                                                                  :environment (or environment
                                                                                   (session-bound-environment session))))))

(defun query-shell-inspector-service (session &optional object-id &key environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (workspace (service-response-data
                     (query-shell-workspace-service session :environment active-environment)))
         (focus-object-id (or object-id
                              (getf workspace :inspector-focus-object-id))))
    (unless focus-object-id
      (error "Shell inspector has no focus object to inspect"))
    (make-service-query-response :shell
                                 :inspector
                                 (append (service-response-data
                                          (query-kernel-inspect-service session
                                                                        focus-object-id
                                                                        :environment active-environment))
                                         (list :focus-object-id focus-object-id
                                               :workspace-id (getf workspace :workspace-id)))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :shell-inspector-v1
                                                                  :session session
                                                                  :environment active-environment))))

(defun command-shell-focus-set-service (session object-id &key environment source)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
         (handle (ensure-kernel-handle object-id active-environment))
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
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
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

(defun command-shell-surface-step-service (session direction &key environment)
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
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

(defun command-shell-open-service (session &key execution-id surface-index governance-index object-kind object-index environment source)
  (let ((active-environment (ensure-kernel-bound-environment session environment)))
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
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
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
  (let* ((active-environment (ensure-kernel-bound-environment session environment))
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
