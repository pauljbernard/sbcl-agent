(in-package #:sbcl-agent/tests)

(defvar *focused-concurrency-lock*
  (sb-thread:make-mutex :name "focused-concurrency-lock"))
(defvar *focused-concurrency-active-count* 0)
(defvar *focused-concurrency-max-count* 0)

(defun reset-focused-concurrency-state ()
  (sb-thread:with-mutex (*focused-concurrency-lock*)
    (setf *focused-concurrency-active-count* 0
          *focused-concurrency-max-count* 0)))

(defun focused-concurrency-sample (&optional (seconds 0.2))
  (sb-thread:with-mutex (*focused-concurrency-lock*)
    (incf *focused-concurrency-active-count*)
    (setf *focused-concurrency-max-count*
          (max *focused-concurrency-max-count*
               *focused-concurrency-active-count*)))
  (sleep seconds)
  (sb-thread:with-mutex (*focused-concurrency-lock*)
    (decf *focused-concurrency-active-count*))
  :ok)

(defun focused-concurrency-max-count ()
  (sb-thread:with-mutex (*focused-concurrency-lock*)
    *focused-concurrency-max-count*))

(defun focused-concurrency-core-keyed-serialization-test ()
  (labels ((measure-max-concurrency (mode lock-key-a lock-key-b)
             (reset-focused-concurrency-state)
             (let ((thread-a
                     (sb-thread:make-thread
                      (lambda ()
                        (sbcl-agent::call-with-concurrency-core-policy
                         mode
                         (lambda ()
                           (focused-concurrency-sample 0.2))
                         :lock-key lock-key-a))
                      :name "focused-concurrency-a"))
                   (thread-b
                     (sb-thread:make-thread
                      (lambda ()
                        (sbcl-agent::call-with-concurrency-core-policy
                         mode
                         (lambda ()
                           (focused-concurrency-sample 0.2))
                         :lock-key lock-key-b))
                      :name "focused-concurrency-b")))
               (sb-thread:join-thread thread-a)
               (sb-thread:join-thread thread-b)
               (focused-concurrency-max-count))))
    (let ((read-max (measure-max-concurrency :concurrent-read :read-a :read-b))
          (same-key-max (measure-max-concurrency :serialized-write :shared-write :shared-write))
          (different-key-max (measure-max-concurrency :serialized-write :domain-a-write :domain-b-write)))
      (assert-true (> read-max 1)
                   "focused concurrency regression should confirm concurrent-read overlap")
      (assert-equal 1
                    same-key-max
                    "focused concurrency regression should serialize same-key writes")
      (assert-true (> different-key-max 1)
                   "focused concurrency regression should permit different-key write overlap"))))

(defun focused-runtime-command-governance-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/private/tmp/"))
         (environment (sbcl-agent::make-default-environment :session session))
         (ignore (sbcl-agent::bind-session-to-environment session environment))
         (policy-id :runtime-eval-mutate)
         (actor-address (sbcl-agent::make-runtime-query-actor-address session))
         (actor-context (sbcl-agent::make-actor-execution-context
                         :actor-id (sbcl-agent::actor-address-id actor-address)
                         :capability :runtime/eval
                         :authority :governed-runtime
                         :policy-id policy-id
                         :target :runtime
                         :operation :eval
                         :request-id "focused-runtime-governance-request"
                         :approval-required-p t
                         :metadata '(:package "SBCL-AGENT-USER" :mutating t)))
         (denied-message nil))
    (declare (ignore ignore))
    (handler-case
        (sbcl-agent::enforce-runtime-actor-governance
         session
         :runtime/eval
         actor-context
         :policy-id policy-id
         :approval-required-p t)
      (error (condition)
        (setf denied-message (princ-to-string condition))))
    (let* ((events (sbcl-agent::agent-session-events session))
           (governance-event (find :runtime-actor-governance-enforcement
                                   events
                                   :key #'sbcl-agent::event-kind
                                   :test #'eq)))
      (assert-true denied-message
                   "focused runtime governance regression should deny unapproved governed execution")
      (assert-true governance-event
                   "focused runtime governance regression should emit actor-side governance enforcement"))
    (sbcl-agent::approve-policy session policy-id)
    (let* ((response
             (progn
               (sbcl-agent::enforce-runtime-actor-governance
                session
                :runtime/eval
                actor-context
                :policy-id policy-id
                :approval-required-p t)
               (sbcl-agent::actorize-runtime-command-response
                (sbcl-agent::make-service-command-response
                 :runtime
                 :eval
                 '(:result 42)
                 :metadata (sbcl-agent::make-service-metadata :authority :environment
                                                              :command-model :runtime-command-test-v1
                                                              :session session
                                                              :runtime-id (sbcl-agent::default-runtime-id)
                                                              :policy-id policy-id))
                :actor-execution-job-id "focused-runtime-governance-job"
                :governance-authority :actor-runtime
                :policy-id policy-id
                :approval-required-p t
                :approval-granted-p t)))
           (metadata (sbcl-agent::service-response-metadata response))
           (data (sbcl-agent::service-response-data response)))
      (assert-equal :actor-runtime
                    (getf metadata :governance-authority)
                    "focused runtime governance regression should mark actor-runtime metadata authority")
      (assert-equal policy-id
                    (getf metadata :policy-id)
                    "focused runtime governance regression should retain the governing policy id")
      (assert-true (getf metadata :approval-required-p)
                   "focused runtime governance regression should retain approval-required metadata")
      (assert-true (stringp (getf metadata :actor-execution-job-id))
                   "focused runtime governance regression should expose actor execution identity")
      (assert-equal :actor-runtime
                    (getf data :governance-authority)
                    "focused runtime governance regression should mark actor-runtime payload authority")
      (assert-equal policy-id
                    (getf data :policy-id)
                    "focused runtime governance regression should retain payload policy id"))))

(defun focused-actor-thread-pool-serializes-per-actor-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/private/tmp/"))
         (environment (sbcl-agent::make-default-environment :session session))
         (ignore (sbcl-agent::bind-session-to-environment session environment))
         (runtime-actor (sbcl-agent::make-standard-actor-address
                         :runtime
                         :scope (sbcl-agent::agent-session-id session)))
         (request (sbcl-agent::make-desktop-task-request
                   :id "focused-actor-serialization-request"
                   :protocol-version 1
                   :requester :context-chat
                   :actor-message (sbcl-agent::make-actor-message
                                   :id "focused-actor-serialization-message"
                                   :receiver runtime-actor)
                   :target :runtime
                   :operation :evaluate-form
                   :payload '(:form "(+ 1 1)")
                   :capability :runtime-eval-safe
                   :metadata '()))
         (current-active 0)
         (max-active 0)
         (lock (sb-thread:make-mutex :name "focused-actor-serialization-lock")))
    (declare (ignore ignore))
    (unwind-protect
         (flet ((exercise-worker ()
                  (sbcl-agent::call-with-actor-worker-for-request
                   session
                   request
                   (lambda ()
                     (sb-thread:with-mutex (lock)
                       (incf current-active)
                       (setf max-active (max max-active current-active)))
                     (unwind-protect
                          (sleep 0.15)
                       (sb-thread:with-mutex (lock)
                         (decf current-active)))))))
           (let ((thread-a (sb-thread:make-thread #'exercise-worker
                                                  :name "focused-actor-serialization-a"))
                 (thread-b (sb-thread:make-thread #'exercise-worker
                                                  :name "focused-actor-serialization-b")))
             (sb-thread:join-thread thread-a)
             (sb-thread:join-thread thread-b)
             (assert-equal 1
                           max-active
                           "focused actor regression should serialize same-actor jobs"))))
      (sbcl-agent::stop-actor-thread-pool session)))

(defun focused-actor-runtime-queue-drain-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/private/tmp/"))
         (environment (sbcl-agent::make-default-environment :session session))
         (ignore (sbcl-agent::bind-session-to-environment session environment))
         (job-a nil)
         (job-b nil))
    (declare (ignore ignore))
    (unwind-protect
         (progn
           (sbcl-agent::start-actor-thread-pool session :pool-size 1)
           (setf job-a
                 (sbcl-agent::enqueue-actor-execution-job
                  session
                  "actor/runtime"
                  (lambda ()
                    (sleep 0.15)
                    :job-a)
                  :context (sbcl-agent::make-actor-execution-context
                            :actor-id "actor/runtime"
                            :capability :runtime/benchmark
                            :authority :benchmark
                            :target :runtime
                            :operation :queue-drain)))
           (setf job-b
                 (sbcl-agent::enqueue-actor-execution-job
                  session
                  "actor/runtime"
                  (lambda ()
                    :job-b)
                  :context (sbcl-agent::make-actor-execution-context
                            :actor-id "actor/runtime"
                            :capability :runtime/benchmark
                            :authority :benchmark
                            :target :runtime
                            :operation :queue-drain)))
           (assert-equal :job-a
                         (sbcl-agent::await-actor-execution-job job-a)
                         "focused actor queue regression should complete the first queued job")
           (assert-equal :job-b
                         (sbcl-agent::await-actor-execution-job job-b)
                         "focused actor queue regression should complete the second queued job")
           (let ((summary (sbcl-agent::actor-runtime-state-summary session)))
             (assert-equal 2
                           (getf summary :submitted-job-count)
                           "focused actor queue regression should record submitted jobs")
             (assert-equal 2
                           (getf summary :completed-job-count)
                           "focused actor queue regression should record completed jobs")
             (assert-equal 0
                           (getf summary :queue-depth)
                           "focused actor queue regression should drain the runtime queue")
             (assert-equal 0
                           (getf summary :busy-worker-count)
                           "focused actor queue regression should leave workers idle after drain"))))
      (sbcl-agent::stop-actor-thread-pool session)))

(defun focused-actor-max-concurrency-test ()
  (let* ((session (sbcl-agent::make-default-session :cwd "/private/tmp/"))
         (environment (sbcl-agent::make-default-environment :session session))
         (ignore (sbcl-agent::bind-session-to-environment session environment))
         (current-active 0)
         (max-active 0)
         (lock (sb-thread:make-mutex :name "focused-actor-max-concurrency-lock"))
         (jobs '()))
    (declare (ignore ignore))
    (unwind-protect
        (progn
          (sbcl-agent::start-actor-thread-pool session :pool-size 3)
          (flet ((make-job (name)
                   (sbcl-agent::enqueue-actor-execution-job
                    session
                    "actor/runtime"
                    (lambda ()
                      (sb-thread:with-mutex (lock)
                        (incf current-active)
                        (setf max-active (max max-active current-active)))
                      (unwind-protect
                           (progn
                             (sleep 0.15)
                             name)
                        (sb-thread:with-mutex (lock)
                          (decf current-active))))
                    :max-concurrency 2
                    :context (sbcl-agent::make-actor-execution-context
                              :actor-id "actor/runtime"
                              :capability :runtime/benchmark
                              :authority :benchmark
                              :target :runtime
                              :operation :max-concurrency))))
            (setf jobs
                  (list (make-job :job-a)
                        (make-job :job-b)
                        (make-job :job-c)))
            (assert-equal '(:job-a :job-b :job-c)
                          (mapcar #'sbcl-agent::await-actor-execution-job jobs)
                          "focused actor max-concurrency regression should complete all queued jobs")
            (assert-equal 2
                          max-active
                          "focused actor max-concurrency regression should honor the per-actor concurrency bound")))
      (sbcl-agent::stop-actor-thread-pool session))))

(defun focused-concurrent-read-not-blocked-by-write-test ()
  (let ((write-thread nil)
        (read-thread nil)
        (read-elapsed nil)
        (read-result nil))
    (unwind-protect
         (progn
           (setf write-thread
                 (sb-thread:make-thread
                  (lambda ()
                    (sbcl-agent::call-with-concurrency-core-policy
                     :serialized-write
                     (lambda ()
                       (sleep 0.25)
                       :write-done)
                     :lock-key :focused-write))
                  :name "focused-write-thread"))
           (sleep 0.05)
           (setf read-thread
                 (sb-thread:make-thread
                  (lambda ()
                    (let ((start (get-internal-real-time)))
                      (setf read-result
                            (sbcl-agent::call-with-concurrency-core-policy
                             :concurrent-read
                             (lambda ()
                               :read-done)))
                      (setf read-elapsed
                            (/ (- (get-internal-real-time) start)
                               internal-time-units-per-second))))
                  :name "focused-read-thread"))
           (sb-thread:join-thread read-thread)
           (assert-equal :read-done
                         read-result
                         "focused mixed-load regression should complete the read request")
           (assert-true (< read-elapsed 0.2)
                        "focused mixed-load regression should let reads complete without waiting for serialized writes")
           (sb-thread:join-thread write-thread))
      (when (and read-thread (sb-thread:thread-alive-p read-thread))
        (sb-thread:join-thread read-thread))
      (when (and write-thread (sb-thread:thread-alive-p write-thread))
        (sb-thread:join-thread write-thread)))))

(defun focused-concurrency-regression-tests ()
  (list (list "focused-concurrency-core-keyed-serialization-test"
              #'focused-concurrency-core-keyed-serialization-test)
        (list "focused-runtime-command-governance-test"
              #'focused-runtime-command-governance-test)
        (list "focused-actor-thread-pool-serializes-per-actor-test"
              #'focused-actor-thread-pool-serializes-per-actor-test)
        (list "focused-actor-max-concurrency-test"
              #'focused-actor-max-concurrency-test)
        (list "focused-actor-runtime-queue-drain-test"
              #'focused-actor-runtime-queue-drain-test)
        (list "focused-concurrent-read-not-blocked-by-write-test"
              #'focused-concurrent-read-not-blocked-by-write-test)))

(defun run-focused-concurrency-test-case (name thunk)
  (funcall thunk)
  (format t "PASS ~A~%" name))

(defun run-concurrency-regressions ()
  (dolist (case (focused-concurrency-regression-tests))
    (run-focused-concurrency-test-case (first case) (second case))))
