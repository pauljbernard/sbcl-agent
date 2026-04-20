(in-package #:sbcl-agent)

(defstruct config
  (provider "mock" :type string)
  (model "gpt-5" :type string)
  (fast-model "gpt-4.1-mini" :type string)
  (api-base nil :type (or null string))
  (api-key nil :type (or null string))
  (api-key-present-p nil :type boolean)
  (retrieval-ranking-mode :auto :type keyword)
  (working-directory nil :type (or null string)))

(defun normalize-config-string (value)
  (let ((trimmed (and value (string-trim '(#\Space #\Tab #\Newline #\Return) value))))
    (if (and trimmed (> (length trimmed) 0))
        trimmed
        nil)))

(defun provider-key-file-names (provider-name)
  (cond
    ((member provider-name '("anthropic") :test #'string-equal)
     '("anthropic-api-key.key"))
    ((member provider-name '("google" "gemini" "google-openai-compatible" "gemini-openai-compatible")
             :test #'string-equal)
     '("gemini-api-key.key" "google-api-key.key"))
    ((member provider-name '("meta-compatible" "meta-openai-compatible") :test #'string-equal)
     '("meta-api-key.key"))
    ((member provider-name '("lm-studio" "lmstudio" "local-openai-compatible") :test #'string-equal)
     '("lm-studio-api-key.key"))
    (t
     '("openai-api-key.key" "openai-api-kay.key"))))

(defun key-file-pathnames (working-directory &optional (provider-name "openai-compatible"))
  (let ((root (uiop:ensure-directory-pathname working-directory)))
    (mapcar (lambda (name)
              (merge-pathnames (parse-namestring name) root))
            (provider-key-file-names provider-name))))

(defun load-api-key-from-file (working-directory &optional (provider-name "openai-compatible"))
  (let ((path (find-if #'probe-file (key-file-pathnames working-directory provider-name))))
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

(defun provider-default-api-base (provider-name)
  (cond
    ((member provider-name '("openai" "openai-compatible") :test #'string-equal)
     "https://api.openai.com/v1")
    ((member provider-name '("google" "gemini" "google-openai-compatible" "gemini-openai-compatible")
             :test #'string-equal)
     "https://generativelanguage.googleapis.com/v1beta/openai")
    ((member provider-name '("lm-studio" "lmstudio" "local-openai-compatible")
             :test #'string-equal)
     "http://localhost:1234/v1")
    ((member provider-name '("anthropic") :test #'string-equal)
     "https://api.anthropic.com")
    (t
     nil)))

(defun provider-default-model (provider-name)
  (cond
    ((member provider-name '("anthropic") :test #'string-equal)
     "claude-sonnet-4-20250514")
    ((member provider-name '("google" "gemini" "google-openai-compatible" "gemini-openai-compatible")
             :test #'string-equal)
     "gemini-2.5-pro")
    ((member provider-name '("lm-studio" "lmstudio" "local-openai-compatible")
             :test #'string-equal)
     "local-model")
    (t
     "gpt-5")))

(defun provider-default-fast-model (provider-name)
  (cond
    ((member provider-name '("anthropic") :test #'string-equal)
     "claude-3-5-haiku")
    ((member provider-name '("google" "gemini" "google-openai-compatible" "gemini-openai-compatible")
             :test #'string-equal)
     "gemini-2.5-flash")
    ((member provider-name '("lm-studio" "lmstudio" "local-openai-compatible")
             :test #'string-equal)
     "local-model")
    (t
     "gpt-4.1-mini")))

(defun provider-env-api-key (provider-name)
  (cond
    ((member provider-name '("anthropic") :test #'string-equal)
     (normalize-config-string (getenv "ANTHROPIC_API_KEY")))
    ((member provider-name '("google" "gemini" "google-openai-compatible" "gemini-openai-compatible")
             :test #'string-equal)
     (or (normalize-config-string (getenv "GEMINI_API_KEY"))
         (normalize-config-string (getenv "GOOGLE_API_KEY"))))
    ((member provider-name '("meta-compatible" "meta-openai-compatible") :test #'string-equal)
     (normalize-config-string (getenv "META_API_KEY")))
    ((member provider-name '("lm-studio" "lmstudio" "local-openai-compatible")
             :test #'string-equal)
     (or (normalize-config-string (getenv "LM_STUDIO_API_KEY"))
         (normalize-config-string (getenv "LOCAL_OPENAI_API_KEY"))))
    (t
     (normalize-config-string (getenv "OPENAI_API_KEY")))))

(defun resolve-config-provider-name (explicit-provider working-directory)
  (let* ((provider (normalize-config-string explicit-provider))
         (openai-key (or (provider-env-api-key "openai-compatible")
                         (load-api-key-from-file working-directory "openai-compatible")))
         (anthropic-key (or (provider-env-api-key "anthropic")
                            (load-api-key-from-file working-directory "anthropic")))
         (gemini-key (or (provider-env-api-key "gemini")
                         (load-api-key-from-file working-directory "gemini"))))
    (or provider
        (and openai-key "openai-compatible")
        (and anthropic-key "anthropic")
        (and gemini-key "gemini")
        "mock")))

(defun resolve-provider-api-key (provider-name working-directory)
  (or (provider-env-api-key provider-name)
      (load-api-key-from-file working-directory provider-name)
      (and (member provider-name '("lm-studio" "lmstudio" "local-openai-compatible")
                   :test #'string-equal)
           "lm-studio")))

(defun parse-retrieval-ranking-mode (value)
  (let ((normalized (normalize-config-string value)))
    (cond
      ((or (null normalized)
           (string-equal normalized "auto"))
       :auto)
      ((member normalized '("off" "disabled" "false" "0") :test #'string-equal)
       :off)
      ((member normalized '("on" "enabled" "true" "1") :test #'string-equal)
       :on)
      (t
       :auto))))

(defun load-config (&key (working-directory (namestring (getcwd))))
  (let* ((normalized-working-directory (namestring (uiop:ensure-directory-pathname working-directory)))
         (explicit-provider (normalize-config-string (getenv "TUTOR_CODEX_PROVIDER")))
         (provider-name (resolve-config-provider-name explicit-provider normalized-working-directory))
         (api-key (resolve-provider-api-key provider-name normalized-working-directory)))
    (make-config
     :provider provider-name
     :model (or (getenv "TUTOR_CODEX_MODEL")
                (provider-default-model provider-name))
     :fast-model (or (getenv "TUTOR_CODEX_FAST_MODEL")
                     (provider-default-fast-model provider-name))
     :api-base (or (normalize-config-string (getenv "TUTOR_CODEX_API_BASE"))
                   (provider-default-api-base provider-name))
     :api-key api-key
     :api-key-present-p (not (null api-key))
     :retrieval-ranking-mode (parse-retrieval-ranking-mode
                              (getenv "TUTOR_CODEX_RETRIEVAL_RANKING"))
     :working-directory normalized-working-directory)))

(defun config-with-overrides (config &key provider model fast-model api-base api-key retrieval-ranking-mode
                                     working-directory)
  (let* ((resolved-working-directory (or working-directory
                                         (config-working-directory config)
                                         (namestring (uiop:ensure-directory-pathname (getcwd)))))
         (normalized-working-directory
           (namestring (uiop:ensure-directory-pathname resolved-working-directory)))
         (resolved-provider (or provider (config-provider config)))
         (resolved-api-key (or api-key
                               (config-api-key config)
                               (resolve-provider-api-key resolved-provider normalized-working-directory))))
    (make-config
     :provider resolved-provider
     :model (or model (config-model config))
     :fast-model (or fast-model (config-fast-model config))
     :api-base (or api-base
                   (config-api-base config)
                   (provider-default-api-base resolved-provider))
     :api-key resolved-api-key
     :api-key-present-p (not (null resolved-api-key))
     :retrieval-ranking-mode (or retrieval-ranking-mode
                                 (config-retrieval-ranking-mode config))
     :working-directory normalized-working-directory)))
