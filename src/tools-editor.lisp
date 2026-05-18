(in-package #:sbcl-agent)

(defun perform-editor-append-text (session &key text scope-id buffer-id package-name pending-action-id)
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

(defun command-editor-append-text-service (session &key text scope-id buffer-id package-name pending-action-id)
  (let* ((thread (and (boundp '*runtime-governance-thread*)
                      *runtime-governance-thread*))
         (turn (and (boundp '*runtime-governance-turn*)
                    *runtime-governance-turn*)))
    (kernelize-service-command-response
     (make-service-command-response
      :editor
      :append-text
      (perform-editor-append-text session
                                  :text text
                                  :scope-id scope-id
                                  :buffer-id buffer-id
                                  :package-name package-name
                                  :pending-action-id pending-action-id)
      :metadata (make-service-metadata :authority :environment
                                       :command-model :editor-mutation-v1
                                       :session session
                                       :thread-id (and thread (thread-id thread))
                                       :turn-id (and turn (turn-id turn))
                                       :policy-id :workspace-write))
     :session session
     :intention "Append governed text to the active editor buffer."
     :capability :editor/append-text
     :authority :workspace-write
     :context (append (when thread
                        (list :thread-id (thread-id thread)))
                      (when turn
                        (list :turn-id (turn-id turn)))
                      (when scope-id
                        (list :scope-id scope-id))
                      (when buffer-id
                        (list :buffer-id buffer-id))
                      (when package-name
                        (list :package-name package-name))
                      (when pending-action-id
                        (list :pending-action-id pending-action-id))))))

(defun tool-editor-append-text (session &key text scope-id buffer-id package-name pending-action-id)
  (service-response-data
   (command-editor-append-text-service session
                                       :text text
                                       :scope-id scope-id
                                       :buffer-id buffer-id
                                       :package-name package-name
                                       :pending-action-id pending-action-id)))

(register-tool :editor/append-text
               "Append text to the active editor buffer shown in the Surface editor panel."
               :workspace-write
               #'tool-editor-append-text)
