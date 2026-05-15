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

(let ((port (configured-port)))
  (ultimate-tic-tac-toe.web:start :port port)
  (format t "~&Ultimate Tic Tac Toe listening on http://127.0.0.1:~D/~%" port)
  (finish-output)
  (loop (sleep 3600)))
