(in-package #:sbcl-agent)

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

(defun build-mock-response (request-or-prompt &optional session-summary)
  (let* ((request (if (typep request-or-prompt 'provider-request)
                      request-or-prompt
                      (make-provider-request :prompt request-or-prompt
                                             :session-summary session-summary)))
         (prompt (provider-request-prompt request))
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
                     :operator-mode (provider-request-operator-mode request)
                     :thread (provider-request-thread-context request)
                     :turn (provider-request-turn-context request)
                     :environment (provider-request-environment-context request)
                     :cognition (and (provider-request-cognition-bundle request)
                                     (cognition-bundle-summary
                                      (provider-request-cognition-bundle request)))
                     :session (provider-request-session-summary request)))))

(defun split-stream-message (message)
  (let* ((length (length message))
         (chunk-size (max 1 (ceiling length 3))))
    (loop for start from 0 below length by chunk-size
          collect (subseq message start (min length (+ start chunk-size))))))

(defun mock-stream-delay-seconds ()
  (let ((value (ignore-errors
                 (parse-integer (or (getenv "TUTOR_CODEX_MOCK_STREAM_DELAY_MS") "0")
                                :junk-allowed t))))
    (if (and value (> value 0))
        (/ value 1000.0)
        0.0)))

(defun maybe-sleep-for-mock-stream ()
  (let ((delay (mock-stream-delay-seconds)))
    (when (> delay 0.0)
      (sleep delay))))

(defmethod send-request ((provider mock-provider) request)
  (declare (ignore provider))
  (build-mock-response request))

(defmethod stream-request ((provider mock-provider) request event-handler)
  (declare (ignore provider))
  (let* ((response (build-mock-response request))
         (actions (assistant-response-actions response)))
    (emit-provider-event event-handler :message-start nil)
    (maybe-sleep-for-mock-stream)
    (dolist (chunk (split-stream-message (assistant-response-message response)))
      (emit-provider-event event-handler :message-delta chunk)
      (maybe-sleep-for-mock-stream))
    (when actions
      (emit-provider-event event-handler :action-proposal actions))
    (when actions
      (maybe-sleep-for-mock-stream))
    (emit-provider-event event-handler
                         :message-complete
                         (list :response response
                               :metadata (assistant-response-metadata response)))
    response))
