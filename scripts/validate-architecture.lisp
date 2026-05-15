;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults *load-truename*))

(defparameter *project-root*
  (truename (merge-pathnames "../" (script-directory))))

(defparameter *errors* nil)

(defparameter *reader-systems*
  '("coalton"
    "named-readtables"
    "clack"
    "lack"
    "lack/middleware/session"
    "ningle"
    "spinneret"
    "clack-handler-woo"
    "clack-handler-hunchentoot"
    "hunchentoot"
    "bordeaux-threads"
    "ironclad"))

(defun fail (control &rest arguments)
  (push (apply #'format nil control arguments) *errors*))

(defun root-path (relative-path)
  (merge-pathnames relative-path *project-root*))

(defun read-project-file (relative-path)
  (uiop:read-file-string (root-path relative-path)))

(defun load-reader-systems ()
  (dolist (system *reader-systems*)
    (asdf:load-system system))
  ;; Load only package definitions so local nicknames and reader directives
  ;; match the source files without compiling the whole application.
  (load (root-path "src/package.lisp") :verbose nil :print nil))

(defun in-package-form-p (form)
  (and (consp form)
       (symbol-name= (first form) "IN-PACKAGE")))

(defun in-readtable-form-p (form)
  (and (consp form)
       (symbol-name= (first form) "IN-READTABLE")))

(defun apply-in-package-form (form)
  (let* ((name (designator-name (second form)))
         (package (find-package name)))
    (if package
        (setf *package* package)
        (fail "Package ~A is referenced by IN-PACKAGE before it is defined."
              name))))

(defun apply-in-readtable-form (form)
  (let ((readtable (uiop:symbol-call :named-readtables '#:find-readtable
                                     (second form))))
    (when readtable
      (setf *readtable* (copy-readtable readtable)))))

(defun apply-reader-directive (form)
  (cond
    ((in-package-form-p form)
     (apply-in-package-form form))
    ((in-readtable-form-p form)
     (apply-in-readtable-form form))))

(defun read-project-forms (relative-path)
  (let ((*read-eval* nil)
        (*package* (find-package "CL-USER"))
        (*readtable* *readtable*)
        (eof (gensym "EOF")))
    (with-open-file (stream (root-path relative-path) :direction :input)
      (loop for form = (read stream nil eof)
            until (eql form eof)
            do (apply-reader-directive form)
            collect form))))

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

(defun symbol-name= (symbol name)
  (and (symbolp symbol)
       (string-equal (symbol-name symbol) name)))

(defun designator-name (designator)
  (etypecase designator
    (string (string-upcase designator))
    (symbol (string-upcase (symbol-name designator)))))

(defun keyword= (object name)
  (and (keywordp object)
       (string-equal (symbol-name object) name)))

(defun walk-form (object function)
  (funcall function object)
  (when (consp object)
    (walk-form (car object) function)
    (walk-form (cdr object) function)))

(defun collect-package-names (package)
  (cons (package-name package)
        (package-nicknames package)))

(defun form-signals (relative-path)
  (let ((packages nil)
        (symbols nil)
        (strings nil))
    (dolist (form (read-project-forms relative-path))
      (walk-form form
                 (lambda (object)
                   (cond
                     ((symbolp object)
                      (pushnew (string-upcase (symbol-name object))
                               symbols
                               :test #'string=)
                      (when (symbol-package object)
                        (dolist (package-name (collect-package-names
                                               (symbol-package object)))
                          (pushnew package-name packages :test #'string=))))
                     ((stringp object)
                      (push object strings))))))
    (values packages symbols strings)))

(defun string-signal-present-p (marker strings)
  (some (lambda (string)
          (contains-p marker string))
        strings))

(defun validate-form-signals-absent (relative-path &key packages symbols strings reason)
  (multiple-value-bind (present-packages present-symbols present-strings)
      (form-signals relative-path)
    (dolist (package packages)
      (when (member (string-upcase package) present-packages :test #'string=)
        (fail "~A must not reference package ~A (~A)."
              relative-path
              package
              reason)))
    (dolist (symbol symbols)
      (when (member (string-upcase symbol) present-symbols :test #'string=)
        (fail "~A must not reference symbol ~A (~A)."
              relative-path
              symbol
              reason)))
    (dolist (string strings)
      (when (string-signal-present-p string present-strings)
        (fail "~A must not contain string marker ~S (~A)."
              relative-path
              string
              reason)))))

(defun validate-form-packages-present (relative-path packages reason)
  (multiple-value-bind (present-packages present-symbols present-strings)
      (form-signals relative-path)
    (declare (ignore present-symbols present-strings))
    (dolist (package packages)
      (unless (member (string-upcase package) present-packages :test #'string=)
        (fail "~A must reference package ~A (~A)."
              relative-path
              package
              reason)))))

(defun defpackage-form-p (form)
  (and (consp form)
       (symbol-name= (first form) "DEFPACKAGE")))

(defun package-form (name)
  (find (string-upcase name)
        (read-project-forms "src/package.lisp")
        :key (lambda (form)
               (when (defpackage-form-p form)
                 (designator-name (second form))))
        :test #'string=))

(defun package-option-sources (form option-name)
  (loop for option in (cddr form)
        when (and (consp option)
                  (keyword= (first option) option-name))
          append (mapcar #'designator-name (rest option))))

(defun package-import-sources (form)
  (loop for option in (cddr form)
        when (and (consp option)
                  (keyword= (first option) "IMPORT-FROM"))
          collect (designator-name (second option))))

(defun validate-package-exists (name)
  (unless (package-form name)
    (fail "src/package.lisp must define package ~A." name)))

(defun validate-package-imports (package-name required-imports forbidden-imports)
  (let ((form (package-form package-name)))
    (when form
      (let ((imports (package-import-sources form))
            (uses (package-option-sources form "USE")))
        (dolist (source required-imports)
          (unless (member (string-upcase source) imports :test #'string=)
            (fail "~A must import from ~A." package-name source)))
        (dolist (source forbidden-imports)
          (when (or (member (string-upcase source) imports :test #'string=)
                    (member (string-upcase source) uses :test #'string=))
            (fail "~A must not depend on package ~A." package-name source)))))))

(defun validate-package-boundaries ()
  (dolist (package '("ULTIMATE-TIC-TAC-TOE.RULES"
                    "ULTIMATE-TIC-TAC-TOE.GAME"
                    "ULTIMATE-TIC-TAC-TOE.WEB"))
    (validate-package-exists package))
  (validate-package-imports "ULTIMATE-TIC-TAC-TOE.RULES"
                            nil
                            '("ULTIMATE-TIC-TAC-TOE.GAME"
                              "ULTIMATE-TIC-TAC-TOE.WEB"))
  (validate-package-imports "ULTIMATE-TIC-TAC-TOE.GAME"
                            '("ULTIMATE-TIC-TAC-TOE.RULES")
                            '("ULTIMATE-TIC-TAC-TOE.WEB"))
  (validate-package-imports "ULTIMATE-TIC-TAC-TOE.WEB"
                            '("ULTIMATE-TIC-TAC-TOE.GAME")
                            '("ULTIMATE-TIC-TAC-TOE.RULES")))

(defun validate-rules-boundary ()
  (validate-form-signals-absent
   "src/rules.lisp"
   :packages '("ULTIMATE-TIC-TAC-TOE.GAME"
               "ULTIMATE-TIC-TAC-TOE.WEB"
               "HUNCHENTOOT"
               "WOO"
               "CLACK"
               "LACK"
               "LACK/BUILDER"
               "NINGLE"
               "NINGLE/APP"
               "SPINNERET"
               "LASS"
               "BORDEAUX-THREADS"
               "IRONCLAD"
               "USOCKET")
   :symbols '("HTMX" "CONTENT-TYPE" "SET-COOKIE")
   :strings '("hx-" "style.css" "text/html")
   :reason "rules must stay pure rule evaluation"))

(defun validate-game-boundary ()
  (validate-form-signals-absent
   "src/game.lisp"
   :packages '("ULTIMATE-TIC-TAC-TOE.WEB"
               "HUNCHENTOOT"
               "WOO"
               "CLACK"
               "LACK"
               "LACK/BUILDER"
               "NINGLE"
               "NINGLE/APP"
               "SPINNERET"
               "LASS"
               "USOCKET")
   :symbols '("HTMX" "CONTENT-TYPE" "SET-COOKIE")
   :strings '("hx-" "style.css" "text/html" "set-cookie" "content-type")
   :reason "game state must not know about HTTP or HTML"))

(defun validate-web-boundary ()
  (validate-form-signals-absent
   "src/web.lisp"
   :packages '("ULTIMATE-TIC-TAC-TOE.RULES"
               "CLACK.HANDLER.HUNCHENTOOT"
               "LASS")
   :reason "web should call game APIs, keep private adapter lookup quarantined, and leave stylesheet generation to asset scripts")
  (validate-form-packages-present
   "src/web.lisp"
   '("CLACK" "LACK/BUILDER" "NINGLE/APP" "SPINNERET")
   "web must remain the HTTP and HTML boundary"))

(defun validate-client-script-boundary ()
  (dolist (marker '(("fetch(" "client scripting must not add a JSON/RPC request layer")
                    ("XMLHttpRequest" "client scripting must not add a JSON/RPC request layer")
                    ("localStorage" "game state must stay server-side")
                    ("sessionStorage" "game state must stay server-side")
                    ("indexedDB" "game state must stay server-side")
                    ("history.pushState" "routing must stay hypermedia-driven")
                    ("history.replaceState" "routing must stay hypermedia-driven")
                    ("window.location" "routing must stay hypermedia-driven")
                    ("document.cookie" "session handling belongs at the HTTP boundary")))
    (destructuring-bind (text reason) marker
      (validate-forbidden-text "static/app.js" text reason))))

(defun validate-nix-dependency (dependency)
  (validate-required-text "flake.nix"
                          (format nil "~%          ~A~%" dependency)))

(defun defsystem-form-p (form)
  (and (consp form)
       (symbol-name= (first form) "DEFSYSTEM")))

(defun defsystem-name (form)
  (when (defsystem-form-p form)
    (designator-name (second form))))

(defun system-form (name)
  (find (string-upcase name)
        (read-project-forms "ultimate-tic-tac-toe.asd")
        :key #'defsystem-name
        :test #'string=))

(defun system-option (form option-name)
  (loop for (key value) on (cddr form) by #'cddr
        when (keyword= key option-name)
          return value))

(defun validate-asdf-system-dependencies (system-name dependencies)
  (let ((form (system-form system-name)))
    (if form
        (let ((actual (mapcar #'designator-name
                              (or (system-option form "DEPENDS-ON") nil))))
          (dolist (dependency dependencies)
            (unless (member (string-upcase dependency) actual :test #'string=)
              (fail "ASDF system ~A must depend on ~A."
                    system-name
                    dependency))))
        (fail "ultimate-tic-tac-toe.asd must define ASDF system ~A."
              system-name))))

(defun validate-dependencies ()
  (validate-asdf-system-dependencies
   "ultimate-tic-tac-toe"
   '("coalton"
     "named-readtables"
     "clack"
     "lack"
     "lack/middleware/session"
     "ningle"
     "spinneret"
     "clack-handler-woo"
     "clack-handler-hunchentoot"
     "hunchentoot"
     "bordeaux-threads"
     "ironclad"))
  (validate-asdf-system-dependencies
   "ultimate-tic-tac-toe/assets"
   '("lass"))
  (validate-asdf-system-dependencies
   "ultimate-tic-tac-toe/test"
   '("ultimate-tic-tac-toe" "fiveam" "usocket"))
  (dolist (dependency '("coalton"
                        "named-readtables"
                        "clack"
                        "lack"
                        "lack-middleware-session"
                        "ningle"
                        "spinneret"
                        "lass"
                        "clack-handler-woo"
                        "clack-handler-hunchentoot"
                        "hunchentoot"
                        "bordeaux-threads"
                        "ironclad"
                        "fiveam"
                        "usocket"))
    (validate-nix-dependency dependency)))

(defun collect-component-files (object)
  (cond
    ((and (consp object)
          (keyword= (first object) "FILE"))
     (list (second object)))
    ((consp object)
     (append (collect-component-files (car object))
             (collect-component-files (cdr object))))
    (t nil)))

(defun validate-asdf-component-order ()
  (let ((form (system-form "ultimate-tic-tac-toe"))
        (expected '("package" "rules" "game" "web")))
    (when form
      (let ((actual (collect-component-files (system-option form "COMPONENTS"))))
        (unless (equal expected actual)
          (fail "ultimate-tic-tac-toe.asd must load src components as ~S, got ~S."
                expected
                actual))))))

(defun main ()
  (load-reader-systems)
  (validate-package-boundaries)
  (validate-rules-boundary)
  (validate-game-boundary)
  (validate-web-boundary)
  (validate-client-script-boundary)
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
