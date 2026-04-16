(in-package #:tutor-codex)

(defun tool-git-status (session)
  (declare (ignore session))
  (error ":git/status must execute through the sandbox isolation layer"))

(defun tool-git-diff (session &key cached)
  (declare (ignore session cached))
  (error ":git/diff must execute through the sandbox isolation layer"))

(defun tool-git-add (session &key paths)
  (declare (ignore session paths))
  (error ":git/add must execute through the sandbox isolation layer"))

(defun tool-git-commit (session &key message)
  (declare (ignore session message))
  (error ":git/commit must execute through the sandbox isolation layer"))

(defun tool-git-branch (session &key name checkout)
  (declare (ignore session name checkout))
  (error ":git/branch must execute through the sandbox isolation layer"))

(register-tool :git/status
               "Show repository status in the current session workspace."
               :git-read
               #'tool-git-status
               :isolation-profile :process-run)

(register-tool :git/diff
               "Show repository diff in the current session workspace."
               :git-read
               #'tool-git-diff
               :isolation-profile :process-run)

(register-tool :git/add
               "Stage repository paths in the current session workspace."
               :git-write
               #'tool-git-add
               :isolation-profile :process-run)

(register-tool :git/commit
               "Create a commit in the current session workspace."
               :git-write
               #'tool-git-commit
               :isolation-profile :process-run)

(register-tool :git/branch
               "Create or switch branches in the current session workspace."
               :git-write
               #'tool-git-branch
               :isolation-profile :process-run)
