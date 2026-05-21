(in-package #:sbcl-agent)

(defstruct provider-environment-snapshot
  environment
  environment-summary
  conversation-state
  workflow-state
  incident-summary)

(declaim (notinline provider-environment-snapshot-environment
                    provider-environment-snapshot-environment-summary
                    provider-environment-snapshot-conversation-state
                    provider-environment-snapshot-workflow-state
                    provider-environment-snapshot-incident-summary))

(defstruct provider-context-bundle
  snapshot
  session-summary
  thread-context
  turn-context
  environment-context
  surface-context
  surface-actions
  runtime-summary
  workspace-summary
  policy-summary
  retrieval-dossier
  cognition-bundle
  reasoning-brief
  planning-brief
  planning-context-packet
  outcome-brief)

(declaim (notinline provider-context-bundle-snapshot
                    provider-context-bundle-session-summary
                    provider-context-bundle-thread-context
                    provider-context-bundle-turn-context
                    provider-context-bundle-environment-context
                    provider-context-bundle-surface-context
                    provider-context-bundle-surface-actions
                    provider-context-bundle-runtime-summary
                    provider-context-bundle-workspace-summary
                    provider-context-bundle-policy-summary
                    provider-context-bundle-retrieval-dossier
                    provider-context-bundle-cognition-bundle
                    provider-context-bundle-reasoning-brief
                    provider-context-bundle-planning-brief
                    provider-context-bundle-planning-context-packet
                    provider-context-bundle-outcome-brief))

(defstruct provider-request-snapshot
  generated-at
  domain-generated-at
  session-summary
  thread-context
  turn-context
  environment-context
  surface-context
  surface-actions
  runtime-summary
  workspace-summary
  policy-summary
  retrieval-dossier
  cognition-bundle
  reasoning-brief
  planning-brief
  planning-context-packet
  outcome-brief
  cached-context-entries
  cached-context-index)

(declaim (notinline provider-request-snapshot-generated-at
                    provider-request-snapshot-domain-generated-at
                    provider-request-snapshot-session-summary
                    provider-request-snapshot-thread-context
                    provider-request-snapshot-turn-context
                    provider-request-snapshot-environment-context
                    provider-request-snapshot-surface-context
                    provider-request-snapshot-surface-actions
                    provider-request-snapshot-runtime-summary
                    provider-request-snapshot-workspace-summary
                    provider-request-snapshot-policy-summary
                    provider-request-snapshot-retrieval-dossier
                    provider-request-snapshot-cognition-bundle
                    provider-request-snapshot-reasoning-brief
                    provider-request-snapshot-planning-brief
                    provider-request-snapshot-planning-context-packet
                    provider-request-snapshot-outcome-brief
                    provider-request-snapshot-cached-context-entries
                    provider-request-snapshot-cached-context-index))

(defparameter +provider-request-snapshot-cache-key+ :provider-request-snapshot-cache)
(defparameter +provider-request-snapshot-refresh-pending-key+
  :provider-request-snapshot-refresh-pending-p)
(defparameter +provider-request-snapshot-dirty-at-key+
  :provider-request-snapshot-dirty-at)
(defparameter +provider-request-snapshot-dirty-domain-times-key+
  :provider-request-snapshot-dirty-domain-times)
(defparameter +provider-request-snapshot-dirty-reasons-key+
  :provider-request-snapshot-dirty-reasons)
(defparameter +provider-request-snapshot-dirty-domains-key+
  :provider-request-snapshot-dirty-domains)
(defparameter +provider-request-snapshot-stale-seconds+ 15)
(defparameter *provider-request-snapshot-cache-lock*
  (sb-thread:make-mutex :name "sbcl-agent-provider-request-snapshot-cache"))

(defparameter +provider-request-snapshot-known-domains+
  '(:conversation :runtime :workspace :policy :environment))
