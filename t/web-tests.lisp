;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.tests)

(in-suite :ultimate-tic-tac-toe)

(defstruct response
  status
  headers
  body)

(defun trim-crlf (line)
  (string-right-trim '(#\Return #\Linefeed) line))

(defun header-value (response name)
  (cdr (assoc name (response-headers response) :test #'string-equal)))

(defun header-alist-value (headers name)
  (cdr (assoc name headers :test #'string-equal)))

(defun response-cookie (response)
  (let ((set-cookie (header-value response "Set-Cookie")))
    (when set-cookie
      (subseq set-cookie 0 (position #\; set-cookie)))))

(defun response-csrf-token (response)
  (let* ((body (response-body response))
         (name-position (or (search "name=csrf-token" body)
                            (search "name=\"csrf-token\"" body)
                            (search "name='csrf-token'" body))))
    (when name-position
      (let ((value-position (search "value=" body :start2 name-position)))
        (when value-position
          (let* ((value-start (+ value-position (length "value=")))
                 (quote (and (< value-start (length body))
                             (find (char body value-start) "\"'"))))
            (when quote
              (incf value-start))
            (let ((value-end
                    (if quote
                        (position quote body :start value-start)
                        (position-if (lambda (char)
                                       (find char '(#\Space #\Tab #\Return
                                                    #\Linefeed #\>)))
                                     body
                                     :start value-start))))
              (subseq body value-start value-end))))))))

(defun csrf-body (token body)
  (format nil "csrf-token=~A~@[&~A~]" token body))

(defun wrong-csrf-token (token)
  (concatenate 'string
               (if (char= #\0 (char token 0)) "1" "0")
               (subseq token 1)))

(defun string-starts-with-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun count-substrings (needle string)
  (loop with count = 0
        with start = 0
        for position = (search needle string :start2 start)
        while position
        do (incf count)
           (setf start (+ position (length needle)))
        finally (return count)))

(defun render-fragment (game &key notice)
  (ultimate-tic-tac-toe.web::render-game-fragment game :notice notice))

(defun status-code (status-line)
  (parse-integer status-line
                 :start (1+ (position #\Space status-line))
                 :junk-allowed t))

(defun read-nonempty-line (stream)
  (loop for line = (read-line stream nil nil)
        while line
        for trimmed = (trim-crlf line)
        unless (zerop (length trimmed))
          return trimmed))

(defun decode-chunked-body (body)
  (with-input-from-string (input body)
    (with-output-to-string (output)
      (loop
        for size-text = (read-nonempty-line input)
        while size-text
        for extension = (position #\; size-text)
        for chunk-size = (parse-integer size-text
                                        :end extension
                                        :radix 16
                                        :junk-allowed nil)
        until (zerop chunk-size)
        do (loop repeat chunk-size
                 for char = (read-char input nil nil)
                 while char
                 do (write-char char output))
           (read-line input nil nil)))))

(defun chunked-body-p (body)
  (let ((line-end (position #\Linefeed body)))
    (when line-end
      (let* ((size-line (trim-crlf (subseq body 0 line-end)))
             (extension (position #\; size-line)))
        (and (plusp (length size-line))
             (handler-case
                 (progn
                   (parse-integer size-line
                                  :end extension
                                  :radix 16
                                  :junk-allowed nil)
                   t)
               (error () nil)))))))

(defun response-body-from-wire (headers raw-body)
  (if (or (string-equal "chunked"
                        (header-alist-value headers "Transfer-Encoding"))
          (chunked-body-p raw-body))
      (decode-chunked-body raw-body)
      raw-body))

(defun read-http-response (stream)
  (let ((status-line (read-nonempty-line stream))
        (headers nil))
    (unless status-line
      (error "HTTP response did not include a status line."))
    (loop
      for line = (trim-crlf (read-line stream))
      until (zerop (length line))
      for separator = (position #\: line)
      when separator
        do (push (cons (subseq line 0 separator)
                       (string-left-trim '(#\Space #\Tab)
                                         (subseq line (1+ separator))))
                 headers))
    (let* ((ordered-headers (nreverse headers))
           (raw-body
             (with-output-to-string (body)
               (loop for char = (read-char stream nil nil)
                     while char
                     do (write-char char body)))))
      (make-response
       :status (status-code status-line)
       :headers ordered-headers
       :body (response-body-from-wire ordered-headers raw-body)))))

(defun http-request (port method path &key body cookie headers)
  (let* ((payload (or body ""))
         (socket (usocket:socket-connect "127.0.0.1" port
                                         :element-type 'character
                                         :timeout 2)))
    (unwind-protect
         (let ((stream (usocket:socket-stream socket)))
           (format stream "~A ~A HTTP/1.1~C~C" method path #\Return #\Linefeed)
           (format stream "Host: 127.0.0.1:~D~C~C" port #\Return #\Linefeed)
           (format stream "User-Agent: ultimate-tic-tac-toe-tests~C~C" #\Return #\Linefeed)
           (format stream "Connection: close~C~C" #\Return #\Linefeed)
           (when cookie
             (format stream "Cookie: ~A~C~C" cookie #\Return #\Linefeed))
           (loop for (name . value) in headers
                 do (format stream "~A: ~A~C~C" name value #\Return #\Linefeed))
           (when body
             (format stream "Content-Type: application/x-www-form-urlencoded~C~C"
                     #\Return #\Linefeed)
             (format stream "Content-Length: ~D~C~C"
                     (length payload) #\Return #\Linefeed))
           (format stream "~C~C~A" #\Return #\Linefeed payload)
           (finish-output stream)
           (read-http-response stream))
      (usocket:socket-close socket))))

(defvar *test-server-port* nil)

(defun wait-for-test-server (port)
  (loop repeat 40
        do (handler-case
               (let ((socket (usocket:socket-connect "127.0.0.1" port
                                                      :element-type 'character
                                                      :timeout 1)))
                 (usocket:socket-close socket)
                 (return t))
             (error ()
               (sleep 0.025)))
        finally (error "Test server on port ~D did not become ready." port)))

(defun start-test-server ()
  (or *test-server-port*
      (setf *test-server-port*
            (loop repeat 20
                  for port = (+ 44000 (random 1000))
                  do (handler-case
                         (progn
                           (ultimate-tic-tac-toe.web:start :port port
                                                           :server :hunchentoot
                                                           :silent t)
                           (wait-for-test-server port)
                           (return port))
                       (usocket:address-in-use-error () nil))
                  finally (error "Could not find a free test port.")))))

(defmacro with-test-server ((port) &body body)
  `(let ((,port (start-test-server)))
     ,@body))

(defun concurrent-http-requests (&rest thunks)
  (let ((results (make-array (length thunks)))
        (start-p nil))
    (let ((threads
            (loop for thunk in thunks
                  for index from 0
                  collect (let ((thread-thunk thunk)
                                (thread-index index))
                            (bordeaux-threads:make-thread
                             (lambda ()
                               (loop until start-p
                                     do (sleep 0.001))
                               (setf (aref results thread-index)
                                     (funcall thread-thunk))))))))
      (setf start-p t)
      (dolist (thread threads)
        (bordeaux-threads:join-thread thread))
      (coerce results 'list))))

(defun assert-security-headers (response)
  (is (string= "nosniff"
               (or (header-value response "X-Content-Type-Options") "")))
  (is (string= "DENY"
               (or (header-value response "X-Frame-Options") "")))
  (is (string= "same-origin"
               (or (header-value response "Referrer-Policy") "")))
  (is (search "camera=()"
              (or (header-value response "Permissions-Policy") "")))
  (let ((policy (or (header-value response "Content-Security-Policy") "")))
    (is (search "default-src 'self'" policy))
    (is (search "script-src 'self'" policy))
    (is (search "style-src 'self'" policy))
    (is (search "frame-ancestors 'none'" policy))))

(test new-game-fragment-renders-all-choices
  (let ((html (render-fragment (make-game))))
    (is (search "X to move" html))
    (is (search "Any open board" html))
    (is (search "game-shell is-any-board" html))
    (is (= 81 (count-substrings "is-playable" html)))
    (is (= 9 (count-substrings "is-choice" html)))
    (is (= 0 (count-substrings "is-active" html)))))

(test active-board-fragment-renders-target
  (let ((game (make-game)))
    (accept-move game 0 4)
    (let ((html (render-fragment game)))
      (is (search "O to move" html))
      (is (search "Center board" html))
      (is (not (search "game-shell is-any-board" html)))
      (is (= 9 (count-substrings "is-playable" html)))
      (is (= 1 (count-substrings "is-active" html)))
      (is (= 0 (count-substrings "is-choice" html))))))

(test won-game-fragment-renders-global-state
  (let ((game (make-game)))
    (setf (aref (game-board-outcomes game) 0) :x
          (aref (game-board-outcomes game) 1) :x
          (aref (game-cells game) 2 0) :x
          (aref (game-cells game) 2 1) :x
          (game-active-board game) nil
          (game-next-player game) :x)
    (accept-move game 2 2)
    (let ((html (render-fragment game)))
      (is (search "X wins" html))
      (is (search "Target</span><strong>Done" html))
      (is (search "turn-card is-x is-result" html))
      (is (search "is-over" html))
      (is (= 3 (count-substrings "is-global-win-board" html)))
      (is (= 14 (count-substrings "confetti-piece" html))))))

(test move-rejections-map-to-notices
  (let ((game (make-game)))
    (is (string= "That move was not understood."
                 (ultimate-tic-tac-toe.web::move-rejection-notice
                  (reject-move :invalid-board game -1 0)))))
  (let ((game (make-game)))
    (accept-move game 0 0)
    (is (string= "That square is no longer available."
                 (ultimate-tic-tac-toe.web::move-rejection-notice
                  (reject-move :occupied-cell game 0 0)))))
  (let ((game (make-game)))
    (accept-move game 0 4)
    (is (string= "That move belongs in the target board."
                 (ultimate-tic-tac-toe.web::move-rejection-notice
                  (reject-move :wrong-board game 0 1)))))
  (let ((game (make-game)))
    (setf (aref (game-board-outcomes game) 4) :draw)
    (is (string= "That board is already complete."
                 (ultimate-tic-tac-toe.web::move-rejection-notice
                  (reject-move :closed-board game 4 0)))))
  (let ((game (make-game)))
    (setf (game-winner game) :x)
    (is (string= "The game is already over."
                 (ultimate-tic-tac-toe.web::move-rejection-notice
                  (reject-move :game-over game 0 0))))))

(test home-renders-full-page-without-session-urls
  (with-test-server (port)
    (let ((response (http-request port "GET" "/")))
      (is (= 200 (response-status response)))
      (is (string-starts-with-p "<!doctype html>" (response-body response)))
      (is (search "id=game" (response-body response)))
      (is (response-csrf-token response))
      (is (search "Start a new game" (response-body response)))
      (is (search "aria-live=polite" (response-body response)))
      (is (search "src=\"/htmx.min.js\"" (response-body response)))
      (is (search "src=\"/app.js\"" (response-body response)))
      (is (search "name=htmx-config" (response-body response)))
      (is (search "site-footer" (response-body response)))
      (is (search "id=site-footer" (response-body response)))
      (is (search "Source code" (response-body response)))
      (is (search (ultimate-tic-tac-toe.web::source-code-url)
                  (response-body response)))
      (is (search "License" (response-body response)))
      (is (search "href=\"/legal\"" (response-body response)))
      (is (not (search "cdn.jsdelivr" (response-body response))))
      (is (not (search "unpkg" (response-body response))))
      (assert-security-headers response)
      (is (not (search "hunchentoot-session" (response-body response)))))))

(test operational-routes-render-status-without-sessions
  (with-test-server (port)
    (let ((health (http-request port "GET" "/health"))
          (version (http-request port "GET" "/version")))
      (is (= 200 (response-status health)))
      (is (string= (format nil "ok~%")
                   (response-body health)))
      (is (string= "text/plain; charset=utf-8"
                   (header-value health "Content-Type")))
      (is (string= "no-store"
                   (header-value health "Cache-Control")))
      (is (not (header-value health "Set-Cookie")))
      (assert-security-headers health)
      (is (= 200 (response-status version)))
      (is (string= "text/plain; charset=utf-8"
                   (header-value version "Content-Type")))
      (is (search "ultimate-tic-tac-toe"
                  (response-body version)))
      (is (search (ultimate-tic-tac-toe.web::app-version)
                  (response-body version)))
      (is (not (search "<!doctype html>" (response-body version))))
      (is (not (header-value version "Set-Cookie")))
      (assert-security-headers version))))

(test legal-notices-page-renders-source-license-and-warranty
  (with-test-server (port)
    (let ((response (http-request port "GET" "/legal")))
      (is (= 200 (response-status response)))
      (is (string-starts-with-p "<!doctype html>" (response-body response)))
      (is (search "Legal Notices" (response-body response)))
      (is (search "Copyright (C) Contributors" (response-body response)))
      (is (search "GNU Affero General Public License" (response-body response)))
      (is (search "without warranty" (response-body response)))
      (is (search (ultimate-tic-tac-toe.web::source-code-url)
                  (response-body response)))
      (is (search "rel=license" (response-body response)))
      (is (search "Back to game" (response-body response))))))

(test responses-include-default-security-headers
  (with-test-server (port)
    (dolist (path '("/" "/legal" "/health" "/style.css" "/missing"))
      (assert-security-headers (http-request port "GET" path)))))

(test static-assets-are-served
  (with-test-server (port)
    (let ((responses
            (concurrent-http-requests
             (lambda () (http-request port "GET" "/style.css"))
             (lambda () (http-request port "GET" "/htmx.min.js"))
             (lambda () (http-request port "GET" "/app.js"))
             (lambda () (http-request port "GET" "/icon.svg"))
             (lambda () (http-request port "GET" "/x.svg"))
             (lambda () (http-request port "GET" "/o.svg")))))
      (is (= 6 (count-if (lambda (response)
                           (= 200 (response-status response)))
                         responses)))
      (is (find "text/css; charset=utf-8"
                responses
                :key (lambda (response)
                       (header-value response "Content-Type"))
                :test #'string=))
      (is (= 2 (count-if (lambda (response)
                           (string= "application/javascript; charset=utf-8"
                                    (header-value response "Content-Type")))
                         responses)))
      (is (= 3 (count-if (lambda (response)
                           (string= "image/svg+xml"
                                    (header-value response "Content-Type")))
                         responses))))))

(test htmx-move-returns-fragment
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (move (http-request port "POST" "/games/current/moves"
                               :cookie cookie
                               :body (csrf-body token "board=0&cell=0")
                               :headers '(("HX-Request" . "true")))))
      (is (not (null cookie)))
      (is (not (null token)))
      (is (= 200 (response-status move)))
      (is (string-starts-with-p "<section" (response-body move)))
      (is (search "id=game" (response-body move)))
      (is (search "O to move" (response-body move)))
      (is (search "player-strip" (response-body move)))
      (is (not (search "players-form" (response-body move))))
      (is (search "site-footer" (response-body move)))
      (is (search "hx-swap-oob" (response-body move)))
      (is (search "Source code" (response-body move)))
      (is (search "href=\"/legal\"" (response-body move)))
      (is (not (search "<!doctype html>" (response-body move))))
      (is (not (search "hunchentoot-session" (response-body move)))))))

(test player-settings-name-players-and-first-turn
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (settings (http-request port "POST" "/games"
                                   :cookie cookie
                                   :body (csrf-body token "player-x=Ada&player-o=Bea&first-player=o")
                                   :headers '(("HX-Request" . "true"))))
           (move (http-request port "POST" "/games/current/moves"
                               :cookie cookie
                               :body (csrf-body token "board=0&cell=0")
                               :headers '(("HX-Request" . "true")))))
      (is (= 200 (response-status settings)))
      (is (search "Bea to move" (response-body settings)))
      (is (search "value=Ada" (response-body settings)))
      (is (search "value=Bea" (response-body settings)))
      (is (= 200 (response-status move)))
      (is (search "player-strip" (response-body move)))
      (is (not (search "players-form" (response-body move))))
      (is (search "Ada to move" (response-body move))))))

(test normal-computer-opponent-replies-with-tactical-move
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (settings (http-request port "POST" "/games"
                                   :cookie cookie
                                   :body (csrf-body token "player-x=Ada&player-o=CPU&first-player=x&opponent=normal")
                                   :headers '(("HX-Request" . "true"))))
           (move (http-request port "POST" "/games/current/moves"
                               :cookie cookie
                               :body (csrf-body token "board=0&cell=0")
                               :headers '(("HX-Request" . "true")))))
      (is (= 200 (response-status settings)))
      (is (search "Ada to move" (response-body settings)))
      (is (search "name=opponent" (response-body settings)))
      (is (= 200 (response-status move)))
      (is (search "Ada to move" (response-body move)))
      (is (search "Center board" (response-body move)))
      (is (= 1 (count-substrings "mark mark-x" (response-body move))))
      (is (= 1 (count-substrings "mark mark-o" (response-body move))))
      (is (search "Normal CPU" (response-body move))))))

(test easy-computer-opponent-replies-with-first-legal-move
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (settings (http-request port "POST" "/games"
                                   :cookie cookie
                                   :body (csrf-body token "player-x=Ada&player-o=CPU&first-player=x&opponent=easy")
                                   :headers '(("HX-Request" . "true"))))
           (move (http-request port "POST" "/games/current/moves"
                               :cookie cookie
                               :body (csrf-body token "board=0&cell=0")
                               :headers '(("HX-Request" . "true")))))
      (is (= 200 (response-status settings)))
      (is (search "Ada to move" (response-body settings)))
      (is (= 200 (response-status move)))
      (is (search "Ada to move" (response-body move)))
      (is (search "Top board" (response-body move)))
      (is (= 1 (count-substrings "mark mark-x" (response-body move))))
      (is (= 1 (count-substrings "mark mark-o" (response-body move))))
      (is (search "Easy CPU" (response-body move))))))

(test normal-computer-opponent-can-start
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (settings (http-request port "POST" "/games"
                                   :cookie cookie
                                   :body (csrf-body token "player-x=Ada&player-o=CPU&first-player=o&opponent=normal")
                                   :headers '(("HX-Request" . "true")))))
      (is (= 200 (response-status settings)))
      (is (search "Ada to move" (response-body settings)))
      (is (search "Center board" (response-body settings)))
      (is (search "player-strip" (response-body settings)))
      (is (not (search "players-form" (response-body settings))))
      (is (= 0 (count-substrings "mark mark-x" (response-body settings))))
      (is (= 1 (count-substrings "mark mark-o" (response-body settings))))
      (is (search "Normal CPU" (response-body settings))))))

(test hard-computer-opponent-can-start
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (settings (http-request port "POST" "/games"
                                   :cookie cookie
                                   :body (csrf-body token "player-x=Ada&player-o=CPU&first-player=o&opponent=hard")
                                   :headers '(("HX-Request" . "true")))))
      (is (= 200 (response-status settings)))
      (is (search "Ada to move" (response-body settings)))
      (is (search "Center board" (response-body settings)))
      (is (search "player-strip" (response-body settings)))
      (is (not (search "players-form" (response-body settings))))
      (is (= 0 (count-substrings "mark mark-x" (response-body settings))))
      (is (= 1 (count-substrings "mark mark-o" (response-body settings))))
      (is (search "Hard CPU" (response-body settings))))))

(test htmx-illegal-move-returns-fragment-with-notice
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (first-move (http-request port "POST" "/games/current/moves"
                                     :cookie cookie
                                     :body (csrf-body token "board=0&cell=0")
                                     :headers '(("HX-Request" . "true"))))
           (second-move (http-request port "POST" "/games/current/moves"
                                      :cookie cookie
                                      :body (csrf-body token "board=0&cell=0")
                                      :headers '(("HX-Request" . "true")))))
      (is (= 200 (response-status first-move)))
      (is (= 200 (response-status second-move)))
      (is (string-starts-with-p "<section" (response-body second-move)))
      (is (search "id=game" (response-body second-move)))
      (is (search "That square is no longer available."
                  (response-body second-move)))
      (is (search "O to move" (response-body second-move)))
      (is (not (search "<!doctype html>" (response-body second-move)))))))

(test concurrent-duplicate-move-is-serialized
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (responses
             (concurrent-http-requests
              (lambda ()
                (http-request port "POST" "/games/current/moves"
                              :cookie cookie
                              :body (csrf-body token "board=0&cell=0")
                              :headers '(("HX-Request" . "true"))))
              (lambda ()
                (http-request port "POST" "/games/current/moves"
                              :cookie cookie
                              :body (csrf-body token "board=0&cell=0")
                              :headers '(("HX-Request" . "true"))))))
           (follow (http-request port "GET" "/" :cookie cookie)))
      (is (not (null cookie)))
      (is (= 2 (count-if (lambda (response)
                           (= 200 (response-status response)))
                         responses)))
      (is (= 1 (count-if (lambda (response)
                           (search "That square is no longer available."
                                   (response-body response)))
                         responses)))
      (is (= 2 (count-if (lambda (response)
                           (search "O to move" (response-body response)))
                         responses)))
      (is (search "O to move" (response-body follow)))
      (is (= 1 (count-substrings "mark mark-x"
                                 (response-body follow)))))))

(test post-routes-reject-missing-csrf-token
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (missing-move (http-request port "POST" "/games/current/moves"
                                       :cookie cookie
                                       :body "board=0&cell=0"
                                       :headers '(("HX-Request" . "true"))))
           (after-missing-move (http-request port "GET" "/" :cookie cookie))
           (wrong-move (http-request port "POST" "/games/current/moves"
                                     :cookie cookie
                                     :body (csrf-body (wrong-csrf-token token)
                                                      "board=0&cell=0")
                                     :headers '(("HX-Request" . "true"))))
           (after-wrong-move (http-request port "GET" "/" :cookie cookie))
           (valid-move (http-request port "POST" "/games/current/moves"
                                     :cookie cookie
                                     :body (csrf-body token "board=0&cell=0")
                                     :headers '(("HX-Request" . "true"))))
           (missing-reset (http-request port "POST" "/games"
                                        :cookie cookie
                                        :body ""
                                        :headers '(("HX-Request" . "true"))))
           (missing-players (http-request port "POST" "/games"
                                          :cookie cookie
                                          :body "player-x=Ada&player-o=Bea&first-player=o"
                                          :headers '(("HX-Request" . "true"))))
           (follow (http-request port "GET" "/" :cookie cookie)))
      (is (not (null token)))
      (is (= 403 (response-status missing-move)))
      (is (search "The form token was not valid." (response-body missing-move)))
      (is (search "X to move" (response-body after-missing-move)))
      (is (= 403 (response-status wrong-move)))
      (is (search "The form token was not valid." (response-body wrong-move)))
      (is (search "X to move" (response-body after-wrong-move)))
      (is (= 200 (response-status valid-move)))
      (is (= 403 (response-status missing-reset)))
      (is (= 403 (response-status missing-players)))
      (is (search "O to move" (response-body follow)))
      (is (not (search "value=Ada" (response-body follow)))))))

(test plain-move-post-redirects-to-full-page
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (move (http-request port "POST" "/games/current/moves"
                               :cookie cookie
                               :body (csrf-body token "board=0&cell=0")))
           (follow (http-request port "GET" "/" :cookie cookie)))
      (is (not (null cookie)))
      (is (not (null token)))
      (is (= 303 (response-status move)))
      (is (header-value move "Location"))
      (is (not (search "hunchentoot-session" (header-value move "Location"))))
      (is (= 200 (response-status follow)))
      (is (string-starts-with-p "<!doctype html>" (response-body follow)))
      (is (search "O to move" (response-body follow))))))

(test plain-invalid-move-flashes-notice-on-redirect
  (with-test-server (port)
    (let* ((home (http-request port "GET" "/"))
           (cookie (response-cookie home))
           (token (response-csrf-token home))
           (move (http-request port "POST" "/games/current/moves"
                               :cookie cookie
                               :body (csrf-body token "board=nope&cell=0")))
           (follow (http-request port "GET" "/" :cookie cookie))
           (again (http-request port "GET" "/" :cookie cookie)))
      (is (= 303 (response-status move)))
      (is (search "role=status" (response-body follow)))
      (is (search "That move was not understood." (response-body follow)))
      (is (not (search "That move was not understood." (response-body again)))))))
