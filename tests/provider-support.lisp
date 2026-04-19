(in-package #:sbcl-agent/tests)

(defun make-test-provider ()
  (sbcl-agent::make-provider
   (sbcl-agent::make-config :provider "mock"
                            :model "gpt-5"
                            :working-directory "/tmp/")))

(defclass mixed-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider mixed-action-provider))
  "mixed-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider mixed-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider mixed-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Executing eval now and staging the file read."
   :actions (list (sbcl-agent::make-assistant-action :type :eval :payload '(:form "(+ 100 203)"))
                  (sbcl-agent::make-assistant-action :type :tool :payload '(:tool-id :fs/read :arguments (:path "src/main.lisp"))))
   :metadata '(:provider :mixed-action-test)))

(defclass patch-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider patch-action-provider))
  "patch-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider patch-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider patch-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a patch that requires workspace write approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :patch
                   :payload '((:write "tmp/generated.txt" "hello from patch"))))
   :metadata '(:provider :patch-action-test)))

(defclass journal-date-time-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider journal-date-time-provider))
  "journal-date-time-test")

(defmethod sbcl-agent::provider-capabilities ((provider journal-date-time-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider journal-date-time-provider) request)
  (declare (ignore provider))
  (let* ((prompt (sbcl-agent::provider-request-prompt request))
         (summary (sbcl-agent::provider-request-session-summary request))
         (transcript (getf summary :recent-transcript))
         (assistant-turn (find :assistant transcript :from-end t :key (lambda (entry) (getf entry :role))))
         (prior-message (and assistant-turn (getf assistant-turn :content)))
         (code "(multiple-value-bind (sec min hour day month year) (get-decoded-time) (format nil \"~D-~D-~D ~D:~D:~D\" year month day hour min sec))"))
    (cond
      ((search "current data and time" prompt :test #'char-equal)
       (sbcl-agent::make-assistant-response
        :message code
        :actions '()
        :metadata '(:provider :journal-date-time-test :step :suggest)))
      ((search "now go execute that" prompt :test #'char-equal)
       (unless (and prior-message (search "get-decoded-time" prior-message :test #'char-equal))
         (error "journal-date-time-provider expected the prior assistant suggestion in recent transcript"))
       (sbcl-agent::make-assistant-response
        :message "Executing the previously suggested date/time code."
        :actions (list (sbcl-agent::make-assistant-action :type :eval :payload prior-message))
        :metadata '(:provider :journal-date-time-test :step :execute)))
      (t
       (error "journal-date-time-provider received unexpected prompt ~S" prompt)))))

(defclass mutating-eval-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider mutating-eval-provider))
  "mutating-eval-test")

(defmethod sbcl-agent::provider-capabilities ((provider mutating-eval-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider mutating-eval-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a mutating eval that requires runtime approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :eval
                   :payload '(:form "(progn (defparameter sbcl-agent-user::*governed-runtime-flag* nil) (setf sbcl-agent-user::*governed-runtime-flag* :mutated) sbcl-agent-user::*governed-runtime-flag*)"
                             :mutating t)))
   :metadata '(:provider :mutating-eval-test)))

(defclass git-write-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider git-write-action-provider))
  "git-write-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider git-write-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider git-write-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a git write action that requires approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :tool
                   :payload '(:tool-id :git/add :arguments (:paths ("README.md")))))
   :metadata '(:provider :git-write-action-test)))

(defclass runtime-reload-action-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider runtime-reload-action-provider))
  "runtime-reload-action-test")

(defmethod sbcl-agent::provider-capabilities ((provider runtime-reload-action-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider runtime-reload-action-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a runtime reload action that requires approval."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :tool
                   :payload '(:tool-id :runtime/reload-file
                             :arguments (:path "tmp/conversation-reload-target.lisp"))))
   :metadata '(:provider :runtime-reload-action-test)))

(defclass failing-mutating-eval-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider failing-mutating-eval-provider))
  "failing-mutating-eval-test")

(defmethod sbcl-agent::provider-capabilities ((provider failing-mutating-eval-provider))
  '(:chat :structured-response :action-proposals))

(defmethod sbcl-agent::send-request ((provider failing-mutating-eval-provider) request)
  (declare (ignore provider request))
  (sbcl-agent::make-assistant-response
   :message "Prepared a mutating eval that will fail at runtime."
   :actions (list (sbcl-agent::make-assistant-action
                   :type :eval
                   :payload '(:form "(error \"runtime incident boom\")"
                             :mutating t)))
   :metadata '(:provider :failing-mutating-eval-test)))

(defclass followup-patch-provider (sbcl-agent::provider) ())

(defmethod sbcl-agent::provider-name ((provider followup-patch-provider))
  "followup-patch-test")

(defmethod sbcl-agent::provider-capabilities ((provider followup-patch-provider))
  '(:chat :structured-response :action-proposals :turn-followup))

(defmethod sbcl-agent::send-request ((provider followup-patch-provider) request)
  (declare (ignore provider))
  (let* ((turn-context (sbcl-agent::provider-request-turn-context request))
         (operations (getf turn-context :operations))
         (completed-patch (find "assistant-patch"
                                operations
                                :key (lambda (entry) (getf entry :name))
                                :test #'string=)))
    (if (and completed-patch
             (eq (getf completed-patch :status) :completed))
        (sbcl-agent::make-assistant-response
         :message "Patch applied successfully. Follow-up summary recorded."
         :actions '()
         :metadata '(:provider :followup-patch-test :phase :followup))
        (sbcl-agent::make-assistant-response
         :message "Prepared a patch that requires approval before follow-up."
         :actions (list (sbcl-agent::make-assistant-action
                         :type :patch
                         :payload '((:write "tmp/followup-generated.txt" "hello from followup patch"))))
         :metadata '(:provider :followup-patch-test :phase :initial)))))
