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

(defun configured-room-storage-mode ()
  (let ((raw (uiop:getenv "UTTT_ROOM_DB")))
    (if (and raw
             (plusp (length (string-trim '(#\Space #\Tab #\Return #\Linefeed)
                                         raw))))
        "sqlite"
        "memory")))

(let ((port (configured-port)))
  (let ((server (configured-server))
        (room-storage-mode (configured-room-storage-mode)))
    (ultimate-tic-tac-toe.web:start :port port :server server)
    (format t "~&Ultimate Tic Tac Toe (~(~A~), rooms: ~A) listening on http://127.0.0.1:~D/~%"
            server
            room-storage-mode
            port))
  (finish-output)
  (loop (sleep 3600)))
