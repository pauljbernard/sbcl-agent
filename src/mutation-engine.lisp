(in-package #:sbcl-agent)

(defun mutation-policy-decision-summary (policy &key (decision :allowed) reason)
  (let ((policy-record (ensure-capability-policy policy)))
    (list :policy-id (capability-policy-id policy-record)
          :decision decision
          :risk-level (capability-policy-risk-level policy-record)
          :default-grant-mode (capability-policy-default-grant-mode policy-record)
          :reason reason)))

(defun policy-decision-summary (policy &key (decision :allowed) reason)
  (mutation-policy-decision-summary policy :decision decision :reason reason))

(defun assistant-action-policy-id (action)
  (case (assistant-action-type action)
    (:eval
     (if (mutating-eval-action-p action)
         :runtime-eval-mutate
         :runtime-eval-safe))
    (:tool
     (let* ((payload (assistant-action-payload action))
            (tool-id (or (getf payload :TOOL-ID)
                         (getf payload :TOOL_ID))))
       (and tool-id
            (ignore-errors (getf (describe-tool tool-id) :policy)))))
    (:patch :workspace-write)
    (t nil)))

(defun assistant-action-policy-decision (action disposition)
  (let ((policy-id (assistant-action-policy-id action)))
    (if policy-id
        (mutation-policy-decision-summary policy-id
                                          :decision disposition
                                          :reason "Assistant action recorded from conversation response handling.")
        (list :policy-id nil
              :decision disposition
              :reason "Assistant action recorded without a known policy mapping."))))

(defun assistant-action-requires-approval-p (action)
  (let ((policy-id (assistant-action-policy-id action)))
    (and policy-id
         (let ((policy (ensure-capability-policy policy-id)))
           (not (eq (capability-policy-default-grant-mode policy) :implicit))))))

(defun governed-assistant-action-p (action)
  (let ((policy-id (assistant-action-policy-id action)))
    (or (eq (assistant-action-type action) :patch)
        (eq policy-id :runtime-eval-mutate)
        (member policy-id '(:workspace-write :git-write :process-run) :test #'eq))))

(defun governed-actions-present-p (action-report)
  (find-if #'governed-assistant-action-p
           (append (getf action-report :immediate-actions)
                   (getf action-report :staged-actions))))

(defun staged-assistant-action-disposition (action)
  (if (assistant-action-requires-approval-p action)
      :approval-required
      :staged))

(defun deferred-assistant-action-disposition (action)
  (declare (ignore action))
  :deferred)

(defun staged-assistant-action-status (action)
  (if (assistant-action-requires-approval-p action)
      :awaiting-approval
      :staged))

(defun deferred-assistant-action-status (action)
  (declare (ignore action))
  :blocked)

(defun action-operation-name (action)
  (case (assistant-action-type action)
    (:eval "assistant-eval")
    (:tool "assistant-tool")
    (:patch "assistant-patch")
    (t "assistant-action")))

(defun turn-bound-work-item-id (turn)
  (getf (turn-metadata turn) :work-item-id))

(defun cognition-bundle-long-horizon-plan (cognition-bundle)
  (when cognition-bundle
    (let* ((planning-steps (or (getf (cognition-bundle-planning-brief cognition-bundle) :ordered-steps) '()))
           (planning-phases (remove nil (mapcar (lambda (step) (getf step :phase))
                                                planning-steps))))
      (list :execution-mode (getf (cognition-bundle-execution-strategy cognition-bundle) :mode)
            :validation-mode (getf (cognition-bundle-validation-strategy cognition-bundle) :mode)
            :agenda-step-count (getf (cognition-bundle-action-agenda cognition-bundle) :step-count)
            :agenda-primary-step (getf (cognition-bundle-action-agenda cognition-bundle) :primary-step)
            :validation-work-item-count (getf (cognition-bundle-validation-plan cognition-bundle) :work-item-count)
            :reuse-recommendation (getf (cognition-bundle-prior-outcome-brief cognition-bundle) :reuse-recommendation)
            :planning-phases planning-phases
            :phase-count (length planning-phases)
            :decomposition-recipe (list :phase-count (length planning-phases)
                                        :phases planning-phases
                                        :agenda-primary-step (getf (cognition-bundle-action-agenda cognition-bundle) :primary-step))
            :plan-health :active))))

(defun stamp-turn-mutation-work-item-plan (session turn work-item cognition-bundle)
  (let ((plan (cognition-bundle-long-horizon-plan cognition-bundle)))
    (when (and work-item plan)
      (set-work-item-long-horizon-plan work-item plan)
      (when (work-item-next-action work-item)
        (set-work-item-next-action session work-item (copy-list (work-item-next-action work-item))))
      (when (work-item-resume-payload work-item)
        (set-work-item-resume-payload session work-item (copy-list (work-item-resume-payload work-item))))
      (setf (turn-metadata turn)
            (append (turn-metadata turn)
                    (list :long-horizon-plan plan))))
    work-item))

(defun ensure-turn-mutation-work-item (session thread turn action-report prompt &key cognition-bundle)
  (let ((existing-id (turn-bound-work-item-id turn)))
    (cond
      (existing-id
       (stamp-turn-mutation-work-item-plan session
                                           turn
                                           (find-work-item session existing-id)
                                           cognition-bundle))
      ((not (governed-actions-present-p action-report))
       nil)
      (t
       (let ((work-item (create-work-item session
                                          (format nil "Conversation turn ~A mutation" (turn-id turn))
                                          :mutation-intent (list :source :conversation-turn
                                                                 :thread-id (thread-id thread)
                                                                 :turn-id (turn-id turn)
                                                                 :prompt prompt
                                                                 :action-types (mapcar #'assistant-action-type
                                                                                       (append (getf action-report :immediate-actions)
                                                                                               (getf action-report :staged-actions))))
                                          :transaction-scope :conversation-turn)))
         (append-work-item-checkpoint session work-item
                                      :validation-baseline (list :turn-id (turn-id turn)
                                                                 :thread-id (thread-id thread)
                                                                 :prompt prompt))
         (append-work-item-runtime-observation session
                                               work-item
                                               :conversation-turn-bound
                                               (list :thread-id (thread-id thread)
                                                     :turn-id (turn-id turn)
                                                     :prompt prompt))
         (setf (turn-metadata turn)
               (append (turn-metadata turn)
                       (list :work-item-id (work-item-id work-item))))
         (let ((approval-action (find-if #'assistant-action-requires-approval-p
                                         (append (getf action-report :immediate-actions)
                                                 (getf action-report :staged-actions)))))
           (when approval-action
             (let ((policy-id (assistant-action-policy-id approval-action)))
               (request-work-item-approval session
                                           work-item
                                           policy-id
                                           :reason "Governed conversation turn requires explicit approval before mutation."))))
         (stamp-turn-mutation-work-item-plan session turn work-item cognition-bundle))))))

(defun apply-resumed-mutation-result (session thread turn operation result)
  (let ((policy-id (getf (operation-policy-decision operation) :policy-id)))
    (update-work-item-status-from-operation session
                                            operation
                                            :mutating
                                            :closure-decision :conversation-mutation-in-progress)
    (if (eq (getf result :status) :failed)
        (progn
          (complete-operation session
                              thread
                              turn
                              operation
                              result
                              :status :failed
                              :metadata (append '(:execution :resumed)
                                                (let ((incident (getf result :incident)))
                                                  (when incident
                                                    (list :incident-id (getf incident :id))))))
          (let ((work-item (operation-bound-work-item session operation)))
            (cond
              ((and work-item
                    (eq (work-item-status work-item) :quarantined))
               nil)
              (work-item
               (quarantine-work-item session
                                     work-item
                                     (or (getf result :error)
                                         "Resumed assistant action failed during governed execution.")
                                     :evidence (list :source :turn-resume
                                                     :turn-id (turn-id turn)
                                                     :operation-id (operation-id operation)
                                                     :incident (getf result :incident))))
              (t
               (update-work-item-status-from-operation session
                                                       operation
                                                       :failed
                                                       :closure-decision :runtime-incident
                                                       :error (getf result :error)
                                                       :result result)))))
        (progn
          (complete-operation session
                              thread
                              turn
                              operation
                              (or result (list :resumed-p t))
                              :status :completed
                              :metadata '(:execution :resumed))
          (update-work-item-status-from-operation session
                                                  operation
                                                  (if (member policy-id '(:runtime-eval-mutate :runtime-reload) :test #'eq)
                                                      :awaiting-cold-validation
                                                      :committed)
                                                  :closure-decision (if (eq policy-id :runtime-eval-mutate)
                                                                        :committed-to-image
                                                                        :committed-to-source-and-image)
                                                  :result result)))))
