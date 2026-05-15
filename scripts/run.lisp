;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults *load-truename*))

(defparameter *project-root*
  (truename (merge-pathnames "../" (script-directory))))

(pushnew *project-root* asdf:*central-registry* :test #'equal)

(asdf:load-system :ultimate-tic-tac-toe)

(defun configured-port ()
  (let ((raw (uiop:getenv "PORT")))
    (if raw
        (parse-integer raw :junk-allowed nil)
        4242)))

(defun configured-server ()
  (let ((raw (uiop:getenv "SERVER")))
    (if raw
        (intern (string-upcase raw) :keyword)
        :woo)))

(let ((port (configured-port)))
  (let ((server (configured-server)))
    (ultimate-tic-tac-toe.web:start :port port :server server)
    (format t "~&Ultimate Tic Tac Toe (~(~A~)) listening on http://127.0.0.1:~D/~%"
            server
            port))
  (finish-output)
  (loop (sleep 3600)))
