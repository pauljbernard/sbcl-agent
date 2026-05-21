(in-package #:sbcl-agent/tests)

(defun measure-seconds (thunk)
  (let ((start (get-internal-real-time)))
    (funcall thunk)
    (/ (- (get-internal-real-time) start)
       internal-time-units-per-second)))

(defun sample-summary (samples)
  (let* ((count (length samples))
         (sorted (sort (copy-seq samples) #'<))
         (sum (reduce #'+ samples :initial-value 0.0)))
    (list :count count
          :min-seconds (and sorted (first sorted))
          :max-seconds (and sorted (car (last sorted)))
          :avg-seconds (if (plusp count) (/ sum count) 0.0)
          :samples-seconds samples)))

(defun benchmark-value-ms (summary key)
  (* 1000.0 (or (getf summary key) 0.0)))

(defun make-performance-session (&key (cwd (current-workspace-root)))
  (make-test-session :cwd cwd))

(defun populate-session-with-turns (session provider count)
  (dotimes (index count session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command
      `(say ,(format nil "detail timing turn ~D" index)))
     provider
     session)))

(defun benchmark-say-turn-latency (&key (iterations 5))
  (let ((provider (make-test-provider))
        (session (make-performance-session))
        (samples '()))
    (dotimes (index iterations)
      (push (measure-seconds
             (lambda ()
               (sbcl-agent::execute-command
                (sbcl-agent::normalize-form-command
                 `(say ,(format nil "latency timing turn ~D" index)))
                provider
                session)))
            samples))
    (sample-summary (nreverse samples))))

(defun benchmark-thread-detail-latency (&key (turn-count 100) (iterations 5))
  (let ((provider (make-test-provider))
        (session (make-performance-session))
        (samples '())
        (batch-size 50))
    (populate-session-with-turns session provider turn-count)
    (dotimes (index iterations)
      (push (/ (measure-seconds
                (lambda ()
                  (dotimes (batch-index batch-size)
                    (sbcl-agent::thread-detail session))))
               batch-size)
            samples))
    (sample-summary (nreverse samples))))

(defun benchmark-turn-detail-latency (&key (turn-count 100) (iterations 5))
  (let ((provider (make-test-provider))
        (session (make-performance-session))
        (samples '())
        (batch-size 50))
    (populate-session-with-turns session provider turn-count)
    (dotimes (index iterations)
      (push (/ (measure-seconds
                (lambda ()
                  (dotimes (batch-index batch-size)
                    (sbcl-agent::turn-detail session))))
               batch-size)
            samples))
    (sample-summary (nreverse samples))))

(defun benchmark-session-save-load (&key (turn-count 100))
  (let* ((provider (make-test-provider))
         (session (make-performance-session))
         (root (make-temporary-directory "/tmp/sbcl-agent-perf-session-XXXXXX"))
         (path (merge-pathnames #P"session.sexp" root)))
    (populate-session-with-turns session provider turn-count)
    (let ((save-seconds (measure-seconds (lambda ()
                                           (sbcl-agent::save-session session (namestring path)))))
          (load-seconds (measure-seconds (lambda ()
                                           (sbcl-agent::load-session (namestring path))))))
      (list :save-seconds save-seconds
            :load-seconds load-seconds
            :total-seconds (+ save-seconds load-seconds)
            :turn-count turn-count
            :path (namestring path)))))

(defun benchmark-environment-save-load (&key (turn-count 100))
  (let* ((provider (make-test-provider))
         (session (make-performance-session))
         (root (make-temporary-directory "/tmp/sbcl-agent-perf-environment-XXXXXX"))
         (path (merge-pathnames #P"environment.sexp" root)))
    (populate-session-with-turns session provider turn-count)
    (let* ((environment (sbcl-agent::make-default-environment
                         :storage-root (sbcl-agent::agent-session-cwd session)
                         :session session))
           (save-seconds (measure-seconds (lambda ()
                                           (sbcl-agent::save-environment environment (namestring path)))))
           (load-seconds (measure-seconds (lambda ()
                                           (sbcl-agent::load-environment (namestring path))))))
      (list :save-seconds save-seconds
            :load-seconds load-seconds
            :total-seconds (+ save-seconds load-seconds)
            :turn-count turn-count
            :path (namestring path)))))

(defun benchmark-desktop-preferences-save-load ()
  (let* ((session (make-performance-session))
         (environment (sbcl-agent::make-default-environment
                       :storage-root (sbcl-agent::agent-session-cwd session)
                       :session session))
         (root (make-temporary-directory "/tmp/sbcl-agent-perf-desktop-preferences-XXXXXX"))
         (path (merge-pathnames #P"environment.sexp" root))
         (preferences
           '(:theme-preference "dark"
             :desktop-surface-view
             (:tooltip-scale-percent 112
              :control-icon-scale-percent 106
              :dock-icon-scale-percent 104
              :conversation-text-scale-percent 155)
             :conversation-draft "performance benchmark draft"
             :selected-conversation-thread-by-project
             (:project-alpha "thread-1")
             :workspace-package-by-project
             (:project-alpha "SBCL-AGENT-USER")
             :workspace-draft-by-project
             (:project-alpha "(defparameter *perf* t)")
             :workspace-result-by-project
             (:project-alpha (:data (:summary "ok")))
             :workspace-history-by-project
             (:project-alpha ((:input "(+ 1 2)" :output "3")
                              (:input "(+ 2 3)" :output "5")))
             :selected-editor-buffer-id-by-project
             (:project-alpha "buffer-main")
             :editor-buffers-by-project
             (:project-alpha
              ((:buffer-id "buffer-main"
                :title "Main"
                :package-name "SBCL-AGENT-USER"
                :draft-form "(print :perf)"
                :baseline-draft "(print :seed)"
                :last-summary "ready"
                :runtime-summary (:runtime-id "runtime-1")))))))
    (sbcl-agent::set-environment-desktop-preferences environment preferences)
    (let ((save-seconds (measure-seconds (lambda ()
                                           (sbcl-agent::save-environment environment (namestring path)))))
          (load-seconds (measure-seconds (lambda ()
                                           (sbcl-agent::load-environment (namestring path))))))
      (list :save-seconds save-seconds
            :load-seconds load-seconds
            :total-seconds (+ save-seconds load-seconds)
            :path (namestring path)))))

(defun benchmark-environment-image-save-load ()
  (let* ((session (make-performance-session))
         (environment (sbcl-agent::make-default-environment
                       :storage-root (sbcl-agent::agent-session-cwd session)
                       :session session)))
    (sbcl-agent::set-environment-metadata-value
     environment
     :compatibility-apps
     '((:app-id "linux.vscode")))
    (let ((save-seconds (measure-seconds
                         (lambda ()
                           (sbcl-agent::save-environment-as-image
                            "perf-image"
                            :overwrite t
                            :environment environment))))
          (load-seconds (measure-seconds
                         (lambda ()
                           (sbcl-agent::load-environment-image
                            "perf-image"
                            environment)))))
      (list :save-seconds save-seconds
            :load-seconds load-seconds
            :total-seconds (+ save-seconds load-seconds)))))

(defun benchmark-trace-link-save-load ()
  (let* ((root (make-temporary-directory "/tmp/sbcl-agent-perf-trace-links-XXXXXX"))
         (root-path (namestring root))
         (path (merge-pathnames #P"environment.sexp" root))
         (session (sbcl-agent::make-default-session :cwd root-path))
         (environment (sbcl-agent::make-default-environment
                       :storage-root root-path
                       :session session))
         (project (sbcl-agent::create-project-record session
                                                     :title "Trace Perf"
                                                     :summary "Trace save/load benchmark."))
         (project-id (sbcl-agent::project-record-id project)))
    (dotimes (index 50)
      (let ((work-item (sbcl-agent::create-work-item session
                                                     (format nil "Trace benchmark work item ~D" index))))
        (sbcl-agent::command-project-bind-work-item-service session
                                                            (sbcl-agent::work-item-id work-item)
                                                            :project-id project-id)
        (sbcl-agent::command-trace-link-create-service
         session
         :relation :validated-by-testing-harness
         :source-kind :work-item
         :source-id (sbcl-agent::work-item-id work-item)
         :target-kind :testing-harness
         :target-id "full-suite"
         :metadata (list :benchmark-index index))))
    (let ((save-seconds (measure-seconds (lambda ()
                                           (sbcl-agent::save-environment environment (namestring path)))))
          (load-seconds (measure-seconds (lambda ()
                                           (sbcl-agent::load-environment (namestring path))))))
      (list :save-seconds save-seconds
            :load-seconds load-seconds
            :total-seconds (+ save-seconds load-seconds)
            :trace-link-count (length (sbcl-agent::list-trace-links session))))))

(defun benchmark-thread-scaling (&key (turn-counts '(25 100 250)))
  (mapcar (lambda (turn-count)
            (let ((summary (benchmark-thread-detail-latency :turn-count turn-count :iterations 3)))
              (list :turn-count turn-count
                    :avg-thread-detail-ms (benchmark-value-ms summary :avg-seconds)
                    :max-thread-detail-ms (benchmark-value-ms summary :max-seconds))))
          turn-counts))

(defun benchmark-persistence-scaling (&key (turn-counts '(25 100 250)))
  (mapcar (lambda (turn-count)
            (let ((session-summary (benchmark-session-save-load :turn-count turn-count))
                  (environment-summary (benchmark-environment-save-load :turn-count turn-count)))
              (list :turn-count turn-count
                    :session-total-ms (* 1000.0 (getf session-summary :total-seconds))
                    :environment-total-ms (* 1000.0 (getf environment-summary :total-seconds)))))
          turn-counts))

(defun benchmark-concurrency-core-dispatch-latency (&key (iterations 100))
  (let ((samples '()))
    (loop repeat iterations
          do (push (measure-seconds
                    (lambda ()
                      (sbcl-agent::call-with-concurrency-core-executor
                       (lambda ()
                         :ok))))
                   samples))
    (sample-summary (nreverse samples))))

(defun benchmark-runtime-eval-read-latency (&key (iterations 25))
  (let ((session (make-performance-session))
        (samples '()))
    (sbcl-agent::bind-session-to-environment
     session
     (sbcl-agent::make-default-environment :session session))
    (loop repeat iterations
          do (push (measure-seconds
                    (lambda ()
                      (sbcl-agent::command-runtime-eval-service
                       session
                       "(+ 1 2)"
                       :package "SBCL-AGENT-USER"
                       :mutating nil)))
                   samples))
    (sample-summary (nreverse samples))))

(defun benchmark-actor-dispatch-latency (&key (iterations 50))
  (let* ((session (make-performance-session))
         (environment (sbcl-agent::make-default-environment :session session))
         (samples '()))
    (sbcl-agent::bind-session-to-environment session environment)
    (unwind-protect
        (progn
          (sbcl-agent::start-actor-thread-pool session)
          (loop repeat iterations
                do (push (measure-seconds
                          (lambda ()
                            (sbcl-agent::submit-actor-execution-job
                             session
                             "actor/runtime"
                             (lambda () :ok)
                             :context (sbcl-agent::make-actor-execution-context
                                       :actor-id "actor/runtime"
                                       :capability :runtime/benchmark
                                       :authority :benchmark
                                       :target :runtime
                                       :operation :benchmark))))
                         samples))
          (sample-summary (nreverse samples)))
      (sbcl-agent::stop-actor-thread-pool session))))

(defun benchmark-actor-queue-throughput (&key (job-count 100))
  (let* ((session (make-performance-session))
         (environment (sbcl-agent::make-default-environment :session session)))
    (sbcl-agent::bind-session-to-environment session environment)
    (unwind-protect
        (progn
          (sbcl-agent::start-actor-thread-pool session)
          (let* ((elapsed-seconds
                   (measure-seconds
                    (lambda ()
                      (let ((jobs
                              (loop repeat job-count
                                    collect
                                    (sbcl-agent::enqueue-actor-execution-job
                                     session
                                     "actor/runtime"
                                     (lambda () :ok)
                                     :context (sbcl-agent::make-actor-execution-context
                                               :actor-id "actor/runtime"
                                               :capability :runtime/benchmark
                                               :authority :benchmark
                                               :target :runtime
                                               :operation :benchmark)))))
                        (dolist (job jobs)
                          (sbcl-agent::await-actor-execution-job job))))))
                 (jobs-per-second (if (plusp elapsed-seconds)
                                      (/ job-count elapsed-seconds)
                                      0.0)))
            (list :job-count job-count
                  :elapsed-seconds elapsed-seconds
                  :jobs-per-second jobs-per-second)))
      (sbcl-agent::stop-actor-thread-pool session))))

(defun benchmark-actor-multi-actor-throughput (&key (jobs-per-actor 25))
  (let* ((session (make-performance-session))
         (environment (sbcl-agent::make-default-environment :session session))
         (actor-ids '("actor/runtime" "actor/workflow" "actor/project" "actor/environment")))
    (sbcl-agent::bind-session-to-environment session environment)
    (unwind-protect
        (progn
          (sbcl-agent::start-actor-thread-pool session :pool-size 4)
          (let* ((job-count (* jobs-per-actor (length actor-ids)))
                 (elapsed-seconds
                   (measure-seconds
                    (lambda ()
                      (let ((jobs
                              (loop for actor-id in actor-ids
                                    append
                                    (loop repeat jobs-per-actor
                                          collect
                                          (sbcl-agent::enqueue-actor-execution-job
                                           session
                                           actor-id
                                           (lambda () :ok)
                                           :context (sbcl-agent::make-actor-execution-context
                                                     :actor-id actor-id
                                                     :capability :runtime/benchmark
                                                     :authority :benchmark
                                                     :target :actor-system
                                                     :operation :benchmark))))))
                        (dolist (job jobs)
                          (sbcl-agent::await-actor-execution-job job))))))
                 (jobs-per-second (if (plusp elapsed-seconds)
                                      (/ job-count elapsed-seconds)
                                      0.0)))
            (list :actor-count (length actor-ids)
                  :jobs-per-actor jobs-per-actor
                  :job-count job-count
                  :elapsed-seconds elapsed-seconds
                  :jobs-per-second jobs-per-second)))
      (sbcl-agent::stop-actor-thread-pool session))))

(defun benchmark-actor-system-panel-latency (&key (iterations 10))
  (let* ((session (make-performance-session))
         (environment (sbcl-agent::make-default-environment :session session))
         (samples '()))
    (sbcl-agent::bind-session-to-environment session environment)
    (sbcl-agent::command-runtime-eval-service
     session
     "(defparameter *actor-system-panel-benchmark* 1)"
     :package "SBCL-AGENT-USER")
    (loop repeat iterations
          do (push (measure-seconds
                    (lambda ()
                      (sbcl-agent::query-desktop-task-actor-system-panel-service session)))
                   samples))
    (sample-summary (nreverse samples))))

(defun benchmark-mixed-load-contention (&key (read-count 25)
                                             (write-count 10)
                                             (actor-job-count 25))
  (let* ((session (make-performance-session))
         (environment (sbcl-agent::make-default-environment :session session))
         (read-samples '())
         (actor-samples '()))
    (sbcl-agent::bind-session-to-environment session environment)
    (unwind-protect
        (progn
          (sbcl-agent::start-actor-thread-pool session :pool-size 4)
          (let ((elapsed-seconds
                  (measure-seconds
                   (lambda ()
                     (let ((write-thread
                             (sb-thread:make-thread
                              (lambda ()
                                (loop repeat write-count
                                      do (sbcl-agent::call-with-concurrency-core-policy
                                          :serialized-write
                                          (lambda ()
                                            (sleep 0.01)
                                            :ok)
                                          :lock-key :mixed-load-write)))
                              :name "mixed-load-write"))
                           (read-thread
                             (sb-thread:make-thread
                              (lambda ()
                                (loop repeat read-count
                                      do (push (measure-seconds
                                                (lambda ()
                                                  (sbcl-agent::call-with-concurrency-core-policy
                                                   :concurrent-read
                                                   (lambda ()
                                                     :ok))))
                                               read-samples)))
                              :name "mixed-load-read"))
                           (actor-thread
                             (sb-thread:make-thread
                              (lambda ()
                                (loop repeat actor-job-count
                                      do (push (measure-seconds
                                                (lambda ()
                                                  (sbcl-agent::submit-actor-execution-job
                                                   session
                                                   "actor/runtime"
                                                   (lambda () :ok)
                                                   :context (sbcl-agent::make-actor-execution-context
                                                             :actor-id "actor/runtime"
                                                             :capability :runtime/benchmark
                                                             :authority :benchmark
                                                             :target :runtime
                                                             :operation :mixed-load))))
                                               actor-samples)))
                              :name "mixed-load-actor")))
                       (sb-thread:join-thread write-thread)
                       (sb-thread:join-thread read-thread)
                       (sb-thread:join-thread actor-thread))))))
            (list :read-latency (sample-summary (nreverse read-samples))
                  :actor-dispatch-latency (sample-summary (nreverse actor-samples))
                  :elapsed-seconds elapsed-seconds
                  :read-count read-count
                  :write-count write-count
                  :actor-job-count actor-job-count)))
      (sbcl-agent::stop-actor-thread-pool session))))

(defun parse-budget-ms (name)
  (let ((value (uiop:getenv name)))
    (and value
         (ignore-errors
           (parse-integer value)))))

(defun enforce-benchmark-budget (metric summary env-var)
  (let ((budget-ms (parse-budget-ms env-var))
        (actual-ms (benchmark-value-ms summary :avg-seconds)))
    (when (and budget-ms (> actual-ms budget-ms))
      (error "Performance budget exceeded for ~A: avg ~,2F ms > ~D ms (~A)"
             metric actual-ms budget-ms env-var))))

(defun enforce-nested-benchmark-budget (metric report summary-key env-var)
  (let ((summary (and report (getf report summary-key))))
    (when summary
      (enforce-benchmark-budget metric summary env-var))))

(defun ensure-performance-report-directory ()
  (let ((root (merge-pathnames #P"tmp/performance/"
                               (uiop:ensure-directory-pathname
                                (uiop:getcwd)))))
    (ensure-directories-exist root)
    root))

(defun write-performance-report (report)
  (let* ((root (ensure-performance-report-directory))
         (path (merge-pathnames #P"latest.sexp" root)))
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (let ((*print-circle* t)
            (*print-pretty* t))
        (write report :stream stream)))
    path))

(defun print-performance-summary (report)
  (flet ((summary-line (label summary)
           (if summary
               (format t "~A avg=~,2Fms min=~,2Fms max=~,2Fms samples=~D~%"
                       label
                       (benchmark-value-ms summary :avg-seconds)
                       (benchmark-value-ms summary :min-seconds)
                       (benchmark-value-ms summary :max-seconds)
                       (or (getf summary :count) 0))
               (format t "~A n/a~%" label))))
    (summary-line "say-turn-latency>" (getf report :say-turn-latency))
    (summary-line "thread-detail-latency>" (getf report :thread-detail-latency))
    (summary-line "turn-detail-latency>" (getf report :turn-detail-latency))
    (summary-line "concurrency-core-dispatch-latency>" (getf report :concurrency-core-dispatch-latency))
    (summary-line "runtime-eval-read-latency>" (getf report :runtime-eval-read-latency))
    (summary-line "actor-dispatch-latency>" (getf report :actor-dispatch-latency))
    (summary-line "mixed-load-read-latency>" (getf (getf report :mixed-load-contention) :read-latency))
    (summary-line "mixed-load-actor-dispatch-latency>"
                  (getf (getf report :mixed-load-contention) :actor-dispatch-latency))
    (let ((session-save-load (getf report :session-save-load))
          (environment-save-load (getf report :environment-save-load))
          (desktop-preferences-save-load (getf report :desktop-preferences-save-load))
          (environment-image-save-load (getf report :environment-image-save-load))
          (trace-link-save-load (getf report :trace-link-save-load))
          (actor-queue-throughput (getf report :actor-queue-throughput))
          (mixed-load-contention (getf report :mixed-load-contention)))
      (when session-save-load
        (format t "session-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
                (* 1000.0 (getf session-save-load :save-seconds))
                (* 1000.0 (getf session-save-load :load-seconds))
                (* 1000.0 (getf session-save-load :total-seconds))))
      (when environment-save-load
        (format t "environment-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
                (* 1000.0 (getf environment-save-load :save-seconds))
                (* 1000.0 (getf environment-save-load :load-seconds))
                (* 1000.0 (getf environment-save-load :total-seconds))))
      (when desktop-preferences-save-load
        (format t "desktop-preferences-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
                (* 1000.0 (getf desktop-preferences-save-load :save-seconds))
                (* 1000.0 (getf desktop-preferences-save-load :load-seconds))
                (* 1000.0 (getf desktop-preferences-save-load :total-seconds))))
      (when environment-image-save-load
        (format t "environment-image-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
                (* 1000.0 (getf environment-image-save-load :save-seconds))
                (* 1000.0 (getf environment-image-save-load :load-seconds))
                (* 1000.0 (getf environment-image-save-load :total-seconds))))
      (when trace-link-save-load
        (format t "trace-link-save-load> save=~,2Fms load=~,2Fms total=~,2Fms traces=~D~%"
                (* 1000.0 (getf trace-link-save-load :save-seconds))
                (* 1000.0 (getf trace-link-save-load :load-seconds))
                (* 1000.0 (getf trace-link-save-load :total-seconds))
                (or (getf trace-link-save-load :trace-link-count) 0)))
      (when actor-queue-throughput
        (format t "actor-queue-throughput> jobs=~D elapsed=~,2Fms jobs-per-second=~,2F~%"
                (or (getf actor-queue-throughput :job-count) 0)
                (* 1000.0 (or (getf actor-queue-throughput :elapsed-seconds) 0.0))
                (or (getf actor-queue-throughput :jobs-per-second) 0.0)))
      (when (getf report :actor-multi-actor-throughput)
        (let ((multi-actor-throughput (getf report :actor-multi-actor-throughput)))
          (format t "actor-multi-actor-throughput> actors=~D jobs=~D elapsed=~,2Fms jobs-per-second=~,2F~%"
                  (or (getf multi-actor-throughput :actor-count) 0)
                  (or (getf multi-actor-throughput :job-count) 0)
                  (* 1000.0 (or (getf multi-actor-throughput :elapsed-seconds) 0.0))
                  (or (getf multi-actor-throughput :jobs-per-second) 0.0))))
      (when mixed-load-contention
        (format t "mixed-load-contention> reads=~D writes=~D actor-jobs=~D elapsed=~,2Fms~%"
                (or (getf mixed-load-contention :read-count) 0)
                (or (getf mixed-load-contention :write-count) 0)
                (or (getf mixed-load-contention :actor-job-count) 0)
                (* 1000.0 (or (getf mixed-load-contention :elapsed-seconds) 0.0)))))
    (dolist (entry (getf report :thread-scaling))
      (format t "thread-scaling> turns=~D avg=~,2Fms max=~,2Fms~%"
              (getf entry :turn-count)
              (getf entry :avg-thread-detail-ms)
              (getf entry :max-thread-detail-ms)))
    (dolist (entry (getf report :persistence-scaling))
      (format t "persistence-scaling> turns=~D session-total=~,2Fms environment-total=~,2Fms~%"
              (getf entry :turn-count)
              (getf entry :session-total-ms)
              (getf entry :environment-total-ms)))))

(defun run-performance-benchmarks ()
  (let* ((say-summary (benchmark-say-turn-latency))
         (thread-summary (benchmark-thread-detail-latency))
         (turn-summary (benchmark-turn-detail-latency))
         (concurrency-core-dispatch-summary (benchmark-concurrency-core-dispatch-latency))
         (runtime-eval-read-summary (benchmark-runtime-eval-read-latency))
         (actor-dispatch-summary (benchmark-actor-dispatch-latency))
         (actor-queue-throughput (benchmark-actor-queue-throughput))
         (mixed-load-contention (benchmark-mixed-load-contention))
         (session-save-load (benchmark-session-save-load))
         (environment-save-load (benchmark-environment-save-load))
         (desktop-preferences-save-load (benchmark-desktop-preferences-save-load))
         (environment-image-save-load (benchmark-environment-image-save-load))
         (trace-link-save-load (benchmark-trace-link-save-load))
         (thread-scaling (benchmark-thread-scaling))
         (persistence-scaling (benchmark-persistence-scaling))
         (report (list :generated-at (get-universal-time)
                       :say-turn-latency say-summary
                       :thread-detail-latency thread-summary
                       :turn-detail-latency turn-summary
                       :concurrency-core-dispatch-latency concurrency-core-dispatch-summary
                       :runtime-eval-read-latency runtime-eval-read-summary
                       :actor-dispatch-latency actor-dispatch-summary
                       :actor-queue-throughput actor-queue-throughput
                       :mixed-load-contention mixed-load-contention
                       :session-save-load session-save-load
                       :environment-save-load environment-save-load
                       :desktop-preferences-save-load desktop-preferences-save-load
                       :environment-image-save-load environment-image-save-load
                       :trace-link-save-load trace-link-save-load
                       :thread-scaling thread-scaling
                       :persistence-scaling persistence-scaling)))
    (enforce-benchmark-budget :say-turn-latency say-summary "SBCL_AGENT_PERF_MAX_SAY_MS")
    (enforce-benchmark-budget :thread-detail-latency thread-summary "SBCL_AGENT_PERF_MAX_THREAD_DETAIL_MS")
    (enforce-benchmark-budget :turn-detail-latency turn-summary "SBCL_AGENT_PERF_MAX_TURN_DETAIL_MS")
    (enforce-benchmark-budget :concurrency-core-dispatch-latency
                              concurrency-core-dispatch-summary
                              "SBCL_AGENT_PERF_MAX_CONCURRENCY_CORE_DISPATCH_MS")
    (enforce-benchmark-budget :runtime-eval-read-latency
                              runtime-eval-read-summary
                              "SBCL_AGENT_PERF_MAX_RUNTIME_EVAL_READ_MS")
    (enforce-benchmark-budget :actor-dispatch-latency
                              actor-dispatch-summary
                              "SBCL_AGENT_PERF_MAX_ACTOR_DISPATCH_MS")
    (enforce-nested-benchmark-budget :mixed-load-read-latency
                                     mixed-load-contention
                                     :read-latency
                                     "SBCL_AGENT_PERF_MAX_MIXED_LOAD_READ_MS")
    (enforce-nested-benchmark-budget :mixed-load-actor-dispatch-latency
                                     mixed-load-contention
                                     :actor-dispatch-latency
                                     "SBCL_AGENT_PERF_MAX_MIXED_LOAD_ACTOR_DISPATCH_MS")
    (let ((path (write-performance-report report)))
      (print-performance-summary report)
      (format t "performance-report> ~A~%" (namestring path)))
    report))

(defun run-concurrency-performance-benchmarks ()
  (let* ((concurrency-core-dispatch-summary
           (benchmark-concurrency-core-dispatch-latency))
         (runtime-eval-read-summary
           (benchmark-runtime-eval-read-latency))
         (actor-dispatch-summary
           (benchmark-actor-dispatch-latency))
         (actor-queue-throughput
           (benchmark-actor-queue-throughput))
         (mixed-load-contention
           (benchmark-mixed-load-contention))
         (report (list :generated-at (get-universal-time)
                       :benchmark-scope :concurrency-core
                       :concurrency-core-dispatch-latency concurrency-core-dispatch-summary
                       :runtime-eval-read-latency runtime-eval-read-summary
                       :actor-dispatch-latency actor-dispatch-summary
                       :actor-queue-throughput actor-queue-throughput
                       :mixed-load-contention mixed-load-contention)))
    (enforce-benchmark-budget :concurrency-core-dispatch-latency
                              concurrency-core-dispatch-summary
                              "SBCL_AGENT_PERF_MAX_CONCURRENCY_CORE_DISPATCH_MS")
    (enforce-benchmark-budget :runtime-eval-read-latency
                              runtime-eval-read-summary
                              "SBCL_AGENT_PERF_MAX_RUNTIME_EVAL_READ_MS")
    (enforce-benchmark-budget :actor-dispatch-latency
                              actor-dispatch-summary
                              "SBCL_AGENT_PERF_MAX_ACTOR_DISPATCH_MS")
    (enforce-nested-benchmark-budget :mixed-load-read-latency
                                     mixed-load-contention
                                     :read-latency
                                     "SBCL_AGENT_PERF_MAX_MIXED_LOAD_READ_MS")
    (enforce-nested-benchmark-budget :mixed-load-actor-dispatch-latency
                                     mixed-load-contention
                                     :actor-dispatch-latency
                                     "SBCL_AGENT_PERF_MAX_MIXED_LOAD_ACTOR_DISPATCH_MS")
    (let ((path (write-performance-report report)))
      (print-performance-summary report)
      (format t "performance-report> ~A~%" (namestring path)))
    report))

(defun run-actor-system-performance-benchmarks ()
  (let* ((actor-dispatch-summary
           (benchmark-actor-dispatch-latency))
         (actor-queue-throughput
           (benchmark-actor-queue-throughput))
         (actor-multi-actor-throughput
           (benchmark-actor-multi-actor-throughput))
         (actor-system-panel-summary
           (benchmark-actor-system-panel-latency))
         (report (list :generated-at (get-universal-time)
                       :benchmark-scope :actor-system
                       :actor-dispatch-latency actor-dispatch-summary
                       :actor-queue-throughput actor-queue-throughput
                       :actor-multi-actor-throughput actor-multi-actor-throughput
                       :actor-system-panel-latency actor-system-panel-summary)))
    (enforce-benchmark-budget :actor-dispatch-latency
                              actor-dispatch-summary
                              "SBCL_AGENT_PERF_MAX_ACTOR_DISPATCH_MS")
    (enforce-benchmark-budget :actor-system-panel-latency
                              actor-system-panel-summary
                              "SBCL_AGENT_PERF_MAX_ACTOR_SYSTEM_PANEL_MS")
    (let ((path (write-performance-report report)))
      (print-performance-summary report)
      (format t "performance-report> ~A~%" (namestring path)))
    report))
