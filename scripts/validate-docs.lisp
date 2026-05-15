;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults *load-truename*))

(defparameter *project-root*
  (truename (merge-pathnames "../" (script-directory))))

(defparameter *errors* nil)

(defun fail (control &rest arguments)
  (push (apply #'format nil control arguments) *errors*))

(defun root-path (relative-path)
  (merge-pathnames relative-path *project-root*))

(defun relative-name (pathname)
  (enough-namestring pathname *project-root*))

(defun read-project-file (relative-path)
  (uiop:read-file-string (root-path relative-path)))

(defun string-starts-with-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun contains-p (needle haystack)
  (not (null (search needle haystack :test #'char=))))

(defun line-count (string)
  (if (zerop (length string))
      0
      (+ (count #\Linefeed string)
         (if (char= #\Linefeed (char string (1- (length string))))
             0
             1))))

(defparameter *required-docs*
  '(("docs/README.md" ("Last reviewed:" "## Map" "## Maintenance Rules"))
    ("docs/ARCHITECTURE.md" ("Last reviewed:" "## Components" "## Boundaries" "## Mechanical Guards"))
    ("docs/hypermedia-architecture.md" ("Last reviewed:" "## Stack" "## Contract"))
    ("docs/PRODUCT.md" ("Last reviewed:" "## Game Contract" "## Player Experience"))
    ("docs/RELIABILITY.md" ("Last reviewed:" "## Runtime" "## Feedback Loops"))
    ("docs/QUALITY.md" ("Last reviewed:" "## Current Grade" "## Verification Matrix" "## Known Gaps"))
    ("docs/PLANS.md" ("Last reviewed:" "## When To Create A Plan" "## Plan Location"))
    ("docs/technical-debt.md" ("Last reviewed:" "## Known Debt" "## Gardening Rule"))
    ("docs/exec-plans/README.md" ("Last reviewed:" "## Layout"))))

(defparameter *agent-map-links*
  '("docs/README.md"
    "docs/ARCHITECTURE.md"
    "docs/hypermedia-architecture.md"
    "docs/PRODUCT.md"
    "docs/RELIABILITY.md"
    "docs/QUALITY.md"
    "docs/PLANS.md"
    "docs/technical-debt.md"))

(defun validate-file-exists (relative-path)
  (unless (probe-file (root-path relative-path))
    (fail "~A is required but missing." relative-path)))

(defun validate-required-docs ()
  (dolist (entry *required-docs*)
    (destructuring-bind (relative-path required-markers) entry
      (validate-file-exists relative-path)
      (when (probe-file (root-path relative-path))
        (let ((content (read-project-file relative-path)))
          (dolist (marker required-markers)
            (unless (contains-p marker content)
              (fail "~A must contain marker ~S." relative-path marker))))))))

(defun validate-link-map (relative-path links)
  (validate-file-exists relative-path)
  (when (probe-file (root-path relative-path))
    (let ((content (read-project-file relative-path)))
      (dolist (link links)
        (unless (contains-p link content)
          (fail "~A must point to ~A." relative-path link))))))

(defun validate-agent-map ()
  (validate-file-exists "AGENTS.md")
  (when (probe-file (root-path "AGENTS.md"))
    (let ((content (read-project-file "AGENTS.md")))
      (when (> (line-count content) 120)
        (fail "AGENTS.md must stay at or below 120 lines."))
      (dolist (marker '("## Start Here" "## Source Of Truth" "## Feedback Loop"))
        (unless (contains-p marker content)
          (fail "AGENTS.md must contain marker ~S." marker)))))
  (validate-link-map "AGENTS.md" *agent-map-links*))

(defun validate-lisp-spdx-headers ()
  (dolist (directory '("src/" "t/" "scripts/"))
    (dolist (pathname (uiop:directory-files (root-path directory)))
      (when (string-equal "lisp" (pathname-type pathname))
        (let ((content (uiop:read-file-string pathname)))
          (unless (string-starts-with-p ";;;; SPDX-License-Identifier: AGPL-3.0-or-later"
                                        content)
            (fail "~A must start with the AGPL SPDX header."
                  (relative-name pathname))))))))

(defun validate-docs-readme-map ()
  (validate-link-map "docs/README.md"
                     '("ARCHITECTURE.md"
                       "hypermedia-architecture.md"
                       "PRODUCT.md"
                       "RELIABILITY.md"
                       "QUALITY.md"
                       "PLANS.md"
                       "technical-debt.md"
                       "exec-plans/README.md")))

(defun main ()
  (validate-agent-map)
  (validate-required-docs)
  (validate-docs-readme-map)
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
