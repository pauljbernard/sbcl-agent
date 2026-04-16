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
