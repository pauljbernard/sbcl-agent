(in-package #:sbcl-agent)

(defparameter +kernel-execution-registry-key+ :kernel-execution-registry)

(defun kernel-tool-capability-id (tool-id)
  (format nil "tool/~A"
          (string-downcase (symbol-name tool-id))))

(defun kernel-plist-without-key (plist key)
  (cond
    ((null plist) '())
    ((eq (first plist) key)
     (kernel-plist-without-key (cddr plist) key))
    (t
     (list* (first plist)
            (second plist)
            (kernel-plist-without-key (cddr plist) key)))))

(defun kernel-plist-put (plist key value)
  (append (kernel-plist-without-key plist key) (list key value)))

(defun ensure-kernel-bound-environment (session &optional environment)
  (let ((active-environment (ensure-environment (or environment
                                                    (session-bound-environment session)))))
    (unless (eq (environment-compatibility-session active-environment) session)
      (bind-session-to-environment session active-environment))
    active-environment))

(defun kernel-execution-registry (&optional environment)
  (copy-list (or (environment-metadata-value (ensure-environment environment)
                                             +kernel-execution-registry-key+
                                             '())
                 '())))

(defun kernel-find-execution (execution-id &optional environment)
  (find execution-id
        (kernel-execution-registry environment)
        :key (lambda (entry) (getf entry :execution-id))
        :test #'string=))

(defun kernel-find-execution-by-target (key value &optional environment)
  (find value
        (kernel-execution-registry environment)
        :key (lambda (entry)
               (getf (getf entry :target) key))
        :test #'equal))

(defun kernel-find-executions-by-target (key value &optional environment)
  (remove-if-not (lambda (entry)
                   (equal (getf (getf entry :target) key) value))
                 (kernel-execution-registry environment)))

(defun kernel-execution-summary (handle)
  (list :execution-id (getf handle :execution-id)
        :capability (getf handle :capability)
        :status (getf handle :status)
        :domain (getf handle :domain)
        :operation (getf handle :operation)
        :target (getf handle :target)
        :recorded-at (getf handle :recorded-at)))

(defun kernel-execution-summaries-by-target (key value &optional environment)
  (mapcar #'kernel-execution-summary
          (kernel-find-executions-by-target key value environment)))

(defun kernel-enrich-summary-with-executions (summary key value &optional environment)
  (if (null summary)
      nil
      (let ((handles (and value
                          (kernel-execution-summaries-by-target key value environment))))
        (append summary
                (list :primary-execution-handle (first handles)
                      :execution-handles (or handles '()))))))

(defun make-kernel-execution-id ()
  (format nil "exec-~D-~D" (get-universal-time) (random 1000000)))

(defun plist-shaped-p (value)
  (and (listp value)
       (evenp (length value))
       (loop for (key val) on value by #'cddr
             always (and key
                         (keywordp key)
                         (or val (null val))))))

(defun kernel-response-state (response)
  (let* ((data (service-response-data response))
         (turn (and (plist-shaped-p data) (getf data :turn)))
         (work-item (and (plist-shaped-p data) (getf data :work-item)))
         (workflow-record (and (plist-shaped-p data) (getf data :workflow-record)))
         (approval (and (plist-shaped-p data) (getf data :approval)))
         (exit-code (and (plist-shaped-p data)
                         (integerp (getf data :exit-code))
                         (getf data :exit-code))))
    (cond
      ((and (listp turn) (getf turn :status))
       (getf turn :status))
      ((and (listp work-item) (getf work-item :state))
       (getf work-item :state))
      ((and (listp workflow-record) (getf workflow-record :status))
       (getf workflow-record :status))
      ((and (listp approval) (getf approval :status))
       (getf approval :status))
      ((integerp exit-code)
       (if (zerop exit-code) :completed :failed))
      (t
       (getf response :status)))))

(defun kernel-response-target (response)
  (let* ((metadata (service-response-metadata response))
         (data (service-response-data response)))
    (list :thread-id (getf metadata :thread-id)
          :turn-id (getf metadata :turn-id)
          :work-item-id (or (getf metadata :work-item-id)
                            (and (plist-shaped-p data)
                                 (getf data :work-item-id)))
          :workflow-record-id (or (getf metadata :workflow-record-id)
                                  (and (plist-shaped-p data)
                                       (getf data :workflow-record-id)))
          :incident-id (or (getf metadata :incident-id)
                           (and (plist-shaped-p data)
                                (getf data :incident-id)))
          :runtime-id (or (getf metadata :runtime-id)
                          (and (plist-shaped-p data)
                               (getf data :runtime-id)))
          :compatibility-execution (and (plist-shaped-p data)
                                        (copy-tree (getf data :compatibility-target)))
          :policy-id (or (getf metadata :policy-id)
                         (and (plist-shaped-p data)
                              (getf data :policy-id))))))

(defun kernel-response-trace (response)
  (let* ((metadata (service-response-metadata response))
         (target (kernel-response-target response)))
    (list :domain (getf response :domain)
          :operation (getf response :operation)
          :event-family (getf metadata :event-family)
          :visibility (getf metadata :visibility)
          :binding (getf metadata :binding)
          :thread-id (getf target :thread-id)
          :turn-id (getf target :turn-id)
          :work-item-id (getf target :work-item-id)
          :workflow-record-id (getf target :workflow-record-id)
          :incident-id (getf target :incident-id)
          :runtime-id (getf target :runtime-id))))

(defun build-kernel-execution-handle (response &key intention capability authority context constraints)
  (let* ((metadata (service-response-metadata response))
         (binding (getf metadata :binding)))
    (list :execution-id (make-kernel-execution-id)
          :intention intention
          :capability capability
          :authority authority
          :constraints constraints
          :context context
          :binding binding
          :status (kernel-response-state response)
          :domain (getf response :domain)
          :operation (getf response :operation)
          :target (kernel-response-target response)
          :trace (kernel-response-trace response)
          :recorded-at (get-universal-time))))

(defun store-kernel-execution-handle (handle &optional environment)
  (let* ((active-environment (ensure-environment environment))
         (current (kernel-execution-registry active-environment))
         (updated (cons handle
                        (remove (getf handle :execution-id)
                                current
                                :key (lambda (entry) (getf entry :execution-id))
                                :test #'string=))))
    (set-environment-metadata-value active-environment
                                    +kernel-execution-registry-key+
                                    updated)
    handle))

(defun normalize-kernel-execution-handle-for-load (handle)
  (let* ((target (copy-tree (or (getf handle :target) '())))
         (compatibility-target (and (listp target)
                                    (copy-tree (getf target :compatibility-execution)))))
    (when (and compatibility-target
               (eq (getf compatibility-target :execution-mode) :detached)
               (not (member (getf handle :status)
                            '(:completed :failed :revoked :terminated :stopped :detached)
                            :test #'eq)))
      ;; Compatibility control tokens are runtime-local and cannot survive reload.
      (setf (getf compatibility-target :control-token) nil)
      (setf (getf compatibility-target :last-observed-status) :detached)
      (setf (getf compatibility-target :last-status-change-at) (get-universal-time))
      (setf (getf compatibility-target :detached-runtime-loss-p) t)
      (setf (getf target :compatibility-execution) compatibility-target)
      (setf (getf handle :target) target)
      (setf (getf handle :status) :detached))
    handle))

(defun normalize-kernel-execution-registry-for-load (environment)
  (let ((registry (kernel-execution-registry environment)))
    (set-environment-metadata-value
     environment
     +kernel-execution-registry-key+
     (mapcar #'normalize-kernel-execution-handle-for-load registry))))

(defun kernelize-service-command-response (response &key session environment intention capability authority context constraints)
  (let* ((active-environment (and session
                                  (ensure-kernel-bound-environment session environment)))
         (handle (and active-environment
                      (build-kernel-execution-handle response
                                                     :intention intention
                                                     :capability capability
                                                     :authority authority
                                                     :context context
                                                     :constraints constraints)))
         (metadata (copy-list (or (service-response-metadata response) '()))))
    (when handle
      (store-kernel-execution-handle handle active-environment)
      (setf metadata (kernel-plist-put metadata :execution-id (getf handle :execution-id)))
      (setf metadata (kernel-plist-put metadata :execution-handle handle))
      (setf (getf response :metadata) metadata))
    response))
