(in-package #:sbcl-agent)

(defparameter +execution-registry-key+ :execution-registry)
(defparameter *execution-registry-lock*
  (sb-thread:make-mutex :name "sbcl-agent-execution-registry"))

(defun tool-capability-id (tool-id)
  (format nil "tool/~A"
          (string-downcase (symbol-name tool-id))))

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

(defun ensure-execution-bound-environment (session &optional environment)
  (let ((active-environment (ensure-environment (or environment
                                                    (session-bound-environment session)))))
    (unless (eq (environment-compatibility-session active-environment) session)
      (bind-session-to-environment session active-environment))
    active-environment))


(defun execution-registry-entries (environment)
  (or (environment-metadata-value environment
                                  +execution-registry-key+
                                  '())
      '()))

(defun call-with-execution-registry (environment thunk)
  (sb-thread:with-mutex (*execution-registry-lock*)
    (funcall thunk)))

(defun execution-registry (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (call-with-execution-registry
     active-environment
     (lambda ()
       (copy-list (execution-registry-entries active-environment))))))

(defun find-execution-handle (execution-id &optional environment)
  (find execution-id
        (execution-registry environment)
        :key (lambda (entry) (getf entry :execution-id))
        :test #'string=))

(defun find-execution-handle-by-target (key value &optional environment)
  (find value
        (execution-registry environment)
        :key (lambda (entry)
               (getf (getf entry :target) key))
        :test #'equal))

(defun find-execution-handles-by-target (key value &optional environment)
  (remove-if-not (lambda (entry)
                   (equal (getf (getf entry :target) key) value))
                 (execution-registry environment)))

(defun execution-handle-summary (handle)
  (list :execution-id (getf handle :execution-id)
        :capability (getf handle :capability)
        :status (getf handle :status)
        :domain (getf handle :domain)
        :operation (getf handle :operation)
        :target (getf handle :target)
        :recorded-at (getf handle :recorded-at)
        :last-observed-status (getf handle :last-observed-status)
        :last-status-change-at (getf handle :last-status-change-at)
        :last-control-action (getf handle :last-control-action)
        :last-control-at (getf handle :last-control-at)))

(defun execution-handle-summaries-by-target (key value &optional environment)
  (mapcar #'execution-handle-summary
          (find-execution-handles-by-target key value environment)))

(defun enrich-summary-with-executions (summary key value &optional environment)
  (if (null summary)
      nil
      (let ((handles (and value
                          (execution-handle-summaries-by-target key value environment))))
        (append summary
                (list :primary-execution-handle (first handles)
                      :execution-handles (or handles '()))))))

(defun make-execution-id ()
  (format nil "exec-~D-~D" (get-universal-time) (random 1000000)))

(defun string-prefix-ci-p (prefix string)
  (and prefix
       string
       (<= (length prefix) (length string))
       (string-equal prefix string :end2 (length prefix))))

(defun self-modification-pathname-p (path)
  (let* ((namestring-path (and path (namestring (pathname path))))
         (normalized (and namestring-path
                          (substitute #\/ #\\ namestring-path))))
    (and normalized
         (or (search "/src/" normalized :test #'char-equal)
             (search "/tests/" normalized :test #'char-equal)
             (search "/docs/" normalized :test #'char-equal)
             (search "/sbcl-agent.asd" normalized :test #'char-equal)
             (string-prefix-ci-p "src/" normalized)
             (string-prefix-ci-p "tests/" normalized)
             (string-prefix-ci-p "docs/" normalized)
             (string= normalized "sbcl-agent.asd")))))

(defun capability-name-string (capability)
  (typecase capability
    (keyword (string-downcase (symbol-name capability)))
    (symbol (string-downcase (symbol-name capability)))
    (string capability)
    (t (princ-to-string capability))))

(defun execution-handle-execution-id (handle)
  (getf handle :execution-id))

(defun execution-handle-target-value (handle key)
  (getf (getf handle :target) key))

(defun plist-shaped-p (value)
  (and (listp value)
       (evenp (length value))
       (loop for (key val) on value by #'cddr
             always (and key
                         (keywordp key)
                         (or val (null val))))))

(defun response-execution-state (response)
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

(defun response-execution-target (response)
  (let* ((metadata (service-response-metadata response))
         (data (service-response-data response))
         (package (and (plist-shaped-p data)
                       (listp (getf data :package))
                       (getf data :package)))
         (turn (and (plist-shaped-p data)
                    (listp (getf data :turn))
                    (getf data :turn))))
    (list :thread-id (or (getf metadata :thread-id)
                         (and (plist-shaped-p data)
                              (getf data :id)
                              (eq (getf response :domain) :conversation)
                              (member (getf response :operation) '(:create-thread :use-thread) :test #'eq)
                              (getf data :id)))
          :turn-id (or (getf metadata :turn-id)
                       (and turn
                            (getf turn :id)))
          :task-id (or (getf metadata :task-id)
                       (and (plist-shaped-p data)
                            (getf data :id)
                            (eq (getf response :domain) :task)
                            (getf data :id)))
          :worker-id (or (getf metadata :worker-id)
                         (and (plist-shaped-p data)
                              (getf data :id)
                              (eq (getf response :domain) :worker)
                              (getf data :id)))
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
                              (getf data :policy-id)))
          :platform-package-id (or (getf metadata :platform-package-id)
                                   (and (plist-shaped-p data)
                                        (or (getf data :package-id)
                                            (and package
                                                 (getf package :package-id)))))
          :platform-package-path (or (getf metadata :platform-package-path)
                                     (and (plist-shaped-p data)
                                          (getf data :path))))))

(defun response-execution-trace (response)
  (let* ((metadata (service-response-metadata response))
         (target (response-execution-target response)))
    (list :domain (getf response :domain)
          :operation (getf response :operation)
          :event-family (getf metadata :event-family)
          :visibility (getf metadata :visibility)
          :binding (getf metadata :binding)
          :thread-id (getf target :thread-id)
          :turn-id (getf target :turn-id)
          :task-id (getf target :task-id)
          :worker-id (getf target :worker-id)
          :work-item-id (getf target :work-item-id)
          :workflow-record-id (getf target :workflow-record-id)
          :incident-id (getf target :incident-id)
          :runtime-id (getf target :runtime-id))))

(defun make-execution-history-entry (&key event-kind status action reason note result)
  (list :timestamp (get-universal-time)
        :event-kind event-kind
        :status status
        :action action
        :reason reason
        :note note
        :result result))

(defun append-execution-history-entry (handle key entry)
  (let ((updated (copy-list handle)))
    (setf (getf updated key)
          (append (copy-list (or (getf handle key) '()))
                  (list entry)))
    updated))

(defun record-execution-lifecycle-event (handle status &key result)
  (let* ((updated (append-execution-history-entry
                   handle
                   :lifecycle-history
                   (make-execution-history-entry :event-kind :lifecycle
                                              :status status
                                              :result result))))
    (setf (getf updated :status) status
          (getf updated :last-observed-status) status
          (getf updated :last-status-change-at) (getf (car (last (getf updated :lifecycle-history))) :timestamp))
    updated))

(defun record-execution-control-event (handle action &key status reason note result)
  (let* ((updated (append-execution-history-entry
                   handle
                   :control-history
                   (make-execution-history-entry :event-kind :control
                                              :status status
                                              :action action
                                              :reason reason
                                              :note note
                                              :result result))))
    (setf (getf updated :last-control-action) action
          (getf updated :last-control-at) (getf (car (last (getf updated :control-history))) :timestamp))
    (if status
        (record-execution-lifecycle-event updated status :result result)
        updated)))

(defun record-execution-observed-status (handle status environment &key (result :observation))
  (if (or (null status)
          (eq status (getf handle :last-observed-status)))
      handle
      (let ((updated (record-execution-lifecycle-event handle status :result result)))
        (let* ((target (copy-tree (or (getf updated :target) '())))
               (compatibility-target (and (listp target)
                                          (copy-tree (getf target :compatibility-execution)))))
          (when compatibility-target
            (setf (getf compatibility-target :last-observed-status) status
                  (getf compatibility-target :last-status-change-at) (getf updated :last-status-change-at)
                  (getf target :compatibility-execution) compatibility-target
                  (getf updated :target) target)))
        (store-execution-handle updated environment)
        updated)))

(defun build-execution-handle (response &key intention capability authority context constraints)
  (let* ((metadata (service-response-metadata response))
         (binding (getf metadata :binding))
         (status (response-execution-state response))
         (recorded-at (get-universal-time)))
    (list :execution-id (make-execution-id)
          :intention intention
          :capability capability
          :authority authority
          :constraints constraints
          :context context
          :binding binding
          :status status
          :domain (getf response :domain)
          :operation (getf response :operation)
          :target (response-execution-target response)
          :trace (response-execution-trace response)
          :recorded-at recorded-at
          :last-observed-status status
          :last-status-change-at recorded-at
          :last-control-action nil
          :last-control-at nil
          :lifecycle-history (list (list :timestamp recorded-at
                                         :event-kind :invoke
                                         :status status
                                         :result :accepted))
          :control-history '())))

(defun store-execution-handle (handle &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (call-with-execution-registry
     active-environment
     (lambda ()
       (let* ((current (execution-registry-entries active-environment))
              (updated (cons handle
                             (remove (getf handle :execution-id)
                                     current
                                     :key (lambda (entry) (getf entry :execution-id))
                                     :test #'string=))))
         (set-environment-metadata-value active-environment
                                         +execution-registry-key+
                                         updated)
         handle)))))

(defun normalize-execution-handle-for-load (handle)
  (let* ((target (copy-tree (or (getf handle :target) '())))
         (compatibility-target (and (listp target)
                                    (copy-tree (getf target :compatibility-execution)))))
    (unless (getf handle :lifecycle-history)
      (setf (getf handle :lifecycle-history)
            (list (list :timestamp (or (getf handle :recorded-at)
                                       (get-universal-time))
                        :event-kind :invoke
                        :status (getf handle :status)
                        :result :accepted))))
    (unless (member :control-history handle)
      (setf (getf handle :control-history) '()))
    (unless (member :last-observed-status handle)
      (setf (getf handle :last-observed-status) (getf handle :status)))
    (unless (member :last-status-change-at handle)
      (setf (getf handle :last-status-change-at)
            (or (getf handle :recorded-at)
                (get-universal-time))))
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
      (setf handle (record-execution-lifecycle-event handle :detached :result :reload-normalization)))
    handle))

(defun normalize-execution-registry-for-load (environment)
  (call-with-execution-registry
   environment
   (lambda ()
     (set-environment-metadata-value
      environment
      +execution-registry-key+
      (mapcar #'normalize-execution-handle-for-load
              (execution-registry-entries environment))))))

(defun register-service-command-response (response &key session environment intention capability authority context constraints)
  (let* ((active-environment (and session
                                  (ensure-execution-bound-environment session environment)))
         (handle (and active-environment
                      (build-execution-handle response
                                              :intention intention
                                              :capability capability
                                              :authority authority
                                              :context context
                                              :constraints constraints)))
         (metadata (copy-list (or (service-response-metadata response) '()))))
    (when handle
      (store-execution-handle handle active-environment)
      (setf metadata (plist-put metadata :execution-id (getf handle :execution-id)))
      (setf (getf response :metadata) metadata))
    response))
