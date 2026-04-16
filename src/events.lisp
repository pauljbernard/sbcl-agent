(in-package #:sbcl-agent)

(defstruct event
  timestamp
  kind
  payload)

(defun make-event-now (kind payload)
  (make-event :timestamp (get-universal-time)
              :kind kind
              :payload payload))
