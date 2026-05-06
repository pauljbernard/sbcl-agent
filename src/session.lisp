(in-package #:sbcl-agent)

(declaim (special *current-environment*))

(defstruct agent-session
  id
  cwd
  package
  threads
  threads-tail
  current-thread-id
  messages
  messages-tail
  turns
  turns-tail
  operations
  operations-tail
  artifacts
  artifacts-tail
  transcript
  transcript-tail
  plan
  shell-focus-object-id
  shell-active-panel-id
  events
  events-tail
  capability-grants
  capability-grants-tail
  pending-actions
  tasks
  tasks-tail
  projects
  projects-tail
  current-project-id
  trace-links
  trace-links-tail
  work-items
  work-items-tail
  workflow-records
  workflow-records-tail
  incidents
  incidents-tail
  workers
  workers-tail)

(defparameter *current-session* nil)

(defun make-default-session (&key (cwd (namestring (getcwd)))
                                  (package "SBCL-AGENT-USER"))
  (make-agent-session
   :id (format nil "session-~D" (get-universal-time))
   :cwd cwd
   :package package
   :threads '()
   :threads-tail nil
   :current-thread-id nil
   :messages '()
   :messages-tail nil
   :turns '()
   :turns-tail nil
   :operations '()
   :operations-tail nil
   :artifacts '()
   :artifacts-tail nil
   :transcript '()
   :transcript-tail nil
   :plan nil
   :shell-focus-object-id nil
   :shell-active-panel-id nil
   :events '()
   :events-tail nil
   :capability-grants '()
   :capability-grants-tail nil
   :pending-actions '()
   :tasks '()
   :tasks-tail nil
   :projects '()
   :projects-tail nil
   :current-project-id nil
   :trace-links '()
   :trace-links-tail nil
   :work-items '()
   :work-items-tail nil
   :workflow-records '()
   :workflow-records-tail nil
   :incidents '()
   :incidents-tail nil
   :workers '()
   :workers-tail nil))

(defun append-linked-item (list tail item)
  (let ((cell (list item)))
    (if list
        (progn
          (setf (cdr tail) cell)
          (values list cell))
        (values cell cell))))

(defun rebuild-agent-session-tails (session)
  (setf (agent-session-threads-tail session) (last (agent-session-threads session))
        (agent-session-messages-tail session) (last (agent-session-messages session))
        (agent-session-turns-tail session) (last (agent-session-turns session))
        (agent-session-operations-tail session) (last (agent-session-operations session))
        (agent-session-artifacts-tail session) (last (agent-session-artifacts session))
        (agent-session-transcript-tail session) (last (agent-session-transcript session))
        (agent-session-events-tail session) (last (agent-session-events session))
        (agent-session-capability-grants-tail session) (last (agent-session-capability-grants session))
        (agent-session-tasks-tail session) (last (agent-session-tasks session))
        (agent-session-projects-tail session) (last (agent-session-projects session))
        (agent-session-trace-links-tail session) (last (agent-session-trace-links session))
        (agent-session-work-items-tail session) (last (agent-session-work-items session))
        (agent-session-workflow-records-tail session) (last (agent-session-workflow-records session))
        (agent-session-incidents-tail session) (last (agent-session-incidents session))
        (agent-session-workers-tail session) (last (agent-session-workers session)))
  session)

(defun ensure-session (&optional session)
  (let ((active-session (or session
                            *current-session*
                            (and (boundp '*current-environment*)
                                 *current-environment*
                                 (environment-compatibility-session *current-environment*))
                            (setf *current-session* (make-default-session)))))
    (ensure-default-thread active-session)
    (when (and (boundp '*current-environment*) *current-environment*)
      (bind-session-to-environment active-session *current-environment*))
    active-session))

(defun append-session-event (session kind payload &key family entity-id thread-id turn-id (visibility :operator) metadata
                                                    environment-id run-id operation-id work-item-id artifact-id incident-id agent-id)
  (let* ((environment (session-bound-environment session))
         (resolved-environment-id (or environment-id
                                      (and environment
                                           (environment-id environment))))
         (event (make-event-now kind
                                payload
                                :family family
                                :entity-id entity-id
                                :thread-id thread-id
                                :turn-id turn-id
                                :visibility visibility
                                :metadata metadata
                                :environment-id resolved-environment-id
                                :session-id (agent-session-id session)
                                :run-id run-id
                                :operation-id operation-id
                                :work-item-id work-item-id
                                :artifact-id artifact-id
                                :incident-id incident-id
                                :agent-id agent-id)))
    (multiple-value-bind (events tail)
        (append-linked-item (agent-session-events session)
                            (agent-session-events-tail session)
                            event)
      (setf (agent-session-events session) events
            (agent-session-events-tail session) tail))
    (when (and (boundp '*current-environment*)
               *current-environment*
               (eq (environment-compatibility-session *current-environment*) session))
      (refresh-environment-root-state-from-session *current-environment* session)
      (append-environment-session-event *current-environment* session event))
    (when (fboundp 'maybe-run-continuous-alignment-loop-for-event)
      (maybe-run-continuous-alignment-loop-for-event session event))
    event))

(defun append-transcript-entry (session role content)
  (let ((entry (list :role role :content content)))
    (multiple-value-bind (transcript tail)
        (append-linked-item (agent-session-transcript session)
                            (agent-session-transcript-tail session)
                            entry)
      (setf (agent-session-transcript session) transcript
            (agent-session-transcript-tail session) tail))
    (append-session-event session :transcript entry)
    entry))

(defun refresh-bound-environment-agent-state (session)
  (let ((environment (session-bound-environment session)))
    (when environment
      (refresh-environment-root-state-from-session environment session)
      (refresh-environment-agent-domain environment session)
      (refresh-environment-workflow-domain environment session)))
  session)

(defun update-session-plan (session goal)
  (setf (agent-session-plan session) goal)
  (append-session-event session :plan goal)
  (refresh-bound-environment-agent-state session)
  goal)

(defun stage-pending-actions (session actions)
  (setf (agent-session-pending-actions session) actions)
  (append-session-event session :pending-actions actions)
  (refresh-bound-environment-agent-state session)
  actions)

(defun remove-pending-actions (session actions)
  (let* ((current (agent-session-pending-actions session))
         (remaining (set-difference current
                                    actions
                                    :test #'eq))
         (removed-count (- (length current) (length remaining))))
    (setf (agent-session-pending-actions session) remaining)
    (append-session-event session
                          :pending-actions-removed
                          (list :removed-count removed-count
                                :remaining-count (length remaining)))
    (refresh-bound-environment-agent-state session)
    remaining))

(defun clear-pending-actions (session)
  (setf (agent-session-pending-actions session) '())
  (append-session-event session :pending-actions-cleared :ok)
  (refresh-bound-environment-agent-state session)
  '())

(defun capability-grant-summary (grant)
  (list :policy-id (capability-grant-policy-id grant)
        :granted-at (capability-grant-granted-at grant)
        :scope (capability-grant-scope grant)
        :metadata (capability-grant-metadata grant)))

(defun normalize-session-capability-grants (session)
  (let ((grants (agent-session-capability-grants session)))
    (setf (agent-session-capability-grants session)
          (mapcar (lambda (entry)
                    (cond
                      ((typep entry 'capability-grant) entry)
                      ((keywordp entry)
                       (make-capability-grant :policy-id entry
                                              :granted-at nil
                                              :scope :session
                                              :metadata '(:migrated-p t)))
                      (t
                       (error "Invalid capability grant entry ~S" entry))))
                  grants))))

(defun grant-capability (session policy-designator &key (scope :session) metadata)
  (let* ((policy (ensure-capability-policy policy-designator))
         (policy-id (capability-policy-id policy))
         (existing (find policy-id
                         (agent-session-capability-grants session)
                         :key #'capability-grant-policy-id
                         :test #'eq)))
    (unless existing
      (setf existing (make-capability-grant :policy-id policy-id
                                            :granted-at (get-universal-time)
                                            :scope scope
                                            :metadata metadata))
      (multiple-value-bind (grants tail)
          (append-linked-item (agent-session-capability-grants session)
                              (agent-session-capability-grants-tail session)
                              existing)
        (setf (agent-session-capability-grants session) grants
              (agent-session-capability-grants-tail session) tail)))
    (append-session-event session :capability-granted (capability-grant-summary existing))
    (refresh-bound-environment-agent-state session)
    existing))

(defun capability-granted-p (session policy-designator)
  (let* ((policy (ensure-capability-policy policy-designator))
         (policy-id (capability-policy-id policy)))
    (find policy-id
          (agent-session-capability-grants session)
          :key #'capability-grant-policy-id
          :test #'eq)))

(defun ensure-capability-granted (session policy-designator)
  (let ((policy (ensure-capability-policy policy-designator)))
    (unless (or (eq (capability-policy-default-grant-mode policy) :implicit)
                (capability-granted-p session policy))
      (append-session-event session :capability-required (capability-policy-summary policy))
      (error "Approval required for ~S. Run (approve ~S) first."
             (capability-policy-id policy)
             (capability-policy-id policy)))
    t))

(defun approve-policy (session policy)
  (capability-grant-policy-id (grant-capability session policy)))

(defun policy-approved-p (session policy)
  (not (null (capability-granted-p session policy))))

(defun ensure-policy-approved (session policy)
  (ensure-capability-granted session policy))

(defun session-approved-policies (session)
  (mapcar #'capability-grant-policy-id (agent-session-capability-grants session)))

(defun session-capability-grants-summary (session)
  (mapcar #'capability-grant-summary (agent-session-capability-grants session)))

(defun work-item-wait-category (session work-item)
  (getf (work-item-wait-report session work-item) :why))

(defun session-wait-summary (session)
  (let ((environment (session-bound-environment session)))
    (if environment
        (progn
          (refresh-environment-workflow-domain environment session)
          (environment-workflow-wait-summary environment))
        (let ((waiting '())
              (blocked '()))
          (dolist (work-item (agent-session-work-items session))
            (let* ((report (work-item-wait-report session work-item))
                   (category (getf report :why)))
              (push (list :work-item-id (work-item-id work-item)
                          :why category
                          :waiting-on (getf report :waiting-on)
                          :pending-validations (getf report :pending-validations)
                          :next-action (getf report :next-action)
                          :resume-payload (getf report :resume-payload))
                    blocked)
              (let ((entry (assoc category waiting)))
                (if entry
                    (incf (cdr entry))
                    (push (cons category 1) waiting)))))
          (list :blocked-count (length blocked)
                :by-reason (mapcar (lambda (entry)
                                     (list :why (car entry) :count (cdr entry)))
                                   (nreverse waiting))
                :blocked-work-items (nreverse blocked))))))

(defun raw-session-validator-replay-groups (session)
  (let ((groups (make-hash-table :test #'equal)))
    (dolist (work-item (agent-session-work-items session))
      (dolist (record (work-item-validator-tasks work-item))
        (let* ((replay-id (validator-task-record-replay-id record))
               (current (gethash replay-id groups)))
          (setf (gethash replay-id groups)
                (list :replay-id replay-id
                      :work-item-id (work-item-id work-item)
                      :task-count (1+ (or (getf current :task-count) 0))
                      :statuses (append (or (getf current :statuses) '())
                                        (list (validator-task-record-status record))))))))
    (let ((result '()))
      (maphash (lambda (_ value)
                 (declare (ignore _))
                 (push value result))
               groups)
      (nreverse result))))

(defun session-validator-replay-groups (session)
  (let ((environment (session-bound-environment session)))
    (let ((raw-groups (raw-session-validator-replay-groups session)))
      (or (and environment
               (environment-validator-replay-groups environment))
          (and environment
               raw-groups
               (refresh-environment-workflow-domain environment session)
               (environment-validator-replay-groups environment))
          raw-groups))))

(defun raw-session-image-reconciliation-summary (session)
  (let ((items '()))
    (dolist (work-item (agent-session-work-items session))
      (let ((record (work-item-image-reconciliation work-item)))
        (when record
          (push (list :work-item-id (work-item-id work-item)
                      :recorded-at (image-reconciliation-record-recorded-at record)
                      :replay-id (image-reconciliation-record-replay-id record)
                      :status (image-reconciliation-record-status record)
                      :source-summary (image-reconciliation-record-source-summary record))
                items))))
    (nreverse items)))

(defun session-image-reconciliation-summary (session)
  (let ((environment (session-bound-environment session)))
    (let ((raw-items (raw-session-image-reconciliation-summary session)))
      (or (and environment
               (environment-image-reconciliation-summary environment))
          (and environment
               raw-items
               (refresh-environment-workflow-domain environment session)
               (environment-image-reconciliation-summary environment))
          raw-items))))

(defun session-incident-summary (session &key (limit 5))
  (let* ((incidents (agent-session-incidents session))
         (open-incidents (remove-if-not (lambda (incident)
                                          (eq (incident-status incident) :open))
                                        incidents))
         (recent (if (> (length incidents) limit)
                     (subseq incidents (- (length incidents) limit))
                     incidents)))
    (list :count (length incidents)
          :open-count (length open-incidents)
          :recent (mapcar #'incident-record-summary recent))))

(defun session-operator-status (session)
  (let ((ready '())
        (blocked '())
        (quarantined '())
        (image-only '())
        (durable '()))
    (dolist (work-item (agent-session-work-items session))
      (let* ((report (work-item-wait-report session work-item))
             (why (getf report :why))
             (entry (list :work-item-id (work-item-id work-item)
                          :status (work-item-status work-item)
                          :why why
                          :waiting-on (getf report :waiting-on)
                          :next-action (getf report :next-action)
                          :resume-payload (getf report :resume-payload))))
        (cond
          ((eq (work-item-status work-item) :quarantined)
           (push entry quarantined))
          ((eq (work-item-status work-item) :image-only)
           (push entry image-only))
          ((eq (work-item-closure-decision work-item) :committed-to-source-and-image)
           (push entry durable))
          ((eq why :ready)
           (push entry ready))
          (t
           (push entry blocked)))))
    (list :ready-count (length ready)
          :blocked-count (length blocked)
          :quarantined-count (length quarantined)
          :image-only-count (length image-only)
          :durable-count (length durable)
          :incident-count (length (agent-session-incidents session))
          :open-incident-count (length (remove-if-not (lambda (incident)
                                                        (eq (incident-status incident) :open))
                                                      (agent-session-incidents session)))
          :ready-work-items (nreverse ready)
          :blocked-work-items (nreverse blocked)
          :quarantined-work-items (nreverse quarantined)
          :image-only-work-items (nreverse image-only)
          :durable-work-items (nreverse durable))))

(defun recent-session-transcript (session &key (limit 6))
  (let* ((entries (agent-session-transcript session))
         (count (length entries)))
    (if (> count limit)
        (subseq entries (- count limit))
        entries)))

(defun session-artifact-summary (session)
  (let ((environment (session-bound-environment session)))
    (or (and environment
             (environment-artifact-summary environment))
        (let* ((artifacts (agent-session-artifacts session))
               (kind-summary (artifact-kind-summary artifacts)))
          (list :artifact-count (length artifacts)
                :kind-counts kind-summary
                :validation-count (or (getf (find :validation kind-summary
                                                  :key (lambda (entry) (getf entry :kind))
                                                  :test #'eq)
                                             :count)
                                      0)
                :reconciliation-count (or (getf (find :reconciliation kind-summary
                                                      :key (lambda (entry) (getf entry :kind))
                                                      :test #'eq)
                                                 :count)
                                          0)
                :incident-count (or (getf (find :incident kind-summary
                                                :key (lambda (entry) (getf entry :kind))
                                                :test #'eq)
                                           :count)
                                    0)
                :plan-count (or (getf (find :plan kind-summary
                                            :key (lambda (entry) (getf entry :kind))
                                            :test #'eq)
                                       :count)
                                0)
                :runtime-artifact-count (count-if (lambda (artifact)
                                                    (member (artifact-kind artifact)
                                                            '(:runtime-state :runtime-eval :runtime-reload)
                                                            :test #'eq))
                                                  artifacts))))))

(defun bound-session-environment-summary (session)
  (let ((environment (session-bound-environment session)))
    (when environment
      (environment-summary environment))))

(defun session-thread-state-summary (session)
  (let* ((environment (session-bound-environment session))
         (conversation-summary (and environment
                                    (environment-conversation-domain-summary environment)))
         (active-thread (and environment
                             (environment-active-thread-summary environment)))
         (threads (and environment
                       (let ((conversation-state (environment-conversation-state environment)))
                         (and conversation-state
                              (environment-conversation-state-threads conversation-state))))))
    (or (and conversation-summary
             (list :current-thread-id (or (getf active-thread :id)
                                          (getf conversation-summary :active-thread-id))
                   :current-thread-title (and active-thread
                                              (getf active-thread :title))
                   :thread-count (getf conversation-summary :thread-count)
                   :threads threads))
        (thread-state-summary session))))

(defun session-events-view (session &key tail)
  (let* ((environment (session-bound-environment session))
         (events (if environment
                     (mapcar #'environment-event->session-event
                             (or (environment-event-log environment) '()))
                     (agent-session-events session)))
         (tail-count (if (and (integerp tail) (plusp tail))
                         tail
                         (length events)))
         (start (max 0 (- (length events) tail-count))))
    (list :event-count (length events)
          :events (subseq events start)
          :environment-backed-p (not (null environment)))))

(defun bound-session-environment-state-summary (environment-summary key)
  (getf environment-summary key))

(defun bound-session-environment-domain-summary (environment-summary key)
  (getf environment-summary key))

(defun session-summary (session)
  (ensure-default-thread session)
  (let* ((environment-summary (bound-session-environment-summary session))
         (operator-evidence (and environment-summary
                                 (environment-operator-evidence environment-summary)))
         (runtime-summary (bound-session-environment-domain-summary environment-summary :runtime-state))
         (conversation-summary (bound-session-environment-domain-summary environment-summary :conversation-state))
         (workflow-summary (bound-session-environment-domain-summary environment-summary :workflow-state))
         (agent-summary (bound-session-environment-domain-summary environment-summary :agent-state))
         (policy-state (and (boundp '*current-environment*)
                            *current-environment*
                            (eq (environment-compatibility-session *current-environment*) session)
                            (environment-policy-state *current-environment*))))
    (append (list :id (agent-session-id session)
                  :cwd (or (bound-session-environment-state-summary environment-summary :storage-root)
                           (agent-session-cwd session))
                  :package (or (getf runtime-summary :package)
                               (agent-session-package session))
                  :thread-state (session-thread-state-summary session)
                  :message-count (or (getf conversation-summary :message-count)
                                     (length (agent-session-messages session)))
                  :turn-count (or (getf conversation-summary :turn-count)
                                  (length (agent-session-turns session)))
                  :operation-count (or (getf conversation-summary :operation-count)
                                       (length (agent-session-operations session)))
                  :artifact-count (or (bound-session-environment-state-summary environment-summary :artifact-count)
                                      (length (agent-session-artifacts session)))
                  :artifact-summary (or (bound-session-environment-state-summary environment-summary :artifact-summary)
                                        (session-artifact-summary session))
                  :plan (or (bound-session-environment-state-summary environment-summary :plan)
                            (agent-session-plan session))
                  :shell-focus-object-id (agent-session-shell-focus-object-id session)
                  :shell-active-panel-id (agent-session-shell-active-panel-id session)
                  :approved-policies (or (and policy-state (getf policy-state :approved-policies))
                                         (session-approved-policies session))
                  :capability-grants (or (and policy-state (getf policy-state :capability-grants))
                                         (session-capability-grants-summary session))
                  :pending-action-count (or (getf agent-summary :pending-action-count)
                                            (length (agent-session-pending-actions session)))
                  :task-count (or (getf agent-summary :task-count)
                                  (length (agent-session-tasks session)))
                  :work-item-count (or (bound-session-environment-state-summary environment-summary :work-item-count)
                                       (length (agent-session-work-items session)))
                  :workflow-record-count (or (getf workflow-summary :workflow-record-count)
                                             (length (agent-session-workflow-records session)))
                  :incident-count (or (bound-session-environment-state-summary environment-summary :incident-count)
                                      (length (agent-session-incidents session)))
                  :incident-summary (or (and operator-evidence (getf operator-evidence :incidents))
                                        (bound-session-environment-state-summary environment-summary :incident-summary)
                                        (session-incident-summary session))
                  :wait-summary (session-wait-summary session)
                  :operator-status (or (and operator-evidence (getf operator-evidence :posture))
                                       (bound-session-environment-state-summary environment-summary :operator-status)
                                       (session-operator-status session))
                  :operator-evidence (or operator-evidence
                                         (list :posture (session-operator-status session)
                                               :incidents (session-incident-summary session)))
                  :validator-replay-groups (session-validator-replay-groups session)
                  :image-reconciliations (session-image-reconciliation-summary session)
                  :active-worker-count (or (getf agent-summary :active-worker-count)
                                           (active-worker-count session))
                  :worker-count (or (getf agent-summary :worker-count)
                                    (length (agent-session-workers session)))
                  :transcript-count (length (agent-session-transcript session))
                  :recent-transcript (recent-session-transcript session)
                  :event-count (or (getf (bound-session-environment-state-summary environment-summary :event-summary)
                                         :event-count)
                                   (length (agent-session-events session)))
                  :event-summary (or (bound-session-environment-state-summary environment-summary :event-summary)
                                     (list :event-count (length (agent-session-events session))
                                           :recent-kinds (recent-event-kinds (agent-session-events session))))
                  :alignment-state (bound-session-environment-state-summary environment-summary :alignment-state)
                  :reconciliation-decision (bound-session-environment-state-summary environment-summary :reconciliation-decision))
            (when environment-summary
              (list :environment environment-summary)))))

(defun compact-session-event-payload (event)
  (let ((payload (event-payload event)))
    (cond
      ((eq (event-kind event) :transcript)
       (list :event payload))
      ((eq (event-kind event) :provider-stream)
       (list :event-summary (list :canonical-type (getf (event-metadata event) :canonical-type)
                                  :legacy-type (getf (event-metadata event) :legacy-type)
                                  :provider-family (getf (event-metadata event) :provider-family))))
      ((listp payload)
       (list :event-summary payload))
      (t
       (list :event-summary payload)))))

(defun serializable-session-value (value)
  (cond
    ((or (null value)
         (eq value t)
         (stringp value)
         (numberp value)
         (characterp value)
         (pathnamep value)
         (keywordp value))
     value)
    ((symbolp value)
     value)
    ((consp value)
     (cons (serializable-session-value (car value))
           (serializable-session-value (cdr value))))
    ((vectorp value)
     (map 'vector #'serializable-session-value value))
    (t
     (princ-to-string value))))

(defun serializable-session-event (event)
  (make-event :id (event-id event)
              :timestamp (event-timestamp event)
              :kind (event-kind event)
              :family (event-family event)
              :entity-id (event-entity-id event)
              :thread-id (event-thread-id event)
              :turn-id (event-turn-id event)
              :visibility (event-visibility event)
              :metadata (serializable-session-value (event-metadata event))
              :payload (serializable-session-value
                        (compact-session-event-payload event))))

(defun serializable-session-events (session)
  (mapcar #'serializable-session-event (agent-session-events session)))

(defun serializable-session-trace-links (session)
  (mapcar #'trace-link-summary (agent-session-trace-links session)))

(defun restore-session-trace-links (session)
  (setf (agent-session-trace-links session)
        (mapcar #'canonicalize-trace-link-record
                (or (agent-session-trace-links session) '())))
  session)

(defun serializable-session-copy (session)
  (ensure-default-thread session)
  (make-agent-session
   :id (agent-session-id session)
   :cwd (agent-session-cwd session)
   :package (agent-session-package session)
   :threads (agent-session-threads session)
   :current-thread-id (agent-session-current-thread-id session)
   :messages (agent-session-messages session)
   :turns (agent-session-turns session)
   :operations (agent-session-operations session)
   :artifacts (agent-session-artifacts session)
   :transcript nil
   :plan (agent-session-plan session)
   :shell-focus-object-id (agent-session-shell-focus-object-id session)
   :shell-active-panel-id (agent-session-shell-active-panel-id session)
   :events (serializable-session-events session)
   :capability-grants (agent-session-capability-grants session)
   :pending-actions (agent-session-pending-actions session)
   :tasks (agent-session-tasks session)
   :projects (agent-session-projects session)
   :current-project-id (agent-session-current-project-id session)
   :trace-links (serializable-session-trace-links session)
   :work-items (agent-session-work-items session)
   :workflow-records (agent-session-workflow-records session)
   :incidents (agent-session-incidents session)
   :workers (serializable-worker-states session)))

(defun save-session (session path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (let ((*print-circle* t)
          (*print-pretty* t))
      (write (serializable-session-copy session) :stream stream)))
  path)

(defun interrupted-operation-status-p (status)
  (member status '(:running) :test #'eq))

(defun interrupted-turn-status-p (status)
  (member status '(:running) :test #'eq))

(defun append-recovery-metadata (metadata &rest entries)
  (append metadata entries))

(defun restore-session-event-payload (event)
  (let ((payload (event-payload event)))
    (setf (event-payload event)
          (or (and (listp payload) (getf payload :event))
              (and (listp payload) (getf payload :event-summary))
              payload))
    event))

(defun restore-session-events-and-transcript (session)
  (let* ((events (mapcar #'restore-session-event-payload (agent-session-events session)))
         (transcript (loop for event in events
                           when (eq (event-kind event) :transcript)
                           collect (event-payload event))))
    (setf (agent-session-events session) events
          (agent-session-transcript session) transcript)
    session))

(defun normalize-loaded-operation-recovery-state (operation)
  (when (interrupted-operation-status-p (operation-status operation))
    (setf (operation-status operation) :interrupted
          (operation-completed-at operation) (or (operation-completed-at operation)
                                                 (get-universal-time))
          (operation-metadata operation)
          (append-recovery-metadata (operation-metadata operation)
                                    :interrupted-during-load-p t
                                    :recovery-state :interrupted)))
  operation)

(defun normalize-loaded-turn-recovery-state (session turn)
  (let* ((operations (list-turn-operations session (turn-id turn)))
         (interrupted-operations (remove-if-not (lambda (operation)
                                                 (eq (operation-status operation) :interrupted))
                                               operations)))
    (when (or (interrupted-turn-status-p (turn-status turn))
              interrupted-operations)
      (setf (turn-status turn) :interrupted
            (turn-completed-at turn) (or (turn-completed-at turn)
                                         (get-universal-time))
            (turn-error-state turn) (or (turn-error-state turn)
                                        :session-recovered-after-interruption)
            (turn-metadata turn)
            (append-recovery-metadata (turn-metadata turn)
                                      :interrupted-during-load-p t
                                      :interrupted-operation-count (length interrupted-operations)
                                      :recovery-state :interrupted))))
  turn)

(defun normalize-loaded-session-recovery-state (session)
  (dolist (operation (agent-session-operations session))
    (normalize-loaded-operation-recovery-state operation))
  (dolist (turn (agent-session-turns session))
    (normalize-loaded-turn-recovery-state session turn))
  session)

(defun load-session (path)
  (with-open-file (stream path :direction :input)
    (let ((session (read stream nil nil)))
      (unless (typep session 'agent-session)
        (error "Session file ~A did not contain an AGENT-SESSION" path))
      (restore-session-events-and-transcript session)
      (restore-session-trace-links session)
      (normalize-session-capability-grants session)
      (ensure-default-thread session)
      (rebuild-agent-session-tails session)
      (rebuild-conversation-tails session)
      (rebuild-workflow-record-tails session)
      (normalize-loaded-session-recovery-state session)
      (setf (agent-session-workers session)
            (serializable-worker-states session))
      (setf (agent-session-workers-tail session)
            (last (agent-session-workers session)))
      (setf *current-session* session)
      (when (and (boundp '*current-environment*) *current-environment*)
        (bind-session-to-environment session *current-environment*))
      session)))

(defun reset-session (&optional session)
  (when session
    (ignore-errors (stop-all-workers session)))
  (let ((fresh-session (make-default-session)))
    (setf *current-session* fresh-session)
    (when (and (boundp '*current-environment*) *current-environment*)
      (bind-session-to-environment fresh-session *current-environment*))
    fresh-session))
