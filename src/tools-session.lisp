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
         (events (agent-session-events session))
         (start (max 0 (- (length events) tail-count))))
    (list :tool :session/events
          :event-count (length events)
          :events (subseq events start)
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
        :sandbox-profile :in-process))

(register-tool :session/operator-status
               "Return operator-facing ready/blocked/quarantined work-item status."
               :safe-read
               #'tool-session-operator-status)


(defun tool-session-replay-groups (session &key)
  (list :tool :session/replay-groups
        :groups (session-validator-replay-groups session)
        :sandbox-profile :in-process))

(register-tool :session/replay-groups
               "Return validator replay groups for the current session."
               :safe-read
               #'tool-session-replay-groups)

(defun tool-session-image-reconciliations (session &key)
  (list :tool :session/image-reconciliations
        :reconciliations (session-image-reconciliation-summary session)
        :sandbox-profile :in-process))

(register-tool :session/image-reconciliations
               "Return image-only reconciliation records for the current session."
               :safe-read
               #'tool-session-image-reconciliations)
