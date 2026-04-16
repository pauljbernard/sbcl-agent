(in-package #:sbcl-agent)

(defstruct config
  (provider "mock" :type string)
  (model "gpt-5" :type string)
  (fast-model "gpt-4.1-mini" :type string)
  (api-base nil :type (or null string))
  (api-key nil :type (or null string))
  (api-key-present-p nil :type boolean)
  (working-directory nil :type (or null string)))

(defun normalize-config-string (value)
  (let ((trimmed (and value (string-trim '(#\Space #\Tab #\Newline #\Return) value))))
    (if (and trimmed (> (length trimmed) 0))
        trimmed
        nil)))

(defun key-file-pathnames (working-directory)
  (let ((root (uiop:ensure-directory-pathname working-directory)))
    (list (merge-pathnames #P"openai-api-key.key" root)
          (merge-pathnames #P"openai-api-kay.key" root))))

(defun load-api-key-from-file (working-directory)
  (let ((path (find-if #'probe-file (key-file-pathnames working-directory))))
    (when path
      (with-open-file (stream path :direction :input)
        (normalize-config-string
         (let ((contents (make-string (file-length stream))))
           (read-sequence contents stream)
           contents))))))

(defun resolve-provider-name (explicit-provider api-key)
  (or explicit-provider
      (and api-key "openai-compatible")
      "mock"))

(defun load-config (&key (working-directory (namestring (getcwd))))
  (let* ((normalized-working-directory (namestring (uiop:ensure-directory-pathname working-directory)))
         (api-key (or (normalize-config-string (getenv "OPENAI_API_KEY"))
                      (load-api-key-from-file normalized-working-directory)))
         (explicit-provider (normalize-config-string (getenv "TUTOR_CODEX_PROVIDER"))))
    (make-config
     :provider (resolve-provider-name explicit-provider api-key)
     :model (or (getenv "TUTOR_CODEX_MODEL") "gpt-5")
     :fast-model (or (getenv "TUTOR_CODEX_FAST_MODEL") "gpt-4.1-mini")
     :api-base (getenv "TUTOR_CODEX_API_BASE")
     :api-key api-key
     :api-key-present-p (not (null api-key))
     :working-directory normalized-working-directory)))

(defun config-with-overrides (config &key provider model api-base api-key working-directory)
  (let* ((resolved-working-directory (or working-directory
                                         (config-working-directory config)
                                         (namestring (uiop:ensure-directory-pathname (getcwd)))))
         (normalized-working-directory
           (namestring (uiop:ensure-directory-pathname resolved-working-directory)))
         (resolved-api-key (or api-key
                               (config-api-key config)
                               (load-api-key-from-file normalized-working-directory))))
    (make-config
     :provider (or provider (config-provider config))
     :model (or model (config-model config))
     :fast-model (config-fast-model config)
     :api-base (or api-base (config-api-base config))
     :api-key resolved-api-key
     :api-key-present-p (not (null resolved-api-key))
     :working-directory normalized-working-directory)))
