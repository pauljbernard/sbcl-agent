(in-package #:sbcl-agent)

(defparameter *environment-runtime-history-lock*
  (sb-thread:make-mutex :name "sbcl-agent-environment-runtime-history"))

(defstruct environment-runtime-state
  runtimes
  active-runtime-id
  loaded-systems
  eval-history
  open-resources
  summaries)

(defun call-with-environment-runtime-history (environment thunk)
  (declare (ignore environment))
  (sb-thread:with-mutex (*environment-runtime-history-lock*)
    (funcall thunk)))

(defun environment-runtime-history-snapshot (environment)
  (call-with-environment-runtime-history
   environment
   (lambda ()
     (copy-list (or (environment-runtime-history environment) '())))))

(defun replace-environment-runtime-history (environment entries)
  (call-with-environment-runtime-history
   environment
   (lambda ()
     (let ((runtime-state (or (environment-runtime-state environment)
                              (setf (environment-runtime-state environment)
                                    (make-environment-runtime-state
                                     :runtimes '()
                                     :active-runtime-id (default-runtime-id)
                                     :loaded-systems '()
                                     :eval-history '()
                                     :open-resources '()
                                     :summaries '())))))
       (setf (environment-runtime-state-eval-history runtime-state)
             entries)))))

(defun default-runtime-id ()
  "runtime-primary")

(defun make-runtime-summary-from-session (session)
  (list :id (default-runtime-id)
        :kind :sbcl
        :cwd (agent-session-cwd session)
        :package (agent-session-package session)
        :status :active))

(defun loaded-system-names ()
  (sort
   (handler-case
       (mapcar (lambda (system)
                 (string-downcase
                  (typecase system
                    (symbol (symbol-name system))
                    (string system)
                    (t (princ-to-string system)))))
               (asdf:already-loaded-systems))
     (error () '()))
   #'string<))

(defun environment-runtime-history (environment)
  (let ((runtime-state (environment-runtime-state environment)))
    (and runtime-state
         (environment-runtime-state-eval-history runtime-state))))

(defun environment-runtime-domain-summary (environment)
  (let ((runtime-state (environment-runtime-state environment)))
    (and runtime-state
         (environment-runtime-state-summaries runtime-state))))

(defun update-environment-runtime-state-summaries (environment session)
  (let* ((runtime-state (environment-runtime-state environment))
         (loaded-systems (and runtime-state
                              (environment-runtime-state-loaded-systems runtime-state)))
         (eval-history (and runtime-state
                            (environment-runtime-history-snapshot environment))))
    (when runtime-state
      (setf (environment-runtime-state-summaries runtime-state)
            (list :runtime-count 1
                  :active-runtime-id (default-runtime-id)
                  :cwd (agent-session-cwd session)
                  :package (agent-session-package session)
                  :loaded-system-count (length loaded-systems)
                  :eval-history-count (length eval-history)))))
  environment)

(defun append-environment-runtime-history (environment entry)
  (call-with-environment-runtime-history
   environment
   (lambda ()
     (let ((runtime-state (or (environment-runtime-state environment)
                              (setf (environment-runtime-state environment)
                                    (make-environment-runtime-state
                                     :runtimes '()
                                     :active-runtime-id (default-runtime-id)
                                     :loaded-systems '()
                                     :eval-history '()
                                     :open-resources '()
                                     :summaries '())))))
       (setf (environment-runtime-state-eval-history runtime-state)
             (append (environment-runtime-state-eval-history runtime-state)
                     (list entry))))))
  environment)

(defun make-environment-runtime-state-from-session (environment session)
  (let* ((runtime-summary (make-runtime-summary-from-session session))
         (existing-runtime-state (environment-runtime-state environment))
         (existing-eval-history (and existing-runtime-state
                                     (environment-runtime-history-snapshot environment)))
         (existing-open-resources (and existing-runtime-state
                                       (environment-runtime-state-open-resources existing-runtime-state)))
         (loaded-systems (loaded-system-names)))
    (make-environment-runtime-state
     :runtimes (list runtime-summary)
     :active-runtime-id (default-runtime-id)
     :loaded-systems loaded-systems
     :eval-history (or existing-eval-history '())
     :open-resources (or existing-open-resources '())
     :summaries '())))

(defun sync-environment-runtime-domain-from-session (environment session)
  (setf (environment-runtime-state environment)
        (make-environment-runtime-state-from-session environment session))
  (setf (environment-runtime-set environment)
        (environment-runtime-state-runtimes (environment-runtime-state environment))
        (environment-active-runtime-id environment)
        (default-runtime-id))
  (update-environment-runtime-state-summaries environment session))
