(in-package #:sbcl-agent)

(defun runtime-telemetry-pid ()
  #+sbcl
  (multiple-value-bind (pid errno)
      (ignore-errors (sb-unix:unix-getpid))
    (if (and (integerp pid) (or (null errno) (zerop errno)))
        pid
        nil))
  #-sbcl
  nil)

(defun runtime-telemetry-process-state (status)
  (case status
    ((:running :active) :running)
    ((:queued :waiting) :waiting)
    (:blocked :blocked)
    (:completed :complete)
    ((:failed :interrupted) :failed)
    (otherwise :idle)))

(defun runtime-telemetry-primary-handle-linkage (handle)
  (let ((target (and handle (getf handle :target))))
    (list :thread-id (and target (getf target :thread-id))
          :turn-id (and target (getf target :turn-id))
          :incident-id (and target (getf target :incident-id))
          :workflow-record-id (and target (getf target :workflow-record-id))
          :runtime-id (and target (getf target :runtime-id)))))

(defun runtime-telemetry-find-incident-for-work-item (session work-item-id)
  (and work-item-id
       (find work-item-id
             (agent-session-incidents session)
             :key #'incident-work-item-id
             :test #'string=)))

(defun runtime-telemetry-find-task-for-worker (session worker-id)
  (find worker-id
        (agent-session-tasks session)
        :key #'task-worker-id
        :test #'string=
        :from-end t))

(defun runtime-telemetry-find-compatibility-handle (session control-token)
  (declare (ignore session))
  (let ((environment (session-bound-environment session)))
    (and environment
         (find control-token
               (kernel-execution-registry environment)
               :key (lambda (handle)
                      (getf (getf (getf handle :target) :compatibility-execution)
                            :control-token))
               :test #'equal))))

(defun runtime-telemetry-task-process (session task-summary)
  (let* ((status (getf task-summary :status))
         (task-id (getf task-summary :id))
         (task (and task-id
                    (find-task session task-id)))
         (work-item-id (getf task-summary :work-item-id))
         (work-item (and work-item-id
                         (find-work-item session work-item-id)))
         (workflow-record-id (or (and work-item
                                      (work-item-workflow-record-ref work-item))
                                 nil))
         (handles (and task
                       (task-associated-execution-summaries session task)))
         (primary-handle (first handles))
         (linkage (runtime-telemetry-primary-handle-linkage primary-handle))
         (incident (or (and (getf linkage :incident-id)
                            (find-incident session (getf linkage :incident-id)))
                       (runtime-telemetry-find-incident-for-work-item session work-item-id)))
         (thread-id (or (getf linkage :thread-id)
                        (and incident (incident-thread-id incident))))
         (turn-id (or (getf linkage :turn-id)
                      (and incident (incident-turn-id incident))))
         (incident-id (or (getf linkage :incident-id)
                          (and incident (incident-id incident))))
         (goal (and work-item
                    (work-item-goal work-item)))
         (summary (format nil
                          "Governed task status ~A~@[ for work item ~A~]~@[ with incident ~A~]."
                          status
                          work-item-id
                          incident-id)))
    (list :process-id (format nil "task:~A" (getf task-summary :id))
          :kind :task
          :label (if goal
                     (format nil "Task ~A · ~A" (or (getf task-summary :kind) :unknown) goal)
                     (format nil "Task ~A" (or (getf task-summary :kind) :unknown)))
          :state (runtime-telemetry-process-state status)
          :summary summary
          :work-item-id work-item-id
          :thread-id thread-id
          :turn-id turn-id
          :incident-id incident-id
          :workflow-record-id (or (getf linkage :workflow-record-id)
                                  workflow-record-id)
          :elapsed nil
          :pid nil
          :command nil)))

(defun runtime-telemetry-worker-process (session worker-summary)
  (let* ((worker-id (getf worker-summary :id))
         (task (runtime-telemetry-find-task-for-worker session worker-id))
         (task-summary (and task
                            (task-summary task)))
         (work-item-id (and task-summary
                            (getf task-summary :work-item-id)))
         (work-item (and work-item-id
                         (find-work-item session work-item-id)))
         (incident (runtime-telemetry-find-incident-for-work-item session work-item-id))
         (task-linkage (and task
                            (let* ((handles (task-associated-execution-summaries session task))
                                   (primary-handle (first handles)))
                              (runtime-telemetry-primary-handle-linkage primary-handle))))
         (goal (and work-item
                    (work-item-goal work-item))))
    (list :process-id (format nil "worker:~A" worker-id)
          :kind :worker
          :label (if goal
                     (format nil "Worker ~A · ~A" worker-id goal)
                     (format nil "Worker ~A" worker-id))
          :state (if (getf worker-summary :running-p) :running :idle)
          :summary (if (getf worker-summary :running-p)
                       (if work-item-id
                           (format nil "Worker is actively servicing governed work item ~A." work-item-id)
                           "Worker is actively servicing governed runtime work.")
                       "Worker is currently idle.")
          :work-item-id work-item-id
          :thread-id (or (and task-linkage (getf task-linkage :thread-id))
                         (and incident (incident-thread-id incident)))
          :turn-id (or (and task-linkage (getf task-linkage :turn-id))
                       (and incident (incident-turn-id incident)))
          :incident-id (or (and task-linkage (getf task-linkage :incident-id))
                           (and incident (incident-id incident)))
          :workflow-record-id (or (and task-linkage (getf task-linkage :workflow-record-id))
                                  (and work-item (work-item-workflow-record-ref work-item)))
          :elapsed nil
          :pid nil
          :command nil)))

(defun runtime-telemetry-compatibility-processes (session)
  (let ((items '()))
    (maphash (lambda (token record)
               (let* ((handle (runtime-telemetry-find-compatibility-handle session token))
                      (linkage (runtime-telemetry-primary-handle-linkage handle))
                      (app-id (or (getf (getf record :compatibility-target) :app-id)
                                  (getf (getf (getf handle :target) :compatibility-execution) :app-id)))
                      (summary (if (getf linkage :work-item-id)
                                   (format nil "Governed compatibility process for work item ~A." (getf linkage :work-item-id))
                                   "Governed compatibility process registered with the runtime sandbox.")))
                 (push (list :process-id (format nil "compatibility:~A" token)
                             :kind :compatibility-process
                             :label (if app-id
                                        (format nil "Compatibility Process ~A" app-id)
                                        (format nil "Compatibility Process ~A" token))
                             :state (compatibility-process-status token)
                             :summary summary
                             :pid (getf record :pid)
                             :command (when (getf record :argv)
                                        (format nil "~{~A~^ ~}" (getf record :argv)))
                             :work-item-id (getf linkage :work-item-id)
                             :thread-id (getf linkage :thread-id)
                             :turn-id (getf linkage :turn-id)
                             :incident-id (getf linkage :incident-id)
                             :workflow-record-id (getf linkage :workflow-record-id)
                             :elapsed nil
                             :control-token token)
                       items)))
             *compatibility-process-registry*)
    (nreverse items)))

(defun runtime-telemetry-summary-data (session)
  (let* ((runtime-summary (runtime-service-summary-data session))
         (runtime-id (or (getf runtime-summary :runtime-id)
                         (default-runtime-id)))
         (runtime-process
           (list :process-id (format nil "runtime:~A" runtime-id)
                 :kind :runtime
                 :label (or (getf runtime-summary :runtime-id) "runtime")
                 :state :running
                 :summary "Primary SBCL runtime process for the bound environment."
                 :pid (runtime-telemetry-pid)
                 :command "sbcl"
                 :elapsed nil))
         (task-summaries (list-task-summaries session))
         (task-processes (mapcar (lambda (task-summary)
                                   (runtime-telemetry-task-process session task-summary))
                                 task-summaries))
         (worker-processes (mapcar (lambda (worker-summary)
                                     (runtime-telemetry-worker-process session worker-summary))
                                   (list-worker-summaries session)))
         (compatibility-processes (runtime-telemetry-compatibility-processes session))
         (processes (append (list runtime-process)
                            task-processes
                            worker-processes
                            compatibility-processes)))
    (list :runtime-id runtime-id
          :sampled-at (get-universal-time)
          :runtime-pid (runtime-telemetry-pid)
          :cpu (list :utilization-percent nil
                     :core-count 0
                     :load-average-1m nil
                     :load-average-5m nil
                     :load-average-15m nil
                     :summary "Host CPU telemetry is attached by the desktop bridge.")
          :memory (list :rss-mb nil
                        :heap-used-mb nil
                        :heap-total-mb nil
                        :system-used-percent nil
                        :summary "Host memory telemetry is attached by the desktop bridge.")
          :network (list :open-connection-count nil
                         :interface-count 0
                         :summary "Host network telemetry is attached by the desktop bridge.")
          :disk (list :read-kbps nil
                      :write-kbps nil
                      :summary "Host disk telemetry is attached by the desktop bridge.")
          :processes processes
          :activity-summary
          (format nil "~D runtime-linked processes are visible from the governed environment."
                  (length processes)))))

(defun query-runtime-telemetry-service (session)
  (make-service-query-response :runtime
                               :telemetry
                               (runtime-telemetry-summary-data session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-telemetry-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun command-runtime-telemetry-query-service (session)
  (call-with-runtime-actor
   session
   (make-runtime-query-request session
                               :telemetry
                               :runtime/telemetry)
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read current runtime telemetry."
                                    "runtime/telemetry"
                                    :authority :environment))
   :runtime/telemetry
   :telemetry))
