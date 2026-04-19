(in-package #:sbcl-agent)

(defun query-mutation-review-service (session &optional turn-id)
  (make-service-query-response :mutation
                               :review
                               (mutation-review session turn-id)
                               :metadata (make-service-metadata :authority :environment
                                                                :read-model :mutation-review-v1
                                                                :session session
                                                                :turn-id turn-id)))
