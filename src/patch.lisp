(in-package #:sbcl-agent)

(defun patch-staging-root-pathname (session)
  (let* ((root (uiop:ensure-directory-pathname #P"/private/tmp/sbcl-agent-workspaces/"))
         (session-segment (format nil "~A/" (agent-session-id session)))
         (workspace-segment
           (format nil "patch-~D-~D/"
                   (get-universal-time)
                   (random 1000000))))
    (merge-pathnames workspace-segment
                     (merge-pathnames session-segment root))))

(defun path-relative-to-session-root (session resolved)
  (let* ((root (canonicalize-directory-path (session-root-pathname session)))
         (existing-target (probe-file resolved))
         (target (if existing-target
                     (truename existing-target)
                     resolved))
         (container (if (uiop:directory-pathname-p target)
                        target
                        (canonicalize-file-parent-directory target))))
    (unless (path-within-root-p container root)
      (error "Resolved path is outside the current session root: ~A" (namestring target)))
    (enough-namestring target root)))

(defun patch-staging-workspace-id (staging-root)
  (let* ((directory-components (pathname-directory staging-root))
         (leaf (car (last directory-components))))
    (princ-to-string leaf)))

(defun patch-stage-pathname (staging-root bucket relative-path)
  (merge-pathnames relative-path
                   (merge-pathnames (format nil "~A/" bucket) staging-root)))

(defun write-string-to-file (pathname content)
  (ensure-directories-exist pathname)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string content stream)))

(defun stage-patch-operation (session staging-root operation)
  (destructuring-bind (kind path content) operation
    (unless (eq kind :write)
      (error "Unsupported patch operation ~S" kind))
    (let* ((resolved (ensure-path-within-session session path :must-exist nil))
           (relative-path (path-relative-to-session-root session resolved))
           (staged-path (patch-stage-pathname staging-root "patched" relative-path))
           (backup-path (patch-stage-pathname staging-root "original" relative-path))
           (existing (probe-file resolved)))
      (when existing
        (ensure-directories-exist backup-path)
        (uiop:copy-file existing backup-path))
      (write-string-to-file staged-path content)
      (list :operation :write
            :path (namestring resolved)
            :relative-path relative-path
            :staged-path (namestring staged-path)
            :backup-path (and existing (namestring backup-path))
            :workspace-id (patch-staging-workspace-id staging-root)
            :staging-root (namestring staging-root)
            :staged-at (get-universal-time)
            :bytes (length content)
            :sandbox-profile :workspace-staging
            :promotion-state :staged))))

(defun promote-staged-patch-entry (entry)
  (unless (getf entry :verified-p)
    (error "Refusing to promote patch entry without successful verification: ~A"
           (or (getf entry :path)
               (getf entry :staged-path))))
  (let ((staged-path (pathname (getf entry :staged-path)))
        (target-path (pathname (getf entry :path))))
    (ensure-directories-exist target-path)
    (uiop:copy-file staged-path target-path)
    (append entry
            (list :promoted-at (get-universal-time)
                  :promotion-state :promoted))))

(defun promote-verified-patch-results (verified-results)
  (mapcar #'promote-staged-patch-entry verified-results))

(defun verify-staged-patch-entry (entry)
  (let* ((staged-path (pathname (getf entry :staged-path)))
         (target-path (pathname (getf entry :path)))
         (staged-at (or (getf entry :staged-at)
                        (get-universal-time)))
         (verified-at (get-universal-time))
         (staged-exists-p (not (null (probe-file staged-path))))
         (declared-bytes (or (getf entry :bytes) 0))
         (observed-bytes
           (when staged-exists-p
             (with-open-file (stream staged-path
                                     :direction :input
                                     :if-does-not-exist nil)
               (when stream
                 (file-length stream))))))
    (unless staged-exists-p
      (error "Staged patch artifact is missing before promotion: ~A" (namestring staged-path)))
    (unless (eql declared-bytes observed-bytes)
      (error "Staged patch artifact size mismatch before promotion for ~A: declared ~S observed ~S"
             (namestring target-path)
             declared-bytes
             observed-bytes))
    (append entry
            (list :verified-at verified-at
                  :verified-p t
                  :verification-state :verified
                  :verification-decision
                  (list :verified-p t
                        :decision :promote-eligible
                        :verification-kind :staged-file-integrity
                        :recorded-at verified-at)
                  :verification-report
                  (list :sandbox-profile :workspace-staging
                        :checked-path (namestring staged-path)
                        :target-path (namestring target-path)
                        :declared-bytes declared-bytes
                        :observed-bytes observed-bytes
                        :staged-at staged-at
                        :verified-at verified-at
                        :verification-kind :staged-file-integrity)))))

(defun create-patch-result-artifacts (session results &key thread turn operation)
  (let ((target-thread (or thread
                           (current-thread session)))
        (work-item-id (and operation
                           (getf (operation-metadata operation) :work-item-id))))
    (when target-thread
      (mapcar (lambda (entry)
                (let ((path (getf entry :path)))
                  (create-artifact session
                                   target-thread
                                   turn
                                   operation
                                   :file
                                   path
                                   :title (and path (file-namestring path))
                                   :summary "Patch write completed."
                                   :work-item-id work-item-id
                                   :metadata (list :source :patch
                                                   :bytes (getf entry :bytes)
                                                   :operation (getf entry :operation)
                                                   :sandbox-profile (getf entry :sandbox-profile)))))
              results))))

(defun normalize-patch-operations-request (request)
  (cond
    ((and (listp request) (member :operations request))
     (values (getf request :operations)
             (if (member :promote-p request)
                 (not (null (getf request :promote-p)))
                 t)))
    ((and (listp request) (member :OPERATIONS request))
     (values (getf request :OPERATIONS)
             (if (member :PROMOTE-P request)
                 (not (null (getf request :PROMOTE-P)))
                 t)))
    (t
     (values request t))))

(defun apply-patch-operations (session request &key thread turn operation)
  (ensure-policy-approved session :workspace-write)
  (ensure-sandbox-profile :workspace-staging)
  (multiple-value-bind (operations promote-p)
      (normalize-patch-operations-request request)
    (unless (listp operations)
      (error "PATCH requires a list of operations"))
    (let* ((staging-root (patch-staging-root-pathname session))
           (staged-results
             (mapcar (lambda (current-operation)
                       (stage-patch-operation session staging-root current-operation))
                     operations))
           (verified-results
             (mapcar #'verify-staged-patch-entry staged-results))
           (verification-decision
             (list :verified-p (every (lambda (entry) (getf entry :verified-p))
                                      verified-results)
                   :decision :promote-eligible
                   :verification-kind :staged-file-integrity
                   :workspace-id (patch-staging-workspace-id staging-root)
                   :staging-root (namestring staging-root)
                   :count (length verified-results)))
           (results
             (if promote-p
                 (if (getf verification-decision :verified-p)
                     (promote-verified-patch-results verified-results)
                     (error "Refusing to promote staged patch workspace without positive verification decision: ~S"
                            verification-decision))
                 '()))
           (materialized-at
             (if staged-results
                 (reduce #'min staged-results
                         :key (lambda (entry)
                                (or (getf entry :staged-at)
                                    (get-universal-time))))
                 (get-universal-time)))
           (promotion-pending-at
             (if staged-results
                 (reduce #'max staged-results
                         :key (lambda (entry)
                                (or (getf entry :staged-at)
                                    (get-universal-time))))
                 materialized-at))
           (verified-at
             (if verified-results
                 (reduce #'max verified-results
                         :key (lambda (entry)
                                (or (getf entry :verified-at)
                                    (get-universal-time))))
                 promotion-pending-at))
           (promoted-at
             (if results
                 (reduce #'max results
                         :key (lambda (entry)
                                (or (getf entry :promoted-at)
                                    (get-universal-time))))
                 verified-at)))
      (when results
        (create-patch-result-artifacts session results
                                       :thread thread
                                       :turn turn
                                       :operation operation))
      (append-session-event session
                            :workspace-stage
                            (list :staging-root (namestring staging-root)
                                  :workspace-id (patch-staging-workspace-id staging-root)
                                  :count (length staged-results)
                                  :results staged-results))
      (append-session-event session
                            :workspace-stage-verified
                            (list :staging-root (namestring staging-root)
                                  :workspace-id (patch-staging-workspace-id staging-root)
                                  :count (length verified-results)
                                  :results verified-results))
      (when results
        (append-session-event session :patch results))
      (list :patch results
            :verified-patch verified-results
            :workspace-id (patch-staging-workspace-id staging-root)
            :staging-root (namestring staging-root)
            :verification-decision verification-decision
            :verification-report
            (list :sandbox-profile :workspace-staging
                  :count (length verified-results)
                  :verified-at verified-at
                  :verification-kind :staged-file-integrity)
            :phase-timeline
            (append
             (list (list :phase :workspace-materialized
                         :recorded-at materialized-at)
                   (list :phase :verification-pending
                         :recorded-at promotion-pending-at
                         :detail (list :workspace-id (patch-staging-workspace-id staging-root)
                                       :staging-root (namestring staging-root)
                                       :count (length staged-results)
                                       :verification-kind :staged-file-integrity))
                   (list :phase :verified
                         :recorded-at verified-at
                         :detail (list :workspace-id (patch-staging-workspace-id staging-root)
                                       :staging-root (namestring staging-root)
                                       :count (length verified-results)
                                       :verification-kind :staged-file-integrity)))
             (when results
               (list (list :phase :promotion-pending
                           :recorded-at verified-at
                           :detail (list :workspace-id (patch-staging-workspace-id staging-root)
                                         :staging-root (namestring staging-root)
                                         :count (length verified-results)))
                     (list :phase :promoted
                           :recorded-at promoted-at
                           :detail (list :workspace-id (patch-staging-workspace-id staging-root)
                                         :staging-root (namestring staging-root)
                                         :count (length results))))))
            :promotion-state (if results :promoted :verified)))))

(defun promote-verified-patch-workspace (session request &key thread turn operation)
  (ensure-policy-approved session :workspace-write)
  (let* ((verified-results (or (getf request :verified-patch)
                               (getf request :VERIFIED-PATCH)
                               (error "PROMOTE-PATCH-WORKSPACE requires :verified-patch entries")))
         (workspace-id (or (getf request :workspace-id)
                           (getf request :WORKSPACE-ID)))
         (staging-root (or (getf request :staging-root)
                           (getf request :STAGING-ROOT)))
         (results (promote-verified-patch-results verified-results))
         (promoted-at
           (if results
               (reduce #'max results
                       :key (lambda (entry)
                              (or (getf entry :promoted-at)
                                  (get-universal-time))))
               (get-universal-time))))
    (create-patch-result-artifacts session results
                                   :thread thread
                                   :turn turn
                                   :operation operation)
    (append-session-event session :patch results)
    (list :patch results
          :verified-patch verified-results
          :workspace-id workspace-id
          :staging-root staging-root
          :phase-timeline
          (list (list :phase :promotion-pending
                      :recorded-at promoted-at
                      :detail (list :workspace-id workspace-id
                                    :staging-root staging-root
                                    :count (length verified-results)))
                (list :phase :promoted
                      :recorded-at promoted-at
                      :detail (list :workspace-id workspace-id
                                    :staging-root staging-root
                                    :count (length results))))
          :promotion-state :promoted)))
