;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defparameter *project-root*
  (truename (merge-pathnames "../" (script-directory))))

(defparameter *errors* nil)

(defun fail (control &rest arguments)
  (push (apply #'format nil control arguments) *errors*))

(defun root-path (relative-path)
  (merge-pathnames relative-path *project-root*))

(defun read-project-file (relative-path)
  (uiop:read-file-string (root-path relative-path)))

(defun contains-p (needle haystack)
  (not (null (search needle haystack :test #'char=))))

(defun string-starts-with-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defparameter *required-docs*
  '(("docs/README.md" ("Last reviewed:" "## Map" "## Maintenance Rules"))
    ("docs/ARCHITECTURE.md" ("Last reviewed:" "## Components" "## Boundaries" "## Mechanical Guards"))
    ("docs/HARNESS.md" ("Last reviewed:" "## Agent-First Harness" "## Common Lisp Taste" "## Feedback Loops"))
    ("docs/PRODUCT.md" ("Last reviewed:" "## App Contract" "## User Experience"))
    ("docs/RELIABILITY.md" ("Last reviewed:" "## Runtime" "## Feedback Loops"))
    ("docs/QUALITY.md" ("Last reviewed:" "## Current Grade" "## Verification Matrix" "## Known Gaps"))
    ("docs/PLANS.md" ("Last reviewed:" "## When To Create A Plan" "## Plan Location"))
    ("docs/technical-debt.md" ("Last reviewed:" "## Known Debt" "## Gardening Rule"))))

(defun validate-file-markers (relative-path markers)
  (unless (probe-file (root-path relative-path))
    (fail "~A is required but missing." relative-path))
  (when (probe-file (root-path relative-path))
    (let ((content (read-project-file relative-path)))
      (dolist (marker markers)
        (unless (contains-p marker content)
          (fail "~A must contain marker ~S." relative-path marker))))))

(defun validate-required-docs ()
  (dolist (entry *required-docs*)
    (destructuring-bind (relative-path markers) entry
      (validate-file-markers relative-path markers))))

(defun validate-agent-map ()
  (validate-file-markers "AGENTS.md"
                         '("## Start Here" "## Source Of Truth" "## Feedback Loop")))

(defun validate-lisp-spdx-headers ()
  (dolist (directory '("src/" "t/" "scripts/"))
    (dolist (pathname (uiop:directory-files (root-path directory)))
      (when (string-equal "lisp" (pathname-type pathname))
        (let ((content (uiop:read-file-string pathname)))
          (unless (string-starts-with-p ";;;; SPDX-License-Identifier: AGPL-3.0-or-later" content)
            (fail "~A must start with the AGPL SPDX header."
                  (enough-namestring pathname *project-root*))))))))

(defun main ()
  (validate-agent-map)
  (validate-required-docs)
  (validate-lisp-spdx-headers)
  (if *errors*
      (progn
        (format t "~&Repository harness validation failed:~%")
        (dolist (error (reverse *errors*))
          (format t "- ~A~%" error))
        (uiop:quit 1))
      (progn
        (format t "~&Repository harness validation passed.~%")
        (uiop:quit 0))))

(main)
