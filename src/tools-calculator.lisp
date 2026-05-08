(in-package #:sbcl-agent)

(defun tool-calculator-summary (session &key)
  (service-response-data
   (query-calculator-summary-service session)))

(defun tool-calculator-set-expression (session &key expression)
  (unless expression
    (error "CALCULATOR/SET-EXPRESSION requires :expression"))
  (service-response-data
   (command-calculator-set-expression-service session expression)))

(defun tool-calculator-append-token (session &key token)
  (unless token
    (error "CALCULATOR/APPEND-TOKEN requires :token"))
  (service-response-data
   (command-calculator-append-token-service session token)))

(defun tool-calculator-backspace (session &key)
  (service-response-data
   (command-calculator-backspace-service session)))

(defun tool-calculator-clear (session &key)
  (service-response-data
   (command-calculator-clear-service session)))

(defun tool-calculator-set-mode (session &key mode)
  (unless mode
    (error "CALCULATOR/SET-MODE requires :mode"))
  (service-response-data
   (command-calculator-set-mode-service session mode)))

(defun tool-calculator-set-base (session &key base)
  (unless base
    (error "CALCULATOR/SET-BASE requires :base"))
  (service-response-data
   (command-calculator-set-base-service session base)))

(defun tool-calculator-set-word-size (session &key word-size)
  (unless word-size
    (error "CALCULATOR/SET-WORD-SIZE requires :word-size"))
  (service-response-data
   (command-calculator-set-word-size-service session word-size)))

(defun tool-calculator-set-angle-unit (session &key angle-unit)
  (unless angle-unit
    (error "CALCULATOR/SET-ANGLE-UNIT requires :angle-unit"))
  (service-response-data
   (command-calculator-set-angle-unit-service session angle-unit)))

(defun tool-calculator-evaluate
    (session
     &key
       expression
       (mode :basic)
       (base 10)
       (word-size 64)
       (angle-unit :radians))
  (unless expression
    (error "CALCULATOR/EVALUATE requires :expression"))
  (service-response-data
   (command-calculator-evaluate-service session
                                        expression
                                        :mode mode
                                        :base base
                                        :word-size word-size
                                        :angle-unit angle-unit)))

(register-tool :calculator/summary
               "Return the current calculator modes, bases, word sizes, and angle units."
               :safe-read
               #'tool-calculator-summary)

(register-tool :calculator/set-expression
               "Replace the current calculator expression buffer."
               :calculator-control
               #'tool-calculator-set-expression)

(register-tool :calculator/append-token
               "Append one token such as 7, +, or sin( to the current calculator expression buffer."
               :calculator-control
               #'tool-calculator-append-token)

(register-tool :calculator/backspace
               "Remove the last token character from the current calculator expression buffer."
               :calculator-control
               #'tool-calculator-backspace)

(register-tool :calculator/clear
               "Clear the current calculator expression buffer and latest result."
               :calculator-control
               #'tool-calculator-clear)

(register-tool :calculator/set-mode
               "Set the calculator mode to basic, scientific, or programmer."
               :calculator-control
               #'tool-calculator-set-mode)

(register-tool :calculator/set-base
               "Set the calculator numeric base for programmer mode."
               :calculator-control
               #'tool-calculator-set-base)

(register-tool :calculator/set-word-size
               "Set the calculator word size for programmer mode."
               :calculator-control
               #'tool-calculator-set-word-size)

(register-tool :calculator/set-angle-unit
               "Set the calculator angle unit to radians or degrees."
               :calculator-control
               #'tool-calculator-set-angle-unit)

(register-tool :calculator/evaluate
               "Evaluate a calculator expression in basic, scientific, or programmer mode."
               :calculator-control
               #'tool-calculator-evaluate)
