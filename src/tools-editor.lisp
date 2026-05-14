(in-package #:sbcl-agent)

(defun tool-editor-append-text (session &key text scope-id buffer-id package-name pending-action-id)
  (unless text
    (error "EDITOR/APPEND-TEXT requires :text"))
  (let ((thread-id (and (boundp '*runtime-governance-thread*)
                        *runtime-governance-thread*
                        (thread-id *runtime-governance-thread*)))
        (turn-id (and (boundp '*runtime-governance-turn*)
                      *runtime-governance-turn*
                      (turn-id *runtime-governance-turn*))))
    (append-session-event session
                          :editor-buffer-updated
                          (list :mode "append"
                                :text text
                                :scope-id scope-id
                                :buffer-id buffer-id
                                :package-name package-name
                                :pending-action-id pending-action-id
                                :summary "Appended text to the active editor buffer.")
                          :family :assistant
                          :thread-id thread-id
                          :turn-id turn-id)
    (list :mode "append"
          :text text
          :scope-id scope-id
          :buffer-id buffer-id
          :package-name package-name
          :pending-action-id pending-action-id
          :receiver-actor :editor
          :receiver-state :completed
          :summary "Appended text to the active editor buffer.")))

(register-tool :editor/append-text
               "Append text to the active editor buffer shown in the Surface editor panel."
               :workspace-write
               #'tool-editor-append-text)
