(in-package #:sbcl-agent)

(defparameter +environment-trace-links-key+ :trace-links)

(defstruct trace-link
  id
  relation
  source-kind
  source-id
  target-kind
  target-id
  status
  created-at
  updated-at
  evidence
  metadata)

(defun make-trace-link-id ()
  (format nil "trace-~D-~D" (get-universal-time) (random 1000000)))

(defun canonicalize-trace-link-record (value)
  (cond
    ((typep value 'trace-link) value)
    ((listp value)
     (let ((link (build-trace-link :id (getf value :id)
                                   :relation (getf value :relation)
                                   :source-kind (getf value :source-kind)
                                   :source-id (getf value :source-id)
                                   :target-kind (getf value :target-kind)
                                   :target-id (getf value :target-id)
                                   :status (or (getf value :status) :active)
                                   :evidence (getf value :evidence)
                                   :metadata (getf value :metadata))))
       (when (getf value :created-at)
         (setf (trace-link-created-at link) (getf value :created-at)))
       (when (getf value :updated-at)
         (setf (trace-link-updated-at link) (getf value :updated-at)))
       link))
    (t nil)))

(defun ensure-session-trace-links-slots (session)
  (let ((environment (ignore-errors (session-bound-environment session))))
    (when (and environment
               (null (agent-session-trace-links session))
               (listp (getf (environment-metadata environment) +environment-trace-links-key+)))
      (setf (agent-session-trace-links session)
            (remove nil
                    (mapcar #'canonicalize-trace-link-record
                            (getf (environment-metadata environment) +environment-trace-links-key+))))))
  (when (listp (agent-session-trace-links session))
    (setf (agent-session-trace-links session)
          (remove nil
                  (mapcar #'canonicalize-trace-link-record
                          (agent-session-trace-links session)))))
  (unless (listp (agent-session-trace-links session))
    (setf (agent-session-trace-links session) '()))
  (unless (or (null (agent-session-trace-links-tail session))
              (consp (agent-session-trace-links-tail session)))
    (setf (agent-session-trace-links-tail session) nil))
  session)

(defun sync-trace-links-to-environment (session)
  (ensure-session-trace-links-slots session)
  (let ((environment (ignore-errors (session-bound-environment session))))
    (when environment
      (setf (getf (environment-metadata environment) +environment-trace-links-key+)
            (mapcar #'trace-link-summary
                    (agent-session-trace-links session)))))
  session)

(defun list-trace-links (session)
  (ensure-session-trace-links-slots session)
  (copy-list (or (agent-session-trace-links session) '())))

(defun trace-link-summary (link)
  (let ((record (canonicalize-trace-link-record link)))
    (unless record
      (error "Unsupported trace-link record ~S" link))
    (list :id (trace-link-id record)
          :relation (trace-link-relation record)
          :source-kind (trace-link-source-kind record)
          :source-id (trace-link-source-id record)
          :target-kind (trace-link-target-kind record)
          :target-id (trace-link-target-id record)
          :status (trace-link-status record)
          :created-at (trace-link-created-at record)
          :updated-at (trace-link-updated-at record)
          :evidence (copy-list (or (trace-link-evidence record) '()))
          :metadata (copy-list (or (trace-link-metadata record) '())))))

(defun find-trace-link (session trace-link-id)
  (find trace-link-id
        (list-trace-links session)
        :key #'trace-link-id
        :test #'string=))

(defun same-trace-link-p (link relation source-kind source-id target-kind target-id)
  (and (eq (trace-link-relation link) relation)
       (eq (trace-link-source-kind link) source-kind)
       (string= (or (trace-link-source-id link) "")
                (or source-id ""))
       (eq (trace-link-target-kind link) target-kind)
       (string= (or (trace-link-target-id link) "")
                (or target-id ""))))

(defun find-trace-link-by-shape (session relation source-kind source-id target-kind target-id)
  (find-if (lambda (link)
             (same-trace-link-p link relation source-kind source-id target-kind target-id))
           (list-trace-links session)))

(defun entity-trace-link-p (link entity-kind entity-id)
  (or (and (eq (trace-link-source-kind link) entity-kind)
           (string= (or (trace-link-source-id link) "")
                    (or entity-id "")))
      (and (eq (trace-link-target-kind link) entity-kind)
           (string= (or (trace-link-target-id link) "")
                    (or entity-id "")))))

(defun entity-trace-links (session entity-kind entity-id &key relation)
  (remove-if-not (lambda (link)
                   (and (entity-trace-link-p link entity-kind entity-id)
                        (if relation
                            (eq (trace-link-relation link) relation)
                            t)))
                 (list-trace-links session)))

(defun outbound-trace-links (session entity-kind entity-id &key relation)
  (remove-if-not (lambda (link)
                   (and (eq (trace-link-source-kind link) entity-kind)
                        (string= (or (trace-link-source-id link) "")
                                 (or entity-id ""))
                        (if relation
                            (eq (trace-link-relation link) relation)
                            t)))
                 (list-trace-links session)))

(defun inbound-trace-links (session entity-kind entity-id &key relation)
  (remove-if-not (lambda (link)
                   (and (eq (trace-link-target-kind link) entity-kind)
                        (string= (or (trace-link-target-id link) "")
                                 (or entity-id ""))
                        (if relation
                            (eq (trace-link-relation link) relation)
                            t)))
                 (list-trace-links session)))

(defun trace-neighborhood-summary (session entity-kind entity-id &key relation)
  (let ((outbound (mapcar #'trace-link-summary
                          (outbound-trace-links session entity-kind entity-id :relation relation)))
        (inbound (mapcar #'trace-link-summary
                         (inbound-trace-links session entity-kind entity-id :relation relation))))
    (list :entity-kind entity-kind
          :entity-id entity-id
          :relation-filter relation
          :outbound outbound
          :inbound inbound
          :count (+ (length outbound) (length inbound)))))

(defun build-trace-link (&key id relation source-kind source-id target-kind target-id
                              evidence metadata (status :active))
  (let ((timestamp (get-universal-time)))
    (make-trace-link :id (or id (make-trace-link-id))
                     :relation relation
                     :source-kind source-kind
                     :source-id source-id
                     :target-kind target-kind
                     :target-id target-id
                     :status status
                     :created-at timestamp
                     :updated-at timestamp
                     :evidence (copy-list (or evidence '()))
                     :metadata (copy-list (or metadata '())))))

(defun upsert-trace-link (session link)
  (ensure-session-trace-links-slots session)
  (let* ((existing (or (find-trace-link session (trace-link-id link))
                       (find-trace-link-by-shape session
                                                (trace-link-relation link)
                                                (trace-link-source-kind link)
                                                (trace-link-source-id link)
                                                (trace-link-target-kind link)
                                                (trace-link-target-id link))))
         (existing-id (and existing (trace-link-id existing)))
         (updated (build-trace-link :id (or existing-id (trace-link-id link))
                                    :relation (trace-link-relation link)
                                    :source-kind (trace-link-source-kind link)
                                    :source-id (trace-link-source-id link)
                                    :target-kind (trace-link-target-kind link)
                                    :target-id (trace-link-target-id link)
                                    :status (trace-link-status link)
                                    :evidence (trace-link-evidence link)
                                    :metadata (trace-link-metadata link))))
    (when existing
      (setf (trace-link-created-at updated) (trace-link-created-at existing)))
    (setf (trace-link-updated-at updated) (get-universal-time)
          (agent-session-trace-links session)
          (cons updated
                (remove (or existing-id (trace-link-id link))
                        (agent-session-trace-links session)
                        :key #'trace-link-id
                        :test #'string=))
          (agent-session-trace-links-tail session) (last (agent-session-trace-links session)))
    (sync-trace-links-to-environment session)
    updated))

(defun create-trace-link (session &key relation source-kind source-id target-kind target-id
                                  evidence metadata (status :active))
  (upsert-trace-link
   session
   (build-trace-link :relation relation
                     :source-kind source-kind
                     :source-id source-id
                     :target-kind target-kind
                     :target-id target-id
                     :status status
                     :evidence evidence
                     :metadata metadata)))
