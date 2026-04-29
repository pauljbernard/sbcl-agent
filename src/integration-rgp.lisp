(in-package #:sbcl-agent)

(defparameter +rgp-runtime-subtype+ "sbcl_agent")
(defparameter +rgp-session-kind+ "stateful_runtime")
(defparameter +rgp-node-profile-key+ :rgp-node-profile)
(defparameter +rgp-assignments-key+ :rgp-local-assignments)
(defparameter +rgp-usage-telemetry-key+ :rgp-usage-telemetry)
(defparameter +rgp-publication-backlog-key+ :rgp-publication-backlog)
(defparameter +rgp-execution-facts-key+ :rgp-execution-facts)
(defparameter +rgp-billing-milestones-key+ :rgp-billing-milestones)

(defun plist-without-key (plist key)
  (cond
    ((null plist) '())
    ((eq (first plist) key)
     (plist-without-key (cddr plist) key))
    (t
     (list* (first plist)
            (second plist)
            (plist-without-key (cddr plist) key)))))

(defun plist-put (plist key value)
  (append (plist-without-key plist key) (list key value)))

(defun ensure-rgp-bound-environment (session &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (unless (eq (environment-compatibility-session active-environment) session)
      (bind-session-to-environment session active-environment))
    active-environment))

(defun environment-rgp-binding (&optional environment)
  (getf (environment-metadata (ensure-environment environment)) :rgp-binding))

(defun normalize-rgp-string (value field)
  (cond
    ((null value) nil)
    ((stringp value) value)
    ((symbolp value) (string-downcase (symbol-name value)))
    (t (error "RGP ~A must be a string, symbol, or NIL" field))))

(defun normalize-rgp-string-list (values field)
  (cond
    ((null values) '())
    ((listp values)
     (remove nil
             (mapcar (lambda (value)
                       (normalize-rgp-string value field))
                     values)
             :test #'equal))
    (t
     (list (normalize-rgp-string values field)))))

(defun environment-rgp-node-profile (&optional environment)
  (environment-metadata-value (ensure-environment environment)
                              +rgp-node-profile-key+))

(defun environment-rgp-local-assignments (&optional environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +rgp-assignments-key+)
      '()))

(defun environment-rgp-usage-telemetry (&optional environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +rgp-usage-telemetry-key+)
      (list :provider-count 0
            :total-input-tokens 0
            :total-output-tokens 0
            :total-cached-tokens 0
            :execution-seconds 0
            :blocked-seconds 0
            :tool-invocations 0
            :artifact-count 0
            :validation-effort 0
            :reports-count 0
            :updated-at nil
            :last-report nil)))

(defun environment-rgp-publication-backlog (&optional environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +rgp-publication-backlog-key+)
      '()))

(defun environment-rgp-execution-facts (&optional environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +rgp-execution-facts-key+)
      '()))

(defun environment-rgp-billing-milestones (&optional environment)
  (or (environment-metadata-value (ensure-environment environment)
                                  +rgp-billing-milestones-key+)
      '()))

(defun make-rgp-publication-id (&optional prefix)
  (format nil "~A-~D-~D"
          (or prefix "publication")
          (get-universal-time)
          (abs (random 1000000))))

(defun canonical-rgp-publication-entry (&key id
                                             topic
                                             assignment-id
                                             state
                                             payload
                                             attempt-count
                                             last-attempt-at
                                             next-attempt-at
                                             created-at
                                             updated-at
                                             last-state-change-at
                                             published-at
                                             failure-reason)
  (unless topic
    (error "RGP publication backlog entries require :TOPIC"))
  (list :id (or (normalize-rgp-string id :publication-id)
                (make-rgp-publication-id "publication"))
        :topic (normalize-rgp-string topic :topic)
        :assignment-id (normalize-rgp-string assignment-id :assignment-id)
        :state (normalize-rgp-string state :state)
        :payload payload
        :attempt-count (or attempt-count 0)
        :last-attempt-at last-attempt-at
        :next-attempt-at next-attempt-at
        :created-at created-at
        :updated-at updated-at
        :last-state-change-at last-state-change-at
        :published-at published-at
        :failure-reason (normalize-rgp-string failure-reason :failure-reason)))

(defun enqueue-environment-rgp-publication (session &key topic
                                                 assignment-id
                                                 payload
                                                 environment)
  (let* ((timestamp (get-universal-time))
         (active-environment (ensure-rgp-bound-environment session environment))
         (entry (canonical-rgp-publication-entry
                 :topic topic
                 :assignment-id assignment-id
                 :state :pending
                 :payload payload
                 :attempt-count 0
                 :created-at timestamp
                 :updated-at timestamp
                 :last-state-change-at timestamp))
         (backlog (environment-rgp-publication-backlog active-environment)))
    (set-environment-metadata-value active-environment
                                    +rgp-publication-backlog-key+
                                    (append backlog (list entry)))
    entry))

(defun update-environment-rgp-publication-entry (session publication-id &key state
                                                      published-at
                                                      next-attempt-at
                                                      failure-reason
                                                      environment)
  (let* ((timestamp (get-universal-time))
         (active-environment (ensure-rgp-bound-environment session environment))
         (backlog (environment-rgp-publication-backlog active-environment))
         (existing (find publication-id backlog
                         :key (lambda (entry) (getf entry :id))
                         :test #'string=))
         (target-state (or (normalize-rgp-string state :state)
                           (getf existing :state))))
    (unless existing
      (error "Unknown RGP publication ~A" publication-id))
    (let ((updated (canonical-rgp-publication-entry
                    :id (getf existing :id)
                    :topic (getf existing :topic)
                    :assignment-id (getf existing :assignment-id)
                    :state target-state
                    :payload (getf existing :payload)
                    :attempt-count (if (member target-state
                                               '("retrying" "published")
                                               :test #'string=)
                                       (1+ (or (getf existing :attempt-count) 0))
                                       (or (getf existing :attempt-count) 0))
                    :last-attempt-at (if (member target-state
                                                 '("retrying" "published")
                                                 :test #'string=)
                                         timestamp
                                         (getf existing :last-attempt-at))
                    :next-attempt-at next-attempt-at
                    :created-at (getf existing :created-at)
                    :updated-at timestamp
                    :last-state-change-at timestamp
                    :published-at (or published-at (getf existing :published-at))
                    :failure-reason (or failure-reason (getf existing :failure-reason)))))
      (set-environment-metadata-value
       active-environment
       +rgp-publication-backlog-key+
       (mapcar (lambda (entry)
                 (if (string= (getf entry :id) publication-id)
                     updated
                     entry))
               backlog))
      updated)))

(defun canonical-rgp-node-profile (&key rgp-agent-id
                                        operator-id
                                        employment-model
                                        trust-profile
                                        visibility-profile
                                        billing-profile
                                        accepted-policy-profiles)
  (list :rgp-agent-id (normalize-rgp-string rgp-agent-id :rgp-agent-id)
        :operator-id (normalize-rgp-string operator-id :operator-id)
        :employment-model (normalize-rgp-string employment-model :employment-model)
        :trust-profile (normalize-rgp-string trust-profile :trust-profile)
        :visibility-profile (normalize-rgp-string visibility-profile :visibility-profile)
        :billing-profile (normalize-rgp-string billing-profile :billing-profile)
        :accepted-policy-profiles (normalize-rgp-string-list accepted-policy-profiles
                                                             :accepted-policy-profiles)))

(defun configure-environment-rgp-node-profile (session &key rgp-agent-id
                                                    operator-id
                                                    employment-model
                                                    trust-profile
                                                    visibility-profile
                                                    billing-profile
                                                    accepted-policy-profiles
                                                    environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (existing (environment-rgp-node-profile active-environment))
         (profile (canonical-rgp-node-profile
                   :rgp-agent-id (or rgp-agent-id (getf existing :rgp-agent-id))
                   :operator-id (or operator-id (getf existing :operator-id))
                   :employment-model (or employment-model (getf existing :employment-model))
                   :trust-profile (or trust-profile (getf existing :trust-profile))
                   :visibility-profile (or visibility-profile (getf existing :visibility-profile))
                   :billing-profile (or billing-profile (getf existing :billing-profile))
                   :accepted-policy-profiles (or accepted-policy-profiles
                                                 (getf existing :accepted-policy-profiles)))))
    (set-environment-metadata-value active-environment +rgp-node-profile-key+ profile)
    profile))

(defun canonical-rgp-local-assignment (&key assignment-id
                                            rgp-work-id
                                            operator-model
                                            compensation-profile
                                            evidence-profile
                                            acceptance-state
                                            billing-state
                                            visibility-profile
                                            linked-local-work-item-ids
                                            linked-thread-id
                                            linked-incident-ids
                                            published-at
                                            created-at
                                            updated-at)
  (unless assignment-id
    (error "RGP local assignment requires :ASSIGNMENT-ID"))
  (list :assignment-id (normalize-rgp-string assignment-id :assignment-id)
        :rgp-work-id (normalize-rgp-string rgp-work-id :rgp-work-id)
        :operator-model (normalize-rgp-string operator-model :operator-model)
        :compensation-profile (normalize-rgp-string compensation-profile :compensation-profile)
        :evidence-profile (normalize-rgp-string evidence-profile :evidence-profile)
        :acceptance-state (normalize-rgp-string acceptance-state :acceptance-state)
        :billing-state (normalize-rgp-string billing-state :billing-state)
        :visibility-profile (normalize-rgp-string visibility-profile :visibility-profile)
        :linked-local-work-item-ids (normalize-rgp-string-list linked-local-work-item-ids
                                                               :linked-local-work-item-ids)
        :linked-thread-id (normalize-rgp-string linked-thread-id :linked-thread-id)
        :linked-incident-ids (normalize-rgp-string-list linked-incident-ids
                                                        :linked-incident-ids)
        :published-at published-at
        :created-at created-at
        :updated-at updated-at))

(defun upsert-environment-rgp-local-assignment (session &key assignment-id
                                                     rgp-work-id
                                                     operator-model
                                                     compensation-profile
                                                     evidence-profile
                                                     acceptance-state
                                                     billing-state
                                                     visibility-profile
                                                     linked-local-work-item-ids
                                                     linked-thread-id
                                                     linked-incident-ids
                                                     published-at
                                                     environment)
  (let* ((timestamp (get-universal-time))
         (active-environment (ensure-rgp-bound-environment session environment))
         (existing-records (environment-rgp-local-assignments active-environment))
         (existing (find assignment-id existing-records
                         :key (lambda (record) (getf record :assignment-id))
                         :test #'string=))
         (record (canonical-rgp-local-assignment
                  :assignment-id assignment-id
                  :rgp-work-id (or rgp-work-id (getf existing :rgp-work-id))
                  :operator-model (or operator-model (getf existing :operator-model))
                  :compensation-profile (or compensation-profile
                                            (getf existing :compensation-profile))
                  :evidence-profile (or evidence-profile (getf existing :evidence-profile))
                  :acceptance-state (or acceptance-state (getf existing :acceptance-state))
                  :billing-state (or billing-state (getf existing :billing-state))
                  :visibility-profile (or visibility-profile (getf existing :visibility-profile))
                  :linked-local-work-item-ids (or linked-local-work-item-ids
                                                  (getf existing :linked-local-work-item-ids))
                  :linked-thread-id (or linked-thread-id (getf existing :linked-thread-id))
                  :linked-incident-ids (or linked-incident-ids
                                           (getf existing :linked-incident-ids))
                  :published-at (or published-at (getf existing :published-at))
                  :created-at (or (getf existing :created-at) timestamp)
                  :updated-at timestamp)))
    (set-environment-metadata-value
     active-environment
     +rgp-assignments-key+
     (cons record
           (remove assignment-id existing-records
                   :key (lambda (entry) (getf entry :assignment-id))
                   :test #'string=)))
    record))

(defun environment-rgp-local-assignment-by-id (assignment-id &optional environment)
  (find assignment-id
        (environment-rgp-local-assignments environment)
        :key (lambda (record) (getf record :assignment-id))
        :test #'string=))

(defun rgp-evidence-profile-scope (evidence-profile)
  (let ((profile (normalize-rgp-string evidence-profile :evidence-profile)))
    (cond
      ((or (null profile) (string= profile "minimal"))
       '(:status))
      ((string= profile "standard")
       '(:status :artifacts :checkpoints :validations))
      ((string= profile "high-assurance")
       '(:status :artifacts :checkpoints :validations :workflow-evidence :incidents :usage))
      (t
       '(:status :artifacts :checkpoints :validations)))))

(defun rgp-linked-work-items (session assignment-record)
  (let ((ids (or (getf assignment-record :linked-local-work-item-ids) '())))
    (remove nil
            (mapcar (lambda (work-item-id)
                      (find-work-item session work-item-id))
                    ids))))

(defun rgp-assignment-evidence-summary (session assignment-record &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (profile (or (getf assignment-record :evidence-profile) "minimal"))
         (scope (rgp-evidence-profile-scope profile))
         (work-items (rgp-linked-work-items session assignment-record))
         (artifacts (if (getf assignment-record :linked-thread-id)
                        (environment-list-thread-artifact-records active-environment
                                                                 (getf assignment-record :linked-thread-id))
                        '()))
         (checkpoint-count (reduce #'+ work-items
                                   :key (lambda (work-item)
                                          (length (work-item-checkpoints work-item)))
                                   :initial-value 0))
         (workflow-evidence-count (reduce #'+ work-items
                                          :key (lambda (work-item)
                                                 (let ((record (work-item-workflow-record session work-item)))
                                                   (if record
                                                       (length (workflow-record-evidence record))
                                                       0)))
                                          :initial-value 0))
         (live-validation-count (count-if #'identity work-items
                                          :key #'work-item-live-validation-result))
         (cold-validation-count (count-if #'identity work-items
                                          :key #'work-item-cold-validation-result))
         (incident-count (length (or (getf assignment-record :linked-incident-ids) '())))
         (usage (environment-rgp-usage-telemetry active-environment))
         (readiness (cond
                      ((string= profile "minimal") "status-ready")
                      ((and (> checkpoint-count 0)
                            (> (+ live-validation-count cold-validation-count) 0))
                       "evidence-ready")
                      ((> (length artifacts) 0) "artifact-backed")
                      (t "needs-more-evidence"))))
    (list :assignment-id (getf assignment-record :assignment-id)
          :evidence-profile profile
          :scope (mapcar #'json-safe-value scope)
          :readiness readiness
          :work-item-count (length work-items)
          :artifact-count (if (member :artifacts scope) (length artifacts) 0)
          :checkpoint-count (if (member :checkpoints scope) checkpoint-count 0)
          :live-validation-count (if (member :validations scope) live-validation-count 0)
          :cold-validation-count (if (member :validations scope) cold-validation-count 0)
          :workflow-evidence-count (if (member :workflow-evidence scope)
                                       workflow-evidence-count
                                       0)
          :incident-count (if (member :incidents scope) incident-count 0)
          :usage-summary (when (member :usage scope)
                           (list :reports-count (getf usage :reports-count)
                                 :total-input-tokens (getf usage :total-input-tokens)
                                 :total-output-tokens (getf usage :total-output-tokens)
                                 :updated-at (getf usage :updated-at))))))

(defun environment-rgp-assignment-evidence-summaries (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (session (environment-session active-environment)))
    (if session
        (mapcar (lambda (record)
                  (rgp-assignment-evidence-summary session record active-environment))
                (environment-rgp-local-assignments active-environment))
        '())))

(defun make-rgp-execution-fact-id ()
  (make-rgp-publication-id "execution-fact"))

(defun canonical-rgp-execution-fact (&key id
                                          assignment-id
                                          fact-kind
                                          status
                                          note
                                          artifact-count
                                          checkpoint-count
                                          validation-count
                                          created-at
                                          updated-at)
  (unless assignment-id
    (error "RGP execution facts require :ASSIGNMENT-ID"))
  (list :id (or (normalize-rgp-string id :execution-fact-id)
                (make-rgp-execution-fact-id))
        :assignment-id (normalize-rgp-string assignment-id :assignment-id)
        :fact-kind (normalize-rgp-string fact-kind :fact-kind)
        :status (normalize-rgp-string status :status)
        :note (normalize-rgp-string note :note)
        :artifact-count (or artifact-count 0)
        :checkpoint-count (or checkpoint-count 0)
        :validation-count (or validation-count 0)
        :created-at created-at
        :updated-at updated-at))

(defun make-rgp-billing-milestone-id ()
  (make-rgp-publication-id "billing-milestone"))

(defun canonical-rgp-billing-milestone (&key id
                                             assignment-id
                                             milestone-kind
                                             status
                                             note
                                             created-at
                                             updated-at)
  (unless assignment-id
    (error "RGP billing milestones require :ASSIGNMENT-ID"))
  (list :id (or (normalize-rgp-string id :billing-milestone-id)
                (make-rgp-billing-milestone-id))
        :assignment-id (normalize-rgp-string assignment-id :assignment-id)
        :milestone-kind (normalize-rgp-string milestone-kind :milestone-kind)
        :status (normalize-rgp-string status :status)
        :note (normalize-rgp-string note :note)
        :created-at created-at
        :updated-at updated-at))

(defun rgp-assignment-publication-evidence-payload (session assignment-record &optional environment)
  (let* ((evidence (rgp-assignment-evidence-summary session assignment-record environment))
         (scope (or (getf evidence :scope) '())))
    (append (list :readiness (getf evidence :readiness)
                  :evidence-profile (getf evidence :evidence-profile))
            (when (member "artifacts" scope :test #'string=)
              (list :artifact-count (getf evidence :artifact-count)))
            (when (member "checkpoints" scope :test #'string=)
              (list :checkpoint-count (getf evidence :checkpoint-count)))
            (when (member "validations" scope :test #'string=)
              (list :validation-count (+ (getf evidence :live-validation-count)
                                         (getf evidence :cold-validation-count))))
            (when (member "workflow-evidence" scope :test #'string=)
              (list :workflow-evidence-count (getf evidence :workflow-evidence-count)))
            (when (member "incidents" scope :test #'string=)
              (list :incident-count (getf evidence :incident-count)))
            (when (member "usage" scope :test #'string=)
              (list :usage-summary (getf evidence :usage-summary))))))

(defun record-environment-rgp-execution-fact (session &key assignment-id
                                                   fact-kind
                                                   status
                                                   note
                                                   artifact-count
                                                   checkpoint-count
                                                   validation-count
                                                   environment)
  (let* ((timestamp (get-universal-time))
         (active-environment (ensure-rgp-bound-environment session environment))
         (assignment-record (environment-rgp-local-assignment-by-id assignment-id active-environment)))
    (unless assignment-record
      (error "Unknown RGP assignment ~A" assignment-id))
    (let* ((fact (canonical-rgp-execution-fact
                  :assignment-id assignment-id
                  :fact-kind fact-kind
                  :status status
                  :note note
                  :artifact-count artifact-count
                  :checkpoint-count checkpoint-count
                  :validation-count validation-count
                  :created-at timestamp
                  :updated-at timestamp))
           (facts (environment-rgp-execution-facts active-environment))
           (evidence-payload (rgp-assignment-publication-evidence-payload
                              session
                              assignment-record
                              active-environment))
           (scope (or (getf (rgp-assignment-evidence-summary session
                                                             assignment-record
                                                             active-environment)
                            :scope)
                      '()))
           (publications
             (remove nil
                     (list
                      (enqueue-environment-rgp-publication
                       session
                       :topic "execution.fact_reported"
                       :assignment-id assignment-id
                       :payload (list :assignment-id assignment-id
                                      :fact-id (getf fact :id)
                                      :fact-kind (getf fact :fact-kind)
                                      :status (getf fact :status)
                                      :note (getf fact :note)
                                      :artifact-count (and (member "artifacts" scope :test #'string=)
                                                           (or artifact-count 0))
                                      :checkpoint-count (and (member "checkpoints" scope :test #'string=)
                                                             (or checkpoint-count 0))
                                      :validation-count (and (member "validations" scope :test #'string=)
                                                             (or validation-count 0))
                                      :evidence evidence-payload)
                       :environment active-environment)
                      (when (and (> (or artifact-count 0) 0)
                                 (member "artifacts" scope :test #'string=))
                        (enqueue-environment-rgp-publication
                         session
                         :topic "artifact.reported"
                         :assignment-id assignment-id
                         :payload (list :assignment-id assignment-id
                                        :fact-id (getf fact :id)
                                        :artifact-count (or artifact-count 0)
                                        :evidence evidence-payload)
                         :environment active-environment))
                      (when (and (> (or checkpoint-count 0) 0)
                                 (member "checkpoints" scope :test #'string=))
                        (enqueue-environment-rgp-publication
                         session
                         :topic "checkpoint.reported"
                         :assignment-id assignment-id
                         :payload (list :assignment-id assignment-id
                                        :fact-id (getf fact :id)
                                        :checkpoint-count (or checkpoint-count 0)
                                        :evidence evidence-payload)
                         :environment active-environment))
                      (when (and (> (or validation-count 0) 0)
                                 (member "validations" scope :test #'string=))
                        (enqueue-environment-rgp-publication
                         session
                         :topic "validation.reported"
                         :assignment-id assignment-id
                         :payload (list :assignment-id assignment-id
                                        :fact-id (getf fact :id)
                                        :validation-count (or validation-count 0)
                                        :evidence evidence-payload)
                         :environment active-environment))))))
      (set-environment-metadata-value active-environment
                                      +rgp-execution-facts-key+
                                      (append facts (list fact)))
      (values fact publications))))

(defun record-environment-rgp-billing-milestone (session &key assignment-id
                                                      milestone-kind
                                                      status
                                                      note
                                                      environment)
  (let* ((timestamp (get-universal-time))
         (active-environment (ensure-rgp-bound-environment session environment))
         (assignment-record (environment-rgp-local-assignment-by-id assignment-id active-environment)))
    (unless assignment-record
      (error "Unknown RGP assignment ~A" assignment-id))
    (let* ((milestone (canonical-rgp-billing-milestone
                       :assignment-id assignment-id
                       :milestone-kind milestone-kind
                       :status status
                       :note note
                       :created-at timestamp
                       :updated-at timestamp))
           (milestones (environment-rgp-billing-milestones active-environment))
           (publication
             (enqueue-environment-rgp-publication
              session
              :topic "billing.milestone_reached"
              :assignment-id assignment-id
              :payload (list :assignment-id assignment-id
                             :milestone-id (getf milestone :id)
                             :milestone-kind (getf milestone :milestone-kind)
                             :status (getf milestone :status)
                             :note (getf milestone :note)
                             :compensation-profile (getf assignment-record :compensation-profile)
                             :billing-state (getf assignment-record :billing-state))
              :environment active-environment)))
      (set-environment-metadata-value active-environment
                                      +rgp-billing-milestones-key+
                                      (append milestones (list milestone)))
      (values milestone
              (remove nil
                      (list publication
                            (when (string= (getf milestone :milestone-kind)
                                           "deliverable-submitted")
                              (enqueue-environment-rgp-publication
                               session
                               :topic "deliverable.submitted"
                               :assignment-id assignment-id
                               :payload (list :assignment-id assignment-id
                                              :milestone-id (getf milestone :id)
                                              :note (getf milestone :note)
                                              :compensation-profile
                                              (getf assignment-record :compensation-profile))
                               :environment active-environment))
                            (when (string= (getf milestone :milestone-kind)
                                           "acceptance-requested")
                              (enqueue-environment-rgp-publication
                               session
                               :topic "acceptance.requested"
                               :assignment-id assignment-id
                               :payload (list :assignment-id assignment-id
                                              :milestone-id (getf milestone :id)
                                              :note (getf milestone :note)
                                              :payment-gate "deliverable_acceptance")
                               :environment active-environment))
                            (when (string= (getf milestone :milestone-kind)
                                           "payment-authorized")
                              (enqueue-environment-rgp-publication
                               session
                               :topic "payment.authorized"
                               :assignment-id assignment-id
                               :payload (list :assignment-id assignment-id
                                              :milestone-id (getf milestone :id)
                                              :note (getf milestone :note)
                                              :compensation-profile
                                              (getf assignment-record :compensation-profile))
                               :environment active-environment))))))))

(defun rgp-assignment-required-policy-profiles (assignment-record)
  (let ((evidence-profile (or (getf assignment-record :evidence-profile) "minimal")))
    (cond
      ((string= evidence-profile "high-assurance")
       '("high-assurance" "artifact-validation"))
      ((string= evidence-profile "standard")
       '("standard-evidence"))
      (t
       '()))))

(defun rgp-assignment-acceptance-mode (node-profile assignment-record)
  (let ((node-employment (or (getf node-profile :employment-model) "contractor"))
        (operator-model (or (getf assignment-record :operator-model) "contractor"))
        (evidence-profile (or (getf assignment-record :evidence-profile) "minimal")))
    (if (and (string= node-employment "employee")
             (string= operator-model "employee")
             (not (string= evidence-profile "high-assurance")))
        "implicit"
        "explicit")))

(defun rgp-assignment-acceptance-posture (assignment-record &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (node-profile (or (environment-rgp-node-profile active-environment) '()))
         (required-policies (rgp-assignment-required-policy-profiles assignment-record))
         (accepted-policies (or (getf node-profile :accepted-policy-profiles) '()))
         (missing-policies (remove-if (lambda (policy)
                                        (member policy accepted-policies :test #'string=))
                                      required-policies))
         (decision-mode (rgp-assignment-acceptance-mode node-profile assignment-record))
         (acceptance-state (or (getf assignment-record :acceptance-state) "pending"))
         (operator-model (or (getf assignment-record :operator-model) "contractor"))
         (policy-satisfied-p (null missing-policies))
         (ready-p (and policy-satisfied-p
                       (or (not (string= decision-mode "explicit"))
                           (member acceptance-state
                                   '("accepted" "rejected" "clarification-requested")
                                   :test #'string=))))
         (allowed-actions (cond
                            ((not policy-satisfied-p)
                             '("request-clarification"))
                            ((member acceptance-state
                                     '("accepted" "rejected" "clarification-requested")
                                     :test #'string=)
                             '("no-op"))
                            ((string= decision-mode "implicit")
                             '("accept"))
                            (t
                             '("accept" "reject" "request-clarification"))))
         (readiness (cond
                      ((not policy-satisfied-p) "policy-blocked")
                      ((and (string= decision-mode "implicit")
                            (string= acceptance-state "pending"))
                       "auto-accept-ready")
                      ((string= acceptance-state "accepted") "accepted")
                      ((string= acceptance-state "rejected") "rejected")
                      ((string= acceptance-state "clarification-requested")
                       "awaiting-clarification")
                      (t "decision-required"))))
    (list :assignment-id (getf assignment-record :assignment-id)
          :operator-model operator-model
          :decision-mode decision-mode
          :acceptance-state acceptance-state
          :required-policy-profiles required-policies
          :accepted-policy-profiles accepted-policies
          :missing-policy-profiles missing-policies
          :policy-satisfied-p policy-satisfied-p
          :ready-p ready-p
          :allowed-actions allowed-actions
          :readiness readiness)))

(defun environment-rgp-assignment-acceptance-postures (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (mapcar (lambda (record)
              (rgp-assignment-acceptance-posture record active-environment))
            (environment-rgp-local-assignments active-environment))))

(defun environment-rgp-enriched-assignment-summaries (session &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (mapcar (lambda (assignment)
              (let ((posture (rgp-assignment-acceptance-posture assignment active-environment)))
                (append assignment
                        (list :acceptance-posture posture
                              :decision-terms (rgp-assignment-decision-terms assignment posture)
                              :lifecycle (rgp-assignment-lifecycle-summary
                                          assignment
                                          posture
                                          active-environment)
                              :evidence-summary (rgp-assignment-evidence-summary
                                                 session
                                                 assignment
                                                 active-environment)))))
            (environment-rgp-local-assignments active-environment))))

(defun environment-rgp-publication-posture (&optional environment)
  (let* ((backlog (environment-rgp-publication-backlog environment))
         (execution-count (count-if (lambda (entry)
                                      (member (getf entry :topic)
                                              '("execution.fact_reported"
                                                "artifact.reported"
                                                "checkpoint.reported"
                                                "validation.reported")
                                              :test #'string=))
                                    backlog))
         (usage-count (count "usage.reported" backlog
                             :key (lambda (entry) (getf entry :topic))
                             :test #'string=))
         (billing-count (count-if (lambda (entry)
                                    (member (getf entry :topic)
                                            '("billing.milestone_reached"
                                              "deliverable.submitted"
                                              "acceptance.requested"
                                              "payment.authorized")
                                            :test #'string=))
                                  backlog))
         (payment-gated-count (count-if (lambda (entry)
                                          (member (getf entry :topic)
                                                  '("deliverable.submitted"
                                                    "acceptance.requested")
                                                  :test #'string=))
                                        backlog))
         (assignment-count (count-if (lambda (entry)
                                       (member (getf entry :topic)
                                               '("assignment.accepted"
                                                 "assignment.rejected"
                                                 "assignment.clarification_requested")
                                               :test #'string=))
                                     backlog))
         (pending-count (count "pending" backlog :key (lambda (entry) (getf entry :state))
                               :test #'string=))
         (retrying-count (count "retrying" backlog :key (lambda (entry) (getf entry :state))
                                :test #'string=))
         (published-count (count "published" backlog :key (lambda (entry) (getf entry :state))
                                 :test #'string=))
         (failed-count (count "failed" backlog :key (lambda (entry) (getf entry :state))
                              :test #'string=))
         (attention-required-p (> failed-count 0))
         (retry-required-p (> (+ failed-count retrying-count) 0))
         (payment-gated-p (> payment-gated-count 0))
         (attention-class (cond
                            ((> failed-count 0) "publication-failure")
                            ((> retrying-count 0) "retry-required")
                            (payment-gated-p "payment-gated")
                            ((> pending-count 0) "publishing")
                            (t "idle")))
         (max-attempt-count (reduce #'max backlog
                                    :key (lambda (entry) (or (getf entry :attempt-count) 0))
                                    :initial-value 0)))
    (list :entry-count (length backlog)
          :pending-count pending-count
          :retrying-count retrying-count
          :published-count published-count
          :failed-count failed-count
          :execution-count execution-count
          :usage-count usage-count
          :billing-count billing-count
          :payment-gated-count payment-gated-count
          :assignment-count assignment-count
          :max-attempt-count max-attempt-count
          :attention-required-p attention-required-p
          :retry-required-p retry-required-p
          :payment-gated-p payment-gated-p
          :attention-class attention-class
          :operator-attention (list :class attention-class
                                    :retry-required-p retry-required-p
                                    :payment-gated-p payment-gated-p
                                    :failed-count failed-count
                                    :retrying-count retrying-count
                                    :payment-gated-count payment-gated-count)
          :readiness (cond
                       (attention-required-p "attention-required")
                       ((> retrying-count 0) "retrying")
                       ((> pending-count 0) "publishing")
                       (t "idle")))))

(defun environment-rgp-business-posture (&optional environment)
  (let* ((milestones (environment-rgp-billing-milestones environment))
         (acceptance-requested-count
           (count "acceptance-requested" milestones
                  :key (lambda (entry) (getf entry :milestone-kind))
                  :test #'string=))
         (payment-authorized-count
           (count "payment-authorized" milestones
                  :key (lambda (entry) (getf entry :milestone-kind))
                  :test #'string=))
         (deliverable-submitted-count
           (count "deliverable-submitted" milestones
                  :key (lambda (entry) (getf entry :milestone-kind))
                  :test #'string=))
         (payment-gated-count (+ acceptance-requested-count deliverable-submitted-count))
         (current-gate (cond
                         ((> payment-authorized-count 0) "payment-authorized")
                         ((> acceptance-requested-count 0) "awaiting-acceptance")
                         ((> deliverable-submitted-count 0) "deliverable-submitted")
                         (t "none"))))
    (list :billing-milestone-count (length milestones)
          :deliverable-submitted-count deliverable-submitted-count
          :acceptance-requested-count acceptance-requested-count
          :payment-authorized-count payment-authorized-count
          :payment-gated-count payment-gated-count
          :current-gate current-gate)))

(defun rgp-assignment-workspace-item (assignment)
  (let ((posture (getf assignment :acceptance-posture))
        (terms (getf assignment :decision-terms))
        (lifecycle (getf assignment :lifecycle))
        (evidence (getf assignment :evidence-summary)))
    (list :assignment-id (getf assignment :assignment-id)
          :rgp-work-id (getf assignment :rgp-work-id)
          :operator-model (getf assignment :operator-model)
          :compensation-profile (getf assignment :compensation-profile)
          :evidence-profile (getf assignment :evidence-profile)
          :visibility-profile (getf assignment :visibility-profile)
          :acceptance-readiness (getf posture :readiness)
          :decision-mode (getf terms :decision-mode)
          :allowed-actions (getf terms :allowed-actions)
          :lifecycle-stage (getf lifecycle :lifecycle-stage)
          :evidence-readiness (getf evidence :readiness)
          :linked-thread-id (getf assignment :linked-thread-id))))

(defun environment-rgp-assignment-terms-summary (session &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (assignments (environment-rgp-enriched-assignment-summaries session active-environment))
         (items (mapcar #'rgp-assignment-workspace-item assignments)))
    (list :assignment-count (length items)
          :decision-required-count (count "decision-required" items
                                          :key (lambda (item) (getf item :acceptance-readiness))
                                          :test #'string=)
          :policy-blocked-count (count "policy-blocked" items
                                       :key (lambda (item) (getf item :acceptance-readiness))
                                       :test #'string=)
          :accepted-count (count "accepted" items
                                 :key (lambda (item) (getf item :acceptance-readiness))
                                 :test #'string=)
          :clarification-count (count "awaiting-clarification" items
                                      :key (lambda (item) (getf item :acceptance-readiness))
                                      :test #'string=)
          :items items)))

(defun environment-rgp-evidence-posture-summary (session &optional environment)
  (declare (ignore session))
  (let* ((active-environment (ensure-environment environment))
         (entries (environment-rgp-assignment-evidence-summaries active-environment)))
    (list :assignment-count (length entries)
          :high-assurance-count (count "high-assurance" entries
                                       :key (lambda (entry) (getf entry :evidence-profile))
                                       :test #'string=)
          :standard-count (count "standard" entries
                                 :key (lambda (entry) (getf entry :evidence-profile))
                                 :test #'string=)
          :minimal-count (count "minimal" entries
                                :key (lambda (entry) (getf entry :evidence-profile))
                                :test #'string=)
          :needs-more-evidence-count (count "needs-more-evidence" entries
                                           :key (lambda (entry) (getf entry :readiness))
                                           :test #'string=)
          :artifact-backed-count (count "artifact-backed" entries
                                       :key (lambda (entry) (getf entry :readiness))
                                       :test #'string=)
          :evidence-ready-count (count "evidence-ready" entries
                                       :key (lambda (entry) (getf entry :readiness))
                                       :test #'string=)
          :items (mapcar (lambda (entry)
                           (list :assignment-id (getf entry :assignment-id)
                                 :evidence-profile (getf entry :evidence-profile)
                                 :readiness (getf entry :readiness)
                                 :artifact-count (getf entry :artifact-count)
                                 :checkpoint-count (getf entry :checkpoint-count)
                                 :incident-count (getf entry :incident-count)))
                         entries))))

(defun environment-rgp-usage-summary (&optional environment)
  (let* ((usage (environment-rgp-usage-telemetry environment))
         (last-report (getf usage :last-report)))
    (list :provider-count (getf usage :provider-count)
          :total-input-tokens (getf usage :total-input-tokens)
          :total-output-tokens (getf usage :total-output-tokens)
          :total-cached-tokens (getf usage :total-cached-tokens)
          :execution-seconds (getf usage :execution-seconds)
          :blocked-seconds (getf usage :blocked-seconds)
          :tool-invocations (getf usage :tool-invocations)
          :artifact-count (getf usage :artifact-count)
          :validation-effort (getf usage :validation-effort)
          :reports-count (getf usage :reports-count)
          :updated-at (getf usage :updated-at)
          :last-provider (getf last-report :provider)
          :last-model (getf last-report :model))))

(defun rgp-workspace-attention-item-priority (item)
  (or (getf item :priority-rank) 99))

(defun environment-rgp-workspace-attention-queue (assignment-terms publication-posture business-posture)
  (let ((items '()))
    (dolist (assignment (getf assignment-terms :items))
      (let ((readiness (getf assignment :acceptance-readiness)))
        (cond
          ((string= readiness "policy-blocked")
           (push (list :kind "assignment-policy"
                       :priority-rank 0
                       :assignment-id (getf assignment :assignment-id)
                       :title "Assignment blocked by node policy"
                       :readiness readiness
                       :allowed-actions (getf assignment :allowed-actions))
                 items))
          ((string= readiness "decision-required")
           (push (list :kind "assignment-decision"
                       :priority-rank 1
                       :assignment-id (getf assignment :assignment-id)
                       :title "Assignment awaits operator decision"
                       :readiness readiness
                       :allowed-actions (getf assignment :allowed-actions))
                 items))
          ((string= readiness "awaiting-clarification")
           (push (list :kind "assignment-clarification"
                       :priority-rank 2
                       :assignment-id (getf assignment :assignment-id)
                       :title "Assignment is waiting for clarification"
                       :readiness readiness
                       :allowed-actions (getf assignment :allowed-actions))
                 items)))))
    (let ((attention-class (getf (getf publication-posture :operator-attention) :class)))
      (unless (string= attention-class "idle")
        (push (list :kind "publication-backlog"
                    :priority-rank (if (member attention-class '("publication-failure" "retry-required")
                                                    :test #'string=)
                                       0
                                       3)
                    :title "Publication backlog requires attention"
                    :readiness (getf publication-posture :readiness)
                    :attention-class attention-class
                    :failed-count (getf publication-posture :failed-count)
                    :retrying-count (getf publication-posture :retrying-count)
                    :payment-gated-count (getf publication-posture :payment-gated-count))
              items)))
    (unless (string= (getf business-posture :current-gate) "none")
      (push (list :kind "business-gate"
                  :priority-rank 3
                  :title "Business completion gate remains active"
                  :current-gate (getf business-posture :current-gate)
                  :payment-gated-count (getf business-posture :payment-gated-count))
            items))
    (let ((sorted (sort items #'< :key #'rgp-workspace-attention-item-priority)))
      (list :count (length sorted)
            :top-item (first sorted)
            :items sorted))))

(defun environment-rgp-workspace-summary (session &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (node-profile (environment-rgp-node-profile active-environment))
         (runtime (environment-rgp-runtime-summary active-environment))
         (assignment-terms (environment-rgp-assignment-terms-summary session active-environment))
         (evidence-posture (environment-rgp-evidence-posture-summary session active-environment))
         (usage-summary (environment-rgp-usage-summary active-environment))
         (publication-posture (environment-rgp-publication-posture active-environment))
         (business-posture (environment-rgp-business-posture active-environment))
         (execution-surfaces (service-response-data
                              (query-execution-surfaces-service session
                                                                :environment active-environment)))
         (attention-queue (environment-rgp-workspace-attention-queue
                           assignment-terms
                           publication-posture
                           business-posture)))
    (list :node-mode (list :rgp-agent-id (getf node-profile :rgp-agent-id)
                           :operator-id (getf node-profile :operator-id)
                           :employment-model (getf node-profile :employment-model)
                           :trust-profile (getf node-profile :trust-profile)
                           :visibility-profile (getf node-profile :visibility-profile)
                           :billing-profile (getf node-profile :billing-profile)
                           :accepted-policy-profiles (getf node-profile :accepted-policy-profiles)
                           :accepted-policy-profile-count (length (getf node-profile :accepted-policy-profiles)))
          :runtime-context (list :environment-id (getf runtime :environment-id)
                                 :session-id (getf runtime :session-id)
                                 :active-thread-id (getf runtime :active-thread-id)
                                 :thread-count (getf runtime :thread-count)
                                 :work-item-count (getf runtime :work-item-count)
                                 :incident-count (getf runtime :incident-count))
          :assignment-terms assignment-terms
          :execution-surfaces (compact-execution-surfaces-data execution-surfaces)
          :evidence-posture evidence-posture
          :usage-summary usage-summary
          :attention-queue attention-queue
          :publication-summary (list :readiness (getf publication-posture :readiness)
                                     :attention-class (getf (getf publication-posture :operator-attention) :class)
                                     :entry-count (getf publication-posture :entry-count)
                                     :retrying-count (getf publication-posture :retrying-count)
                                     :failed-count (getf publication-posture :failed-count)
                                     :payment-gated-count (getf publication-posture :payment-gated-count))
          :business-summary (list :current-gate (getf business-posture :current-gate)
                                  :payment-gated-count (getf business-posture :payment-gated-count)
                                  :payment-authorized-count (getf business-posture :payment-authorized-count)))))

(defun rgp-assignment-materialization-kind (posture)
  (let ((readiness (getf posture :readiness)))
    (cond
      ((string= readiness "policy-blocked") "policy-review")
      ((string= readiness "decision-required") "assignment-decision")
      ((string= readiness "awaiting-clarification") "awaiting-clarification")
      ((string= readiness "accepted") "execution-ready")
      ((string= readiness "auto-accept-ready") "execution-ready")
      ((string= readiness "rejected") "assignment-rejected")
      (t "assignment-received"))))

(defun rgp-assignment-control-payloads (work-item assignment-record posture)
  (let* ((assignment-id (getf assignment-record :assignment-id))
         (projection-kind (rgp-assignment-materialization-kind posture))
         (allowed-actions (getf posture :allowed-actions)))
    (values
     projection-kind
     (cond
       ((string= projection-kind "policy-review")
        (list :type :assignment-policy-review
              :assignment-id assignment-id
              :missing-policy-profiles (getf posture :missing-policy-profiles)
              :suggested-step :align-node-policy-or-request-clarification))
       ((string= projection-kind "assignment-decision")
        (list :type :assignment-decision
              :assignment-id assignment-id
              :allowed-actions allowed-actions
              :suggested-step :review-assignment-terms))
       ((string= projection-kind "awaiting-clarification")
        (list :type :await-clarification
              :assignment-id assignment-id
              :suggested-step :wait-for-rgp-response))
       ((string= projection-kind "execution-ready")
        (list :type :execute-assignment
              :assignment-id assignment-id
              :suggested-step :start-work-item))
       ((string= projection-kind "assignment-rejected")
        (list :type :assignment-rejected
              :assignment-id assignment-id
              :suggested-step :await-reassignment))
       (t
        (list :type :inspect-assignment
              :assignment-id assignment-id
              :suggested-step :review-assignment)))
     (cond
       ((member projection-kind '("policy-review" "assignment-decision" "awaiting-clarification")
                :test #'string=)
        (list :resume-command :review-rgp-assignment
              :assignment-id assignment-id
              :allowed-actions allowed-actions
              :missing-policy-profiles (getf posture :missing-policy-profiles)
              :decision-mode (getf posture :decision-mode)))
       ((string= projection-kind "execution-ready")
        (list :resume-command :start-work-item
              :assignment-id assignment-id
              :checkpoint-id (latest-work-item-checkpoint-id work-item)
              :pending (work-item-pending-validation-kinds work-item)))
       (t
        (list :resume-command :review-rgp-assignment
              :assignment-id assignment-id))))))

(defun rgp-assignment-lifecycle-stage (assignment-record posture)
  (let ((acceptance-state (getf assignment-record :acceptance-state))
        (projection-kind (rgp-assignment-materialization-kind posture)))
    (cond
      ((string= acceptance-state "rejected") "closed-rejected")
      ((string= acceptance-state "clarification-requested") "waiting-for-clarification")
      ((string= projection-kind "policy-review") "blocked-by-policy")
      ((string= projection-kind "assignment-decision") "awaiting-local-decision")
      ((string= projection-kind "execution-ready") "ready-for-local-execution")
      (t "received"))))

(defun rgp-assignment-lifecycle-summary (assignment-record posture &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (publication-posture (environment-rgp-publication-posture active-environment)))
    (list :assignment-id (getf assignment-record :assignment-id)
          :acceptance-state (getf assignment-record :acceptance-state)
          :billing-state (getf assignment-record :billing-state)
          :projection-kind (rgp-assignment-materialization-kind posture)
          :lifecycle-stage (rgp-assignment-lifecycle-stage assignment-record posture)
          :decision-mode (getf posture :decision-mode)
          :readiness (getf posture :readiness)
          :publication-readiness (getf publication-posture :readiness)
          :missing-policy-profiles (getf posture :missing-policy-profiles))))

(defun rgp-assignment-decision-terms (assignment-record posture)
  (list :assignment-id (getf assignment-record :assignment-id)
        :operator-model (getf assignment-record :operator-model)
        :compensation-profile (getf assignment-record :compensation-profile)
        :evidence-profile (getf assignment-record :evidence-profile)
        :visibility-profile (getf assignment-record :visibility-profile)
        :decision-mode (getf posture :decision-mode)
        :readiness (getf posture :readiness)
        :allowed-actions (getf posture :allowed-actions)
        :required-policy-profiles (getf posture :required-policy-profiles)
        :missing-policy-profiles (getf posture :missing-policy-profiles)
        :policy-satisfied-p (getf posture :policy-satisfied-p)))

(defun assert-rgp-assignment-action-allowed (assignment-record posture requested-action)
  (let* ((allowed-actions (getf posture :allowed-actions))
         (action-name (normalize-rgp-string requested-action :requested-action)))
    (unless (member action-name allowed-actions :test #'string=)
      (error "RGP assignment ~A does not allow ~A while readiness is ~A"
             (getf assignment-record :assignment-id)
             action-name
             (getf posture :readiness)))))

(defun project-rgp-assignment-materialization (session work-item assignment-record posture)
  (let* ((assignment-id (getf assignment-record :assignment-id))
         (projection-kind nil)
         (next-action nil)
         (resume-payload nil))
    (multiple-value-setq (projection-kind next-action resume-payload)
      (rgp-assignment-control-payloads work-item assignment-record posture))
    (set-work-item-next-action session work-item next-action)
    (set-work-item-resume-payload session work-item resume-payload)
    (append-work-item-workflow-entry
     session
     work-item
     :plan
     :rgp-assignment-materialized
     (list :assignment-id assignment-id
           :projection-kind projection-kind
           :readiness (getf posture :readiness))
     :status (if (string= projection-kind "execution-ready") :resumed :open))
    (let ((payload (list :assignment-id assignment-id
                         :work-item-id (work-item-id work-item)
                         :projection-kind projection-kind
                         :readiness (getf posture :readiness)
                         :workflow-record-id (work-item-workflow-record-ref work-item))))
      (append-session-event session
                            :rgp-assignment-materialized
                            payload
                            :family :governance
                            :entity-id assignment-id
                            :work-item-id (work-item-id work-item)
                            :metadata (list :assignment-id assignment-id
                                            :workflow-record-id (work-item-workflow-record-ref work-item)))
      (append-session-event session
                            (cond
                              ((string= projection-kind "policy-review") :rgp-assignment-policy-blocked)
                              ((string= projection-kind "assignment-decision") :rgp-assignment-awaiting-decision)
                              ((string= projection-kind "awaiting-clarification") :rgp-assignment-awaiting-clarification)
                              ((string= projection-kind "execution-ready") :rgp-assignment-ready-to-execute)
                              ((string= projection-kind "assignment-rejected") :rgp-assignment-rejected)
                              (t :rgp-assignment-received))
                            payload
                            :family :governance
                            :entity-id assignment-id
                            :work-item-id (work-item-id work-item)
                            :metadata (list :assignment-id assignment-id
                                            :workflow-record-id (work-item-workflow-record-ref work-item))))
    (list :assignment-id assignment-id
          :work-item-id (work-item-id work-item)
          :workflow-record-id (work-item-workflow-record-ref work-item)
          :projection-kind projection-kind
          :lifecycle-stage (rgp-assignment-lifecycle-stage assignment-record posture)
          :next-action (work-item-next-action work-item)
          :resume-payload (work-item-resume-payload work-item))))

(defun project-rgp-assignment-decision-transition (session assignment-record posture &optional environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (work-item-id (first (or (getf assignment-record :linked-local-work-item-ids) '())))
         (work-item (and work-item-id (find-work-item session work-item-id)))
         (assignment-id (getf assignment-record :assignment-id))
         (projection-kind (rgp-assignment-materialization-kind posture)))
    (when work-item
      (multiple-value-bind (control-kind next-action resume-payload)
          (rgp-assignment-control-payloads work-item assignment-record posture)
        (declare (ignore control-kind))
        (set-work-item-next-action session work-item next-action)
        (set-work-item-resume-payload session work-item resume-payload)
        (append-work-item-workflow-entry
         session
         work-item
         :operator
         :rgp-assignment-decision-projected
         (list :assignment-id assignment-id
               :acceptance-state (getf assignment-record :acceptance-state)
               :projection-kind projection-kind
               :readiness (getf posture :readiness))
         :status (if (string= projection-kind "execution-ready") :resumed :open))
        (let ((payload (list :assignment-id assignment-id
                             :work-item-id (work-item-id work-item)
                             :acceptance-state (getf assignment-record :acceptance-state)
                             :projection-kind projection-kind
                             :readiness (getf posture :readiness)
                             :workflow-record-id (work-item-workflow-record-ref work-item))))
          (append-session-event session
                                (cond
                                  ((string= (getf assignment-record :acceptance-state) "accepted")
                                   :rgp-assignment-accepted-locally)
                                  ((string= (getf assignment-record :acceptance-state) "rejected")
                                   :rgp-assignment-rejected-locally)
                                  ((string= (getf assignment-record :acceptance-state)
                                            "clarification-requested")
                                   :rgp-assignment-clarification-requested-locally)
                                  (t :rgp-assignment-updated-locally))
                                payload
                                :family :governance
                                :entity-id assignment-id
                                :work-item-id (work-item-id work-item)
                                :metadata (list :assignment-id assignment-id
                                                :workflow-record-id (work-item-workflow-record-ref work-item))))))
    (rgp-assignment-lifecycle-summary assignment-record posture active-environment)))

(defun receive-environment-rgp-assignment (session &key assignment-id
                                                goal
                                                rgp-work-id
                                                operator-model
                                                compensation-profile
                                                evidence-profile
                                                visibility-profile
                                                billing-state
                                                acceptance-state
                                                thread-id
                                                environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (target-thread (or (and thread-id
                                 (find-thread session thread-id))
                            (current-thread session)))
         (existing (environment-rgp-local-assignment-by-id assignment-id active-environment))
         (existing-work-item-id (first (or (getf existing :linked-local-work-item-ids) '())))
         (work-item (or (and existing-work-item-id
                             (find-work-item session existing-work-item-id))
                        (create-work-item session
                                          (or goal
                                              (format nil "RGP assignment ~A" assignment-id))
                                          :transaction-scope :rgp-assignment)))
         (record (upsert-environment-rgp-local-assignment
                  session
                  :assignment-id assignment-id
                  :rgp-work-id rgp-work-id
                  :operator-model operator-model
                  :compensation-profile compensation-profile
                  :evidence-profile evidence-profile
                  :acceptance-state (or acceptance-state
                                        (getf existing :acceptance-state)
                                        :pending)
                  :billing-state billing-state
                  :visibility-profile visibility-profile
                  :linked-local-work-item-ids (list (work-item-id work-item))
                  :linked-thread-id (and target-thread (thread-id target-thread))
                  :linked-incident-ids (or (getf existing :linked-incident-ids) '())
                  :environment active-environment)))
    (append-session-event session
                          :rgp-assignment-received
                          (list :assignment-id assignment-id
                                :rgp-work-id rgp-work-id
                                :operator-model (getf record :operator-model)
                                :work-item-id (work-item-id work-item)
                                :acceptance-state (getf record :acceptance-state))
                          :family :governance
                          :entity-id assignment-id
                          :thread-id (and target-thread (thread-id target-thread))
                          :work-item-id (work-item-id work-item)
                          :metadata (list :assignment-id assignment-id
                                          :rgp-work-id rgp-work-id
                                          :operator-model (getf record :operator-model)))
    (let* ((posture (rgp-assignment-acceptance-posture record active-environment))
           (auto-accepted-publication nil)
           (final-record record)
           (final-posture posture)
           (materialization nil))
      (when (and (string= (getf posture :decision-mode) "implicit")
                 (string= (getf posture :acceptance-state) "pending")
                 (getf posture :policy-satisfied-p))
        (multiple-value-bind (updated publication)
            (transition-environment-rgp-local-assignment session assignment-id :accepted
                                                         :note "Implicit acceptance by node policy posture."
                                                         :environment active-environment)
          (setf final-record updated
                auto-accepted-publication publication
                final-posture (rgp-assignment-acceptance-posture updated active-environment))
          (append-session-event session
                                :rgp-assignment-auto-accepted
                                (list :assignment-id assignment-id
                                      :publication-id (getf publication :id))
                                :family :governance
                                :entity-id assignment-id
                                :work-item-id (work-item-id work-item)
                                :metadata (list :assignment-id assignment-id
                                                :publication-id (getf publication :id)))))
      (setf materialization
            (project-rgp-assignment-materialization session
                                                   work-item
                                                   final-record
                                                   final-posture))
      (list :assignment final-record
            :acceptance-posture final-posture
            :decision-terms (rgp-assignment-decision-terms final-record final-posture)
            :lifecycle (rgp-assignment-lifecycle-summary final-record
                                                         final-posture
                                                         active-environment)
            :evidence-summary (rgp-assignment-evidence-summary session final-record active-environment)
            :work-item (enriched-work-item-service-detail session work-item)
            :materialization materialization
            :auto-accepted-publication auto-accepted-publication))))

(defun transition-environment-rgp-local-assignment (session assignment-id acceptance-state
                                                         &key note environment)
  (let* ((active-environment (ensure-rgp-bound-environment session environment))
         (existing (environment-rgp-local-assignment-by-id assignment-id active-environment)))
    (unless existing
      (error "Unknown RGP assignment ~A" assignment-id))
    (let ((pre-transition-posture (rgp-assignment-acceptance-posture existing active-environment)))
      (assert-rgp-assignment-action-allowed
       existing
       pre-transition-posture
       (ecase acceptance-state
         (:accepted "accept")
         (:rejected "reject")
         (:clarification-requested "request-clarification"))))
    (let* ((updated (upsert-environment-rgp-local-assignment
                     session
                     :assignment-id assignment-id
                     :rgp-work-id (getf existing :rgp-work-id)
                     :operator-model (getf existing :operator-model)
                     :compensation-profile (getf existing :compensation-profile)
                     :evidence-profile (getf existing :evidence-profile)
                     :acceptance-state acceptance-state
                     :billing-state (getf existing :billing-state)
                     :visibility-profile (getf existing :visibility-profile)
                     :linked-local-work-item-ids (getf existing :linked-local-work-item-ids)
                     :linked-thread-id (getf existing :linked-thread-id)
                     :linked-incident-ids (getf existing :linked-incident-ids)
                     :published-at (getf existing :published-at)
                     :environment active-environment))
           (topic (ecase acceptance-state
                    (:accepted "assignment.accepted")
                    (:rejected "assignment.rejected")
                    (:clarification-requested "assignment.clarification_requested")))
           (evidence-summary (rgp-assignment-evidence-summary session updated active-environment))
           (publication (enqueue-environment-rgp-publication
                         session
                         :topic topic
                         :assignment-id assignment-id
                         :payload (list :assignment-id assignment-id
                                        :acceptance-state (json-safe-value acceptance-state)
                                        :note note
                                        :rgp-work-id (getf updated :rgp-work-id)
                                        :operator-model (getf updated :operator-model)
                                        :evidence evidence-summary)
                         :environment active-environment)))
      (values updated
              publication
              (project-rgp-assignment-decision-transition
               session
               updated
               (rgp-assignment-acceptance-posture updated active-environment)
               active-environment)))))

(defun record-environment-rgp-usage-telemetry (session &key provider
                                                    model
                                                    input-tokens
                                                    output-tokens
                                                    cached-tokens
                                                    execution-seconds
                                                    blocked-seconds
                                                    tool-invocations
                                                    artifact-count
                                                    validation-effort
                                                    environment)
  (let* ((timestamp (get-universal-time))
         (active-environment (ensure-rgp-bound-environment session environment))
         (existing (environment-rgp-usage-telemetry active-environment))
         (report (list :provider (normalize-rgp-string provider :provider)
                       :model (normalize-rgp-string model :model)
                       :input-tokens (or input-tokens 0)
                       :output-tokens (or output-tokens 0)
                       :cached-tokens (or cached-tokens 0)
                       :execution-seconds (or execution-seconds 0)
                       :blocked-seconds (or blocked-seconds 0)
                       :tool-invocations (or tool-invocations 0)
                       :artifact-count (or artifact-count 0)
                       :validation-effort (or validation-effort 0)
                       :reported-at timestamp))
         (updated (list :provider-count (+ (if provider 1 0)
                                           (or (getf existing :provider-count) 0))
                        :total-input-tokens (+ (or (getf existing :total-input-tokens) 0)
                                               (or input-tokens 0))
                        :total-output-tokens (+ (or (getf existing :total-output-tokens) 0)
                                                (or output-tokens 0))
                        :total-cached-tokens (+ (or (getf existing :total-cached-tokens) 0)
                                                (or cached-tokens 0))
                        :execution-seconds (+ (or (getf existing :execution-seconds) 0)
                                              (or execution-seconds 0))
                        :blocked-seconds (+ (or (getf existing :blocked-seconds) 0)
                                            (or blocked-seconds 0))
                        :tool-invocations (+ (or (getf existing :tool-invocations) 0)
                                             (or tool-invocations 0))
                        :artifact-count (+ (or (getf existing :artifact-count) 0)
                                           (or artifact-count 0))
                        :validation-effort (+ (or (getf existing :validation-effort) 0)
                                              (or validation-effort 0))
                        :reports-count (+ (or (getf existing :reports-count) 0) 1)
                        :updated-at timestamp
                        :last-report report)))
    (set-environment-metadata-value active-environment +rgp-usage-telemetry-key+ updated)
    (enqueue-environment-rgp-publication
     session
     :topic "usage.reported"
     :payload (list :provider (getf report :provider)
                    :model (getf report :model)
                    :input-tokens (getf report :input-tokens)
                    :output-tokens (getf report :output-tokens)
                    :cached-tokens (getf report :cached-tokens)
                    :execution-seconds (getf report :execution-seconds)
                    :blocked-seconds (getf report :blocked-seconds)
                    :tool-invocations (getf report :tool-invocations)
                    :artifact-count (getf report :artifact-count)
                    :validation-effort (getf report :validation-effort)
                    :reported-at (getf report :reported-at))
     :environment active-environment)
    updated))

(defun rgp-binding-summary (&optional environment)
  (let ((binding (environment-rgp-binding environment)))
    (when binding
      (list :tenant-id (getf binding :tenant-id)
            :request-id (getf binding :request-id)
            :agent-session-id (getf binding :agent-session-id)
            :integration-id (getf binding :integration-id)
            :projection-id (getf binding :projection-id)
            :runtime-subtype (getf binding :runtime-subtype)
            :session-kind (getf binding :session-kind)
            :environment-id (getf binding :environment-id)
            :session-id (getf binding :session-id)
            :bound-at (getf binding :bound-at)
            :updated-at (getf binding :updated-at)))))

(defun bind-environment-to-rgp (session &key tenant-id
                                     request-id
                                     agent-session-id
                                     integration-id
                                     projection-id
                                     rgp-agent-id
                                     operator-id
                                     employment-model
                                     trust-profile
                                     visibility-profile
                                     billing-profile
                                     accepted-policy-profiles
                                     environment)
  (unless (stringp request-id)
    (error "RGP binding requires a string request id"))
  (unless (stringp agent-session-id)
    (error "RGP binding requires a string agent-session id"))
  (when (and tenant-id (not (stringp tenant-id)))
    (error "RGP binding :TENANT-ID must be a string when provided"))
  (when (and integration-id (not (stringp integration-id)))
    (error "RGP binding :INTEGRATION-ID must be a string when provided"))
  (when (and projection-id (not (stringp projection-id)))
    (error "RGP binding :PROJECTION-ID must be a string when provided"))
  (let* ((timestamp (get-universal-time))
         (active-environment (ensure-rgp-bound-environment session environment))
         (existing (environment-rgp-binding active-environment))
         (binding (list :tenant-id tenant-id
                        :request-id request-id
                        :agent-session-id agent-session-id
                        :integration-id integration-id
                        :projection-id projection-id
                        :runtime-subtype +rgp-runtime-subtype+
                        :session-kind +rgp-session-kind+
                        :environment-id (environment-id active-environment)
                        :session-id (agent-session-id session)
                        :bound-at (or (getf existing :bound-at) timestamp)
                        :updated-at timestamp)))
    (setf (environment-metadata active-environment)
          (plist-put (environment-metadata active-environment) :rgp-binding binding))
    (when (or rgp-agent-id
              operator-id
              employment-model
              trust-profile
              visibility-profile
              billing-profile
              accepted-policy-profiles)
      (configure-environment-rgp-node-profile session
                                              :rgp-agent-id rgp-agent-id
                                              :operator-id operator-id
                                              :employment-model employment-model
                                              :trust-profile trust-profile
                                              :visibility-profile visibility-profile
                                              :billing-profile billing-profile
                                              :accepted-policy-profiles accepted-policy-profiles
                                              :environment active-environment))
    binding))

(defun latest-thread-turn-summary (session thread)
  (let ((turn (and thread
                   (car (last (list-thread-turns session (thread-id thread)))))))
    (and turn
         (turn-detail session (turn-id turn)))))

(defun environment-rgp-runtime-summary (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (session (environment-session active-environment))
         (summary (environment-summary active-environment))
         (binding (environment-rgp-binding active-environment))
         (wait-summary (and session (session-wait-summary session)))
         (operator-status (and session (session-operator-status session))))
    (list :runtime-subtype (or (getf binding :runtime-subtype) +rgp-runtime-subtype+)
          :session-kind (or (getf binding :session-kind) +rgp-session-kind+)
          :environment-id (environment-id active-environment)
          :session-id (and session (agent-session-id session))
          :storage-root (environment-storage-root active-environment)
          :active-runtime-id (getf summary :active-runtime-id)
          :active-thread-id (getf summary :active-thread-id)
          :thread-count (getf summary :thread-count)
          :artifact-count (getf summary :artifact-count)
          :work-item-count (getf summary :work-item-count)
          :incident-count (getf summary :incident-count)
          :event-count (getf (getf summary :event-summary) :event-count)
          :wait-summary wait-summary
          :operator-status operator-status
          :supports-approval-actions-p t
          :supports-resume-actions-p t
          :supports-artifact-lineage-p t
          :node-profile (environment-rgp-node-profile active-environment)
          :local-assignment-count (length (environment-rgp-local-assignments active-environment))
          :execution-fact-count (length (environment-rgp-execution-facts active-environment))
          :billing-milestone-count (length (environment-rgp-billing-milestones active-environment))
          :business-posture (environment-rgp-business-posture active-environment)
          :publication-backlog-count (length (environment-rgp-publication-backlog active-environment))
          :assignment-evidence-count (length (environment-rgp-assignment-evidence-summaries
                                              active-environment))
          :assignment-acceptance-count (length (environment-rgp-assignment-acceptance-postures
                                                active-environment))
          :local-assignments (and session
                                  (environment-rgp-enriched-assignment-summaries
                                   session
                                   active-environment))
          :publication-posture (environment-rgp-publication-posture active-environment)
          :usage-telemetry (environment-rgp-usage-telemetry active-environment))))

(defun environment-rgp-artifact-summaries (&optional environment)
  (let* ((session (environment-session environment))
         (artifacts (if session
                        (agent-session-artifacts session)
                        '())))
    (mapcar (lambda (artifact)
              (let ((summary (artifact-record-summary artifact)))
                (append summary
                        (list :lineage (list :source-ref (getf summary :source-ref)
                                             :image-ref (getf summary :image-ref)
                                             :work-item-id (getf summary :work-item-id))
                              :governance-scope (if (getf summary :thread-id)
                                                    :thread
                                                    :environment)))))
            artifacts)))

(defun environment-rgp-approval-summaries (&optional environment)
  (let* ((session (environment-session environment))
         (work-items (if session
                         (agent-session-work-items session)
                         '()))
         (blocked '()))
    (dolist (work-item work-items (nreverse blocked))
      (let* ((wait-report (work-item-wait-report session work-item))
             (reason (getf wait-report :why))
             (handles (kernel-execution-summaries-by-target :work-item-id
                                                            (work-item-id work-item)
                                                            environment)))
        (unless (eq reason :ready)
          (push (append (work-item-summary work-item)
                        (list :primary-execution-handle (first handles)
                              :execution-handles handles)
                        (list :waiting-on (getf wait-report :waiting-on)
                              :wait-reason reason
                              :approval-requirements (getf wait-report :approval-requirements)
                              :resume-count (getf wait-report :resume-count)
                              :quarantine-reason (getf wait-report :quarantine-reason)
                              :governed-actions (list :approve-runtime-checkpoint
                                                      :resume-runtime)))
                blocked))))))

(defun json-safe-keyword (value)
  (string-downcase (symbol-name value)))

(defun json-alist-p (value)
  (and (listp value)
       (every #'consp value)
       (every (lambda (entry)
                (stringp (car entry)))
              value)))

(defun json-alist-keyword (key)
  (intern (string-upcase (substitute #\- #\_ key)) "KEYWORD"))

(defun json-safe-value (value)
  (cond
    ((or (null value) (eq value t) (stringp value) (numberp value))
     value)
    ((keywordp value)
     (json-safe-keyword value))
    ((symbolp value)
     (string-downcase (symbol-name value)))
    ((json-alist-p value)
     (loop for (key . entry) in value
           append (list (json-alist-keyword key)
                        (json-safe-value entry))))
    ((and (listp value)
          (every #'keywordp value))
     (mapcar #'json-safe-value value))
    ((json-plist-p value)
     (loop for (key entry) on value by #'cddr
           append (list key (json-safe-value entry))))
    ((listp value)
     (mapcar #'json-safe-value value))
    (t
     (princ-to-string value))))

(defun environment-rgp-snapshot (&optional environment)
  (let* ((active-environment (ensure-environment environment))
         (session (environment-session active-environment))
         (thread (and session (current-thread session)))
         (latest-turn (and session thread
                           (latest-thread-turn-summary session thread)))
         (operations (if latest-turn
                         (getf latest-turn :operations)
                         '()))
         (summary (environment-summary active-environment)))
    (list :schema-version 1
          :exported-at (get-universal-time)
          :binding (rgp-binding-summary active-environment)
          :governed-runtime (environment-rgp-runtime-summary active-environment)
          :environment summary
          :session (and session (session-summary session))
          :thread (and thread (thread-detail session (thread-id thread)))
          :turn latest-turn
          :operations operations
          :artifacts (environment-rgp-artifact-summaries active-environment)
          :approvals (environment-rgp-approval-summaries active-environment)
          :node-profile (environment-rgp-node-profile active-environment)
          :local-assignments (and session
                                  (environment-rgp-enriched-assignment-summaries
                                   session
                                   active-environment))
          :assignment-evidence (environment-rgp-assignment-evidence-summaries active-environment)
          :assignment-acceptance (environment-rgp-assignment-acceptance-postures active-environment)
          :workspace-summary (and session
                                  (environment-rgp-workspace-summary session
                                                                     active-environment))
          :execution-facts (environment-rgp-execution-facts active-environment)
          :billing-milestones (environment-rgp-billing-milestones active-environment)
          :business-posture (environment-rgp-business-posture active-environment)
          :publication-backlog (environment-rgp-publication-backlog active-environment)
          :publication-posture (environment-rgp-publication-posture active-environment)
          :usage-telemetry (environment-rgp-usage-telemetry active-environment)
          :event-summary (getf summary :event-summary))))

(defun export-environment-rgp-snapshot (path &optional environment)
  (unless (stringp path)
    (error "RGP export requires a string path"))
  (let ((snapshot (environment-rgp-snapshot environment)))
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string (emit-json (json-safe-value snapshot)) stream))
    (list :path path
          :snapshot snapshot)))
