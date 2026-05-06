(in-package #:sbcl-agent)

(defparameter +reconciliation-correction-policy+ :alignment-reconciliation-execute)
(defparameter *continuous-alignment-event-loop-enabled* t)
(defparameter *continuous-alignment-event-loop-active* nil)

(defparameter +continuous-alignment-trigger-kinds+
  '(:incident-created
    :validation-completed
    :runtime-evaluated
    :runtime-reloaded-file
    :runtime-package-switched))

(defun reconciliation-action-label (action)
  (string-downcase
   (substitute #\Space #\- (symbol-name (or (getf action :kind) :unknown)))))

(defun corrective-work-item-goal (decision)
  (let* ((direction (or (getf decision :decision) :reconcile))
         (actions (or (getf decision :proposed-actions) '()))
         (intent-id (getf decision :intent-id))
         (action-summary (if actions
                             (format nil "~{~A~^, ~}"
                                     (mapcar #'reconciliation-action-label actions))
                             "monitor alignment")))
    (format nil "Reconcile ~A alignment for ~A via ~A."
            (string-downcase (symbol-name direction))
            (or intent-id "current-intent")
            action-summary)))

(defun corrective-work-item-mutation-intent (decision packet prompt)
  (list :source :reconciliation-decision
        :prompt prompt
        :intent-id (getf decision :intent-id)
        :decision (getf decision :decision)
        :approval-posture (getf decision :approval-posture)
        :proposed-actions (copy-tree (or (getf decision :proposed-actions) '()))
        :alignment-state (copy-tree (or (getf decision :alignment-state) '()))
        :context-packet (copy-tree packet)))

(defun append-corrective-workflow-entry (session work-item decision)
  (append-work-item-workflow-entry
   session
   work-item
   :plan
   :reconciliation-correction-planned
   (list :decision (getf decision :decision)
         :approval-posture (getf decision :approval-posture)
         :proposed-actions (copy-tree (or (getf decision :proposed-actions) '()))
         :trigger-events (copy-tree (or (getf decision :trigger-events) '())))
   :status :open))

(defun set-corrective-work-item-controls (session work-item decision)
  (set-work-item-next-action
   session
   work-item
   (list :type :execute-reconciliation-correction
         :decision (getf decision :decision)
         :approval-posture (getf decision :approval-posture)
         :proposed-actions (copy-tree (or (getf decision :proposed-actions) '()))))
  (set-work-item-resume-payload
   session
   work-item
   (list :resume-command `(resume-work-item ,(work-item-id work-item))
         :decision (getf decision :decision)
         :approval-posture (getf decision :approval-posture)
         :approval-policy +reconciliation-correction-policy+
         :proposed-actions (copy-tree (or (getf decision :proposed-actions) '())))))

(defun trace-corrective-work-item (session work-item decision)
  (let ((intent-id (getf decision :intent-id))
        (trigger-events (or (getf decision :trigger-events) '())))
    (when intent-id
      (create-trace-link session
                         :relation :reconciled-by-work-item
                         :source-kind :intent
                         :source-id intent-id
                         :target-kind :work-item
                         :target-id (work-item-id work-item)
                         :metadata (list :origin :reconciliation-execution)))
    (dolist (event trigger-events)
      (let ((event-id (getf event :event-id)))
        (when event-id
          (create-trace-link session
                             :relation :triggered-corrective-work
                             :source-kind :event
                             :source-id event-id
                             :target-kind :work-item
                             :target-id (work-item-id work-item)
                             :metadata (list :origin :reconciliation-execution
                                             :event-kind (getf event :kind)))))))
  work-item)

(defun append-reconciliation-correction-event (session work-item decision)
  (append-session-event
   session
   :reconciliation-correction-created
   (list :work-item-id (work-item-id work-item)
         :decision (getf decision :decision)
         :approval-posture (getf decision :approval-posture)
         :proposed-action-count (length (or (getf decision :proposed-actions) '()))
         :trigger-event-count (length (or (getf decision :trigger-events) '())))
   :family :workflow
   :visibility :operator
   :entity-id (work-item-id work-item)
   :work-item-id (work-item-id work-item)))

(defun continuous-alignment-trigger-event-p (event)
  (member (event-kind event) +continuous-alignment-trigger-kinds+ :test #'eq))

(defun corrective-work-item-actionable-p (work-item)
  (and (work-item-corrective-context work-item)
       (or (work-item-resume-payload work-item)
           (work-item-next-action work-item)
           (work-item-pending-validations work-item)
           (member (work-item-status work-item)
                   '(:created :planned :checkpointed :mutating :resumed :awaiting-approval :awaiting-cold-validation :quarantined)
                   :test #'eq))))

(defun corrective-work-item-matches-decision-p (work-item decision)
  (let* ((context (work-item-corrective-context work-item))
         (existing-events (mapcar (lambda (event) (getf event :event-id))
                                  (or (getf context :trigger-events) '())))
         (incoming-events (mapcar (lambda (event) (getf event :event-id))
                                  (or (getf decision :trigger-events) '()))))
    (and context
         (equal (getf context :intent-id)
                (getf decision :intent-id))
         (eq (getf context :decision)
             (getf decision :decision))
         (or (null incoming-events)
             (intersection existing-events incoming-events :test #'string=)))))

(defun existing-actionable-corrective-work-item (session decision)
  (find-if (lambda (work-item)
             (and (corrective-work-item-actionable-p work-item)
                  (corrective-work-item-matches-decision-p work-item decision)))
           (agent-session-work-items session)))

(defun continuous-alignment-prompt-for-event (event)
  (format nil
          "Evaluate continuous alignment after event ~A in family ~A and determine whether governed corrective execution is required."
          (event-kind event)
          (event-family event)))

(defun continuous-alignment-current-intent-available-p (session)
  (not (null (current-intent-record session))))

(defun materialize-reconciliation-correction-from-decision (session prompt packet state decision)
  (if (eq (getf decision :decision) :maintain)
      (kernelize-service-command-response
       (make-service-response
        :alignment
        :materialize-reconciliation-correction
        :command
        (list :outcome :no-correction-needed
              :reconciliation-decision decision)
        :metadata (make-service-metadata :authority :environment
                                         :command-model :reconciliation-correction-command-v1
                                         :session session))
       :session session
       :intention "Acknowledge that current alignment does not require corrective governed execution."
       :capability :alignment-reconciliation-execute
       :authority :governance)
      (let ((existing (existing-actionable-corrective-work-item session decision)))
        (if existing
            (kernelize-service-command-response
             (make-service-response
              :alignment
              :materialize-reconciliation-correction
              :command
              (list :outcome :existing-correction-active
                    :reconciliation-decision decision
                    :work-item (enriched-work-item-service-detail session existing))
              :metadata (make-service-metadata :authority :environment
                                               :command-model :reconciliation-correction-command-v1
                                               :session session
                                               :work-item-id (work-item-id existing)))
             :session session
             :intention "Preserve the active governed corrective work instead of creating a duplicate."
             :capability :alignment-reconciliation-execute
             :authority :governance)
            (let* ((work-item (create-work-item
                               session
                               (corrective-work-item-goal decision)
                               :mutation-intent (corrective-work-item-mutation-intent decision packet prompt)
                               :transaction-scope :alignment-reconciliation))
                   (record (work-item-workflow-record session work-item))
                   (approval-required-p (getf decision :requires-approval-p))
                   (approval-reason (or (getf (first (or (getf decision :proposed-actions) '())) :reason)
                                        "Corrective execution requires governed review before mutation proceeds.")))
              (append-corrective-workflow-entry session work-item decision)
              (set-corrective-work-item-controls session work-item decision)
              (trace-corrective-work-item session work-item decision)
              (append-reconciliation-correction-event session work-item decision)
              (when approval-required-p
                (request-work-item-approval session
                                            work-item
                                            +reconciliation-correction-policy+
                                            :reason approval-reason))
              (kernelize-service-command-response
               (make-service-response
                :alignment
                :materialize-reconciliation-correction
                :command
                (list :outcome (if approval-required-p :awaiting-approval :created)
                      :reconciliation-decision decision
                      :work-item (enriched-work-item-service-detail session work-item)
                      :workflow-record (and record
                                            (enrich-workflow-record-summary-with-executions
                                             session
                                             (workflow-record-summary record))))
                :status (if approval-required-p :awaiting-approval :ok)
                :metadata (make-service-metadata :authority :environment
                                                 :command-model :reconciliation-correction-command-v1
                                                 :session session
                                                 :policy-id (and approval-required-p
                                                                 +reconciliation-correction-policy+)
                                                 :work-item-id (work-item-id work-item)
                                                 :workflow-record-id (and record
                                                                          (workflow-record-id record))))
               :session session
               :intention "Materialize reconciliation into governed corrective execution."
               :capability :alignment-reconciliation-execute
               :authority :governance
               :constraints (list :decision (getf decision :decision)
                                  :approval-posture (getf decision :approval-posture)
                                  :prompt prompt)))))))

(defun maybe-run-continuous-alignment-loop-for-event (session event)
  (when (and *continuous-alignment-event-loop-enabled*
             (not *continuous-alignment-event-loop-active*)
             (continuous-alignment-current-intent-available-p session)
             (continuous-alignment-trigger-event-p event))
    (let ((*continuous-alignment-event-loop-active* t))
      (let* ((prompt (continuous-alignment-prompt-for-event event))
             (packet (build-alignment-context-packet session prompt :operator-mode :environment))
             (state (alignment-state->plist
                     (build-alignment-state-from-packet packet)))
             (decision (append (reconciliation-decision->plist
                                (build-reconciliation-decision-from-state packet state))
                               (list :alignment-state state
                                     :context-packet packet))))
        (materialize-reconciliation-correction-from-decision session prompt packet state decision)))))

(defun command-materialize-reconciliation-correction-service (session prompt &key (operator-mode :conversation))
  (let* ((packet (build-alignment-context-packet session prompt :operator-mode operator-mode))
         (state (alignment-state->plist
                 (build-alignment-state-from-packet packet)))
         (decision (append (reconciliation-decision->plist
                            (build-reconciliation-decision-from-state packet state))
                           (list :alignment-state state
                                 :context-packet packet))))
    (materialize-reconciliation-correction-from-decision session prompt packet state decision)))
