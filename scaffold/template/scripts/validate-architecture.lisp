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

(defun file-string (relative-path)
  (uiop:read-file-string (root-path relative-path)))

(defun contains-p (needle haystack)
  (not (null (search needle haystack :test #'char=))))

(defun validate-domain-boundary ()
  (let ((domain (file-string "src/domain.lisp")))
    (dolist (forbidden '("clack" "lack" "ningle" "spinneret" "style.css" "htmx"))
      (when (contains-p forbidden (string-downcase domain))
        (fail "src/domain.lisp must not reference ~A." forbidden)))))

(defun validate-asdf-order ()
  (let ((asd (file-string "app.asd")))
    (unless (< (or (search "(:file \"package\")" asd :test #'char=) most-positive-fixnum)
               (or (search "(:file \"domain\")" asd :test #'char=) 0)
               (or (search "(:file \"web\")" asd :test #'char=) 0))
      (fail "app.asd must load package, domain, then web."))))

(defun main ()
  (validate-domain-boundary)
  (validate-asdf-order)
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
