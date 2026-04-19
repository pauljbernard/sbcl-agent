(in-package #:sbcl-agent)

(defun environment-session (&optional environment)
  (let ((active-environment (ensure-environment environment)))
    (let ((session (environment-compatibility-session active-environment)))
      (when (typep session 'environment-compatibility-payload)
        (setf session (compatibility-payload->session session active-environment)
              (environment-compatibility-session active-environment) session))
      (when session
        (setf *current-session* session))
      session)))

(defun bind-session-to-environment (session &optional environment)
  (let ((active-environment (ensure-environment environment)))
    (setf (environment-compatibility-session active-environment) session
          *current-session* session
          *current-environment* active-environment)
    (sync-environment-from-session active-environment session)))
