(in-package #:sbcl-agent)

(defun query-calculator-summary-service (session)
  (make-service-query-response
   :calculator
   :summary
   (sbcl-agent.calculator:calculator-summary)
   :metadata (make-service-metadata :authority :environment
                                    :read-model :calculator-summary-v1
                                    :session session
                                    :runtime-id (default-runtime-id))))

(defun command-calculator-evaluate-service (session expression &key (mode :basic) (base 10) (word-size 64) (angle-unit :radians))
  (kernelize-service-command-response
   (make-service-command-response
    :calculator
    :evaluate
    (sbcl-agent.calculator:evaluate-expression expression
                                               :mode mode
                                               :base base
                                               :word-size word-size
                                               :angle-unit angle-unit)
    :metadata (make-service-metadata :authority :environment
                                     :command-model :calculator-evaluate-v1
                                     :session session
                                     :runtime-id (default-runtime-id)
                                     :policy-id :calculator-evaluate))
   :session session
   :intention (format nil "Evaluate calculator expression ~S in ~A mode." expression mode)
   :capability :calculator/evaluate
   :authority :runtime
   :constraints (list :mode mode
                      :base base
                      :word-size word-size
                      :angle-unit angle-unit)))
