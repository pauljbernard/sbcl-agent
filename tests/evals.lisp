(in-package #:sbcl-agent/tests)

(defparameter *evaluation-task-families*
  '((:id :repo-q-and-a
     :label "Repo Q&A"
     :description "Can the system answer grounded questions about the repository and surface cognition metadata?")
    (:id :governed-mutation
     :label "Governed Mutation"
     :description "Can the system propose a governed mutation while preserving approval posture and workflow evidence?")
    (:id :followup-recovery
     :label "Follow-up Recovery"
     :description "Can the system resume governed work and carry follow-up cognition correctly?")
    (:id :runtime-debugging
     :label "Runtime Debugging"
     :description "Can retrieval and reasoning engage runtime-centric requests cleanly?")
    (:id :long-horizon
     :label "Long-Horizon"
     :description "Multi-step resumable execution tasks with durable plan continuity.")
    (:id :parallel-orchestration
     :label "Parallel Orchestration"
     :description "Coordinated multi-worker execution tasks with shared orchestration metadata.")
    (:id :self-improvement
     :label "Self-Improvement"
     :description "Reflective engineering and improvement proposals grounded in prior outcomes.")))

(defun evaluation-family-definition (family-id)
  (find family-id *evaluation-task-families*
        :key (lambda (entry) (getf entry :id))
        :test #'eq))

(defun evaluation-result (family-id status &key score duration-seconds notes metrics)
  (let ((definition (evaluation-family-definition family-id)))
    (list :family-id family-id
          :label (getf definition :label)
          :status status
          :score (or score 0.0)
          :duration-seconds (or duration-seconds 0.0)
          :notes notes
          :metrics metrics)))

(defun run-evaluation-case (family-id thunk)
  (let ((started (get-internal-real-time)))
    (handler-case
        (let ((payload (funcall thunk)))
          (let ((duration (/ (- (get-internal-real-time) started)
                             internal-time-units-per-second)))
            (append (evaluation-result family-id
                                       :passed
                                       :score 1.0
                                       :duration-seconds duration)
                    payload)))
      (error (condition)
        (let ((duration (/ (- (get-internal-real-time) started)
                           internal-time-units-per-second)))
          (evaluation-result family-id
                             :failed
                             :score 0.0
                             :duration-seconds duration
                             :notes (princ-to-string condition)))))))

(defun run-repo-q-and-a-eval ()
  (let* ((provider (make-test-provider))
         (session (make-test-session :cwd "/tmp/sbcl-agent-eval-repo-qa/"))
         (result (sbcl-agent::run-conversation-turn provider
                                                    session
                                                    "Inspect the runtime and summarize the current code context."
                                                    :stream-p nil
                                                    :source :say
                                                    :operator-mode :conversation)))
    (unless (listp (getf result :cognition-summary))
      (error "Expected cognition summary in repo Q&A eval"))
    (unless (listp (getf result :action-agenda-summary))
      (error "Expected action agenda summary in repo Q&A eval"))
    (list :metrics (list :has-cognition-summary t
                         :has-action-agenda-summary t
                         :retrieval-category (getf (getf result :retrieval-summary) :category)
                         :agenda-step-count (getf (getf result :action-agenda-summary) :step-count)))))

(defun run-governed-mutation-eval ()
  (let* ((provider (make-instance 'patch-action-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/sbcl-agent-eval-governed-mutation/"))
         (command (sbcl-agent::normalize-form-command '(say "prepare governed patch"))))
    (multiple-value-bind (result kind updated-session)
        (sbcl-agent::execute-command command provider session)
      (declare (ignore updated-session))
      (unless (eq kind :say)
        (error "Expected :say dispatch for governed mutation eval"))
      (unless (eq (getf (getf result :turn) :status) :awaiting-approval)
        (error "Expected awaiting approval turn state for governed mutation eval"))
      (unless (= (getf result :staged-action-count) 1)
        (error "Expected one staged governed action"))
      (list :metrics (list :dispatch kind
                           :turn-status (getf (getf result :turn) :status)
                           :staged-action-count (getf result :staged-action-count)
                           :agenda-step-count (getf (getf result :action-agenda-summary) :step-count))))))

(defun run-followup-recovery-eval ()
  (let* ((provider (make-instance 'followup-patch-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/sbcl-agent-eval-followup/")))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare patch and continue"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :workspace-write))
     provider
     session)
    (multiple-value-bind (resume-result resume-kind resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (declare (ignore resumed-session))
      (unless (eq resume-kind :turn-resume)
        (error "Expected :turn-resume for follow-up recovery eval"))
      (unless (getf (getf resume-result :followup) :followup-p)
        (error "Expected structured follow-up payload"))
      (unless (listp (getf (getf resume-result :followup) :action-agenda-summary))
        (error "Expected action agenda summary in follow-up payload"))
      (list :metrics (list :resume-kind resume-kind
                           :followup-p t
                           :followup-agenda-step-count
                           (getf (getf (getf resume-result :followup) :action-agenda-summary)
                                 :step-count))))))

(defun run-runtime-debugging-eval ()
  (let* ((session (make-test-session :cwd "/tmp/sbcl-agent-eval-runtime-debugging/"))
         (payload (sbcl-agent::service-response-data
                   (sbcl-agent::query-retrieval-dossier-service
                    session
                    "Inspect the runtime and explain the current package and loaded systems."
                    :operator-mode :conversation)))
         (intent (getf payload :intent))
         (ranking (getf payload :ranking)))
    (unless (member (getf intent :category) '(:runtime-debugging :runtime-inspection) :test #'eq)
      (error "Expected runtime-centric retrieval intent"))
    (unless (find :runtime (getf intent :domains) :test #'eq)
      (error "Expected runtime domain in runtime debugging eval"))
    (unless (eq (getf ranking :strategy) :disabled)
      (error "Expected direct symbolic retrieval for runtime debugging eval"))
    (list :metrics (list :intent-category (getf intent :category)
                         :domains (getf intent :domains)
                         :ranking-enabled-p (getf ranking :enabled-p)
                         :ranking-strategy (getf ranking :strategy)))))

(defun run-self-improvement-eval ()
  (let* ((session (make-test-session :cwd "/tmp/sbcl-agent-eval-self-improvement/"))
         (environment (sbcl-agent::make-default-environment :session session
                                                            :storage-root "/tmp/sbcl-agent-eval-self-improvement/")))
    (sbcl-agent::bind-session-to-environment session environment)
    (setf (sbcl-agent::environment-memory environment)
          (list
           (list :kind :failure-cluster
                 :memory-id "cluster-runtime-incidents"
                 :cluster-key "cluster-runtime-incidents"
                 :title "runtime-debugging / incidents=yes / weak-grounding=no"
                 :retrieval-category :runtime-debugging
                 :failure-count 3
                 :guidance "Inspect incident evidence and recovery history before repeating this path."
                 :sample-prompts '("Investigate the runtime incident and recover safely.")
                 :improvement-proposals
                 '((:kind :incident-preflight
                    :statement "Add incident-aware preflight checks before mutating along this path.")))))
    (let ((brief (sbcl-agent::build-prior-outcome-brief
                  session
                  "Investigate the runtime incident and recover safely."
                  :current-turn-id nil)))
      (unless (> (or (getf brief :failure-cluster-count) 0) 0)
        (error "Expected failure-cluster coverage in self-improvement eval"))
      (unless (> (length (or (getf brief :improvement-proposals) '())) 0)
        (error "Expected improvement proposals in self-improvement eval"))
      (list :metrics (list :failure-cluster-count (getf brief :failure-cluster-count)
                           :improvement-proposal-count (length (or (getf brief :improvement-proposals) '()))
                           :first-proposal-kind (getf (first (getf brief :improvement-proposals)) :kind))))))

(defun run-long-horizon-eval ()
  (let* ((provider (make-instance 'followup-patch-provider))
         (session (sbcl-agent::make-default-session :cwd "/tmp/sbcl-agent-eval-long-horizon/")))
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(say "prepare patch and continue"))
     provider
     session)
    (sbcl-agent::execute-command
     (sbcl-agent::normalize-form-command '(approve :workspace-write))
     provider
     session)
    (multiple-value-bind (resume-result resume-kind resumed-session)
        (sbcl-agent::execute-command
         (sbcl-agent::normalize-form-command '(turn/resume))
         provider
         session)
      (declare (ignore resumed-session))
      (unless (eq resume-kind :turn-resume)
        (error "Expected turn/resume dispatch in long-horizon eval"))
        (let* ((turn (sbcl-agent::most-recent-thread-turn session))
               (work-item-id (getf (sbcl-agent::turn-metadata turn) :work-item-id))
               (work-item (and work-item-id (sbcl-agent::find-work-item session work-item-id)))
               (summary (and work-item (sbcl-agent::work-item-summary work-item))))
        (unless (listp (and summary (getf summary :long-horizon-plan)))
          (error "Expected durable long-horizon plan in work-item summary"))
        (unless (listp (and summary (getf summary :plan-steering)))
          (error "Expected long-horizon steering snapshot in work-item summary"))
        (unless (member (getf (getf summary :plan-steering) :revision-reason)
                        '(:blocked-awaiting-resume :validation-pending :incident-recovery :partial-progress :steady-state)
                        :test #'eq)
          (error "Expected a valid long-horizon revision reason in work-item steering"))
        (unless (listp (getf resume-result :followup))
          (error "Expected structured follow-up payload in long-horizon eval"))
        (list :metrics (list :resume-kind resume-kind
                             :plan-health (and summary (getf summary :plan-health))
                             :current-phase (and summary (getf (getf summary :plan-steering) :current-phase))
                             :revision-reason (and summary (getf (getf summary :plan-steering) :revision-reason))
                             :agenda-step-count (getf (getf summary :long-horizon-plan) :agenda-step-count)
                             :followup-p (getf (getf resume-result :followup) :followup-p)))))))

(defun run-parallel-orchestration-eval ()
  (let* ((provider (make-instance 'slow-test-provider))
         (session (make-test-session :cwd "/tmp/sbcl-agent-eval-parallel-orchestration/"))
         (tasks (sbcl-agent::enqueue-parallel-task-group
                 session
                 (list (list :command (sbcl-agent::normalize-form-command '(say "parallel eval task a"))
                             :ownership-scope '("src/eval-a.lisp"))
                       (list :command (sbcl-agent::normalize-form-command '(say "parallel eval task b"))
                             :ownership-scope '("src/eval-b.lisp")))
                 :shared-context '(:goal "parallel eval patch set")
                 :merge-policy :serial-review)))
    (sbcl-agent::start-worker session provider)
    (sbcl-agent::start-worker session provider)
    (unwind-protect
         (progn
           (wait-for (lambda ()
                       (every (lambda (task)
                                (eq :completed (sbcl-agent::task-status task)))
                              tasks))
                     :timeout-seconds 30.0
                     :sleep-seconds 0.05)
           (let* ((group-id (sbcl-agent::task-orchestration-group-id (first tasks)))
                  (worker-ids (remove-duplicates (mapcar #'sbcl-agent::task-worker-id tasks)
                                                 :test #'string=))
                  (summaries (mapcar #'sbcl-agent::task-summary tasks))
                  (work-item-summaries (mapcar (lambda (task)
                                                 (sbcl-agent::work-item-summary
                                                  (sbcl-agent::find-work-item session
                                                                              (sbcl-agent::task-work-item-id task))))
                                               tasks)))
             (unless (and group-id (every (lambda (summary)
                                            (string= group-id
                                                     (getf (getf summary :orchestration) :group-id)))
                                          summaries))
               (error "Expected a stable orchestration group across all parallel tasks"))
             (unless (every (lambda (summary)
                              (eq :serial-review (getf (getf summary :orchestration) :merge-policy)))
                            summaries)
               (error "Expected a stable merge policy across all parallel tasks"))
             (unless (= 2 (length worker-ids))
               (error "Expected two distinct workers to complete the parallel orchestration eval"))
             (unless (every (lambda (summary)
                              (eq :serial-review-merge
                                  (getf (getf summary :next-action) :type)))
                            work-item-summaries)
               (error "Expected serial-review orchestration to surface a governed review posture"))
             (list :metrics (list :task-count (length tasks)
                                  :group-id group-id
                                  :distinct-worker-count (length worker-ids)
                                  :merge-policy (getf (getf (first summaries) :orchestration) :merge-policy)
                                  :review-next-action (getf (getf (first work-item-summaries) :next-action) :type)
                                  :shared-context (getf (getf (first summaries) :orchestration) :shared-context)))))
      (sbcl-agent::stop-all-workers session))))

(defun internal-evaluation-report ()
  (let* ((results (list (run-evaluation-case :repo-q-and-a #'run-repo-q-and-a-eval)
                        (run-evaluation-case :governed-mutation #'run-governed-mutation-eval)
                        (run-evaluation-case :followup-recovery #'run-followup-recovery-eval)
                        (run-evaluation-case :runtime-debugging #'run-runtime-debugging-eval)
                        (run-evaluation-case :long-horizon #'run-long-horizon-eval)
                        (run-evaluation-case :parallel-orchestration #'run-parallel-orchestration-eval)
                        (run-evaluation-case :self-improvement #'run-self-improvement-eval)
                        ))
         (completed (count-if (lambda (entry)
                                (member (getf entry :status) '(:passed :failed) :test #'eq))
                              results))
         (passed (count :passed results :key (lambda (entry) (getf entry :status)) :test #'eq))
         (implemented-score (if (> completed 0)
                                (/ (reduce #'+ results :key (lambda (entry) (or (getf entry :score) 0.0)))
                                   completed)
                                0.0)))
    (list :generated-at (get-universal-time)
          :family-count (length *evaluation-task-families*)
          :implemented-family-count completed
          :passed-family-count passed
          :implemented-score implemented-score
          :results results)))

(defun ensure-evaluation-report-directory ()
  (let ((root (merge-pathnames #P"tmp/evals/"
                               (uiop:ensure-directory-pathname
                                (uiop:getcwd)))))
    (ensure-directories-exist root)
    root))

(defun write-evaluation-report (report)
  (let* ((root (ensure-evaluation-report-directory))
         (path (merge-pathnames #P"latest.sexp" root)))
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (let ((*print-circle* t)
            (*print-pretty* t))
        (write report :stream stream)))
    path))

(defun print-evaluation-report (report)
  (format t "evaluation-report> implemented=~D/~D passed=~D score=~,2F~%"
          (getf report :implemented-family-count)
          (getf report :family-count)
          (getf report :passed-family-count)
          (getf report :implemented-score))
  (dolist (entry (getf report :results))
    (format t "evaluation-family> ~A status=~A score=~,2F duration=~,3Fs~%"
            (getf entry :family-id)
            (getf entry :status)
            (or (getf entry :score) 0.0)
            (or (getf entry :duration-seconds) 0.0))))

(defun run-internal-evaluations ()
  (let* ((report (internal-evaluation-report))
         (path (write-evaluation-report report))
         (session (and (boundp 'sbcl-agent::*current-session*)
                       sbcl-agent::*current-session*)))
    (when session
      (sbcl-agent::remember-evaluation-report-memory session report))
    (print-evaluation-report report)
    (format t "evaluation-report-path> ~A~%" (namestring path))
    report))

(defun evaluation-harness-smoke-test ()
  (let ((report (internal-evaluation-report)))
    (assert-equal 7
                  (getf report :family-count)
                  "internal evaluation harness should register the expected family count")
    (assert-true (>= (getf report :implemented-family-count) 4)
                 "internal evaluation harness should implement the initial Phase 1 families")
    (assert-true (> (getf report :passed-family-count) 0)
                 "internal evaluation harness should produce passing implemented families")
    (assert-true (find :repo-q-and-a (getf report :results)
                       :key (lambda (entry) (getf entry :family-id))
                       :test #'eq)
                 "internal evaluation harness should include repo Q&A coverage")
    (assert-true (find :long-horizon (getf report :results)
                       :key (lambda (entry) (getf entry :family-id))
                       :test #'eq)
                 "internal evaluation harness should include long-horizon placeholders")))
