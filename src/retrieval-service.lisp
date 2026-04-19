(in-package #:sbcl-agent)

(defun patch-result-paths (result)
  (when (listp result)
    (remove nil
            (mapcan (lambda (patch-entry)
                      (cond
                        ((and (listp patch-entry) (getf patch-entry :path))
                         (list (getf patch-entry :path)))
                        ((and (listp patch-entry)
                              (listp (getf patch-entry :result))
                              (getf (getf patch-entry :result) :path))
                         (list (getf (getf patch-entry :result) :path)))
                        (t nil)))
                    (or (getf result :patch)
                        result)))))

(defun action-result-summary-entry (entry)
  (let* ((action (getf entry :action))
         (result (or (getf entry :result) '()))
         (payload (and action (assistant-action-payload action)))
         (tool-id (and action
                       (eq (assistant-action-type action) :tool)
                       payload
                       (or (getf payload :tool-id)
                           (getf payload :TOOL-ID)
                           (getf payload :tool_id)
                           (getf payload :TOOL_ID))))
         (paths (cond
                  ((eq (and action (assistant-action-type action)) :patch)
                   (remove nil
                           (mapcar (lambda (patch-op)
                                     (and (listp patch-op)
                                         (second patch-op)))
                                   payload)))
                  ((or (eq (and action (assistant-action-type action)) :patch)
                       (and tool-id
                            (member tool-id '(:workspace/write :workspace/apply-patch)
                                    :test #'eq)))
                   (patch-result-paths result))
                  (t
                   nil))))
    (list :action-type (and action (assistant-action-type action))
          :tool-id tool-id
          :status (or (getf entry :status) :completed)
          :mutating-p (and action
                           (eq (assistant-action-type action) :eval)
                           (mutating-eval-action-p action))
          :paths paths
          :error (getf entry :error))))

(defun action-result-retrieval-domains (entry)
  (let* ((action (getf entry :action))
         (status (or (getf entry :status) :completed))
         (domains '()))
    (when action
      (case (assistant-action-type action)
        (:patch
         (setf domains (append domains '(:workspace :artifact :workflow :events))))
        (:eval
         (setf domains (append domains
                               (if (mutating-eval-action-p action)
                                   '(:runtime :workflow :artifact :events)
                                   '(:runtime :events)))))
        (:tool
         (setf domains (append domains
                               (if (governed-assistant-action-p action)
                                   '(:workflow :artifact :events)
                                   '(:events)))))))
    (when (eq status :failed)
      (setf domains (append domains '(:incident :workflow :events))))
    (remove-duplicates domains :test #'eq)))

(defun copy-retrieval-intent-with-domains (intent domains)
  (make-retrieval-intent
   :category (retrieval-intent-category intent)
   :domains domains
   :historical-p (retrieval-intent-historical-p intent)
   :runtime-inspection-p (or (retrieval-intent-runtime-inspection-p intent)
                             (member :runtime domains :test #'eq))
   :governance-context-p (or (retrieval-intent-governance-context-p intent)
                             (member :workflow domains :test #'eq)
                             (member :incident domains :test #'eq))
   :source-context-p (or (retrieval-intent-source-context-p intent)
                         (member :workspace domains :test #'eq))
   :mutation-likely-p t
   :explanation (retrieval-intent-explanation intent)))

(defun copy-retrieval-plan-with-domains (plan intent domains)
  (let ((limits (copy-list (retrieval-plan-per-domain-limits plan))))
    (dolist (domain domains)
      (unless (getf limits domain)
        (setf limits (append limits
                             (list domain
                                   (retrieval-domain-limit intent domain))))))
    (make-retrieval-plan
     :intent intent
     :domains domains
     :per-domain-limits limits
     :expansion-posture :expand-on-gap
     :runtime-detail-p (or (retrieval-plan-runtime-detail-p plan)
                           (member :runtime domains :test #'eq))
     :governance-detail-p (or (retrieval-plan-governance-detail-p plan)
                              (member :workflow domains :test #'eq)
                              (member :incident domains :test #'eq))
     :source-detail-p (or (retrieval-plan-source-detail-p plan)
                          (member :workspace domains :test #'eq))
     :semantic-ranking-p (retrieval-plan-semantic-ranking-p plan)
     :explanation "Post-mutation retrieval widened the domain set to inspect observed consequences.")))

(defun build-post-mutation-retrieval-dossier (session prompt action-results
                                              &key (operator-mode :conversation))
  (let* ((base (build-retrieval-dossier session prompt :operator-mode operator-mode))
         (observed (mapcar #'action-result-summary-entry action-results))
         (result-domains (remove-duplicates
                          (mapcan #'action-result-retrieval-domains action-results)
                          :test #'eq))
         (domains (remove-duplicates
                   (append (retrieval-intent-domains (retrieval-dossier-intent base))
                           result-domains)
                   :test #'eq))
         (intent (copy-retrieval-intent-with-domains (retrieval-dossier-intent base) domains))
         (plan (copy-retrieval-plan-with-domains (retrieval-dossier-plan base)
                                                 intent
                                                 domains)))
    (make-retrieval-dossier
     :phase :post-mutation
     :intent intent
     :plan plan
     :observed-consequences observed
     :conversation-context (when (find :conversation domains :test #'eq)
                             (or (retrieval-dossier-conversation-context base)
                                 (build-conversation-dossier-section session plan)))
     :runtime-context (when (find :runtime domains :test #'eq)
                        (build-runtime-dossier-section session plan))
     :workflow-context (when (find :workflow domains :test #'eq)
                         (build-workflow-dossier-section session plan))
     :incident-context (when (find :incident domains :test #'eq)
                         (build-incident-dossier-section session plan))
     :artifact-context (when (find :artifact domains :test #'eq)
                         (build-artifact-dossier-section session))
     :environment-context (build-environment-dossier-section plan)
     :source-context (when (find :workspace domains :test #'eq)
                       (build-source-dossier-section))
     :gaps (append (when (and (find :workspace domains :test #'eq)
                              (null (build-source-dossier-section)))
                     (list "Workspace retrieval was requested after mutation but no source context was assembled."))
                   (when (and (find :artifact domains :test #'eq)
                              (null (build-artifact-dossier-section session)))
                     (list "Artifact retrieval was requested after mutation but no artifact context was assembled."))))))

(defun retrieval-dossier->plist (dossier)
  (let ((intent (retrieval-dossier-intent dossier))
        (plan (retrieval-dossier-plan dossier)))
    (list :phase (retrieval-dossier-phase dossier)
          :intent (list :category (retrieval-intent-category intent)
                        :domains (retrieval-intent-domains intent)
                        :historical-p (retrieval-intent-historical-p intent)
                        :runtime-inspection-p (retrieval-intent-runtime-inspection-p intent)
                        :governance-context-p (retrieval-intent-governance-context-p intent)
                        :source-context-p (retrieval-intent-source-context-p intent)
                        :mutation-likely-p (retrieval-intent-mutation-likely-p intent)
                        :explanation (retrieval-intent-explanation intent))
          :plan (list :domains (retrieval-plan-domains plan)
                      :per-domain-limits (retrieval-plan-per-domain-limits plan)
                      :expansion-posture (retrieval-plan-expansion-posture plan)
                      :expansion-pass (retrieval-plan-expansion-pass plan)
                      :runtime-detail-p (retrieval-plan-runtime-detail-p plan)
                      :governance-detail-p (retrieval-plan-governance-detail-p plan)
                      :source-detail-p (retrieval-plan-source-detail-p plan)
                      :semantic-ranking-p (retrieval-plan-semantic-ranking-p plan)
                      :explanation (retrieval-plan-explanation plan))
          :ranking (retrieval-dossier-ranking dossier)
          :observed-consequences (retrieval-dossier-observed-consequences dossier)
          :conversation-context (retrieval-dossier-conversation-context dossier)
          :runtime-context (retrieval-dossier-runtime-context dossier)
          :workflow-context (retrieval-dossier-workflow-context dossier)
          :incident-context (retrieval-dossier-incident-context dossier)
          :artifact-context (retrieval-dossier-artifact-context dossier)
          :environment-context (retrieval-dossier-environment-context dossier)
          :source-context (retrieval-dossier-source-context dossier)
          :gaps (retrieval-dossier-gaps dossier))))

(defun query-retrieval-dossier-service (session prompt &key (operator-mode :repl-bridge))
  (let ((dossier (build-retrieval-dossier session
                                          prompt
                                          :operator-mode operator-mode)))
    (make-service-query-response :retrieval
                                 :dossier
                                 (retrieval-dossier->plist dossier)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :retrieval-dossier-v1
                                                                  :session session))))

(defun query-post-mutation-retrieval-dossier-service (session prompt action-results
                                                      &key (operator-mode :conversation))
  (let ((dossier (build-post-mutation-retrieval-dossier session
                                                        prompt
                                                        action-results
                                                        :operator-mode operator-mode)))
    (setf (retrieval-dossier-ranking dossier)
          (build-retrieval-ranking prompt dossier))
    (make-service-query-response :retrieval
                                 :dossier
                                 (retrieval-dossier->plist dossier)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :retrieval-dossier-v1
                                                                  :session session))))
