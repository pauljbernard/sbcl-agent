(in-package #:tutor-codex)

(defun session-root-pathname (session)
  (uiop:ensure-directory-pathname (agent-session-cwd session)))

(defun resolve-session-path (session path)
  (let ((pathname (pathname path)))
    (if (uiop:absolute-pathname-p pathname)
        pathname
        (merge-pathnames pathname (session-root-pathname session)))))

(defun read-file-contents (pathname)
  (with-open-file (stream pathname :direction :input)
    (let ((contents (make-string (file-length stream))))
      (read-sequence contents stream)
      contents)))

(defun tool-fs-read (session &key path)
  (unless path
    (error ":fs/read requires :path"))
  (let* ((resolved (ensure-path-within-session session path :must-exist t))
         (content (read-file-contents resolved)))
    (list :tool :fs/read
          :path (namestring resolved)
          :content content
          :sandbox-profile :in-process)))

(defun tool-fs-list (session &key (path "."))
  (let* ((resolved (uiop:ensure-directory-pathname
                    (ensure-path-within-session session path :must-exist t)))
         (entries (sort (mapcar #'namestring (directory (merge-pathnames #P"*" resolved)))
                        #'string<)))
    (list :tool :fs/list
          :path (namestring resolved)
          :entries entries
          :sandbox-profile :in-process)))

(register-tool :fs/read
               "Read a file from the current session workspace."
               :safe-read
               #'tool-fs-read)

(register-tool :fs/list
               "List entries in a directory from the current session workspace."
               :safe-read
               #'tool-fs-list)
