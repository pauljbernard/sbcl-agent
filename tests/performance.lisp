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
           (format t "~A avg=~,2Fms min=~,2Fms max=~,2Fms samples=~D~%"
                   label
                   (benchmark-value-ms summary :avg-seconds)
                   (benchmark-value-ms summary :min-seconds)
                   (benchmark-value-ms summary :max-seconds)
                   (or (getf summary :count) 0))))
    (summary-line "say-turn-latency>" (getf report :say-turn-latency))
    (summary-line "thread-detail-latency>" (getf report :thread-detail-latency))
    (summary-line "turn-detail-latency>" (getf report :turn-detail-latency))
    (let ((session-save-load (getf report :session-save-load))
          (environment-save-load (getf report :environment-save-load))
          (desktop-preferences-save-load (getf report :desktop-preferences-save-load))
          (environment-image-save-load (getf report :environment-image-save-load))
          (trace-link-save-load (getf report :trace-link-save-load)))
      (format t "session-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
              (* 1000.0 (getf session-save-load :save-seconds))
              (* 1000.0 (getf session-save-load :load-seconds))
              (* 1000.0 (getf session-save-load :total-seconds)))
      (format t "environment-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
              (* 1000.0 (getf environment-save-load :save-seconds))
              (* 1000.0 (getf environment-save-load :load-seconds))
              (* 1000.0 (getf environment-save-load :total-seconds)))
      (format t "desktop-preferences-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
              (* 1000.0 (getf desktop-preferences-save-load :save-seconds))
              (* 1000.0 (getf desktop-preferences-save-load :load-seconds))
              (* 1000.0 (getf desktop-preferences-save-load :total-seconds)))
      (format t "environment-image-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
              (* 1000.0 (getf environment-image-save-load :save-seconds))
              (* 1000.0 (getf environment-image-save-load :load-seconds))
              (* 1000.0 (getf environment-image-save-load :total-seconds)))
      (format t "trace-link-save-load> save=~,2Fms load=~,2Fms total=~,2Fms traces=~D~%"
              (* 1000.0 (getf trace-link-save-load :save-seconds))
              (* 1000.0 (getf trace-link-save-load :load-seconds))
              (* 1000.0 (getf trace-link-save-load :total-seconds))
              (or (getf trace-link-save-load :trace-link-count) 0)))
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
    (let ((path (write-performance-report report)))
      (print-performance-summary report)
      (format t "performance-report> ~A~%" (namestring path)))
    report))
