(in-package #:sbcl-agent)

(defstruct calculator-session-state
  (expression "")
  (mode :basic)
  (base 10)
  (word-size 64)
  (angle-unit :radians)
  latest-result
  (history '()))

(defparameter +environment-calculator-state-key+ :calculator-state)

(defun calculator-state->plist (state)
  (list :expression (calculator-session-state-expression state)
        :mode (calculator-session-state-mode state)
        :base (calculator-session-state-base state)
        :word-size (calculator-session-state-word-size state)
        :angle-unit (calculator-session-state-angle-unit state)
        :latest-result (copy-tree (calculator-session-state-latest-result state))
        :history (copy-tree (calculator-session-state-history state))))

(defun calculator-state-from-plist (value)
  (let ((state (make-calculator-session-state)))
    (when (listp value)
      (setf (calculator-session-state-expression state) (or (getf value :expression) "")
            (calculator-session-state-mode state) (or (getf value :mode) :basic)
            (calculator-session-state-base state) (or (getf value :base) 10)
            (calculator-session-state-word-size state) (or (getf value :word-size) 64)
            (calculator-session-state-angle-unit state) (or (getf value :angle-unit) :radians)
            (calculator-session-state-latest-result state) (copy-tree (getf value :latest-result))
            (calculator-session-state-history state) (copy-tree (or (getf value :history) '()))))
    state))

(defun persist-calculator-session-state (environment state)
  (set-environment-metadata-value environment
                                  +environment-calculator-state-key+
                                  (calculator-state->plist state))
  state)

(defun calculator-session-state-for (session)
  (declare (ignore session))
  (let* ((environment (ensure-environment))
         (persisted (environment-metadata-value environment +environment-calculator-state-key+)))
    (if persisted
        (calculator-state-from-plist persisted)
        (persist-calculator-session-state environment
                                          (make-calculator-session-state)))))

(defun calculator-history-entry (expression result)
  (list :expression expression
        :mode (getf result :mode)
        :result (getf result :display-value)))

(defun calculator-summary-payload (session)
  (let* ((state (calculator-session-state-for session))
         (summary (copy-list (sbcl-agent.calculator:calculator-summary))))
    (append summary
            (list :current-expression (calculator-session-state-expression state)
                  :current-mode (calculator-session-state-mode state)
                  :current-base (calculator-session-state-base state)
                  :current-word-size (calculator-session-state-word-size state)
                  :current-angle-unit (calculator-session-state-angle-unit state)
                  :latest-result (calculator-session-state-latest-result state)
                  :history (copy-tree (calculator-session-state-history state))))))

(defun update-calculator-session-state (session &key expression mode base word-size angle-unit latest-result history)
  (let* ((environment (ensure-environment))
         (state (calculator-session-state-for session)))
    (when expression
      (setf (calculator-session-state-expression state) expression))
    (when mode
      (setf (calculator-session-state-mode state) mode))
    (when base
      (setf (calculator-session-state-base state) base))
    (when word-size
      (setf (calculator-session-state-word-size state) word-size))
    (when angle-unit
      (setf (calculator-session-state-angle-unit state) angle-unit))
    (when latest-result
      (setf (calculator-session-state-latest-result state) latest-result))
    (when history
      (setf (calculator-session-state-history state) history))
    (persist-calculator-session-state environment state)))

(defun calculator-command-response (session operation)
  (make-service-command-response
   :calculator
   operation
   (calculator-summary-payload session)
   :metadata (make-service-metadata :authority :environment
                                    :command-model :calculator-state-v1
                                    :session session
                                    :runtime-id (default-runtime-id)
                                    :policy-id :calculator-control)))

(defun query-calculator-summary-service (session)
  (make-service-query-response
   :calculator
   :summary
   (calculator-summary-payload session)
   :metadata (make-service-metadata :authority :environment
                                    :read-model :calculator-summary-v1
                                    :session session
                                    :runtime-id (default-runtime-id))))

(defun command-calculator-summary-query-service (session)
  (call-with-calculator-actor
   session
   (make-calculator-control-request session
                                    :summary
                                    :calculator/summary)
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read calculator session summary."
                                    "calculator/summary"
                                    :authority :environment))
   :calculator/summary
   :summary))

(defun make-calculator-control-actor-address (session)
  (make-standard-actor-address :calculator
                               :scope (agent-session-id session)))

(defun actorize-calculator-command-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (listp data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun make-calculator-control-request (session action capability &key payload metadata)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :calculator
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :calculator-control-v1)
                     metadata)))

(defun call-with-calculator-actor (session request thunk capability action &key metadata)
  (let ((actor-address (make-calculator-control-actor-address session)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-calculator-command-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :governance
               :target :calculator
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata metadata))))

(defun perform-calculator-set-expression-service (session expression)
  (update-calculator-session-state session
                                   :expression expression)
  (calculator-command-response session :set-expression))

(defun command-calculator-set-expression-service (session expression)
  (call-with-calculator-actor
   session
   (make-calculator-control-request session
                                    :set-expression
                                    :calculator/set-expression
                                    :payload (list :expression expression))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Set calculator expression to ~S." expression)
                                    "calculator/set-expression"
                                    :authority :environment
                                    :payload (list :expression expression)))
   :calculator/set-expression
   :set-expression
   :metadata (list :expression expression)))

(defun perform-calculator-append-token-service (session token)
  (let ((state (calculator-session-state-for session)))
    (update-calculator-session-state
     session
     :expression (concatenate 'string
                              (calculator-session-state-expression state)
                              token)))
  (calculator-command-response session :append-token))

(defun command-calculator-append-token-service (session token)
  (call-with-calculator-actor
   session
   (make-calculator-control-request session
                                    :append-token
                                    :calculator/append-token
                                    :payload (list :token token))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Append calculator token ~S." token)
                                    "calculator/append-token"
                                    :authority :environment
                                    :payload (list :token token)))
   :calculator/append-token
   :append-token
   :metadata (list :token token)))

(defun perform-calculator-backspace-service (session)
  (let* ((state (calculator-session-state-for session))
         (expression (calculator-session-state-expression state)))
    (update-calculator-session-state
     session
     :expression (if (> (length expression) 0)
                     (subseq expression 0 (1- (length expression)))
                     "")))
  (calculator-command-response session :backspace))

(defun command-calculator-backspace-service (session)
  (call-with-calculator-actor
   session
   (make-calculator-control-request session
                                    :backspace
                                    :calculator/backspace)
   (lambda ()
     (command-kernel-invoke-service session
                                    "Backspace calculator expression."
                                    "calculator/backspace"
                                    :authority :environment))
   :calculator/backspace
   :backspace))

(defun perform-calculator-clear-service (session)
  (update-calculator-session-state session
                                   :expression ""
                                   :latest-result nil)
  (calculator-command-response session :clear))

(defun command-calculator-clear-service (session)
  (call-with-calculator-actor
   session
   (make-calculator-control-request session
                                    :clear
                                    :calculator/clear)
   (lambda ()
     (command-kernel-invoke-service session
                                    "Clear calculator state."
                                    "calculator/clear"
                                    :authority :environment))
   :calculator/clear
   :clear))

(defun perform-calculator-set-mode-service (session mode)
  (update-calculator-session-state session
                                   :mode (sbcl-agent.calculator::normalize-mode mode))
  (calculator-command-response session :set-mode))

(defun command-calculator-set-mode-service (session mode)
  (call-with-calculator-actor
   session
   (make-calculator-control-request session
                                    :set-mode
                                    :calculator/set-mode
                                    :payload (list :mode mode))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Set calculator mode to ~A." mode)
                                    "calculator/set-mode"
                                    :authority :environment
                                    :payload (list :mode mode)))
   :calculator/set-mode
   :set-mode
   :metadata (list :mode mode)))

(defun perform-calculator-set-base-service (session base)
  (update-calculator-session-state session
                                   :base (sbcl-agent.calculator::normalize-base base))
  (calculator-command-response session :set-base))

(defun command-calculator-set-base-service (session base)
  (call-with-calculator-actor
   session
   (make-calculator-control-request session
                                    :set-base
                                    :calculator/set-base
                                    :payload (list :base base))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Set calculator base to ~A." base)
                                    "calculator/set-base"
                                    :authority :environment
                                    :payload (list :base base)))
   :calculator/set-base
   :set-base
   :metadata (list :base base)))

(defun perform-calculator-set-word-size-service (session word-size)
  (update-calculator-session-state session
                                   :word-size (sbcl-agent.calculator::normalize-word-size word-size))
  (calculator-command-response session :set-word-size))

(defun command-calculator-set-word-size-service (session word-size)
  (call-with-calculator-actor
   session
   (make-calculator-control-request session
                                    :set-word-size
                                    :calculator/set-word-size
                                    :payload (list :word-size word-size))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Set calculator word size to ~A." word-size)
                                    "calculator/set-word-size"
                                    :authority :environment
                                    :payload (list :word-size word-size)))
   :calculator/set-word-size
   :set-word-size
   :metadata (list :word-size word-size)))

(defun perform-calculator-set-angle-unit-service (session angle-unit)
  (update-calculator-session-state session
                                   :angle-unit (sbcl-agent.calculator::normalize-angle-unit angle-unit))
  (calculator-command-response session :set-angle-unit))

(defun command-calculator-set-angle-unit-service (session angle-unit)
  (call-with-calculator-actor
   session
   (make-calculator-control-request session
                                    :set-angle-unit
                                    :calculator/set-angle-unit
                                    :payload (list :angle-unit angle-unit))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Set calculator angle unit to ~A." angle-unit)
                                    "calculator/set-angle-unit"
                                    :authority :environment
                                    :payload (list :angle-unit angle-unit)))
   :calculator/set-angle-unit
   :set-angle-unit
   :metadata (list :angle-unit angle-unit)))

(defun perform-calculator-evaluate-service (session expression &key (mode :basic) (base 10) (word-size 64) (angle-unit :radians))
  (let* ((resolved-mode (sbcl-agent.calculator::normalize-mode mode))
         (resolved-base (sbcl-agent.calculator::normalize-base base))
         (resolved-word-size (sbcl-agent.calculator::normalize-word-size word-size))
         (resolved-angle-unit (sbcl-agent.calculator::normalize-angle-unit angle-unit))
         (result (sbcl-agent.calculator:evaluate-expression expression
                                                            :mode resolved-mode
                                                            :base resolved-base
                                                            :word-size resolved-word-size
                                                            :angle-unit resolved-angle-unit))
         (state (calculator-session-state-for session))
         (next-history (subseq (append (list (calculator-history-entry expression result))
                                       (calculator-session-state-history state))
                               0
                               (min 12
                                    (1+ (length (calculator-session-state-history state)))))))
    (update-calculator-session-state session
                                     :expression expression
                                     :mode resolved-mode
                                     :base resolved-base
                                     :word-size resolved-word-size
                                     :angle-unit resolved-angle-unit
                                     :latest-result result
                                     :history next-history)
    (kernelize-service-command-response
     (make-service-command-response
      :calculator
      :evaluate
      result
     :metadata (make-service-metadata :authority :environment
                                      :command-model :calculator-evaluate-v1
                                      :session session
                                      :runtime-id (default-runtime-id)
                                      :policy-id :calculator-control))
     :session session
     :intention (format nil "Evaluate calculator expression ~S in ~A mode." expression resolved-mode)
     :capability :calculator/evaluate
     :authority :runtime
     :constraints (list :mode resolved-mode
                        :base resolved-base
                        :word-size resolved-word-size
                        :angle-unit resolved-angle-unit))))

(defun command-calculator-evaluate-service (session expression &key (mode :basic) (base 10) (word-size 64) (angle-unit :radians))
  (call-with-calculator-actor
   session
   (make-calculator-control-request session
                                    :evaluate
                                    :calculator/evaluate
                                    :payload (list :expression expression
                                                   :mode mode
                                                   :base base
                                                   :word-size word-size
                                                   :angle-unit angle-unit))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Evaluate calculator expression ~S." expression)
                                    "calculator/evaluate"
                                    :authority :environment
                                    :payload (list :expression expression
                                                   :mode mode
                                                   :base base
                                                   :word-size word-size
                                                   :angle-unit angle-unit)))
   :calculator/evaluate
   :evaluate
   :metadata (list :expression expression
                   :mode mode
                   :base base
                   :word-size word-size
                   :angle-unit angle-unit)))
