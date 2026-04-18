(in-package #:sbcl-agent)

(defparameter +rgp-runtime-subtype+ "sbcl_agent")
(defparameter +rgp-session-kind+ "stateful_runtime")

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

(defun bind-environment-to-rgp (session &key tenant-id request-id agent-session-id integration-id projection-id environment)
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
          :supports-artifact-lineage-p t)))

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
             (reason (getf wait-report :why)))
        (unless (eq reason :ready)
          (push (append (work-item-summary work-item)
                        (list :waiting-on (getf wait-report :waiting-on)
                              :wait-reason reason
                              :approval-requirements (getf wait-report :approval-requirements)
                              :resume-count (getf wait-report :resume-count)
                              :quarantine-reason (getf wait-report :quarantine-reason)
                              :governed-actions (list :approve-runtime-checkpoint
                                                      :resume-runtime)))
                blocked))))))

(defun json-safe-keyword (value)
  (string-downcase (substitute #\_ #\- (symbol-name value))))

(defun json-safe-value (value)
  (cond
    ((or (null value) (eq value t) (stringp value) (numberp value))
     value)
    ((keywordp value)
     (json-safe-keyword value))
    ((symbolp value)
     (string-downcase (symbol-name value)))
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
