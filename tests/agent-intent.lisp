(in-package #:sbcl-agent/tests)

(defun interaction-decision-conversation-only-test ()
  (let ((decision (sbcl-agent::classify-interaction-decision
                   "Explain this architecture and help me understand how the workflow fits together."
                   :operator-mode :conversation)))
    (assert-equal :conversation
                  (sbcl-agent::interaction-decision-mode decision)
                  "explanatory prompts should remain conversation-only")
    (assert-equal :none
                  (sbcl-agent::interaction-decision-environment-effect decision)
                  "conversation-only prompts should not require environment mutation")
    (assert-equal :free
                  (sbcl-agent::interaction-decision-approval-posture decision)
                  "conversation-only prompts should not enter governed approval posture")
    (assert-equal :reply-only
                  (sbcl-agent::interaction-decision-output-target decision)
                  "conversation-only prompts should return a reply, not local work")
    (assert-true (search "does not require environment mutation"
                         (sbcl-agent::interaction-decision-explanation decision))
                 "conversation-only decisions should explain the safe non-mutating boundary")))

(defun interaction-decision-inspection-only-test ()
  (let ((decision (sbcl-agent::classify-interaction-decision
                   "Why is this failing? Investigate the runtime incident and inspect the blocked workflow."
                   :operator-mode :conversation)))
    (assert-equal :inspect
                  (sbcl-agent::interaction-decision-mode decision)
                  "diagnostic prompts should classify as inspection")
    (assert-equal :read-only
                  (sbcl-agent::interaction-decision-environment-effect decision)
                  "inspection prompts should stay read-only")
    (assert-equal :supervised
                  (sbcl-agent::interaction-decision-approval-posture decision)
                  "inspection prompts should remain supervised, not free-form mutation")
    (assert-equal :workspace-context
                  (sbcl-agent::interaction-decision-output-target decision)
                  "inspection prompts should gather workspace context rather than create source mutation")
    (assert-true (search "without mutating the environment"
                         (sbcl-agent::interaction-decision-explanation decision))
                 "inspection decisions should explicitly preserve the mutation boundary")))

(defun interaction-decision-prepare-without-write-test ()
  (let ((decision (sbcl-agent::classify-interaction-decision
                   "What would you change before patching this file? Prepare the fix but do not implement it yet."
                   :operator-mode :conversation)))
    (assert-equal :prepare
                  (sbcl-agent::interaction-decision-mode decision)
                  "planning prompts should classify as preparation")
    (assert-equal :read-only
                  (sbcl-agent::interaction-decision-environment-effect decision)
                  "preparation prompts should still avoid writes")
    (assert-equal :supervised
                  (sbcl-agent::interaction-decision-approval-posture decision)
                  "preparation prompts should stay in supervised planning posture")
    (assert-equal :local-work-item
                  (sbcl-agent::interaction-decision-output-target decision)
                  "preparation prompts should target local work context rather than direct source mutation")
    (assert-true (search "until implementation is explicitly confirmed"
                         (sbcl-agent::interaction-decision-explanation decision))
                 "preparation decisions should explain why planning does not yet mutate")))

(defun interaction-decision-direct-mutation-test ()
  (let ((decision (sbcl-agent::classify-interaction-decision
                   "Implement the fix, patch the source file, and update the workflow."
                   :operator-mode :conversation)))
    (assert-equal :mutate
                  (sbcl-agent::interaction-decision-mode decision)
                  "direct implementation prompts should classify as mutation")
    (assert-equal :write-required
                  (sbcl-agent::interaction-decision-environment-effect decision)
                  "direct implementation prompts should require writes")
    (assert-equal :governed
                  (sbcl-agent::interaction-decision-approval-posture decision)
                  "direct implementation prompts should enter governed execution posture")
    (assert-equal :source-mutation
                  (sbcl-agent::interaction-decision-output-target decision)
                  "direct implementation prompts should target source mutation")
    (assert-true (search "implementation or mutation"
                         (sbcl-agent::interaction-decision-explanation decision))
                 "mutation decisions should explain why governed change flow was entered")))

(defun interaction-decision-resume-existing-work-test ()
  (let ((decision (sbcl-agent::classify-interaction-decision
                   "Resume the blocked work item and continue this fix."
                   :operator-mode :conversation)))
    (assert-equal :mutate
                  (sbcl-agent::interaction-decision-mode decision)
                  "resume prompts should stay in mutation posture")
    (assert-equal :local-work-item
                  (sbcl-agent::interaction-decision-output-target decision)
                  "resume prompts should continue existing local work instead of defaulting to fresh source mutation")
    (assert-true (search "resumes existing work"
                         (string-downcase (sbcl-agent::interaction-decision-explanation decision)))
                 "resume decisions should explicitly explain the local work continuation path")))

(defun interaction-decision-ambiguous-safe-default-test ()
  (let ((decision (sbcl-agent::classify-interaction-decision
                   "Can you look at this and tell me what you think?"
                   :operator-mode :conversation)))
    (assert-equal :conversation
                  (sbcl-agent::interaction-decision-mode decision)
                  "ambiguous prompts should default safely to conversation")
    (assert-equal :none
                  (sbcl-agent::interaction-decision-environment-effect decision)
                  "ambiguous prompts should not trigger mutation by default")
    (assert-equal :reply-only
                  (sbcl-agent::interaction-decision-output-target decision)
                  "ambiguous prompts should default to reply-only until intent is clearer")))
