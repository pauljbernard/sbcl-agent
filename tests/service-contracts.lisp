(in-package #:sbcl-agent/tests)

(defun service-envelope-helper-test ()
  (let ((response (sbcl-agent::make-service-query-response :environment
                                                           :status
                                                           '(:ok t)
                                                           :metadata '(:read-model :demo))))
    (assert-equal 1
                  (getf response :contract-version)
                  "service responses should carry a contract version")
    (assert-equal :environment
                  (getf response :domain)
                  "service responses should identify the domain")
    (assert-equal :query
                  (getf response :kind)
                  "query helpers should tag query responses")
    (assert-equal '(:ok t)
                  (sbcl-agent::service-response-data response)
                  "service-response-data should unwrap the data payload")
    (assert-equal '(:read-model :demo)
                  (sbcl-agent::service-response-metadata response)
                  "service-response-metadata should unwrap the metadata payload")))

(defun assert-service-metadata-shape (response message)
  (let* ((metadata (sbcl-agent::service-response-metadata response))
         (binding (getf metadata :binding)))
    (assert-equal :environment
                  (getf metadata :authority)
                  (format nil "~A should declare environment authority" message))
    (assert-true (listp binding)
                 (format nil "~A should include a binding object" message))
    (assert-true (member :session-id binding)
                 (format nil "~A should include binding session-id" message))
    (assert-true (member :environment-id binding)
                 (format nil "~A should include binding environment-id" message))))

(defun environment-service-contract-test ()
  (let* ((session (make-test-session :cwd "/tmp/environment-service-contract/"))
         (environment (sbcl-agent::ensure-environment)))
    (declare (ignore environment))
    (let ((response (sbcl-agent::query-environment-status-service)))
      (assert-service-metadata-shape response "environment status service")
      (assert-equal :environment
                    (getf response :domain)
                    "environment status service should report the environment domain")
      (assert-equal :status
                    (getf response :operation)
                    "environment status service should identify the status operation")
      (assert-true (listp (sbcl-agent::service-response-data response))
                   "environment status service should return a plist payload")
      (assert-equal (sbcl-agent::environment-id sbcl-agent::*current-environment*)
                    (getf (getf response :metadata) :environment-id)
                    "environment status metadata should include the environment id"))))

(defun conversation-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/conversation-service-contract/")))
    (let ((create-response (sbcl-agent::command-conversation-create-thread-service session
                                                                                   :title "Service Thread")))
      (assert-service-metadata-shape create-response "conversation create-thread service")
      (assert-equal :conversation
                    (getf create-response :domain)
                    "conversation command should report the conversation domain")
      (assert-equal :command
                    (getf create-response :kind)
                    "create-thread should be modeled as a command")
      (assert-equal "Service Thread"
                    (getf (sbcl-agent::service-response-data create-response) :title)
                    "create-thread should return the created thread summary"))
    (let ((list-response (sbcl-agent::query-conversation-thread-list-service session)))
      (assert-service-metadata-shape list-response "conversation thread-list service")
      (assert-equal :thread-list
                    (getf list-response :operation)
                    "thread list should identify its query operation")
      (assert-true (>= (length (sbcl-agent::service-response-data list-response)) 1)
                   "thread list service should return at least one thread"))))

(defun runtime-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/runtime-service-contract/")))
    (sbcl-agent::ensure-environment)
    (let ((summary-response (sbcl-agent::query-runtime-summary-service session)))
      (assert-service-metadata-shape summary-response "runtime summary service")
      (assert-equal :runtime
                    (getf summary-response :domain)
                    "runtime summary service should report the runtime domain")
      (assert-equal :summary
                    (getf summary-response :operation)
                    "runtime summary service should identify the summary operation")
      (assert-true (stringp (getf (sbcl-agent::service-response-data summary-response) :package))
                   "runtime summary service should expose the active package"))
    (let ((history-response (sbcl-agent::query-runtime-history-service session :tail 1)))
      (assert-service-metadata-shape history-response "runtime history service")
      (assert-equal :history
                    (getf history-response :operation)
                    "runtime history service should identify the history operation")
      (assert-equal :runtime/history
                    (getf (sbcl-agent::service-response-data history-response) :tool)
                    "runtime history service should reuse the runtime history read model"))))

(defun workflow-and-approval-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/workflow-approval-service-contract/")))
    (sbcl-agent::ensure-environment)
    (let* ((work-item (sbcl-agent::create-work-item session "Service approval goal"))
           (approval-response (sbcl-agent::command-request-work-item-approval-service session
                                                                                      (sbcl-agent::work-item-id work-item)
                                                                                      :workspace-write
                                                                                      :reason "Need operator confirmation")))
      (assert-equal :approval
                    (getf approval-response :domain)
                    "approval service should report the approval domain")
      (assert-service-metadata-shape approval-response "approval request service")
      (assert-equal :workspace-write
                    (getf (sbcl-agent::service-response-metadata approval-response) :policy-id)
                    "approval request service should expose the governing policy id")
      (assert-equal :request-work-item-approval
                    (getf approval-response :operation)
                    "approval service should identify the approval request operation")
      (assert-equal :approval-required
                    (getf (getf (sbcl-agent::service-response-data approval-response) :wait) :why)
                    "approval request should project an approval-required wait state")
      (assert-equal :awaiting-approval
                    (getf (getf (sbcl-agent::service-response-data approval-response) :workflow-record) :status)
                    "approval request should move the workflow record into awaiting-approval"))
    (let* ((record (sbcl-agent::create-workflow-record session "Workflow service goal"))
           (detail-response (sbcl-agent::query-workflow-record-detail-service session
                                                                              (sbcl-agent::workflow-record-id record))))
      (assert-equal :workflow
                    (getf detail-response :domain)
                    "workflow service should report the workflow domain")
      (assert-service-metadata-shape detail-response "workflow detail service")
      (assert-equal :record-detail
                    (getf detail-response :operation)
                    "workflow detail service should identify the detail operation")
      (assert-equal (sbcl-agent::workflow-record-id record)
                    (getf (sbcl-agent::service-response-data detail-response) :id)
                    "workflow detail service should return the requested workflow record"))))

(defun event-stream-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/event-stream-service-contract/")))
    (let ((environment (sbcl-agent::ensure-environment)))
      (sbcl-agent::append-session-event session
                                        :thread-created
                                        '(:id "thread-1")
                                        :family :conversation
                                        :visibility :operator)
      (sbcl-agent::sync-environment-from-session environment session)
      (let* ((response (sbcl-agent::query-service-event-stream :environment environment
                                                               :limit 10
                                                               :family :conversation))
             (payload (sbcl-agent::service-response-data response))
             (events (getf payload :events)))
        (assert-equal :events
                      (getf response :domain)
                      "event stream service should report the events domain")
        (assert-service-metadata-shape response "event stream service")
        (assert-equal :stream
                      (getf response :operation)
                      "event stream service should identify the stream operation")
        (assert-equal 1
                      (length events)
                      "event stream service should filter by event family")
        (assert-equal 0
                      (getf (first events) :cursor)
                      "event stream entries should include a stable cursor")
        (assert-equal :thread-created
                      (getf (first events) :kind)
                      "event stream entries should expose canonical event kinds")))))

(defun incident-and-work-item-service-contract-test ()
  (let ((session (make-test-session :cwd "/tmp/incident-work-item-service-contract/")))
    (sbcl-agent::ensure-environment)
    (let* ((work-item (sbcl-agent::create-work-item session "Service work item"))
           (work-list-response (sbcl-agent::query-work-item-list-service session))
           (work-detail-response (sbcl-agent::query-work-item-detail-service session
                                                                             (sbcl-agent::work-item-id work-item))))
      (assert-equal :work-item
                    (getf work-list-response :domain)
                    "work-item list service should report the work-item domain")
      (assert-service-metadata-shape work-list-response "work-item list service")
      (assert-equal :list
                    (getf work-list-response :operation)
                    "work-item list service should identify the list operation")
      (assert-true (= 1 (length (sbcl-agent::service-response-data work-list-response)))
                   "work-item list service should return created work-items")
      (assert-equal (sbcl-agent::work-item-id work-item)
                    (getf (sbcl-agent::service-response-data work-detail-response) :id)
                    "work-item detail service should return the requested work-item"))
    (let* ((incident (sbcl-agent::create-incident session
                                                  :runtime-eval-failure
                                                  "Incident title"
                                                  "Incident summary"))
           (incident-list-response (sbcl-agent::query-incident-list-service session))
           (incident-detail-response (sbcl-agent::query-incident-detail-service session
                                                                                 (sbcl-agent::incident-id incident))))
      (assert-equal :incident
                    (getf incident-list-response :domain)
                    "incident list service should report the incident domain")
      (assert-service-metadata-shape incident-list-response "incident list service")
      (assert-equal :list
                    (getf incident-list-response :operation)
                    "incident list service should identify the list operation")
      (assert-true (= 1 (length (sbcl-agent::service-response-data incident-list-response)))
                   "incident list service should return created incidents")
      (assert-service-metadata-shape incident-detail-response "incident detail service")
      (assert-equal (sbcl-agent::incident-id incident)
                    (getf (sbcl-agent::service-response-data incident-detail-response) :id)
                    "incident detail service should return the requested incident"))))
