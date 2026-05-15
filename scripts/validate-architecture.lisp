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

(defun read-project-file (relative-path)
  (uiop:read-file-string (root-path relative-path)))

(defun contains-p (needle haystack)
  (not (null (search needle haystack :test #'char-equal))))

(defun first-position (needle haystack)
  (search needle haystack :test #'char-equal))

(defun line-number-at (string position)
  (1+ (count #\Linefeed string :end position)))

(defun validate-required-text (relative-path marker)
  (let ((content (read-project-file relative-path)))
    (unless (contains-p marker content)
      (fail "~A must contain ~S." relative-path marker))))

(defun validate-forbidden-text (relative-path marker reason)
  (let* ((content (read-project-file relative-path))
         (position (first-position marker content)))
    (when position
      (fail "~A:~D must not contain ~S (~A)."
            relative-path
            (line-number-at content position)
            marker
            reason))))

(defun validate-package-boundaries ()
  (dolist (marker '("(defpackage #:ultimate-tic-tac-toe.rules"
                    "(defpackage #:ultimate-tic-tac-toe.game"
                    "(:import-from #:ultimate-tic-tac-toe.rules"
                    "(defpackage #:ultimate-tic-tac-toe.web"
                    "(:import-from #:ultimate-tic-tac-toe.game"))
    (validate-required-text "src/package.lisp" marker)))

(defun validate-rules-boundary ()
  (dolist (marker '("ultimate-tic-tac-toe.game"
                    "ultimate-tic-tac-toe.web"
                    "hunchentoot"
                    "clack"
                    "lack"
                    "ningle"
                    "spinneret"
                    "htmx"
                    "hx-"
                    "style.css"
                    "bordeaux-threads"
                    "ironclad"))
    (validate-forbidden-text "src/rules.lisp"
                             marker
                             "rules must stay pure rule evaluation")))

(defun validate-game-boundary ()
  (dolist (marker '("ultimate-tic-tac-toe.web"
                    "hunchentoot"
                    "clack"
                    "lack"
                    "ningle"
                    "spinneret"
                    "htmx"
                    "hx-"
                    "style.css"
                    "text/html"
                    "set-cookie"
                    "content-type"))
    (validate-forbidden-text "src/game.lisp"
                             marker
                             "game state must not know about HTTP or HTML")))

(defun validate-web-boundary ()
  (validate-forbidden-text "src/web.lisp"
                           "ultimate-tic-tac-toe.rules"
                           "web should call game APIs rather than bypassing the game layer")
  (dolist (marker '("clack:"
                    "lack:"
                    "ningle:"
                    "spinneret:"))
    (validate-required-text "src/web.lisp" marker)))

(defun validate-asdf-dependency (dependency)
  (validate-required-text "ultimate-tic-tac-toe.asd"
                          (format nil "\"~A\"" dependency)))

(defun validate-nix-dependency (dependency)
  (validate-required-text "flake.nix"
                          (format nil "~%          ~A~%" dependency)))

(defun validate-dependencies ()
  (dolist (dependency '("coalton"
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
    (validate-asdf-dependency dependency))
  (dolist (dependency '("coalton"
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
    (validate-nix-dependency dependency)))

(defun validate-asdf-component-order ()
  (let ((content (read-project-file "ultimate-tic-tac-toe.asd"))
        (last-position -1))
    (dolist (component '("(:file \"package\")"
                         "(:file \"rules\")"
                         "(:file \"game\")"
                         "(:file \"web\")"))
      (let ((position (first-position component content)))
        (cond
          ((null position)
           (fail "ultimate-tic-tac-toe.asd must declare component ~S."
                 component))
          ((<= position last-position)
           (fail "ultimate-tic-tac-toe.asd must load components in package, rules, game, web order."))
          (t
           (setf last-position position)))))))

(defun main ()
  (validate-package-boundaries)
  (validate-rules-boundary)
  (validate-game-boundary)
  (validate-web-boundary)
  (validate-dependencies)
  (validate-asdf-component-order)
  (if *errors*
      (progn
        (format t "~&Architecture validation failed:~%")
        (dolist (error (reverse *errors*))
          (format t "- ~A~%" error))
        (uiop:quit 1))
      (progn
        (format t "~&Architecture validation passed.~%")
        (uiop:quit 0))))

(main)
