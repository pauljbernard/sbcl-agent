(in-package #:sbcl-agent)

(defun tool-desktop-show (session &key)
  (service-response-data
   (query-shell-desktop-model-service session)))

(defun tool-desktop-action (session &key action-id action-kind panel-id command index execution-id object-kind params)
  (service-response-data
   (command-shell-desktop-action-service
    session
    (append (when action-id (list :action-id action-id))
            (when action-kind (list :action-kind action-kind))
            (when panel-id (list :panel-id panel-id))
            (when command (list :command command))
            (when index (list :index index))
            (when execution-id (list :execution-id execution-id))
            (when object-kind (list :object-kind object-kind))
            (when params (list :params params))))))

(register-tool :desktop/show
               "Return the current Surface desktop model, including available panels and actions."
               :safe-read
               #'tool-desktop-show)

(register-tool :desktop/action
               "Execute one structured Surface desktop action such as activate-panel, select-panel, open-panel, restore-panel, show-panel, step-panel, or control-panel."
               :desktop-control
               #'tool-desktop-action)
