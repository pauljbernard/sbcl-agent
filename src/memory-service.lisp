(in-package #:sbcl-agent)

(defun query-memory-list-service (session)
  (make-service-query-response :memory
                               :list
                               (list :entries (list-operator-memory-entries session)
                                     :entry-count (length (list-operator-memory-entries session)))
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :operator-memory-list-v1
                                                                :session session)))

(defun query-memory-detail-service (session memory-id)
  (let ((entry (find-operator-memory-entry session memory-id)))
    (unless (and entry (environment-memory-operator-memory-entry-p entry))
      (error "Unknown operator memory entry ~S" memory-id))
    (make-service-query-response :memory
                                 :detail
                                 entry
                                 :metadata (make-service-metadata :authority :environment
                                                                  :read-model :operator-memory-detail-v1
                                                                  :session session))))

(defun command-memory-update-service (session memory-id &key category attribute value summary confidence)
  (make-service-command-response :memory
                                 :update
                                 (compact-operator-memory-entry
                                  (update-operator-memory-entry session
                                                                memory-id
                                                                :category category
                                                                :attribute attribute
                                                                :value value
                                                                :summary summary
                                                                :confidence confidence))
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :operator-memory-command-v1
                                                                  :session session)))

(defun command-memory-delete-service (session memory-id)
  (delete-operator-memory-entry session memory-id)
  (make-service-command-response :memory
                                 :delete
                                 (list :memory-id memory-id
                                       :deleted-p t)
                                 :metadata (make-service-metadata :authority :environment
                                                                  :command-model :operator-memory-command-v1
                                                                  :session session)))
