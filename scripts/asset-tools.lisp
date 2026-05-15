;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults *load-truename*))

(defparameter *project-root*
  (truename (merge-pathnames "../" (script-directory))))

(pushnew *project-root* asdf:*central-registry* :test #'equal)

(asdf:load-system :ultimate-tic-tac-toe/assets)

(defpackage #:ultimate-tic-tac-toe.asset-tools
  (:use #:cl)
  (:export #:build-assets
           #:generated-stylesheet
           #:stylesheet-target-path))

(in-package #:ultimate-tic-tac-toe.asset-tools)

(defparameter *project-root*
  (asdf:system-source-directory :ultimate-tic-tac-toe))

(defparameter +stylesheet-header+
  "/* Generated from assets/style.lass. Run scripts/build-assets.lisp after edits. */")

(defun css-value-list (values)
  (format nil "~{~A~^ ~}" (mapcar #'lass:resolve values)))

(lass:define-special-property box-shadow (&rest values)
  (list (lass:make-property "box-shadow" (css-value-list values))))

(lass:define-special-property transform (&rest values)
  (list (lass:make-property "transform" (css-value-list values))))

(defun project-path (relative-path)
  (merge-pathnames relative-path *project-root*))

(defun stylesheet-source-path ()
  (project-path "assets/style.lass"))

(defun stylesheet-target-path ()
  (project-path "static/style.css"))

(defun temporary-stylesheet-path ()
  (merge-pathnames
   (format nil "ultimate-tic-tac-toe-style-~D-~D.css"
           (get-universal-time)
           (random most-positive-fixnum))
   (uiop:temporary-directory)))

(defun read-generated-lass-css ()
  (let ((temporary-path (temporary-stylesheet-path)))
    (unwind-protect
         (progn
           (lass:generate (stylesheet-source-path)
                          :out temporary-path
                          :pretty t)
           (uiop:read-file-string temporary-path))
      (when (probe-file temporary-path)
        (delete-file temporary-path)))))

(defun ensure-trailing-newline (content)
  (if (and (plusp (length content))
           (char= #\Newline (char content (1- (length content)))))
      content
      (format nil "~A~%" content)))

(defun generated-stylesheet ()
  (format nil "~A~%~%~A"
          +stylesheet-header+
          (ensure-trailing-newline (read-generated-lass-css))))

(defun build-assets ()
  (ensure-directories-exist (stylesheet-target-path))
  (with-open-file (stream (stylesheet-target-path)
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string (generated-stylesheet) stream))
  (format t "~&Generated ~A from ~A.~%"
          (enough-namestring (stylesheet-target-path) *project-root*)
          (enough-namestring (stylesheet-source-path) *project-root*)))
