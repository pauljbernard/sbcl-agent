(in-package #:sbcl-agent)

(defun make-runtime-query-actor-address (session)
  (make-standard-actor-address :runtime
                               :scope (agent-session-id session)))

(defun actorize-runtime-query-response (response &key actor-execution-job-id)
  (if (and actor-execution-job-id
           (listp response))
      (let* ((metadata (copy-list (or (service-response-metadata response) '())))
             (data (service-response-data response)))
        (setf (getf metadata :actor-execution-job-id) actor-execution-job-id
              (getf response :metadata) metadata)
        (when (listp data)
          (let ((updated-data (copy-list data)))
            (setf (getf updated-data :actor-execution-job-id) actor-execution-job-id
                  (getf response :data) updated-data)))
        response)
      response))

(defun make-runtime-query-request (session action capability &key payload metadata)
  (make-governed-desktop-task-request
   :requester :context-chat
   :target :runtime
   :operation action
   :capability capability
   :payload payload
   :metadata (append (list :session-id (agent-session-id session)
                           :actor-slice :runtime-query-v1)
                     metadata)))

(defun call-with-runtime-actor (session request thunk capability action &key metadata)
  (let ((actor-address (make-runtime-query-actor-address session)))
    (call-with-actor-worker-for-request
     session
     request
     (lambda ()
       (actorize-runtime-query-response
        (funcall thunk)
        :actor-execution-job-id (current-actor-execution-job-id)))
     :context (make-actor-execution-context
               :actor-id (actor-address-id actor-address)
               :capability capability
               :authority :governance
               :target :runtime
               :operation action
               :request-id (desktop-task-request-id request)
               :metadata metadata))))

(defun runtime-service-summary-data (session)
  (let* ((environment (session-bound-environment session))
         (runtime-domain (and environment
                              (environment-runtime-domain-summary environment)))
         (package-view (tool-runtime-current-package session))
         (systems-view (tool-runtime-list-loaded-systems session))
         (package-management (sbcl-agent.bootstrap:package-management-state)))
    (list :runtime-id (or (and runtime-domain
                               (getf runtime-domain :active-runtime-id))
                          (default-runtime-id))
          :package (getf package-view :package)
          :package-details package-view
          :loaded-system-count (getf systems-view :system-count)
          :loaded-systems (getf systems-view :systems)
          :package-management package-management
          :runtime-domain runtime-domain)))

(defun query-runtime-summary-service (session)
  (make-service-query-response :runtime
                               :summary
                               (runtime-service-summary-data session)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-summary-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun runtime-package-symbol-kind (symbol)
  (cond
    ((macro-function symbol) :macro)
    ((and (fboundp symbol)
          (typep (fdefinition symbol) 'generic-function))
     :generic-function)
    ((find-class symbol nil) :class)
    ((fboundp symbol) :function)
    ((boundp symbol) :variable)
    (t :unknown)))

(defun runtime-package-symbol-summary (symbol visibility)
  (list :symbol (symbol-name symbol)
        :kind (runtime-package-symbol-kind symbol)
        :visibility visibility))

(defun runtime-package-browser-data (session package-name)
  (declare (ignore session))
  (let* ((resolved-package (or (find-package package-name)
                               (error "Unknown package ~S" package-name)))
         (available-packages (sort (remove-duplicates (mapcar #'package-name (list-all-packages))
                                                      :test #'string=)
                                   #'string<))
         (externals '())
         (internals '()))
    (do-external-symbols (symbol resolved-package)
      (push (runtime-package-symbol-summary symbol :external) externals))
    (do-symbols (symbol resolved-package)
      (multiple-value-bind (_symbol found-status)
          (find-symbol (symbol-name symbol) resolved-package)
        (declare (ignore _symbol))
        (when (eq found-status :internal)
          (push (runtime-package-symbol-summary symbol :internal) internals))))
    (list :package (package-name resolved-package)
          :available-packages available-packages
          :nicknames (sort (copy-list (package-nicknames resolved-package)) #'string<)
          :use-list (sort (mapcar #'package-name (package-use-list resolved-package)) #'string<)
          :external-symbols (sort externals #'string< :key (lambda (entry) (getf entry :symbol)))
          :internal-symbols (sort internals #'string< :key (lambda (entry) (getf entry :symbol)))
          :summary (format nil "~A exposes live namespace structure for exported and internal symbols."
                           (package-name resolved-package)))))

(defun runtime-package-browser-query-service (session package-name)
  (make-service-query-response :runtime
                               :package-browser
                               (runtime-package-browser-data session package-name)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :package-browser-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun runtime-package-browser-entry< (left right)
  (let ((package-comparison (string< (getf left :package-name) (getf right :package-name)))
        (same-package-p (string= (getf left :package-name) (getf right :package-name))))
    (or package-comparison
        (and same-package-p
             (string< (getf left :symbol) (getf right :symbol))))))

(defun runtime-symbol-page-query-data (session &key package-scope kinds visibility search offset limit)
  (declare (ignore session))
  (let* ((resolved-package-scope
           (when (and package-scope
                      (> (length package-scope) 0)
                      (not (string= package-scope "All Packages")))
             (or (find-package package-scope)
                 (error "Unknown package ~S" package-scope))))
         (available-packages (sort (remove-duplicates (mapcar #'package-name (list-all-packages))
                                                      :test #'string=)
                                   #'string<))
         (packages (if resolved-package-scope
                       (list resolved-package-scope)
                       (sort (copy-list (list-all-packages)) #'string< :key #'package-name)))
         (allowed-kinds (or kinds '()))
         (search-term (when (and search (> (length search) 0))
                        (string-downcase search)))
         (offset-value (max 0 (or offset 0)))
         (limit-value (max 1 (min 200 (or limit 32))))
         (entries '()))
    (dolist (package packages)
      (let ((package-name (package-name package)))
        (labels ((maybe-push-entry (symbol visibility-kind)
                   (let* ((symbol-kind (runtime-package-symbol-kind symbol))
                          (symbol-name (symbol-name symbol))
                          (matches-kind (or (null allowed-kinds)
                                            (member symbol-kind allowed-kinds)))
                          (matches-visibility
                            (or (null visibility)
                                (eq visibility :all)
                                (eq visibility visibility-kind)))
                          (matches-search
                            (or (null search-term)
                                (search search-term (string-downcase symbol-name))
                                (search search-term (string-downcase package-name)))))
                     (when (and matches-kind matches-visibility matches-search)
                       (push (list :package-name package-name
                                   :symbol symbol-name
                                   :kind symbol-kind
                                   :visibility visibility-kind)
                             entries)))))
          (do-external-symbols (symbol package)
            (maybe-push-entry symbol :external))
          (do-symbols (symbol package)
            (multiple-value-bind (_symbol found-status)
                (find-symbol (symbol-name symbol) package)
              (declare (ignore _symbol))
              (when (eq found-status :internal)
                (maybe-push-entry symbol :internal)))))))
    (let* ((sorted-entries (sort entries #'runtime-package-browser-entry<))
           (total-count (length sorted-entries))
           (paged-entries (subseq sorted-entries
                                  (min offset-value total-count)
                                  (min total-count (+ offset-value limit-value)))))
      (list :package-scope (and resolved-package-scope (package-name resolved-package-scope))
            :available-packages available-packages
            :nicknames (if resolved-package-scope
                           (sort (copy-list (package-nicknames resolved-package-scope)) #'string<)
                           '())
            :use-list (if resolved-package-scope
                          (sort (mapcar #'package-name (package-use-list resolved-package-scope)) #'string<)
                          '())
            :total-count total-count
            :offset offset-value
            :limit limit-value
            :has-more (< (+ offset-value limit-value) total-count)
            :items paged-entries
            :summary (if resolved-package-scope
                         (format nil "~A symbol browser page." (package-name resolved-package-scope))
                         "All packages symbol browser page.")))))

(defun query-runtime-symbol-page-service (session &key package-scope kinds visibility search offset limit)
  (make-service-query-response :runtime
                               :symbol-page
                               (runtime-symbol-page-query-data session
                                                               :package-scope package-scope
                                                               :kinds kinds
                                                               :visibility visibility
                                                               :search search
                                                               :offset offset
                                                               :limit limit)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :symbol-page-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun runtime-entity-detail-kind (resolved-symbol)
  (runtime-package-symbol-kind resolved-symbol))

(defun generic-function-signature (symbol-name methods)
  (let ((primary (first methods)))
    (if primary
        (format nil "(~A ~{~A~^ ~})"
                (string-downcase symbol-name)
                (mapcar (lambda (specializer)
                          (string-downcase (princ-to-string specializer)))
                        (or (getf primary :specializers) '())))
        (format nil "(~A ...)" (string-downcase symbol-name)))))

(defun class-slot-summaries (class)
  (mapcar (lambda (slot)
            (let ((slot-name (ignore-errors (sb-mop:slot-definition-name slot))))
              (list :label "Slot"
                    :detail (if slot-name
                                (symbol-name slot-name)
                                (princ-to-string slot))
                    :emphasis nil)))
          (ignore-errors (sb-mop:class-direct-slots class))))

(defun class-relationship-summaries (class)
  (append
   (mapcar (lambda (superclass)
             (list :label "Superclass"
                   :detail (princ-to-string (or (ignore-errors (class-name superclass))
                                                superclass))
                   :emphasis nil))
           (ignore-errors (sb-mop:class-direct-superclasses class)))
   (mapcar (lambda (subclass)
             (list :label "Subclass"
                   :detail (princ-to-string (or (ignore-errors (class-name subclass))
                                                subclass))
                   :emphasis nil))
           (ignore-errors (sb-mop:class-direct-subclasses class)))))

(defun generic-method-summary (method)
  (list :label "Method"
        :detail (format nil "Specializers: (~{~A~^ ~})"
                        (mapcar #'princ-to-string
                                (or (getf method :specializers) '())))
        :emphasis (let ((qualifiers (getf method :qualifiers)))
                    (if (and qualifiers
                             (> (length qualifiers) 0))
                        (format nil "Qualifiers: ~{~A~^ ~}" qualifiers)
                        "primary"))))

(defun object-detail-facet (label value)
  (when value
    (list :label label
          :value (if (stringp value)
                     value
                     (princ-to-string value)))))

(defun object-detail-facets (detail)
  (remove nil
          (list (object-detail-facet "Object Kind" (getf detail :kind))
                (object-detail-facet "Type" (getf detail :type))
                (object-detail-facet "Class" (getf detail :class))
                (object-detail-facet "Printed" (getf detail :printed))
                (object-detail-facet "Length" (getf detail :length))
                (object-detail-facet "Count" (getf detail :count))
                (object-detail-facet "Dimensions" (getf detail :dimensions))
                (object-detail-facet "Total Size" (getf detail :total-size))
                (object-detail-facet "Element Type" (getf detail :element-type))
                (object-detail-facet "External Symbols" (getf detail :external-symbol-count))
                (object-detail-facet "Internal Symbols" (getf detail :internal-symbol-count))
                (object-detail-facet "Used Packages"
                                     (let ((used (getf detail :used-packages)))
                                       (and used (> (length used) 0)
                                            (format nil "~{~A~^, ~}" used))))
                (object-detail-facet "Used By Packages"
                                     (let ((used-by (getf detail :used-by-packages)))
                                       (and used-by (> (length used-by) 0)
                                            (format nil "~{~A~^, ~}" used-by))))
                (object-detail-facet "Boundp" (and (member :boundp detail) (getf detail :boundp)))
                (object-detail-facet "Fboundp" (and (member :fboundp detail) (getf detail :fboundp)))
                (object-detail-facet "Keywordp" (and (member :keywordp detail) (getf detail :keywordp)))
                (object-detail-facet "Constantp" (and (member :constantp detail) (getf detail :constantp)))
                (object-detail-facet "Function Kind" (getf detail :function-kind))
                (object-detail-facet "Slot Count" (getf detail :slot-count)))))

(defun object-detail-related-items (detail)
  (append
   (mapcar (lambda (slot)
             (list :label "Slot"
                   :detail (or (getf slot :printed)
                               (if (getf slot :boundp) "bound" "unbound"))
                   :emphasis (getf slot :name)))
           (or (getf detail :slots) '()))
   (mapcar (lambda (entry)
             (list :label "Preview"
                   :detail (if (stringp entry)
                               entry
                               (princ-to-string entry))
                   :emphasis nil))
           (or (getf detail :preview) '()))))

(defun runtime-entity-detail-query-data (session symbol package)
  (multiple-value-bind (resolved-package resolved-symbol status)
      (resolve-runtime-symbol session symbol package)
    (unless resolved-symbol
      (error "Symbol ~S was not found in package ~A" symbol (package-name resolved-package)))
    (let* ((entity-kind (runtime-entity-detail-kind resolved-symbol))
           (object-result (ignore-errors
                            (service-response-data
                             (query-runtime-object-service
                              session
                              symbol
                              :package (package-name resolved-package)))))
           (object-detail (and (listp object-result)
                               (getf object-result :object-detail)))
           (definition-result (tool-runtime-find-definition session
                                                            :symbol symbol
                                                            :package (package-name resolved-package)))
           (definitions (getf definition-result :definitions))
           (caller-result (tool-runtime-callers session
                                                :symbol symbol
                                                :package (package-name resolved-package)))
           (callers (getf caller-result :callers))
           (methods (and (eq entity-kind :generic-function)
                         (getf (tool-runtime-methods session
                                                     :symbol symbol
                                                     :package (package-name resolved-package))
                               :methods)))
           (class (and (eq entity-kind :class)
                       (find-class resolved-symbol nil)))
           (direct-slots (and class (ignore-errors (sb-mop:class-direct-slots class))))
           (direct-superclasses (and class (ignore-errors (sb-mop:class-direct-superclasses class))))
           (direct-subclasses (and class (ignore-errors (sb-mop:class-direct-subclasses class))))
           (facets (append
                    (list (list :label "Entity Kind"
                                :value (string-downcase (symbol-name entity-kind)))
                          (list :label "Status"
                                :value (string-downcase
                                        (symbol-name
                                         (symbol-status-keyword status))))
                          (list :label "Definition Count"
                                :value (princ-to-string (length definitions)))
                          (list :label "Caller Count"
                                :value (princ-to-string (length callers)))
                          (list :label "Home Package"
                                :value (package-name resolved-package)))
                    (when methods
                      (list (list :label "Method Count"
                                  :value (princ-to-string (length methods)))))
                    (when class
                      (list (list :label "Direct Slots"
                                  :value (princ-to-string (length direct-slots)))
                            (list :label "Superclass Count"
                                  :value (princ-to-string (length direct-superclasses)))
                            (list :label "Subclass Count"
                                  :value (princ-to-string (length direct-subclasses)))))
                    (when object-detail
                      (object-detail-facets object-detail))))
           (related-items
             (append
              (when object-detail
                (object-detail-related-items object-detail))
              (when methods
                (mapcar #'generic-method-summary methods))
              (when class
                (class-relationship-summaries class))
              (when class
                (class-slot-summaries class))
              (mapcar (lambda (caller)
                        (list :label "Caller"
                              :detail (getf caller :path)
                              :emphasis (format nil "line ~A" (getf caller :line))
                              :path (getf caller :path)
                              :line (getf caller :line)))
                      callers)
              (mapcar (lambda (definition)
                        (list :label "Definition"
                              :detail (getf definition :path)
                              :emphasis (format nil "line ~A" (getf definition :line))
                              :path (getf definition :path)
                              :line (getf definition :line)))
                      definitions))))
      (list :package (package-name resolved-package)
            :symbol (symbol-name resolved-symbol)
            :entity-kind entity-kind
            :signature (cond
                         ((eq entity-kind :generic-function)
                          (generic-function-signature (symbol-name resolved-symbol) methods))
                         ((eq entity-kind :class)
                          (format nil "(defclass ~A ...)" (string-downcase (symbol-name resolved-symbol))))
                         (t
                          (format nil "(~A ...)" (string-downcase (symbol-name resolved-symbol)))))
            :summary (cond
                       (object-detail
                        (format nil "~A resolves to a live ~A object in ~A with structured runtime detail."
                                (symbol-name resolved-symbol)
                                (or (getf object-detail :kind) "runtime")
                                (package-name resolved-package)))
                       ((eq entity-kind :generic-function)
                        (format nil "~A is a live generic function. Dispatch, methods, and definitions should stay visible together."
                                (symbol-name resolved-symbol)))
                       ((eq entity-kind :class)
                        (format nil "~A is a live class. Slots and definitions should remain inspectable from the same browser surface."
                                (symbol-name resolved-symbol)))
                       (t
                        (format nil "~A is available as a live runtime entity in ~A."
                                (symbol-name resolved-symbol)
                                (package-name resolved-package))))
            :facets facets
            :related-items related-items))))

(defun query-runtime-inspect-symbol-service (session symbol-name &key package mode)
  (unless symbol-name
    (error "runtime.inspect-symbol requires a symbol payload"))
  (make-service-query-response
   :runtime
   :inspect-symbol
   (cond
     ((string= mode "describe")
      (service-response-data
       (query-runtime-describe-symbol-service session symbol-name :package package)))
     ((string= mode "definitions")
      (service-response-data
       (query-runtime-find-definition-service session symbol-name :package package)))
     ((string= mode "callers")
      (service-response-data
       (query-runtime-callers-service session symbol-name :package package)))
     ((string= mode "methods")
      (service-response-data
       (query-runtime-methods-service session symbol-name :package package)))
     ((string= mode "divergence")
      (service-response-data
       (query-runtime-source-image-divergence-service session symbol-name :package package)))
     (t
      (error "Unsupported runtime.inspect-symbol mode ~A" mode)))
   :metadata (make-service-metadata :authority :environment
                                    :read-model :runtime-inspector-v1
                                    :session session
                                    :runtime-id (default-runtime-id))))

(defun query-runtime-entity-detail-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :entity-detail
                               (runtime-entity-detail-query-data session symbol-name package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-entity-detail-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun command-runtime-summary-query-service (session)
  (call-with-runtime-actor
   session
   (make-runtime-query-request session
                               :summary
                               :runtime/summary)
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read the current runtime summary."
                                    "runtime/summary"
                                    :authority :environment))
   :runtime/summary
   :summary))

(defun command-runtime-package-browser-query-service (session &key package-name)
  (call-with-runtime-actor
   session
   (make-runtime-query-request session
                               :package-browser
                               :runtime/package-browser
                               :payload (list :package-name package-name))
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read runtime package browser."
                                    "runtime/package-browser"
                                    :authority :environment
                                    :payload (list :package-name package-name)))
   :runtime/package-browser
   :package-browser
   :metadata (list :package-name package-name)))

(defun command-runtime-symbol-page-query-service (session &key package-scope kinds visibility search offset limit)
  (call-with-runtime-actor
   session
   (make-runtime-query-request session
                               :symbol-page
                               :runtime/symbol-page
                               :payload (list :package-scope package-scope
                                              :kinds kinds
                                              :visibility visibility
                                              :search search
                                              :offset offset
                                              :limit limit))
   (lambda ()
     (command-kernel-invoke-service session
                                    "Read runtime symbol page."
                                    "runtime/symbol-page"
                                    :authority :environment
                                    :payload (list :package-scope package-scope
                                                   :kinds kinds
                                                   :visibility visibility
                                                   :search search
                                                   :offset offset
                                                   :limit limit)))
   :runtime/symbol-page
   :symbol-page
   :metadata (list :package-scope package-scope
                   :visibility visibility
                   :search search
                   :offset offset
                   :limit limit)))

(defun command-runtime-inspect-symbol-query-service (session symbol-name &key package mode)
  (call-with-runtime-actor
   session
   (make-runtime-query-request session
                               :inspect-symbol
                               :runtime/inspect-symbol
                               :payload (list :symbol-name symbol-name
                                              :package package
                                              :mode mode))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Inspect runtime symbol ~A." symbol-name)
                                    "runtime/inspect-symbol"
                                    :authority :environment
                                    :payload (list :symbol-name symbol-name
                                                   :package package
                                                   :mode mode)))
   :runtime/inspect-symbol
   :inspect-symbol
   :metadata (list :symbol-name symbol-name
                   :package package
                   :mode mode)))

(defun command-runtime-entity-detail-query-service (session symbol-name &key package)
  (call-with-runtime-actor
   session
   (make-runtime-query-request session
                               :entity-detail
                               :runtime/entity-detail
                               :payload (list :symbol-name symbol-name
                                              :package package))
   (lambda ()
     (command-kernel-invoke-service session
                                    (format nil "Read runtime entity detail for ~A." symbol-name)
                                    "runtime/entity-detail"
                                    :authority :environment
                                    :payload (list :symbol-name symbol-name
                                                   :package package)))
   :runtime/entity-detail
   :entity-detail
   :metadata (list :symbol-name symbol-name
                   :package package)))

(defun query-runtime-describe-symbol-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :describe-symbol
                               (tool-runtime-describe-symbol session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-describe-symbol-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-inspect-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :inspect
                               (tool-runtime-inspect-symbol session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-inspect-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-object-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :object
                               (tool-runtime-object-symbol session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-object-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-condition-service (session incident-id)
  (let ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown incident ~A" incident-id))
    (make-service-query-response :runtime
                                 :condition
                                 (list :tool :runtime/condition
                                       :incident-id (incident-id incident)
                                       :kind (incident-kind incident)
                                       :status (incident-status incident)
                                       :condition (incident-condition-string incident)
                                       :condition-summary (incident-condition-summary incident)
                                       :condition-detail (incident-condition-detail incident)
                                       :runtime-context (incident-runtime-context session incident))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :runtime-condition-v1
                                                                  :session session
                                                                  :runtime-id (default-runtime-id)
                                                                  :incident-id incident-id))))

(defun query-runtime-restarts-service (session incident-id)
  (let ((incident (find-incident session incident-id)))
    (unless incident
      (error "Unknown incident ~A" incident-id))
    (let ((restart-suggestions (incident-restart-suggestions incident)))
      (make-service-query-response :runtime
                                   :restarts
                                   (list :tool :runtime/restarts
                                         :incident-id (incident-id incident)
                                         :kind (incident-kind incident)
                                         :status (incident-status incident)
                                         :restart-count (length restart-suggestions)
                                         :restart-suggestions restart-suggestions
                                         :recommended-actions
                                         (remove-if-not (lambda (action)
                                                          (eq (getf action :type) :consider-restart))
                                                        (incident-recommended-actions session incident))
                                         :runtime-context (incident-runtime-context session incident))
                                   :metadata (make-service-metadata :authority :environment
                                                                    :read-model :runtime-restarts-v1
                                                                    :session session
                                                                    :runtime-id (default-runtime-id)
                                                                    :incident-id incident-id)))))

(defun query-runtime-find-definition-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :find-definition
                               (tool-runtime-find-definition session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-find-definition-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-callers-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :callers
                               (tool-runtime-callers session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-callers-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-methods-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :methods
                               (tool-runtime-methods session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-methods-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-source-image-divergence-service (session symbol-name &key package)
  (make-service-query-response :runtime
                               :source-image-divergence
                               (tool-runtime-source-image-divergence session :symbol symbol-name :package package)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-source-image-divergence-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun query-runtime-history-service (session &key tail)
  (make-service-query-response :runtime
                               :history
                               (tool-runtime-history session :tail tail)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :runtime-history-v1
                                                                :session session
                                                                :runtime-id (default-runtime-id))))

(defun command-runtime-set-package-service (session package-name)
  (kernelize-service-command-response
   (make-service-command-response :runtime
                                  :set-package
                                  (tool-runtime-set-package session :package package-name)
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :runtime-command-v1
                                                                   :session session
                                                                   :runtime-id (default-runtime-id)
                                                                   :policy-id :runtime-package-switch))
   :session session
   :intention (format nil "Set the active runtime package to ~A." package-name)
   :capability :runtime/set-package
   :authority :runtime))

(defun command-runtime-eval-service (session form-or-source &key package mutating recovery-launch)
  (kernelize-service-command-response
   (make-service-command-response :runtime
                                  :eval
                                  (tool-runtime-eval session
                                                     :form form-or-source
                                                     :package package
                                                     :mutating mutating
                                                     :recovery-launch recovery-launch)
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :runtime-command-v1
                                                                   :session session
                                                                   :runtime-id (default-runtime-id)
                                                                   :policy-id (runtime-eval-policy-id mutating)))
   :session session
   :intention (format nil "Evaluate ~A in the live runtime.~@[ Package: ~A.~]" form-or-source package)
   :capability :runtime/eval
   :authority (if mutating :governed-runtime :runtime)
   :constraints (list :mutating mutating :package package)))

(defun command-runtime-reload-file-service (session path)
  (kernelize-service-command-response
   (make-service-command-response :runtime
                                  :reload-file
                                  (tool-runtime-reload-file session :path path)
                                  :metadata (make-service-metadata :authority :environment
                                                                   :command-model :runtime-command-v1
                                                                   :session session
                                                                   :runtime-id (default-runtime-id)
                                                                   :policy-id :runtime-reload))
   :session session
   :intention (format nil "Reload ~A into the live runtime." path)
   :capability :runtime/reload-file
   :authority :governed-runtime))
