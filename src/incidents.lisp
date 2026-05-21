(in-package #:sbcl-agent)

(defstruct incident
  id
  thread-id
  turn-id
  operation-id
  work-item-id
  workflow-record-id
  kind
  title
  summary
  status
  condition-string
  created-at
  metadata)

(declaim (notinline incident-id
                    incident-thread-id
                    incident-turn-id
                    incident-operation-id
                    incident-work-item-id
                    incident-workflow-record-id
                    incident-kind
                    incident-title
                    incident-summary
                    incident-status
                    incident-condition-string
                    incident-created-at
                    incident-metadata))

(defun plist-remove-keys (plist keys)
  (loop for (key value) on plist by #'cddr
        unless (member key keys :test #'eq)
          append (list key value)))

(defun condition-type-name (condition)
  (when condition
    (let ((class (class-of condition)))
      (and class
           (class-name class)
           (string-upcase (string (class-name class)))))))

(defun restart-display-string (restart)
  (handler-case
      (string-trim '(#\Space #\Tab #\Newline)
                   (with-output-to-string (stream)
                     (princ restart stream)))
    (error ()
      nil)))

(defun restart-summary (restart)
  (let ((name (restart-name restart))
        (display (restart-display-string restart)))
    (list :name (and name (string-upcase (string name)))
          :label (or display
                     (and name (string-capitalize (substitute #\Space #\- (string-downcase (string name)))))
                     "Anonymous restart"))))

(defun runtime-condition-summary (condition)
  (when condition
    (list :type (condition-type-name condition)
          :message (condition->incident-string condition)
          :restart-count (length (compute-restarts condition)))))

(defun runtime-condition-slot-summaries (condition)
  (let* ((class (ignore-errors (class-of condition)))
         (slots (and class
                     (ignore-errors (sb-mop:class-slots class)))))
    (when slots
      (let* ((limited-slots (subseq slots 0 (min (length slots) 12)))
             (summaries
               (remove nil
                       (mapcar (lambda (slot)
                                 (let* ((slot-name (ignore-errors (sb-mop:slot-definition-name slot)))
                                        (boundp (and slot-name
                                                     (ignore-errors (slot-boundp condition slot-name))))
                                        (value (and boundp
                                                    slot-name
                                                    (ignore-errors (slot-value condition slot-name)))))
                                   (and slot-name
                                        (list :name (string-upcase (string slot-name))
                                              :boundp (not (null boundp))
                                              :printed (and boundp
                                                            (ignore-errors
                                                             (let ((text (princ-to-string value)))
                                                               (if (> (length text) 160)
                                                                   (concatenate 'string (subseq text 0 160) "...")
                                                                   text))))
                                              :type (and boundp value
                                                         (ignore-errors
                                                          (string-upcase
                                                           (princ-to-string (type-of value)))))))))
                               limited-slots))))
        (list :slot-count (length slots)
              :slots summaries)))))

(defun runtime-condition-detail (condition)
  (when condition
    (append (list :type (condition-type-name condition)
                  :message (condition->incident-string condition)
                  :printed (ignore-errors (princ-to-string condition))
                  :class (ignore-errors
                           (let ((class (class-of condition)))
                             (and class
                                  (class-name class)
                                  (string-upcase (string (class-name class))))))
                  :restart-count (length (compute-restarts condition)))
            (or (runtime-condition-slot-summaries condition) '()))))

(defun runtime-condition-restart-summaries (condition)
  (when condition
    (remove-duplicates
     (mapcar #'restart-summary (compute-restarts condition))
     :test #'equal)))

(defun incident-condition-summary (incident)
  (or (getf (incident-metadata incident) :condition-summary)
      (let ((condition-text (incident-condition-string incident)))
        (and condition-text
             (list :type nil
                   :message condition-text
                   :restart-count (length (or (getf (incident-metadata incident) :restart-suggestions) '())))))))

(defun incident-condition-detail (incident)
  (or (getf (incident-metadata incident) :condition-detail)
      (let ((summary (incident-condition-summary incident))
            (condition-text (incident-condition-string incident)))
        (and (or summary condition-text)
             (append (list :type (getf summary :type)
                           :message (or (getf summary :message) condition-text)
                           :printed condition-text
                           :class (getf summary :type)
                           :restart-count (or (getf summary :restart-count) 0))
                     '())))))

(defun incident-restart-suggestions (incident)
  (or (getf (incident-metadata incident) :restart-suggestions) '()))

(defun make-incident-id ()
  (format nil "incident-~D-~D" (get-universal-time) (random 1000000)))

(defun incident-record-summary (incident)
  (list :id (incident-id incident)
        :thread-id (incident-thread-id incident)
        :turn-id (incident-turn-id incident)
        :operation-id (incident-operation-id incident)
        :work-item-id (incident-work-item-id incident)
        :workflow-record-id (incident-workflow-record-id incident)
        :kind (incident-kind incident)
        :title (incident-title incident)
        :summary (incident-summary incident)
        :status (incident-status incident)
        :condition (incident-condition-string incident)
        :created-at (incident-created-at incident)
        :metadata (incident-metadata incident)))

(defun incident-linked-thread-summary (session incident)
  (let ((thread-id (incident-thread-id incident)))
    (and thread-id
         (let ((thread (find-thread session thread-id)))
           (and thread (thread-record-summary thread))))))

(defun incident-linked-turn-summary (session incident)
  (let ((turn-id (incident-turn-id incident)))
    (and turn-id
         (let ((turn (find-turn session turn-id)))
           (and turn (turn-record-summary turn))))))

(defun incident-linked-operation-summary (session incident)
  (let ((operation-id (incident-operation-id incident)))
    (and operation-id
         (let ((operation (find-operation session operation-id)))
           (and operation (operation-record-summary operation))))))

(defun incident-linked-work-item-summary (session incident)
  (let ((work-item-id (incident-work-item-id incident)))
    (and work-item-id
         (let ((work-item (find-work-item session work-item-id)))
           (and work-item (work-item-summary work-item))))))

(defun incident-linked-workflow-summary (session incident)
  (let ((workflow-record-id (incident-workflow-record-id incident)))
    (and workflow-record-id
         (let ((record (find-workflow-record session workflow-record-id)))
           (and record (workflow-record-summary record))))))

(defun incident-turn-recovery-summary (session incident)
  (let* ((turn-id (incident-turn-id incident))
         (turn (and turn-id
                    (find-turn session turn-id))))
    (and turn
         (turn-recovery-summary session
                                turn
                                (list-turn-operations session turn-id)))))

(defun incident-work-item-wait-summary (session incident)
  (let* ((work-item-id (incident-work-item-id incident))
         (work-item (and work-item-id
                         (find-work-item session work-item-id))))
    (and work-item
         (work-item-wait-report session work-item))))

(defun incident-runtime-context (session incident)
  (let* ((operation (and (incident-operation-id incident)
                         (find-operation session (incident-operation-id incident))))
         (work-item (and (incident-work-item-id incident)
                         (find-work-item session (incident-work-item-id incident))))
         (history (current-environment-runtime-history)))
    (list :package (or (and operation
                            (getf (operation-metadata operation) :package))
                       (getf (incident-metadata incident) :package)
                       (agent-session-package session))
          :operation-input (and operation (operation-input operation))
          :operation-output (and operation (operation-output operation))
          :operation-policy (and operation (operation-policy-decision operation))
          :operation-recovery-state (and operation
                                         (getf (operation-metadata operation) :recovery-state))
          :condition-summary (incident-condition-summary incident)
          :condition-detail (incident-condition-detail incident)
          :restart-suggestions (incident-restart-suggestions incident)
          :work-item-checkpoint-count (if work-item
                                         (length (work-item-checkpoints work-item))
                                         0)
          :latest-checkpoint-id (and work-item
                                     (latest-work-item-checkpoint-id work-item))
          :runtime-observation-count (if work-item
                                         (length (work-item-runtime-observations work-item))
                                         0)
          :latest-runtime-observation (and work-item
                                           (car (last (work-item-runtime-observations work-item))))
          :recent-runtime-history (runtime-history-tail history 5))))

(defun incident-recovery-plan (session incident)
  (let* ((recovery (incident-turn-recovery-summary session incident))
         (wait (incident-work-item-wait-summary session incident))
         (actions (incident-recommended-actions session incident)))
    (list :incident-id (incident-id incident)
          :status (incident-status incident)
          :resumable-p (and recovery (getf recovery :resumable-p))
          :interrupted-p (and recovery (getf recovery :interrupted-p))
          :wait-reason (and wait (getf wait :why))
          :next-action (and wait (getf wait :next-action))
          :resume-payload (and wait (getf wait :resume-payload))
          :actions actions)))

(defun incident-recommended-actions (session incident)
  (let* ((recovery (incident-turn-recovery-summary session incident))
         (wait (incident-work-item-wait-summary session incident))
         (restart-suggestions (incident-restart-suggestions incident))
         (actions '()))
    (dolist (restart restart-suggestions)
      (push (list :type :consider-restart
                  :incident-id (incident-id incident)
                  :restart-name (getf restart :name)
                  :label (getf restart :label))
            actions))
    (when (and recovery (getf recovery :resumable-p))
      (push (list :type :resume-turn
                  :turn-id (incident-turn-id incident)
                  :command :turn/resume)
            actions))
    (when wait
      (let ((next-action (getf wait :next-action)))
        (when next-action
          (push (append (list :type :work-item-next-action
                              :work-item-id (incident-work-item-id incident))
                        next-action)
                actions))))
    (when (incident-operation-id incident)
      (push (list :type :inspect-runtime-context
                  :incident-id (incident-id incident)
                  :command `(incident/show ,(incident-id incident)))
            actions))
    (nreverse actions)))

(defun incident-remediation-plan (incident)
  (getf (incident-metadata incident) :remediation-plan))

(defun update-incident-remediation-plan (session incident remediation-plan)
  (declare (ignore session))
  (let* ((metadata (incident-metadata incident))
         (without-plan (loop for (key value) on metadata by #'cddr
                             unless (eq key :remediation-plan)
                               append (list key value))))
    (setf (incident-metadata incident)
          (append without-plan
                  (list :remediation-plan remediation-plan))))
  incident)

(defun merge-runtime-incident-metadata (metadata condition)
  (append (plist-remove-keys metadata '(:condition-summary :condition-detail :restart-suggestions))
          (list :condition-summary (runtime-condition-summary condition)
                :condition-detail (runtime-condition-detail condition)
                :restart-suggestions (runtime-condition-restart-summaries condition))))

(defun maybe-create-incident-recovery-plan-artifact (session incident)
  (let* ((thread-id (incident-thread-id incident))
         (thread (and thread-id (find-thread session thread-id)))
         (turn (and (incident-turn-id incident)
                    (find-turn session (incident-turn-id incident))))
         (operation (and (incident-operation-id incident)
                         (find-operation session (incident-operation-id incident))))
         (plan (incident-recovery-plan session incident)))
    (when (and thread
               (getf plan :actions))
      (create-artifact session
                       thread
                       turn
                       operation
                       :plan
                       nil
                       :title (format nil "Recovery plan for ~A" (incident-id incident))
                       :summary "Recovery guidance captured for incident follow-through."
                       :work-item-id (incident-work-item-id incident)
                       :metadata (list :source :incident-recovery-plan
                                       :incident-id (incident-id incident)
                                       :recovery-plan plan)))))

(defun incident-detail (session incident)
  (append (incident-record-summary incident)
          (list :thread (incident-linked-thread-summary session incident)
                :turn (incident-linked-turn-summary session incident)
                :operation (incident-linked-operation-summary session incident)
                :work-item (incident-linked-work-item-summary session incident)
                :workflow-record (incident-linked-workflow-summary session incident)
                :trace-neighborhood (trace-neighborhood-summary session :incident (incident-id incident))
                :runtime-context (incident-runtime-context session incident)
                :recovery (incident-turn-recovery-summary session incident)
                :wait (incident-work-item-wait-summary session incident)
                :recovery-plan (incident-recovery-plan session incident)
                :remediation-plan (incident-remediation-plan incident)
                :recommended-actions (incident-recommended-actions session incident))))

(defun find-incident (session incident-id)
  (find incident-id (agent-session-incidents session)
        :key #'incident-id :test #'string=))

(defun list-incident-summaries (session &key thread-id turn-id)
  (mapcar #'incident-record-summary
          (remove-if-not (lambda (incident)
                           (and (if thread-id
                                    (string= thread-id (incident-thread-id incident))
                                    t)
                                (if turn-id
                                    (string= turn-id (incident-turn-id incident))
                                    t)))
                         (agent-session-incidents session))))

(defun operation-incidents (session operation-or-id)
  (let ((operation-id (etypecase operation-or-id
                        (operation (operation-id operation-or-id))
                        (string operation-or-id))))
    (remove-if-not (lambda (incident)
                     (and (incident-operation-id incident)
                          (string= operation-id (incident-operation-id incident))))
                   (agent-session-incidents session))))

(defun latest-operation-incident (session operation-or-id)
  (car (last (operation-incidents session operation-or-id))))

(defun thread-incidents (session thread-id)
  (remove-if-not (lambda (incident)
                   (and (incident-thread-id incident)
                        (string= thread-id (incident-thread-id incident))))
                 (agent-session-incidents session)))

(defun turn-incidents (session turn-id)
  (remove-if-not (lambda (incident)
                   (and (incident-turn-id incident)
                        (string= turn-id (incident-turn-id incident))))
                 (agent-session-incidents session)))

(defun condition->incident-string (condition)
  (typecase condition
    (null nil)
    (string condition)
    (t (princ-to-string condition))))

(defun maybe-bind-incident-to-operation (operation incident)
  (when (and operation incident)
    (let ((incident-id (incident-id incident))
          (existing (getf (operation-metadata operation) :incident-ids)))
      (setf (operation-metadata operation)
            (append (operation-metadata operation)
                    (list :incident-ids
                          (append existing (list incident-id)))))))
  incident)

(defun maybe-bind-incident-to-turn (turn incident)
  (when (and turn incident)
    (let ((incident-id (incident-id incident))
          (existing (getf (turn-metadata turn) :incident-ids)))
      (setf (turn-metadata turn)
            (append (turn-metadata turn)
                    (list :incident-ids
                          (append existing (list incident-id)))))))
  incident)

(defun create-incident (session kind title summary
                         &key thread turn operation work-item workflow-record
                           condition metadata (status :open))
  (let* ((thread-record (or thread
                            (ignore-errors (current-thread session))))
         (incident (make-incident :id (make-incident-id)
                                  :thread-id (and thread-record (thread-id thread-record))
                                  :turn-id (and turn (turn-id turn))
                                  :operation-id (and operation (operation-id operation))
                                  :work-item-id (and work-item (work-item-id work-item))
                                  :workflow-record-id (and workflow-record
                                                           (workflow-record-id workflow-record))
                                  :kind kind
                                  :title title
                                  :summary summary
                                  :status status
                                  :condition-string (condition->incident-string condition)
                                  :created-at (get-universal-time)
                                  :metadata metadata)))
    (multiple-value-bind (incidents tail)
        (append-linked-item (agent-session-incidents session)
                            (agent-session-incidents-tail session)
                            incident)
      (setf (agent-session-incidents session) incidents
            (agent-session-incidents-tail session) tail))
    (when work-item
      (create-trace-link session
                         :relation :degraded-by-incident
                         :source-kind :work-item
                         :source-id (work-item-id work-item)
                         :target-kind :incident
                         :target-id (incident-id incident)
                         :metadata (list :workflow-record-id (and workflow-record
                                                                  (workflow-record-id workflow-record))
                                         :kind kind)))
    (maybe-bind-incident-to-operation operation incident)
    (maybe-bind-incident-to-turn turn incident)
    (append-session-event session
                          :incident-created
                          (incident-record-summary incident)
                          :family :incident
                          :entity-id (incident-id incident)
                          :thread-id (and thread-record (thread-id thread-record))
                          :turn-id (and turn (turn-id turn))
                          :visibility :operator
                          :metadata (list :workflow-record-id (and workflow-record
                                                                   (workflow-record-id workflow-record)))
                          :operation-id (and operation (operation-id operation))
                          :work-item-id (and work-item (work-item-id work-item))
                          :incident-id (incident-id incident))
    (let ((environment (session-bound-environment session)))
      (when environment
        (environment-append-incident environment session incident)))
    (when thread-record
      (create-artifact session
                       thread-record
                       turn
                       operation
                       :incident
                       nil
                       :title title
                       :summary summary
                       :work-item-id (and work-item (work-item-id work-item))
                       :metadata (list :source :incident
                                       :incident-id (incident-id incident)
                                       :kind kind
                                       :condition (condition->incident-string condition))))
    (maybe-create-incident-recovery-plan-artifact session incident)
    incident))

(defun record-runtime-incident (session condition
                                &key thread turn operation work-item kind title summary metadata)
  (let* ((bound-work-item (or work-item
                              (and operation
                                   (operation-bound-work-item session operation))))
         (workflow-record (and bound-work-item
                               (work-item-workflow-record session bound-work-item)))
         (reason (or summary
                     (condition->incident-string condition)
                     "Runtime incident captured.")))
    (when (and bound-work-item
               (not (eq (work-item-status bound-work-item) :quarantined)))
      (quarantine-work-item session
                            bound-work-item
                            reason
                            :evidence (list :source :runtime-incident
                                            :operation-id (and operation (operation-id operation))
                                            :turn-id (and turn (turn-id turn))
                                            :condition (condition->incident-string condition))))
    (create-incident session
                     (or kind :runtime-condition)
                     (or title "Runtime incident")
                     reason
                     :thread thread
                     :turn turn
                     :operation operation
                     :work-item bound-work-item
                     :workflow-record workflow-record
                     :condition condition
                     :metadata (merge-runtime-incident-metadata metadata condition)
                     :status :open)))
