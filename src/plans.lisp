(in-package #:sbcl-agent)

(defstruct plan-step
  id
  kind
  status
  goal
  depends-on
  capability-query
  resolved-capability
  assigned-actor
  execution-id
  verification-status
  repair-count
  result-summary
  created-at
  updated-at
  evidence)

(defstruct plan-record
  id
  parent-plan-id
  goal
  status
  scope
  created-at
  updated-at
  steps
  selected-capabilities
  verification-policy
  repair-policy
  evidence
  workflow-record-id
  work-item-id
  assigned-actors)

(defun make-plan-record-id ()
  (format nil "plan-~D-~D" (get-universal-time) (random 1000000)))

(defun make-plan-step-id ()
  (format nil "plan-step-~D-~D" (get-universal-time) (random 1000000)))

(defun create-plan-step (goal &key kind depends-on capability-query resolved-capability assigned-actor
                                execution-id verification-status result-summary evidence
                                (status :pending))
  (let ((timestamp (get-universal-time)))
    (make-plan-step
     :id (make-plan-step-id)
     :kind (or kind :execute)
     :status status
     :goal goal
     :depends-on (copy-list (or depends-on '()))
     :capability-query (copy-tree capability-query)
     :resolved-capability (copy-tree resolved-capability)
     :assigned-actor (copy-tree assigned-actor)
     :execution-id execution-id
     :verification-status verification-status
     :repair-count 0
     :result-summary result-summary
     :created-at timestamp
     :updated-at timestamp
     :evidence (copy-list (or evidence '())))))

(defun create-plan-record (goal &key parent-plan-id scope steps selected-capabilities
                                 verification-policy repair-policy evidence workflow-record-id
                                 work-item-id assigned-actors
                                 (status :open))
  (let ((timestamp (get-universal-time)))
    (make-plan-record
     :id (make-plan-record-id)
     :parent-plan-id parent-plan-id
     :goal goal
     :status status
     :scope (copy-tree scope)
     :created-at timestamp
     :updated-at timestamp
     :steps (copy-list (or steps '()))
     :selected-capabilities (copy-list (or selected-capabilities '()))
     :verification-policy (copy-tree verification-policy)
     :repair-policy (copy-tree repair-policy)
     :evidence (copy-list (or evidence '()))
     :workflow-record-id workflow-record-id
     :work-item-id work-item-id
     :assigned-actors (copy-list (or assigned-actors '())))))

(defun plan-step-summary (step)
  (list :id (plan-step-id step)
        :kind (plan-step-kind step)
        :status (plan-step-status step)
        :goal (plan-step-goal step)
        :depends-on (copy-list (or (plan-step-depends-on step) '()))
        :capability-query (copy-tree (plan-step-capability-query step))
        :resolved-capability (copy-tree (plan-step-resolved-capability step))
        :assigned-actor (copy-tree (plan-step-assigned-actor step))
        :execution-id (plan-step-execution-id step)
        :verification-status (plan-step-verification-status step)
        :repair-count (plan-step-repair-count step)
        :result-summary (plan-step-result-summary step)
        :created-at (plan-step-created-at step)
        :updated-at (plan-step-updated-at step)))

(defun plan-step-detail (step)
  (append (plan-step-summary step)
          (list :evidence (copy-list (or (plan-step-evidence step) '())))))

(defun plan-record-summary (plan)
  (list :id (plan-record-id plan)
        :parent-plan-id (plan-record-parent-plan-id plan)
        :goal (plan-record-goal plan)
        :status (plan-record-status plan)
        :scope (copy-tree (plan-record-scope plan))
        :created-at (plan-record-created-at plan)
        :updated-at (plan-record-updated-at plan)
        :step-count (length (plan-record-steps plan))
        :selected-capabilities (copy-list (or (plan-record-selected-capabilities plan) '()))
        :verification-policy (copy-tree (plan-record-verification-policy plan))
        :repair-policy (copy-tree (plan-record-repair-policy plan))
        :workflow-record-id (plan-record-workflow-record-id plan)
        :work-item-id (plan-record-work-item-id plan)
        :assigned-actors (copy-list (or (plan-record-assigned-actors plan) '()))))

(defun plan-record-detail (plan)
  (append (plan-record-summary plan)
          (list :steps (mapcar #'plan-step-detail (plan-record-steps plan))
                :evidence (copy-list (or (plan-record-evidence plan) '())))))

(defun find-plan-step (plan step-id)
  (find step-id (plan-record-steps plan)
        :key #'plan-step-id
        :test #'string=))

(defun append-plan-step (plan step)
  (setf (plan-record-steps plan)
        (append (plan-record-steps plan) (list step))
        (plan-record-updated-at plan) (get-universal-time))
  step)

(defun append-plan-evidence (plan evidence)
  (setf (plan-record-evidence plan)
        (append (plan-record-evidence plan) (list evidence))
        (plan-record-updated-at plan) (get-universal-time))
  evidence)

(defun append-plan-step-evidence (step evidence)
  (setf (plan-step-evidence step)
        (append (plan-step-evidence step) (list evidence))
        (plan-step-updated-at step) (get-universal-time))
  evidence)

(defun update-plan-status (plan status &key result-summary)
  (setf (plan-record-status plan) status
        (plan-record-updated-at plan) (get-universal-time))
  (when result-summary
    (append-plan-evidence plan (list :kind :status-update
                                     :status status
                                     :summary result-summary
                                     :timestamp (get-universal-time))))
  plan)

(defun update-plan-step-status (step status &key verification-status result-summary execution-id)
  (setf (plan-step-status step) status
        (plan-step-updated-at step) (get-universal-time))
  (when verification-status
    (setf (plan-step-verification-status step) verification-status))
  (when result-summary
    (setf (plan-step-result-summary step) result-summary))
  (when execution-id
    (setf (plan-step-execution-id step) execution-id))
  step)

(defun increment-plan-step-repair-count (step)
  (incf (plan-step-repair-count step))
  (setf (plan-step-updated-at step) (get-universal-time))
  step)

(defun normalize-plan-step (step)
  (cond
    ((null step) nil)
    ((typep step 'plan-step) step)
    ((and (listp step)
          (or (getf step :goal)
              (getf step :id)))
     (make-plan-step
      :id (or (getf step :id) (make-plan-step-id))
      :kind (or (getf step :kind) :execute)
      :status (or (getf step :status) :pending)
      :goal (getf step :goal)
      :depends-on (copy-list (or (getf step :depends-on) '()))
      :capability-query (copy-tree (getf step :capability-query))
      :resolved-capability (copy-tree (getf step :resolved-capability))
      :assigned-actor (copy-tree (getf step :assigned-actor))
      :execution-id (getf step :execution-id)
      :verification-status (getf step :verification-status)
      :repair-count (or (getf step :repair-count) 0)
      :result-summary (getf step :result-summary)
      :created-at (or (getf step :created-at) (get-universal-time))
      :updated-at (or (getf step :updated-at) (get-universal-time))
      :evidence (copy-list (or (getf step :evidence) '()))))
    (t
     (error "Invalid legacy plan step ~S" step))))

(defun normalize-plan-record (plan)
  (cond
    ((null plan) nil)
    ((typep plan 'plan-record) plan)
    ((stringp plan)
     (create-plan-record plan))
    ((and (listp plan)
          (or (getf plan :goal)
              (getf plan :id)))
     (make-plan-record
      :id (or (getf plan :id) (make-plan-record-id))
      :parent-plan-id (getf plan :parent-plan-id)
      :goal (or (getf plan :goal) "Recovered legacy plan")
      :status (or (getf plan :status) :open)
      :scope (copy-tree (getf plan :scope))
      :created-at (or (getf plan :created-at) (get-universal-time))
      :updated-at (or (getf plan :updated-at) (get-universal-time))
      :steps (mapcar #'normalize-plan-step (or (getf plan :steps) '()))
      :selected-capabilities (copy-list (or (getf plan :selected-capabilities) '()))
      :verification-policy (copy-tree (getf plan :verification-policy))
      :repair-policy (copy-tree (getf plan :repair-policy))
      :evidence (copy-list (or (getf plan :evidence) '()))
      :workflow-record-id (getf plan :workflow-record-id)
      :work-item-id (getf plan :work-item-id)
      :assigned-actors (copy-list (or (getf plan :assigned-actors) '()))))
    (t
     (error "Invalid legacy plan record ~S" plan))))

(defun normalize-plan-set (plans)
  (remove nil (mapcar #'normalize-plan-record (or plans '()))))

(defun plan-display-value (plan)
  (let ((normalized (normalize-plan-record plan)))
    (and normalized
         (plan-record-goal normalized))))

(defun session-active-plan (session)
  (let ((plan (normalize-plan-record (agent-session-plan session))))
    (setf (agent-session-plan session) plan)
    plan))

(defun session-plan-set (session)
  (normalize-plan-set
   (or (and (session-active-plan session)
            (list (session-active-plan session)))
       '())))

(defun session-active-plan-id (session)
  (let ((plan (session-active-plan session)))
    (and plan (plan-record-id plan))))

(defun session-plan-display-value (session)
  (plan-display-value (session-active-plan session)))

(defun session-plan-summaries (session)
  (mapcar #'plan-record-summary (session-plan-set session)))

(defun set-session-active-plan (session plan)
  (setf (agent-session-plan session)
        (normalize-plan-record plan)))

(defun clear-session-active-plan (session)
  (setf (agent-session-plan session) nil)
  session)
