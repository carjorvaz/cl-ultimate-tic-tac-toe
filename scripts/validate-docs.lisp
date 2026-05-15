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

(defun contains-ci-p (needle haystack)
  (not (null (search needle haystack :test #'char-equal))))

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

(defparameter *forbidden-package-dependencies*
  '(("ultimate-tic-tac-toe.rules"
     ("ultimate-tic-tac-toe.game"
      "ultimate-tic-tac-toe.web"
      "clack"
      "lack"
      "ningle"
      "spinneret"
      "hunchentoot"))
    ("ultimate-tic-tac-toe.game"
     ("ultimate-tic-tac-toe.web"
      "clack"
      "lack"
      "ningle"
      "spinneret"
      "hunchentoot"))
    ("ultimate-tic-tac-toe.web"
     ("ultimate-tic-tac-toe.rules"))))

(defparameter *required-package-dependencies*
  '(("ultimate-tic-tac-toe.game" "ultimate-tic-tac-toe.rules")
    ("ultimate-tic-tac-toe.web" "ultimate-tic-tac-toe.game")))

(defparameter *required-asdf-dependencies*
  '("coalton"
    "named-readtables"
    "clack"
    "lack"
    "lack/middleware/session"
    "ningle"
    "spinneret"
    "clack-handler-hunchentoot"
    "hunchentoot"
    "bordeaux-threads"
    "ironclad"
    "fiveam"
    "usocket"))

(defparameter *required-nix-dependencies*
  '("coalton"
    "named-readtables"
    "clack"
    "lack"
    "lack-middleware-session"
    "ningle"
    "spinneret"
    "clack-handler-hunchentoot"
    "hunchentoot"
    "bordeaux-threads"
    "ironclad"
    "fiveam"
    "usocket"))

(defparameter *forbidden-source-dependencies*
  '(("src/rules.lisp"
     ("ultimate-tic-tac-toe.game"
      "ultimate-tic-tac-toe.web"
      "clack:"
      "lack:"
      "ningle:"
      "spinneret:"
      "hunchentoot:"
      "htmx"))
    ("src/game.lisp"
     ("ultimate-tic-tac-toe.web"
      "clack:"
      "lack:"
      "ningle:"
      "spinneret:"
      "hunchentoot:"
      "htmx"))
    ("src/web.lisp"
     ("ultimate-tic-tac-toe.rules:"))))

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

(defun defpackage-block (content package-name)
  (let* ((needle (format nil "(defpackage #:~A" package-name))
         (start (search needle content :test #'char-equal)))
    (when start
      (let ((next (search "(defpackage" content
                          :start2 (+ start (length needle))
                          :test #'char-equal)))
        (subseq content start (or next (length content)))))))

(defun validate-package-layer-boundaries ()
  (let ((content (read-project-file "src/package.lisp")))
    (dolist (entry *forbidden-package-dependencies*)
      (destructuring-bind (package-name forbidden-markers) entry
        (let ((block (defpackage-block content package-name)))
          (if block
              (dolist (marker forbidden-markers)
                (when (contains-ci-p marker block)
                  (fail "Package ~A must not depend on ~A."
                        package-name marker)))
              (fail "src/package.lisp must define package ~A." package-name)))))
    (dolist (entry *required-package-dependencies*)
      (destructuring-bind (package-name required-marker) entry
        (let ((block (defpackage-block content package-name)))
          (when (and block (not (contains-ci-p required-marker block)))
            (fail "Package ~A must depend on ~A."
                  package-name required-marker)))))))

(defun validate-source-layer-boundaries ()
  (dolist (entry *forbidden-source-dependencies*)
    (destructuring-bind (relative-path forbidden-markers) entry
      (let ((content (read-project-file relative-path)))
        (dolist (marker forbidden-markers)
          (when (contains-ci-p marker content)
            (fail "~A must not reference ~A; dependency direction is rules -> game -> web."
                  relative-path marker)))))))

(defun validate-asdf-component-order ()
  (let* ((content (read-project-file "ultimate-tic-tac-toe.asd"))
         (package-position (search "(:file \"package\")" content))
         (rules-position (search "(:file \"rules\")" content))
         (game-position (search "(:file \"game\")" content))
         (web-position (search "(:file \"web\")" content)))
    (if (and package-position rules-position game-position web-position)
        (unless (< package-position rules-position game-position web-position)
          (fail "ultimate-tic-tac-toe.asd must load src files as package, rules, game, web."))
        (fail "ultimate-tic-tac-toe.asd must list package, rules, game, and web components."))))

(defun validate-asdf-dependency-declarations ()
  (let ((content (read-project-file "ultimate-tic-tac-toe.asd")))
    (dolist (dependency *required-asdf-dependencies*)
      (unless (contains-ci-p (format nil "\"~A\"" dependency) content)
        (fail "ultimate-tic-tac-toe.asd must declare dependency ~A."
              dependency)))))

(defun validate-nix-dependency-declarations ()
  (let ((content (read-project-file "flake.nix")))
    (dolist (dependency *required-nix-dependencies*)
      (unless (contains-ci-p (format nil "~%          ~A~%" dependency)
                             content)
        (fail "flake.nix must include SBCL package ~A."
              dependency)))))

(defun validate-dependency-declarations ()
  (validate-asdf-dependency-declarations)
  (validate-nix-dependency-declarations))

(defun validate-layer-boundaries ()
  (validate-package-layer-boundaries)
  (validate-source-layer-boundaries)
  (validate-asdf-component-order)
  (validate-dependency-declarations))

(defun main ()
  (validate-agent-map)
  (validate-required-docs)
  (validate-docs-readme-map)
  (validate-lisp-spdx-headers)
  (validate-layer-boundaries)
  (if *errors*
      (progn
        (format t "~&Repository harness validation failed:~%")
        (dolist (error (reverse *errors*))
          (format t "- ~A~%" error))
        (uiop:quit 1))
      (progn
        (format t "~&Repository harness and architecture validation passed.~%")
        (uiop:quit 0))))

(main)
