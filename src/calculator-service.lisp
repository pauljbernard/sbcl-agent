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

(defun command-calculator-set-expression-service (session expression)
  (update-calculator-session-state session
                                   :expression expression)
  (calculator-command-response session :set-expression))

(defun command-calculator-append-token-service (session token)
  (let ((state (calculator-session-state-for session)))
    (update-calculator-session-state
     session
     :expression (concatenate 'string
                              (calculator-session-state-expression state)
                              token)))
  (calculator-command-response session :append-token))

(defun command-calculator-backspace-service (session)
  (let* ((state (calculator-session-state-for session))
         (expression (calculator-session-state-expression state)))
    (update-calculator-session-state
     session
     :expression (if (> (length expression) 0)
                     (subseq expression 0 (1- (length expression)))
                     "")))
  (calculator-command-response session :backspace))

(defun command-calculator-clear-service (session)
  (update-calculator-session-state session
                                   :expression ""
                                   :latest-result nil)
  (calculator-command-response session :clear))

(defun command-calculator-set-mode-service (session mode)
  (update-calculator-session-state session
                                   :mode (sbcl-agent.calculator::normalize-mode mode))
  (calculator-command-response session :set-mode))

(defun command-calculator-set-base-service (session base)
  (update-calculator-session-state session
                                   :base (sbcl-agent.calculator::normalize-base base))
  (calculator-command-response session :set-base))

(defun command-calculator-set-word-size-service (session word-size)
  (update-calculator-session-state session
                                   :word-size (sbcl-agent.calculator::normalize-word-size word-size))
  (calculator-command-response session :set-word-size))

(defun command-calculator-set-angle-unit-service (session angle-unit)
  (update-calculator-session-state session
                                   :angle-unit (sbcl-agent.calculator::normalize-angle-unit angle-unit))
  (calculator-command-response session :set-angle-unit))

(defun command-calculator-evaluate-service (session expression &key (mode :basic) (base 10) (word-size 64) (angle-unit :radians))
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
