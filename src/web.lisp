;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.web)

(defparameter *server* nil)

(defparameter *server-port* nil)

(defvar *request-env* nil)

(defconstant +confetti-piece-count+ 14)

(defconstant +max-player-name-length+ 24)

(defparameter *games-path* "/games")

(defparameter *current-game-path* "/games/current")
(defparameter *current-game-moves-path* "/games/current/moves")
(defparameter *rooms-path* "/rooms")
(defparameter *legal-notices-path* "/legal")

(defparameter *health-path* "/health")

(defparameter *version-path* "/version")

(defparameter *html-content-type* "text/html; charset=utf-8")
(defparameter *plain-text-content-type* "text/plain; charset=utf-8")
(defparameter *event-stream-content-type* "text/event-stream; charset=utf-8")
(defparameter *room-update-event-name* "room-update")
(defparameter *room-event-retry-milliseconds* 500)
(defparameter *recovered-game-notice*
  "The saved game state could not be used, so a fresh game has been started.")

(defparameter *default-source-code-url*
  "https://github.com/carjorvaz/cl-ultimate-tic-tac-toe")

(defparameter *system-root*
  (asdf:system-source-directory :ultimate-tic-tac-toe))

(defparameter *clack-hunchentoot-package-name*
  "CLACK.HANDLER.HUNCHENTOOT")

(defparameter *session-state-lock*
  (bordeaux-threads:make-lock "ultimate-tic-tac-toe-session-state"))

(defparameter *room-db-environment-variable* "UTTT_ROOM_DB")

(defun nonempty-string-p (value)
  (and value
       (plusp (length (string-trim '(#\Space #\Tab #\Return #\Linefeed)
                                   value)))))

(defun normalized-room-database-path (value)
  (when (nonempty-string-p value)
    (string-trim '(#\Space #\Tab #\Return #\Linefeed) value)))

(defun configured-room-database-path ()
  (normalized-room-database-path
   (uiop:getenv *room-db-environment-variable*)))

(defun configured-room-repository (&optional (room-db (configured-room-database-path)))
  (let ((room-db (normalized-room-database-path room-db)))
    (if room-db
        (make-sqlite-room-repository room-db)
        (make-memory-room-repository))))

(defun connect-sqlite-session-database (room-db)
  (let ((connection (dbi:connect :sqlite3 :database-name room-db)))
    (dbi:do-sql connection "pragma busy_timeout = 5000")
    connection))

(defun initialize-sqlite-session-store (room-db)
  (let ((connection (connect-sqlite-session-database room-db)))
    (unwind-protect
         (dbi:do-sql connection
                     "create table if not exists sessions (id text primary key, session_data text not null)")
      (dbi:disconnect connection))))

(defun make-sqlite-session-store (room-db)
  (initialize-sqlite-session-store room-db)
  (lack.session.store.dbi:make-dbi-store
   :connector (lambda ()
                (connect-sqlite-session-database room-db))
   :disconnector #'dbi:disconnect))

(defparameter *room-database-path* (configured-room-database-path))

(defun configured-session-middleware (&optional (room-db *room-database-path*))
  (let ((room-db (normalized-room-database-path room-db)))
    (if room-db
        (list :session :keep-empty nil
              :store (make-sqlite-session-store room-db))
        '(:session :keep-empty nil))))

(defparameter *persistent-session-volatile-keys* '(:game-lock))

(defun drop-persistent-session-volatile-state (env)
  (let ((session (getf env :lack.session)))
    (when session
      (dolist (key *persistent-session-volatile-keys*)
        (remhash key session)))))

(defun wrap-persistent-session-state (app)
  (lambda (env)
    (let ((response (funcall app env)))
      (drop-persistent-session-volatile-state env)
      response)))

(defun configured-session-cleanup-middleware (&optional (room-db *room-database-path*))
  (when (normalized-room-database-path room-db)
    #'wrap-persistent-session-state))

(defparameter *room-repository* (configured-room-repository *room-database-path*))

(defparameter *board-position-labels*
  #("Top left"
    "Top"
    "Top right"
    "Left"
    "Center"
    "Right"
    "Bottom left"
    "Bottom"
    "Bottom right"))

(defparameter *static-assets*
  '(("/style.css" "static/style.css" "text/css; charset=utf-8")
    ("/htmx.min.js" "static/htmx.min.js" "application/javascript; charset=utf-8")
    ("/htmx-ext-sse.js" "static/htmx-ext-sse.js" "application/javascript; charset=utf-8")
    ("/app.js" "static/app.js" "application/javascript; charset=utf-8")
    ("/icon.svg" "static/icon.svg" "image/svg+xml")
    ("/x.svg" "static/x.svg" "image/svg+xml")
    ("/o.svg" "static/o.svg" "image/svg+xml")))

(defparameter *security-headers*
  (list :x-content-type-options "nosniff"
        :x-frame-options "DENY"
        :referrer-policy "same-origin"
        :permissions-policy "camera=(), microphone=(), geolocation=()"
        :content-security-policy
        (format nil "~{~A~^; ~}"
                '("default-src 'self'"
                  "base-uri 'none'"
                  "connect-src 'self'"
                  "form-action 'self'"
                  "frame-ancestors 'none'"
                  "img-src 'self'"
                  "object-src 'none'"
                  "script-src 'self'"
                  "style-src 'self'"))))

(defun css-classes (&rest names)
  (format nil "~{~A~^ ~}" (remove nil names)))

(defun system-path (relative-path)
  (merge-pathnames relative-path *system-root*))

(defun source-code-url ()
  (or (uiop:getenv "SOURCE_CODE_URL")
      *default-source-code-url*))

(defun repository-file-url (relative-path)
  (format nil "~A/blob/master/~A"
          (string-right-trim "/" (source-code-url))
          relative-path))

(defun app-version ()
  (asdf:component-version (asdf:find-system :ultimate-tic-tac-toe)))

(defun header-key-name (key)
  (etypecase key
    (keyword (symbol-name key))
    (symbol (symbol-name key))
    (string key)))

(defun header-present-p (headers key)
  (loop for rest on headers by #'cddr
        for name = (first rest)
        thereis (string-equal (header-key-name name)
                              (header-key-name key))))

(defun missing-default-headers (headers defaults)
  (loop for (name value) on defaults by #'cddr
        unless (header-present-p headers name)
          append (list name value)))

(defun response-headers (&key content-type headers)
  (let ((explicit-headers
          (append (when content-type
                    (list :content-type content-type))
                  headers)))
    (append explicit-headers
            (missing-default-headers explicit-headers *security-headers*))))

(defun clack-response (status body &key content-type headers)
  (list status
        (response-headers :content-type content-type :headers headers)
        (list body)))

(defun response-with-default-headers (response)
  (etypecase response
    (list
     (destructuring-bind (status headers &optional (body nil body-p)) response
       (let ((headers (append headers
                              (missing-default-headers headers *security-headers*))))
         (if body-p
             (list status headers body)
             (list status headers)))))
    (function
     (lambda (respond)
       (funcall response
                (lambda (streaming-response)
                  (funcall respond
                           (response-with-default-headers streaming-response))))))))

(defun wrap-default-headers (app)
  (lambda (env)
    (response-with-default-headers (funcall app env))))

(defun html-response (body)
  (clack-response 200 body :content-type *html-content-type*))

(defun redirect-response (location)
  (clack-response 303 "" :headers (list :location location)))

(defun not-found-response ()
  (clack-response 404
                  "Not found"
                  :content-type *plain-text-content-type*))

(defun asset-response (relative-path content-type)
  (let ((path (system-path relative-path)))
    (if (probe-file path)
        (clack-response 200
                        (uiop:read-file-string path)
                        :content-type content-type
                        :headers (list :cache-control
                                       "public, max-age=3600"))
        (not-found-response))))

(defun wrap-request-env (app)
  (lambda (env)
    (let ((*request-env* env))
      (funcall app env))))

(defun request-session ()
  (or (and *request-env*
           (getf *request-env* :lack.session))
      (error "No Lack session is bound for this request.")))

(defun current-session-value (key)
  (let ((session (and *request-env*
                      (getf *request-env* :lack.session))))
    (when session
      (gethash key session))))

(defun (setf current-session-value) (value key)
  (setf (gethash key (request-session)) value))

(defun session-equal-table (key)
  (or (current-session-value key)
      (setf (current-session-value key)
            (make-hash-table :test #'equal))))

(defun room-session-token (code)
  (let ((tokens (current-session-value :room-tokens)))
    (when tokens
      (gethash code tokens))))

(defun ensure-room-session-token (code)
  (let ((tokens (session-equal-table :room-tokens)))
    (or (gethash code tokens)
        (setf (gethash code tokens) (random-token)))))

(defun room-session-notices ()
  (session-equal-table :room-notices))

(defun remember-room-notice (code notice)
  (when notice
    (setf (gethash code (room-session-notices)) notice)))

(defun pop-room-notice (code)
  (let ((notices (current-session-value :room-notices)))
    (when notices
      (multiple-value-bind (notice presentp)
          (gethash code notices)
        (when presentp
          (remhash code notices))
        notice))))

(defun random-token ()
  (ironclad:byte-array-to-hex-string
   (ironclad:random-data 32)))

(defun token-octets (token)
  (when token
    (handler-case
        (ironclad:hex-string-to-byte-array token)
      (error () nil))))

(defun current-csrf-token ()
  (let ((session (and *request-env*
                      (getf *request-env* :lack.session))))
    (when session
      (or (gethash :csrf-token session)
          (setf (gethash :csrf-token session)
                (random-token))))))

(defun csrf-token-valid-p (submitted-token)
  (let ((expected-token (current-session-value :csrf-token)))
    (and expected-token
         submitted-token
         (= (length submitted-token) (length expected-token))
         (let ((expected-octets (token-octets expected-token))
               (submitted-octets (token-octets submitted-token)))
           (and expected-octets
                submitted-octets
                (ironclad:constant-time-equal submitted-octets
                                              expected-octets))))))

(defun reject-csrf-token ()
  (clack-response 403
                  "The form token was not valid. Reload the page and try again."
                  :content-type "text/plain; charset=utf-8"))

(defun make-session-game (&key first-player)
  (make-game :next-player (or first-player
                              (session-first-player))))

(defun current-game ()
  (let ((session (request-session)))
    (multiple-value-bind (game presentp)
        (gethash :game session)
      (if (and presentp
               (valid-game-state-p game))
          (values game nil)
          (values (setf (gethash :game session)
                        (make-session-game))
                  presentp)))))

(defun current-game-lock ()
  (let ((session (request-session)))
    (bordeaux-threads:with-lock-held (*session-state-lock*)
      (or (gethash :game-lock session)
          (setf (gethash :game-lock session)
                (bordeaux-threads:make-lock "ultimate-tic-tac-toe-game"))))))

(defmacro with-current-game-locked (() &body body)
  `(bordeaux-threads:with-lock-held ((current-game-lock))
     ,@body))

(defun pop-notice ()
  (let ((session (request-session)))
    (multiple-value-bind (notice presentp)
        (gethash :notice session)
      (when presentp
        (remhash :notice session))
      notice)))

(defun remember-notice (notice)
  (when notice
    (setf (current-session-value :notice) notice)))

(defun replace-current-game (&key first-player)
  (setf (current-session-value :game)
        (make-session-game :first-player first-player)))

(defun player-name-key (mark)
  (ecase mark
    (:x :player-x-name)
    (:o :player-o-name)))

(defun player-parameter-name (mark)
  (ecase mark
    (:x "player-x")
    (:o "player-o")))

(defun player-input-id (mark)
  (ecase mark
    (:x "player-x-name")
    (:o "player-o-name")))

(defun clean-player-name (value mark)
  (declare (ignore mark))
  (let ((trimmed (and value
                      (string-trim '(#\Space #\Tab #\Return #\Linefeed)
                                   value))))
    (when (and trimmed (plusp (length trimmed)))
      (subseq trimmed 0 (min (length trimmed) +max-player-name-length+)))))

(defun player-name (mark)
  (or (current-session-value (player-name-key mark))
      (player-label mark)))

(defun player-input-value (mark)
  (or (current-session-value (player-name-key mark))
      ""))

(defun parse-player-mark (value)
  (cond
    ((string-equal value "x") :x)
    ((string-equal value "o") :o)))

(defun parse-opponent-mode (value)
  (cond
    ((string-equal value "easy") :easy)
    ((string-equal value "hard") :hard)
    ((or (string-equal value "normal")
         (string-equal value "computer"))
     :normal)
    (t :human)))

(defun session-first-player ()
  (let ((first-player (current-session-value :first-player)))
    (if (player-p first-player)
        first-player
        :x)))

(defun opponent-mode-p (object)
  (member object '(:human :easy :normal :hard)))

(defun session-opponent-mode ()
  (let ((mode (current-session-value :opponent-mode)))
    (cond
      ((opponent-mode-p mode) mode)
      ((current-session-value :computer-player) :normal)
      (t :human))))

(defun session-opponent-value ()
  (ecase (session-opponent-mode)
    (:human "human")
    (:easy "easy")
    (:hard "hard")
    (:normal "normal")))

(defun session-computer-player ()
  (unless (eql :human (session-opponent-mode))
    :o))

(defun session-computer-label ()
  (ecase (session-opponent-mode)
    (:easy "Easy CPU")
    (:hard "Hard CPU")
    (:normal "Normal CPU")))

(defun remember-player-settings (player-x player-o first-player opponent)
  (setf (current-session-value :player-x-name)
        (clean-player-name player-x :x)
        (current-session-value :player-o-name)
        (clean-player-name player-o :o)
        (current-session-value :first-player)
        (or first-player (session-first-player))
        (current-session-value :opponent-mode)
        (parse-opponent-mode opponent)
        (current-session-value :computer-player)
        nil))

(defun header-in (name)
  (let ((headers (and *request-env*
                      (getf *request-env* :headers))))
    (when headers
      (or (gethash name headers)
          (gethash (string-downcase name) headers)))))

(defun htmx-request-p ()
  (string-equal "true" (header-in "hx-request")))

(defun parse-room-event-id (value)
  (when (and value
             (plusp (length value))
             (every #'digit-char-p value))
    (parse-integer value)))

(defun request-last-event-id (request-env)
  (let ((*request-env* request-env))
    (parse-room-event-id (header-in "last-event-id"))))

(defun form-parameter (params name)
  (cdr (assoc name params :test #'string=)))

(defun form-submitted-p (params &rest names)
  (some (lambda (name)
          (assoc name params :test #'string=))
        names))

(defun csrf-parameter-valid-p (params)
  (csrf-token-valid-p (form-parameter params "csrf-token")))

(defmacro with-valid-csrf ((params) &body body)
  `(if (csrf-parameter-valid-p ,params)
       (progn ,@body)
       (reject-csrf-token)))

(defun route-parameter (params key)
  (cdr (assoc key params :test #'eql)))

(defun room-path (code)
  (format nil "/rooms/~A" code))

(defun room-game-path (code)
  (format nil "/rooms/~A/game" code))

(defun room-events-path (code)
  (format nil "/rooms/~A/events" code))

(defun room-seat-path (code mark)
  (format nil "/rooms/~A/seats/~A" code (string-downcase (player-label mark))))

(defun room-moves-path (code)
  (format nil "/rooms/~A/moves" code))

(defun request-room-code (params)
  (let ((code (route-parameter params :code)))
    (when code
      (string-upcase code))))

(defun parse-room-revision (value)
  (parse-index value))

(defun parse-index (value)
  (when value
    (handler-case
        (parse-integer value :junk-allowed nil)
      (error () nil))))
