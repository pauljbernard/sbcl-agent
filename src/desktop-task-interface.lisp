(in-package #:sbcl-agent)

;; Compile-time surface declaration for the desktop-task service facade.
;; These entry points are implemented across the desktop-task stack but are
;; invoked from later-loaded application surface files such as execution-handle-service.
(declaim
 (ftype (function (&rest t) t)
        command-desktop-task-ack-context-chat-approval-service
        command-desktop-task-apply-editor-authorization-service
        command-desktop-task-consume-editor-authorization-service
        command-desktop-task-dequeue-governance-approval-service
        command-desktop-task-invoke-service
        query-desktop-task-actor-flow-service
        query-desktop-task-actor-replies-service
        query-desktop-task-dead-letter-queue-service
        query-desktop-task-editor-authorization-mailbox-service
        query-desktop-task-governance-decision-outbox-service
        query-desktop-task-governance-inbox-service
        query-desktop-task-governance-state-service
        query-desktop-task-pending-approval-service
        query-desktop-task-runtime-outbox-service
        query-desktop-task-runtime-state-service))
