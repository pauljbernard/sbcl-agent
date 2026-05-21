(in-package #:sbcl-agent)

(defun console-event-summary-payload (event)
  (let ((payload (event-payload event)))
    (cond
      ((and (listp payload) (getf payload :event-summary))
       (getf payload :event-summary))
      ((listp payload)
       payload)
      (t
       nil))))

(defun console-event-correlation-value (event key)
  (let* ((metadata (event-metadata event))
         (summary (console-event-summary-payload event))
         (payload (event-payload event))
         (nested-payload (and (listp payload)
                              (listp (getf payload :payload))
                              (getf payload :payload))))
    (or (getf metadata key)
        (and (listp summary) (getf summary key))
        (and (listp payload) (getf payload key))
        (and (listp nested-payload) (getf nested-payload key)))))

(defun console-event-string-value (event &rest keys)
  (loop for key in keys
        for value = (console-event-correlation-value event key)
        when value
          do (return (princ-to-string value))))

(defun console-process-name-for-event (event)
  (or (console-event-string-value event :process-name :worker-label :worker-id :task-id)
      (case (event-family event)
        (:provider "provider-stream")
        (:workflow "workflow-engine")
        (:runtime "runtime-engine")
        (:artifact "artifact-index")
        (:incident "incident-manager")
        (:assistant "assistant-orchestrator")
        (otherwise "sbcl-agent"))))

(defun console-activity-id-for-event (event)
  (or (console-event-string-value event
                                  :operation-id
                                  :run-id
                                  :source-event-id
                                  :task-id
                                  :worker-id
                                  :work-item-id
                                  :workflow-record-id
                                  :incident-id)
      (format nil "~(~A~):~(~A~):~A"
              (event-family event)
              (event-kind event)
              (or (event-thread-id event)
                  (event-turn-id event)
                  "event"))))

(defun console-log-type-for-event (event)
  (let ((kind (event-kind event)))
    (cond
      ((or (search "failed" (string-downcase (symbol-name kind)))
           (eq (event-family event) :incident))
       :error)
      ((or (search "approval" (string-downcase (symbol-name kind)))
           (search "blocked" (string-downcase (symbol-name kind)))
           (search "waiting" (string-downcase (symbol-name kind))))
       :warning)
      ((eq (event-family event) :provider)
       :debug)
      (t
       :info))))

(defun console-log-message-for-event (event)
  (let ((payload (event-payload event)))
    (cond
      ((and (listp payload) (getf payload :message))
       (princ-to-string (getf payload :message)))
      ((and (listp payload) (getf payload :summary))
       (princ-to-string (getf payload :summary)))
      ((and (listp payload) (getf payload :payload))
       (princ-to-string (getf payload :payload)))
      (t
       (format nil "~(~A~) / ~(~A~)" (event-family event) (event-kind event))))))

(defun console-log-entry (event index environment)
  (let* ((metadata (event-metadata event))
         (payload (event-payload event))
         (summary-payload (console-event-summary-payload event))
         (runtime-id (or (getf metadata :runtime-id)
                         (environment-active-runtime-id environment))))
    (list :entry-id (format nil "~A:~D" (environment-id environment) index)
          :cursor index
          :plane :environment
          :timestamp (event-timestamp event)
          :type (console-log-type-for-event event)
          :category (event-family event)
          :source (event-kind event)
          :message (console-log-message-for-event event)
          :process-name (console-process-name-for-event event)
          :pid nil
          :thread-id (console-event-string-value event :worker-id :task-id)
          :activity-id (console-activity-id-for-event event)
          :environment-id (environment-id environment)
          :runtime-id runtime-id
          :work-item-id (console-event-correlation-value event :work-item-id)
          :workflow-record-id (console-event-correlation-value event :workflow-record-id)
          :incident-id (console-event-correlation-value event :incident-id)
          :thread-ref-id (event-thread-id event)
          :turn-ref-id (event-turn-id event)
          :visibility (event-visibility event)
          :detail (or summary-payload
                      (when (listp payload)
                        payload)))))

(defun console-log-entry-visible-p (entry type source)
  (and (or (null type)
           (eq (getf entry :type) type))
       (or (null source)
           (string-equal (princ-to-string (getf entry :source))
                         (princ-to-string source)))))

(defun query-console-log-stream-service (&key environment after-cursor limit type source)
  (let* ((active-environment (ensure-environment environment))
         (events (or (environment-event-log active-environment) '()))
         (start-index (if (and after-cursor (integerp after-cursor))
                          (1+ after-cursor)
                          0))
         (limit-count (cond
                        ((null limit) 50)
                        ((and (integerp limit) (plusp limit)) limit)
                        (t (error "Console stream limit must be a positive integer, got ~S" limit))))
         (entries '()))
    (loop for event in events
          for index from 0
          when (>= index start-index)
            do (let ((entry (console-log-entry event index active-environment)))
                 (when (console-log-entry-visible-p entry type source)
                   (push entry entries)))
          when (>= (length entries) limit-count)
            do (return))
    (let* ((ordered-entries (nreverse entries))
           (next-cursor (and ordered-entries
                             (getf (first (last ordered-entries)) :cursor))))
      (make-service-query-response :console
                                   :stream
                                   (list :plane :environment
                                         :entries ordered-entries
                                         :next-cursor next-cursor
                                         :summary (format nil
                                                          "Projected ~D console entries from the governed environment event log."
                                                          (length ordered-entries)))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :read-model :console-stream-v1
                                                                    :environment active-environment)))))

(defun command-console-log-stream-query-service (&key environment after-cursor limit type source)
  (let ((active-environment (ensure-environment environment)))
    (call-with-environment-query-actor
     active-environment
     (make-environment-control-request
      active-environment
      :console-stream-query
      :console/stream
     :payload (list :after-cursor after-cursor
                    :limit limit
                    :type type
                    :source source))
     (lambda ()
       (query-console-log-stream-service
        :environment active-environment
        :after-cursor after-cursor
        :limit limit
        :type type
        :source source))
     :console/stream
     :console-stream-query)))
