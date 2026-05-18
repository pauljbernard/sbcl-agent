(in-package #:sbcl-agent)

(defstruct retrieval-dossier
  phase
  intent
  alignment-intent-context
  plan
  ranking
  decisive-context-core
  observed-consequences
  conversation-context
  runtime-context
  telemetry-context
  workflow-context
  incident-context
  artifact-context
  environment-context
  console-context
  diagnostic-context
  testing-context
  project-context
  source-context
  trace-context
  gaps)

(defun decisive-context-base-score (kind)
  (case kind
    (:blocker 100)
    (:validation-obligation 95)
    (:open-incident 90)
    (:observed-consequence 85)
    (:runtime-target 70)
    (:project-constraint 65)
    (:intent-constraint 60)
    (:history-anchor 50)
    (otherwise 40)))

(defun decisive-context-authority-weight (domain kind)
  (declare (ignore kind))
  (case domain
    (:workflow 20)
    (:incident 18)
    (:intent 14)
    (:project 12)
    (:workspace 10)
    (:artifact 9)
    (:conversation 6)
    (otherwise 4)))

(defun decisive-context-conflict-potential (kind ref)
  (declare (ignore ref))
  (case kind
    (:blocker 18)
    (:open-incident 16)
    (:validation-obligation 14)
    (:observed-consequence 10)
    (:project-constraint 8)
    (:intent-constraint 6)
    (otherwise 0)))

(defun decisive-context-validation-criticality (kind supporting-evidence)
  (case kind
    (:validation-obligation (+ 18 (length (or supporting-evidence '()))))
    (:blocker 14)
    (:open-incident 6)
    (otherwise 0)))

(defun decisive-context-recency-weight (kind supporting-evidence)
  (cond
    ((eq kind :observed-consequence)
     (if supporting-evidence 10 6))
    ((eq kind :history-anchor)
     4)
    (t
     0)))

(defun decisive-context-entry-score (domain kind ref supporting-evidence)
  (+ (decisive-context-base-score kind)
     (decisive-context-authority-weight domain kind)
     (decisive-context-conflict-potential kind ref)
     (decisive-context-validation-criticality kind supporting-evidence)
     (decisive-context-recency-weight kind supporting-evidence)))

(defun decisive-context-salience-summary (domain kind ref supporting-evidence)
  (list :base-score (decisive-context-base-score kind)
        :authority-weight (decisive-context-authority-weight domain kind)
        :conflict-potential (decisive-context-conflict-potential kind ref)
        :validation-criticality (decisive-context-validation-criticality kind supporting-evidence)
        :recency-weight (decisive-context-recency-weight kind supporting-evidence)))

(defun make-decisive-context-entry (domain kind label summary &key ref supporting-evidence)
  (let* ((evidence (copy-tree (or supporting-evidence '())))
         (salience (decisive-context-salience-summary domain kind ref evidence)))
    (list :domain domain
          :kind kind
          :label label
          :summary summary
          :score (decisive-context-entry-score domain kind ref evidence)
          :salience salience
          :ref ref
          :supporting-evidence evidence)))

(defun dossier-decisive-workflow-entries (dossier)
  (let ((entries '()))
    (dolist (item (or (getf (retrieval-dossier-workflow-context dossier) :work-items) '()))
      (let ((status (getf item :status))
            (work-item-id (getf item :id))
            (pending-validations (or (getf item :pending-validations) '())))
        (when (member status '(:awaiting-approval :blocked :quarantined :awaiting-cold-validation)
                      :test #'eq)
          (push (make-decisive-context-entry
                 :workflow
                 :blocker
                 "Blocked work-item"
                 (format nil "Work-item ~A is currently ~S." (or work-item-id "<unknown>") status)
                 :ref (list :type :work-item :id work-item-id :status status))
                entries))
        (when pending-validations
          (push (make-decisive-context-entry
                 :workflow
                 :validation-obligation
                 "Pending validation"
                 (format nil "Work-item ~A still requires validations ~S." (or work-item-id "<unknown>")
                         pending-validations)
                 :ref (list :type :work-item :id work-item-id)
                 :supporting-evidence pending-validations)
                entries))))
    (nreverse entries)))

(defun dossier-decisive-incident-entries (dossier)
  (let ((entries '()))
    (dolist (incident (or (getf (retrieval-dossier-incident-context dossier) :incidents) '()))
      (when (eq (getf incident :status) :open)
        (push (make-decisive-context-entry
               :incident
               :open-incident
               "Open incident"
               (format nil "~A (~A) remains open."
                       (or (getf incident :summary)
                           (getf incident :title)
                           (getf incident :id)
                           "Incident")
                       (or (getf incident :kind) :incident))
               :ref (list :type :incident :id (getf incident :id) :kind (getf incident :kind)))
              entries)))
    (nreverse entries)))

(defun dossier-decisive-source-entries (dossier)
  (let ((source-context (retrieval-dossier-source-context dossier)))
    (remove nil
            (list
             (when (and source-context (getf source-context :symbol-target))
               (make-decisive-context-entry
                :workspace
                :runtime-target
                "Symbol target"
                (format nil "Source inspection is anchored on symbol target ~A."
                        (getf source-context :symbol-target))
                :ref (list :type :symbol :symbol (getf source-context :symbol-target))))))))

(defun dossier-decisive-intent-entries (dossier)
  (let* ((intent-context (retrieval-dossier-alignment-intent-context dossier))
         (constraints (copy-list (or (getf intent-context :constraints) '()))))
    (when constraints
      (list (make-decisive-context-entry
             :intent
             :intent-constraint
             "Intent constraints"
             "Durable intent constraints narrow the safe solution space."
             :ref (list :type :intent :id (getf intent-context :current-intent-id))
             :supporting-evidence constraints)))))

(defun dossier-decisive-project-entries (dossier)
  (let* ((project-context (retrieval-dossier-project-context dossier))
         (constraints (copy-list (or (and project-context
                                          (getf (getf project-context :constitution) :constraints))
                                     '()))))
    (when constraints
      (list (make-decisive-context-entry
             :project
             :project-constraint
             "Project constraints"
             "Project constitution constraints materially affect planning and mutation choices."
             :ref (list :type :project :id (getf project-context :current-project-id))
             :supporting-evidence constraints)))))

(defun dossier-decisive-conversation-entries (dossier)
  (let ((conversation-context (retrieval-dossier-conversation-context dossier)))
    (remove nil
            (list
             (when (and conversation-context
                        (getf conversation-context :transcript-memory))
               (make-decisive-context-entry
                :conversation
                :history-anchor
                "Relevant prior conversation"
                "Transcript memory surfaced earlier turns that are likely to govern the current task."
                :ref (list :type :thread
                           :id (getf (getf conversation-context :thread) :id))
                :supporting-evidence
                (mapcar (lambda (entry)
                          (list :entry-index (getf entry :entry-index)
                                :match-score (getf entry :match-score)))
                        (or (getf (getf conversation-context :transcript-memory) :entries) '()))))))))

(defun dossier-decisive-observed-consequence-entries (dossier)
  (mapcar (lambda (entry)
            (make-decisive-context-entry
             :artifact
             :observed-consequence
             "Observed mutation consequence"
             (format nil "Observed ~A result with status ~A."
                     (or (getf entry :action-type) :action)
                     (or (getf entry :status) :completed))
             :ref (list :type :action-result
                        :action-type (getf entry :action-type)
                        :tool-id (getf entry :tool-id))
             :supporting-evidence (or (getf entry :paths) '())))
          (or (retrieval-dossier-observed-consequences dossier) '())))

(defun build-decisive-context-core (dossier)
  (let* ((entries (sort (remove nil
                               (append (dossier-decisive-workflow-entries dossier)
                                       (dossier-decisive-incident-entries dossier)
                                       (dossier-decisive-observed-consequence-entries dossier)
                                       (dossier-decisive-source-entries dossier)
                                       (dossier-decisive-intent-entries dossier)
                                       (dossier-decisive-project-entries dossier)
                                       (dossier-decisive-conversation-entries dossier)))
                        #'>
                        :key (lambda (entry) (or (getf entry :score) 0))))
         (primary-entry (first entries)))
    (list :entry-count (length entries)
          :entries entries
          :primary-entry primary-entry
          :focus-labels (remove-duplicates (mapcar (lambda (entry) (getf entry :domain)) entries)
                                           :test #'eq)
          :explanation
          (if primary-entry
              "Decisive context core prioritizes authority-bearing, conflict-prone, validation-critical, and recent governing evidence ahead of broad dossier relevance."
              "No decisive context core was derived beyond the broader dossier payload."))))

(defparameter *retrieval-symbol-token-separators*
  '(#\Space #\Tab #\Newline #\Return #\( #\) #\[ #\] #\{ #\} #\, #\. #\; #\" #\' #\` #\? #\!))

(defun retrieval-symbol-token-candidates (prompt)
  (remove-if (lambda (token) (<= (length token) 1))
             (remove-duplicates
              (mapcar (lambda (token)
                        (string-trim '(#\Space #\Tab #\Newline #\Return) token))
                      (uiop:split-string (or prompt "")
                                         :separator *retrieval-symbol-token-separators*))
              :test #'string=)))

(defun maybe-resolve-prompt-symbol (session prompt)
  (labels ((resolve-token (token)
             (let* ((double-colon (search "::" token))
                    (single-colon (and (null double-colon)
                                       (position #\: token)))
                    (package-name (cond
                                    (double-colon (subseq token 0 double-colon))
                                    (single-colon (subseq token 0 single-colon))
                                    (t nil)))
                    (symbol-name (cond
                                   (double-colon (subseq token (+ double-colon 2)))
                                   (single-colon (subseq token (1+ single-colon)))
                                   (t token))))
               (ignore-errors
                 (multiple-value-bind (resolved-package resolved-symbol status)
                     (resolve-runtime-symbol session (string-upcase symbol-name) package-name)
                   (when resolved-symbol
                     (list :package (package-name resolved-package)
                           :symbol (symbol-name resolved-symbol)
                           :status status)))))))
    (some #'resolve-token
          (retrieval-symbol-token-candidates prompt))))

(defun run-captured-process-output (program arguments)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (handler-case
        (let ((process (sb-ext:run-program program
                                           arguments
                                           :search t
                                           :input nil
                                           :output stdout
                                           :error stderr
                                           :wait t)))
          (when (zerop (sb-ext:process-exit-code process))
            (get-output-stream-string stdout)))
      (error ()
        nil))))

(defun retrieval-token-match-score (prompt &rest values)
  (let* ((tokens (retrieval-symbol-token-candidates prompt))
         (haystack (string-downcase
                    (format nil "~{~A~^ ~}"
                            (remove nil
                                    (mapcar (lambda (value)
                                              (and value (princ-to-string value)))
                                            values))))))
    (count-if (lambda (token)
                (search (string-downcase token) haystack))
              tokens)))

(defun transcript-memory-match-entry (entry index total-count prompt)
  (let* ((role (getf entry :role))
         (content (getf entry :content))
         (score (retrieval-token-match-score prompt role content)))
    (when (> score 0)
      (list :entry-index index
            :role role
            :content (provider-summary-content content :limit 320)
            :match-score score
            :distance-from-latest (- (1- total-count) index)))))

(defun transcript-memory-match-better-p (left right)
  (let ((left-score (or (getf left :match-score) 0))
        (right-score (or (getf right :match-score) 0)))
    (if (/= left-score right-score)
        (> left-score right-score)
        (< (or (getf left :distance-from-latest) most-positive-fixnum)
           (or (getf right :distance-from-latest) most-positive-fixnum)))))

(defun transcript-memory-matches (session prompt &key (limit 4))
  (let* ((entries (agent-session-transcript session))
         (total-count (length entries))
         (last-index (1- total-count))
         (scored '()))
    (loop for entry in entries
          for index from 0
          do (unless (and (= index last-index)
                          (eq (getf entry :role) :user)
                          (stringp (getf entry :content))
                          (string= (getf entry :content) (or prompt "")))
               (let ((match (transcript-memory-match-entry entry index total-count prompt)))
                 (when match
                   (push match scored)))))
    (compact-list (sort scored #'transcript-memory-match-better-p) limit)))

(defun host-console-entry-from-json-line (line index)
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) line)))
    (when (and (> (length trimmed) 1)
               (char= (char trimmed 0) #\{))
      (let* ((decoded (ignore-errors (parse-json trimmed)))
             (message (and (listp decoded) (json-object-value decoded "eventMessage"))))
        (when (listp decoded)
          (let ((process-name (or (json-object-value decoded "processImagePath")
                                  (json-object-value decoded "senderImagePath")
                                  (json-object-value decoded "process"))))
            (list :entry-id (format nil "host:~D" index)
                  :cursor index
                  :plane :host
                  :timestamp (or (json-object-value decoded "timestamp")
                                 (json-object-value decoded "date"))
                  :type (or (json-object-value decoded "messageType")
                            (json-object-value decoded "eventType")
                            "default")
                  :category (or (json-object-value decoded "subsystem")
                                (json-object-value decoded "category"))
                  :source (or (json-object-value decoded "category")
                              (json-object-value decoded "subsystem")
                              process-name)
                  :message (if message
                               (princ-to-string message)
                               (princ-to-string (or (json-object-value decoded "composedMessage")
                                                    "")))
                  :process-name process-name
                  :pid (json-object-value decoded "processID")
                  :thread-id (json-object-value decoded "threadID")
                  :activity-id (json-object-value decoded "activityIdentifier")
                  :detail (json-object->keyword-plist decoded))))))))

(defun host-console-entries (prompt &optional (limit 6))
  (let* ((output (run-captured-process-output "log"
                                              '("show" "--style" "json" "--last" "2m"))))
    (when output
      (let ((entries '()))
        (loop for line in (uiop:split-string output :separator '(#\Newline))
              for index from 0
              for entry = (and (> (length line) 0)
                               (host-console-entry-from-json-line line index))
              when entry
                do (push entry entries))
        (let* ((ordered (nreverse entries))
               (scored (sort (copy-list ordered)
                             #'>
                             :key (lambda (entry)
                                    (retrieval-token-match-score prompt
                                                                 (getf entry :message)
                                                                 (getf entry :process-name)
                                                                 (getf entry :source)
                                                                 (getf entry :category))))))
          (subseq scored 0 (min limit (length scored))))))))

(defun diagnostic-report-kind-for-path (pathname)
  (let ((name (string-downcase (file-namestring pathname))))
    (cond
      ((search ".spin" name) :spin)
      ((search ".panic" name) :crash)
      ((search ".ips" name) :crash)
      ((search ".diag" name) :diagnostic)
      (t :diagnostic))))

(defun diagnostic-preview-metadata (pathname)
  (let ((content (ignore-errors
                   (with-open-file (stream pathname :direction :input)
                     (let ((buffer (make-string 4096)))
                       (let ((count (read-sequence buffer stream)))
                         (subseq buffer 0 count)))))))
    (when content
      (let ((decoded (and (> (length content) 0)
                          (char= (char content 0) #\{)
                          (ignore-errors (parse-json content)))))
        (list :preview (subseq content 0 (min 280 (length content)))
              :process-name (or (and decoded (json-object-value decoded "procName"))
                                (and decoded (json-object-value decoded "process"))
                                (pathname-name pathname))
              :pid (and decoded (json-object-value decoded "pid"))
              :incident-id (and decoded (json-object-value decoded "incident_id"))
              :bug-type (and decoded (json-object-value decoded "bug_type"))
              :responsible-process (and decoded
                                        (or (json-object-value decoded "responsibleProc")
                                            (json-object-value decoded "responsible_process"))))))))

(defun diagnostic-report-roots ()
  (remove nil
          (list (ignore-errors (uiop:ensure-directory-pathname
                                (merge-pathnames "Library/Logs/DiagnosticReports/"
                                                 (uiop:ensure-directory-pathname (getenv "HOME")))))
                (ignore-errors (uiop:ensure-directory-pathname "/Library/Logs/DiagnosticReports/")))))

(defun host-diagnostic-report-summaries (prompt &optional (limit 6))
  (let ((files '()))
    (dolist (root (diagnostic-report-roots))
      (dolist (pathname (ignore-errors (uiop:directory-files root)))
        (push pathname files)))
    (let ((ordered (sort files #'> :key (lambda (pathname)
                                          (or (ignore-errors (file-write-date pathname)) 0)))))
      (let ((reports
              (mapcar (lambda (pathname)
                        (let* ((preview (diagnostic-preview-metadata pathname))
                               (process-name (or (getf preview :process-name)
                                                 (pathname-name pathname))))
                          (list :report-id (namestring pathname)
                                :kind (diagnostic-report-kind-for-path pathname)
                                :source (princ-to-string (pathname-directory pathname))
                                :process-name process-name
                                :created-at (ignore-errors (file-write-date pathname))
                                :bytes (ignore-errors
                                         (with-open-file (stream pathname :direction :input
                                                                 :element-type '(unsigned-byte 8))
                                           (file-length stream)))
                                :preview (getf preview :preview)
                                :pid (getf preview :pid)
                                :incident-id (getf preview :incident-id)
                                :bug-type (getf preview :bug-type)
                                :responsible-process (getf preview :responsible-process)
                                :summary (format nil "Host diagnostic report ~A" (file-namestring pathname)))))
                      ordered)))
        (let ((scored (sort reports
                            #'>
                            :key (lambda (report)
                                   (retrieval-token-match-score prompt
                                                                (getf report :process-name)
                                                                (getf report :summary)
                                                                (getf report :preview)
                                                                (getf report :incident-id)
                                                                (getf report :bug-type))))))
          (subseq scored 0 (min limit (length scored))))))))

(defun retrieval-read-file-contents (pathname &key (element-type 'character))
  (when (and pathname (probe-file pathname))
    (with-open-file (stream pathname :direction :input :element-type element-type)
      (let ((buffer (make-string (file-length stream))))
        (read-sequence buffer stream)
        buffer))))

(defun retrieval-read-json-file (pathname)
  (let ((contents (retrieval-read-file-contents pathname)))
    (and contents
         (ignore-errors (parse-json contents)))))

(defun retrieval-read-lisp-value-file (pathname)
  (when (and pathname (probe-file pathname))
    (ignore-errors
      (with-open-file (stream pathname :direction :input)
        (read stream nil nil)))))

(defun json-test-result-entry->plist (entry)
  (when (listp entry)
    (list :name (json-object-value entry "name")
          :category (let ((category (json-object-value entry "category")))
                      (cond
                        ((keywordp category) category)
                        ((stringp category) (intern (string-upcase category) "KEYWORD"))
                        (t category)))
          :status (let ((status (json-object-value entry "status")))
                    (cond
                      ((keywordp status) status)
                      ((stringp status) (intern (string-upcase status) "KEYWORD"))
                      (t status)))
          :duration-seconds (json-object-value entry "durationSeconds")
          :error (json-object-value entry "error"))))

(defun json-testing-summary->plist (summary)
  (when (listp summary)
    (list :total (json-object-value summary "total")
          :passed (json-object-value summary "passed")
          :failed (json-object-value summary "failed")
          :duration-seconds (json-object-value summary "durationSeconds"))))

(defun testing-artifact-root ()
  (merge-pathnames #P"tmp/test-results/"
                   (uiop:ensure-directory-pathname (uiop:getcwd))))

(defun performance-artifact-root ()
  (merge-pathnames #P"tmp/performance/"
                   (uiop:ensure-directory-pathname (uiop:getcwd))))

(defun coverage-artifact-root ()
  (merge-pathnames #P"tmp/coverage/"
                   (uiop:ensure-directory-pathname (uiop:getcwd))))

(defun latest-test-report-path ()
  (merge-pathnames #P"latest-report.json" (testing-artifact-root)))

(defun test-evidence-index-path ()
  (merge-pathnames #P"evidence-index.json" (testing-artifact-root)))

(defun performance-report-path ()
  (merge-pathnames #P"latest.sexp" (performance-artifact-root)))

(defun coverage-index-path ()
  (merge-pathnames #P"cover-index.html" (coverage-artifact-root)))

(defun testing-harness-inventory ()
  (list
   (list :id :full-suite
         :label "Full Lisp Suite"
         :entrypoint "./bin/run-tests"
         :kind :suite)
   (list :id :coverage
         :label "Coverage"
         :entrypoint "./bin/run-coverage"
         :kind :coverage)
   (list :id :internal-evaluations
         :label "Internal Evaluations"
         :entrypoint "./bin/run-evals"
         :kind :evaluation)
   (list :id :performance-benchmarks
         :label "Performance Benchmarks"
         :entrypoint "./bin/run-performance"
         :kind :performance)
   (list :id :service-contracts
         :label "Service Contracts"
         :entrypoint "./bin/run-test-service-contracts"
         :kind :focused-suite
         :categories '(:service-contracts))
   (list :id :workflow-governance
         :label "Workflow And Governance"
         :entrypoint "./bin/run-test-workflow-governance"
         :kind :focused-suite
         :categories '(:workflow-and-governance))
   (list :id :shell-compatibility
         :label "Shell And Compatibility"
         :entrypoint "./bin/run-test-shell-compatibility"
         :kind :focused-suite
         :categories '(:shell-and-compatibility))
   (list :id :retrieval-memory
         :label "Retrieval And Memory"
         :entrypoint "./bin/run-test-retrieval-memory"
         :kind :focused-suite
         :categories '(:retrieval-and-memory))
   (list :id :environment-persistence
         :label "Environment And Persistence"
         :entrypoint "./bin/run-test-environment-persistence"
         :kind :focused-suite
         :categories '(:environment-and-persistence))))

(defun scored-testing-harnesses (prompt &optional (limit 6))
  (let* ((harnesses (testing-harness-inventory))
         (scored (sort (copy-list harnesses)
                       #'>
                       :key (lambda (entry)
                              (retrieval-token-match-score prompt
                                                           (getf entry :label)
                                                           (getf entry :entrypoint)
                                                           (getf entry :kind)
                                                           (getf entry :categories))))))
    (compact-list scored limit)))

(defun summarized-test-results (results)
  (let* ((total (length results))
         (passed (count :passed results :key (lambda (entry) (getf entry :status)) :test #'eq))
         (failed (count :failed results :key (lambda (entry) (getf entry :status)) :test #'eq))
         (duration (reduce #'+ results
                           :key (lambda (entry) (or (getf entry :duration-seconds) 0.0))
                           :initial-value 0.0)))
    (list :total total
          :passed passed
          :failed failed
          :duration-seconds duration)))

(defun select-testing-failures (prompt results &optional (limit 6))
  (let* ((failures (remove-if-not (lambda (entry)
                                    (eq (getf entry :status) :failed))
                                  (or results '())))
         (scored (sort (copy-list failures)
                       #'>
                       :key (lambda (entry)
                              (retrieval-token-match-score prompt
                                                           (getf entry :name)
                                                           (getf entry :category)
                                                           (getf entry :error))))))
    (compact-list scored limit)))

(defun performance-report-summary (report)
  (when report
    (list :generated-at (getf report :generated-at)
          :say-turn-latency (getf report :say-turn-latency)
          :thread-detail-latency (getf report :thread-detail-latency)
          :turn-detail-latency (getf report :turn-detail-latency)
          :session-save-load (getf report :session-save-load)
          :environment-save-load (getf report :environment-save-load)
          :thread-scaling (compact-list (or (getf report :thread-scaling) '()) 4)
          :persistence-scaling (compact-list (or (getf report :persistence-scaling) '()) 4))))

(defun work-item-testing-linkage-summary (work-item)
  (list :work-item-id (work-item-id work-item)
        :title (work-item-goal work-item)
        :status (work-item-status work-item)
        :pending-validations (work-item-pending-validations work-item)
        :validator-action-count (length (or (work-item-validator-actions work-item) '()))
        :validator-task-count (length (or (work-item-validator-tasks work-item) '()))
        :replay-id (let ((transaction (current-work-item-transaction work-item)))
                     (and transaction (mutation-transaction-replay-id transaction)))))

(defun dossier-section (domain operation response)
  (list :domain domain
        :operation operation
        :metadata (service-response-metadata response)
        :data (service-response-data response)))

(defun build-conversation-dossier-section (session prompt plan)
  (let ((thread-response (query-conversation-thread-detail-service session))
        (turn-response (ignore-errors (query-conversation-turn-detail-service session)))
        (memory-limit (retrieval-plan-limit plan :conversation 4)))
    (list :thread (dossier-section :conversation :thread-detail thread-response)
          :turn (and turn-response
                     (dossier-section :conversation :turn-detail turn-response))
          :recent-transcript (mapcar #'provider-transcript-entry
                                     (recent-session-transcript session :limit memory-limit))
          :transcript-memory (list :query prompt
                                   :transcript-count (length (agent-session-transcript session))
                                   :entries (transcript-memory-matches session prompt
                                                                       :limit memory-limit))
          :operator-memory (list :query prompt
                                 :entry-count (length (list-operator-memory-entries session))
                                 :entries (ranked-operator-memory-entries session prompt
                                                                         :limit memory-limit))
          :limit memory-limit)))

(defun build-runtime-dossier-section (session plan)
  (let ((summary-response (query-runtime-summary-service session))
        (history-response (query-runtime-history-service session
                                                         :tail (retrieval-plan-limit plan :runtime 3))))
    (list :summary (dossier-section :runtime :summary summary-response)
          :history (dossier-section :runtime :history history-response)
          :detail-p (retrieval-plan-runtime-detail-p plan))))

(defun build-telemetry-dossier-section (session plan)
  (let* ((telemetry-response (query-runtime-telemetry-service session))
         (telemetry-data (service-response-data telemetry-response))
         (process-limit (retrieval-plan-limit plan :telemetry 4)))
    (list :snapshot (dossier-section :telemetry :snapshot telemetry-response)
          :processes (compact-list (or (getf telemetry-data :processes) '()) process-limit)
          :activity-summary (getf telemetry-data :activity-summary)
          :runtime-id (getf telemetry-data :runtime-id))))

(defun build-workflow-dossier-section (session plan)
  (let* ((limit (retrieval-plan-limit plan :workflow 4))
         (work-item-list-response (query-work-item-list-service session))
         (workflow-list-response (query-workflow-record-list-service session)))
    (list :work-items (compact-list (service-response-data work-item-list-response) limit)
          :workflow-records (compact-list (service-response-data workflow-list-response) limit)
          :work-item-metadata (service-response-metadata work-item-list-response)
          :workflow-metadata (service-response-metadata workflow-list-response)
          :detail-p (retrieval-plan-governance-detail-p plan))))

(defun build-incident-dossier-section (session plan)
  (let* ((limit (retrieval-plan-limit plan :incident 3))
         (incident-list-response (query-incident-list-service session)))
    (list :incidents (compact-list (service-response-data incident-list-response) limit)
          :metadata (service-response-metadata incident-list-response)
          :detail-p (retrieval-plan-governance-detail-p plan))))

(defun build-artifact-dossier-section (session)
  (let ((review-response (ignore-errors (query-mutation-review-service session))))
    (if review-response
        (list :review (dossier-section :mutation :review review-response))
        (list :review nil
              :note "No mutation review is available for the current thread yet."))))

(defun build-environment-dossier-section (plan)
  (let* ((environment (ensure-environment))
         (summary-response (query-environment-summary-service environment
                                                             :include-alignment-state-p nil
                                                             :include-reconciliation-decision-p nil))
         (status-response (query-environment-status-service environment
                                                           :include-alignment-state-p nil
                                                           :include-reconciliation-decision-p nil))
         (event-response (query-service-event-stream :environment environment
                                                     :limit (retrieval-plan-limit plan :events 4))))
    (list :summary (dossier-section :environment :summary summary-response)
          :status (dossier-section :environment :status status-response)
          :events (dossier-section :events :stream event-response))))

(defun build-console-dossier-section (prompt plan)
  (let* ((environment (ensure-environment))
         (limit (retrieval-plan-limit plan :console 6))
         (console-response (query-console-log-stream-service :environment environment
                                                             :limit limit))
         (console-data (service-response-data console-response))
         (host-entries (host-console-entries prompt limit)))
    (list :environment-stream (dossier-section :console :stream console-response)
          :environment-entries (or (getf console-data :entries) '())
          :host-entries host-entries
          :next-cursor (getf console-data :next-cursor)
          :summary (format nil
                           "Environment console yielded ~D entries; host console yielded ~D entries."
                           (length (or (getf console-data :entries) '()))
                           (length host-entries)))
          :focus-tokens (retrieval-symbol-token-candidates prompt)))

(defun build-diagnostic-dossier-section (prompt plan)
  (let* ((limit (retrieval-plan-limit plan :diagnostic 6))
         (reports (host-diagnostic-report-summaries prompt limit)))
    (list :reports reports
          :report-count (length reports)
          :focus-tokens (retrieval-symbol-token-candidates prompt)
          :summary (format nil "Collected ~D host diagnostic reports for agent reasoning." (length reports)))))

(defun build-testing-dossier-section (session prompt plan)
  (let* ((limit (retrieval-plan-limit plan :testing 6))
         (report-json (retrieval-read-json-file (latest-test-report-path)))
         (evidence-index (retrieval-read-json-file (test-evidence-index-path)))
         (performance-report (retrieval-read-lisp-value-file (performance-report-path)))
         (coverage-index (coverage-index-path))
         (results (mapcar #'json-test-result-entry->plist
                          (or (and report-json (json-object-value report-json "results")) '())))
         (summary (and report-json
                       (json-testing-summary->plist
                        (json-object-value report-json "summary"))))
         (harnesses (scored-testing-harnesses prompt limit))
         (failures (select-testing-failures prompt results limit))
         (linked-work-items (compact-list
                             (mapcar #'work-item-testing-linkage-summary
                                     (agent-session-work-items session))
                             limit))
         (replay-groups (compact-list (session-validator-replay-groups session) limit)))
    (list :harnesses harnesses
          :latest-report (and report-json
                              (list :generated-at (json-object-value report-json "generatedAt")
                                    :suite-id (json-object-value report-json "suiteId")
                                    :summary summary))
          :failures failures
          :performance (performance-report-summary performance-report)
          :coverage (list :index-path (and (probe-file coverage-index)
                                           (namestring coverage-index))
                          :present-p (not (null (probe-file coverage-index))))
          :evidence-index evidence-index
          :linked-work-items linked-work-items
          :replay-groups replay-groups
          :focus-tokens (retrieval-symbol-token-candidates prompt)
          :summary (format nil
                           "Testing context includes ~D harnesses, ~D recent failures, ~D linked work items, and ~D replay groups."
                           (length harnesses)
                           (length failures)
                           (length linked-work-items)
                           (length replay-groups)))))

(defun summarized-project-requirement (requirement)
  (list :id (project-requirement-id requirement)
        :title (project-requirement-title requirement)
        :summary (project-requirement-summary requirement)
        :scope (project-requirement-scope requirement)
        :kind (project-requirement-kind requirement)
        :priority (project-requirement-priority requirement)
        :status (project-requirement-status requirement)
        :verification-kind (project-requirement-verification-kind requirement)))

(defun summarized-project-feature-spec (spec)
  (list :id (project-feature-spec-id spec)
        :title (project-feature-spec-title spec)
        :summary (project-feature-spec-summary spec)
        :status (project-feature-spec-status spec)
        :acceptance-criteria (compact-list (or (project-feature-spec-acceptance-criteria spec) '()) 4)
        :linked-requirement-ids (copy-list (or (project-feature-spec-linked-requirement-ids spec) '()))
        :linked-journey-ids (copy-list (or (project-feature-spec-linked-journey-ids spec) '()))))

(defun summarized-project-user-journey (journey)
  (list :id (project-user-journey-id journey)
        :title (project-user-journey-title journey)
        :summary (project-user-journey-summary journey)
        :actors (compact-list (or (project-user-journey-actors journey) '()) 4)
        :entrypoints (compact-list (or (project-user-journey-entrypoints journey) '()) 4)
        :steps (compact-list (or (project-user-journey-steps journey) '()) 5)
        :outcomes (compact-list (or (project-user-journey-outcomes journey) '()) 4)
        :edge-cases (compact-list (or (project-user-journey-edge-cases journey) '()) 4)))

(defun summarized-project-architecture-decision (decision)
  (list :id (project-architecture-decision-id decision)
        :title (project-architecture-decision-title decision)
        :status (project-architecture-decision-status decision)
        :summary (project-architecture-decision-summary decision)
        :drivers (compact-list (or (project-architecture-decision-drivers decision) '()) 4)
        :consequences (compact-list (or (project-architecture-decision-consequences decision) '()) 4)
        :stack-choices (compact-list (or (project-architecture-decision-stack-choices decision) '()) 4)
        :linked-requirement-ids (copy-list (or (project-architecture-decision-linked-requirement-ids decision) '()))))

(defun summarized-project-linked-work-item (session work-item-id)
  (let ((work-item (find-work-item session work-item-id)))
    (and work-item
         (list :id (work-item-id work-item)
               :title (work-item-goal work-item)
               :status (work-item-status work-item)
               :workflow-record-id (work-item-workflow-record-ref work-item)
               :pending-validations (copy-list (or (work-item-pending-validations work-item) '()))
               :source-mutation-count
               (length
                (or (provenance-record-executed-mutations (work-item-provenance work-item)) '()))))))

(defun summarized-project-linked-incident (session incident-id)
  (let ((incident (find-incident session incident-id)))
    (and incident
         (list :id (incident-id incident)
               :title (incident-title incident)
               :summary (incident-summary incident)
               :status (incident-status incident)
               :kind (incident-kind incident)
               :work-item-id (incident-work-item-id incident)
               :workflow-record-id (incident-workflow-record-id incident)))))

(defun project-testing-harness-summaries (project)
  (let ((linked-ids (or (project-record-linked-testing-harness-ids project) '())))
    (mapcar (lambda (entry)
              (list :id (getf entry :id)
                    :label (getf entry :label)
                    :entrypoint (getf entry :entrypoint)
                    :kind (getf entry :kind)
                    :categories (copy-list (or (getf entry :categories) '()))))
            (remove-if-not (lambda (entry)
                             (find (getf entry :id) linked-ids :test #'eq))
                           (testing-harness-inventory)))))

(defun project-testing-evidence-summary ()
  (let* ((report-json (retrieval-read-json-file (latest-test-report-path)))
         (performance-report (retrieval-read-lisp-value-file (performance-report-path)))
         (coverage-index (coverage-index-path)))
    (list :latest-report (and report-json
                              (list :generated-at (json-object-value report-json "generatedAt")
                                    :suite-id (json-object-value report-json "suiteId")
                                    :summary (json-testing-summary->plist
                                              (json-object-value report-json "summary"))))
          :coverage (list :index-path (and (probe-file coverage-index)
                                           (namestring coverage-index))
                          :present-p (not (null (probe-file coverage-index))))
          :performance (performance-report-summary performance-report))))

(defun project-quality-gate-evidence-summary (session project)
  (let* ((payload (project-detail-payload session project
                                          :include-alignment-state-p nil
                                          :include-reconciliation-decision-p nil))
         (quality-gates
           (mapcar (lambda (entry)
                     (if (typep entry 'project-quality-gate)
                         (project-quality-gate-payload entry)
                         entry))
                   (or (getf payload :quality-gates) '())))
         (quality-gate-summary (getf payload :quality-gate-summary)))
    (list :quality-gates (compact-list quality-gates 6)
          :quality-gate-summary quality-gate-summary)))

(defun project-readiness-evidence-summary (session project)
  (let* ((payload (project-detail-payload session project
                                          :include-alignment-state-p nil
                                          :include-reconciliation-decision-p nil))
         (readiness-summary (getf payload :readiness-summary)))
    (when readiness-summary
      (list :status (getf readiness-summary :status)
            :testing-readiness (getf readiness-summary :testing-readiness)
            :quality-gate-readiness (getf readiness-summary :quality-gate-readiness)
            :recovery-readiness (getf readiness-summary :recovery-readiness)
            :release-readiness-status (getf readiness-summary :release-readiness-status)
            :release-review-state (getf readiness-summary :release-review-state)
            :release-signoff-state (getf readiness-summary :release-signoff-state)
            :release-signoff-ready-p (getf readiness-summary :release-signoff-ready-p)
            :release-signoff-summary (getf readiness-summary :release-signoff-summary)
            :release-required-approvers (copy-list (or (getf readiness-summary :release-required-approvers) '()))
            :release-approved-approvers (copy-list (or (getf readiness-summary :release-approved-approvers) '()))
            :release-pending-approvers (copy-list (or (getf readiness-summary :release-pending-approvers) '()))
            :release-unassigned-approvers (copy-list (or (getf readiness-summary :release-unassigned-approvers) '()))
            :release-signoff-ownership-ready-p (getf readiness-summary :release-signoff-ownership-ready-p)
            :release-current-phase (getf readiness-summary :release-current-phase)
            :release-target-phase (getf readiness-summary :release-target-phase)
            :release-transition-ready-p (getf readiness-summary :release-transition-ready-p)
            :release-transition-summary (getf readiness-summary :release-transition-summary)
            :suite-blocked-count (getf readiness-summary :suite-blocked-count)
            :suite-ready-count (getf readiness-summary :suite-ready-count)
            :release-stage (getf readiness-summary :release-stage)
            :release-signoff-status (getf readiness-summary :release-signoff-status)
            :readiness-obligation-count (getf readiness-summary :readiness-obligation-count)
            :blocked-readiness-obligation-count (getf readiness-summary :blocked-readiness-obligation-count)
            :ready-readiness-obligation-count (getf readiness-summary :ready-readiness-obligation-count)
            :release-next-actions (compact-list (or (getf readiness-summary :release-next-actions) '()) 4)
            :unmet-obligations (compact-list (or (getf readiness-summary :unmet-obligations) '()) 6)))))

(defun build-intent-dossier-section (session plan)
  (let* ((current-intent (current-intent-record session))
         (intents (list-intent-records session))
         (limit (retrieval-plan-limit plan :intent 4)))
    (when current-intent
      (list :current-intent-id (intent-record-id current-intent)
            :intent-count (length intents)
            :intents (mapcar #'intent-record-summary (compact-list intents limit))
            :summary (intent-record-summary current-intent)
            :scope (copy-tree (intent-record-scope current-intent))
            :constraints (copy-tree (or (intent-record-constraints current-intent) '()))
            :expected-behaviors (compact-list (copy-list (or (intent-record-expected-behaviors current-intent) '()))
                                             limit)
            :non-goals (compact-list (copy-list (or (intent-record-non-goals current-intent) '()))
                                     limit)
            :linked-runtime-objects (compact-list
                                     (copy-list (or (intent-record-linked-runtime-objects current-intent) '()))
                                     limit)
            :linked-source-artifacts (compact-list
                                      (copy-list (or (intent-record-linked-source-artifacts current-intent) '()))
                                      limit)
            :linked-event-ids (compact-list
                               (copy-list (or (intent-record-linked-event-ids current-intent) '()))
                               limit)
            :linked-mutation-ids (compact-list
                                  (copy-list (or (intent-record-linked-mutation-ids current-intent) '()))
                                  limit)))))

(defun project-prompt-alignment-field-tokens (value)
  (labels ((project-search-text (value)
             (cond
               ((null value) "")
               ((stringp value) value)
               ((symbolp value) (string-downcase (string value)))
               ((numberp value) (princ-to-string value))
               ((listp value)
                (with-output-to-string (stream)
                  (dolist (entry value)
                    (let ((text (project-search-text entry)))
                      (when (> (length text) 0)
                        (write-string text stream)
                        (write-char #\Space stream))))))
               (t
                (princ-to-string value)))))
    (remove-duplicates
     (prompt-match-tokens
      (string-downcase (project-search-text value)))
     :test #'string=)))

(defparameter +project-alignment-stopwords+
  '("project" "context" "planning" "plan" "state" "runtime" "environment"
    "provider" "response" "decisive" "evidence" "posture" "inspect" "detail"
    "current" "govern" "governed" "changes" "change" "validate" "validation"
    "explain" "identify" "should" "what" "which" "under" "with" "into"))

(defun project-alignment-relevant-tokens (value)
  (remove-if (lambda (token)
               (or (< (length token) 4)
                   (member token +project-alignment-stopwords+ :test #'string=)))
             (project-prompt-alignment-field-tokens value)))

(defun project-prompt-alignment-score (prompt project-summary &optional project-record)
  (let* ((prompt-tokens (remove-duplicates (project-alignment-relevant-tokens prompt) :test #'string=))
         (weighted-fields
          (remove nil
                  (list (list :weight 3
                              :tokens (project-alignment-relevant-tokens
                                       (list (getf project-summary :id)
                                             (getf project-summary :title)
                                             (getf project-summary :source-roots))))
                        (and project-record
                             (list :weight 2
                                   :tokens (project-alignment-relevant-tokens
                                            (project-record-constitution project-record))))
                        (and project-record
                             (list :weight 2
                                   :tokens (project-alignment-relevant-tokens
                                            (mapcar #'summarized-project-requirement
                                                    (or (project-record-requirements project-record) '())))))
                        (and project-record
                             (list :weight 1
                                   :tokens (project-alignment-relevant-tokens
                                            (mapcar #'summarized-project-architecture-decision
                                                    (or (project-record-architecture-decisions project-record) '())))))
                        (and project-record
                             (list :weight 1
                                   :tokens (project-alignment-relevant-tokens
                                            (mapcar #'summarized-project-feature-spec
                                                    (or (project-record-feature-specifications project-record) '()))))))))
         (field-matches
          (mapcar (lambda (field)
                    (let ((matches (loop for token in prompt-tokens
                                         count (member token (getf field :tokens) :test #'string=))))
                      (list :weight (getf field :weight)
                            :match-count matches)))
                  weighted-fields)))
    (loop for field in field-matches
          sum (* (getf field :weight) (getf field :match-count)))))

(defun project-selection-posture-from-prompt (prompt current-project-summary project-summaries
                                                &optional project-records)
  (let* ((confidence-threshold 2)
         (record-for-summary
          (lambda (summary)
            (find (getf summary :id)
                  project-records
                  :key #'project-record-id
                  :test #'string=)))
         (current-score (and current-project-summary
                             (project-prompt-alignment-score prompt
                                                             current-project-summary
                                                             (funcall record-for-summary
                                                                      current-project-summary))))
         (linked-scores
          (remove nil
                  (mapcar (lambda (summary)
                            (unless (and current-project-summary
                                         (string= (getf summary :id)
                                                  (getf current-project-summary :id)))
                              (list :project-id (getf summary :id)
                                    :title (getf summary :title)
                                    :score (project-prompt-alignment-score prompt
                                                                           summary
                                                                           (funcall record-for-summary summary)))))
                          (or project-summaries '()))))
         (matching-linked-scores
          (remove-if-not (lambda (entry) (> (or (getf entry :score) 0) 0))
                         linked-scores))
         (best-linked-score
          (first (sort (copy-list matching-linked-scores)
                       #'>
                       :key (lambda (entry) (or (getf entry :score) 0)))))
         (matching-linked-count (length matching-linked-scores))
         (project-count (length (or project-summaries '())))
         (selection-confident-p
          (cond
            ((<= project-count 1) t)
            ((and (>= current-score confidence-threshold)
                  (or (null best-linked-score)
                      (> current-score (getf best-linked-score :score))))
             t)
            (t nil)))
         (selection-basis
          (cond
            ((<= project-count 1) :single-project)
            ((and (= current-score 0) (> matching-linked-count 0)) :prompt-mismatch)
            ((and (>= current-score confidence-threshold)
                  best-linked-score
                  (= current-score (getf best-linked-score :score)))
             :prompt-ambiguous)
            ((>= current-score confidence-threshold) :prompt-aligned)
            (t :weak-prompt-alignment))))
    (list :selection-confident-p selection-confident-p
          :selection-basis selection-basis
          :prompt-match-score current-score
          :matching-linked-project-count matching-linked-count
          :best-linked-project-match best-linked-score)))

(defun build-project-dossier-section (session prompt plan)
  (let* ((response (query-project-list-service session))
         (data (service-response-data response))
         (projects (or (getf data :projects) '()))
         (current-id (getf data :current-project-id))
         (explicit-selected-projects (context-chat-selected-project-records session))
         (explicit-primary-project (context-chat-primary-project-record session))
         (current-project (or explicit-primary-project
                              (and current-id (find-project-record session current-id))
                              (current-project-record session)))
         (limit (retrieval-plan-limit plan :project 4))
         (linked-work-items
           (compact-list
            (remove nil
                    (mapcar (lambda (work-item-id)
                              (summarized-project-linked-work-item session work-item-id))
                            (or (and current-project
                                     (project-record-linked-work-item-ids current-project))
                                '())))
            limit))
         (linked-incidents
           (compact-list
            (remove nil
                    (mapcar (lambda (incident-id)
                              (summarized-project-linked-incident session incident-id))
                            (or (and current-project
                                     (project-record-linked-incident-ids current-project))
                                '())))
            limit))
         (testing-harnesses (and current-project
                                (compact-list
                                  (project-testing-harness-summaries current-project)
                                  limit)))
         (quality-gate-evidence (and current-project
                                     (project-quality-gate-evidence-summary session current-project)))
         (readiness-summary (and current-project
                                 (project-readiness-evidence-summary session current-project)))
         (linked-projects
           (compact-list
            (or (and explicit-selected-projects
                     (remove nil
                             (mapcar (lambda (project)
                                       (unless (and current-project
                                                    (string= (project-record-id current-project)
                                                             (project-record-id project)))
                                         (project-summary project)))
                                     explicit-selected-projects)))
                (remove nil
                        (mapcar (lambda (project)
                                  (unless (and current-id
                                               (string= (getf project :id) current-id))
                                    project))
                                projects)))
            limit))
         (selection-posture
          (if explicit-selected-projects
              (list :selection-confident-p t
                    :selection-basis :explicit-context-chat-selection
                    :prompt-match-score nil
                    :matching-linked-project-count
                    (max 0 (1- (length explicit-selected-projects)))
                    :best-linked-project-match nil)
              (project-selection-posture-from-prompt prompt
                                                     (and current-project
                                                          (project-summary current-project))
                                                     projects
                                                     (and session (list-project-records session))))))
    (when current-project
      (list :current-project-id (project-record-id current-project)
            :project-count (length projects)
            :projects (compact-list projects limit)
            :linked-projects linked-projects
            :selected-project-ids
            (if explicit-selected-projects
                (mapcar #'project-record-id explicit-selected-projects)
                (and current-project
                     (list (project-record-id current-project))))
            :primary-project-id (project-record-id current-project)
            :selected-project-source (cond
                                       (explicit-selected-projects :explicit-context-chat-selection)
                                       (current-id :session-selection)
                                       (t :none))
            :ambiguity-risk (cond
                              ((and explicit-selected-projects
                                    (> (length explicit-selected-projects) 1))
                               :explicit-multi-project)
                              ((> (length projects) 1) :multi-project)
                              ((= (length projects) 1) :single-project)
                              (t :none))
            :selection-confident-p (getf selection-posture :selection-confident-p)
            :selection-posture selection-posture
            :summary (project-summary current-project)
            :constitution (copy-list (or (project-record-constitution current-project) '()))
            :requirements (mapcar #'summarized-project-requirement
                                  (compact-list (or (project-record-requirements current-project) '()) limit))
            :feature-specifications (mapcar #'summarized-project-feature-spec
                                            (compact-list (or (project-record-feature-specifications current-project) '()) limit))
            :user-journeys (mapcar #'summarized-project-user-journey
                                   (compact-list (or (project-record-user-journeys current-project) '()) limit))
            :non-functional-requirements (mapcar #'summarized-project-requirement
                                                 (compact-list (or (project-record-non-functional-requirements current-project) '()) limit))
            :architecture-decisions (mapcar #'summarized-project-architecture-decision
                                            (compact-list (or (project-record-architecture-decisions current-project) '()) limit))
            :linked-work-items linked-work-items
            :linked-incidents linked-incidents
            :linked-testing-harnesses testing-harnesses
            :testing-evidence (project-testing-evidence-summary)
            :release-readiness (copy-list (or (getf (project-record-metadata current-project)
                                                    :release-readiness)
                                              '()))
            :readiness-obligations (compact-list
                                    (copy-list (or (getf (project-record-metadata current-project)
                                                          :readiness-obligations)
                                                   '()))
                                    limit)
            :quality-gate-evidence quality-gate-evidence
            :readiness-summary readiness-summary
            :design-system (copy-list (or (project-record-design-system current-project) '()))
            :style-guide (copy-list (or (project-record-style-guide current-project) '()))
            :source-roots (copy-list (or (project-record-source-roots current-project) '()))
            :metadata (service-response-metadata response)
            :detail-p (retrieval-plan-project-detail-p plan)))))

(defun compact-trace-neighborhood-summary (summary &optional (limit 6))
  (when summary
    (list :entity-kind (getf summary :entity-kind)
          :entity-id (getf summary :entity-id)
          :count (getf summary :count)
          :outbound (compact-list (or (getf summary :outbound) '()) limit)
          :inbound (compact-list (or (getf summary :inbound) '()) limit))))

(defun build-trace-dossier-section (session plan intent-context project-context workflow-context incident-context)
  (let* ((limit (retrieval-plan-limit plan :project 4))
         (intent-id (and intent-context
                         (getf intent-context :current-intent-id)))
         (intent-neighborhood
           (and intent-id
                (compact-trace-neighborhood-summary
                 (trace-neighborhood-summary session :intent intent-id)
                 limit)))
         (project-id (and project-context
                          (getf project-context :current-project-id)))
         (project-neighborhood
           (and project-id
                (compact-trace-neighborhood-summary
                 (trace-neighborhood-summary session :project project-id)
                 limit)))
         (work-item-ids
           (remove-duplicates
            (remove nil
                    (append (mapcar (lambda (entry) (getf entry :id))
                                    (or (and project-context
                                             (getf project-context :linked-work-items))
                                        '()))
                            (mapcar (lambda (entry) (getf entry :id))
                                    (or (and workflow-context
                                             (getf workflow-context :work-items))
                                        '()))))
            :test #'string=))
         (incident-ids
           (remove-duplicates
            (remove nil
                    (append (mapcar (lambda (entry) (getf entry :id))
                                    (or (and project-context
                                             (getf project-context :linked-incidents))
                                        '()))
                            (mapcar (lambda (entry) (getf entry :id))
                                    (or (and incident-context
                                             (getf incident-context :incidents))
                                        '()))))
            :test #'string=))
         (work-item-neighborhoods
           (remove nil
                   (mapcar (lambda (work-item-id)
                             (compact-trace-neighborhood-summary
                              (trace-neighborhood-summary session :work-item work-item-id)
                              limit))
                           (compact-list work-item-ids 3))))
         (incident-neighborhoods
           (remove nil
                   (mapcar (lambda (incident-id)
                             (compact-trace-neighborhood-summary
                              (trace-neighborhood-summary session :incident incident-id)
                              limit))
                           (compact-list incident-ids 3))))
         (focused-links
           (mapcar #'trace-link-summary
                   (compact-list (list-trace-links session)
                                 (retrieval-plan-limit plan :events 8)))))
    (when (or intent-neighborhood project-neighborhood work-item-neighborhoods incident-neighborhoods focused-links)
      (list :summary (format nil
                             "Trace graph includes ~D intent, ~D project, ~D work-item, and ~D incident neighborhoods."
                             (if intent-neighborhood 1 0)
                             (if project-neighborhood 1 0)
                             (length work-item-neighborhoods)
                             (length incident-neighborhoods))
            :intent-neighborhood intent-neighborhood
            :project-neighborhood project-neighborhood
            :work-item-neighborhoods work-item-neighborhoods
            :incident-neighborhoods incident-neighborhoods
            :link-count (length (list-trace-links session))
            :focused-links focused-links))))

(defun build-source-dossier-section (session prompt plan)
  (let* ((environment-summary (service-response-data
                               (query-environment-summary-service (ensure-environment)
                                                                  :include-alignment-state-p nil
                                                                  :include-reconciliation-decision-p nil)))
         (runtime-summary (service-response-data (query-runtime-summary-service session)))
         (symbol-target (maybe-resolve-prompt-symbol session prompt))
         (symbol-name (and symbol-target (getf symbol-target :symbol)))
         (package-name (and symbol-target (getf symbol-target :package)))
         (workspace-limit (retrieval-plan-limit plan :workspace 4))
         (describe-response (and symbol-name
                                 (query-runtime-describe-symbol-service session symbol-name :package package-name)))
         (definition-response (and symbol-name
                                   (query-runtime-find-definition-service session symbol-name :package package-name)))
         (callers-response (and symbol-name
                                (query-runtime-callers-service session symbol-name :package package-name)))
         (methods-response (and symbol-name
                                (ignore-errors
                                  (query-runtime-methods-service session symbol-name :package package-name))))
         (divergence-response (and symbol-name
                                   (query-runtime-source-image-divergence-service session symbol-name :package package-name)))
         (definition-data (and definition-response (service-response-data definition-response)))
         (callers-data (and callers-response (service-response-data callers-response)))
         (methods-data (and methods-response (service-response-data methods-response)))
         (divergence-data (and divergence-response (service-response-data divergence-response))))
    (list :workspace-root (getf environment-summary :storage-root)
          :artifact-summary (getf environment-summary :artifact-summary)
          :package (getf runtime-summary :package)
          :loaded-systems (compact-list (or (getf runtime-summary :loaded-systems) '()) workspace-limit)
          :symbol-target symbol-target
          :describe (and describe-response
                         (dossier-section :workspace :describe-symbol describe-response))
          :definitions (and definition-response
                            (list :summary (dossier-section :workspace :find-definition definition-response)
                                  :items (compact-list (or (getf definition-data :definitions) '()) workspace-limit)
                                  :count (getf definition-data :definition-count)))
          :callers (and callers-response
                        (list :summary (dossier-section :workspace :callers callers-response)
                              :items (compact-list (or (getf callers-data :callers) '()) workspace-limit)
                              :count (getf callers-data :caller-count)))
          :methods (and methods-response
                        (list :summary (dossier-section :workspace :methods methods-response)
                              :items (compact-list (or (getf methods-data :methods) '()) workspace-limit)
                              :count (getf methods-data :method-count)))
          :divergence (and divergence-response
                           (dossier-section :workspace :source-image-divergence divergence-response))
          :note (if symbol-target
                    "Workspace/source retrieval is enriched with symbol-targeted runtime/source inspection."
                    "Workspace/source retrieval includes loaded systems and awaits a symbol-bearing prompt for deeper source inspection."))))

(defun build-retrieval-dossier-from-plan (session prompt intent plan)
  (let* ((domains (retrieval-plan-domains plan))
         (operator-memory-present-p
           (find-if #'environment-memory-operator-memory-entry-p
                    (environment-memory-entries session)))
         (alignment-intent-context (when (find :intent domains)
                                     (build-intent-dossier-section session plan)))
         (artifact-context (when (find :artifact domains)
                             (build-artifact-dossier-section session)))
         (workflow-context (when (find :workflow domains)
                             (build-workflow-dossier-section session plan)))
         (incident-context (when (find :incident domains)
                             (build-incident-dossier-section session plan)))
         (project-context (when (find :project domains)
                            (build-project-dossier-section session prompt plan)))
         (source-context (when (find :workspace domains)
                           (build-source-dossier-section session prompt plan)))
         (trace-context (when (or (find :intent domains)
                                  (find :project domains)
                                  (find :workflow domains)
                                  (find :incident domains))
                          (build-trace-dossier-section session
                                                       plan
                                                       alignment-intent-context
                                                       project-context
                                                       workflow-context
                                                       incident-context))))
    (make-retrieval-dossier
     :phase :pre-prompt
     :intent intent
     :alignment-intent-context alignment-intent-context
     :plan plan
     :observed-consequences nil
     :conversation-context (when (or (find :conversation domains)
                                     operator-memory-present-p)
                             (build-conversation-dossier-section session prompt plan))
     :runtime-context (when (find :runtime domains)
                        (build-runtime-dossier-section session plan))
     :telemetry-context (when (find :telemetry domains)
                          (build-telemetry-dossier-section session plan))
     :workflow-context workflow-context
     :incident-context incident-context
     :artifact-context artifact-context
     :environment-context (build-environment-dossier-section plan)
     :console-context (when (find :console domains)
                        (build-console-dossier-section prompt plan))
     :diagnostic-context (when (find :diagnostic domains)
                           (build-diagnostic-dossier-section prompt plan))
     :testing-context (when (find :testing domains)
                        (build-testing-dossier-section session prompt plan))
     :project-context project-context
     :source-context source-context
     :trace-context trace-context
     :gaps (append (when (and (find :intent domains) (null alignment-intent-context))
                     (list "Intent retrieval was requested but no current intent context was assembled."))
                   (when (and (find :project domains) (null project-context))
                     (list "Project retrieval was requested but no current project context was assembled."))
                   (when (and (find :workspace domains) (null source-context))
                     (list "Workspace retrieval was requested but no source context was assembled."))
                   (when (and (find :testing domains)
                              (null (build-testing-dossier-section session prompt plan)))
                     (list "Testing retrieval was requested but no testing context was assembled."))
                   (when (and (find :artifact domains) (null artifact-context))
                     (list "Artifact retrieval was requested but no artifact context was assembled."))))))

(defun dossier-thin-domain-p (dossier domain)
  (case domain
    (:workflow
     (let ((context (retrieval-dossier-workflow-context dossier)))
       (and context
            (null (or (getf context :work-items) '()))
            (null (or (getf context :workflow-records) '())))))
    (:incident
     (let ((context (retrieval-dossier-incident-context dossier)))
       (and context
            (null (or (getf context :incidents) '())))))
    (:runtime
     (let ((context (retrieval-dossier-runtime-context dossier)))
       (and context
            (null (getf context :history)))))
    (:telemetry
     (let ((context (retrieval-dossier-telemetry-context dossier)))
       (and context
            (null (or (getf context :processes) '())))))
    (:console
     (let ((context (retrieval-dossier-console-context dossier)))
       (and context
            (null (append (or (getf context :environment-entries) '())
                          (or (getf context :host-entries) '()))))))
    (:diagnostic
     (let ((context (retrieval-dossier-diagnostic-context dossier)))
       (and context
            (null (or (getf context :reports) '())))))
    (:testing
     (let ((context (retrieval-dossier-testing-context dossier)))
       (and context
            (null (or (getf context :harnesses) '()))
            (null (getf context :latest-report))
            (null (getf context :performance)))))
    (:project
     (let ((context (retrieval-dossier-project-context dossier)))
       (and context
            (null (getf context :summary))
            (null (or (getf context :requirements) '()))
            (null (or (getf context :user-journeys) '()))
            (null (or (getf context :linked-work-items) '()))
            (null (or (getf context :linked-incidents) '())))))
    (otherwise
     nil)))

(defun retrieval-expansion-reason (dossier)
  (let* ((plan (retrieval-dossier-plan dossier))
         (domains (retrieval-plan-domains plan)))
    (cond
      ((or (null (retrieval-plan-expansion-posture plan))
           (eq (retrieval-plan-expansion-posture plan) :compact-first))
       nil)
      ((> (length (or (retrieval-dossier-gaps dossier) '())) 0)
       :gaps)
      ((find-if (lambda (domain) (dossier-thin-domain-p dossier domain)) domains)
       :thin-context)
      (t
       nil))))

(defun maybe-expand-retrieval-dossier (session prompt intent dossier)
  (let* ((plan (retrieval-dossier-plan dossier))
         (reason (retrieval-expansion-reason dossier)))
    (if (and reason
             (< (or (retrieval-plan-expansion-pass plan) 0) 1))
        (build-retrieval-dossier-from-plan session
                                           prompt
                                           intent
                                           (expand-retrieval-plan plan reason))
        dossier)))

(defun build-retrieval-dossier (session prompt &key (operator-mode :repl-bridge))
  (let* ((intent (classify-retrieval-intent prompt :operator-mode operator-mode))
         (plan (build-retrieval-plan prompt
                                     :session session
                                     :operator-mode operator-mode))
         (dossier (maybe-expand-retrieval-dossier session
                                                  prompt
                                                  intent
                                                  (build-retrieval-dossier-from-plan session prompt intent plan))))
    (setf (retrieval-dossier-ranking dossier)
          (build-retrieval-ranking prompt dossier)
          (retrieval-dossier-decisive-context-core dossier)
          (build-decisive-context-core dossier))
    dossier))
