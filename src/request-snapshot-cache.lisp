(in-package #:sbcl-agent)

(defun normalize-provider-request-dirty-domain (domain)
  (case domain
    ((:conversation) :conversation)
    ((:runtime) :runtime)
    ((:workspace :project :artifact :events :workflow :testing) :workspace)
    ((:incident :telemetry :console :diagnostic) :runtime)
    ((:intent :policy) :policy)
    ((:environment) :environment)
    (otherwise nil)))

(defun normalize-provider-request-dirty-domains (domains)
  (let ((normalized '()))
    (dolist (domain domains)
      (let ((mapped (normalize-provider-request-dirty-domain domain)))
        (when mapped
          (pushnew mapped normalized :test #'eq))))
    (nreverse normalized)))


;; Planning-context construction lives in request-planning-context.lisp.

(defun clone-provider-request-snapshot (snapshot)
  (when snapshot
    (make-provider-request-snapshot
     :generated-at (provider-request-snapshot-generated-at snapshot)
     :domain-generated-at (copy-tree (provider-request-snapshot-domain-generated-at snapshot))
     :session-summary (provider-request-snapshot-session-summary snapshot)
     :thread-context (provider-request-snapshot-thread-context snapshot)
     :turn-context (provider-request-snapshot-turn-context snapshot)
     :environment-context (provider-request-snapshot-environment-context snapshot)
     :surface-context (provider-request-snapshot-surface-context snapshot)
     :surface-actions (provider-request-snapshot-surface-actions snapshot)
     :runtime-summary (provider-request-snapshot-runtime-summary snapshot)
     :workspace-summary (provider-request-snapshot-workspace-summary snapshot)
     :policy-summary (provider-request-snapshot-policy-summary snapshot)
     :retrieval-dossier (provider-request-snapshot-retrieval-dossier snapshot)
     :cognition-bundle (provider-request-snapshot-cognition-bundle snapshot)
     :reasoning-brief (provider-request-snapshot-reasoning-brief snapshot)
     :planning-brief (provider-request-snapshot-planning-brief snapshot)
     :planning-context-packet (provider-request-snapshot-planning-context-packet snapshot)
     :outcome-brief (provider-request-snapshot-outcome-brief snapshot)
     :cached-context-entries (provider-request-snapshot-cached-context-entries snapshot)
     :cached-context-index (provider-request-snapshot-cached-context-index snapshot))))

(defun provider-request-snapshot-age-seconds (snapshot &optional (now (get-universal-time)))
  (let ((generated-at (and snapshot
                           (provider-request-snapshot-generated-at snapshot))))
    (when generated-at
      (max 0 (- now generated-at)))))

(defun provider-request-snapshot-domain-generated-at-value (snapshot domain)
  (or (getf (provider-request-snapshot-domain-generated-at snapshot) domain)
      (provider-request-snapshot-generated-at snapshot)))

(defun provider-request-snapshot-domain-generation-map (&optional (generated-at (get-universal-time)))
  (loop for domain in +provider-request-snapshot-known-domains+
        append (list domain generated-at)))

(defun provider-request-snapshot-refresh-domains (domains)
  (let ((normalized (normalize-provider-request-dirty-domains domains)))
    (or normalized +provider-request-snapshot-known-domains+)))

(defun provider-request-snapshot-domain-age-seconds (snapshot domain &optional (now (get-universal-time)))
  (let ((generated-at (and snapshot
                           (provider-request-snapshot-domain-generated-at-value snapshot domain))))
    (when generated-at
      (max 0 (- now generated-at)))))

(defun provider-request-snapshot-stale-p (snapshot
                                          &key (now (get-universal-time))
                                            (max-age-seconds +provider-request-snapshot-stale-seconds+))
  (let ((age (provider-request-snapshot-age-seconds snapshot now)))
    (or (null snapshot)
        (null age)
        (> age max-age-seconds))))

(defun provider-request-snapshot-domain-stale-p (snapshot domain
                                                 &key (now (get-universal-time))
                                                   (max-age-seconds +provider-request-snapshot-stale-seconds+))
  (let ((age (provider-request-snapshot-domain-age-seconds snapshot domain now)))
    (or (null snapshot)
        (null age)
        (> age max-age-seconds))))

(defun provider-request-snapshot-dirty-domains-for-reason (reason)
  (case reason
    ((:transcript) '(:conversation))
    ((:plan :pending-actions :pending-actions-cleared) '(:policy :workspace :environment))
    ((:capability-granted :capability-required) '(:policy))
    ((:patch) '(:workspace))
    ((:assistant-actions-executed) '(:runtime :workspace :policy :environment))
    ((:task-enqueued :task-started :task-completed :task-failed :task-cancelled
      :worker-started :worker-stopped)
     '(:workspace :environment))
    ((:incident :sandbox-exec :environment-test) '(:runtime :workspace :policy :environment))
    (otherwise +provider-request-snapshot-known-domains+)))

(defun provider-request-snapshot-dirty-domains-for-family (family)
  (case family
    ((:conversation) '(:conversation))
    ((:runtime :telemetry :diagnostic :console) '(:runtime :environment))
    ((:workflow :artifact :workspace :testing) '(:workspace :environment))
    ((:policy :intent) '(:policy :environment))
    ((:environment) '(:environment))
    (otherwise '())))

(defun provider-request-snapshot-dirty-domains-for-event (&key reason family)
  (normalize-provider-request-dirty-domains
   (append (provider-request-snapshot-dirty-domains-for-reason reason)
           (provider-request-snapshot-dirty-domains-for-family family))))

(defun provider-request-snapshot-domain-selected-p (domains domain)
  (member domain domains :test #'eq))

(defun provider-request-snapshot-dirty-p (session snapshot &key relevant-domains)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let ((dirty-at (environment-metadata-value environment
                                                  +provider-request-snapshot-dirty-at-key+))
            (dirty-domain-times (or (environment-metadata-value environment
                                                                +provider-request-snapshot-dirty-domain-times-key+)
                                    '()))
            (dirty-domains (or (environment-metadata-value environment
                                                            +provider-request-snapshot-dirty-domains-key+)
                               '())))
        (and dirty-at
             (or (null relevant-domains)
                 (null dirty-domains)
                 (some (lambda (domain)
                         (and (member domain dirty-domains :test #'eq)
                              (let ((domain-dirty-at (or (getf dirty-domain-times domain)
                                                         dirty-at)))
                                (or (null snapshot)
                                    (null (provider-request-snapshot-domain-generated-at-value snapshot
                                                                                              domain))
                                    (>= domain-dirty-at
                                        (provider-request-snapshot-domain-generated-at-value snapshot
                                                                                              domain))))))
                       relevant-domains))
             (or (null snapshot)
                 (null relevant-domains)
                 (null (provider-request-snapshot-generated-at snapshot))
                 (>= dirty-at (provider-request-snapshot-generated-at snapshot))))))))

(defun provider-request-snapshot-needs-refresh-p (session snapshot
                                                  &key relevant-domains
                                                    (now (get-universal-time))
                                                    (max-age-seconds +provider-request-snapshot-stale-seconds+))
  (or (if relevant-domains
          (some (lambda (domain)
                  (provider-request-snapshot-domain-stale-p snapshot
                                                           domain
                                                           :now now
                                                           :max-age-seconds max-age-seconds))
                relevant-domains)
          (provider-request-snapshot-stale-p snapshot
                                             :now now
                                             :max-age-seconds max-age-seconds))
      (provider-request-snapshot-dirty-p session snapshot
                                         :relevant-domains relevant-domains)))

(defun provider-request-snapshot-cache-state (environment)
  (list :snapshot (environment-metadata-value environment
                                              +provider-request-snapshot-cache-key+)
        :refresh-pending-p (environment-metadata-value environment
                                                       +provider-request-snapshot-refresh-pending-key+)
        :dirty-at (environment-metadata-value environment
                                              +provider-request-snapshot-dirty-at-key+)
        :dirty-domain-times (copy-list
                             (or (environment-metadata-value environment
                                                             +provider-request-snapshot-dirty-domain-times-key+)
                                 '()))
        :dirty-reasons (copy-list
                        (or (environment-metadata-value environment
                                                        +provider-request-snapshot-dirty-reasons-key+)
                            '()))
        :dirty-domains (copy-list
                        (or (environment-metadata-value environment
                                                        +provider-request-snapshot-dirty-domains-key+)
                            '()))))

(defun write-provider-request-snapshot-cache-state (environment state)
  (set-environment-metadata-value environment
                                  +provider-request-snapshot-cache-key+
                                  (getf state :snapshot))
  (set-environment-metadata-value environment
                                  +provider-request-snapshot-refresh-pending-key+
                                  (getf state :refresh-pending-p))
  (set-environment-metadata-value environment
                                  +provider-request-snapshot-dirty-at-key+
                                  (getf state :dirty-at))
  (set-environment-metadata-value environment
                                  +provider-request-snapshot-dirty-domain-times-key+
                                  (getf state :dirty-domain-times))
  (set-environment-metadata-value environment
                                  +provider-request-snapshot-dirty-reasons-key+
                                  (getf state :dirty-reasons))
  (set-environment-metadata-value environment
                                  +provider-request-snapshot-dirty-domains-key+
                                  (getf state :dirty-domains))
  state)

(defun mark-provider-request-snapshot-dirty (session &key reason family)
  (let ((environment (session-bound-environment session)))
    (when environment
      (sb-thread:with-mutex (*provider-request-snapshot-cache-lock*)
        (let* ((state (provider-request-snapshot-cache-state environment))
               (now (get-universal-time))
               (dirty-reasons (getf state :dirty-reasons))
               (dirty-domain-times (getf state :dirty-domain-times))
               (dirty-domains (getf state :dirty-domains)))
          (setf (getf state :dirty-at) now)
          (when reason
            (pushnew reason dirty-reasons :test #'equal))
          (dolist (domain (provider-request-snapshot-dirty-domains-for-event
                           :reason reason
                           :family family))
            (pushnew domain dirty-domains :test #'eq)
            (setf (getf dirty-domain-times domain) now))
          (setf (getf state :dirty-reasons) dirty-reasons
                (getf state :dirty-domain-times) dirty-domain-times
                (getf state :dirty-domains) dirty-domains)
          (write-provider-request-snapshot-cache-state environment state))))))

(defun lightweight-conversation-request-p (prompt &key (operator-mode :repl-bridge)
                                                  attachments surface-actions)
  (declare (ignore surface-actions))
  (let* ((normalized (string-trim '(#\Space #\Tab #\Newline #\Return) (or prompt "")))
         (decision (classify-interaction-decision normalized :operator-mode operator-mode)))
    (and (eq operator-mode :conversation)
         (> (length normalized) 0)
         (<= (length normalized) 160)
         (not (find #\Newline normalized))
         (null attachments)
         (eq (interaction-decision-mode decision) :conversation))))

(defun cached-conversation-context-request-p (prompt &key (operator-mode :repl-bridge)
                                                        attachments surface-actions)
  (let* ((normalized (string-trim '(#\Space #\Tab #\Newline #\Return) (or prompt "")))
         (decision (classify-interaction-decision normalized :operator-mode operator-mode)))
    (and (eq operator-mode :conversation)
         (> (length normalized) 0)
         (null attachments)
         (member (interaction-decision-mode decision) '(:conversation :inspect) :test #'eq)
         (not (lightweight-conversation-request-p normalized
                                                  :operator-mode operator-mode
                                                  :attachments attachments
                                                  :surface-actions surface-actions)))))

(defun context-search-text (value)
  (labels ((collect-text (item)
             (cond
               ((null item) "")
               ((stringp item) item)
               ((symbolp item) (string-downcase (string item)))
               ((numberp item) (princ-to-string item))
               ((listp item)
                (with-output-to-string (stream)
                  (dolist (entry item)
                    (let ((text (collect-text entry)))
                      (when (> (length text) 0)
                        (write-string text stream)
                        (write-char #\Space stream))))))
               (t
                (princ-to-string item)))))
    (string-downcase (collect-text value))))

(defun context-summary-text (value &key (limit 240))
  (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return)
                           (context-search-text value))))
    (if (> (length text) limit)
        (concatenate 'string (subseq text 0 limit) "...")
        text)))

(defun cached-context-entry-with-index (entry)
  (let* ((label (or (getf entry :label) ""))
         (domain (or (getf entry :domain) ""))
         (text (or (getf entry :text) ""))
         (summary (or (getf entry :summary) ""))
         (label-tokens (remove-duplicates (prompt-match-tokens label) :test #'string=))
         (domain-tokens (remove-duplicates (prompt-match-tokens domain) :test #'string=))
         (summary-tokens (remove-duplicates (prompt-match-tokens summary) :test #'string=))
         (text-tokens (remove-duplicates (prompt-match-tokens text) :test #'string=)))
    (append entry
            (list :label-tokens label-tokens
                  :domain-tokens domain-tokens
                  :summary-tokens summary-tokens
                  :text-tokens text-tokens))))

(defun cached-context-entry-score (prompt-tokens entry)
  (let ((label-tokens (getf entry :label-tokens))
        (domain-tokens (getf entry :domain-tokens))
        (summary-tokens (getf entry :summary-tokens))
        (text-tokens (getf entry :text-tokens)))
    (loop for token in prompt-tokens
          sum (+ (if (member token label-tokens :test #'string=) 4 0)
                 (if (member token domain-tokens :test #'string=) 3 0)
                 (if (member token summary-tokens :test #'string=) 2 0)
                 (if (member token text-tokens :test #'string=) 1 0)))))

(defun cached-context-entry-token-weight (entry token)
  (+ (if (member token (getf entry :label-tokens) :test #'string=) 4 0)
     (if (member token (getf entry :domain-tokens) :test #'string=) 3 0)
     (if (member token (getf entry :summary-tokens) :test #'string=) 2 0)
     (if (member token (getf entry :text-tokens) :test #'string=) 1 0)))

(defun build-cached-context-index (entries)
  (let ((index (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (let ((tokens (remove-duplicates
                     (append (or (getf entry :label-tokens) '())
                             (or (getf entry :domain-tokens) '())
                             (or (getf entry :summary-tokens) '())
                             (or (getf entry :text-tokens) '()))
                     :test #'string=)))
        (dolist (token tokens)
          (push (cons entry (cached-context-entry-token-weight entry token))
                (gethash token index)))))
    index))

(defun copy-cached-context-index (index)
  (let ((copy (make-hash-table :test #'equal)))
    (when index
      (maphash (lambda (token postings)
                 (setf (gethash token copy) (copy-list postings)))
               index))
    copy))

(defun merge-cached-context-index (existing-index replacement-entries domains)
  (let* ((replacement-domains
           (mapcar #'provider-request-domain->cached-context-domain domains))
         (merged-index (copy-cached-context-index existing-index))
         (replacement-index (build-cached-context-index replacement-entries)))
    (maphash (lambda (token postings)
               (let ((filtered
                       (remove-if (lambda (posting)
                                    (member (getf (car posting) :domain)
                                            replacement-domains
                                            :test #'string=))
                                  postings)))
                 (if filtered
                     (setf (gethash token merged-index) filtered)
                     (remhash token merged-index))))
             (copy-cached-context-index merged-index))
    (maphash (lambda (token postings)
               (let* ((filtered
                        (or (gethash token merged-index) '()))
                      (combined (append filtered postings)))
                 (if combined
                     (setf (gethash token merged-index) combined)
                     (remhash token merged-index))))
             replacement-index)
    merged-index))

(defun cached-context-ranked-items (prompt-tokens entries index)
  (if (and index prompt-tokens)
      (let ((scores (make-hash-table :test #'eq)))
        (dolist (token prompt-tokens)
          (dolist (posting (gethash token index))
            (incf (gethash (car posting) scores 0) (cdr posting))))
        (let ((ranked '()))
          (maphash (lambda (entry score)
                     (push (list :entry entry :score score) ranked))
                   scores)
          (if ranked
              (sort ranked #'> :key (lambda (item) (getf item :score)))
              (sort (loop for entry in entries
                          for score = (cached-context-entry-score prompt-tokens entry)
                          collect (list :entry entry :score score))
                    #'>
                    :key (lambda (item) (getf item :score))))))
      (sort (loop for entry in entries
                  for score = (cached-context-entry-score prompt-tokens entry)
                  collect (list :entry entry :score score))
            #'>
            :key (lambda (item) (getf item :score)))))

(defun cached-context-ranking-entry (entry score)
  (list :label (getf entry :label)
        :kind :cached-context
        :domain (getf entry :domain)
        :score score
        :summary (getf entry :summary)
        :ref (getf entry :ref)))

(defun provider-request-domain->cached-context-domain (domain)
  (string-downcase (string domain)))

(defun cached-conversation-context-entries-for-domain (snapshot domain)
  (ecase domain
    (:conversation
     (remove nil
             (list
              (let ((thread-context (and snapshot
                                         (provider-request-snapshot-thread-context snapshot))))
                (when thread-context
                  (list :domain "conversation"
                        :label "Active Thread"
                        :summary (or (getf thread-context :summary)
                                     (getf thread-context :title))
                        :ref (list :type :thread
                                   :id (getf thread-context :id))
                        :text (context-search-text thread-context))))
              (let ((turn-context (and snapshot
                                       (provider-request-snapshot-turn-context snapshot))))
                (when turn-context
                  (list :domain "conversation"
                        :label "Current Turn"
                        :summary (or (getf (getf turn-context :assistant-message) :content)
                                     (getf (getf turn-context :user-message) :content)
                                     (context-summary-text (getf turn-context :detail-summary)))
                        :ref (list :type :turn
                                   :id (getf turn-context :id))
                        :text (context-search-text turn-context))))
              (let ((session-summary (and snapshot
                                          (provider-request-snapshot-session-summary snapshot))))
                (when session-summary
                  (list :domain "conversation"
                        :label "Recent Transcript"
                        :summary (format nil "~D recent transcript entries"
                                         (length (or (getf session-summary :recent-transcript) '())))
                        :ref (list :type :transcript
                                   :count (getf session-summary :transcript-count))
                        :text (context-search-text (getf session-summary :recent-transcript))))))))
    (:runtime
     (let ((runtime-summary (and snapshot
                                 (provider-request-snapshot-runtime-summary snapshot))))
       (remove nil
               (list
                (when runtime-summary
                  (list :domain "runtime"
                        :label "Runtime Summary"
                        :summary (format nil "Package ~A, ~D open incidents"
                                         (or (getf runtime-summary :package) "CL-USER")
                                         (or (getf runtime-summary :open-incident-count) 0))
                        :ref (list :type :runtime
                                   :environment-id (getf runtime-summary :environment-id))
                        :text (context-search-text runtime-summary)))))))
    (:workspace
     (let ((workspace-summary (and snapshot
                                   (provider-request-snapshot-workspace-summary snapshot))))
       (remove nil
               (list
                (when workspace-summary
                  (list :domain "workspace"
                        :label "Workspace Summary"
                        :summary (format nil "~D work items, ~D artifacts"
                                         (or (getf workspace-summary :work-item-count) 0)
                                         (or (getf workspace-summary :artifact-count) 0))
                        :ref (list :type :workspace
                                   :cwd (getf workspace-summary :cwd))
                        :text (context-search-text workspace-summary)))))))
    (:policy
     (let ((policy-summary (and snapshot
                                (provider-request-snapshot-policy-summary snapshot))))
       (remove nil
               (list
                (when policy-summary
                  (list :domain "policy"
                        :label "Policy Summary"
                        :summary (format nil "~D open incidents"
                                         (or (getf policy-summary :open-incident-count) 0))
                        :ref (list :type :policy
                                   :environment-id (getf policy-summary :environment-id))
                        :text (context-search-text policy-summary)))))))
    (:environment
     (let ((environment-context (and snapshot
                                     (provider-request-snapshot-environment-context snapshot))))
       (remove nil
               (list
                (when environment-context
                  (list :domain "environment"
                        :label "Environment Refs"
                        :summary (format nil "~D threads, ~D work items, ~D incidents"
                                         (or (getf environment-context :thread-count) 0)
                                         (or (getf environment-context :work-item-count) 0)
                                         (or (getf environment-context :open-incident-count) 0))
                        :ref (list :type :environment
                                   :environment-id (getf environment-context :environment-id))
                        :text (context-search-text environment-context)))))))))

(defun cached-conversation-context-entries-for-domains (snapshot domains)
  (mapcar #'cached-context-entry-with-index
          (loop for domain in domains
                append (cached-conversation-context-entries-for-domain snapshot domain))))

(defun merge-cached-conversation-context-entries (existing-entries replacement-entries domains)
  (let ((replacement-domains
          (mapcar #'provider-request-domain->cached-context-domain domains)))
    (append
     (remove-if (lambda (entry)
                  (member (getf entry :domain) replacement-domains :test #'string=))
                (or existing-entries '()))
     replacement-entries)))

(defun cached-conversation-context-entries (snapshot)
  (mapcar #'cached-context-entry-with-index
          (loop for domain in +provider-request-snapshot-known-domains+
                append (cached-conversation-context-entries-for-domain snapshot domain))))

(defun build-cached-conversation-retrieval-dossier (prompt snapshot &key (operator-mode :conversation))
  (let* ((prompt-tokens (remove-duplicates (prompt-match-tokens prompt) :test #'string=))
         (intent (classify-retrieval-intent prompt :operator-mode operator-mode))
         (entries (or (and snapshot
                           (provider-request-snapshot-cached-context-entries snapshot))
                      (cached-conversation-context-entries snapshot)))
         (index (and snapshot
                     (provider-request-snapshot-cached-context-index snapshot)))
         (ranked (cached-context-ranked-items prompt-tokens entries index))
         (hits (subseq ranked 0 (min 6 (length ranked))))
         (domains (remove-duplicates
                   (append (or (retrieval-intent-domains intent) '())
                           (mapcar (lambda (item)
                                     (intern (string-upcase (getf (getf item :entry) :domain))
                                             :keyword))
                                   hits))
                   :test #'eq)))
    (list :phase :cached-conversation
          :intent (list :category (or (retrieval-intent-category intent) :conversation)
                        :primary-intent (or (retrieval-intent-primary-intent intent)
                                            (retrieval-intent-category intent)
                                            :conversation)
                        :secondary-intents (copy-list (or (retrieval-intent-secondary-intents intent) '()))
                        :task-archetype (retrieval-intent-task-archetype intent)
                        :requested-deliverable (retrieval-intent-requested-deliverable intent)
                        :phase-intent (or (retrieval-intent-phase-intent intent) :inspect)
                        :domains domains
                        :historical-p (retrieval-intent-historical-p intent)
                        :intent-context-p (retrieval-intent-intent-context-p intent)
                        :runtime-inspection-p (retrieval-intent-runtime-inspection-p intent)
                        :governance-context-p (retrieval-intent-governance-context-p intent)
                        :observability-context-p (retrieval-intent-observability-context-p intent)
                        :testing-context-p (retrieval-intent-testing-context-p intent)
                        :project-context-p (retrieval-intent-project-context-p intent)
                        :source-context-p (retrieval-intent-source-context-p intent)
                        :mutation-likely-p nil
                        :explanation "Cached conversational context relevance over a warm snapshot.")
          :plan (list :domains domains
                      :per-domain-limits '((:conversation . 3)
                                           (:runtime . 2)
                                           (:workspace . 2)
                                           (:policy . 1)
                                           (:environment . 2))
                      :expansion-posture :cached-search
                      :expansion-pass 0
                      :runtime-detail-p nil
                      :governance-detail-p nil
                      :project-detail-p nil
                      :source-detail-p nil
                      :semantic-ranking-p nil
                      :explanation "Use warm snapshot search results instead of building a full retrieval dossier.")
          :ranking (mapcar (lambda (item)
                             (cached-context-ranking-entry (getf item :entry)
                                                           (getf item :score)))
                           hits)
          :conversation-context (list :thread (and snapshot
                                                   (provider-request-snapshot-thread-context snapshot))
                                      :turn (and snapshot
                                                 (provider-request-snapshot-turn-context snapshot))
                                      :recent-transcript (and snapshot
                                                              (getf (provider-request-snapshot-session-summary snapshot)
                                                                    :recent-transcript)))
          :runtime-context (and snapshot
                                (provider-request-snapshot-runtime-summary snapshot))
          :workflow-context (and snapshot
                                 (provider-request-snapshot-workspace-summary snapshot))
          :artifact-context (and snapshot
                                 (getf (provider-request-snapshot-workspace-summary snapshot)
                                       :artifact-summary))
          :environment-context (and snapshot
                                    (provider-request-snapshot-environment-context snapshot))
          :observed-consequences '()
          :gaps '())))

(defun build-prompt-independent-provider-request-snapshot (session
                                                           &key thread turn
                                                             surface-context surface-actions)
  (ensure-default-thread session)
  (let* ((snapshot (build-provider-environment-snapshot session))
         (thread-context (provider-thread-context session thread snapshot))
         (turn-context (provider-turn-context session turn snapshot))
         (session-summary (provider-session-summary session snapshot))
         (environment-context (provider-environment-context session snapshot))
         (generated-at (get-universal-time))
         (base-snapshot (make-provider-request-snapshot
                         :generated-at generated-at
                         :domain-generated-at (provider-request-snapshot-domain-generation-map generated-at)
                         :session-summary session-summary
                         :thread-context thread-context
                         :turn-context turn-context
                         :environment-context environment-context
                         :surface-context surface-context
                         :surface-actions surface-actions
                         :runtime-summary (provider-runtime-summary session snapshot)
                         :workspace-summary (provider-workspace-summary session snapshot)
                         :policy-summary (provider-policy-summary session snapshot)
                         :retrieval-dossier nil
                         :cognition-bundle nil
                         :reasoning-brief nil
                         :planning-brief nil
                         :planning-context-packet nil
                         :outcome-brief nil
                         :cached-context-entries nil
                         :cached-context-index nil))
         (cached-context-entries (cached-conversation-context-entries base-snapshot))
         (cached-context-index (build-cached-context-index cached-context-entries)))
    (make-provider-request-snapshot
     :generated-at (provider-request-snapshot-generated-at base-snapshot)
     :domain-generated-at (copy-tree (provider-request-snapshot-domain-generated-at base-snapshot))
     :session-summary session-summary
     :thread-context thread-context
     :turn-context turn-context
     :environment-context environment-context
     :surface-context surface-context
     :surface-actions surface-actions
     :runtime-summary (provider-request-snapshot-runtime-summary base-snapshot)
     :workspace-summary (provider-request-snapshot-workspace-summary base-snapshot)
     :policy-summary (provider-request-snapshot-policy-summary base-snapshot)
     :retrieval-dossier nil
     :cognition-bundle nil
     :reasoning-brief nil
     :planning-brief nil
     :planning-context-packet nil
     :outcome-brief nil
     :cached-context-entries cached-context-entries
     :cached-context-index cached-context-index)))

(defun merge-provider-request-snapshot-domains (session existing-snapshot
                                                &key thread turn
                                                  surface-context surface-actions
                                                  domains)
  (let* ((refresh-domains (provider-request-snapshot-refresh-domains domains))
         (environment-snapshot (build-provider-environment-snapshot session))
         (generated-at (get-universal-time))
         (domain-generated-at (copy-tree
                               (or (provider-request-snapshot-domain-generated-at existing-snapshot)
                                   (provider-request-snapshot-domain-generation-map generated-at))))
         (thread-context (if (provider-request-snapshot-domain-selected-p refresh-domains :conversation)
                             (provider-thread-context session thread environment-snapshot)
                             (or thread
                                 (provider-request-snapshot-thread-context existing-snapshot))))
         (turn-context (if (provider-request-snapshot-domain-selected-p refresh-domains :conversation)
                           (provider-turn-context session turn environment-snapshot)
                           (or turn
                               (provider-request-snapshot-turn-context existing-snapshot))))
         (merged-snapshot
           (make-provider-request-snapshot
            :generated-at generated-at
            :domain-generated-at domain-generated-at
            :session-summary (provider-session-summary session environment-snapshot)
            :thread-context thread-context
            :turn-context turn-context
            :environment-context (if (provider-request-snapshot-domain-selected-p refresh-domains :environment)
                                     (provider-environment-context session environment-snapshot)
                                     (provider-request-snapshot-environment-context existing-snapshot))
            :surface-context (or surface-context
                                 (provider-request-snapshot-surface-context existing-snapshot))
            :surface-actions (or surface-actions
                                 (provider-request-snapshot-surface-actions existing-snapshot))
            :runtime-summary (if (provider-request-snapshot-domain-selected-p refresh-domains :runtime)
                                 (provider-runtime-summary session environment-snapshot)
                                 (provider-request-snapshot-runtime-summary existing-snapshot))
            :workspace-summary (if (provider-request-snapshot-domain-selected-p refresh-domains :workspace)
                                   (provider-workspace-summary session environment-snapshot)
                                   (provider-request-snapshot-workspace-summary existing-snapshot))
            :policy-summary (if (provider-request-snapshot-domain-selected-p refresh-domains :policy)
                                (provider-policy-summary session environment-snapshot)
                                (provider-request-snapshot-policy-summary existing-snapshot))
            :retrieval-dossier nil
            :cognition-bundle nil
            :reasoning-brief nil
            :planning-brief nil
            :planning-context-packet nil
            :outcome-brief nil
            :cached-context-entries nil
            :cached-context-index nil)))
    (dolist (domain refresh-domains)
      (setf (getf domain-generated-at domain) generated-at))
    (let ((merged-entries
            (merge-cached-conversation-context-entries
             (provider-request-snapshot-cached-context-entries existing-snapshot)
             (cached-conversation-context-entries-for-domains merged-snapshot refresh-domains)
             refresh-domains))
          (replacement-entries
            (cached-conversation-context-entries-for-domains merged-snapshot refresh-domains)))
      (setf (provider-request-snapshot-domain-generated-at merged-snapshot) domain-generated-at
            (provider-request-snapshot-cached-context-entries merged-snapshot) merged-entries
            (provider-request-snapshot-cached-context-index merged-snapshot)
            (merge-cached-context-index
             (provider-request-snapshot-cached-context-index existing-snapshot)
             replacement-entries
             refresh-domains)))
    merged-snapshot))

(defun provider-request-snapshot-with-overrides (snapshot
                                                 &key thread-context turn-context
                                                   surface-context surface-actions
                                                   retrieval-dossier cognition-bundle
                                                   reasoning-brief planning-brief
                                                   planning-context-packet
                                                   outcome-brief)
  (make-provider-request-snapshot
   :generated-at (provider-request-snapshot-generated-at snapshot)
   :domain-generated-at (copy-tree (provider-request-snapshot-domain-generated-at snapshot))
   :session-summary (provider-request-snapshot-session-summary snapshot)
   :thread-context (or thread-context
                       (provider-request-snapshot-thread-context snapshot))
   :turn-context (or turn-context
                     (provider-request-snapshot-turn-context snapshot))
   :environment-context (provider-request-snapshot-environment-context snapshot)
   :surface-context (or surface-context
                        (provider-request-snapshot-surface-context snapshot))
   :surface-actions (or surface-actions
                        (provider-request-snapshot-surface-actions snapshot))
   :runtime-summary (provider-request-snapshot-runtime-summary snapshot)
   :workspace-summary (provider-request-snapshot-workspace-summary snapshot)
   :policy-summary (provider-request-snapshot-policy-summary snapshot)
   :retrieval-dossier (or retrieval-dossier
                          (provider-request-snapshot-retrieval-dossier snapshot))
   :cognition-bundle (or cognition-bundle
                         (provider-request-snapshot-cognition-bundle snapshot))
   :reasoning-brief (or reasoning-brief
                        (provider-request-snapshot-reasoning-brief snapshot))
   :planning-brief (or planning-brief
                       (provider-request-snapshot-planning-brief snapshot))
   :planning-context-packet (or planning-context-packet
                                (provider-request-snapshot-planning-context-packet snapshot))
   :outcome-brief (or outcome-brief
                      (provider-request-snapshot-outcome-brief snapshot))
   :cached-context-entries (provider-request-snapshot-cached-context-entries snapshot)
   :cached-context-index (provider-request-snapshot-cached-context-index snapshot)))

(defun cached-provider-request-snapshot (session)
  (let ((environment (session-bound-environment session)))
    (when environment
      (sb-thread:with-mutex (*provider-request-snapshot-cache-lock*)
        (clone-provider-request-snapshot
         (getf (provider-request-snapshot-cache-state environment)
               :snapshot))))))

(defun refresh-provider-request-snapshot-cache (session
                                                &key thread turn
                                                  surface-context surface-actions
                                                  domains)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let* ((state (provider-request-snapshot-cache-state environment))
             (existing-snapshot (getf state :snapshot))
             (snapshot (if (and existing-snapshot domains)
                           (merge-provider-request-snapshot-domains
                            session
                            existing-snapshot
                            :thread thread
                            :turn turn
                            :surface-context surface-context
                            :surface-actions surface-actions
                            :domains domains)
                           (build-prompt-independent-provider-request-snapshot
                            session
                            :thread thread
                            :turn turn
                            :surface-context surface-context
                            :surface-actions surface-actions))))
        (sb-thread:with-mutex (*provider-request-snapshot-cache-lock*)
          (setf (getf state :snapshot) snapshot
                (getf state :dirty-at) nil
                (getf state :dirty-domain-times) nil
                (getf state :dirty-reasons) nil
                (getf state :dirty-domains) nil)
          (write-provider-request-snapshot-cache-state environment state))
        snapshot))))

(defun provider-request-relevant-dirty-domains (prompt operator-mode attachments surface-actions)
  (when (cached-conversation-context-request-p prompt
                                               :operator-mode operator-mode
                                               :attachments attachments
                                               :surface-actions surface-actions)
    (or (normalize-provider-request-dirty-domains
         (retrieval-intent-domains (classify-retrieval-intent prompt
                                                              :operator-mode operator-mode)))
        '(:conversation))))

(defun schedule-provider-request-snapshot-refresh (session
                                                   &key thread turn
                                                     surface-context surface-actions
                                                     domains)
  (let ((environment (session-bound-environment session)))
    (when environment
      (let ((start-refresh-p nil))
        (sb-thread:with-mutex (*provider-request-snapshot-cache-lock*)
          (let ((state (provider-request-snapshot-cache-state environment)))
            (unless (getf state :refresh-pending-p)
              (setf (getf state :refresh-pending-p) t)
              (write-provider-request-snapshot-cache-state environment state)
              (setf start-refresh-p t))))
        (when start-refresh-p
          (sb-thread:make-thread
           (lambda ()
             (unwind-protect
                  (refresh-provider-request-snapshot-cache session
                                                           :thread thread
                                                           :turn turn
                                                           :surface-context surface-context
                                                           :surface-actions surface-actions
                                                           :domains domains)
               (sb-thread:with-mutex (*provider-request-snapshot-cache-lock*)
                 (let ((state (provider-request-snapshot-cache-state environment)))
                   (setf (getf state :refresh-pending-p) nil)
                   (write-provider-request-snapshot-cache-state environment state)))))
           :name "sbcl-agent-provider-request-snapshot-refresh"))))))

(defun notify-provider-request-snapshot-environment-change (environment
                                                            &key reason family
                                                              domains)
  (let* ((active-environment (ensure-environment environment))
         (sessionish (environment-compatibility-session active-environment))
         (session (and (compatibility-session-materialized-p sessionish)
                       sessionish))
         (resolved-domains (provider-request-snapshot-refresh-domains
                            (or domains
                                (provider-request-snapshot-dirty-domains-for-event
                                 :reason reason
                                 :family family)))))
    (when session
      (mark-provider-request-snapshot-dirty session :reason reason :family family)
      (schedule-provider-request-snapshot-refresh session :domains resolved-domains))
    resolved-domains))
