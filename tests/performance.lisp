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
      `(say ,(format nil "performance benchmark turn ~D" index)))
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
                 `(say ,(format nil "latency benchmark turn ~D" index)))
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
      (declare (ignore index))
      (push (/ (measure-seconds
                (lambda ()
                  (dotimes (batch-index batch-size)
                    (declare (ignore batch-index))
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
      (declare (ignore index))
      (push (/ (measure-seconds
                (lambda ()
                  (dotimes (batch-index batch-size)
                    (declare (ignore batch-index))
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
          (environment-save-load (getf report :environment-save-load)))
      (format t "session-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
              (* 1000.0 (getf session-save-load :save-seconds))
              (* 1000.0 (getf session-save-load :load-seconds))
              (* 1000.0 (getf session-save-load :total-seconds)))
      (format t "environment-save-load> save=~,2Fms load=~,2Fms total=~,2Fms~%"
              (* 1000.0 (getf environment-save-load :save-seconds))
              (* 1000.0 (getf environment-save-load :load-seconds))
              (* 1000.0 (getf environment-save-load :total-seconds))))
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
         (thread-scaling (benchmark-thread-scaling))
         (persistence-scaling (benchmark-persistence-scaling))
         (report (list :generated-at (get-universal-time)
                       :say-turn-latency say-summary
                       :thread-detail-latency thread-summary
                       :turn-detail-latency turn-summary
                       :session-save-load session-save-load
                       :environment-save-load environment-save-load
                       :thread-scaling thread-scaling
                       :persistence-scaling persistence-scaling)))
    (enforce-benchmark-budget :say-turn-latency say-summary "SBCL_AGENT_PERF_MAX_SAY_MS")
    (enforce-benchmark-budget :thread-detail-latency thread-summary "SBCL_AGENT_PERF_MAX_THREAD_DETAIL_MS")
    (enforce-benchmark-budget :turn-detail-latency turn-summary "SBCL_AGENT_PERF_MAX_TURN_DETAIL_MS")
    (let ((path (write-performance-report report)))
      (print-performance-summary report)
      (format t "performance-report> ~A~%" (namestring path)))
    report))
