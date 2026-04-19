(in-package #:sbcl-agent)

(defparameter *provider-timing-listener* nil)

(defun emit-provider-timing (phase &rest payload)
  (when *provider-timing-listener*
    (funcall *provider-timing-listener* phase payload)))

(defun provider-transport-error (label exit-code detail)
  (error "~A failed with exit code ~D: ~A" label exit-code detail))
