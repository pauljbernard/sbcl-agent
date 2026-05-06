(in-package #:sbcl-agent)

(defparameter +environment-intent-records-key+ :intent-records)
(defparameter +environment-current-intent-id-key+ :current-intent-id)

(defstruct intent-record
  id
  description
  scope
  constraints
  expected-behaviors
  non-goals
  priority
  version
  status
  linked-runtime-objects
  linked-source-artifacts
  linked-event-ids
  linked-mutation-ids
  metadata
  created-at
  updated-at)

(defun make-generated-intent-id ()
  (format nil "intent-~D-~D" (get-universal-time) (random 1000000)))

(defun copy-intent-string-list (entries)
  (copy-list (or entries '())))

(defun copy-intent-scope (scope)
  (copy-tree (or scope '())))

(defun canonical-intent-status (value)
  (cond
    ((keywordp value) value)
    ((stringp value)
     (intern (string-upcase (substitute #\- #\_ (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
             "KEYWORD"))
    (t :active)))

(defun canonical-intent-priority (value)
  (cond
    ((keywordp value) value)
    ((stringp value)
     (intern (string-upcase (substitute #\- #\_ (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
             "KEYWORD"))
    ((numberp value) value)
    (t :normal)))

(defun canonicalize-intent-scope (scope)
  (let ((value (or scope '())))
    (cond
      ((and (listp value) (evenp (length value)) (keywordp (first value)))
       (list :symbols (copy-intent-string-list (getf value :symbols))
             :systems (copy-intent-string-list (getf value :systems))
             :workflows (copy-intent-string-list (getf value :workflows))))
      ((listp value)
       (list :symbols '()
             :systems '()
             :workflows (copy-intent-string-list value)))
      (t
       (list :symbols '() :systems '() :workflows '())))))

(defun canonicalize-intent-record-value (value)
  (cond
    ((typep value 'intent-record) value)
    ((listp value)
     (make-intent-record
      :id (or (getf value :id) (make-generated-intent-id))
      :description (or (getf value :description) "")
      :scope (canonicalize-intent-scope (getf value :scope))
      :constraints (copy-tree (or (getf value :constraints) '()))
      :expected-behaviors (copy-intent-string-list (getf value :expected-behaviors))
      :non-goals (copy-intent-string-list (getf value :non-goals))
      :priority (canonical-intent-priority (getf value :priority))
      :version (or (getf value :version) 1)
      :status (canonical-intent-status (getf value :status))
      :linked-runtime-objects (copy-intent-string-list (getf value :linked-runtime-objects))
      :linked-source-artifacts (copy-intent-string-list (getf value :linked-source-artifacts))
      :linked-event-ids (copy-intent-string-list (getf value :linked-event-ids))
      :linked-mutation-ids (copy-intent-string-list (getf value :linked-mutation-ids))
      :metadata (copy-tree (or (getf value :metadata) '()))
      :created-at (or (getf value :created-at) (get-universal-time))
      :updated-at (or (getf value :updated-at) (get-universal-time))))
    (t nil)))

(defun intent-record->plist (intent)
  (list :id (intent-record-id intent)
        :description (intent-record-description intent)
        :scope (copy-intent-scope (intent-record-scope intent))
        :constraints (copy-tree (or (intent-record-constraints intent) '()))
        :expected-behaviors (copy-intent-string-list (intent-record-expected-behaviors intent))
        :non-goals (copy-intent-string-list (intent-record-non-goals intent))
        :priority (intent-record-priority intent)
        :version (intent-record-version intent)
        :status (intent-record-status intent)
        :linked-runtime-objects (copy-intent-string-list (intent-record-linked-runtime-objects intent))
        :linked-source-artifacts (copy-intent-string-list (intent-record-linked-source-artifacts intent))
        :linked-event-ids (copy-intent-string-list (intent-record-linked-event-ids intent))
        :linked-mutation-ids (copy-intent-string-list (intent-record-linked-mutation-ids intent))
        :metadata (copy-tree (or (intent-record-metadata intent) '()))
        :created-at (intent-record-created-at intent)
        :updated-at (intent-record-updated-at intent)))

(defun persist-intent-records (environment records current-id)
  (setf (getf (environment-metadata environment) +environment-intent-records-key+)
        (mapcar #'intent-record->plist records)
        (getf (environment-metadata environment) +environment-current-intent-id-key+)
        current-id)
  records)

(defun load-intent-records (environment)
  (let ((active-environment (ensure-environment environment)))
    (unless (and (listp (getf (environment-metadata active-environment) +environment-intent-records-key+))
                 (every #'listp (getf (environment-metadata active-environment) +environment-intent-records-key+)))
      (persist-intent-records active-environment '() nil))
    (mapcar #'canonicalize-intent-record-value
            (getf (environment-metadata active-environment) +environment-intent-records-key+))))

(defun current-intent-id (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (unless (stringp (getf (environment-metadata active-environment) +environment-current-intent-id-key+))
      (setf (getf (environment-metadata active-environment) +environment-current-intent-id-key+) nil))
    (getf (environment-metadata active-environment) +environment-current-intent-id-key+)))

(defun list-intent-records (session)
  (load-intent-records (or (session-bound-environment session)
                           (ensure-environment))))

(defun find-intent-record (session intent-id)
  (find intent-id (list-intent-records session)
        :key #'intent-record-id
        :test #'string=))

(defun current-intent-record (session)
  (let ((current-id (current-intent-id (session-bound-environment session))))
    (or (and current-id (find-intent-record session current-id))
        (first (list-intent-records session)))))

(defun intent-record-summary (intent)
  (list :id (intent-record-id intent)
        :description (intent-record-description intent)
        :status (intent-record-status intent)
        :priority (intent-record-priority intent)
        :version (intent-record-version intent)
        :scope-summary (list :symbol-count (length (or (getf (intent-record-scope intent) :symbols) '()))
                             :system-count (length (or (getf (intent-record-scope intent) :systems) '()))
                             :workflow-count (length (or (getf (intent-record-scope intent) :workflows) '())))
        :linked-runtime-object-count (length (or (intent-record-linked-runtime-objects intent) '()))
        :linked-source-artifact-count (length (or (intent-record-linked-source-artifacts intent) '()))
        :linked-event-count (length (or (intent-record-linked-event-ids intent) '()))
        :linked-mutation-count (length (or (intent-record-linked-mutation-ids intent) '()))
        :created-at (intent-record-created-at intent)
        :updated-at (intent-record-updated-at intent)))

(defun intent-record-detail (intent &key currentp)
  (append (intent-record-summary intent)
          (list :scope (copy-intent-scope (intent-record-scope intent))
                :constraints (copy-tree (or (intent-record-constraints intent) '()))
                :expected-behaviors (copy-intent-string-list (intent-record-expected-behaviors intent))
                :non-goals (copy-intent-string-list (intent-record-non-goals intent))
                :linked-runtime-objects (copy-intent-string-list (intent-record-linked-runtime-objects intent))
                :linked-source-artifacts (copy-intent-string-list (intent-record-linked-source-artifacts intent))
                :linked-event-ids (copy-intent-string-list (intent-record-linked-event-ids intent))
                :linked-mutation-ids (copy-intent-string-list (intent-record-linked-mutation-ids intent))
                :metadata (copy-tree (or (intent-record-metadata intent) '()))
                :current-p (and currentp t))))

(defun intent-record-diff (before after)
  (let* ((before-intent (canonicalize-intent-record-value before))
         (after-intent (canonicalize-intent-record-value after))
         (fields '(:description :scope :constraints :expected-behaviors :non-goals
                   :priority :version :status :linked-runtime-objects
                   :linked-source-artifacts :linked-event-ids :linked-mutation-ids
                   :metadata)))
    (remove nil
            (mapcar (lambda (field)
                      (let ((before-value (getf (intent-record->plist before-intent) field))
                            (after-value (getf (intent-record->plist after-intent) field)))
                        (unless (equal before-value after-value)
                          (list :field field
                                :before before-value
                                :after after-value))))
                    fields))))

(defun intent-linked-trace-targets (intent)
  (append (mapcar (lambda (runtime-object)
                    (list :relation :constrains
                          :target-kind :runtime-object
                          :target-id runtime-object))
                  (or (intent-record-linked-runtime-objects intent) '()))
          (mapcar (lambda (source-artifact)
                    (list :relation :constrains
                          :target-kind :source-artifact
                          :target-id source-artifact))
                  (or (intent-record-linked-source-artifacts intent) '()))
          (mapcar (lambda (event-id)
                    (list :relation :observes
                          :target-kind :event
                          :target-id event-id))
                  (or (intent-record-linked-event-ids intent) '()))
          (mapcar (lambda (mutation-id)
                    (list :relation :governs
                          :target-kind :mutation
                          :target-id mutation-id))
                  (or (intent-record-linked-mutation-ids intent) '()))))

(defun sync-intent-trace-links (session intent)
  (dolist (target (intent-linked-trace-targets intent))
    (create-trace-link session
                       :relation (getf target :relation)
                       :source-kind :intent
                       :source-id (intent-record-id intent)
                       :target-kind (getf target :target-kind)
                       :target-id (getf target :target-id)
                       :metadata (list :origin :intent-record-sync
                                       :intent-version (intent-record-version intent)
                                       :intent-status (intent-record-status intent))))
  intent)

(defun build-intent-record (&key id description scope constraints expected-behaviors
                                 non-goals priority version status linked-runtime-objects
                                 linked-source-artifacts linked-event-ids linked-mutation-ids metadata)
  (canonicalize-intent-record-value
   (list :id id
         :description description
         :scope scope
         :constraints constraints
         :expected-behaviors expected-behaviors
         :non-goals non-goals
         :priority priority
         :version version
         :status status
         :linked-runtime-objects linked-runtime-objects
         :linked-source-artifacts linked-source-artifacts
         :linked-event-ids linked-event-ids
         :linked-mutation-ids linked-mutation-ids
         :metadata metadata)))

(defun upsert-intent-record (session intent)
  (let* ((environment (or (session-bound-environment session)
                          (ensure-environment)))
         (existing (load-intent-records environment))
         (intent-id (intent-record-id intent))
         (preserved (find intent-id existing :key #'intent-record-id :test #'string=))
         (updated (build-intent-record
                   :id intent-id
                   :description (intent-record-description intent)
                   :scope (intent-record-scope intent)
                   :constraints (intent-record-constraints intent)
                   :expected-behaviors (intent-record-expected-behaviors intent)
                   :non-goals (intent-record-non-goals intent)
                   :priority (intent-record-priority intent)
                   :version (intent-record-version intent)
                   :status (intent-record-status intent)
                   :linked-runtime-objects (intent-record-linked-runtime-objects intent)
                   :linked-source-artifacts (intent-record-linked-source-artifacts intent)
                   :linked-event-ids (intent-record-linked-event-ids intent)
                   :linked-mutation-ids (intent-record-linked-mutation-ids intent)
                   :metadata (intent-record-metadata intent))))
    (when preserved
      (setf (intent-record-created-at updated) (intent-record-created-at preserved)))
    (setf (intent-record-updated-at updated) (get-universal-time)
          (intent-record-created-at updated) (or (intent-record-created-at updated)
                                                 (get-universal-time)))
    (persist-intent-records environment
                            (append (remove intent-id existing :key #'intent-record-id :test #'string=)
                                    (list updated))
                            (or (current-intent-id environment)
                                (intent-record-id updated)))
    (sync-intent-trace-links session updated)
    updated))

(defun create-intent-record (session &key description scope constraints expected-behaviors
                                  non-goals priority (version 1) (status :active)
                                  linked-runtime-objects linked-source-artifacts
                                  linked-event-ids linked-mutation-ids metadata)
  (let ((intent (upsert-intent-record
                 session
                 (build-intent-record :id (make-generated-intent-id)
                                      :description description
                                      :scope scope
                                      :constraints constraints
                                      :expected-behaviors expected-behaviors
                                      :non-goals non-goals
                                      :priority priority
                                      :version version
                                      :status status
                                      :linked-runtime-objects linked-runtime-objects
                                      :linked-source-artifacts linked-source-artifacts
                                      :linked-event-ids linked-event-ids
                                      :linked-mutation-ids linked-mutation-ids
                                      :metadata metadata))))
    (select-intent-record session (intent-record-id intent))
    intent))

(defun select-intent-record (session intent-id)
  (let* ((environment (or (session-bound-environment session)
                          (ensure-environment)))
         (intent (find-intent-record session intent-id)))
    (unless intent
      (error "Unknown intent ~A" intent-id))
    (persist-intent-records environment (load-intent-records environment) intent-id)
    intent))

(defun update-intent-record (session intent-id updater)
  (let* ((intent (or (find-intent-record session intent-id)
                     (error "Unknown intent ~A" intent-id)))
         (updated (funcall updater intent)))
    (upsert-intent-record session updated)))
