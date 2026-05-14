(in-package #:sbcl-agent)

(defun resolve-runtime-package-designator (package-designator)
  (typecase package-designator
    (package package-designator)
    (symbol (or (find-package package-designator)
                (find-package (string-upcase (symbol-name package-designator)))))
    (string (or (find-package package-designator)
                (find-package (string-upcase package-designator))))
    (t nil)))

(defun session-runtime-package (session)
  (or (resolve-runtime-package-designator (agent-session-package session))
      (error "Unknown runtime package ~S" (agent-session-package session))))

(defparameter *runtime-eval-debug-log-path*
  #P"/private/tmp/sbcl-agent-runtime-eval-debug.log")

(defparameter *runtime-governance-thread* nil)
(defparameter *runtime-governance-turn* nil)
(defparameter *runtime-governance-operation* nil)

(declaim (special *runtime-governance-thread*
                  *runtime-governance-turn*
                  *runtime-governance-operation*))

(defun runtime-recovery-launch-summary (recovery-launch)
  (when (listp recovery-launch)
    (let ((source (getf recovery-launch :source))
          (incident-id (getf recovery-launch :incident-id))
          (restart-label (getf recovery-launch :restart-label)))
      (when (and source incident-id restart-label)
        (list :source source
              :incident-id incident-id
              :restart-label restart-label)))))

(defparameter *runtime-source-extensions* '("lisp" "lsp" "asd" "cl"))

(defun package-use-list-names (package)
  (sort (mapcar #'package-name (package-use-list package)) #'string<))

(defun runtime-loaded-system-names ()
  (sort
   (handler-case
       (mapcar (lambda (system)
                 (string-downcase
                  (typecase system
                    (symbol (symbol-name system))
                    (string system)
                    (t (princ-to-string system)))))
               (asdf:already-loaded-systems))
     (error () '()))
   #'string<))

(defun tool-runtime-current-package (session &key)
  (let ((package (session-runtime-package session)))
    (list :tool :runtime/current-package
          :package (package-name package)
          :nicknames (sort (copy-list (package-nicknames package)) #'string<)
          :use-list (package-use-list-names package)
          :sandbox-profile :in-process)))

(defun tool-runtime-list-loaded-systems (session &key)
  (declare (ignore session))
  (let ((systems (runtime-loaded-system-names)))
    (list :tool :runtime/list-loaded-systems
          :system-count (length systems)
          :systems systems
          :sandbox-profile :in-process)))

(defun symbol-status-keyword (status)
  (or status :missing))

(defun maybe-sync-current-environment-from-session (session)
  (when (and (boundp '*current-environment*) *current-environment*)
    (sync-environment-runtime-history-from-session *current-environment* session)))

(defun current-environment-runtime-history ()
  (let ((environment (ensure-environment)))
    (or (environment-runtime-history environment) '())))

(defun append-runtime-history-entry (session kind payload)
  (let* ((environment (ensure-environment))
         (entry (list :kind kind
                      :timestamp (get-universal-time)
                      :package (agent-session-package session)
                      :payload payload)))
    (append-environment-runtime-history environment entry)
    (maybe-sync-current-environment-from-session session)
    entry))

(defun maybe-append-operation-artifact-link (operation artifact)
  (when (and operation artifact)
    (let ((artifact-id (artifact-id artifact))
          (existing (getf (operation-metadata operation) :artifact-ids)))
      (setf (operation-metadata operation)
            (append (operation-metadata operation)
                    (list :artifact-ids
                          (append existing (list artifact-id)))))))
  artifact)

(defun runtime-incident-thread (session)
  (or *runtime-governance-thread*
      (ignore-errors (current-thread session))))

(defun call-with-runtime-incident-capture (session thunk &key kind title summary metadata)
  (handler-case
      (funcall thunk)
    (error (condition)
      (record-runtime-incident session
                               condition
                               :thread (runtime-incident-thread session)
                               :turn *runtime-governance-turn*
                               :operation *runtime-governance-operation*
                               :kind kind
                               :title title
                               :summary (or summary (princ-to-string condition))
                               :metadata metadata)
      (error condition))))

(defun runtime-governance-work-item (session form-or-path kind policy-id &key result)
  (declare (ignore kind))
  (let* ((environment-operation-work-item-id
           (and (boundp '*runtime-governance-operation*)
                *runtime-governance-operation*
                (getf (operation-metadata *runtime-governance-operation*) :work-item-id)))
         (existing-work-item (and environment-operation-work-item-id
                                  (find-work-item session environment-operation-work-item-id))))
    (or existing-work-item
        (create-work-item session
                          (format nil "Structured runtime mutation ~A" form-or-path)
                          :mutation-intent (list :source :runtime-operation
                                                 :kind kind
                                                 :package (agent-session-package session)
                                                 :form-or-path form-or-path
                                                 :policy-id policy-id
                                                 :result result)
                          :transaction-scope :runtime-mutation))))

(defun create-runtime-mutation-work-item (session form-string policy-id result &key recovery-launch)
  (let* ((work-item (runtime-governance-work-item session
                                                  form-string
                                                  :live-image-mutation
                                                  policy-id
                                                  :result result))
         (checkpoint (or (first (last (work-item-checkpoints work-item)))
                         (append-work-item-checkpoint
                          session
                          work-item
                          :validation-baseline (list :runtime-form form-string
                                                     :package (agent-session-package session)
                                                     :policy-id policy-id)))))
    (append-work-item-runtime-observation
     session
     work-item
     :runtime-mutation-executed
     (list :form form-string
           :package (agent-session-package session)
           :policy-id policy-id
           :recovery-launch recovery-launch
           :result result))
    (append-work-item-image-mutation
     work-item
     (list :kind :structured-runtime-eval
           :package (agent-session-package session)
           :form form-string
           :result result)
     session)
    (setf (work-item-live-validation-result work-item)
          (make-live-validation-result
           :passed
           (list :kind :runtime-mutation-live
                 :checkpoint-id (checkpoint-record-id checkpoint)
                 :result result))
          (work-item-cold-validation-result work-item) nil
          (provenance-record-validation-outputs (work-item-provenance work-item))
          (list (validation-result-summary (work-item-live-validation-result work-item))))
    (refresh-work-item-pending-validations session work-item)
    (let ((transaction (current-work-item-transaction work-item))
          (record (work-item-workflow-record session work-item)))
      (when transaction
        (setf (mutation-transaction-state transaction) :committed
              (mutation-transaction-rollback-status transaction) :captured
              (mutation-transaction-rollback-detail transaction)
              (list :reason :cold-validation-pending
                    :checkpoint-id (checkpoint-record-id checkpoint))))
      (setf (work-item-status work-item) :awaiting-cold-validation
            (work-item-closure-decision work-item) :awaiting-cold-validation
            (work-item-updated-at work-item) (get-universal-time))
      (set-work-item-next-action session work-item
                                 (list :type :complete-pending-validations
                                       :suggested-step :run-cold-validation
                                       :pending (work-item-pending-validations work-item)
                                       :final-closure-decision :committed-to-image))
      (set-work-item-resume-payload session work-item
                                    (list :resume-command :complete-validations
                                          :checkpoint-id (checkpoint-record-id checkpoint)
                                          :pending (work-item-pending-validations work-item)
                                          :validator-actions (work-item-validator-actions work-item)
                                          :replay-id (mutation-transaction-replay-id transaction)
                                          :rollback-point (work-item-rollback-point work-item)
                                          :final-closure-decision :committed-to-image))
      (append-work-item-workflow-entry
       session
       work-item
       :validate
       :runtime-mutation-awaiting-cold-validation
       (list :form form-string
             :package (agent-session-package session)
             :policy-id policy-id
             :checkpoint-id (checkpoint-record-id checkpoint)
             :result result)
       :status :awaiting-cold-validation)
      (when record
        (setf (workflow-record-status record) :awaiting-cold-validation
              (workflow-record-updated-at record) (get-universal-time))))
    work-item))

(defun create-runtime-reload-work-item (session path load-result)
  (let* ((work-item (runtime-governance-work-item session
                                                  path
                                                  :source-to-image-reload
                                                  :runtime-reload
                                                  :result load-result))
         (checkpoint (or (first (last (work-item-checkpoints work-item)))
                         (append-work-item-checkpoint
                          session
                          work-item
                          :validation-baseline (list :path path
                                                     :policy-id :runtime-reload)))))
    (append-work-item-runtime-observation
     session
     work-item
     :runtime-reload-executed
     (list :path path
           :policy-id :runtime-reload
           :load-result load-result))
    (append-work-item-source-mutation
     work-item
     (list :kind :source-reload-input
           :path path)
     session)
    (append-work-item-image-mutation
     work-item
     (list :kind :source-file-reloaded
           :path path
           :load-result load-result)
     session)
    (setf (work-item-live-validation-result work-item)
          (make-live-validation-result
           :passed
           (list :kind :runtime-reload-live
                 :checkpoint-id (checkpoint-record-id checkpoint)
                 :path path))
          (work-item-cold-validation-result work-item) nil
          (provenance-record-validation-outputs (work-item-provenance work-item))
          (list (validation-result-summary (work-item-live-validation-result work-item))))
    (refresh-work-item-pending-validations session work-item)
    (let ((transaction (current-work-item-transaction work-item))
          (record (work-item-workflow-record session work-item)))
      (when transaction
        (setf (mutation-transaction-state transaction) :committed
              (mutation-transaction-rollback-status transaction) :captured
              (mutation-transaction-rollback-detail transaction)
              (list :reason :cold-validation-pending
                    :checkpoint-id (checkpoint-record-id checkpoint))))
      (setf (work-item-status work-item) :awaiting-cold-validation
            (work-item-closure-decision work-item) :awaiting-cold-validation
            (work-item-updated-at work-item) (get-universal-time))
      (set-work-item-next-action session work-item
                                 (list :type :complete-pending-validations
                                       :suggested-step :run-cold-validation
                                       :pending (work-item-pending-validations work-item)
                                       :final-closure-decision :committed-to-source-and-image))
      (set-work-item-resume-payload session work-item
                                    (list :resume-command :complete-validations
                                          :checkpoint-id (checkpoint-record-id checkpoint)
                                          :pending (work-item-pending-validations work-item)
                                          :validator-actions (work-item-validator-actions work-item)
                                          :replay-id (mutation-transaction-replay-id transaction)
                                          :rollback-point (work-item-rollback-point work-item)
                                          :final-closure-decision :committed-to-source-and-image))
      (append-work-item-workflow-entry
       session
       work-item
       :validate
       :runtime-reload-awaiting-cold-validation
       (list :path path
             :policy-id :runtime-reload
             :checkpoint-id (checkpoint-record-id checkpoint)
             :load-result load-result)
       :status :awaiting-cold-validation)
      (when record
        (setf (workflow-record-status record) :awaiting-cold-validation
              (workflow-record-updated-at record) (get-universal-time))))
    work-item))

(defun runtime-history-tail (entries tail)
  (let* ((tail-count (cond
                       ((null tail) 10)
                       ((and (integerp tail) (plusp tail)) tail)
                       (t (error "Tail count must be a positive integer, got ~S" tail))))
         (start (max 0 (- (length entries) tail-count))))
    (subseq entries start)))

(defun runtime-eval-policy-id (mutating)
  (if mutating :runtime-eval-mutate :runtime-eval-safe))

(defun runtime-eval-primary-form (resolved-forms)
  (and (consp resolved-forms)
       (first resolved-forms)))

(defun runtime-eval-primary-operator (resolved-forms)
  (let ((form (runtime-eval-primary-form resolved-forms)))
    (and (consp form)
         (symbolp (first form))
         (first form))))

(defun runtime-eval-defined-name (resolved-forms)
  (let ((form (runtime-eval-primary-form resolved-forms)))
    (and (consp form)
         (eq (first form) 'defun)
         (symbolp (second form))
         (second form))))

(defun runtime-history-eval-payloads-for-package (package-name)
  (loop for entry in (reverse (current-environment-runtime-history))
        for payload = (getf entry :payload)
        when (and (eq (getf entry :kind) :eval)
                  (listp payload)
                  (string= (or (getf payload :package) "") package-name))
          collect payload))

(defun runtime-actor-state-definition-payload-for-symbol (session package-name symbol)
  (let* ((mailboxes (or (and (fboundp 'ensure-session-actor-mailboxes)
                             (ignore-errors (ensure-session-actor-mailboxes session)))
                        (agent-session-actor-mailboxes session)
                        '()))
         (runtime-state (and (listp mailboxes)
                             (getf mailboxes :runtime-state)))
         (definitions (and (listp runtime-state)
                           (getf runtime-state :definitions)))
         (match (find-if (lambda (entry)
                           (and (string= (or (getf entry :package-name) "") package-name)
                                (string= (or (getf entry :symbol-name) "")
                                         (symbol-name symbol))))
                         definitions)))
    (and match
         (list :package (getf match :package-name)
               :form (getf match :form)
               :source :runtime-actor-state
               :actor-message-id (getf match :actor-message-id)
               :request-id (getf match :request-id)))))

(defun runtime-history-definition-payload-for-symbol (package-name symbol)
  (loop for payload in (runtime-history-eval-payloads-for-package package-name)
        for form-string = (getf payload :form)
        for forms = (ignore-errors
                      (parse-runtime-forms form-string
                                           :package (symbol-package symbol)))
        for form = (and forms (first forms))
        when (and (consp form)
                  (eq (first form) 'defun)
                  (symbolp (second form))
                  (string= (symbol-name (second form))
                           (symbol-name symbol)))
          return payload))

(defun maybe-replay-runtime-definition-from-history (session resolved-package resolved-forms)
  (let ((operator (runtime-eval-primary-operator resolved-forms)))
    (when (and operator
               (not (fboundp operator)))
      (let* ((payload (or (runtime-actor-state-definition-payload-for-symbol
                           session
                           (package-name resolved-package)
                           operator)
                          (runtime-history-definition-payload-for-symbol
                           (package-name resolved-package)
                           operator)))
             (form-string (and payload (getf payload :form)))
             (history-forms (and form-string
                                 (ignore-errors
                                   (parse-runtime-forms form-string
                                                        :package resolved-package)))))
        (when history-forms
          (append-runtime-eval-debug-log :replay-before
                                         session
                                         resolved-package
                                         form-string
                                         history-forms)
          (let ((*package* resolved-package))
            (dolist (history-form history-forms)
              (eval history-form)))
          (append-runtime-eval-debug-log :replay-after
                                         session
                                         resolved-package
                                         form-string
                                         history-forms))))))

(defun append-runtime-eval-debug-log (stage session resolved-package form resolved-forms
                                     &key values error)
  (ignore-errors
    (with-open-file (out *runtime-eval-debug-log-path*
                         :direction :output
                         :if-exists :append
                         :if-does-not-exist :create)
      (let* ((primary-operator (runtime-eval-primary-operator resolved-forms))
             (defined-name (runtime-eval-defined-name resolved-forms)))
        (format out
                "~&stage=~A session-package=~A runtime-package=~A form=~S operator=~S operator-fboundp=~S defined-name=~S defined-name-fboundp=~S values=~S error=~S~%"
                stage
                (agent-session-package session)
                (package-name resolved-package)
                form
                primary-operator
                (and primary-operator (fboundp primary-operator))
                defined-name
                (and defined-name (fboundp defined-name))
                values
                error)))))

(defun parse-runtime-forms (form-or-source &key package)
  (flet ((collect-forms ()
           (if (stringp form-or-source)
               (with-input-from-string (stream form-or-source)
                 (loop with eof = (gensym "EOF")
                       for form = (read stream nil eof)
                       until (eq form eof)
                       collect form))
               (list form-or-source))))
    (if package
        (let ((*package* package))
          (collect-forms))
        (collect-forms))))

(defun runtime-function-kind (symbol)
  (cond
    ((macro-function symbol) :macro)
    ((special-operator-p symbol) :special-operator)
    ((and (fboundp symbol)
          (typep (fdefinition symbol) 'generic-function))
     :generic-function)
    ((fboundp symbol) :function)
    (t nil)))

(defun runtime-class-display-name (class)
  (typecase class
    (class (let ((name (class-name class)))
             (and name (string-upcase (string name)))))
    (t nil)))

(defun runtime-safe-princ-string (value &key (limit 160))
  (let ((rendered (handler-case
                      (princ-to-string value)
                    (error ()
                      (format nil "#<unprintable ~A>" (type-of value))))))
    (if (> (length rendered) limit)
        (concatenate 'string (subseq rendered 0 limit) "...")
        rendered)))

(defun runtime-slot-summary (object slot-definition)
  (let* ((slot-name (ignore-errors (sb-mop:slot-definition-name slot-definition)))
         (boundp (and slot-name
                      (ignore-errors (slot-boundp object slot-name))))
         (value (and boundp
                     slot-name
                     (ignore-errors (slot-value object slot-name)))))
    (list :name (and slot-name (string-upcase (string slot-name)))
          :boundp (not (null boundp))
          :value (and boundp (runtime-safe-princ-string value))
          :value-type (and boundp value (runtime-safe-princ-string (type-of value) :limit 80)))))

(defun runtime-object-slot-summaries (object)
  (let* ((class (ignore-errors (class-of object)))
         (slots (and class
                     (ignore-errors (sb-mop:class-slots class)))))
    (when slots
      (let* ((limited-slots (subseq slots 0 (min (length slots) 12)))
             (summaries (remove nil (mapcar (lambda (slot)
                                              (ignore-errors (runtime-slot-summary object slot)))
                                            limited-slots))))
        (list :slot-count (length slots)
              :slots summaries)))))

(defun runtime-list-preview (values &key (limit 8))
  (let ((items '())
        (count 0))
    (dolist (value values)
      (when (>= count limit)
        (return))
      (push (runtime-safe-princ-string value :limit 80) items)
      (incf count))
    (nreverse items)))

(defun runtime-hash-table-preview (table &key (limit 8))
  (let ((entries '())
        (count 0))
    (maphash (lambda (key value)
               (when (< count limit)
                 (push (list :key (runtime-safe-princ-string key :limit 80)
                             :value (runtime-safe-princ-string value :limit 80))
                       entries)
                 (incf count)))
             table)
    (nreverse entries)))

(defun runtime-package-symbol-counts (package)
  (let ((external 0)
        (internal 0))
    (do-external-symbols (symbol package)
      (declare (ignore symbol))
      (incf external))
    (do-symbols (symbol package)
      (declare (ignore symbol))
      (multiple-value-bind (_symbol status)
          (find-symbol (symbol-name symbol) package)
        (declare (ignore _symbol))
        (when (eq status :internal)
          (incf internal))))
    (list :external-symbol-count external
          :internal-symbol-count internal)))

(defun runtime-value-summary (value)
  (let* ((class (ignore-errors (class-of value)))
         (class-name (runtime-class-display-name class))
         (type-name (runtime-safe-princ-string (type-of value) :limit 80))
         (summary (list :type type-name
                        :class class-name
                        :printed (runtime-safe-princ-string value))))
    (append summary
            (typecase value
              (null (list :kind :null))
              (cons (list :kind :list
                          :length (ignore-errors (length value))))
              (hash-table (list :kind :hash-table
                                :count (hash-table-count value)
                                :test (runtime-safe-princ-string (hash-table-test value) :limit 40)))
              (array (list :kind :array
                           :dimensions (array-dimensions value)))
              (package (list :kind :package
                             :name (package-name value)
                             :nicknames (sort (copy-list (package-nicknames value)) #'string<)))
              (symbol (list :kind :symbol
                            :name (symbol-name value)
                            :home-package (and (symbol-package value)
                                               (package-name (symbol-package value)))))
              (function (list :kind :function))
              (standard-object (append (list :kind :standard-object)
                                       (or (runtime-object-slot-summaries value) '())))
              (structure-object (append (list :kind :structure-object)
                                        (or (runtime-object-slot-summaries value) '())))
              (t (list :kind :atom))))))

(defun runtime-object-detail (value)
  (append (runtime-value-summary value)
          (typecase value
            (null '())
            (cons (list :preview (runtime-list-preview value)))
            (hash-table (list :preview (runtime-hash-table-preview value)))
            (array (list :total-size (array-total-size value)
                         :element-type (runtime-safe-princ-string (array-element-type value) :limit 80)))
            (package (append (list :used-packages
                                   (sort (mapcar #'package-name (copy-list (package-use-list value))) #'string<)
                                   :used-by-packages
                                   (sort (mapcar #'package-name (copy-list (package-used-by-list value))) #'string<))
                             (runtime-package-symbol-counts value)))
            (symbol (list :boundp (boundp value)
                          :fboundp (not (null (fboundp value)))
                          :keywordp (keywordp value)
                          :constantp (constantp value)))
            (function (list :function-kind
                            (typecase value
                              (generic-function :generic-function)
                              (function :function)
                              (t :unknown))))
            (t '()))))

(defun runtime-function-summary (symbol)
  (let ((kind (runtime-function-kind symbol)))
    (when kind
      (let ((function (ignore-errors (fdefinition symbol))))
        (append (list :kind kind
                      :name (symbol-name symbol)
                      :lambda-list (ignore-errors
                                     (multiple-value-bind (lambda-expression closure-p name)
                                         (function-lambda-expression function)
                                       (declare (ignore closure-p name))
                                       (and (consp lambda-expression)
                                            (second lambda-expression)))))
                (when (eq kind :generic-function)
                  (list :method-count (length (or (runtime-generic-function-methods symbol) '())))))))))

(defun runtime-generic-function-methods (symbol)
  (let ((function (and (fboundp symbol) (fdefinition symbol))))
    (when (typep function 'generic-function)
      (mapcar (lambda (method)
                (list :qualifiers (ignore-errors (method-qualifiers method))
                      :specializers
                      (mapcar (lambda (specializer)
                                (typecase specializer
                                  (class (or (class-name specializer)
                                             (princ-to-string specializer)))
                                  (t (princ-to-string specializer))))
                              (ignore-errors (sb-mop:method-specializers method)))))
              (ignore-errors (sb-mop:generic-function-methods function))))))

(defun pathname-hidden-p (pathname)
  (let ((name (or (pathname-name pathname) "")))
    (and (> (length name) 0)
         (char= (char name 0) #\.))))

(defun runtime-source-file-p (pathname)
  (let ((type (pathname-type pathname)))
    (and type
         (member (string-downcase type) *runtime-source-extensions* :test #'string=)
         (not (pathname-hidden-p pathname)))))

(defun collect-runtime-source-files (root)
  (labels ((walk (directory)
             (append (remove-if-not #'runtime-source-file-p
                                    (ignore-errors (uiop:directory-files directory)))
                     (mapcan #'walk
                             (remove-if #'pathname-hidden-p
                                        (ignore-errors (uiop:subdirectories directory)))))))
    (let ((resolved (uiop:ensure-directory-pathname root)))
      (remove-duplicates (walk resolved) :test #'equal))))

(defun trim-whitespace (string)
  (string-trim '(#\Space #\Tab) string))

(defun definition-form-kind (line symbol-name)
  (let ((normalized (string-downcase (trim-whitespace line)))
        (needle (string-downcase symbol-name)))
    (loop for prefix in '("defun" "defmacro" "defgeneric" "defmethod" "defclass"
                          "defvar" "defparameter" "defconstant")
          when (search (format nil "(~A ~A" prefix needle) normalized)
            return (intern (string-upcase prefix) "KEYWORD"))))

(defun caller-line-p (line symbol-name)
  (let ((normalized (string-downcase line))
        (needle (string-downcase symbol-name)))
    (search (format nil "(~A" needle) normalized)))

(defun scan-runtime-source-file (pathname symbol-name)
  (let ((definitions '())
        (callers '()))
    (with-open-file (stream pathname :direction :input)
      (loop for line = (read-line stream nil nil)
            for line-number from 1
            while line
            for definition-kind = (definition-form-kind line symbol-name)
            do (when definition-kind
                 (push (list :path (namestring pathname)
                             :line line-number
                             :definition-kind definition-kind
                             :text (trim-whitespace line))
                       definitions))
               (when (caller-line-p line symbol-name)
                 (push (list :path (namestring pathname)
                             :line line-number
                             :text (trim-whitespace line))
                       callers))))
    (values (nreverse definitions) (nreverse callers))))

(defun runtime-source-analysis (session symbol-name)
  (let ((definitions '())
        (callers '()))
    (dolist (pathname (collect-runtime-source-files (agent-session-cwd session)))
      (multiple-value-bind (file-definitions file-callers)
          (scan-runtime-source-file pathname symbol-name)
        (setf definitions (append definitions file-definitions)
              callers (append callers file-callers))))
    (values definitions callers)))

(defun runtime-symbol-presence-summary (resolved-symbol status)
  (list :status (symbol-status-keyword status)
        :home-package (let ((home (symbol-package resolved-symbol)))
                        (and home (package-name home)))
        :boundp (boundp resolved-symbol)
        :fboundp (not (null (fboundp resolved-symbol)))
        :keywordp (keywordp resolved-symbol)
        :constantp (constantp resolved-symbol)
        :function-kind (runtime-function-kind resolved-symbol)))

(defun resolve-runtime-symbol (session symbol-name &optional package-name)
  (let* ((resolved-package (or (resolve-runtime-package-designator (or package-name (agent-session-package session)))
                               (error "Unknown package ~S" (or package-name (agent-session-package session))))))
    (multiple-value-bind (resolved-symbol status)
        (find-symbol symbol-name resolved-package)
      (values resolved-package resolved-symbol status))))

(defun tool-runtime-find-definition (session &key symbol package)
  (unless symbol
    (error ":runtime/find-definition requires :symbol"))
  (multiple-value-bind (resolved-package resolved-symbol status)
      (resolve-runtime-symbol session symbol package)
    (multiple-value-bind (definitions callers)
        (runtime-source-analysis session symbol)
      (list :tool :runtime/find-definition
            :package (package-name resolved-package)
            :symbol symbol
            :runtime-symbol (and resolved-symbol (symbol-name resolved-symbol))
            :runtime-presence (and resolved-symbol
                                   (runtime-symbol-presence-summary resolved-symbol status))
            :definition-count (length definitions)
            :definitions definitions
            :caller-count (length callers)
            :sandbox-profile :in-process))))

(defun tool-runtime-callers (session &key symbol package)
  (unless symbol
    (error ":runtime/callers requires :symbol"))
  (multiple-value-bind (resolved-package resolved-symbol status)
      (resolve-runtime-symbol session symbol package)
    (declare (ignore status))
    (multiple-value-bind (definitions callers)
        (runtime-source-analysis session symbol)
      (declare (ignore definitions))
      (list :tool :runtime/callers
            :package (package-name resolved-package)
            :symbol symbol
            :runtime-symbol (and resolved-symbol (symbol-name resolved-symbol))
            :caller-count (length callers)
            :callers callers
            :sandbox-profile :in-process))))

(defun tool-runtime-methods (session &key symbol package)
  (unless symbol
    (error ":runtime/methods requires :symbol"))
  (multiple-value-bind (resolved-package resolved-symbol status)
      (resolve-runtime-symbol session symbol package)
    (unless resolved-symbol
      (error "Symbol ~S was not found in package ~A" symbol (package-name resolved-package)))
    (let ((methods (runtime-generic-function-methods resolved-symbol)))
      (list :tool :runtime/methods
            :package (package-name resolved-package)
            :symbol (symbol-name resolved-symbol)
            :runtime-presence (runtime-symbol-presence-summary resolved-symbol status)
            :method-count (length methods)
            :methods methods
            :sandbox-profile :in-process))))

(defun runtime-open-mutation-work-item-p (session symbol-name package-name)
  (find-if (lambda (work-item)
             (let* ((intent (work-item-mutation-intent work-item))
                    (form-or-path (getf intent :form-or-path))
                    (intent-package (getf intent :package))
                    (status (work-item-status work-item)))
               (and (member status '(:awaiting-cold-validation :quarantined :image-only) :test #'eq)
                    (or (null intent-package)
                        (string= intent-package package-name))
                    form-or-path
                    (search (string-downcase symbol-name)
                            (string-downcase (princ-to-string form-or-path))))))
           (agent-session-work-items session)))

(defun tool-runtime-source-image-divergence (session &key symbol package)
  (unless symbol
    (error ":runtime/source-image-divergence requires :symbol"))
  (multiple-value-bind (resolved-package resolved-symbol status)
      (resolve-runtime-symbol session symbol package)
    (multiple-value-bind (definitions callers)
        (runtime-source-analysis session symbol)
      (declare (ignore callers))
      (let* ((package-name (package-name resolved-package))
             (runtime-present-p (not (null resolved-symbol)))
             (source-present-p (not (null definitions)))
             (open-work-item (runtime-open-mutation-work-item-p session symbol package-name))
             (divergence
               (cond
                 ((and runtime-present-p (not source-present-p)) :runtime-only)
                 ((and source-present-p (not runtime-present-p)) :source-only)
                 (open-work-item :potential-drift)
                 ((and source-present-p runtime-present-p) :in-sync)
                 (t :unknown))))
        (list :tool :runtime/source-image-divergence
              :package package-name
              :symbol symbol
              :runtime-symbol (and resolved-symbol (symbol-name resolved-symbol))
              :runtime-present-p runtime-present-p
              :source-present-p source-present-p
              :divergence divergence
              :definition-count (length definitions)
              :definitions definitions
              :open-work-item-id (and open-work-item (work-item-id open-work-item))
              :runtime-presence (and resolved-symbol
                                     (runtime-symbol-presence-summary resolved-symbol status))
              :sandbox-profile :in-process)))))

(defun tool-runtime-describe-symbol (session &key symbol package)
  (unless symbol
    (error ":runtime/describe-symbol requires :symbol"))
  (let* ((package-name (or package (agent-session-package session)))
         (resolved-package (or (resolve-runtime-package-designator package-name)
                               (error "Unknown package ~S" package-name))))
    (multiple-value-bind (resolved-symbol status)
        (find-symbol symbol resolved-package)
      (unless resolved-symbol
        (error "Symbol ~S was not found in package ~A" symbol (package-name resolved-package)))
      (list :tool :runtime/describe-symbol
            :package (package-name resolved-package)
            :symbol (symbol-name resolved-symbol)
            :status (symbol-status-keyword status)
            :home-package (let ((home (symbol-package resolved-symbol)))
                            (and home (package-name home)))
            :boundp (boundp resolved-symbol)
            :fboundp (not (null (fboundp resolved-symbol)))
            :keywordp (keywordp resolved-symbol)
            :constantp (constantp resolved-symbol)
            :sandbox-profile :in-process))))

(defun tool-runtime-inspect-symbol (session &key symbol package)
  (unless symbol
    (error ":runtime/inspect requires :symbol"))
  (let* ((package-name (or package (agent-session-package session)))
         (resolved-package (or (resolve-runtime-package-designator package-name)
                               (error "Unknown package ~S" package-name))))
    (multiple-value-bind (resolved-symbol status)
        (find-symbol symbol resolved-package)
      (unless resolved-symbol
        (error "Symbol ~S was not found in package ~A" symbol (package-name resolved-package)))
      (let* ((boundp (boundp resolved-symbol))
             (value (and boundp (symbol-value resolved-symbol)))
             (function-summary (runtime-function-summary resolved-symbol))
             (methods (and (eq (getf function-summary :kind) :generic-function)
                           (runtime-generic-function-methods resolved-symbol))))
        (list :tool :runtime/inspect
              :package (package-name resolved-package)
              :symbol (symbol-name resolved-symbol)
              :status (symbol-status-keyword status)
              :home-package (let ((home (symbol-package resolved-symbol)))
                              (and home (package-name home)))
              :runtime-presence (runtime-symbol-presence-summary resolved-symbol status)
              :value-summary (and boundp (runtime-value-summary value))
              :function-summary function-summary
              :method-count (length (or methods '()))
              :methods methods
              :sandbox-profile :in-process)))))

(defun tool-runtime-object-symbol (session &key symbol package)
  (unless symbol
    (error ":runtime/object requires :symbol"))
  (let* ((package-name (or package (agent-session-package session)))
         (resolved-package (or (resolve-runtime-package-designator package-name)
                               (error "Unknown package ~S" package-name))))
    (multiple-value-bind (resolved-symbol status)
        (find-symbol symbol resolved-package)
      (unless resolved-symbol
        (error "Symbol ~S was not found in package ~A" symbol (package-name resolved-package)))
      (unless (boundp resolved-symbol)
        (error "Symbol ~S is not bound in package ~A" symbol (package-name resolved-package)))
      (let ((value (symbol-value resolved-symbol)))
        (list :tool :runtime/object
              :package (package-name resolved-package)
              :symbol (symbol-name resolved-symbol)
              :status (symbol-status-keyword status)
              :home-package (let ((home (symbol-package resolved-symbol)))
                              (and home (package-name home)))
              :runtime-presence (runtime-symbol-presence-summary resolved-symbol status)
              :object-detail (runtime-object-detail value)
              :sandbox-profile :in-process)))))

(defun tool-runtime-set-package (session &key package)
  (unless package
    (error ":runtime/set-package requires :package"))
  (ensure-capability-granted session :runtime-package-switch)
  (let ((resolved-package (or (resolve-runtime-package-designator package)
                              (error "Unknown package ~S" package))))
    (setf (agent-session-package session) (package-name resolved-package))
    (append-session-event session
                          :runtime-package-switched
                          (list :package (package-name resolved-package)))
    (append-runtime-history-entry session
                                  :package-switch
                                  (list :package (package-name resolved-package)
                                        :policy-id :runtime-package-switch))
    (let ((artifact (create-artifact session
                                     (or *runtime-governance-thread* (current-thread session))
                                     *runtime-governance-turn*
                                     *runtime-governance-operation*
                                     :runtime-state
                                     nil
                                     :title (format nil "Runtime package switched to ~A" (package-name resolved-package))
                                     :summary "Governed runtime package switch completed."
                                     :work-item-id (and *runtime-governance-operation*
                                                        (getf (operation-metadata *runtime-governance-operation*) :work-item-id))
                                     :metadata (list :source :runtime/set-package
                                                     :package (package-name resolved-package)
                                                     :policy-id :runtime-package-switch))))
      (maybe-append-operation-artifact-link *runtime-governance-operation* artifact))
    (maybe-sync-current-environment-from-session session)
    (list :tool :runtime/set-package
          :package (package-name resolved-package)
          :sandbox-profile :in-process)))

(defun tool-runtime-eval (session &key form package mutating recovery-launch)
  (unless form
    (error ":runtime/eval requires :form"))
  (let* ((policy-id (runtime-eval-policy-id mutating))
         (package-name (or package (agent-session-package session)))
         (resolved-package (or (resolve-runtime-package-designator package-name)
                               (error "Unknown package ~S" package-name)))
         (resolved-forms (parse-runtime-forms form :package resolved-package))
         (recovery-launch-summary (runtime-recovery-launch-summary recovery-launch)))
    (when (endp resolved-forms)
      (error ":runtime/eval requires at least one readable form"))
    (ensure-capability-granted session policy-id)
    (append-runtime-eval-debug-log :before
                                   session
                                   resolved-package
                                   form
                                   resolved-forms)
    (maybe-replay-runtime-definition-from-history session
                                                  resolved-package
                                                  resolved-forms)
    (call-with-runtime-incident-capture
     session
     (lambda ()
       (let* ((*package* resolved-package)
              (values
                (loop for resolved-form in resolved-forms
                      finally (return (multiple-value-list (eval resolved-form)))
                      do (eval resolved-form)))
              (result (first values)))
         (append-runtime-eval-debug-log :after
                                        session
                                        resolved-package
                                        form
                                        resolved-forms
                                        :values values)
         (append-session-event session
                               :runtime-evaluated
                               (list :package (package-name *package*)
                                     :form form
                                     :mutating (not (null mutating))
                                     :policy-id policy-id))
         (append-runtime-history-entry session
                                       :eval
                                       (list :package (package-name *package*)
                                             :form form
                                             :mutating (not (null mutating))
                                             :policy-id policy-id
                                             :recovery-launch recovery-launch-summary
                                             :result result))
         (let ((work-item (and mutating
                               (create-runtime-mutation-work-item session
                                                                  form
                                                                  policy-id
                                                                  result
                                                                  :recovery-launch recovery-launch-summary))))
           (let ((artifact (create-artifact session
                                            (or *runtime-governance-thread* (current-thread session))
                                            *runtime-governance-turn*
                                            *runtime-governance-operation*
                                            :runtime-eval
                                            nil
                                            :title "Structured runtime evaluation"
                                            :summary (format nil "Evaluated ~A in ~A."
                                                             form
                                                             (package-name *package*))
                                            :work-item-id (and work-item (work-item-id work-item))
                                            :metadata (list :source :runtime/eval
                                                            :package (package-name *package*)
                                                            :form form
                                                            :mutating (not (null mutating))
                                                            :policy-id policy-id
                                                            :recovery-launch recovery-launch-summary
                                                            :work-item-id (and work-item (work-item-id work-item))
                                                            :result result))))
             (maybe-append-operation-artifact-link *runtime-governance-operation* artifact))
           (when mutating
             (maybe-sync-current-environment-from-session session))
           (list :tool :runtime/eval
                 :package (package-name *package*)
                 :form form
                 :mutating (not (null mutating))
                 :policy-id policy-id
                 :recovery-launch recovery-launch-summary
                 :work-item-id (and work-item (work-item-id work-item))
                 :result result
                 :values values
                 :sandbox-profile :in-process))))
     :kind :runtime-eval-failure
     :title "Runtime eval failed"
     :summary (format nil "Evaluation of ~A in ~A failed."
                      form
                      (package-name resolved-package))
     :metadata (list :source :runtime/eval
                     :package (package-name resolved-package)
                     :form form
                     :mutating (not (null mutating))
                     :policy-id policy-id
                     :recovery-launch recovery-launch-summary))))

(defun tool-runtime-history (session &key tail)
  (declare (ignore session))
  (let ((entries (current-environment-runtime-history)))
    (list :tool :runtime/history
          :entry-count (length entries)
          :entries (runtime-history-tail entries tail)
          :sandbox-profile :in-process)))

(defun tool-runtime-reload-file (session &key path)
  (unless path
    (error ":runtime/reload-file requires :path"))
  (ensure-capability-granted session :runtime-reload)
  (let* ((resolved (ensure-path-within-session session path :must-exist t))
         (namestring-path (namestring resolved)))
    (call-with-runtime-incident-capture
     session
     (lambda ()
       (let* ((load-result (let ((*package* (session-runtime-package session)))
                             (load resolved :verbose nil :print nil)))
              (work-item (create-runtime-reload-work-item session namestring-path load-result)))
         (append-session-event session
                               :runtime-reloaded-file
                               (list :path namestring-path
                                     :policy-id :runtime-reload
                                     :work-item-id (work-item-id work-item)))
         (append-runtime-history-entry session
                                       :reload-file
                                       (list :path namestring-path
                                             :policy-id :runtime-reload
                                             :work-item-id (work-item-id work-item)))
         (let ((artifact (create-artifact session
                                          (or *runtime-governance-thread* (current-thread session))
                                          *runtime-governance-turn*
                                          *runtime-governance-operation*
                                          :runtime-reload
                                          namestring-path
                                          :title (file-namestring resolved)
                                          :summary "Workspace source file loaded into the live image."
                                          :work-item-id (work-item-id work-item)
                                          :source-ref namestring-path
                                          :metadata (list :source :runtime/reload-file
                                                          :path namestring-path
                                                          :policy-id :runtime-reload
                                                          :work-item-id (work-item-id work-item)))))
           (maybe-append-operation-artifact-link *runtime-governance-operation* artifact))
         (maybe-sync-current-environment-from-session session)
         (list :tool :runtime/reload-file
               :path namestring-path
               :policy-id :runtime-reload
               :work-item-id (work-item-id work-item)
               :result load-result
               :sandbox-profile :in-process)))
     :kind :runtime-reload-failure
     :title "Runtime reload failed"
     :summary (format nil "Reload of ~A into the live image failed." namestring-path)
     :metadata (list :source :runtime/reload-file
                     :path namestring-path
                     :policy-id :runtime-reload))))

(register-tool :runtime/current-package
               "Return the active Common Lisp package for the current runtime session."
               :runtime-read
               #'tool-runtime-current-package)

(register-tool :runtime/list-loaded-systems
               "Return ASDF systems currently loaded in the live image."
               :runtime-read
               #'tool-runtime-list-loaded-systems)

(register-tool :runtime/describe-symbol
               "Describe a symbol visible in the current runtime package or a specified package."
               :runtime-read
               #'tool-runtime-describe-symbol)

(register-tool :runtime/inspect
               "Inspect the live value and callable shape of a symbol in the current runtime package or a specified package."
               :runtime-read
               #'tool-runtime-inspect-symbol)

(register-tool :runtime/object
               "Inspect rich live object detail for one bound symbol in the current runtime package or a specified package."
               :runtime-read
               #'tool-runtime-object-symbol)

(register-tool :runtime/find-definition
               "Locate source definitions for a symbol inside the current workspace and relate them to the live image."
               :runtime-read
               #'tool-runtime-find-definition)

(register-tool :runtime/callers
               "Locate source-level caller sites for a symbol inside the current workspace."
               :runtime-read
               #'tool-runtime-callers)

(register-tool :runtime/methods
               "List generic function methods for a symbol in the live image."
               :runtime-read
               #'tool-runtime-methods)

(register-tool :runtime/source-image-divergence
               "Report whether a symbol appears only in source, only in the image, or may have pending source/image drift."
               :runtime-read
               #'tool-runtime-source-image-divergence)

(register-tool :runtime/set-package
               "Change the active Common Lisp package for the current runtime session."
               :runtime-package-switch
               #'tool-runtime-set-package)

(register-tool :runtime/eval
               "Evaluate a form in the current runtime package with policy checks."
               :runtime-eval-safe
               #'tool-runtime-eval)

(register-tool :runtime/history
               "Return recent structured runtime operations recorded in the environment."
               :runtime-read
               #'tool-runtime-history)

(register-tool :runtime/reload-file
               "Load a workspace source file into the current live image with workflow evidence."
               :runtime-reload
               #'tool-runtime-reload-file)
