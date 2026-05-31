;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defparameter *project-root*
  (truename (merge-pathnames "../" (script-directory))))

(pushnew *project-root* asdf:*central-registry* :test #'equal)
(asdf:load-system :app)

(defun configured-port ()
  (let ((raw (uiop:getenv "PORT")))
    (if raw (parse-integer raw) 4242)))

(defun configured-server ()
  (let ((raw (uiop:getenv "SERVER")))
    (if raw (intern (string-upcase raw) :keyword) :woo)))

(let ((port (configured-port))
      (server (configured-server)))
  (app.web:start :port port :server server)
  (format t "~&Common Lisp web app (~(~A~)) listening on http://127.0.0.1:~D/~%" server port)
  (loop (sleep 3600)))
