(in-package #:sbcl-agent)

(defparameter *concurrency-core-worker-count* 8)

(defvar *concurrency-core-executor-lock*
  (sb-thread:make-mutex :name "concurrency-core-executor-lock"))
(defvar *concurrency-core-executor-waitqueue*
  (sb-thread:make-waitqueue :name "concurrency-core-executor-waitqueue"))
(defvar *concurrency-core-lock-table-lock*
  (sb-thread:make-mutex :name "concurrency-core-lock-table-lock"))
(defvar *concurrency-core-lock-table*
  (make-hash-table :test #'equal))
(defvar *concurrency-core-executor-queue* nil)
(defvar *concurrency-core-executor-workers* '())
(defvar *concurrency-core-executor-next-job-id* 0)
(defvar *concurrency-core-worker-thread-p* nil)

(defstruct (concurrency-core-future
             (:constructor make-concurrency-core-future-instance ()))
  done-p
  result
  error
  (lock (sb-thread:make-mutex :name "concurrency-core-future-lock"))
  (waitqueue (sb-thread:make-waitqueue :name "concurrency-core-future-waitqueue")))

(defstruct (concurrency-core-gate
             (:constructor make-concurrency-core-gate-instance
                           (&key (name "concurrency-core-gate"))))
  (lock (sb-thread:make-mutex :name name))
  (waitqueue (sb-thread:make-waitqueue :name name)))

(defstruct (concurrency-core-queue
             (:constructor make-concurrency-core-queue-instance ()))
  head
  tail)

(defstruct (concurrency-core-job
             (:constructor make-concurrency-core-job (id thunk)))
  id
  thunk
  (future (make-concurrency-core-future-instance)))

(defun concurrency-core-queue-empty-p (queue)
  (null (concurrency-core-queue-head queue)))

(defun enqueue-concurrency-core-queue (queue item)
  (let ((cell (list item)))
    (if (concurrency-core-queue-head queue)
        (setf (cdr (concurrency-core-queue-tail queue)) cell
              (concurrency-core-queue-tail queue) cell)
        (setf (concurrency-core-queue-head queue) cell
              (concurrency-core-queue-tail queue) cell)))
  item)

(defun dequeue-concurrency-core-queue (queue)
  (let ((cell (concurrency-core-queue-head queue)))
    (when cell
      (setf (concurrency-core-queue-head queue) (cdr cell))
      (when (null (concurrency-core-queue-head queue))
        (setf (concurrency-core-queue-tail queue) nil))
      (car cell))))

(defun concurrency-core-queue-items (queue)
  (copy-list (concurrency-core-queue-head queue)))

(defun remove-first-matching-concurrency-core-queue (queue predicate)
  (let ((previous nil)
        (cursor (concurrency-core-queue-head queue))
        (matched-item nil))
    (loop while cursor
          for item = (car cursor)
          do (if (funcall predicate item)
                 (progn
                   (if previous
                       (setf (cdr previous) (cdr cursor))
                       (setf (concurrency-core-queue-head queue) (cdr cursor)))
                   (when (eq cursor (concurrency-core-queue-tail queue))
                     (setf (concurrency-core-queue-tail queue) previous))
                   (when (null (concurrency-core-queue-head queue))
                     (setf (concurrency-core-queue-tail queue) nil))
                   (setf matched-item item)
                   (return))
                 (setf previous cursor
                       cursor (cdr cursor))))
    matched-item))

(defun lease-concurrency-core-queue-item (gate queue predicate
                                          &key on-match stop-p on-wait)
  (let ((leased-item nil))
    (sb-thread:with-mutex ((concurrency-core-gate-lock gate))
      (loop
        for item = (remove-first-matching-concurrency-core-queue queue predicate)
        do (cond
             (item
              (when on-match
                (funcall on-match item))
              (setf leased-item item)
              (return))
             ((and stop-p (funcall stop-p))
              (return))
             (t
              (when on-wait
                (funcall on-wait))
              (concurrency-core-gate-wait gate)))))
    leased-item))

(defun enqueue-concurrency-core-job (job)
  (sb-thread:with-mutex (*concurrency-core-executor-lock*)
    (unless *concurrency-core-executor-queue*
      (setf *concurrency-core-executor-queue*
            (make-concurrency-core-queue-instance)))
    (enqueue-concurrency-core-queue *concurrency-core-executor-queue* job)
    (sb-thread:condition-notify *concurrency-core-executor-waitqueue*))
  job)

(defun dequeue-concurrency-core-job ()
  (sb-thread:with-mutex (*concurrency-core-executor-lock*)
    (unless *concurrency-core-executor-queue*
      (setf *concurrency-core-executor-queue*
            (make-concurrency-core-queue-instance)))
    (loop while (concurrency-core-queue-empty-p *concurrency-core-executor-queue*)
          do (sb-thread:condition-wait *concurrency-core-executor-waitqueue*
                                       *concurrency-core-executor-lock*))
    (dequeue-concurrency-core-queue *concurrency-core-executor-queue*)))

(defun resolve-concurrency-core-future (future result)
  (sb-thread:with-mutex ((concurrency-core-future-lock future))
    (setf (concurrency-core-future-result future) result
          (concurrency-core-future-error future) nil
          (concurrency-core-future-done-p future) t)
    (sb-thread:condition-notify (concurrency-core-future-waitqueue future) 1))
  future)

(defun reject-concurrency-core-future (future error)
  (sb-thread:with-mutex ((concurrency-core-future-lock future))
    (setf (concurrency-core-future-result future) nil
          (concurrency-core-future-error future) error
          (concurrency-core-future-done-p future) t)
    (sb-thread:condition-notify (concurrency-core-future-waitqueue future) 1))
  future)

(defun await-concurrency-core-future (future)
  (sb-thread:with-mutex ((concurrency-core-future-lock future))
    (loop until (concurrency-core-future-done-p future)
          do (sb-thread:condition-wait (concurrency-core-future-waitqueue future)
                                       (concurrency-core-future-lock future)))
    (when (concurrency-core-future-error future)
      (error (concurrency-core-future-error future)))
    (concurrency-core-future-result future)))

(defmacro with-concurrency-core-gate ((gate) &body body)
  `(sb-thread:with-mutex ((concurrency-core-gate-lock ,gate))
     ,@body))

(defun concurrency-core-gate-wait (gate)
  (sb-thread:condition-wait (concurrency-core-gate-waitqueue gate)
                            (concurrency-core-gate-lock gate)))

(defun concurrency-core-gate-notify (gate &optional (count 1))
  (sb-thread:condition-notify (concurrency-core-gate-waitqueue gate) count))

(defun concurrency-core-gate-broadcast (gate)
  (sb-thread:condition-broadcast (concurrency-core-gate-waitqueue gate)))

(defun spawn-concurrency-core-thread (name thunk)
  (sb-thread:make-thread thunk :name name))

(defun join-concurrency-core-thread (thread)
  (when thread
    (sb-thread:join-thread thread)))

(defun run-concurrency-core-managed-thread (work-thunk &key on-error on-finally)
  (unwind-protect
       (handler-case
           (funcall work-thunk)
         (error (condition)
           (when on-error
             (funcall on-error condition))))
    (when on-finally
      (funcall on-finally))))

(defun complete-concurrency-core-job (job result error)
  (if error
      (reject-concurrency-core-future (concurrency-core-job-future job) error)
      (resolve-concurrency-core-future (concurrency-core-job-future job) result))
  job)

(defun await-concurrency-core-job (job)
  (await-concurrency-core-future (concurrency-core-job-future job)))

(defun concurrency-core-worker-loop ()
  (let ((*concurrency-core-worker-thread-p* t))
    (loop
      (let* ((job (dequeue-concurrency-core-job))
             (result nil)
             (error nil))
        (handler-case
            (setf result (funcall (concurrency-core-job-thunk job)))
          (condition (condition)
            (setf error condition)))
        (complete-concurrency-core-job job result error)))))

(defun ensure-concurrency-core-executor ()
  (sb-thread:with-mutex (*concurrency-core-executor-lock*)
    (unless *concurrency-core-executor-workers*
      (setf *concurrency-core-executor-workers*
            (loop for index from 1 to *concurrency-core-worker-count*
                  collect (spawn-concurrency-core-thread
                           (format nil "concurrency-core-worker-~D" index)
                           #'concurrency-core-worker-loop))))))

(defun call-with-concurrency-core-executor (thunk)
  (if *concurrency-core-worker-thread-p*
      (funcall thunk)
      (progn
        (ensure-concurrency-core-executor)
        (await-concurrency-core-job
         (enqueue-concurrency-core-job
          (sb-thread:with-mutex (*concurrency-core-executor-lock*)
            (make-concurrency-core-job (incf *concurrency-core-executor-next-job-id*)
                                       thunk)))))))

(defun ensure-concurrency-core-lock (key)
  (sb-thread:with-mutex (*concurrency-core-lock-table-lock*)
    (or (gethash key *concurrency-core-lock-table*)
        (setf (gethash key *concurrency-core-lock-table*)
              (sb-thread:make-mutex :name (format nil "concurrency-core-~A" key))))))

(defun call-with-concurrency-core-policy (mode thunk &key lock-key)
  (call-with-concurrency-core-executor
   (lambda ()
     (case mode
       (:serialized-write
        (sb-thread:with-mutex ((ensure-concurrency-core-lock (or lock-key :serialized-write)))
          (funcall thunk)))
       (otherwise
        (funcall thunk))))))
