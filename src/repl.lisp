(in-package #:tutor-codex)

(defun prompt-line (label)
  (format *query-io* "~A" label)
  (finish-output *query-io*)
  (read-line *query-io* nil nil))

(defun start-chat-repl (provider)
  (format t "Starting chat with provider ~A. Type /quit to exit.~%"
          (provider-name provider))
  (loop
    for line = (prompt-line "you> ")
    do (cond
         ((null line)
          (format t "~%")
          (return 0))
         ((string= line "/quit")
          (return 0))
         ((string= (string-trim '(#\Space #\Tab) line) "")
          (format t "assistant> Please enter a prompt.~%"))
         (t
          (format t "assistant> ~A~%" (send-prompt provider line))))))
