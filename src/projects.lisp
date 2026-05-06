(in-package #:sbcl-agent)

(defparameter +environment-project-records-key+ :project-records)
(defparameter +environment-current-project-id-key+ :current-project-id)
(defparameter +project-testing-strategy-key+ :testing-strategy)
(defparameter +project-release-readiness-key+ :release-readiness)
(defparameter +project-readiness-obligations-key+ :readiness-obligations)

(defstruct project-requirement
  id
  title
  summary
  scope
  kind
  priority
  status
  verification-kind
  linked-artifact-ids
  metadata)

(defstruct project-feature-spec
  id
  title
  summary
  status
  acceptance-criteria
  linked-requirement-ids
  linked-journey-ids
  metadata)

(defstruct project-user-journey
  id
  title
  summary
  actors
  entrypoints
  steps
  outcomes
  edge-cases
  metadata)

(defstruct project-architecture-decision
  id
  title
  status
  summary
  drivers
  consequences
  stack-choices
  linked-requirement-ids
  metadata)

(defstruct project-quality-gate
  id
  title
  summary
  status
  required-harness-ids
  minimum-linked-work-items
  minimum-linked-incidents
  require-source-roots-p
  required-trace-target-kinds
  maximum-failed-tests
  require-coverage-p
  maximum-say-turn-latency-seconds
  maximum-environment-save-load-seconds
  require-recovery-ready-p
  metadata)

(defstruct project-record
  id
  title
  summary
  status
  created-at
  updated-at
  constitution
  requirements
  feature-specifications
  design-system
  style-guide
  user-journeys
  non-functional-requirements
  architecture-decisions
  quality-gates
  linked-work-item-ids
  linked-incident-ids
  linked-testing-harness-ids
  source-roots
  metadata)

(defun project-requirement->plist (requirement)
  (list :id (project-requirement-id requirement)
        :title (project-requirement-title requirement)
        :summary (project-requirement-summary requirement)
        :scope (project-requirement-scope requirement)
        :kind (project-requirement-kind requirement)
        :priority (project-requirement-priority requirement)
        :status (project-requirement-status requirement)
        :verification-kind (project-requirement-verification-kind requirement)
        :linked-artifact-ids (copy-list (or (project-requirement-linked-artifact-ids requirement) '()))
        :metadata (copy-list (or (project-requirement-metadata requirement) '()))))

(defun canonicalize-project-requirement-value (value)
  (cond
    ((typep value 'project-requirement) value)
    ((listp value)
     (make-project-requirement :id (getf value :id)
                               :title (getf value :title)
                               :summary (getf value :summary)
                               :scope (getf value :scope)
                               :kind (getf value :kind)
                               :priority (getf value :priority)
                               :status (getf value :status)
                               :verification-kind (getf value :verification-kind)
                               :linked-artifact-ids (copy-list (or (getf value :linked-artifact-ids) '()))
                               :metadata (copy-list (or (getf value :metadata) '()))))
    (t nil)))

(defun project-feature-spec->plist (feature)
  (list :id (project-feature-spec-id feature)
        :title (project-feature-spec-title feature)
        :summary (project-feature-spec-summary feature)
        :status (project-feature-spec-status feature)
        :acceptance-criteria (copy-list (or (project-feature-spec-acceptance-criteria feature) '()))
        :linked-requirement-ids (copy-list (or (project-feature-spec-linked-requirement-ids feature) '()))
        :linked-journey-ids (copy-list (or (project-feature-spec-linked-journey-ids feature) '()))
        :metadata (copy-list (or (project-feature-spec-metadata feature) '()))))

(defun canonicalize-project-feature-spec-value (value)
  (cond
    ((typep value 'project-feature-spec) value)
    ((listp value)
     (make-project-feature-spec :id (getf value :id)
                                :title (getf value :title)
                                :summary (getf value :summary)
                                :status (getf value :status)
                                :acceptance-criteria (copy-list (or (getf value :acceptance-criteria) '()))
                                :linked-requirement-ids (copy-list (or (getf value :linked-requirement-ids) '()))
                                :linked-journey-ids (copy-list (or (getf value :linked-journey-ids) '()))
                                :metadata (copy-list (or (getf value :metadata) '()))))
    (t nil)))

(defun project-user-journey->plist (journey)
  (list :id (project-user-journey-id journey)
        :title (project-user-journey-title journey)
        :summary (project-user-journey-summary journey)
        :actors (copy-list (or (project-user-journey-actors journey) '()))
        :entrypoints (copy-list (or (project-user-journey-entrypoints journey) '()))
        :steps (copy-list (or (project-user-journey-steps journey) '()))
        :outcomes (copy-list (or (project-user-journey-outcomes journey) '()))
        :edge-cases (copy-list (or (project-user-journey-edge-cases journey) '()))
        :metadata (copy-list (or (project-user-journey-metadata journey) '()))))

(defun canonicalize-project-user-journey-value (value)
  (cond
    ((typep value 'project-user-journey) value)
    ((listp value)
     (make-project-user-journey :id (getf value :id)
                                :title (getf value :title)
                                :summary (getf value :summary)
                                :actors (copy-list (or (getf value :actors) '()))
                                :entrypoints (copy-list (or (getf value :entrypoints) '()))
                                :steps (copy-list (or (getf value :steps) '()))
                                :outcomes (copy-list (or (getf value :outcomes) '()))
                                :edge-cases (copy-list (or (getf value :edge-cases) '()))
                                :metadata (copy-list (or (getf value :metadata) '()))))
    (t nil)))

(defun project-architecture-decision->plist (decision)
  (list :id (project-architecture-decision-id decision)
        :title (project-architecture-decision-title decision)
        :status (project-architecture-decision-status decision)
        :summary (project-architecture-decision-summary decision)
        :drivers (copy-list (or (project-architecture-decision-drivers decision) '()))
        :consequences (copy-list (or (project-architecture-decision-consequences decision) '()))
        :stack-choices (copy-list (or (project-architecture-decision-stack-choices decision) '()))
        :linked-requirement-ids (copy-list (or (project-architecture-decision-linked-requirement-ids decision) '()))
        :metadata (copy-list (or (project-architecture-decision-metadata decision) '()))))

(defun canonicalize-project-architecture-decision-value (value)
  (cond
    ((typep value 'project-architecture-decision) value)
    ((listp value)
     (make-project-architecture-decision
      :id (getf value :id)
      :title (getf value :title)
      :status (getf value :status)
      :summary (getf value :summary)
      :drivers (copy-list (or (getf value :drivers) '()))
      :consequences (copy-list (or (getf value :consequences) '()))
      :stack-choices (copy-list (or (getf value :stack-choices) '()))
      :linked-requirement-ids (copy-list (or (getf value :linked-requirement-ids) '()))
      :metadata (copy-list (or (getf value :metadata) '()))))
    (t nil)))

(defun project-quality-gate->plist (gate)
  (list :id (project-quality-gate-id gate)
        :title (project-quality-gate-title gate)
        :summary (project-quality-gate-summary gate)
        :status (project-quality-gate-status gate)
        :required-harness-ids (copy-list (or (project-quality-gate-required-harness-ids gate) '()))
        :minimum-linked-work-items (project-quality-gate-minimum-linked-work-items gate)
        :minimum-linked-incidents (project-quality-gate-minimum-linked-incidents gate)
        :require-source-roots-p (project-quality-gate-require-source-roots-p gate)
        :required-trace-target-kinds (copy-list (or (project-quality-gate-required-trace-target-kinds gate) '()))
        :maximum-failed-tests (project-quality-gate-maximum-failed-tests gate)
        :require-coverage-p (project-quality-gate-require-coverage-p gate)
        :maximum-say-turn-latency-seconds (project-quality-gate-maximum-say-turn-latency-seconds gate)
        :maximum-environment-save-load-seconds (project-quality-gate-maximum-environment-save-load-seconds gate)
        :require-recovery-ready-p (project-quality-gate-require-recovery-ready-p gate)
        :metadata (copy-list (or (project-quality-gate-metadata gate) '()))))

(defun canonicalize-project-quality-gate-value (value)
  (cond
    ((typep value 'project-quality-gate) value)
    ((listp value)
     (make-project-quality-gate
      :id (getf value :id)
      :title (getf value :title)
      :summary (getf value :summary)
      :status (getf value :status)
      :required-harness-ids (copy-list (or (getf value :required-harness-ids) '()))
      :minimum-linked-work-items (getf value :minimum-linked-work-items)
      :minimum-linked-incidents (getf value :minimum-linked-incidents)
      :require-source-roots-p (getf value :require-source-roots-p)
      :required-trace-target-kinds (copy-list (or (getf value :required-trace-target-kinds) '()))
      :maximum-failed-tests (getf value :maximum-failed-tests)
      :require-coverage-p (getf value :require-coverage-p)
      :maximum-say-turn-latency-seconds (getf value :maximum-say-turn-latency-seconds)
      :maximum-environment-save-load-seconds (getf value :maximum-environment-save-load-seconds)
      :require-recovery-ready-p (getf value :require-recovery-ready-p)
      :metadata (copy-list (or (getf value :metadata) '()))))
    (t nil)))

(defun project-record->plist (project)
  (append (project-summary project)
          (list :source-roots (copy-project-string-list (project-record-source-roots project))
                :constitution (copy-list (or (project-record-constitution project) '()))
                :requirements (mapcar #'project-requirement->plist
                                      (or (project-record-requirements project) '()))
                :feature-specifications (mapcar #'project-feature-spec->plist
                                                (or (project-record-feature-specifications project) '()))
                :design-system (copy-list (or (project-record-design-system project) '()))
                :style-guide (copy-list (or (project-record-style-guide project) '()))
                :user-journeys (mapcar #'project-user-journey->plist
                                       (or (project-record-user-journeys project) '()))
                :non-functional-requirements (mapcar #'project-requirement->plist
                                                     (or (project-record-non-functional-requirements project) '()))
                :architecture-decisions (mapcar #'project-architecture-decision->plist
                                                (or (project-record-architecture-decisions project) '()))
                :quality-gates (mapcar #'project-quality-gate->plist
                                       (or (project-record-quality-gates project) '()))
                :linked-work-item-ids (copy-project-string-list (project-record-linked-work-item-ids project))
                :linked-incident-ids (copy-project-string-list (project-record-linked-incident-ids project))
                :linked-testing-harness-ids (copy-project-symbol-list (project-record-linked-testing-harness-ids project))
                :metadata (copy-list (or (project-record-metadata project) '())))))

(defun canonicalize-project-record-value (value)
  (cond
    ((typep value 'project-record) value)
    ((listp value)
     (let ((project (build-project-record
                     :id (getf value :id)
                     :title (getf value :title)
                     :summary (getf value :summary)
                     :constitution (getf value :constitution)
                     :requirements (remove nil (mapcar #'canonicalize-project-requirement-value
                                                       (or (getf value :requirements) '())))
                     :feature-specifications (remove nil
                                                     (mapcar #'canonicalize-project-feature-spec-value
                                                             (or (getf value :feature-specifications) '())))
                     :design-system (getf value :design-system)
                     :style-guide (getf value :style-guide)
                     :user-journeys (remove nil (mapcar #'canonicalize-project-user-journey-value
                                                        (or (getf value :user-journeys) '())))
                     :non-functional-requirements (remove nil
                                                          (mapcar #'canonicalize-project-requirement-value
                                                                  (or (getf value :non-functional-requirements) '())))
                     :architecture-decisions (remove nil
                                                     (mapcar #'canonicalize-project-architecture-decision-value
                                                             (or (getf value :architecture-decisions) '())))
                     :quality-gates (remove nil (mapcar #'canonicalize-project-quality-gate-value
                                                        (or (getf value :quality-gates) '())))
                     :linked-work-item-ids (getf value :linked-work-item-ids)
                     :linked-incident-ids (getf value :linked-incident-ids)
                     :linked-testing-harness-ids (getf value :linked-testing-harness-ids)
                     :source-roots (getf value :source-roots)
                     :metadata (getf value :metadata)
                     :status (or (getf value :status) :active))))
       (when (getf value :created-at)
         (setf (project-record-created-at project) (getf value :created-at)))
       (when (getf value :updated-at)
         (setf (project-record-updated-at project) (getf value :updated-at)))
       project))
    (t nil)))

(defun sync-projects-to-environment (session)
  (let ((environment (ignore-errors (session-bound-environment session))))
    (when environment
      (setf (getf (environment-metadata environment) +environment-project-records-key+)
            (mapcar #'project-record->plist
                    (or (agent-session-projects session) '()))
            (getf (environment-metadata environment) +environment-current-project-id-key+)
            (agent-session-current-project-id session))))
  session)

(defun copy-project-string-list (values)
  (copy-list
   (remove-duplicates
    (remove-if-not #'stringp (or values '()))
    :test #'string=)))

(defun copy-project-symbol-list (values)
  (copy-list
   (remove-duplicates
    (remove-if-not #'symbolp (or values '()))
    :test #'eq)))

(defun make-generated-project-id (&optional (prefix "project"))
  (format nil "~A-~D-~D"
          prefix
          (get-universal-time)
          (random 1000000)))

(defun ensure-projects-session-slots (session)
  (let ((environment (ignore-errors (session-bound-environment session))))
    (when (and environment
               (null (agent-session-projects session))
               (listp (getf (environment-metadata environment) +environment-project-records-key+)))
      (setf (agent-session-projects session)
            (remove nil
                    (mapcar #'canonicalize-project-record-value
                            (getf (environment-metadata environment) +environment-project-records-key+)))))
    (when (and environment
               (null (agent-session-current-project-id session))
               (stringp (getf (environment-metadata environment) +environment-current-project-id-key+)))
      (setf (agent-session-current-project-id session)
            (getf (environment-metadata environment) +environment-current-project-id-key+))))
  (unless (listp (agent-session-projects session))
    (setf (agent-session-projects session) '()))
  (unless (or (null (agent-session-projects-tail session))
              (consp (agent-session-projects-tail session)))
    (setf (agent-session-projects-tail session) nil))
  session)

(defun list-project-records (session)
  (ensure-projects-session-slots session)
  (copy-list (or (agent-session-projects session) '())))

(defun find-project-record (session project-id)
  (find project-id
        (list-project-records session)
        :key #'project-record-id
        :test #'string=))

(defun current-project-record (session)
  (let ((current-id (agent-session-current-project-id session)))
    (or (and current-id (find-project-record session current-id))
        (first (list-project-records session)))))

(defun project-summary (project)
  (list :id (project-record-id project)
        :title (project-record-title project)
        :summary (project-record-summary project)
        :status (project-record-status project)
        :created-at (project-record-created-at project)
        :updated-at (project-record-updated-at project)
        :requirement-count (length (or (project-record-requirements project) '()))
        :feature-spec-count (length (or (project-record-feature-specifications project) '()))
        :journey-count (length (or (project-record-user-journeys project) '()))
        :architecture-decision-count (length (or (project-record-architecture-decisions project) '()))
        :quality-gate-count (length (or (project-record-quality-gates project) '()))
        :nfr-count (length (or (project-record-non-functional-requirements project) '()))
        :linked-work-item-count (length (or (project-record-linked-work-item-ids project) '()))
        :linked-incident-count (length (or (project-record-linked-incident-ids project) '()))
        :linked-testing-harness-count (length (or (project-record-linked-testing-harness-ids project) '()))
        :source-roots (copy-list (or (project-record-source-roots project) '()))))

(defun project-detail (project)
  (append (project-summary project)
          (list :constitution (copy-list (or (project-record-constitution project) '()))
                :requirements (mapcar #'project-requirement->plist
                                      (or (project-record-requirements project) '()))
                :feature-specifications (mapcar #'project-feature-spec->plist
                                                (or (project-record-feature-specifications project) '()))
                :design-system (copy-list (or (project-record-design-system project) '()))
                :style-guide (copy-list (or (project-record-style-guide project) '()))
                :user-journeys (mapcar #'project-user-journey->plist
                                       (or (project-record-user-journeys project) '()))
                :non-functional-requirements (mapcar #'project-requirement->plist
                                                     (or (project-record-non-functional-requirements project) '()))
                :architecture-decisions (mapcar #'project-architecture-decision->plist
                                                (or (project-record-architecture-decisions project) '()))
                :quality-gates (mapcar #'project-quality-gate->plist
                                       (or (project-record-quality-gates project) '()))
                :linked-work-item-ids (copy-project-string-list (project-record-linked-work-item-ids project))
                :linked-incident-ids (copy-project-string-list (project-record-linked-incident-ids project))
                :linked-testing-harness-ids (copy-project-symbol-list (project-record-linked-testing-harness-ids project))
                :testing-strategy (copy-list (or (getf (project-record-metadata project) +project-testing-strategy-key+) '()))
                :release-readiness (copy-list (or (getf (project-record-metadata project) +project-release-readiness-key+) '()))
                :readiness-obligations (copy-list (or (getf (project-record-metadata project) +project-readiness-obligations-key+) '()))
                :metadata (copy-list (or (project-record-metadata project) '())))))

(defun build-project-record (&key id title summary constitution requirements feature-specifications
                                  design-system style-guide user-journeys
                                  non-functional-requirements architecture-decisions
                                  quality-gates
                                  linked-work-item-ids linked-incident-ids
                                  linked-testing-harness-ids
                                  source-roots metadata (status :active))
  (let ((timestamp (get-universal-time)))
    (make-project-record :id (or id (make-generated-project-id))
                         :title (or title "Untitled Project")
                         :summary (or summary "Governed project record.")
                         :status status
                         :created-at timestamp
                         :updated-at timestamp
                         :constitution (copy-list (or constitution '()))
                         :requirements (remove nil
                                               (mapcar #'canonicalize-project-requirement-value
                                                       (or requirements '())))
                         :feature-specifications (remove nil
                                                         (mapcar #'canonicalize-project-feature-spec-value
                                                                 (or feature-specifications '())))
                         :design-system (copy-list (or design-system '()))
                         :style-guide (copy-list (or style-guide '()))
                         :user-journeys (remove nil
                                                (mapcar #'canonicalize-project-user-journey-value
                                                        (or user-journeys '())))
                         :non-functional-requirements (copy-list (or non-functional-requirements '()))
                         :architecture-decisions (remove nil
                                                         (mapcar #'canonicalize-project-architecture-decision-value
                                                                 (or architecture-decisions '())))
                         :quality-gates (remove nil
                                                (mapcar #'canonicalize-project-quality-gate-value
                                                        (or quality-gates '())))
                         :linked-work-item-ids (copy-project-string-list linked-work-item-ids)
                         :linked-incident-ids (copy-project-string-list linked-incident-ids)
                         :linked-testing-harness-ids (copy-project-symbol-list linked-testing-harness-ids)
                         :source-roots (copy-project-string-list source-roots)
                         :metadata (copy-list (or metadata '())))))

(defun upsert-project-record (session project)
  (ensure-projects-session-slots session)
  (let* ((existing (agent-session-projects session))
         (project-id (project-record-id project))
         (preserved (find-project-record session project-id))
         (updated (build-project-record
                   :id project-id
                   :title (project-record-title project)
                   :summary (project-record-summary project)
                   :constitution (project-record-constitution project)
                   :requirements (project-record-requirements project)
                   :feature-specifications (project-record-feature-specifications project)
                   :design-system (project-record-design-system project)
                   :style-guide (project-record-style-guide project)
                   :user-journeys (project-record-user-journeys project)
                   :non-functional-requirements (project-record-non-functional-requirements project)
                   :architecture-decisions (project-record-architecture-decisions project)
                   :quality-gates (project-record-quality-gates project)
                   :linked-work-item-ids (project-record-linked-work-item-ids project)
                   :linked-incident-ids (project-record-linked-incident-ids project)
                   :linked-testing-harness-ids (project-record-linked-testing-harness-ids project)
                   :source-roots (project-record-source-roots project)
                   :metadata (project-record-metadata project)
                   :status (project-record-status project))))
    (when preserved
      (setf (project-record-created-at updated) (project-record-created-at preserved)))
    (setf (project-record-updated-at updated) (get-universal-time)
          (agent-session-projects session)
          (cons updated
                (remove project-id existing :key #'project-record-id :test #'string=))
          (agent-session-projects-tail session) (last (agent-session-projects session))
          (agent-session-current-project-id session) project-id)
    (sync-projects-to-environment session)
    updated))

(defun create-project-record (session &key title summary constitution requirements feature-specifications
                                       design-system style-guide user-journeys
                                       non-functional-requirements architecture-decisions
                                       quality-gates
                                       linked-work-item-ids linked-incident-ids
                                       linked-testing-harness-ids
                                       source-roots metadata)
  (upsert-project-record
   session
   (build-project-record :title title
                         :summary summary
                         :constitution constitution
                         :requirements requirements
                         :feature-specifications feature-specifications
                         :design-system design-system
                         :style-guide style-guide
                         :user-journeys user-journeys
                         :non-functional-requirements non-functional-requirements
                         :architecture-decisions architecture-decisions
                         :quality-gates quality-gates
                         :linked-work-item-ids linked-work-item-ids
                         :linked-incident-ids linked-incident-ids
                         :linked-testing-harness-ids linked-testing-harness-ids
                         :source-roots source-roots
                         :metadata metadata)))

(defun select-project-record (session project-id)
  (let ((project (find-project-record session project-id)))
    (unless project
      (error "Unknown project ~A" project-id))
    (setf (agent-session-current-project-id session) project-id)
    (sync-projects-to-environment session)
    project))

(defun ensure-project-record (session &optional project-id)
  (let ((project (if project-id
                     (find-project-record session project-id)
                     (current-project-record session))))
    (unless project
      (error "No project is currently selected."))
    project))

(defun update-project-record (session project-id updater)
  (let* ((project (ensure-project-record session project-id))
         (updated (funcall updater project)))
    (upsert-project-record session updated)))

(defun set-project-constitution (session constitution &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-constitution project) (copy-list (or constitution '())))
     project)))

(defun set-project-design-system (session design-system &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-design-system project) (copy-list (or design-system '())))
     project)))

(defun set-project-style-guide (session style-guide &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-style-guide project) (copy-list (or style-guide '())))
     project)))

(defun set-project-testing-strategy (session testing-strategy &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (getf (project-record-metadata project) +project-testing-strategy-key+)
           (copy-list (or testing-strategy '())))
     project)))

(defun set-project-release-readiness (session release-readiness &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (getf (project-record-metadata project) +project-release-readiness-key+)
           (copy-list (or release-readiness '())))
     project)))

(defun set-project-readiness-obligations (session readiness-obligations &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (getf (project-record-metadata project) +project-readiness-obligations-key+)
           (copy-list (or readiness-obligations '())))
     project)))

(defun append-project-requirement (session requirement &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-requirements project)
           (append (or (project-record-requirements project) '())
                   (list requirement)))
     project)))

(defun append-project-feature-specification (session feature-spec &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-feature-specifications project)
           (append (or (project-record-feature-specifications project) '())
                   (list feature-spec)))
     project)))

(defun append-project-user-journey (session journey &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-user-journeys project)
           (append (or (project-record-user-journeys project) '())
                   (list journey)))
     project)))

(defun append-project-architecture-decision (session decision &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-architecture-decisions project)
           (append (or (project-record-architecture-decisions project) '())
                   (list decision)))
     project)))

(defun append-project-quality-gate (session quality-gate &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-quality-gates project)
           (append (or (project-record-quality-gates project) '())
                   (list quality-gate)))
     project)))

(defun append-project-work-item-binding (session work-item-id &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-linked-work-item-ids project)
           (copy-project-string-list
            (append (or (project-record-linked-work-item-ids project) '())
                    (list work-item-id))))
     project)))

(defun append-project-incident-binding (session incident-id &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-linked-incident-ids project)
           (copy-project-string-list
            (append (or (project-record-linked-incident-ids project) '())
                    (list incident-id))))
     project)))

(defun append-project-testing-harness-binding (session harness-id &optional project-id)
  (update-project-record
   session
     project-id
     (lambda (project)
       (setf (project-record-linked-testing-harness-ids project)
           (copy-project-symbol-list
            (append (or (project-record-linked-testing-harness-ids project) '())
                    (list harness-id))))
     project)))

(defun append-project-source-root (session source-root &optional project-id)
  (update-project-record
   session
   project-id
   (lambda (project)
     (setf (project-record-source-roots project)
           (copy-project-string-list
            (append (or (project-record-source-roots project) '())
                    (list source-root))))
     project)))
