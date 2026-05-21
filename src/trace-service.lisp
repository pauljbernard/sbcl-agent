(in-package #:sbcl-agent.system.trace)

(defun query-trace-link-list-service (session &key entity-kind entity-id relation)
  (let ((links (if (and entity-kind entity-id)
                   (entity-trace-links session entity-kind entity-id :relation relation)
                   (list-trace-links session))))
    (sbcl-agent::make-service-query-response
     :trace
     :list
     (list :entity-kind entity-kind
           :entity-id entity-id
           :relation-filter relation
           :trace-links (mapcar #'trace-link-summary links))
     :metadata (sbcl-agent::make-service-metadata :authority :environment
                                                  :read-model :trace-link-list-v1
                                                  :session session))))

(defun query-trace-link-detail-service (session trace-link-id)
  (let ((link (find-trace-link session trace-link-id)))
    (unless link
      (error "Unknown trace link ~A" trace-link-id))
    (sbcl-agent::make-service-query-response
     :trace
     :detail
     (trace-link-summary link)
     :metadata (sbcl-agent::make-service-metadata :authority :environment
                                                  :read-model :trace-link-detail-v1
                                                  :session session))))

(defun query-trace-neighborhood-service (session entity-kind entity-id &key relation)
  (sbcl-agent::make-service-query-response
   :trace
   :neighborhood
   (trace-neighborhood-summary session entity-kind entity-id :relation relation)
   :metadata (sbcl-agent::make-service-metadata :authority :environment
                                                :read-model :trace-neighborhood-v1
                                                :session session)))

(defun command-trace-link-create-service (session &key relation source-kind source-id target-kind target-id
                                                  evidence metadata (status :active))
  (let ((link (create-trace-link session
                                 :relation relation
                                 :source-kind source-kind
                                 :source-id source-id
                                 :target-kind target-kind
                                 :target-id target-id
                                 :status status
                                 :evidence evidence
                                 :metadata metadata)))
    (sbcl-agent::make-service-command-response
     :trace
     :create-link
     (trace-link-summary link)
     :metadata (sbcl-agent::make-service-metadata :authority :environment
                                                  :command-model :trace-link-command-v1
                                                  :session session))))
