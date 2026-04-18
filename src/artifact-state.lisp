(in-package #:sbcl-agent)

(defun environment-artifact-records (environment)
  (or (environment-artifact-index environment)
      (let ((conversation-state (environment-conversation-state environment)))
        (and conversation-state
             (environment-conversation-state-artifacts conversation-state)))))

(defun environment-artifact-summary (environment)
  (artifact-summary-from-records
   (or (environment-artifact-records environment) '())))

(defun environment-artifact-count (environment)
  (length (or (environment-artifact-records environment) '())))

(defun environment-find-artifact-record (environment artifact-id)
  (find artifact-id
        (or (environment-artifact-records environment) '())
        :key (lambda (entry) (getf entry :id))
        :test #'string=))

(defun environment-list-thread-artifact-records (environment thread-id)
  (remove-if-not (lambda (entry)
                   (string= thread-id (getf entry :thread-id)))
                 (or (environment-artifact-records environment) '())))

(defun environment-list-turn-artifact-records (environment turn-id)
  (remove-if-not (lambda (entry)
                   (string= turn-id (getf entry :turn-id)))
                 (or (environment-artifact-records environment) '())))

(defun environment-artifact (environment artifact-id)
  (let ((record (environment-find-artifact-record environment artifact-id)))
    (and record
         (conversation-summary->artifact record))))

(defun environment-thread-artifacts (environment thread-id)
  (mapcar #'conversation-summary->artifact
          (environment-list-thread-artifact-records environment thread-id)))

(defun environment-turn-artifacts (environment turn-id)
  (mapcar #'conversation-summary->artifact
          (environment-list-turn-artifact-records environment turn-id)))

(defun refresh-environment-artifact-index (environment)
  (setf (environment-artifact-index environment)
        (or (environment-artifact-records environment) '()))
  environment)

(defun environment-append-artifact (environment session artifact)
  (let* ((conversation-state (ensure-environment-conversation-state environment session))
         (artifacts (environment-conversation-state-artifacts conversation-state))
         (artifact-summary (artifact-record-summary artifact)))
    (unless (find (artifact-id artifact) artifacts
                  :key (lambda (entry) (getf entry :id))
                  :test #'string=)
      (setf (environment-conversation-state-artifacts conversation-state)
            (append artifacts (list artifact-summary))))
    (refresh-environment-conversation-domain environment session)
    (refresh-environment-artifact-index environment)))
