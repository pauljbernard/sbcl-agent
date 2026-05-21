(in-package #:sbcl-agent)

(defun actor-system-panel-hierarchy-edges (actors)
  (remove nil
          (mapcar (lambda (actor)
                    (let ((parent-id (actor-summary-parent-id actor))
                          (actor-id (actor-summary-id actor)))
                      (and parent-id
                           actor-id
                           (list :parent-actor-id parent-id
                                 :child-actor-id actor-id
                                 :provenance :actor-registry))))
                  actors)))

(defun actor-system-panel-projected-workflow-edges (session &key session-id)
  (let ((edges (make-hash-table :test #'equal))
        (recent-threshold (- (get-universal-time) 300)))
    (dolist (record (list-desktop-task-records session))
      (when (or (null session-id)
                (let ((record-session-id (desktop-task-record-session-id record)))
                  (and record-session-id
                       (string= session-id record-session-id))))
        (let* ((message (desktop-task-record-actor-message record))
               (sender (and message (actor-message-sender message)))
               (receiver (and message (actor-message-receiver message))))
          (when (and sender receiver)
            (let* ((key (list (actor-address-id sender)
                              (actor-address-id receiver)
                              (desktop-task-record-target record)
                              (desktop-task-record-operation record)))
                   (bucket (or (gethash key edges)
                               (setf (gethash key edges)
                                     (list :from-actor-id (actor-address-id sender)
                                           :to-actor-id (actor-address-id receiver)
                                           :from-role (actor-address-role sender)
                                           :to-role (actor-address-role receiver)
                                           :provenance :desktop-task-record-projection
                                           :target (desktop-task-record-target record)
                                           :operation (desktop-task-record-operation record)
                                           :message-count 0
                                           :recent-count 0
                                           :failed-count 0
                                           :latest-status nil
                                           :latest-created-at nil)))))
              (incf (getf bucket :message-count))
              (when (member (desktop-task-record-status record)
                            '(:failed :retryable-failure :canceled)
                            :test #'eq)
                (incf (getf bucket :failed-count)))
              (when (>= (or (desktop-task-record-created-at record) 0)
                        recent-threshold)
                (incf (getf bucket :recent-count)))
              (when (> (or (desktop-task-record-created-at record) 0)
                       (or (getf bucket :latest-created-at) 0))
                (setf (getf bucket :latest-created-at)
                      (desktop-task-record-created-at record)
                      (getf bucket :latest-status)
                      (desktop-task-record-status record))))))))
    (sort (loop for edge being the hash-values of edges collect edge)
          #'>
          :key (lambda (entry)
                 (or (getf entry :latest-created-at) 0)))))

(defun actor-system-panel-native-workflow-edges (session &key session-id)
  (let ((edges (make-hash-table :test #'equal)))
    (dolist (record (agent-session-workflow-records session))
      (when (or (null session-id)
                (string= session-id (agent-session-id session)))
        (dolist (edge (workflow-record-native-actor-links session record))
          (let* ((key (list (getf edge :from-actor-id)
                            (getf edge :to-actor-id)
                            (getf edge :operation)))
                 (bucket (or (gethash key edges)
                             (setf (gethash key edges)
                                   (list :from-actor-id (getf edge :from-actor-id)
                                         :to-actor-id (getf edge :to-actor-id)
                                         :from-role (getf edge :from-role)
                                         :to-role (getf edge :to-role)
                                         :provenance (getf edge :provenance)
                                         :workflow-record-id (getf edge :workflow-record-id)
                                         :work-item-id (getf edge :work-item-id)
                                         :plan-id (getf edge :plan-id)
                                         :phase (getf edge :phase)
                                         :operation (getf edge :operation)
                                         :message-count 0
                                         :recent-count 0
                                         :failed-count 0
                                         :latest-status nil
                                         :latest-created-at nil
                                         :actor-execution-job-id nil)))))
            (incf (getf bucket :message-count) (or (getf edge :message-count) 0))
            (incf (getf bucket :recent-count) (or (getf edge :recent-count) 0))
            (incf (getf bucket :failed-count) (or (getf edge :failed-count) 0))
            (when (> (or (getf edge :latest-created-at) 0)
                     (or (getf bucket :latest-created-at) 0))
              (setf (getf bucket :latest-created-at) (getf edge :latest-created-at)
                    (getf bucket :latest-status) (getf edge :latest-status)
                    (getf bucket :actor-execution-job-id)
                    (getf edge :actor-execution-job-id)
                    (getf bucket :workflow-record-id)
                    (getf edge :workflow-record-id)
                    (getf bucket :work-item-id)
                    (getf edge :work-item-id)
                    (getf bucket :plan-id)
                    (getf edge :plan-id)))))))
    (sort (loop for edge being the hash-values of edges collect edge)
          #'>
          :key (lambda (entry)
                 (or (getf entry :latest-created-at) 0)))))

(defun actor-system-panel-workflow-edges (session &key session-id)
  (let ((native-edges (actor-system-panel-native-workflow-edges session
                                                                :session-id session-id))
        (projected-edges (actor-system-panel-projected-workflow-edges session
                                                                      :session-id session-id)))
    (values (append native-edges projected-edges)
            native-edges
            projected-edges)))

(defun query-desktop-task-actor-system-panel-service (session &key session-id)
  (ensure-environment-actor-registry-for-session session)
  (let* ((registered-actors
           (mapcar (lambda (definition)
                     (actor-definition-address definition))
                   (actor-system-registry-definitions session)))
         (observed-actors
           (mapcar (lambda (address)
                     (canonical-actor-address-for-session session address))
                   (desktop-task-capability-actor-addresses session)))
         (addresses
           (nreverse
            (delete-duplicates (append registered-actors observed-actors)
                               :test #'actor-address-equal-p)))
         (actors
           (mapcar (lambda (address)
                     (let ((summary (desktop-task-actor-summary session address)))
                       (append summary
                               (list :metrics
                                     (actor-mailbox-metrics-for-actor
                                      session
                                      (actor-summary-id summary))))))
                   addresses))
         (hierarchy-edges (actor-system-panel-hierarchy-edges actors))
         (workflow-edges nil)
         (native-workflow-edges nil)
         (projected-workflow-edges nil)
         (runtime-execution
           (and (fboundp 'actor-runtime-state-summary)
                (actor-runtime-state-summary session)))
         (supervision-incidents
           (service-response-data
            (query-desktop-task-supervision-incidents-service
             session
             :session-id session-id)))
         (supervision-escalation-inbox
           (service-response-data
            (query-desktop-task-supervision-escalation-inbox-service
             session
             :session-id session-id))))
    (multiple-value-setq (workflow-edges native-workflow-edges projected-workflow-edges)
      (actor-system-panel-workflow-edges session :session-id session-id))
    (make-service-query-response
     :desktop-task
     :actor-system-panel
     (list :root-actor-id "actor/actor-system"
           :session-id (or session-id
                           (agent-session-id session))
           :topology-provenance
           (list :actors :actor-registry+mailbox-projection
                 :hierarchy-edges :actor-registry
                 :workflow-edges :native+desktop-task-record-projection
                 :native-workflow-edges :workflow-record
                 :projected-workflow-edges :desktop-task-record-projection
                 :runtime-execution :native-actor-runtime)
           :actor-count (length actors)
           :actors actors
           :hierarchy-edge-count (length hierarchy-edges)
           :hierarchy-edges hierarchy-edges
           :workflow-edge-count (length workflow-edges)
           :workflow-edges workflow-edges
           :native-workflow-topology native-workflow-edges
           :projected-workflow-topology projected-workflow-edges
           :runtime-execution runtime-execution
           :native-runtime-execution runtime-execution
           :supervision-incidents supervision-incidents
           :supervision-escalation-inbox supervision-escalation-inbox)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-actor-system-panel-v3
                                      :session session))))

(defun actor-message-transport-event-p (event)
  (eq (event-kind event) :actor-message-transport))

(defun actor-message-transport-event-summary (event)
  (let ((payload (event-payload event)))
    (append (if (listp payload) payload (list :payload payload))
            (list :event-id (event-id event)
                  :recorded-at (event-timestamp event)
                  :thread-id (event-thread-id event)
                  :turn-id (event-turn-id event)
                  :entity-id (event-entity-id event)
                  :family (event-family event)
                  :kind (event-kind event)))))

(defun actor-message-trace-matches-p (event actor-message-id actor-role phase dead-letters-only-p)
  (let* ((payload (event-payload event))
         (sender (let ((value (getf payload :sender)))
                   (and (listp value) value)))
         (receiver (let ((value (getf payload :receiver)))
                     (and (listp value) value)))
         (payload-role (or (getf receiver :role)
                           (getf sender :role)))
         (payload-phase (getf payload :phase))
         (payload-message-id (getf payload :actor-message-id))
         (dead-letter-p (getf payload :dead-letter-p)))
    (and (actor-message-transport-event-p event)
         (or (null actor-message-id)
             (and payload-message-id
                  (string= actor-message-id payload-message-id)))
         (or (null actor-role)
             (eq (normalize-actor-role actor-role :unknown)
                 payload-role))
         (or (null phase)
             (eq phase payload-phase))
         (or (not dead-letters-only-p)
             dead-letter-p))))

(defun query-desktop-task-actor-trace-service (session &key actor-message-id actor-role phase latest-only-p dead-letters-only-p)
  (let* ((events (remove-if-not
                  (lambda (event)
                    (actor-message-trace-matches-p event
                                                   actor-message-id
                                                   actor-role
                                                   phase
                                                   dead-letters-only-p))
                  (agent-session-events session)))
         (ordered (sort (copy-list events)
                        #'>
                        :key #'event-timestamp))
         (selected (if latest-only-p
                       (if ordered
                           (list (first ordered))
                           '())
                       ordered)))
    (make-service-query-response
     :desktop-task
     (if dead-letters-only-p :dead-letter-queue :actor-trace)
     (mapcar #'actor-message-transport-event-summary selected)
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if dead-letters-only-p
                                                      :desktop-task-dead-letter-queue-v1
                                                      :desktop-task-actor-trace-v1)
                                      :session session))))

(defun find-desktop-task-record-by-actor-message-id (session actor-message-id)
  (find actor-message-id
        (list-desktop-task-records session)
        :key (lambda (record)
               (let ((message (desktop-task-actor-message-for-record record)))
                 (and message
                      (actor-message-id message))))
        :test #'string=))

(defun desktop-task-actor-reply-summary (record)
  (let* ((actor-message (desktop-task-record-actor-message record))
         (result (desktop-task-record-result record))
         (last-error (desktop-task-record-last-error record)))
    (list :request-id (desktop-task-record-request-id record)
          :record-id (desktop-task-record-id record)
          :actor-message-id (and actor-message
                                 (actor-message-id actor-message))
          :target (desktop-task-record-target record)
          :operation (desktop-task-record-operation record)
          :actor-slice (or (and actor-message
                                (getf (actor-message-metadata actor-message) :slice))
                           (getf (desktop-task-record-request-metadata record)
                                 :actor-slice))
          :status (desktop-task-record-status record)
          :summary (or (and (listp result)
                            (or (getf result :summary)
                                (getf result :SUMMARY)))
                       (and (listp last-error)
                            (or (getf last-error :summary)
                                (getf last-error :SUMMARY)
                                (getf last-error :error)
                                (getf last-error :ERROR))))
          :error (and (listp last-error)
                      (or (getf last-error :error)
                          (getf last-error :ERROR)))
          :completed-at (desktop-task-record-completed-at record)
          :result (and (listp result)
                       (list :summary (or (getf result :summary)
                                          (getf result :SUMMARY))
                             :status (or (getf result :status)
                                         (getf result :STATUS))))
          :actor-message (actor-message-summary actor-message))))

(defun desktop-task-record-policy-ids* (records)
  (remove-duplicates
   (remove nil (mapcar #'desktop-task-record-policy-id records))
   :test #'eq))

(defun query-desktop-task-manifest-list-service (session)
  (declare (ignore session))
  (make-service-query-response
   :desktop-task
   :manifest-list
   (mapcar #'desktop-task-manifest-summary
           (list-registered-desktop-task-manifests :discoverable-only-p t))
   :metadata (make-service-metadata :authority :environment
                                    :read-model :desktop-task-manifest-list-v1
                                    :session session)))

(defun query-desktop-task-manifest-detail-service (session target operation)
  (declare (ignore session))
  (let ((manifest (find-desktop-task-manifest target operation)))
    (unless manifest
      (error "Unknown desktop task manifest ~S/~S" target operation))
    (make-service-query-response
     :desktop-task
     :manifest-detail
     (desktop-task-manifest-summary manifest)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-manifest-detail-v1
                                      :session session))))

(defun query-desktop-task-record-list-service (session &key thread-id status approval-status)
  (let ((records
          (remove-if-not
           (lambda (record)
             (and (or (null thread-id)
                      (and (desktop-task-record-thread-id record)
                           (string= thread-id (desktop-task-record-thread-id record))))
                  (or (null status)
                      (eq status (desktop-task-record-status record)))
                  (or (null approval-status)
                      (eq approval-status (desktop-task-record-approval-status record)))))
           (list-desktop-task-records session))))
    (make-service-query-response
     :desktop-task
     :record-list
     (mapcar (lambda (record)
               (desktop-task-record-summary-with-audit session record))
             records)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-record-list-v1
                                      :session session
                                      :thread-id thread-id))))

(defun query-desktop-task-record-detail-service (session record-id)
  (let ((record (find-desktop-task-record session record-id)))
    (unless record
      (error "Unknown desktop task record ~A" record-id))
    (make-service-query-response
     :desktop-task
     :record-detail
     (desktop-task-record-summary-with-audit session record)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-record-detail-v1
                                      :session session
                                      :thread-id (desktop-task-record-thread-id record)
                                      :turn-id (desktop-task-record-turn-id record)))))

(defun query-desktop-task-actor-list-service (session)
  (make-service-query-response
   :desktop-task
   :actor-list
   (mapcar (lambda (address)
             (desktop-task-actor-summary session address))
           (desktop-task-capability-actor-addresses session))
   :metadata (make-service-metadata :authority :environment
                                    :read-model :desktop-task-actor-list-v1
                                    :session session)))

(defun query-desktop-task-actor-detail-service (session actor-role)
  (let* ((role (normalize-actor-role actor-role :unknown))
         (actor-address
           (find role
                 (desktop-task-capability-actor-addresses session)
                 :key #'actor-address-role
                 :test #'eq)))
    (unless actor-address
      (error "Unknown desktop task actor ~S" actor-role))
    (make-service-query-response
     :desktop-task
     :actor-detail
     (desktop-task-actor-summary session actor-address)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-actor-detail-v1
                                      :session session))))

(defun query-desktop-task-actor-inbox-service (session actor-role &key status)
  (let* ((role (normalize-actor-role actor-role :unknown))
         (records
           (remove-if-not
            (lambda (record)
              (and (eq role
                       (desktop-task-actor-role-for-record record :direction :receiver))
                   (or (null status)
                       (eq status (desktop-task-record-status record)))))
            (list-desktop-task-records session))))
    (make-service-query-response
     :desktop-task
     :actor-inbox
     (mapcar (lambda (record)
               (desktop-task-record-summary-with-audit session record))
             records)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-actor-inbox-v1
                                      :session session))))

(defun query-desktop-task-actor-outbox-service (session actor-role &key status)
  (let* ((role (normalize-actor-role actor-role :unknown))
         (records
           (remove-if-not
            (lambda (record)
              (and (eq role
                       (desktop-task-actor-role-for-record record :direction :sender))
                   (or (null status)
                       (eq status (desktop-task-record-status record)))))
            (list-desktop-task-records session))))
    (make-service-query-response
     :desktop-task
     :actor-outbox
     (mapcar (lambda (record)
               (desktop-task-record-summary-with-audit session record))
             records)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-actor-outbox-v1
                                      :session session))))

(defun query-desktop-task-actor-message-detail-service (session actor-message-id)
  (let ((record (find-desktop-task-record-by-actor-message-id session actor-message-id)))
    (unless record
      (error "Unknown actor message ~A" actor-message-id))
    (make-service-query-response
     :desktop-task
     :actor-message-detail
     (desktop-task-record-summary-with-audit session record)
     :metadata (make-service-metadata :authority :environment
                                      :read-model :desktop-task-actor-message-detail-v1
                                      :session session
                                      :thread-id (desktop-task-record-thread-id record)
                                      :turn-id (desktop-task-record-turn-id record)))))

(defun query-desktop-task-editor-mailbox-service (session
                                                  &key session-id pending-action-id status
                                                    approval-status scope-id latest-only-p)
  (let* ((mailboxes (ensure-session-actor-mailboxes session))
         (mutations
           (remove-if-not
            (lambda (entry)
              (and (or (null session-id)
                       (let ((entry-session-id (actor-mailbox-entry-session-id entry)))
                         (and entry-session-id
                              (string= session-id entry-session-id))))
                   (or (null pending-action-id)
                       (string= pending-action-id
                                (actor-mailbox-entry-pending-action-id entry)))
                   (or (null status)
                       (eq status (actor-mailbox-entry-status entry)))
                   (or (null approval-status)
                       (eq approval-status (actor-mailbox-entry-approval-status entry)))
                   (or (null scope-id)
                       (let ((entry-scope-id (getf (actor-mailbox-entry-payload entry) :scope-id)))
                         (and entry-scope-id
                              (string= scope-id entry-scope-id))))))
            (copy-list (or (getf mailboxes :editor-pending-mutation-mailbox) '()))))
         (selected (if latest-only-p
                       (if mutations (list (first mutations)) '())
                       mutations))
         (effective-session-id (or session-id
                                   (and selected
                                        (actor-mailbox-entry-session-id (first selected))))))
    (make-service-query-response
     :desktop-task
     (if latest-only-p :editor-mailbox-latest :editor-mailbox)
     (list :session-id effective-session-id
           :receiver-actor (actor-address-summary
                            (make-standard-actor-address :editor
                                                         :kind :internal
                                                         :scope (or scope-id effective-session-id)
                                                         :display-name "Editor Actor"
                                                         :metadata '(:actor-class :capability-server)))
           :mutation-count (length selected)
           :mutations (mapcar #'actor-mailbox-entry-summary selected))
     :metadata (make-service-metadata :authority :environment
                                      :read-model (if latest-only-p
                                                      :desktop-task-editor-mailbox-latest-v1
                                                      :desktop-task-editor-mailbox-v1)
                                      :session session))))
