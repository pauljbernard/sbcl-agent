(in-package #:tutor-codex)

(defclass mock-provider (provider)
  ((model :initarg :model :reader mock-provider-model)))

(defmethod provider-name ((provider mock-provider))
  "mock")

(defmethod provider-capabilities ((provider mock-provider))
  '(:chat :structured-response :action-proposals :streaming))

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

(defun build-mock-response (prompt session-summary)
  (let ((actions (mock-actions-for-prompt prompt)))
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

(defun split-stream-message (message)
  (let* ((length (length message))
         (chunk-size (max 1 (ceiling length 3))))
    (loop for start from 0 below length by chunk-size
          collect (subseq message start (min length (+ start chunk-size))))))

(defmethod send-request ((provider mock-provider) request)
  (declare (ignore provider))
  (build-mock-response (provider-request-prompt request)
                       (provider-request-session-summary request)))

(defmethod stream-request ((provider mock-provider) request event-handler)
  (declare (ignore provider))
  (let* ((response (build-mock-response (provider-request-prompt request)
                                        (provider-request-session-summary request)))
         (actions (assistant-response-actions response)))
    (emit-provider-event event-handler :message-start nil)
    (dolist (chunk (split-stream-message (assistant-response-message response)))
      (emit-provider-event event-handler :message-delta chunk))
    (when actions
      (emit-provider-event event-handler :action-proposal actions))
    (emit-provider-event event-handler
                         :message-complete
                         (list :response response
                               :metadata (assistant-response-metadata response)))
    response))
