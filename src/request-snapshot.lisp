(in-package #:sbcl-agent)


;; Snapshot cache and cached-context mechanics live in request-snapshot-cache.lisp.


;; Provider environment/context summaries live in provider-environment-context.lisp.

(defun build-provider-context-bundle (session &key thread turn prompt retrieval-dossier outcome-brief
                                        surface-context surface-actions
                                        (operator-mode :repl-bridge)
                                        attachments)
  (ensure-default-thread session)
  (let* ((snapshot (build-provider-environment-snapshot session))
         (thread-context (provider-thread-context session thread snapshot))
         (turn-context (provider-turn-context session turn snapshot))
         (session-summary (provider-session-summary session snapshot))
         (environment-context (provider-environment-context session snapshot))
         (runtime-summary (provider-runtime-summary session snapshot))
         (workspace-summary (provider-workspace-summary session snapshot))
         (policy-summary (provider-policy-summary session snapshot))
         (lightweight-conversation-p
           (lightweight-conversation-request-p prompt
                                               :operator-mode operator-mode
                                               :attachments attachments
                                               :surface-actions surface-actions))
         (cached-conversation-context-p
           (cached-conversation-context-request-p prompt
                                                 :operator-mode operator-mode
                                                 :attachments attachments
                                                 :surface-actions surface-actions))
         (base-request-snapshot
           (make-provider-request-snapshot
            :session-summary session-summary
            :thread-context thread-context
            :turn-context turn-context
            :environment-context environment-context
            :surface-context surface-context
            :surface-actions surface-actions
            :runtime-summary runtime-summary
            :workspace-summary workspace-summary
            :policy-summary policy-summary
            :retrieval-dossier nil
            :cognition-bundle nil
            :reasoning-brief nil
            :planning-brief nil
            :planning-context-packet nil
            :outcome-brief nil))
         (resolved-retrieval-dossier
           (or retrieval-dossier
               (and prompt
                    (cond
                      (lightweight-conversation-p
                       nil)
                      (cached-conversation-context-p
                       (build-cached-conversation-retrieval-dossier
                        prompt
                        base-request-snapshot
                        :operator-mode operator-mode))
                      (t
                       (service-response-data
                        (query-retrieval-dossier-service
                         session
                         prompt
                         :operator-mode operator-mode)))))))
         (resolved-cognition-bundle
           (and resolved-retrieval-dossier
                (not lightweight-conversation-p)
                (not cached-conversation-context-p)
                (build-cognition-bundle prompt
                                        session-summary
                                        environment-context
                                        resolved-retrieval-dossier
                                        :session session
                                        :outcome-brief outcome-brief
                                        :current-turn-id (and turn
                                                              (turn-id turn)))))
         (resolved-reasoning-brief
           (and resolved-cognition-bundle
                (cognition-bundle-reasoning-brief resolved-cognition-bundle)))
         (resolved-planning-brief
           (and resolved-cognition-bundle
                (cognition-bundle-planning-brief resolved-cognition-bundle)))
         (resolved-outcome-brief
           (or (and resolved-cognition-bundle
                    (cognition-bundle-outcome-brief resolved-cognition-bundle))
               outcome-brief))
         (planning-context-packet
           (and resolved-cognition-bundle
                (build-provider-planning-context-packet prompt
                                                        operator-mode
                                                        nil
                                                        session-summary
                                                        session
                                                        thread-context
                                                        turn-context
                                                        environment-context
                                                        surface-context
                                                        surface-actions
                                                        runtime-summary
                                                        workspace-summary
                                                        policy-summary
                                                        resolved-retrieval-dossier
                                                        resolved-cognition-bundle
                                                        resolved-reasoning-brief
                                                        resolved-planning-brief
                                                        resolved-outcome-brief))))
    (make-provider-context-bundle
     :snapshot snapshot
     :session-summary session-summary
     :thread-context thread-context
     :turn-context turn-context
     :environment-context environment-context
     :surface-context surface-context
     :surface-actions surface-actions
     :runtime-summary runtime-summary
     :workspace-summary workspace-summary
     :policy-summary policy-summary
     :retrieval-dossier resolved-retrieval-dossier
     :cognition-bundle resolved-cognition-bundle
     :reasoning-brief resolved-reasoning-brief
     :planning-brief resolved-planning-brief
     :planning-context-packet planning-context-packet
     :outcome-brief resolved-outcome-brief)))

(defun provider-context-bundle->request-snapshot (bundle)
  (when bundle
    (let* ((generated-at (get-universal-time))
           (base-snapshot
             (make-provider-request-snapshot
              :generated-at generated-at
              :session-summary (provider-context-bundle-session-summary bundle)
              :thread-context (provider-context-bundle-thread-context bundle)
              :turn-context (provider-context-bundle-turn-context bundle)
              :environment-context (provider-context-bundle-environment-context bundle)
              :surface-context (provider-context-bundle-surface-context bundle)
              :surface-actions (provider-context-bundle-surface-actions bundle)
              :runtime-summary (provider-context-bundle-runtime-summary bundle)
              :workspace-summary (provider-context-bundle-workspace-summary bundle)
              :policy-summary (provider-context-bundle-policy-summary bundle)
              :retrieval-dossier (provider-context-bundle-retrieval-dossier bundle)
              :cognition-bundle (provider-context-bundle-cognition-bundle bundle)
              :reasoning-brief (provider-context-bundle-reasoning-brief bundle)
              :planning-brief (provider-context-bundle-planning-brief bundle)
              :planning-context-packet (provider-context-bundle-planning-context-packet bundle)
              :outcome-brief (provider-context-bundle-outcome-brief bundle)
              :cached-context-entries nil
              :cached-context-index nil))
           (cached-context-entries (cached-conversation-context-entries base-snapshot)))
      (make-provider-request-snapshot
       :generated-at generated-at
       :session-summary (provider-context-bundle-session-summary bundle)
       :thread-context (provider-context-bundle-thread-context bundle)
       :turn-context (provider-context-bundle-turn-context bundle)
       :environment-context (provider-context-bundle-environment-context bundle)
       :surface-context (provider-context-bundle-surface-context bundle)
       :surface-actions (provider-context-bundle-surface-actions bundle)
       :runtime-summary (provider-context-bundle-runtime-summary bundle)
       :workspace-summary (provider-context-bundle-workspace-summary bundle)
       :policy-summary (provider-context-bundle-policy-summary bundle)
       :retrieval-dossier (provider-context-bundle-retrieval-dossier bundle)
       :cognition-bundle (provider-context-bundle-cognition-bundle bundle)
       :reasoning-brief (provider-context-bundle-reasoning-brief bundle)
       :planning-brief (provider-context-bundle-planning-brief bundle)
       :planning-context-packet (provider-context-bundle-planning-context-packet bundle)
       :outcome-brief (provider-context-bundle-outcome-brief bundle)
       :cached-context-entries cached-context-entries
       :cached-context-index (build-cached-context-index cached-context-entries)))))

(defun make-provider-request-from-snapshot (prompt request-snapshot
                                           &key (operator-mode :repl-bridge)
                                             stream-p
                                             attachments)
  (make-provider-request :prompt prompt
                         :attachments attachments
                         :session-summary (and request-snapshot
                                               (provider-request-snapshot-session-summary request-snapshot))
                         :thread-context (and request-snapshot
                                              (provider-request-snapshot-thread-context request-snapshot))
                         :turn-context (and request-snapshot
                                            (provider-request-snapshot-turn-context request-snapshot))
                         :environment-context (and request-snapshot
                                                 (provider-request-snapshot-environment-context request-snapshot))
                         :surface-context (and request-snapshot
                                               (provider-request-snapshot-surface-context request-snapshot))
                         :surface-actions (and request-snapshot
                                               (provider-request-snapshot-surface-actions request-snapshot))
                         :runtime-summary (and request-snapshot
                                               (provider-request-snapshot-runtime-summary request-snapshot))
                         :workspace-summary (and request-snapshot
                                                 (provider-request-snapshot-workspace-summary request-snapshot))
                         :policy-summary (and request-snapshot
                                              (provider-request-snapshot-policy-summary request-snapshot))
                         :retrieval-dossier (and request-snapshot
                                                (provider-request-snapshot-retrieval-dossier request-snapshot))
                         :cognition-bundle (and request-snapshot
                                                (provider-request-snapshot-cognition-bundle request-snapshot))
                         :reasoning-brief (and request-snapshot
                                              (provider-request-snapshot-reasoning-brief request-snapshot))
                         :planning-brief (and request-snapshot
                                             (provider-request-snapshot-planning-brief request-snapshot))
                         :planning-context-packet (and request-snapshot
                                                      (provider-request-snapshot-planning-context-packet request-snapshot))
                         :outcome-brief (and request-snapshot
                                            (provider-request-snapshot-outcome-brief request-snapshot))
                         :operator-mode operator-mode
                         :stream-p stream-p))

(defun make-provider-request-from-session (prompt session
                                          &key thread turn
                                            retrieval-dossier
                                            outcome-brief
                                            surface-context
                                            surface-actions
                                            (operator-mode :repl-bridge)
                                            stream-p
                                            attachments)
  (let* ((active-session (or session (ignore-errors (ensure-session))))
         (cached-snapshot (and active-session
                               (cached-provider-request-snapshot active-session)))
         (relevant-dirty-domains
           (and prompt
                (provider-request-relevant-dirty-domains prompt
                                                         operator-mode
                                                         attachments
                                                         surface-actions)))
         (cached-snapshot-needs-refresh-p
           (and active-session
                (provider-request-snapshot-needs-refresh-p active-session
                                                           cached-snapshot
                                                           :relevant-domains relevant-dirty-domains)))
         (base-snapshot (or cached-snapshot
                            (and active-session
                                 (or (refresh-provider-request-snapshot-cache active-session
                                                                             :thread thread
                                                                             :turn turn
                                                                             :surface-context surface-context
                                                                             :surface-actions surface-actions)
                                     (build-prompt-independent-provider-request-snapshot
                                      active-session
                                      :thread thread
                                      :turn turn
                                      :surface-context surface-context
                                      :surface-actions surface-actions)))))
         (resolved-thread-context (and active-session
                                       (provider-thread-context active-session thread)))
         (resolved-turn-context (and active-session
                                     (provider-turn-context active-session turn)))
         (resolved-snapshot (and base-snapshot
                                 (provider-request-snapshot-with-overrides
                                  base-snapshot
                                  :thread-context resolved-thread-context
                                  :turn-context resolved-turn-context
                                  :surface-context surface-context
                                  :surface-actions surface-actions)))
         (session-summary (and resolved-snapshot
                               (provider-request-snapshot-session-summary resolved-snapshot)))
         (environment-context (and resolved-snapshot
                                   (provider-request-snapshot-environment-context resolved-snapshot)))
         (lightweight-conversation-p
           (lightweight-conversation-request-p prompt
                                               :operator-mode operator-mode
                                               :attachments attachments
                                               :surface-actions surface-actions))
         (cached-conversation-context-p
           (cached-conversation-context-request-p prompt
                                                 :operator-mode operator-mode
                                                 :attachments attachments
                                                 :surface-actions surface-actions))
         (resolved-retrieval-dossier
           (or retrieval-dossier
               (and prompt
                    active-session
                    (cond
                      (lightweight-conversation-p
                       nil)
                      (cached-conversation-context-p
                       (build-cached-conversation-retrieval-dossier prompt
                                                                    resolved-snapshot
                                                                    :operator-mode operator-mode))
                      (t
                       (service-response-data
                        (query-retrieval-dossier-service active-session
                                                         prompt
                                                         :operator-mode operator-mode)))))))
         (cognition-bundle
           (and resolved-retrieval-dossier
                (not lightweight-conversation-p)
                (not cached-conversation-context-p)
                active-session
                (build-cognition-bundle prompt
                                        session-summary
                                        environment-context
                                        resolved-retrieval-dossier
                                        :session active-session
                                        :outcome-brief outcome-brief
                                        :current-turn-id (and turn
                                                              (turn-id turn)))))
         (resolved-reasoning-brief
           (and cognition-bundle
                (cognition-bundle-reasoning-brief cognition-bundle)))
         (planning-brief (and cognition-bundle
                              (cognition-bundle-planning-brief cognition-bundle)))
         (resolved-outcome-brief (or (and cognition-bundle
                                         (cognition-bundle-outcome-brief cognition-bundle))
                                     outcome-brief))
         (planning-context-packet
           (and cognition-bundle
                resolved-snapshot
                (build-provider-planning-context-packet prompt
                                                        operator-mode
                                                        stream-p
                                                        session-summary
                                                        active-session
                                                        resolved-thread-context
                                                        resolved-turn-context
                                                        environment-context
                                                        surface-context
                                                        surface-actions
                                                        (provider-request-snapshot-runtime-summary
                                                         resolved-snapshot)
                                                        (provider-request-snapshot-workspace-summary
                                                         resolved-snapshot)
                                                        (provider-request-snapshot-policy-summary
                                                         resolved-snapshot)
                                                        resolved-retrieval-dossier
                                                        cognition-bundle
                                                        resolved-reasoning-brief
                                                        planning-brief
                                                        resolved-outcome-brief)))
         (request-snapshot
           (and resolved-snapshot
                (provider-request-snapshot-with-overrides
                 resolved-snapshot
                 :retrieval-dossier resolved-retrieval-dossier
                 :cognition-bundle cognition-bundle
                 :reasoning-brief resolved-reasoning-brief
                 :planning-brief planning-brief
                 :planning-context-packet planning-context-packet
                 :outcome-brief resolved-outcome-brief))))
    (when (and active-session
               (or (null cached-snapshot)
                   cached-snapshot-needs-refresh-p))
      (schedule-provider-request-snapshot-refresh active-session
                                                  :thread thread
                                                  :turn turn
                                                  :surface-context surface-context
                                                  :surface-actions surface-actions
                                                  :domains relevant-dirty-domains))
    (make-provider-request-from-snapshot prompt
                                         request-snapshot
                                         :operator-mode operator-mode
                                         :stream-p stream-p
                                         :attachments attachments)))
