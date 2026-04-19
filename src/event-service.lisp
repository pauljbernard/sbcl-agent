(in-package #:sbcl-agent)

(defun event-stream-entry (event index)
  (let ((metadata (event-metadata event)))
    (list :cursor index
        :kind (event-kind event)
        :timestamp (event-timestamp event)
        :family (event-family event)
        :entity-id (event-entity-id event)
        :thread-id (event-thread-id event)
        :turn-id (event-turn-id event)
        :visibility (event-visibility event)
        :payload (event-payload event)
        :metadata metadata
        :run-id (getf metadata :run-id)
        :operation-id (getf metadata :operation-id)
        :work-item-id (getf metadata :work-item-id))))

(defun event-visible-to-stream-p (event family visibility)
  (and (or (null family)
           (eq (event-family event) family))
       (or (null visibility)
           (eq (event-visibility event) visibility))))

(defun query-service-event-stream (&key environment after-cursor limit family visibility)
  (let* ((active-environment (ensure-environment environment))
         (events (or (environment-event-log active-environment) '()))
         (start-index (if (and after-cursor (integerp after-cursor))
                          (1+ after-cursor)
                          0))
         (limit-count (cond
                        ((null limit) 50)
                        ((and (integerp limit) (plusp limit)) limit)
                        (t (error "Event stream limit must be a positive integer, got ~S" limit))))
         (entries '()))
    (loop for event in events
          for index from 0
          when (and (>= index start-index)
                    (event-visible-to-stream-p event family visibility))
            do (push (event-stream-entry event index) entries)
          when (>= (length entries) limit-count)
            do (return))
    (let* ((ordered-entries (nreverse entries))
           (next-cursor (and ordered-entries
                             (getf (first (last ordered-entries)) :cursor))))
      (make-service-query-response :events
                                   :stream
                                   (list :environment-id (environment-id active-environment)
                                         :after-cursor after-cursor
                                         :next-cursor next-cursor
                                         :limit limit-count
                                         :family family
                                         :visibility visibility
                                         :events ordered-entries)
                                   :metadata (make-service-metadata :authority :environment
                                                                    :read-model :event-stream-v1
                                                                    :environment active-environment
                                                                    :event-family family
                                                                    :visibility visibility)))))
