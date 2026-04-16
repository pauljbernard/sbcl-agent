(in-package #:tutor-codex)

(defstruct config
  (provider "mock" :type string)
  (model "gpt-5" :type string)
  (api-base nil :type (or null string))
  (api-key-present-p nil :type boolean)
  (working-directory nil :type (or null string)))

(defun load-config ()
  (make-config
   :provider (or (getenv "TUTOR_CODEX_PROVIDER") "mock")
   :model (or (getenv "TUTOR_CODEX_MODEL") "gpt-5")
   :api-base (getenv "TUTOR_CODEX_API_BASE")
   :api-key-present-p (not (null (getenv "OPENAI_API_KEY")))
   :working-directory (namestring (getcwd))))
