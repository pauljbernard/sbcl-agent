(in-package #:tutor-codex)

(defclass provider ()
  ())

(defgeneric provider-name (provider))
(defgeneric provider-capabilities (provider))
(defgeneric send-prompt (provider prompt))

(defclass mock-provider (provider)
  ((model :initarg :model :reader mock-provider-model)))

(defmethod provider-name ((provider mock-provider))
  "mock")

(defmethod provider-capabilities ((provider mock-provider))
  '(:chat))

(defmethod send-prompt ((provider mock-provider) prompt)
  (declare (ignore provider))
  (format nil
          "Mock response: ~A~%~%This is the SBCL scaffold. Replace the mock provider with a real model adapter next."
          prompt))

(defun make-provider (config)
  (let ((provider-name (string-downcase (config-provider config))))
    (cond
      ((string= provider-name "mock")
       (make-instance 'mock-provider :model (config-model config)))
      (t
       (error "Unsupported provider ~S. Supported providers: mock"
              (config-provider config))))))
