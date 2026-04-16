(in-package #:tutor-codex)

(defclass mock-provider (provider)
  ((model :initarg :model :reader mock-provider-model)))

(defmethod provider-name ((provider mock-provider))
  "mock")

(defmethod provider-capabilities ((provider mock-provider))
  '(:chat :structured-response :action-proposals))

(defun mock-actions-for-prompt (prompt)
  (cond
    ((search "read src/main.lisp" prompt :test #'char-equal)
     (list
      (make-assistant-action
       :type :tool
       :payload (list :tool-id :fs/read
                      :arguments (list :path "src/main.lisp")))))
    ((search "list src" prompt :test #'char-equal)
     (list
      (make-assistant-action
       :type :tool
       :payload (list :tool-id :fs/list
                      :arguments (list :path "src")))))
    (t
     nil)))

(defmethod send-request ((provider mock-provider) request)
  (declare (ignore provider))
  (let* ((prompt (provider-request-prompt request))
         (session-summary (provider-request-session-summary request))
         (actions (mock-actions-for-prompt prompt)))
    (make-assistant-response
     :message (if actions
                  (format nil
                          "Mock response: ~A~%~%I have prepared ~D proposed action~:P."
                          prompt
                          (length actions))
                  (format nil
                          "Mock response: ~A~%~%This is the SBCL scaffold. Replace the mock provider with a real model adapter next."
                          prompt))
     :actions actions
     :metadata (list :provider :mock
                     :prompt prompt
                     :session session-summary))))
