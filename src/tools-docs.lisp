(in-package #:sbcl-agent)

(defun docs-root-pathname (session)
  (uiop:ensure-directory-pathname
   (ensure-path-within-session session "docs/" :must-exist t)))

(defun resolve-doc-path (session path &key must-exist)
  (let* ((relative (or path "architecture.md"))
         (candidate (merge-pathnames (pathname relative) (docs-root-pathname session))))
    (ensure-path-within-session session
                                (enough-namestring candidate (session-root-pathname session))
                                :must-exist must-exist)))

(defun tool-docs-read (session &key path)
  (let* ((resolved (resolve-doc-path session path :must-exist t))
         (content (read-file-contents resolved)))
    (list :tool :docs/read
          :path (namestring resolved)
          :content content
          :sandbox-profile :in-process)))

(defun tool-docs-list (session &key (path ""))
  (let* ((resolved (uiop:ensure-directory-pathname
                    (resolve-doc-path session path :must-exist t)))
         (entries (sort (mapcar #'namestring (directory (merge-pathnames #P"*" resolved)))
                        #'string<)))
    (list :tool :docs/list
          :path (namestring resolved)
          :entries entries
          :sandbox-profile :in-process)))

(register-tool :docs/read
               "Read a maintained project document from the docs directory."
               :safe-read
               #'tool-docs-read)

(register-tool :docs/list
               "List maintained project documents from the docs directory."
               :safe-read
               #'tool-docs-list)
