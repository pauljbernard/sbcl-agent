(in-package #:sbcl-agent)

(defun normalize-tail-count (tail)
  (cond
    ((null tail) 10)
    ((and (integerp tail) (plusp tail)) tail)
    (t (error "Tail count must be a positive integer, got ~S" tail))))

(defun tool-session-summary (session &key)
  (list :tool :session/summary
        :session (session-summary session)
        :sandbox-profile :in-process))

(defun tool-session-events (session &key tail)
  (let* ((tail-count (normalize-tail-count tail))
         (event-view (session-events-view session :tail tail-count)))
    (list :tool :session/events
          :event-count (getf event-view :event-count)
          :event-summary (let ((environment (session-bound-environment session)))
                           (if environment
                               (environment-event-summary environment)
                               (list :event-count (getf event-view :event-count)
                                     :recent-kinds (mapcar #'event-kind (getf event-view :events)))))
          :events (getf event-view :events)
          :environment-backed-p (getf event-view :environment-backed-p)
          :sandbox-profile :in-process)))

(register-tool :session/summary
               "Return the current session summary as Common Lisp data."
               :safe-read
               #'tool-session-summary)

(register-tool :session/events
               "Return recent session events from the current session."
               :safe-read
               #'tool-session-events)


(defun tool-session-operator-status (session &key)
  (list :tool :session/operator-status
        :status (session-operator-status session)
        :event-summary (let ((environment (session-bound-environment session)))
                         (and environment
                              (environment-event-summary environment)))
        :sandbox-profile :in-process))

(register-tool :session/operator-status
               "Return operator-facing ready/blocked/quarantined work-item status."
               :safe-read
               #'tool-session-operator-status)


(defun tool-session-replay-groups (session &key)
  (let ((environment (session-bound-environment session)))
    (list :tool :session/replay-groups
          :groups (session-validator-replay-groups session)
          :environment-backed-p (not (null environment))
          :sandbox-profile :in-process)))

(register-tool :session/replay-groups
               "Return validator replay groups for the current session."
               :safe-read
               #'tool-session-replay-groups)

(defun tool-session-image-reconciliations (session &key)
  (let ((environment (session-bound-environment session)))
    (list :tool :session/image-reconciliations
          :reconciliations (session-image-reconciliation-summary session)
          :environment-backed-p (not (null environment))
          :sandbox-profile :in-process)))

(register-tool :session/image-reconciliations
               "Return image-only reconciliation records for the current session."
               :safe-read
               #'tool-session-image-reconciliations)
