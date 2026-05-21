(in-package #:sbcl-agent.system.policy)

(defparameter +control-plane-package-prefixes+
  '("SBCL-AGENT.SYSTEM.KERNEL"
    "SBCL-AGENT.SYSTEM.ACTOR-RUNTIME"
    "SBCL-AGENT.SYSTEM.POLICY"
    "SBCL-AGENT.SYSTEM.REGISTRY"
    "SBCL-AGENT.SYSTEM.TRACE"))

(defparameter +work-plane-package-prefixes+
  '("SBCL-AGENT.WORK.WORKSPACE"))

(defparameter +candidate-package-prefixes+
  '("SBCL-AGENT.CANDIDATE.ACTOR"))

(defparameter +generated-package-prefixes+
  '("SBCL-AGENT.GENERATED.SYSTEM"))

(defun package-designator-name (package-designator)
  (typecase package-designator
    (package
     (package-name package-designator))
    (symbol
     (package-designator-name (symbol-package package-designator)))
    (string
     package-designator)
    (t
     nil)))

(defun package-name-has-prefix-p (package-name prefix)
  (and (stringp package-name)
       (stringp prefix)
       (let ((package-name (string-upcase package-name))
             (prefix (string-upcase prefix)))
         (or (string= package-name prefix)
             (and (> (length package-name) (length prefix))
                  (string= package-name prefix :end1 (length prefix) :end2 (length prefix))
                  (char= (char package-name (length prefix)) #\.))))))

(defun package-name-in-prefix-set-p (package-name prefixes)
  (some (lambda (prefix)
          (package-name-has-prefix-p package-name prefix))
        prefixes))

(defun package-trust-tier (package-designator)
  (let ((package-name (package-designator-name package-designator)))
    (cond
      ((null package-name) :unknown)
      ((package-name-in-prefix-set-p package-name +control-plane-package-prefixes+)
       :control-plane)
      ((package-name-in-prefix-set-p package-name +work-plane-package-prefixes+)
       :work-plane)
      ((package-name-in-prefix-set-p package-name +candidate-package-prefixes+)
       :candidate)
      ((package-name-in-prefix-set-p package-name +generated-package-prefixes+)
       :generated)
      (t :application))))

(defun trusted-control-plane-package-p (package-designator)
  (eq (package-trust-tier package-designator) :control-plane))

(defun mutable-work-plane-package-p (package-designator)
  (eq (package-trust-tier package-designator) :work-plane))

(defun candidate-runtime-package-p (package-designator)
  (eq (package-trust-tier package-designator) :candidate))

(defun generated-runtime-package-p (package-designator)
  (eq (package-trust-tier package-designator) :generated))
