(in-package #:tutor-codex)

(defstruct tool-definition
  id
  documentation
  policy
  function)

(defparameter *tool-registry* (make-hash-table :test #'equal))

(defun register-tool (id documentation policy function)
  (setf (gethash id *tool-registry*)
        (make-tool-definition :id id
                              :documentation documentation
                              :policy policy
                              :function function))
  id)

(defun find-tool (id)
  (gethash id *tool-registry*))

(defun list-tools ()
  (sort
   (loop for definition being the hash-values of *tool-registry*
         collect (list :id (tool-definition-id definition)
                       :documentation (tool-definition-documentation definition)
                       :policy (tool-definition-policy definition)))
   #'string<
   :key (lambda (entry)
          (symbol-name (getf entry :id)))))

(defun describe-tool (id)
  (let ((definition (find-tool id)))
    (unless definition
      (error "Unknown tool ~S" id))
    (list :id (tool-definition-id definition)
          :documentation (tool-definition-documentation definition)
          :policy (tool-definition-policy definition))))

(defun invoke-tool (id session &rest args &key &allow-other-keys)
  (let ((definition (find-tool id)))
    (unless definition
      (error "Unknown tool ~S" id))
    (let ((policy (tool-definition-policy definition)))
      (unless (eq policy :safe-read)
        (ensure-policy-approved session policy))
      (apply (tool-definition-function definition) session args))))
